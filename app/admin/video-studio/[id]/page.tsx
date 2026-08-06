import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { hasAdminAccess } from "@/lib/auth/admin-access";
import { CopyButton } from "@/components/video-studio/copy-button";
import { VideoStatusBadge, videoStatusOptions } from "@/components/video-studio/video-status-badge";
import { YouTubeEmbed } from "@/components/video-studio/youtube-embed";
import { generateVideoDraftAction, updateVideoStudioAction } from "../actions";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type PageProps = {
  params: Promise<{ id: string }>;
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
};

type DailyLightVideoDetail = {
  id: string;
  scheduled_date: string | null;
  status: string | null;
  title: string | null;
  theme: string | null;
  summary: string | null;
  body: string | null;
  small_deed: string | null;
  reflection_prompt: string | null;
  video_status: string | null;
  video_platform: string | null;
  video_title: string | null;
  video_hook: string | null;
  video_script: string | null;
  video_caption: string | null;
  video_hashtags: string | null;
  video_notes: string | null;
  video_asset_url: string | null;
  youtube_url: string | null;
  tiktok_url: string | null;
  instagram_url: string | null;
  short_video_public: boolean | null;
  video_posted_at: string | null;
};

function getString(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function formatDate(value?: string | null) {
  if (!value) return "No date";
  return new Date(`${value}T00:00:00`).toLocaleDateString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

async function requireAdmin(next: string) {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect(`/login?next=${encodeURIComponent(next)}`);
  }

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("role,is_suspended")
    .eq("user_id", user.id)
    .maybeSingle();

  const isAdmin = hasAdminAccess({
    email: user.email,
    profile,
    profileError,
  });

  if (!isAdmin) {
    redirect("/today");
  }

  return supabase;
}

export default async function AdminVideoStudioDetailPage({
  params,
  searchParams,
}: PageProps) {
  const { id } = await params;
  const query = searchParams ? await searchParams : {};
  const supabase = await requireAdmin(`/admin/video-studio/${id}`);

  const { data } = await supabase
    .from("daily_lights")
    .select(
      "id,scheduled_date,status,title,theme,summary,body,small_deed,reflection_prompt,video_status,video_platform,video_title,video_hook,video_script,video_caption,video_hashtags,video_notes,video_asset_url,youtube_url,tiktok_url,instagram_url,short_video_public,video_posted_at",
    )
    .eq("id", id)
    .maybeSingle();

  if (!data) {
    notFound();
  }

  const light = data as DailyLightVideoDetail;
  const updateAction = updateVideoStudioAction.bind(null, light.id);
  const generateAction = generateVideoDraftAction.bind(null, light.id);
  const updated = getString(query.updated);
  const error = getString(query.error);

  const exportCaption = [light.video_caption, light.video_hashtags]
    .filter(Boolean)
    .join("\n\n");

  return (
    <div className="mx-auto max-w-6xl px-5 py-12 md:py-20">
      <div className="flex flex-col gap-5 md:flex-row md:items-start md:justify-between">
        <section>
          <Link
            href="/admin/video-studio"
            className="text-sm font-black text-amber-800 underline-offset-4 hover:underline"
          >
            ← Back to video studio
          </Link>
          <p className="mt-6 text-xs font-black uppercase tracking-[0.32em] text-amber-800">
            Short Video Studio
          </p>
          <h1 className="mt-3 text-4xl font-black tracking-tight text-stone-950 md:text-6xl">
            {light.video_title || light.title || "Untitled daily light"}
          </h1>
          <div className="mt-4 flex flex-wrap gap-2">
            <VideoStatusBadge status={light.video_status} />
            <span className="rounded-full bg-[#fff8ea] px-3 py-1 text-xs font-black uppercase tracking-[0.16em] text-amber-800">
              {formatDate(light.scheduled_date)}
            </span>
            {light.short_video_public ? (
              <span className="rounded-full bg-emerald-50 px-3 py-1 text-xs font-black uppercase tracking-[0.16em] text-emerald-800">
                Public on Today
              </span>
            ) : null}
          </div>
        </section>

        <form action={generateAction}>
          <button
            type="submit"
            className="rounded-full bg-amber-400 px-5 py-3 text-sm font-black text-stone-950 shadow-lg shadow-amber-100 active:scale-95"
          >
            Generate draft from Daily Light
          </button>
        </form>
      </div>

      {updated ? (
        <div className="mt-8 rounded-3xl border border-emerald-100 bg-emerald-50 p-5 text-sm font-bold text-emerald-900">
          {updated === "generated"
            ? "Starter video draft generated. Review and adjust it before posting."
            : "Video studio changes saved."}
        </div>
      ) : null}

      {error ? (
        <div className="mt-8 rounded-3xl border border-red-100 bg-red-50 p-5 text-sm font-bold text-red-900">
          {error}
        </div>
      ) : null}

      <div className="mt-8 grid gap-8 lg:grid-cols-[1.4fr_0.8fr]">
        <form
          action={updateAction}
          className="rounded-[2rem] border border-amber-100 bg-white p-6 shadow-[0_24px_70px_rgba(42,32,16,0.08)] md:p-8"
        >
          <div className="grid gap-5 md:grid-cols-2">
            <label className="block">
              <span className="text-sm font-black text-stone-800">Video status</span>
              <select
                name="video_status"
                defaultValue={light.video_status || "not_started"}
                className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm outline-none focus:border-amber-500"
              >
                {videoStatusOptions.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            </label>

            <label className="block">
              <span className="text-sm font-black text-stone-800">Platform plan</span>
              <input
                name="video_platform"
                defaultValue={light.video_platform ?? ""}
                className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm outline-none focus:border-amber-500"
                placeholder="YouTube Shorts / TikTok / Reels"
              />
            </label>
          </div>

          <label className="mt-5 block">
            <span className="text-sm font-black text-stone-800">Video title</span>
            <input
              name="video_title"
              defaultValue={light.video_title ?? ""}
              className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm outline-none focus:border-amber-500"
              placeholder="Short video title"
            />
          </label>

          <label className="mt-5 block">
            <span className="text-sm font-black text-stone-800">First 3 seconds / hook</span>
            <textarea
              name="video_hook"
              rows={3}
              defaultValue={light.video_hook ?? ""}
              className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm outline-none focus:border-amber-500"
              placeholder="The line that stops the scroll"
            />
          </label>

          <label className="mt-5 block">
            <span className="text-sm font-black text-stone-800">Short video script</span>
            <textarea
              name="video_script"
              rows={12}
              defaultValue={light.video_script ?? ""}
              className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm leading-7 outline-none focus:border-amber-500"
              placeholder="Write the voiceover or talking-head script here"
            />
          </label>

          <label className="mt-5 block">
            <span className="text-sm font-black text-stone-800">Caption</span>
            <textarea
              name="video_caption"
              rows={6}
              defaultValue={light.video_caption ?? ""}
              className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm leading-7 outline-none focus:border-amber-500"
              placeholder="Caption for YouTube Shorts, TikTok, or Reels"
            />
          </label>

          <label className="mt-5 block">
            <span className="text-sm font-black text-stone-800">Hashtags</span>
            <textarea
              name="video_hashtags"
              rows={3}
              defaultValue={light.video_hashtags ?? ""}
              className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm outline-none focus:border-amber-500"
              placeholder="#Deedlight #GoodDeeds #Kindness"
            />
          </label>

          <div className="mt-5 grid gap-5 md:grid-cols-2">
            <label className="block">
              <span className="text-sm font-black text-stone-800">YouTube URL</span>
              <input
                name="youtube_url"
                defaultValue={light.youtube_url ?? ""}
                className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm outline-none focus:border-amber-500"
                placeholder="https://youtube.com/shorts/..."
              />
            </label>

            <label className="block">
              <span className="text-sm font-black text-stone-800">TikTok URL</span>
              <input
                name="tiktok_url"
                defaultValue={light.tiktok_url ?? ""}
                className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm outline-none focus:border-amber-500"
                placeholder="https://tiktok.com/..."
              />
            </label>

            <label className="block">
              <span className="text-sm font-black text-stone-800">Instagram/Reels URL</span>
              <input
                name="instagram_url"
                defaultValue={light.instagram_url ?? ""}
                className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm outline-none focus:border-amber-500"
                placeholder="https://instagram.com/reel/..."
              />
            </label>

            <label className="block">
              <span className="text-sm font-black text-stone-800">Video asset URL</span>
              <input
                name="video_asset_url"
                defaultValue={light.video_asset_url ?? ""}
                className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm outline-none focus:border-amber-500"
                placeholder="Drive/asset link for raw or final file"
              />
            </label>
          </div>

          <label className="mt-5 block">
            <span className="text-sm font-black text-stone-800">Production notes</span>
            <textarea
              name="video_notes"
              rows={5}
              defaultValue={light.video_notes ?? ""}
              className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm leading-7 outline-none focus:border-amber-500"
              placeholder="B-roll ideas, recording notes, reminders, thumbnail idea..."
            />
          </label>

          <label className="mt-6 flex items-start gap-3 rounded-3xl border border-amber-100 bg-[#fff8ea] p-4">
            <input
              type="checkbox"
              name="short_video_public"
              defaultChecked={Boolean(light.short_video_public)}
              className="mt-1 h-5 w-5 rounded border-amber-300"
            />
            <span>
              <span className="block text-sm font-black text-stone-900">
                Show this video publicly
              </span>
              <span className="mt-1 block text-sm leading-6 text-stone-600">
                When a YouTube URL is saved, this can show on /videos and on Today’s Deedlight.
              </span>
            </span>
          </label>

          <button
            type="submit"
            className="mt-6 w-full rounded-full bg-amber-400 px-6 py-4 text-sm font-black text-stone-950 shadow-lg shadow-amber-200 transition hover:bg-amber-500 active:scale-[0.98]"
          >
            Save video plan
          </button>
        </form>

        <aside className="space-y-6">
          <section className="rounded-[2rem] border border-amber-100 bg-white p-6 shadow-sm">
            <p className="text-xs font-black uppercase tracking-[0.22em] text-amber-800">
              Source Daily Light
            </p>
            <h2 className="mt-3 text-2xl font-black text-stone-950">
              {light.title}
            </h2>
            {light.theme ? (
              <p className="mt-2 text-sm font-bold text-amber-800">{light.theme}</p>
            ) : null}
            {light.summary ? (
              <p className="mt-3 text-sm leading-7 text-stone-700">{light.summary}</p>
            ) : null}
            {light.small_deed ? (
              <div className="mt-4 rounded-3xl bg-[#fff8ea] p-4">
                <p className="text-xs font-black uppercase tracking-[0.18em] text-amber-800">
                  Small deed
                </p>
                <p className="mt-2 text-sm font-bold leading-7 text-stone-800">
                  {light.small_deed}
                </p>
              </div>
            ) : null}
          </section>

          <section className="rounded-[2rem] border border-amber-100 bg-white p-6 shadow-sm">
            <div className="flex items-center justify-between gap-3">
              <p className="text-xs font-black uppercase tracking-[0.22em] text-amber-800">
                Export
              </p>
              <CopyButton value={exportCaption || ""} label="Copy caption" />
            </div>
            <p className="mt-3 whitespace-pre-line text-sm leading-7 text-stone-700">
              {exportCaption || "Add a caption and hashtags to export."}
            </p>
          </section>

          <section className="rounded-[2rem] border border-amber-100 bg-white p-6 shadow-sm">
            <div className="flex items-center justify-between gap-3">
              <p className="text-xs font-black uppercase tracking-[0.22em] text-amber-800">
                Script
              </p>
              <CopyButton value={light.video_script || ""} label="Copy script" />
            </div>
            <p className="mt-3 whitespace-pre-line text-sm leading-7 text-stone-700">
              {light.video_script || "Generate or write a script first."}
            </p>
          </section>

          {light.youtube_url ? (
            <section className="rounded-[2rem] border border-amber-100 bg-white p-6 shadow-sm">
              <p className="text-xs font-black uppercase tracking-[0.22em] text-amber-800">
                Public preview
              </p>
              <div className="mt-4">
                <YouTubeEmbed url={light.youtube_url} title={light.video_title || light.title} />
              </div>
            </section>
          ) : null}
        </aside>
      </div>
    </div>
  );
}
