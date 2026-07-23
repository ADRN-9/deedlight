"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type SignupFormProps = {
  initialError?: string;
  initialMessage?: string;
};

export function SignupForm({ initialError, initialMessage }: SignupFormProps) {
  const router = useRouter();
  const [error, setError] = useState(initialError || "");
  const [message, setMessage] = useState(initialMessage || "");
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setMessage("");
    setIsSubmitting(true);

    try {
      const formData = new FormData(event.currentTarget);
      const displayName = String(formData.get("display_name") || "").trim();
      const email = String(formData.get("email") || "").trim().toLowerCase();
      const password = String(formData.get("password") || "");

      if (!displayName || !email || !password) {
        setError("Please complete all fields.");
        return;
      }

      if (password.length < 8) {
        setError("Please use a password with at least 8 characters.");
        return;
      }

      const supabase = createClient();
      const emailRedirectTo = `${window.location.origin}/today`;
      const { data, error: signUpError } = await supabase.auth.signUp({
        email,
        password,
        options: {
          emailRedirectTo,
          data: {
            display_name: displayName
          }
        }
      });

      if (signUpError) {
        setError(signUpError.message);
        return;
      }

      if (data.session) {
        router.push("/today?joined=1");
        router.refresh();
        return;
      }

      router.push(
        `/login?message=${encodeURIComponent("Account created. Please check your email to confirm your account, then sign in.")}`
      );
    } catch (unknownError) {
      console.error("Signup failed", unknownError);
      setError("Signup could not be completed. Please try again, or sign in if this account already exists.");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="deed-card p-7 sm:p-9">
      <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Join Deedlight</p>
      <h1 className="mt-3 font-[var(--font-heading)] text-4xl font-semibold">Begin your journey</h1>
      <p className="mt-3 text-sm leading-6 text-[#7C715F]">A daily space for goodness, beauty, and better deeds.</p>

      {message ? <p className="mt-4 rounded-2xl bg-[#F4FBF1] p-3 text-sm font-semibold text-[#476642]">{message}</p> : null}
      {error ? <p className="mt-4 rounded-2xl bg-[#FFF4DC] p-3 text-sm font-semibold text-[#8D381D]">{error}</p> : null}

      <form onSubmit={handleSubmit} className="mt-7 space-y-4">
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
        <button disabled={isSubmitting} className="focus-ring w-full rounded-full bg-[#D9A441] px-6 py-3 font-extrabold text-[#26231F] shadow-[0_10px_25px_rgba(217,164,65,0.30)] disabled:cursor-not-allowed disabled:opacity-60" type="submit">
          {isSubmitting ? "Creating account…" : "Begin My Journey"}
        </button>
      </form>

      <p className="mt-6 text-center text-sm text-[#7C715F]">
        Already have an account? <Link className="font-extrabold text-[#8D681D]" href="/login">Sign in</Link>
      </p>
    </div>
  );
}
