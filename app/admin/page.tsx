import Link from "next/link";
import { AdminCard } from "@/components/admin/admin-card";
import { AdminStatusMessage } from "@/components/admin/admin-status-message";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type CountQuery = {
  count: number | null;
  error: { message?: string } | null;
};

async function exactCount(
  supabase: Awaited<ReturnType<typeof createClient>>,
  table: string,
  configure?: (query: any) => any,
) {
  try {
    let query = (supabase as any)
      .from(table)
      .select("id", { count: "exact", head: true });

    if (configure) {
      query = configure(query);
    }

    const result = (await query) as CountQuery;

    if (result.error) {
      return null;
    }

    return result.count ?? 0;
  } catch {
    return null;
  }
}

export default async function AdminHomePage({
  searchParams,
}: {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const supabase = await createClient();

  const [
    pendingOfferings,
    openReports,
    publishedDailyLights,
    publicVideos,
    draftedVideos,
  ] = await Promise.all([
    exactCount(supabase, "offerings", (query) => query.eq("status", "pending")),
    exactCount(supabase, "reports", (query) => query.in("status", ["open", "pending"])),
    exactCount(supabase, "daily_lights", (query) => query.eq("status", "published")),
    exactCount(supabase, "daily_lights", (query) =>
      query.eq("short_video_public", true).not("youtube_url", "is", null),
    ),
    exactCount(supabase, "daily_lights", (query) =>
      query.in("video_status", ["planned", "scripted", "recorded"]),
    ),
  ]);

  return (
    <div className="mx-auto max-w-6xl px-5 py-12 md:py-16">
      {params?.updated ? (
        <div className="mb-8">
          <AdminStatusMessage type="success" title="Saved">
            The admin workspace has been updated.
          </AdminStatusMessage>
        </div>
      ) : null}

      <section className="rounded-[2.4rem] border border-amber-100 bg-white p-7 shadow-[0_30px_90px_rgba(42,32,16,0.08)] md:p-10">
        <p className="text-xs font-black uppercase tracking-[0.32em] text-amber-800">
          Deedlight admin
        </p>
        <div className="mt-4 flex flex-col gap-6 md:flex-row md:items-end md:justify-between">
          <div>
            <h1 className="max-w-4xl text-4xl font-black tracking-tight text-stone-950 md:text-6xl">
              Content, moderation, and publishing in one place.
            </h1>
            <p className="mt-4 max-w-2xl text-sm leading-7 text-stone-700 md:text-base md:leading-8">
              Manage Today’s Deedlight, community Offerings, reports, and short-video publishing without typing hidden admin URLs.
            </p>
          </div>
          <div className="flex flex-col gap-3 sm:flex-row md:shrink-0">
            <Link
              href="/admin/daily/new"
              className="rounded-full bg-amber-400 px-6 py-3 text-center text-sm font-black text-stone-950 shadow-lg shadow-amber-200 transition hover:bg-amber-500 active:scale-[0.98]"
            >
              New Daily Light
            </Link>
            <Link
              href="/admin/video-studio"
              className="rounded-full border border-amber-200 bg-white px-6 py-3 text-center text-sm font-black text-stone-950 transition hover:bg-[#fff8ea] active:scale-[0.98]"
            >
              Video Studio
            </Link>
          </div>
        </div>

        <div className="mt-8 grid gap-4 md:grid-cols-5">
          <Stat value={pendingOfferings} label="Pending Offerings" />
          <Stat value={openReports} label="Open Reports" />
          <Stat value={publishedDailyLights} label="Published Lights" />
          <Stat value={draftedVideos} label="Videos in Progress" />
          <Stat value={publicVideos} label="Public Videos" />
        </div>
      </section>

      <section className="mt-10 grid gap-5 md:grid-cols-2 lg:grid-cols-3">
        <AdminCard
          href="/admin/daily"
          eyebrow="Daily content"
          title="Daily Desk"
          description="Create, schedule, publish, archive, and refine Today’s Deedlight posts."
          metric={publishedDailyLights}
          metricLabel="Published"
          tone="amber"
        />
        <AdminCard
          href="/admin/video-studio"
          eyebrow="Short videos"
          title="Video Studio"
          description="Generate hooks, scripts, captions, hashtags, and public embeds from Daily Lights."
          metric={draftedVideos}
          metricLabel="In progress"
          tone="sky"
        />
        <AdminCard
          href="/admin/offerings"
          eyebrow="Community"
          title="Offering Queue"
          description="Review, edit, approve, hide, or request changes for community Offerings."
          metric={pendingOfferings}
          metricLabel="Pending"
          tone="emerald"
        />
        <AdminCard
          href="/admin/reports"
          eyebrow="Safety"
          title="Reports"
          description="Review community reports and take moderation actions with clear notes."
          metric={openReports}
          metricLabel="Open"
          tone="stone"
        />
        <AdminCard
          href="/videos"
          eyebrow="Public"
          title="Public Videos"
          description="See what visitors can watch and verify public short-video embeds."
          metric={publicVideos}
          metricLabel="Visible"
          tone="amber"
        />
        <AdminCard
          href="/debug/auth"
          eyebrow="Diagnostics"
          title="Auth Debug"
          description="Admin-only environment and authentication configuration check."
          tone="stone"
        />
      </section>

      <section className="mt-10 rounded-[2rem] border border-amber-100 bg-[#fff8ea] p-6">
        <p className="text-xs font-black uppercase tracking-[0.28em] text-amber-800">
          Production polish checklist
        </p>
        <div className="mt-4 grid gap-3 text-sm font-bold text-stone-700 md:grid-cols-2">
          <ChecklistItem text="Admin pages are reachable from /admin." />
          <ChecklistItem text="Daily Desk and Video Studio are one click away." />
          <ChecklistItem text="Debug remains admin-only and hidden from public users." />
          <ChecklistItem text="Public Today, Videos, Offerings, and Journey pages remain easy to reach." />
        </div>
      </section>
    </div>
  );
}

function Stat({ value, label }: { value: number | null; label: string }) {
  return (
    <div className="rounded-3xl border border-amber-100 bg-[#fff8ea] p-5">
      <p className="text-3xl font-black text-stone-950">{value ?? "—"}</p>
      <p className="mt-1 text-xs font-black uppercase tracking-[0.2em] text-amber-800">
        {label}
      </p>
    </div>
  );
}

function ChecklistItem({ text }: { text: string }) {
  return (
    <div className="flex gap-3 rounded-2xl bg-white p-4">
      <span className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-emerald-100 text-xs text-emerald-800">
        ✓
      </span>
      <span>{text}</span>
    </div>
  );
}
