import Link from "next/link";

import { createDailyPostAction } from "@/app/admin/daily/[id]/actions";
import { getApprovedOfferingsForFeature, requireAdmin } from "@/lib/data/daily";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type NewDailyPageProps = {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
};

function readParam(params: Record<string, string | string[] | undefined>, key: string): string | undefined {
  const value = params[key];
  return typeof value === "string" ? value : undefined;
}

function todayIsoDate(): string {
  return new Date().toISOString().slice(0, 10);
}

export default async function NewDailyPage({ searchParams }: NewDailyPageProps) {
  await requireAdmin();
  const params = (await searchParams) ?? {};
  const error = readParam(params, "error");
  const offerings = await getApprovedOfferingsForFeature();

  return (
    <main className="mx-auto max-w-6xl px-6 py-14 md:py-20">
      {error ? (
        <div className="mb-6 rounded-3xl border border-[#f0c7a8] bg-[#fff3e8] px-6 py-4 text-sm font-bold text-[#9a3f1d]">
          {error}
        </div>
      ) : null}

      <div className="mb-8 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <p className="text-xs font-black uppercase tracking-[0.35em] text-[#8a641a]">Admin · New daily light</p>
          <h1 className="mt-4 text-5xl font-black text-[#2a241c] md:text-7xl">Create Today’s Deedlight.</h1>
          <p className="mt-4 max-w-3xl text-lg text-[#756b5f]">
            Write one daily invitation, schedule it, and prepare a short-video seed from the same message.
          </p>
        </div>
        <Link href="/admin/daily" className="rounded-full border border-[#efd9a8] bg-white px-6 py-3 text-sm font-extrabold text-[#4b4034]">
          Back to daily desk
        </Link>
      </div>

      <form action={createDailyPostAction} className="grid gap-8 lg:grid-cols-[1fr_360px]">
        <section className="space-y-6 rounded-[2rem] border border-[#efd9a8] bg-white p-8 shadow-[0_24px_80px_rgba(110,79,33,0.08)]">
          <div className="grid gap-4 md:grid-cols-2">
            <label className="block">
              <span className="text-sm font-extrabold text-[#4b4034]">Schedule date</span>
              <input
                type="date"
                name="scheduled_for"
                defaultValue={todayIsoDate()}
                className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]"
              />
            </label>
            <label className="block">
              <span className="text-sm font-extrabold text-[#4b4034]">Status</span>
              <select name="status" defaultValue="draft" className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]">
                <option value="draft">Draft</option>
                <option value="scheduled">Scheduled</option>
                <option value="published">Published</option>
                <option value="archived">Archived</option>
              </select>
            </label>
          </div>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Kicker</span>
            <input name="kicker" defaultValue="TODAY’S DEEDLIGHT" className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Title</span>
            <input name="title" placeholder="A new light can begin today." className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 text-xl font-black outline-none focus:border-[#dfa93b]" />
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Theme</span>
            <input name="theme" placeholder="courage, mercy, gratitude, dignity..." className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Summary</span>
            <textarea name="summary" rows={3} placeholder="One clear sentence explaining today’s beauty and invitation." className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Main reflection/body</span>
            <textarea name="body" rows={8} placeholder="Write the daily message with warmth and dignity." className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Today’s small deed</span>
            <textarea name="small_deed" rows={3} placeholder="A small deed someone can try today." className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 font-bold outline-none focus:border-[#dfa93b]" />
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Reflection prompt</span>
            <input name="reflection_prompt" placeholder="Where can I protect dignity today?" className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
          </label>
        </section>

        <aside className="space-y-6">
          <section className="rounded-[2rem] border border-[#efd9a8] bg-white p-6 shadow-[0_24px_80px_rgba(110,79,33,0.08)]">
            <h2 className="text-2xl font-black text-[#2a241c]">Featured Offering</h2>
            <p className="mt-2 text-sm text-[#756b5f]">Choose one approved community post to inspire today’s light.</p>
            <select name="featured_offering_id" defaultValue="none" className="mt-4 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]">
              <option value="none">No featured Offering</option>
              {offerings.map((offering) => (
                <option key={offering.id} value={offering.id}>
                  {offering.title}
                </option>
              ))}
            </select>
          </section>

          <section className="rounded-[2rem] border border-[#efd9a8] bg-white p-6 shadow-[0_24px_80px_rgba(110,79,33,0.08)]">
            <h2 className="text-2xl font-black text-[#2a241c]">Short video seed</h2>
            <div className="mt-4 space-y-4">
              <input name="video_title" placeholder="Video title" className="w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
              <textarea name="video_hook" rows={2} placeholder="First 3 seconds / hook" className="w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
              <textarea name="video_script" rows={6} placeholder="Short video script" className="w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
              <textarea name="video_caption" rows={3} placeholder="Caption and hashtags" className="w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
              <input name="youtube_url" placeholder="YouTube URL after publishing" className="w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
              <select name="video_status" defaultValue="idea" className="w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]">
                <option value="idea">Idea</option>
                <option value="scripted">Scripted</option>
                <option value="recorded">Recorded</option>
                <option value="published">Published</option>
              </select>
            </div>
          </section>

          <section className="rounded-[2rem] border border-[#efd9a8] bg-white p-6 shadow-[0_24px_80px_rgba(110,79,33,0.08)]">
            <button type="submit" className="w-full rounded-full bg-[#dfa93b] px-6 py-4 text-sm font-extrabold text-[#2a241c] shadow-[0_16px_38px_rgba(174,122,34,0.22)]">
              Save draft / schedule
            </button>
            <button type="submit" name="publish_now" value="yes" className="mt-3 w-full rounded-full bg-[#2a241c] px-6 py-4 text-sm font-extrabold text-white">
              Save and publish now
            </button>
          </section>
        </aside>
      </form>
    </main>
  );
}
