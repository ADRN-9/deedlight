import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export default async function AdminPage() {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) {
    return <AdminShell message="Supabase is not configured yet. Add .env.local values, then refresh." />;
  }

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login?next=/admin");

  const { data: profile } = await supabase
    .from("profiles")
    .select("role")
    .eq("user_id", user.id)
    .maybeSingle();

  if (profile?.role !== "admin") redirect("/today");

  return <AdminShell message="Sprint 1 admin shell ready. Sprint 2 adds Daily Lights editor and Sprint 5 adds review queues." />;
}

function AdminShell({ message }: { message: string }) {
  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Admin</p>
      <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">Deedlight control room</h1>
      <p className="mt-4 leading-8 text-[#7C715F]">{message}</p>
      <div className="mt-8 grid gap-5 md:grid-cols-3">
        {[
          ["Daily Lights", "Create and schedule official daily reflections."],
          ["Offerings Review", "Approve, reject, or request edits for user Offerings."],
          ["Reports", "Resolve dignity, safety, and trust reports."]
        ].map(([title, body]) => (
          <div key={title} className="deed-card p-6">
            <h2 className="font-[var(--font-heading)] text-2xl font-semibold">{title}</h2>
            <p className="mt-3 leading-7 text-[#7C715F]">{body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
