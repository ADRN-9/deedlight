export type ReminderPreferenceInput = {
  dailyEnabled: boolean;
  reminderTime: string;
  timezone: string;
};

export type ReminderPreferenceResult =
  | { ok: true; data: ReminderPreferenceInput }
  | { ok: false; error: string };

const TIME_PATTERN = /^([01]\d|2[0-3]):([0-5]\d)$/;
const TIMEZONE_PATTERN = /^[A-Za-z0-9_+./-]{1,64}$/;

export function isValidTimeZone(value: string) {
  if (!TIMEZONE_PATTERN.test(value)) return false;

  try {
    new Intl.DateTimeFormat("en-US", {
      timeZone: value,
    }).format(new Date());

    return true;
  } catch {
    return false;
  }
}

export function parseReminderPreferenceForm(
  formData: FormData,
): ReminderPreferenceResult {
  const dailyEnabled = formData.get("daily_enabled") === "on";
  const reminderTime = String(
    formData.get("reminder_time") ?? "",
  ).trim();
  const timezone = String(formData.get("timezone") ?? "")
    .trim()
    .replace(/\s+/g, "");

  if (!TIME_PATTERN.test(reminderTime)) {
    return {
      ok: false,
      error: "Choose a valid reminder time.",
    };
  }

  if (!isValidTimeZone(timezone)) {
    return {
      ok: false,
      error:
        "Choose a valid timezone, such as Asia/Singapore, Europe/London, or UTC.",
    };
  }

  return {
    ok: true,
    data: {
      dailyEnabled,
      reminderTime,
      timezone,
    },
  };
}
