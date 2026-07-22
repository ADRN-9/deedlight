import Link from "next/link";
import { login } from "./actions";

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const params = await searchParams;
  return (
    <section className="mx-auto max-w-md px-4 py-16 sm:px-6">
      <div className="deed-card p-7 sm:p-9">
        <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Welcome back</p>
        <h1 className="mt-3 font-[var(--font-heading)] text-4xl font-semibold">Sign in</h1>
        <p className="mt-3 text-sm leading-6 text-[#7C715F]">Return to your Goodness Journey.</p>
        {params.error ? <p className="mt-4 rounded-2xl bg-[#FFF4DC] p-3 text-sm font-semibold text-[#8D381D]">{params.error}</p> : null}
        <form action={login} className="mt-7 space-y-4">
          <label className="block text-sm font-bold text-[#5F5548]">
            Email
            <input className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" name="email" type="email" required />
          </label>
          <label className="block text-sm font-bold text-[#5F5548]">
            Password
            <input className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" name="password" type="password" required />
          </label>
          <button className="focus-ring w-full rounded-full bg-[#D9A441] px-6 py-3 font-extrabold text-[#26231F] shadow-[0_10px_25px_rgba(217,164,65,0.30)]" type="submit">
            Sign in
          </button>
        </form>
        <p className="mt-6 text-center text-sm text-[#7C715F]">
          New to Deedlight? <Link className="font-extrabold text-[#8D681D]" href="/signup">Create an account</Link>
        </p>
      </div>
    </section>
  );
}
