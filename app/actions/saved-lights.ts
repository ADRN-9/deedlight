"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const RETURN_PATHS = new Set(["/today", "/journey"]);

function cleanText(value: FormDataEntryValue | null, maxLength: number) {
  return String(value ?? "").trim().slice(0, maxLength);
}

function cleanUuid(value: FormDataEntryValue | null) {
  const candidate = cleanText(value, 80);
  return UUID_PATTERN.test(candidate) ? candidate : "";
}

function cleanReturnTo(value: FormDataEntryValue | null) {
  const candidate = cleanText(value, 100);
  return RETURN_PATHS.has(candidate) ? candidate : "/today";
}

function redirectWithMessage(
  returnTo: string,
  key: "saved" | "error",
  value: string,
): never {
  redirect(`${returnTo}?${key}=${encodeURIComponent(value)}`);
}

async function requireSavedLightUser(returnTo: string) {
  const supabase = await createClient({ allowMissingEnv: true });

  if (!supabase) {
    redirectWithMessage(
      returnTo,
      "error",
      "Saved Lights are temporarily unavailable.",
    );
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect(`/login?next=${encodeURIComponent(returnTo)}`);
  }

  return { supabase, user };
}

export async function saveDailyLightAction(formData: FormData) {
  const returnTo = cleanReturnTo(formData.get("return_to"));
  const dailyLightId = cleanUuid(formData.get("daily_light_id"));
  const { supabase, user } = await requireSavedLightUser(returnTo);

  if (!dailyLightId) {
    redirectWithMessage(returnTo, "error", "This Daily Light could not be identified.");
  }

  const { data: light, error: lightError } = await supabase
    .from("daily_lights")
    .select("id")
    .eq("id", dailyLightId)
    .eq("status", "published")
    .maybeSingle();

  if (lightError || !light) {
    console.error("[saveDailyLightAction] Daily Light lookup failed", lightError);
    redirectWithMessage(
      returnTo,
      "error",
      "This Daily Light is not available to save.",
    );
  }

  const { error } = await supabase.from("saved_lights").insert({
    user_id: user.id,
    daily_light_id: dailyLightId,
  });

  if (error && error.code !== "23505") {
    console.error("[saveDailyLightAction] insert failed", error);
    redirectWithMessage(
      returnTo,
      "error",
      "This Daily Light could not be saved. Please try again.",
    );
  }

  revalidatePath("/today");
  revalidatePath("/journey");
  redirectWithMessage(returnTo, "saved", "1");
}

export async function unsaveDailyLightAction(formData: FormData) {
  const returnTo = cleanReturnTo(formData.get("return_to"));
  const dailyLightId = cleanUuid(formData.get("daily_light_id"));
  const { supabase, user } = await requireSavedLightUser(returnTo);

  if (!dailyLightId) {
    redirectWithMessage(returnTo, "error", "This Daily Light could not be identified.");
  }

  const { error } = await supabase
    .from("saved_lights")
    .delete()
    .eq("user_id", user.id)
    .eq("daily_light_id", dailyLightId);

  if (error) {
    console.error("[unsaveDailyLightAction] delete failed", error);
    redirectWithMessage(
      returnTo,
      "error",
      "This Daily Light could not be removed. Please try again.",
    );
  }

  revalidatePath("/today");
  revalidatePath("/journey");
  redirectWithMessage(returnTo, "saved", "0");
}
