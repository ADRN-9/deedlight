import Link from "next/link";
import { AdminStatusMessage } from "@/components/admin/admin-status-message";
import { requireDatabaseAdmin } from "@/lib/auth/admin";
import {
  getCurrentWeeklyFeature,
  getWeeklyFeatureOptions,
} from "@/lib/data/weekly";
import { saveWeeklyFeatureAction } from "./actions";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default async function AdminWeeklyGoodnessPage({
  searchParams,
}: {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
}) {
  await requireDatabaseAdmin("/admin/weekly");

  const params = await searchParams;
  const [feature, offerings] = await Promise.all([
    getCurrentWeeklyFeature(),
    getWeeklyFeatureOptions(150),
  ]);

  return (
    <div className="mx-auto max-w-5xl px-5 py-12 md:py-16">
      {params?.updated ? (
        <div className="mb-7">
          <AdminStatusMessage type="success" title="Weekly feature saved">
            The public Weekly Goodness page now uses the updated Featured Light.
          </AdminStatusMessage>
        </div>
      ) : null}

      {params?.error ? (
        <div className="mb-7">
          <AdminStatusMessage type="error" title="Could not save">
            {String(params.error)}
          </AdminStatusMessage>
        </div>
      ) : null}

      <section className="rounded-[2.4rem] border border-amber-100 bg-white p-7 shadow-[0_30px_90px_rgba(42,32,16,0.08)] md:p-10">
        <p className="text-xs font-black uppercase tracking-[0.30em] text-amber-800">
          Weekly Goodness
        </p>
        <h1 className="mt-4 text-4xl font-black tracking-tight text-stone-950 md:text-5xl">
          Curate one Featured Light for the week.
        </h1>
        <p className="mt-4 max-w-3xl leading-8 text-stone-700">
          This is an editorial choice, not a leaderboard position. The public
          page still uses only approved Offering data and preserves anonymous
          attribution.
        </p>

        <div className="mt-7 flex flex-wrap gap-3">
          <Link
            href="/weekly"
            className="rounded-full border border-amber-200 bg-[#fff8ea] px-5 py-3 text-sm font-black text-stone-900 transition hover:bg-amber-100 active:scale-[0.98]"
          >
            View public Weekly Goodness
          </Link>
        </div>
      </section>

      <section className="mt-8 rounded-[2rem] border border-amber-100 bg-white p-6 md:p-8">
        <h2 className="text-2xl font-black text-stone-950">
          Current Featured Light
        </h2>

        {feature ? (
          <div className="mt-4 rounded-3xl bg-[#fff8ea] p-5">
            <p className="text-xs font-black uppercase tracking-[0.18em] text-amber-800">
              Week beginning {feature.week_start} UTC
            </p>
            <Link
              href={`/offerings/${feature.offering.id}`}
              className="mt-2 block text-xl font-black text-stone-950 hover:text-amber-800"
            >
              {feature.offering.title}
            </Link>
            <p className="mt-2 text-sm font-bold text-stone-600">
              {feature.offering.is_anonymous
                ? "Anonymous Light"
                : feature.offering.author_name || "Deedlight member"}
            </p>
          </div>
        ) : (
          <p className="mt-4 rounded-3xl bg-[#fff8ea] p-5 text-sm font-bold leading-7 text-stone-700">
            No Featured Light is selected for the current week.
          </p>
        )}
      </section>

      <section className="mt-8 rounded-[2rem] border border-amber-100 bg-white p-6 md:p-8">
        <h2 className="text-2xl font-black text-stone-950">
          Select an approved Offering
        </h2>
        <p className="mt-2 max-w-2xl text-sm leading-7 text-stone-600">
          Choose “No featured Offering” to clear the current week. Hidden,
          pending, or rejected Offerings are not available here.
        </p>

        <form action={saveWeeklyFeatureAction} className="mt-6">
          <label
            htmlFor="offering_id"
            className="text-sm font-black text-stone-800"
          >
            Featured Light
          </label>
          <select
            id="offering_id"
            name="offering_id"
            defaultValue={feature?.offering.id ?? "none"}
            className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm font-bold text-stone-900 outline-none focus:border-amber-500"
          >
            <option value="none">No featured Offering</option>
            {offerings.map((offering) => (
              <option key={offering.id} value={offering.id}>
                {offering.title} —{" "}
                {offering.is_anonymous
                  ? "Anonymous Light"
                  : offering.author_name || "Deedlight member"}
              </option>
            ))}
          </select>

          <button
            type="submit"
            className="mt-5 rounded-full bg-amber-400 px-6 py-3 text-sm font-black text-stone-950 shadow-lg shadow-amber-200 transition hover:bg-amber-500 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-60"
          >
            Save Featured Light
          </button>
        </form>
      </section>

      <section className="mt-8 rounded-[2rem] border border-stone-200 bg-stone-50 p-6 text-sm leading-7 text-stone-700">
        <p className="font-black text-stone-900">Privacy boundary</p>
        <p className="mt-2">
          Weekly Goodness reads public Offering content and seven-day aggregate
          reaction counts only. It does not query reflection text, Daily
          completions, Saved Lights, or reminder preferences.
        </p>
      </section>
    </div>
  );
}
