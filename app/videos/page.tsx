import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { YouTubeEmbed } from "@/components/video-studio/youtube-embed";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export const metadata: Metadata = {
  title: "Deedlight Videos",
  description: "Short videos from Deedlight’s daily invitations to goodness.",
  openGraph: {
    title: "Deedlight Videos",
    description: "Short videos from Deedlight’s daily invitations to goodness.",
    url: "/videos",
    images: ["/og/deedlight-og.png"],
  },
};

type PublicVideoRow = {
  id: string;
  scheduled_date: string | null;
  title: string | null;
  theme: string | null;
  summary: string | null;
  small_deed: string | null;
  video_title: string | null;
  video_hook: string | null;
  video_caption: string | null;
  video_hashtags: string | null;
  youtube_url: string | null;
  tiktok_url: string | null;
  instagram_url: string | null;
  video_posted_at: string | null;
};

function formatDate(value?: string | null) {
  if (!value) return "Daily light";
  return new Date(`${value}T00:00:00`).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export default async function PublicVideosPage() {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("daily_lights")
    .select(
      "id,scheduled_date,title,theme,summary,small_deed,video_title,video_hook,video_caption,video_hashtags,youtube_url,tiktok_url,instagram_url,video_posted_at",
    )
    .eq("status", "published")
    .eq("short_video_public", true)
    .not("youtube_url", "is", null)
    .order("scheduled_date", { ascending: false })
    .limit(24);

  const videos = (data ?? []) as PublicVideoRow[];

  return (
    <div className="mx-auto max-w-5xl px-5 py-12 md:py-20">
      <section className="text-center">
        <p className="text-xs font-black uppercase tracking-[0.32em] text-amber-800">
          Deedlight videos
        </p>
        <h1 className="mx-auto mt-4 max-w-4xl text-5xl font-black tracking-tight text-stone-950 md:text-7xl">
          Short lights for daily goodness.
        </h1>
        <p className="mx-auto mt-5 max-w-2xl leading-8 text-stone-700">
          Watch short Deedlight messages made from daily invitations, small deeds, and community inspiration.
        </p>
      </section>

      {error ? (
        <div className="mt-8 rounded-3xl border border-red-100 bg-red-50 p-5 text-sm font-bold text-red-900">
          {error.message}
        </div>
      ) : null}

      <section className="mt-10 space-y-8">
        {videos.length ? (
          videos.map((video) => (
            <article
              key={video.id}
              className="overflow-hidden rounded-[2.2rem] border border-amber-100 bg-white shadow-[0_30px_90px_rgba(42,32,16,0.08)]"
            >
              <YouTubeEmbed url={video.youtube_url} title={video.video_title || video.title} />

              <div className="p-6 md:p-8">
                <div className="flex flex-wrap gap-2">
                  <span className="rounded-full bg-amber-100 px-3 py-1 text-xs font-black uppercase tracking-[0.18em] text-amber-800">
                    {formatDate(video.scheduled_date)}
                  </span>
                  {video.theme ? (
                    <span className="rounded-full bg-[#fff8ea] px-3 py-1 text-xs font-black uppercase tracking-[0.18em] text-amber-800">
                      {video.theme}
                    </span>
                  ) : null}
                </div>

                <h2 className="mt-4 text-3xl font-black text-stone-950">
                  {video.video_title || video.title}
                </h2>

                {video.video_caption || video.summary ? (
                  <p className="mt-3 whitespace-pre-line text-sm leading-7 text-stone-700">
                    {video.video_caption || video.summary}
                  </p>
                ) : null}

                <div className="mt-5 flex flex-wrap gap-3">
                  <Link
                    href={`/today`}
                    className="rounded-full border border-amber-200 bg-white px-5 py-3 text-sm font-black text-stone-950 active:scale-95"
                  >
                    Today’s Deedlight
                  </Link>
                  {video.youtube_url ? (
                    <a
                      href={video.youtube_url}
                      target="_blank"
                      rel="noreferrer"
                      className="rounded-full bg-amber-400 px-5 py-3 text-sm font-black text-stone-950 active:scale-95"
                    >
                      Open on YouTube
                    </a>
                  ) : null}
                </div>
              </div>
            </article>
          ))
        ) : (
          <div className="rounded-[2rem] border border-amber-100 bg-white p-8 text-center shadow-sm">
            <h2 className="text-2xl font-black text-stone-950">No public videos yet.</h2>
            <p className="mt-2 text-sm leading-7 text-stone-600">
              Deedlight videos will appear here after they are posted and marked public.
            </p>
          </div>
        )}
      </section>
    </div>
  );
}
