"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function cleanText(value: FormDataEntryValue | null, maxLength: number) {
  return String(value ?? "").trim().slice(0, maxLength);
}

function cleanUuid(value: FormDataEntryValue | null) {
  const candidate = cleanText(value, 80);
  return UUID_PATTERN.test(candidate) ? candidate : "";
}

async function requireTodayUser() {
  const supabase = await createClient({ allowMissingEnv: true });

  if (!supabase) {
    redirect("/today?error=Today’s member tools are temporarily unavailable.");
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login?next=/today");
  }

  return { supabase, user };
}

export async function completeDailyDeedAction(formData: FormData) {
  const { supabase, user } = await requireTodayUser();
  const dailyLightId = cleanUuid(formData.get("daily_light_id"));

  if (!dailyLightId) {
    redirect("/today?error=Today’s light is not ready to be completed.");
  }

  const { data: light, error: lightError } = await supabase
    .from("daily_lights")
    .select("id")
    .eq("id", dailyLightId)
    .eq("status", "published")
    .maybeSingle();

  if (lightError || !light) {
    console.error("[completeDailyDeedAction] Daily Light lookup failed", lightError);
    redirect("/today?error=This Daily Light is not available for completion.");
  }

  const { error } = await supabase.from("daily_deed_completions").insert({
    user_id: user.id,
    daily_light_id: dailyLightId,
  });

  if (error && error.code !== "23505") {
    console.error("[completeDailyDeedAction] insert failed", error);
    redirect("/today?error=Your daily deed could not be saved. Please try again.");
  }

  revalidatePath("/today");
  revalidatePath("/journey");
  redirect("/today?deed=completed");
}

export async function undoDailyDeedAction(formData: FormData) {
  const { supabase, user } = await requireTodayUser();
  const dailyLightId = cleanUuid(formData.get("daily_light_id"));

  if (!dailyLightId) {
    redirect("/today?error=Today’s light could not be identified.");
  }

  const { error } = await supabase
    .from("daily_deed_completions")
    .delete()
    .eq("user_id", user.id)
    .eq("daily_light_id", dailyLightId);

  if (error) {
    console.error("[undoDailyDeedAction] delete failed", error);
    redirect("/today?error=Your daily deed could not be undone. Please try again.");
  }

  revalidatePath("/today");
  revalidatePath("/journey");
  redirect("/today?deed=undone");
}

export async function submitDailyReflection(formData: FormData) {
  const { supabase, user } = await requireTodayUser();

  const dailyLightId = cleanUuid(formData.get("daily_light_id"));
  const reflection = cleanText(formData.get("reflection"), 500);
  const intention = cleanText(formData.get("intention"), 180);

  if (!dailyLightId) {
    redirect("/today?error=Today’s light is not ready for reflection yet.");
  }

  if (!reflection && !intention) {
    redirect("/today?error=Write a short reflection or intention first.");
  }

  const { error } = await supabase.from("daily_reflections").upsert(
    {
      daily_light_id: dailyLightId,
      user_id: user.id,
      reflection,
      intention,
      is_private: true,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "daily_light_id,user_id" },
  );

  if (error) {
    console.error("[submitDailyReflection] upsert failed", error);
    redirect(
      `/today?error=${encodeURIComponent(
        "Reflection could not be saved. Please try again.",
      )}`,
    );
  }

  revalidatePath("/today");
  revalidatePath("/journey");
  redirect("/today?reflected=1");
}

export { submitDailyReflection as submitDailyReflectionAction };
