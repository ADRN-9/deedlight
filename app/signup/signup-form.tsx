"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";
import { createClient } from "@/lib/supabase/client";

function readableError(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  try {
    return JSON.stringify(error);
  } catch {
    return "Unknown error";
  }
}

function authErrorDetails(error: unknown) {
  const anyError = error as { message?: string; code?: string; status?: number; name?: string };
  const parts = [anyError?.message || readableError(error)];
  if (anyError?.code) parts.push(`code: ${anyError.code}`);
  if (anyError?.status) parts.push(`status: ${anyError.status}`);
  if (anyError?.name) parts.push(`name: ${anyError.name}`);
  return parts.filter(Boolean).join(" | ");
}

export function SignupForm() {
  const router = useRouter();
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
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
        console.error("Supabase signup returned error", signUpError);
        setError(authErrorDetails(signUpError));
        return;
      }

      if (data.session) {
        router.push("/today?joined=1");
        router.refresh();
        return;
      }

      if (data.user) {
        setMessage("Account created. Please check your email to confirm your account, then sign in. If email confirmation is disabled, use Sign in now.");
        return;
      }

      setMessage("Signup request completed. Please check your email, then sign in.");
    } catch (unknownError) {
      console.error("Signup threw exception", unknownError);
      setError(`Signup exception: ${readableError(unknownError)}`);
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
      {error ? <p className="mt-4 whitespace-pre-wrap rounded-2xl bg-[#FFF4DC] p-3 text-sm font-semibold text-[#8D381D]">{error}</p> : null}

      <form onSubmit={handleSubmit} className="mt-7 space-y-4">
        <label className="block text-sm font-bold text-[#5F5548]">
          Display name
          <input className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" name="display_name" type="text" autoComplete="name" required />
        </label>
        <label className="block text-sm font-bold text-[#5F5548]">
          Email
          <input className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" name="email" type="email" autoComplete="email" required />
        </label>
        <label className="block text-sm font-bold text-[#5F5548]">
          Password
          <input className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" name="password" type="password" autoComplete="new-password" required minLength={8} />
        </label>
        <button disabled={isSubmitting} className="focus-ring w-full rounded-full bg-[#D9A441] px-6 py-3 font-extrabold text-[#26231F] shadow-[0_10px_25px_rgba(217,164,65,0.30)] disabled:cursor-not-allowed disabled:opacity-60" type="submit">
          {isSubmitting ? "Creating account…" : "Begin My Journey"}
        </button>
      </form>

      <p className="mt-6 text-center text-sm text-[#7C715F]">
        Already have an account? <Link className="font-extrabold text-[#8D681D]" href="/login">Sign in</Link>
      </p>
      <p className="mt-3 text-center text-xs text-[#7C715F]">
        Debug: <Link className="font-bold text-[#8D681D]" href="/debug/auth">Auth check</Link>
      </p>
    </div>
  );
}
