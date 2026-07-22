import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { getMyOfferings } from "@/lib/data/offerings";

export default async function JourneyPage({ searchParams }: { searchParams: Promise<{ submitted?: string }> }) {
  const supabase = await createClient({ allowMissingEnv: true });
  const { data } = supabase ? await supabase.auth.getUser() : { data: { user: null } };
  const params = await searchParams;

  if (supabase && !data.user) {
    return (
      <section className="mx-auto max-w-xl px-4 py-16 text-center sm:px-6">
        <div className="deed-card p-8">
          <h1 className="font-[var(--font-heading)] text-4xl font-semibold">Please sign in to continue your Goodness Journey.</h1>
          <Link href="/login" className="mt-7 inline-flex rounded-full bg-[#D9A441] px-6 py-3 font-extrabold text-[#26231F]">Sign in</Link>
        </div>
      </section>
    );
  }

  const myOfferings = await getMyOfferings(12);
  const approvedCount = myOfferings.filter((item) => item.status === "approved").length;
  const pendingCount = myOfferings.filter((item) => item.status === "pending").length;
  const totalInspired = myOfferings.reduce((sum, item) => sum + (item.inspired_count || 0), 0);

  return (
    <section className="mx-auto max-w-5xl px-4 py-12 sm:px-6">
      {params.submitted ? (
        <div className="mb-6 rounded-3xl border border-[rgba(217,164,65,0.25)] bg-[#FFF4DC] p-5 font-bold text-[#5F5548]">
          Thank you. Your Offering is being reviewed so Deedlight remains safe, dignified, and sincere.
        </div>
      ) : null}
      <div className="deed-card p-8">
        <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Goodness Journey</p>
        <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">A new light can begin today.</h1>
        <p className="mt-4 max-w-2xl leading-8 text-[#7C715F]">
          Track the Offerings you have shared and whether they are waiting for review, approved, or need edits.
        </p>
        <div className="mt-8 grid gap-4 sm:grid-cols-3">
          <Stat label="Offerings Shared" value={String(myOfferings.length)} />
          <Stat label="Approved Lights" value={String(approvedCount)} />
          <Stat label="People Inspired" value={String(totalInspired)} />
        </div>
        <div className="mt-8 flex flex-wrap gap-3">
          <Link href="/offerings/new" className="focus-ring rounded-full bg-[#D9A441] px-6 py-3 text-sm font-extrabold text-[#26231F]">Share an Offering</Link>
          <Link href="/offerings" className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-6 py-3 text-sm font-extrabold text-[#26231F]">View Offerings</Link>
        </div>
      </div>

      <div className="mt-8">
        <div className="mb-4 flex items-end justify-between gap-3">
          <div>
            <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">My Offerings</p>
            <h2 className="mt-2 font-[var(--font-heading)] text-3xl font-semibold">Review status</h2>
          </div>
          {pendingCount ? <p className="text-sm font-bold text-[#7C715F]">{pendingCount} pending</p> : null}
        </div>

        {myOfferings.length === 0 ? (
          <div className="deed-card p-8 text-center">
            <h3 className="font-[var(--font-heading)] text-3xl font-semibold">Your first Offering can begin with one small deed.</h3>
            <p className="mx-auto mt-3 max-w-xl leading-8 text-[#7C715F]">Share goodness you practiced, witnessed, or invite others to try.</p>
          </div>
        ) : (
          <div className="grid gap-4">
            {myOfferings.map((offering) => (
              <article key={offering.id} className="deed-card p-5">
                <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                  <div>
                    <div className="mb-3 flex flex-wrap gap-2">
                      <span className="rounded-full bg-[#FFF4DC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">{offering.status.replace("_", " ")}</span>
                      <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">{formatOfferingType(offering.offering_type)}</span>
                    </div>
                    <h3 className="font-[var(--font-heading)] text-2xl font-semibold">{offering.title}</h3>
                    <p className="mt-2 line-clamp-2 text-sm leading-6 text-[#7C715F]">{offering.body}</p>
                    {offering.moderation_note ? <p className="mt-3 rounded-2xl bg-[#FFF4DC] p-3 text-sm font-semibold text-[#5F5548]">Admin note: {offering.moderation_note}</p> : null}
                  </div>
                  {offering.status === "approved" ? (
                    <Link href={`/offerings/${offering.id}`} className="focus-ring rounded-full bg-[#D9A441] px-5 py-3 text-center text-sm font-extrabold text-[#26231F]">Open</Link>
                  ) : (
                    <span className="rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-center text-sm font-extrabold text-[#5F5548]">{offering.status === "pending" ? "Waiting for review" : "Not public"}</span>
                  )}
                </div>
              </article>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-3xl bg-[#FFF8EA] p-5">
      <p className="font-[var(--font-heading)] text-4xl font-semibold">{value}</p>
      <p className="mt-1 text-xs font-extrabold uppercase tracking-[0.16em] text-[#8D681D]">{label}</p>
    </div>
  );
}

function formatOfferingType(value: string) {
  return value
    .split("_")
    .map((word) => word[0]?.toUpperCase() + word.slice(1))
    .join(" ");
}
