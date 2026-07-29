import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { VideoStatusBadge, videoStatusOptions } from "@/components/video-studio/video-status-badge";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

type DailyLightVideoRow = {
  id: string;
  scheduled_date: string | null;
  status: string | null;
  title: string | null;
  theme: string | null;
  video_status: string | null;
  video_title: string | null;
  video_hook: string | null;
  video_caption: string | null;
  video_hashtags: string | null;
  youtube_url: string | null;
  tiktok_url: string | null;
  instagram_url: string | null;
  short_video_public: boolean | null;
  video_posted_at: string | null;
  updated_at: string | null;
};

function getString(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function formatDate(value?: string | null) {
  if (!value) return "No date";
  return new Date(`${value}T00:00:00`).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function countByStatus(items: DailyLightVideoRow[], status: string) {
  return items.filter((item) => (item.video_status || "not_started") === status).length;
}

async function requireAdmin() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login?next=/admin/video-studio");
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("role,is_suspended")
    .eq("user_id", user.id)
    .maybeSingle();

  const isAdmin = profile?.role === "admin" && profile?.is_suspended !== true;

  if (!isAdmin) {
    redirect("/today");
  }

  return supabase;
}

export default async function AdminVideoStudioPage({
  searchParams,
}: {
  searchParams?: SearchParams;
}) {
  const params = searchParams ? await searchParams : {};
  const filter = getString(params.status) || "all";
  const supabase = await requireAdmin();

  let query = supabase
    .from("daily_lights")
    .select(
      "id,scheduled_date,status,title,theme,video_status,video_title,video_hook,video_caption,video_hashtags,youtube_url,tiktok_url,instagram_url,short_video_public,video_posted_at,updated_at",
    )
    .order("scheduled_date", { ascending: false })
    .limit(100);

  if (filter !== "all") {
    query = query.eq("video_status", filter);
  }

  const { data, error } = await query;
  const lights = (data ?? []) as DailyLightVideoRow[];

  const statsSource = lights;

  return (
    <div className="mx-auto max-w-6xl px-5 py-12 md:py-20">
      <div className="flex flex-col gap-5 md:flex-row md:items-end md:justify-between">
        <section>
          <p className="text-xs font-black uppercase tracking-[0.32em] text-amber-800">
            Admin · Short Video Studio
          </p>
          <h1 className="mt-3 text-4xl font-black tracking-tight text-stone-950 md:text-6xl">
            Turn daily lights into short videos.
          </h1>
          <p className="mt-4 max-w-2xl leading-8 text-stone-700">
            Plan hooks, scripts, captions, hashtags, platform links, and public embeds from each Daily Deedlight.
          </p>
        </section>

        <div className="flex flex-col gap-3 sm:flex-row">
          <Link
            href="/admin/daily/new"
            className="rounded-full border border-amber-200 bg-white px-5 py-3 text-center text-sm font-black text-stone-950 active:scale-95"
          >
            New Daily Light
          </Link>
          <Link
            href="/videos"
            className="rounded-full bg-amber-400 px-5 py-3 text-center text-sm font-black text-stone-950 shadow-lg shadow-amber-100 active:scale-95"
          >
            Public Videos
          </Link>
        </div>
      </div>

      {error ? (
        <div className="mt-8 rounded-3xl border border-red-100 bg-red-50 p-5 text-sm font-bold text-red-900">
          {error.message}
        </div>
      ) : null}

      <section className="mt-8 grid gap-4 md:grid-cols-5">
        <StatCard label="Planned" value={countByStatus(statsSource, "planned")} />
        <StatCard label="Scripted" value={countByStatus(statsSource, "scripted")} />
        <StatCard label="Recorded" value={countByStatus(statsSource, "recorded")} />
        <StatCard label="Posted" value={countByStatus(statsSource, "posted")} />
        <StatCard label="Public" value={statsSource.filter((item) => item.short_video_public).length} />
      </section>

      <nav className="mt-8 flex flex-wrap gap-2">
        <FilterLink href="/admin/video-studio" active={filter === "all"}>All</FilterLink>
        {videoStatusOptions.map((option) => (
          <FilterLink
            key={option.value}
            href={`/admin/video-studio?status=${option.value}`}
            active={filter === option.value}
          >
            {option.label}
          </FilterLink>
        ))}
      </nav>

      <section className="mt-8 space-y-4">
        {lights.length ? (
          lights.map((light) => (
            <article
              key={light.id}
              className="rounded-[1.75rem] border border-amber-100 bg-white p-5 shadow-[0_18px_55px_rgba(42,32,16,0.06)]"
            >
              <div className="flex flex-col gap-5 md:flex-row md:items-start md:justify-between">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <VideoStatusBadge status={light.video_status} />
                    <span className="rounded-full bg-[#fff8ea] px-3 py-1 text-xs font-black uppercase tracking-[0.16em] text-amber-800">
                      {formatDate(light.scheduled_date)}
                    </span>
                    {light.short_video_public ? (
                      <span className="rounded-full bg-emerald-50 px-3 py-1 text-xs font-black uppercase tracking-[0.16em] text-emerald-800">
                        Public embed
                      </span>
                    ) : null}
                  </div>

                  <h2 className="mt-3 text-2xl font-black text-stone-950">
                    {light.video_title || light.title || "Untitled daily light"}
                  </h2>

                  {light.video_hook ? (
                    <p className="mt-2 max-w-2xl text-sm leading-7 text-stone-700">
                      {light.video_hook}
                    </p>
                  ) : (
                    <p className="mt-2 text-sm leading-7 text-stone-500">
                      No hook/script yet. Open this light to generate a starter draft.
                    </p>
                  )}

                  <div className="mt-3 flex flex-wrap gap-2 text-xs font-bold text-stone-500">
                    {light.youtube_url ? <span>YouTube ready</span> : null}
                    {light.tiktok_url ? <span>TikTok linked</span> : null}
                    {light.instagram_url ? <span>Instagram linked</span> : null}
                    {light.video_posted_at ? <span>Posted {new Date(light.video_posted_at).toLocaleDateString("en-US")}</span> : null}
                  </div>
                </div>

                <Link
                  href={`/admin/video-studio/${light.id}`}
                  className="rounded-full bg-stone-950 px-5 py-3 text-center text-sm font-black text-white active:scale-95"
                >
                  Open studio
                </Link>
              </div>
            </article>
          ))
        ) : (
          <div className="rounded-[1.75rem] border border-amber-100 bg-white p-8 text-center shadow-sm">
            <h2 className="text-2xl font-black text-stone-950">No daily lights found.</h2>
            <p className="mt-2 text-sm leading-7 text-stone-600">
              Create Daily Deedlights first, then turn them into short-video content here.
            </p>
          </div>
        )}
      </section>
    </div>
  );
}

function StatCard({ value, label }: { value: number; label: string }) {
  return (
    <div className="rounded-3xl border border-amber-100 bg-white p-5 shadow-sm">
      <p className="text-3xl font-black text-stone-950">{value}</p>
      <p className="mt-1 text-xs font-black uppercase tracking-[0.22em] text-amber-800">
        {label}
      </p>
    </div>
  );
}

function FilterLink({
  href,
  active,
  children,
}: {
  href: string;
  active: boolean;
  children: React.ReactNode;
}) {
  return (
    <Link
      href={href}
      className={`rounded-full border px-4 py-2 text-sm font-black active:scale-95 ${
        active
          ? "border-amber-400 bg-amber-400 text-stone-950"
          : "border-amber-200 bg-white text-stone-800"
      }`}
    >
      {children}
    </Link>
  );
}
