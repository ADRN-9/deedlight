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

  const { supabase } = await requireSignedIn(
    "/settings/reminders",
  );

  const { data, error } = await supabase.rpc(
    "set_daily_reminder_preference",
    {
      p_enabled: parsed.data.dailyEnabled,
      p_reminder_time: `${parsed.data.reminderTime}:00`,
      p_timezone: parsed.data.timezone,
    },
  );

  if (error) {
    console.error(
      "[updateReminderPreferenceAction] preference RPC failed",
      error,
    );

    const message =
      error.code === "42501" && parsed.data.dailyEnabled
        ? "While community access is suspended, reminders can be turned off but cannot be enabled."
        : error.code === "22023"
          ? "Your reminder time or timezone is no longer valid. Please review it and try again."
          : "Your reminder preference could not be saved. Please try again.";

    redirect(
      "/settings/reminders?error=" +
        encodeURIComponent(message),
    );
  }

  if (data !== parsed.data.dailyEnabled) {
    redirect(
      "/settings/reminders?error=" +
        encodeURIComponent(
          "Your reminder preference could not be verified.",
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
