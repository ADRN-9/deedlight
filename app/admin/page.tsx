import Link from "next/link";
import { Flag, Newspaper, ShieldCheck, Sparkles } from "lucide-react";
import { requireAdmin } from "@/lib/auth/admin";

export default async function AdminPage() {
  await requireAdmin("/admin");

  const cards = [
    ["Daily Lights", "Create and schedule official daily reflections.", "/admin/daily-lights", <Sparkles key="daily" className="h-5 w-5" />],
    ["Offerings Review", "Edit, approve, reject, request edits, or hide member Offerings.", "/admin/offerings", <ShieldCheck key="offerings" className="h-5 w-5" />],
    ["Reports", "Review dignity, safety, privacy, and trust reports from members.", "/admin/reports", <Flag key="reports" className="h-5 w-5" />],
    ["Public Site", "Return to the public Offerings stream.", "/offerings", <Newspaper key="site" className="h-5 w-5" />]
  ] as const;

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Admin</p>
      <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">Deedlight control room</h1>
      <p className="mt-4 max-w-2xl leading-8 text-[#7C715F]">Keep the platform beautiful, safe, sincere, and dignified.</p>
      <div className="mt-8 grid gap-5 md:grid-cols-2">
        {cards.map(([title, body, href, icon]) => (
          <Link key={href} href={href} className="deed-card group p-6 transition hover:-translate-y-1">
            <div className="flex h-11 w-11 items-center justify-center rounded-full bg-[#FFF4DC] text-[#8D681D]">{icon}</div>
            <h2 className="mt-5 font-[var(--font-heading)] text-2xl font-semibold group-hover:text-[#8D681D]">{title}</h2>
            <p className="mt-3 leading-7 text-[#7C715F]">{body}</p>
          </Link>
        ))}
      </div>
    </section>
  );
}
