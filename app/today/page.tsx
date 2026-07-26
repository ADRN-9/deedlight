import Link from "next/link";

import { DailyReflectionForm } from "@/components/daily/daily-reflection-form";
import {
  getCurrentUser,
  getDailyReflectionCounts,
  getMyReflectionForDailyPost,
  getTodayDailyPost,
} from "@/lib/data/daily";

type TodayPageProps = {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
};

function getMessage(params: Record<string, string | string[] | undefined>, key: string): string | null {
  const value = params[key];
  if (typeof value !== "string") return null;
  return value;
}

export default async function TodayPage({ searchParams }: TodayPageProps) {
  const params = (await searchParams) ?? {};
  const post = await getTodayDailyPost();
  const [{ user }, reflection, counts] = await Promise.all([
    getCurrentUser(),
    getMyReflectionForDailyPost(post.id),
    getDailyReflectionCounts(post.id),
  ]);

  const error = getMessage(params, "error");
  const reflectionSaved = getMessage(params, "reflection") === "saved";

  return (
    <main className="mx-auto max-w-6xl px-6 py-14 md:py-20">
      {error ? (
        <div className="mb-6 rounded-3xl border border-[#f0c7a8] bg-[#fff3e8] px-6 py-4 text-sm font-bold text-[#9a3f1d]">
          {error}
        </div>
      ) : null}
      {reflectionSaved ? (
        <div className="mb-6 rounded-3xl border border-[#cfe7c6] bg-[#f1faed] px-6 py-4 text-sm font-bold text-[#426534]">
          Your private check-in was saved.
        </div>
      ) : null}

      <section className="text-center">
        <p className="text-xs font-black uppercase tracking-[0.4em] text-[#8a641a]">
          {post.kicker ?? "TODAY’S DEEDLIGHT"}
        </p>
        <h1 className="mt-4 text-5xl font-black leading-tight text-[#2a241c] md:text-7xl">{post.title}</h1>
        {post.summary ? <p className="mx-auto mt-5 max-w-3xl text-lg text-[#756b5f]">{post.summary}</p> : null}
      </section>

      <section className="mx-auto mt-10 max-w-4xl overflow-hidden rounded-[2rem] border border-[#efd9a8] bg-white shadow-[0_24px_80px_rgba(110,79,33,0.10)]">
        {post.image_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={post.image_url} alt="Today’s Deedlight" className="h-80 w-full object-cover" />
        ) : (
          <div className="h-80 bg-[linear-gradient(135deg,#ffe3a6,#eaf4f8)]" />
        )}
        <div className="p-8 md:p-10">
          <span className="inline-flex rounded-full bg-[#fff1c8] px-4 py-2 text-xs font-black uppercase tracking-[0.22em] text-[#8a641a]">
            {post.theme ?? "goodness"}
          </span>
          {post.body ? <p className="mt-6 whitespace-pre-wrap text-lg leading-8 text-[#4b4034]">{post.body}</p> : null}
          {post.small_deed ? (
            <div className="mt-8 rounded-3xl border border-[#efd9a8] bg-[#fff8e8] p-6">
              <p className="text-xs font-black uppercase tracking-[0.28em] text-[#8a641a]">Today’s small deed</p>
              <p className="mt-3 text-xl font-black text-[#2a241c]">{post.small_deed}</p>
            </div>
          ) : null}
        </div>
      </section>

      {post.featured_offering ? (
        <section className="mx-auto mt-8 max-w-4xl rounded-[2rem] border border-[#efd9a8] bg-white p-8 shadow-[0_24px_80px_rgba(110,79,33,0.08)]">
          <p className="text-xs font-black uppercase tracking-[0.35em] text-[#8a641a]">Featured Offering</p>
          <h2 className="mt-3 text-3xl font-black text-[#2a241c]">{post.featured_offering.title}</h2>
          {post.featured_offering.story ? (
            <p className="mt-3 text-[#756b5f]">{post.featured_offering.story}</p>
          ) : null}
          <Link
            href={`/offerings/${post.featured_offering.id}`}
            className="mt-5 inline-flex rounded-full border border-[#efd9a8] px-5 py-3 text-sm font-extrabold text-[#4b4034]"
          >
            Open featured Offering
          </Link>
        </section>
      ) : null}

      <section className="mx-auto mt-8 grid max-w-4xl gap-4 md:grid-cols-2">
        <div className="rounded-3xl border border-[#efd9a8] bg-[#fff8e8] p-6">
          <p className="text-4xl font-black text-[#2a241c]">{counts.completedCount}</p>
          <p className="text-xs font-black uppercase tracking-[0.2em] text-[#8a641a]">people checked in</p>
        </div>
        <div className="rounded-3xl border border-[#efd9a8] bg-[#fff8e8] p-6">
          <p className="text-4xl font-black text-[#2a241c]">{counts.reflectionCount}</p>
          <p className="text-xs font-black uppercase tracking-[0.2em] text-[#8a641a]">private reflections saved</p>
        </div>
      </section>

      <div className="mx-auto mt-8 max-w-4xl">
        <DailyReflectionForm post={post} reflection={reflection} isSignedIn={Boolean(user)} />
      </div>

      <section className="mx-auto mt-8 max-w-4xl rounded-[2rem] border border-[#efd9a8] bg-[#fffaf0] p-8">
        <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
          <div>
            <p className="text-xs font-black uppercase tracking-[0.35em] text-[#8a641a]">Short video seed</p>
            <h2 className="mt-3 text-3xl font-black text-[#2a241c]">{post.video_title ?? post.title}</h2>
            {post.video_hook ? <p className="mt-3 font-bold text-[#4b4034]">{post.video_hook}</p> : null}
            {post.video_caption ? <p className="mt-3 text-sm text-[#756b5f]">{post.video_caption}</p> : null}
          </div>
          {post.youtube_url ? (
            <a
              href={post.youtube_url}
              target="_blank"
              rel="noreferrer"
              className="rounded-full bg-[#2a241c] px-5 py-3 text-sm font-extrabold text-white"
            >
              Watch video
            </a>
          ) : null}
        </div>
      </section>

      <div className="mx-auto mt-8 max-w-4xl text-center">
        <Link href="/today/archive" className="text-sm font-extrabold text-[#8a641a] underline decoration-[#efd9a8] underline-offset-4">
          View past Deedlights
        </Link>
      </div>
    </main>
  );
}
