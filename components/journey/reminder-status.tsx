import Link from "next/link";
import { getDailyReminderPreference } from "@/lib/data/reminders";

export async function ReminderStatus({
  userId,
}: {
  userId: string;
}) {
  const preference = await getDailyReminderPreference(userId);

  return (
    <section className="mt-10">
      <p className="text-xs font-extrabold uppercase tracking-[0.32em] text-[#8D681D]">
        Gentle reminder
      </p>

      <div className="deed-card mt-4 flex flex-col gap-4 p-6 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 className="font-[var(--font-heading)] text-3xl font-semibold">
            {preference.daily_enabled
              ? "Reminder preference is enabled."
              : "Reminder preference is off."}
          </h2>

          <p className="mt-2 text-sm leading-6 text-[#5F5548]">
            {preference.daily_enabled
              ? `${preference.reminder_time} · ${preference.timezone} · Delivery not active yet.`
              : "Choose a private local time whenever a reminder preference becomes useful to you."}
          </p>
        </div>

        <Link
          className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-6 py-3 text-center text-sm font-extrabold text-[#26231F]"
          href="/settings/reminders"
        >
          Reminder settings
        </Link>
      </div>
    </section>
  );
}
