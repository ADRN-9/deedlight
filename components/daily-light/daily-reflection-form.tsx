import Link from "next/link";
import { submitDailyReflection } from "@/app/today/actions";

type DailyReflectionFormProps = {
  dailyLightId: string;
  hasReflected: boolean;
  isSignedIn: boolean;
  prompt?: string | null;
};

export function DailyReflectionForm({ dailyLightId, hasReflected, isSignedIn, prompt }: DailyReflectionFormProps) {
  if (!dailyLightId) return null;

  if (!isSignedIn) {
    return (
      <section className="deed-card p-6 text-center sm:p-8">
        <p className="text-xs font-extrabold uppercase tracking-[0.24em] text-[#8D681D]">Daily check-in</p>
        <h2 className="mt-3 font-[var(--font-heading)] text-3xl font-semibold">Reflect on today’s light.</h2>
        <p className="mx-auto mt-3 max-w-xl leading-7 text-[#5F5548]">Sign in to save your private reflection and grow your Goodness Journey.</p>
        <Link href="/login?next=/today" className="focus-ring mt-6 inline-flex rounded-full bg-[#D9A441] px-6 py-3 text-sm font-extrabold text-[#26231F] shadow-[0_12px_25px_rgba(217,164,65,0.30)]">
          Sign in to reflect
        </Link>
      </section>
    );
  }

  if (hasReflected) {
    return (
      <section className="rounded-[28px] border border-emerald-100 bg-emerald-50 p-6 text-emerald-950 shadow-[0_18px_45px_rgba(38,35,31,0.06)] sm:p-8">
        <p className="text-xs font-extrabold uppercase tracking-[0.24em] text-emerald-800">Reflection complete</p>
        <h2 className="mt-3 font-[var(--font-heading)] text-3xl font-semibold">You carried today’s light.</h2>
        <p className="mt-3 leading-7">A small moment of attention matters. Come back tomorrow for another Deedlight.</p>
      </section>
    );
  }

  return (
    <form action={submitDailyReflection} className="deed-card p-6 sm:p-8">
      <input type="hidden" name="daily_light_id" value={dailyLightId} />
      <p className="text-xs font-extrabold uppercase tracking-[0.24em] text-[#8D681D]">Daily check-in</p>
      <h2 className="mt-3 font-[var(--font-heading)] text-3xl font-semibold">Pause for one honest moment.</h2>

      <label className="mt-6 block">
        <span className="text-sm font-extrabold text-[#26231F]">{prompt || "What small good thing will you protect today?"}</span>
        <textarea name="reflection" rows={4} maxLength={500} className="mt-2 w-full rounded-3xl border border-[rgba(217,164,65,0.24)] bg-[#FFFDF7] p-4 text-sm outline-none focus:border-[#D9A441]" placeholder="Write a short private reflection..." />
      </label>

      <label className="mt-4 block">
        <span className="text-sm font-extrabold text-[#26231F]">One small intention</span>
        <input name="intention" maxLength={180} className="mt-2 w-full rounded-3xl border border-[rgba(217,164,65,0.24)] bg-[#FFFDF7] p-4 text-sm outline-none focus:border-[#D9A441]" placeholder="Example: I will speak gently today." />
      </label>

      <button type="submit" className="focus-ring mt-6 w-full rounded-full bg-[#D9A441] px-6 py-4 text-sm font-extrabold text-[#26231F] shadow-[0_12px_25px_rgba(217,164,65,0.30)] transition active:scale-[0.98]">
        Complete today’s reflection
      </button>
    </form>
  );
}
