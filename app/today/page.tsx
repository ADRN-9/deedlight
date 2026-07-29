import type { Metadata } from "next";
import Link from "next/link";
import { ShareButton } from "@/components/share-button";
import { YouTubeEmbed } from "@/components/video-studio/youtube-embed";
import { createClient } from "@/lib/supabase/server";
import { submitDailyReflectionAction } from "./actions";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export const metadata: Metadata = {
  title: "Today’s Deedlight",
  description: "A daily invitation to goodness, beauty, and better deeds.",
  openGraph: {
    title: "Today’s Deedlight",
    description: "A daily invitation to goodness, beauty, and better deeds.",
    url: "/today",
    images: ["/og/deedlight-og.png"],
  },
  twitter: {
    card: "summary_large_image",
    title: "Today’s Deedlight",
    description: "A daily invitation to goodness, beauty, and better deeds.",
    images: ["/og/deedlight-og.png"],
  },
};

type TodayPageProps = {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
};

type FeaturedOffering = {
  id: string;
  title: string | null;
  body: string | null;
  offering_type: string | null;
  display_name: string | null;
};

type DailyLightRow = {
  id: string;
  scheduled_date: string | null;
  status: string | null;
  kicker: string | null;
  title: string | null;
  theme: string | null;
  summary: string | null;
  body: string | null;
  small_deed: string | null;
  reflection_prompt: string | null;
  featured_offering_id: string | null;
  video_title: string | null;
  video_caption: string | null;
  youtube_url: string | null;
  short_video_public: boolean | null;
  video_status: string | null;
};

