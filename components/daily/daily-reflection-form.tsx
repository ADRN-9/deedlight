"use client";

import { useFormStatus } from "react-dom";

import type { DailyPost, DailyReflection } from "@/lib/types-daily";
import { submitDailyReflectionAction } from "@/app/today/actions";

function SubmitButton() {
  const { pending } = useFormStatus();

  return (
    <button
      type="submit"
      disabled={pending}
      className="inline-flex min-h-12 items-center justify-center rounded-full bg-[#dfa93b] px-6 py-3 text-sm font-extrabold text-[#2a241c] shadow-[0_16px_38px_rgba(174,122,34,0.22)] transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-65"
    >
      {pending ? "Saving your check-in..." : "Save today’s check-in"}
    </button>
  );
}

type DailyReflectionFormProps = {
  post: DailyPost;
  reflection: DailyReflection | null;
  isSignedIn: boolean;
};

export function DailyReflectionForm({ post, reflection, isSignedIn }: DailyReflectionFormProps) {
  if (!isSignedIn) {
    return (
      <section className="rounded-[2rem] border border-[#efd9a8] bg-white p-8 shadow-[0_24px_80px_rgba(110,79,33,0.10)]">
        <p className="text-xs font-black uppercase tracking-[0.35em] text-[#8a641a]">Daily reflection</p>
        <h2 className="mt-3 text-3xl font-black text-[#2a241c]">Carry today’s light with you.</h2>
        <p className="mt-3 max-w-2xl text-[#756b5f]">
          Sign in to privately save one reflection or mark that you tried today’s small deed.
        </p>
        <a
          href="/login?next=/today"
          className="mt-6 inline-flex rounded-full bg-[#dfa93b] px-6 py-3 text-sm font-extrabold text-[#2a241c] shadow-[0_16px_38px_rgba(174,122,34,0.22)]"
        >
          Sign in to check in
        </a>
      </section>
    );
  }

  return (
    <section className="rounded-[2rem] border border-[#efd9a8] bg-white p-8 shadow-[0_24px_80px_rgba(110,79,33,0.10)]">
      <p className="text-xs font-black uppercase tracking-[0.35em] text-[#8a641a]">Daily reflection</p>
      <h2 className="mt-3 text-3xl font-black text-[#2a241c]">A private check-in for today.</h2>
      <p className="mt-3 text-[#756b5f]">
        {post.reflection_prompt ?? "What is one small way you can make today kinder?"}
      </p>

      <form action={submitDailyReflectionAction} className="mt-6 space-y-5">
        <input type="hidden" name="daily_post_id" value={post.id} />

        <label className="block">
          <span className="text-sm font-extrabold text-[#4b4034]">One sentence from your heart</span>
          <textarea
            name="reflection_text"
            defaultValue={reflection?.reflection_text ?? ""}
            rows={4}
            placeholder="Today I want to protect goodness by..."
            className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 text-[#2a241c] outline-none focus:border-[#dfa93b] focus:ring-4 focus:ring-[#f4d689]/40"
          />
        </label>

        <div className="grid gap-3 md:grid-cols-3">
          {[
            ["quiet", "Quiet but willing"],
            ["grateful", "Grateful"],
            ["brave", "A little braver"],
          ].map(([value, label]) => (
            <label
              key={value}
              className="flex cursor-pointer items-center gap-3 rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] px-4 py-3 text-sm font-bold text-[#4b4034]"
            >
              <input
                type="radio"
                name="mood_label"
                value={value}
                defaultChecked={reflection?.mood_label === value}
                className="accent-[#dfa93b]"
              />
              {label}
            </label>
          ))}
        </div>

        <label className="flex cursor-pointer items-center gap-3 rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] px-4 py-3 text-sm font-bold text-[#4b4034]">
          <input
            type="checkbox"
            name="did_today_deed"
            value="yes"
            defaultChecked={reflection?.did_today_deed ?? false}
            className="accent-[#dfa93b]"
          />
          I tried today’s small deed, or I made a sincere effort.
        </label>

        <div className="flex flex-wrap items-center gap-3">
          <SubmitButton />
          {reflection ? (
            <span className="rounded-full bg-[#eef7e9] px-4 py-2 text-xs font-black uppercase tracking-[0.16em] text-[#426534]">
              Saved before — update anytime
            </span>
          ) : null}
        </div>
      </form>
    </section>
  );
}
