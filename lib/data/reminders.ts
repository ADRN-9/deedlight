import { createClient } from "@/lib/supabase/server";

export type DailyReminderPreference = {
  exists: boolean;
  daily_enabled: boolean;
  reminder_time: string;
  timezone: string;
};

const DEFAULT_PREFERENCE: DailyReminderPreference = {
  exists: false,
  daily_enabled: false,
  reminder_time: "08:00",
  timezone: "UTC",
};

function normalizeTime(value: unknown) {
  const text = String(value ?? "").trim();

  if (/^\d{2}:\d{2}/.test(text)) {
    return text.slice(0, 5);
  }

  return DEFAULT_PREFERENCE.reminder_time;
}

export async function getDailyReminderPreference(
  userId: string,
): Promise<DailyReminderPreference> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("daily_reminder_preferences")
    .select("daily_enabled,reminder_time,timezone")
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    console.error(
      "[getDailyReminderPreference] query failed",
      error,
    );

    throw new Error("Reminder preferences are unavailable.");
  }

  if (!data) {
    return DEFAULT_PREFERENCE;
  }

  return {
    exists: true,
    daily_enabled: data.daily_enabled === true,
    reminder_time: normalizeTime(data.reminder_time),
    timezone:
      typeof data.timezone === "string" && data.timezone.trim()
        ? data.timezone.trim()
        : DEFAULT_PREFERENCE.timezone,
  };
}
