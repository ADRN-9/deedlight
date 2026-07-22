import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

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
          This page will show your saved lights, Offerings, daily deeds, and badges. Sprint 1 creates the foundation; Sprint 2–3 will connect the live stats.
        </p>
        <div className="mt-8 grid gap-4 sm:grid-cols-3">
          <Stat label="Days of Goodness" value="0" />
          <Stat label="Offerings Shared" value="0" />
          <Stat label="People Inspired" value="0" />
        </div>
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
