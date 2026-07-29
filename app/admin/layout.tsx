import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import type { ReactNode } from "react";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function isAdminEmail(email?: string | null) {
  const adminEmails = (process.env.ADMIN_EMAILS ?? "")
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean);

  return Boolean(email && adminEmails.includes(email.toLowerCase()));
}

const adminLinks = [
  { href: "/admin", label: "Admin Home" },
  { href: "/admin/daily", label: "Daily Desk" },
  { href: "/admin/video-studio", label: "Video Studio" },
  { href: "/admin/offerings", label: "Offerings" },
  { href: "/admin/reports", label: "Reports" },
  { href: "/today", label: "View Today" },
];

export default async function AdminLayout({ children }: { children: ReactNode }) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login?next=/admin");
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("role,is_suspended,display_name")
    .eq("user_id", user.id)
    .maybeSingle();

  const isAdmin =
    (profile?.role === "admin" && profile?.is_suspended !== true) ||
    isAdminEmail(user.email);

  if (!isAdmin) {
    notFound();
  }

  return (
    <div>
      <section className="border-b border-amber-100 bg-[#fff8ea]/90 px-5 py-4 backdrop-blur">
        <div className="mx-auto flex max-w-6xl flex-col gap-4 md:flex-row md:items-center md:justify-between">
          <div>
            <p className="text-xs font-black uppercase tracking-[0.24em] text-amber-800">
              Admin workspace
            </p>
            <p className="mt-1 text-sm font-bold text-stone-700">
              {profile?.display_name || user.email || "Deedlight admin"}
            </p>
          </div>

          <nav className="flex gap-2 overflow-x-auto pb-1 md:flex-wrap md:justify-end md:overflow-visible md:pb-0">
            {adminLinks.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className="shrink-0 rounded-full border border-amber-200 bg-white px-4 py-2 text-xs font-black text-stone-900 transition hover:bg-amber-400 active:scale-[0.98]"
              >
                {item.label}
              </Link>
            ))}
          </nav>
        </div>
      </section>
      {children}
    </div>
  );
}
