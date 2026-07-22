"use client";

import { useTransition } from "react";
import { signOut } from "@/lib/auth/actions";

export function SignOutButton() {
  const [pending, startTransition] = useTransition();

  return (
    <button
      type="button"
      onClick={() => startTransition(() => signOut())}
      disabled={pending}
      className="focus-ring rounded-full border border-[rgba(217,164,65,0.35)] bg-white/70 px-4 py-2 text-sm font-bold text-[#5F5548] disabled:opacity-60"
    >
      {pending ? "Leaving…" : "Sign out"}
    </button>
  );
}
