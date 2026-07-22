import Link from "next/link";
import { signup } from "./actions";

export default async function SignupPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const params = await searchParams;
  return (
    <section className="mx-auto max-w-md px-4 py-16 sm:px-6">
      <div className="deed-card p-7 sm:p-9">
        <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Join Deedlight</p>
        <h1 className="mt-3 font-[var(--font-heading)] text-4xl font-semibold">Begin your journey</h1>
        <p className="mt-3 text-sm leading-6 text-[#7C715F]">A daily space for goodness, beauty, and better deeds.</p>
        {params.error ? <p className="mt-4 rounded-2xl bg-[#FFF4DC] p-3 text-sm font-semibold text-[#8D381D]">{params.error}</p> : null}
        <form action={signup} className="mt-7 space-y-4">
          <label className="block text-sm font-bold text-[#5F5548]">
            Display name
            <input className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" name="display_name" type="text" required />
          </label>
          <label className="block text-sm font-bold text-[#5F5548]">
            Email
            <input className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" name="email" type="email" required />
          </label>
          <label className="block text-sm font-bold text-[#5F5548]">
            Password
            <input className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" name="password" type="password" required minLength={8} />
          </label>
          <button className="focus-ring w-full rounded-full bg-[#D9A441] px-6 py-3 font-extrabold text-[#26231F] shadow-[0_10px_25px_rgba(217,164,65,0.30)]" type="submit">
            Begin My Journey
          </button>
        </form>
        <p className="mt-6 text-center text-sm text-[#7C715F]">
          Already have an account? <Link className="font-extrabold text-[#8D681D]" href="/login">Sign in</Link>
        </p>
      </div>
    </section>
  );
}
