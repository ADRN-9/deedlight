import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

function isAdminEmail(email?: string | null) {
  const adminEmails = (process.env.ADMIN_EMAILS ?? "")
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean);

  return Boolean(email && adminEmails.includes(email.toLowerCase()));
}

export async function AdminFloatingLink() {
  try {
    const supabase = await createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return null;
    }

    const { data: profile } = await supabase
      .from("profiles")
      .select("role,is_suspended")
      .eq("user_id", user.id)
      .maybeSingle();

    const isAdmin =
      (profile?.role === "admin" && profile?.is_suspended !== true) ||
      isAdminEmail(user.email);

    if (!isAdmin) {
      return null;
    }

    return (
      <Link
        href="/admin"
        className="fixed bottom-24 right-4 z-50 hidden rounded-full border border-amber-200 bg-stone-950 px-5 py-3 text-sm font-black text-white shadow-[0_20px_60px_rgba(42,32,16,0.22)] transition hover:-translate-y-0.5 hover:bg-amber-500 hover:text-stone-950 active:scale-[0.98] md:inline-flex"
      >
        Admin
      </Link>
    );
  } catch {
    return null;
  }
}
