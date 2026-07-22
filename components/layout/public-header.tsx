import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { DeedlightLogo } from "@/components/brand/deedlight-logo";
import { SignOutButton } from "@/components/auth/sign-out-button";
import type { User } from "@supabase/supabase-js";

export async function PublicHeader() {
  let user: User | null = null;

  try {
    const supabase = await createClient({ allowMissingEnv: true });
    if (supabase) {
      const { data } = await supabase.auth.getUser();
      user = data.user;
    }
  } catch (error) {
    // Do not let auth/session refresh problems crash public pages.
    // The app can still render as logged out while we inspect runtime logs.
    console.error("PublicHeader auth check failed", error);
  }

  return (
    <header className="sticky top-0 z-40 border-b border-[rgba(217,164,65,0.14)] bg-[#FFF8EA]/85 backdrop-blur-xl">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4 sm:px-6">
        <Link href="/" className="focus-ring rounded-xl" aria-label="Deedlight home">
          <DeedlightLogo />
        </Link>
        <nav className="hidden items-center gap-7 text-sm font-semibold text-[#5F5548] md:flex">
          <Link className="hover:text-[#26231F]" href="/today">Today</Link>
          <Link className="hover:text-[#26231F]" href="/offerings">Offerings</Link>
          <Link className="hover:text-[#26231F]" href="/rising">Rising</Link>
          <Link className="hover:text-[#26231F]" href="/about">About</Link>
        </nav>
        <div className="flex items-center gap-3">
          {user ? (
            <>
              <Link className="hidden text-sm font-semibold text-[#5F5548] hover:text-[#26231F] sm:inline" href="/journey">
                Journey
              </Link>
              <SignOutButton />
            </>
          ) : (
            <>
              <Link className="hidden text-sm font-semibold text-[#5F5548] hover:text-[#26231F] sm:inline" href="/login">
                Sign in
              </Link>
              <Link
                href="/signup"
                className="focus-ring rounded-full bg-[#D9A441] px-4 py-2 text-sm font-bold text-[#26231F] shadow-[0_10px_25px_rgba(217,164,65,0.30)]"
              >
                Join
              </Link>
            </>
          )}
        </div>
      </div>
    </header>
  );
}
