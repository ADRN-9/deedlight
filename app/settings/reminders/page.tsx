import Link from "next/link";
import { redirect } from "next/navigation";
import { requireSignedIn } from "@/lib/auth/admin";
import { getDailyReminderPreference } from "@/lib/data/reminders";
import { ReminderSettingsForm } from "@/components/reminders/reminder-settings-form";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type SearchParams = Promise<
  Record<string, string | string[] | undefined>
>;

function firstValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

export default async function ReminderSettingsPage({
  searchParams,
}: {
  searchParams?: SearchParams;
}) {
  const params = searchParams ? await searchParams : {};
  const { supabase, user } = await requireSignedIn(
    "/settings/reminders",
  );

  const [{ data: profile, error: profileError }, preference] =
    await Promise.all([
      supabase
        .from("profiles")
        .select("is_suspended")
        .eq("user_id", user.id)
        .maybeSingle(),
      getDailyReminderPreference(user.id),
    ]);

  if (profileError) {
    redirect(
      "/journey?error=" +
        encodeURIComponent(
          "Reminder settings could not be verified.",
        ),
    );
  }

  const errorMessage = firstValue(params.error);
  const updatedState = firstValue(params.updated);

  return (
    <section className="mx-auto max-w-4xl px-4 py-12 sm:px-6 sm:py-16">
      <div className="deed-card p-6 sm:p-10">
        <p className="text-xs font-extrabold uppercase tracking-[0.3em] text-[#8D681D]">
          Gentle reminders
        </p>

        <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold leading-tight">
          Choose a quiet time to return.
        </h1>

        <p className="mt-4 max-w-2xl leading-8 text-[#5F5548]">
          Reminder preferences are optional, private, and designed
          without streak-loss pressure or guilt.
        </p>

        {updatedState === "enabled" ? (
          <div className="mt-6 rounded-3xl border border-emerald-100 bg-emerald-50 p-5 text-sm font-extrabold text-emerald-900">
            Reminder preference enabled. Delivery is not active yet.
          </div>
        ) : null}

        {updatedState === "disabled" ? (
          <div className="mt-6 rounded-3xl border border-emerald-100 bg-emerald-50 p-5 text-sm font-extrabold text-emerald-900">
            Reminder preference saved. The preference is off.
          </div>
        ) : null}

        {errorMessage ? (
          <div className="mt-6 rounded-3xl border border-amber-200 bg-[#FFF4DC] p-5 text-sm font-extrabold text-[#8D381D]">
            {errorMessage}
          </div>
        ) : null}

        <ReminderSettingsForm
          hasSavedPreference={preference.exists}
          initialEnabled={preference.daily_enabled}
          initialTime={preference.reminder_time}
          initialTimezone={preference.timezone}
          isSuspended={profile?.is_suspended === true}
        />

        <div className="mt-7">
          <Link
            className="focus-ring inline-flex rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-6 py-3 text-sm font-extrabold text-[#26231F]"
            href="/journey"
          >
            Back to Journey
          </Link>
        </div>
      </div>
    </section>
  );
}