function getString(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

export default async function TodayPage({ searchParams }: TodayPageProps) {
  const params = searchParams ? await searchParams : {};
  const supabase = await createClient();
  const today = new Date().toISOString().slice(0, 10);

  // Keep this primary query simple. Do not embed the featured Offering here.
  // Supabase can return null data if the relationship cache is stale, which made
  // /today fall back even when the Daily Light row existed and /videos worked.
  const { data: dailyLight, error: dailyLightError } = await supabase
    .from("daily_lights")
    .select(
      "id,scheduled_date,status,kicker,title,theme,summary,body,small_deed,reflection_prompt,featured_offering_id,video_title,video_caption,youtube_url,short_video_public,video_status",
    )
    .eq("status", "published")
    .lte("scheduled_date", today)
    .order("scheduled_date", { ascending: false })
    .limit(1)
    .maybeSingle();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  let hasReflected = false;

  if (user && dailyLight?.id) {
    const { data: reflection } = await supabase
      .from("daily_reflections")
      .select("id")
      .eq("daily_light_id", dailyLight.id)
      .eq("user_id", user.id)
      .maybeSingle();

    hasReflected = Boolean(reflection);
  }

  let featuredOffering: FeaturedOffering | null = null;

  if (dailyLight?.featured_offering_id) {
    const { data } = await supabase
      .from("offerings")
      .select("id,title,body,offering_type,display_name")
      .eq("id", dailyLight.featured_offering_id)
      .eq("status", "approved")
      .maybeSingle();

    featuredOffering = data as FeaturedOffering | null;
  }

  const fallback: DailyLightRow = {
    id: "",
    scheduled_date: null,
    status: "fallback",
    kicker: "TODAY’S DEEDLIGHT",
    title: "A new light can begin today.",
    theme: "courage, dignity, kindness",
    summary:
      "Beauty is not only found in nature. Sometimes beauty appears when one person refuses to join cruelty.",
    body:
      "Goodness does not prevail by accident. It grows when someone chooses it in a real moment.",
    small_deed:
      "Say one gentle sentence in defense of someone who is being judged unfairly.",
    reflection_prompt: "Where can you protect dignity today?",
    featured_offering_id: null,
    video_title: null,
    video_caption: null,
    youtube_url: null,
    short_video_public: false,
    video_status: null,
  };

  const light = (dailyLight ?? fallback) as DailyLightRow;
  const showVideo = Boolean(
    light.short_video_public && light.youtube_url && light.video_status === "posted",
  );
  const isExactToday = light.scheduled_date === today;
  const reflected = getString(params.reflected);
  const error = getString(params.error);
  const shareUrl = "https://deedlight.com/today";

  return (
    <div className="mx-auto max-w-5xl px-5 py-12 md:py-20">
      {dailyLightError ? (
        <div className="mb-8 rounded-3xl border border-red-100 bg-red-50 p-5 text-sm font-bold text-red-900">
          Today’s Deedlight query failed: {dailyLightError.message}
        </div>
      ) : null}

      {dailyLight && !isExactToday ? (
        <div className="mb-8 rounded-3xl border border-amber-200 bg-amber-50 p-5 text-sm font-bold text-amber-900">
          Today’s exact Deedlight is not scheduled yet, so the latest published light is showing.
        </div>
      ) : null}

      {!dailyLight && !dailyLightError ? (
        <div className="mb-8 rounded-3xl border border-amber-200 bg-amber-50 p-5 text-sm font-bold text-amber-900">
          Today’s published Deedlight is not scheduled yet, so the fallback light is showing.
        </div>
      ) : null}

      {reflected ? (
        <div className="mb-8 rounded-3xl border border-emerald-100 bg-emerald-50 p-5 text-sm font-bold text-emerald-900">
          Reflection saved. Thank you for carrying today’s light.
        </div>
      ) : null}

      {error ? (
        <div className="mb-8 rounded-3xl border border-red-100 bg-red-50 p-5 text-sm font-bold text-red-900">
          {error}
        </div>
      ) : null}

      <section className="text-center">
        <p className="text-xs font-black uppercase tracking-[0.32em] text-amber-800">
          {light.kicker || "TODAY’S DEEDLIGHT"}
        </p>
        <h1 className="mx-auto mt-4 max-w-4xl text-5xl font-black tracking-tight text-stone-950 md:text-7xl">
          {light.title}
        </h1>
      </section>

      <section className="mx-auto mt-10 overflow-hidden rounded-[2.2rem] border border-amber-100 bg-white shadow-[0_30px_90px_rgba(42,32,16,0.10)]">
        <div className="h-72 bg-gradient-to-br from-amber-100 via-[#fff8ea] to-sky-100" />

        <div className="p-6 md:p-9">
          {light.theme ? (
            <span className="rounded-full bg-amber-100 px-3 py-1 text-xs font-black uppercase tracking-[0.18em] text-amber-800">
              {light.theme}
            </span>
          ) : null}

          <h2 className="mt-5 text-3xl font-black text-stone-950">
            {light.title}
          </h2>

          {light.summary ? (
            <p className="mt-4 text-base leading-8 text-stone-700">
              {light.summary}
            </p>
          ) : null}

          {light.body ? (
            <p className="mt-4 whitespace-pre-line text-base leading-8 text-stone-700">
              {light.body}
            </p>
          ) : null}

          {showVideo ? (
            <div className="mt-8">
              <p className="mb-3 text-xs font-black uppercase tracking-[0.22em] text-amber-800">
                Watch today’s short light
              </p>
              <YouTubeEmbed url={light.youtube_url} title={light.video_title || light.title} />
              {light.video_caption ? (
                <p className="mt-3 whitespace-pre-line text-sm leading-7 text-stone-600">
                  {light.video_caption}
                </p>
              ) : null}
            </div>
          ) : null}

          {light.small_deed ? (
            <div className="mt-6 rounded-3xl border border-amber-100 bg-[#fff8ea] p-5">
              <p className="text-xs font-black uppercase tracking-[0.22em] text-amber-800">
                Today’s small deed
              </p>
              <p className="mt-2 text-lg font-black text-stone-950">
                {light.small_deed}
              </p>
            </div>
          ) : null}

          {featuredOffering ? (
            <div className="mt-6 rounded-3xl border border-amber-100 p-5">
              <p className="text-xs font-black uppercase tracking-[0.22em] text-amber-800">
                Inspired by the community
              </p>
              <h3 className="mt-2 text-xl font-black text-stone-950">
                {featuredOffering.title}
              </h3>
              {featuredOffering.body ? (
                <p className="mt-2 line-clamp-3 text-sm leading-7 text-stone-700">
                  {featuredOffering.body}
                </p>
              ) : null}
            </div>
          ) : null}

          <div className="mt-6 flex flex-col gap-3 sm:flex-row">
            <ShareButton
              title="Today’s Deedlight"
              text={light.title || "A daily Deedlight"}
              url={shareUrl}
              label="Share Today’s Deedlight"
            />
            <Link
              href="/videos"
              className="rounded-full border border-amber-200 bg-white px-5 py-3 text-center text-sm font-black text-stone-900 shadow-sm transition active:scale-95"
            >
              Watch videos
            </Link>
          </div>
        </div>
      </section>

      {dailyLight?.id ? (
        <div className="mx-auto mt-10 max-w-2xl">
          {user ? (
            hasReflected ? (
              <section className="rounded-[2rem] border border-emerald-100 bg-emerald-50 p-6 text-emerald-900 shadow-sm">
                <p className="text-xs font-black uppercase tracking-[0.22em]">
                  Reflection complete
                </p>
                <h2 className="mt-2 text-2xl font-black">
                  You carried today’s light.
                </h2>
                <p className="mt-2 text-sm leading-7">
                  A small moment of awareness matters. Come back tomorrow for another Deedlight.
                </p>
              </section>
            ) : (
              <form
                action={submitDailyReflectionAction}
                className="rounded-[2rem] border border-amber-100 bg-white p-6 shadow-[0_24px_70px_rgba(42,32,16,0.08)]"
              >
                <input type="hidden" name="daily_light_id" value={dailyLight.id} />

                <p className="text-xs font-black uppercase tracking-[0.22em] text-amber-800">
                  Daily check-in
                </p>
                <h2 className="mt-2 text-2xl font-black text-stone-950">
                  Pause for one honest moment.
                </h2>

                <label className="mt-5 block">
                  <span className="text-sm font-black text-stone-800">
                    {light.reflection_prompt || "What small good thing will you protect today?"}
                  </span>
                  <textarea
                    name="reflection"
                    rows={4}
                    maxLength={500}
                    className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm outline-none focus:border-amber-500"
                    placeholder="Write a short private reflection..."
                  />
                </label>

                <label className="mt-4 block">
                  <span className="text-sm font-black text-stone-800">
                    One small intention
                  </span>
                  <input
                    name="intention"
                    maxLength={180}
                    className="mt-2 w-full rounded-2xl border border-amber-200 bg-[#fffaf0] p-4 text-sm outline-none focus:border-amber-500"
                    placeholder="Example: I will speak gently today."
                  />
                </label>

                <button
                  type="submit"
                  className="mt-5 w-full rounded-full bg-amber-400 px-6 py-4 text-sm font-black text-stone-950 shadow-lg shadow-amber-200 transition hover:bg-amber-500 active:scale-[0.98]"
                >
                  Complete today’s reflection
                </button>
              </form>
            )
          ) : (
            <div className="rounded-[2rem] border border-amber-100 bg-white p-6 text-center shadow-sm">
              <h2 className="text-2xl font-black">Reflect on today’s light.</h2>
              <p className="mt-2 text-sm leading-7 text-stone-700">
                Sign in to complete your daily check-in and keep your journey.
              </p>
              <Link
                href="/login?next=/today"
                className="mt-5 inline-flex rounded-full bg-amber-400 px-6 py-3 text-sm font-black text-stone-950 active:scale-95"
              >
                Sign in
              </Link>
            </div>
          )}
        </div>
      ) : null}
    </div>
  );
}
