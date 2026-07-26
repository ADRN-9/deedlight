"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

function textValue(formData: FormData, key: string): string | null {
  const value = formData.get(key);
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export async function submitDailyReflectionAction(formData: FormData) {
  const supabase = await createClient();
  if (!supabase) {
    redirect("/login?error=Supabase%20is%20not%20configured");
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login?next=/today");
  }

  const dailyPostId = textValue(formData, "daily_post_id");
  const reflectionText = textValue(formData, "reflection_text");
  const moodLabel = textValue(formData, "mood_label");
  const didTodayDeed = formData.get("did_today_deed") === "yes";

  if (!dailyPostId || dailyPostId === "fallback-today") {
    redirect("/today?error=Today%E2%80%99s%20Deedlight%20is%20not%20saved%20yet");
  }

  if (!reflectionText && !didTodayDeed && !moodLabel) {
    redirect("/today?error=Please%20add%20a%20reflection%20or%20check%20in");
  }

  const { error } = await supabase.from("daily_reflections").upsert(
    {
      daily_post_id: dailyPostId,
      user_id: user.id,
      reflection_text: reflectionText,
      mood_label: moodLabel,
      did_today_deed: didTodayDeed,
      is_private: true,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id,daily_post_id" }
  );

  if (error) {
    redirect(`/today?error=${encodeURIComponent(error.message)}`);
  }

  revalidatePath("/today");
  redirect("/today?reflection=saved");
}
