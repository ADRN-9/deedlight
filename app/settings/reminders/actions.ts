"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireSignedIn } from "@/lib/auth/admin";
import { parseReminderPreferenceForm } from "@/lib/reminders/validation";

export async function updateReminderPreferenceAction(
  formData: FormData,
) {
  const parsed = parseReminderPreferenceForm(formData);

  if (!parsed.ok) {
    redirect(
      `/settings/reminders?error=${encodeURIComponent(parsed.error)}`,
    );
  }

  const { supabase, user } = await requireSignedIn(
    "/settings/reminders",
  );

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("is_suspended")
    .eq("user_id", user.id)
    .maybeSingle();

  if (profileError) {
    console.error(
      "[updateReminderPreferenceAction] profile lookup failed",
      profileError,
    );

    redirect(
      "/settings/reminders?error=" +
        encodeURIComponent(
          "Reminder settings could not be verified. Please try again.",
        ),
    );
  }

  if (
    profile?.is_suspended === true &&
    parsed.data.dailyEnabled
  ) {
    redirect(
      "/settings/reminders?error=" +
        encodeURIComponent(
          "While community access is suspended, reminders can be turned off but cannot be enabled.",
        ),
    );
  }

  const { error } = await supabase
    .from("daily_reminder_preferences")
    .upsert(
      {
        user_id: user.id,
        daily_enabled: parsed.data.dailyEnabled,
        reminder_time: `${parsed.data.reminderTime}:00`,
        timezone: parsed.data.timezone,
      },
      {
        onConflict: "user_id",
      },
    );

  if (error) {
    console.error(
      "[updateReminderPreferenceAction] upsert failed",
      error,
    );

    redirect(
      "/settings/reminders?error=" +
        encodeURIComponent(
          "Your reminder preference could not be saved. Please try again.",
        ),
    );
  }

  revalidatePath("/settings/reminders");
  revalidatePath("/journey");

  redirect(
    `/settings/reminders?updated=${
      parsed.data.dailyEnabled ? "enabled" : "disabled"
    }`,
  );
}
