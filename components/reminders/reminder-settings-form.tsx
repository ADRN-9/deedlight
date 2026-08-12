"use client";

import { useEffect, useState } from "react";
import { updateReminderPreferenceAction } from "@/app/settings/reminders/actions";

type Props = {
  initialEnabled: boolean;
  initialTime: string;
  initialTimezone: string;
  hasSavedPreference: boolean;
  isSuspended: boolean;
};

const COMMON_TIMEZONES = [
  "UTC",
  "Asia/Singapore",
  "Asia/Kuala_Lumpur",
  "Asia/Dubai",
  "Asia/Kolkata",
  "Asia/Tokyo",
  "Australia/Sydney",
  "Europe/London",
  "Europe/Paris",
  "America/New_York",
  "America/Chicago",
  "America/Denver",
  "America/Los_Angeles",
];

export function ReminderSettingsForm({
  initialEnabled,
  initialTime,
  initialTimezone,
  hasSavedPreference,
  isSuspended,
}: Props) {
  const [enabled, setEnabled] = useState(initialEnabled);
  const [timezone, setTimezone] = useState(initialTimezone);

  useEffect(() => {
    if (hasSavedPreference) return;

    const detected =
      Intl.DateTimeFormat().resolvedOptions().timeZone;

    if (detected) {
      setTimezone(detected);
    }
  }, [hasSavedPreference]);

  const cannotEnable = isSuspended && !enabled;

  return (
    <form
      action={updateReminderPreferenceAction}
      className="mt-8 space-y-6"
    >
      <label
        className={`flex cursor-pointer items-start justify-between gap-4 rounded-3xl border p-5 transition-all ${
          enabled
            ? "border-[#D9A441] bg-[#FFF0C7] shadow-[0_12px_30px_rgba(217,164,65,0.16)]"
            : "border-[rgba(217,164,65,0.22)] bg-[#FFF8EA]"
        } ${cannotEnable ? "cursor-not-allowed opacity-70" : ""}`}
      >
        <span className="flex min-w-0 items-start gap-3">
          <input
            aria-describedby="daily-reminder-help"
            checked={enabled}
            className="mt-1 h-5 w-5 shrink-0 accent-[#D9A441]"
            disabled={cannotEnable}
            name="daily_enabled"
            onChange={(event) => setEnabled(event.target.checked)}
            type="checkbox"
          />
          <span>
            <span className="block font-extrabold text-[#26231F]">
              Enable daily reminder preference
            </span>
            <span
              className="mt-1 block text-sm leading-6 text-[#7C715F]"
              id="daily-reminder-help"
            >
              Off by default. This preference is private and is
              never shown on your profile.
            </span>
          </span>
        </span>

        <span
          aria-live="polite"
          className={`shrink-0 rounded-full px-3 py-1 text-xs font-extrabold uppercase tracking-[0.16em] ${
            enabled
              ? "bg-[#D9A441] text-[#26231F]"
              : "bg-white text-[#7C715F]"
          }`}
        >
          {enabled ? "Preference on" : "Preference off"}
        </span>
      </label>

      <div className="grid gap-5 sm:grid-cols-2">
        <label className="block text-sm font-bold text-[#5F5548]">
          Preferred local time
          <input
            className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]"
            defaultValue={initialTime}
            name="reminder_time"
            required
            type="time"
          />
        </label>

        <label className="block text-sm font-bold text-[#5F5548]">
          Timezone
          <input
            className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]"
            list="deedlight-timezones"
            maxLength={64}
            name="timezone"
            onChange={(event) => setTimezone(event.target.value)}
            required
            value={timezone}
          />
          <datalist id="deedlight-timezones">
            {COMMON_TIMEZONES.map((item) => (
              <option key={item} value={item} />
            ))}
          </datalist>
          <span className="mt-2 block text-xs leading-5 text-[#7C715F]">
            Your browser timezone is suggested automatically for
            new preferences.
          </span>
        </label>
      </div>

      {isSuspended ? (
        <div className="rounded-3xl border border-amber-200 bg-amber-50 p-5 text-sm leading-6 text-amber-950">
          While community access is suspended, an existing
          reminder preference may be turned off, but reminders
          cannot be enabled.
        </div>
      ) : null}

      <div className="rounded-3xl border border-[rgba(217,164,65,0.22)] bg-white p-5 text-sm leading-6 text-[#5F5548]">
        <strong className="text-[#26231F]">
          Delivery is not active yet.
        </strong>{" "}
        Sprint 10.3A stores your private opt-in preference and
        timezone. Email or push delivery will only be added after
        a dedicated transport and scheduling review.
      </div>

      <button
        className="focus-ring rounded-full bg-[#D9A441] px-7 py-3 text-sm font-extrabold text-[#26231F] shadow-[0_12px_25px_rgba(217,164,65,0.30)]"
        type="submit"
      >
        Save reminder preference
      </button>
    </form>
  );
}
