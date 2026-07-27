"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function cleanText(value: FormDataEntryValue | null, maxLength: number) {
  return String(value ?? "").trim().slice(0, maxLength);
}

export async function submitDailyReflection(formData: FormData) {
  const supabase = await createClient({ allowMissingEnv: true });

  if (!supabase) {
    redirect("/today?error=Daily reflection is temporarily unavailable.");
  }

  const {
    data: { user }
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login?next=/today");
  }

  const dailyLightId = cleanText(formData.get("daily_light_id"), 80);
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
      updated_at: new Date().toISOString()
    },
    { onConflict: "daily_light_id,user_id" }
  );

  if (error) {
    redirect(`/today?error=${encodeURIComponent("Reflection could not be saved. Please try again.")}`);
  }

  revalidatePath("/today");
  revalidatePath("/journey");
  redirect("/today?reflected=1");
}

export { submitDailyReflection as submitDailyReflectionAction };