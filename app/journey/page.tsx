import Link from "next/link";
import { redirect } from "next/navigation";
import { getMyDailyReflectionHistory } from "@/lib/data/daily-lights";
import { getMyOfferings } from "@/lib/data/offerings";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

export default async function JourneyPage({ searchParams }: { searchParams?: SearchParams }) {
  const params = searchParams ? await searchParams : {};
  const supabase = await createClient({ allowMissingEnv: true });

  if (!supabase) redirect("/login?next=/journey");

  const {
    data: { user }
  } = await supabase.auth.getUser();

  if (!user) redirect("/login?next=/journey");

  const [offerings, reflections] = await Promise.all([
    getMyOfferings(24),
    getMyDailyReflectionHistory(user.id, 14)
  ]);

  const offeringCount = offerings.length;
  const reflectedCount = reflections.length;
  const peopleInspired = offerings.reduce((sum, item) => {
    return sum + Number(item.bless_count || 0) + Number(item.inspired_count || 0) + Number(item.carried_forward_count || 0);
  }, 0);

  return (
    <section className="mx-auto max-w-5xl px-4 py-12 sm:px-6 sm:py-16">
      {params.offering === "submitted" ? (
        <div className="mb-8 rounded-3xl border border-emerald-100 bg-emerald-50 p-5 text-sm font-extrabold text-emerald-900">
          Your Offering was submitted for review.
        </div>
      ) : null}

      <div className="deed-card p-6 sm:p-10">
        <p className="text-xs font-extrabold uppercase tracking-[0.32em] text-[#8D681D]">Goodness journey</p>
        <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold leading-tight sm:text-6xl">A new light can begin today.</h1>
        <p className="mt-4 max-w-2xl leading-8 text-[#5F5548]">Track your Offerings, reflections, and daily practice.</p>

        <div className="mt-8 grid gap-4 sm:grid-cols-3">
          <StatCard value={offeringCount} label="Offerings shared" />
          <StatCard value={reflectedCount} label="Daily reflections" />
          <StatCard value={peopleInspired} label="People inspired" />
        </div>

        <div className="mt-7 flex flex-col gap-3 sm:flex-row">
          <Link href="/offerings/new" className="focus-ring rounded-full bg-[#D9A441] px-6 py-3 text-center text-sm font-extrabold text-[#26231F] shadow-[0_12px_25px_rgba(217,164,65,0.30)]">
            Share an Offering
          </Link>
          <Link href="/today" className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-6 py-3 text-center text-sm font-extrabold text-[#26231F]">
            Reflect today
          </Link>
        </div>
      </div>

      <section className="mt-10">
        <p className="text-xs font-extrabold uppercase tracking-[0.32em] text-[#8D681D]">Daily reflections</p>
        <h2 className="mt-2 font-[var(--font-heading)] text-4xl font-semibold">Check-in history</h2>

        <div className="mt-5 space-y-4">
          {reflections.length ? (
            reflections.map((item) => (
              <article key={item.id} className="deed-card p-5">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="rounded-full bg-emerald-50 px-3 py-1 text-xs font-extrabold uppercase tracking-[0.16em] text-emerald-800">Completed</span>
                  <span className="text-xs font-bold text-[#7C715F]">{item.daily_light?.scheduled_date || new Date(item.created_at).toLocaleDateString()}</span>
                </div>

                <h3 className="mt-3 font-[var(--font-heading)] text-2xl font-semibold">{item.daily_light?.title || "Daily reflection"}</h3>
                {item.intention ? <p className="mt-2 text-sm font-bold text-[#5F5548]">Intention: {item.intention}</p> : null}
                {item.reflection ? <p className="mt-2 whitespace-pre-line text-sm leading-7 text-[#5F5548]">{item.reflection}</p> : null}
              </article>
            ))
          ) : (
            <div className="deed-card p-8 text-center">
              <h3 className="font-[var(--font-heading)] text-3xl font-semibold">No reflections yet.</h3>
              <p className="mt-2 text-[#5F5548]">Complete today’s check-in to begin your rhythm.</p>
            </div>
          )}
        </div>
      </section>

      <section className="mt-10">
        <p className="text-xs font-extrabold uppercase tracking-[0.32em] text-[#8D681D]">My Offerings</p>
        <h2 className="mt-2 font-[var(--font-heading)] text-4xl font-semibold">Review status</h2>

        <div className="mt-5 space-y-4">
          {offerings.length ? (
            offerings.map((item) => (
              <article key={item.id} className="deed-card p-5">
                <div className="flex flex-wrap gap-2">
                  <span className="rounded-full bg-[#FFF4DC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.16em] text-[#8D681D]">{item.status}</span>
                  <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.16em] text-[#8D681D]">{item.offering_type}</span>
                </div>
                <h3 className="mt-3 font-[var(--font-heading)] text-2xl font-semibold">{item.title}</h3>
              </article>
            ))
          ) : (
            <div className="deed-card p-8 text-center">
              <h3 className="font-[var(--font-heading)] text-3xl font-semibold">No Offerings yet.</h3>
            </div>
          )}
        </div>
      </section>
    </section>
  );
}

function StatCard({ value, label }: { value: number; label: string }) {
  return (
    <div className="rounded-3xl bg-[#FFF8EA] p-5">
      <p className="font-[var(--font-heading)] text-4xl font-semibold">{value}</p>
      <p className="mt-1 text-xs font-extrabold uppercase tracking-[0.22em] text-[#8D681D]">{label}</p>
    </div>
  );
}
