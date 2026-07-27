import Link from "next/link";
import { notFound } from "next/navigation";

import {
  archiveDailyPostAction,
  publishDailyPostAction,
  saveAndPublishDailyPostAction,
  saveDailyPostAction,
  scheduleDailyPostAction,
} from "@/app/admin/daily/[id]/actions";
import { getAdminDailyPostById, getApprovedOfferingsForFeature } from "@/lib/data/daily";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type AdminDailyEditPageProps = {
  params: Promise<{ id: string }>;
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
};

function readParam(params: Record<string, string | string[] | undefined>, key: string): string | undefined {
  const value = params[key];
  return typeof value === "string" ? value : undefined;
}

function statusLabel(value: string | undefined): string | null {
  if (!value) return null;
  const labels: Record<string, string> = {
    created: "Daily Deedlight created.",
    saved: "Daily Deedlight saved.",
    published: "Daily Deedlight published.",
    scheduled: "Daily Deedlight scheduled.",
    archived: "Daily Deedlight archived.",
    saved_and_published: "Daily Deedlight saved and published.",
  };
  return labels[value] ?? "Daily Deedlight updated.";
}

export default async function AdminDailyEditPage({ params, searchParams }: AdminDailyEditPageProps) {
  const { id } = await params;
  const query = (await searchParams) ?? {};
  const [post, offerings] = await Promise.all([getAdminDailyPostById(id), getApprovedOfferingsForFeature()]);

  if (!post) notFound();

  const error = readParam(query, "error");
  const updated = statusLabel(readParam(query, "updated"));

  return (
    <main className="mx-auto max-w-6xl px-6 py-14 md:py-20">
      {error ? (
        <div className="mb-6 rounded-3xl border border-[#f0c7a8] bg-[#fff3e8] px-6 py-4 text-sm font-bold text-[#9a3f1d]">
          {error}
        </div>
      ) : null}
      {updated ? (
        <div className="mb-6 rounded-3xl border border-[#cfe7c6] bg-[#f1faed] px-6 py-4 text-sm font-bold text-[#426534]">
          {updated}
        </div>
      ) : null}

      <div className="mb-8 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <p className="text-xs font-black uppercase tracking-[0.35em] text-[#8a641a]">Admin · Daily Deedlight</p>
          <h1 className="mt-4 text-5xl font-black text-[#2a241c] md:text-7xl">Edit daily light.</h1>
          <p className="mt-4 max-w-3xl text-lg text-[#756b5f]">
            Update the message, choose a featured Offering, publish, schedule, archive, and prepare video content.
          </p>
        </div>
        <div className="flex flex-wrap gap-3">
          <Link href="/today" className="rounded-full border border-[#efd9a8] bg-white px-6 py-3 text-sm font-extrabold text-[#4b4034]">
            Open today
          </Link>
          <Link href="/admin/daily" className="rounded-full border border-[#efd9a8] bg-white px-6 py-3 text-sm font-extrabold text-[#4b4034]">
            Back to desk
          </Link>
        </div>
      </div>

      <form action={saveDailyPostAction} className="grid gap-8 lg:grid-cols-[1fr_360px]">
        <input type="hidden" name="id" value={post.id} />

        <section className="space-y-6 rounded-[2rem] border border-[#efd9a8] bg-white p-8 shadow-[0_24px_80px_rgba(110,79,33,0.08)]">
          <div className="rounded-[2rem] border border-[#efd9a8] bg-[#fff8e8] p-6">
            <div className="flex flex-wrap items-center gap-2">
              <span className="rounded-full bg-[#fff1c8] px-3 py-1 text-[0.68rem] font-black uppercase tracking-[0.18em] text-[#8a641a]">
                {post.status}
              </span>
              <span className="rounded-full border border-[#efd9a8] px-3 py-1 text-[0.68rem] font-black uppercase tracking-[0.18em] text-[#8a641a]">
                {post.scheduled_for}
              </span>
            </div>
            <h2 className="mt-4 text-3xl font-black text-[#2a241c]">{post.title}</h2>
            {post.small_deed ? <p className="mt-3 font-bold text-[#4b4034]">{post.small_deed}</p> : null}
          </div>

          <div className="grid gap-4 md:grid-cols-2">
            <label className="block">
              <span className="text-sm font-extrabold text-[#4b4034]">Schedule date</span>
              <input
                type="date"
                name="scheduled_for"
                defaultValue={post.scheduled_for}
                className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]"
              />
            </label>
            <label className="block">
              <span className="text-sm font-extrabold text-[#4b4034]">Status</span>
              <select name="status" defaultValue={post.status} className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]">
                <option value="draft">Draft</option>
                <option value="scheduled">Scheduled</option>
                <option value="published">Published</option>
                <option value="archived">Archived</option>
              </select>
            </label>
          </div>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Slug</span>
            <input name="slug" defaultValue={post.slug ?? ""} className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Kicker</span>
            <input name="kicker" defaultValue={post.kicker ?? ""} className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Title</span>
            <input name="title" defaultValue={post.title} className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 text-xl font-black outline-none focus:border-[#dfa93b]" />
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Theme</span>
            <input name="theme" defaultValue={post.theme ?? ""} className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Summary</span>
            <textarea name="summary" rows={3} defaultValue={post.summary ?? ""} className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Main reflection/body</span>
            <textarea name="body" rows={8} defaultValue={post.body ?? ""} className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Today’s small deed</span>
            <textarea name="small_deed" rows={3} defaultValue={post.small_deed ?? ""} className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 font-bold outline-none focus:border-[#dfa93b]" />
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Reflection prompt</span>
            <input name="reflection_prompt" defaultValue={post.reflection_prompt ?? ""} className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
          </label>

          <label className="block">
            <span className="text-sm font-extrabold text-[#4b4034]">Image URL</span>
            <input name="image_url" defaultValue={post.image_url ?? ""} placeholder="Optional image URL" className="mt-2 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
          </label>
        </section>

        <aside className="space-y-6">
          <section className="rounded-[2rem] border border-[#efd9a8] bg-white p-6 shadow-[0_24px_80px_rgba(110,79,33,0.08)]">
            <h2 className="text-2xl font-black text-[#2a241c]">Actions</h2>
            <p className="mt-2 text-sm text-[#756b5f]">
              “Save and publish” applies editor changes before changing public status.
            </p>
            <button type="submit" className="mt-5 w-full rounded-full bg-[#dfa93b] px-6 py-4 text-sm font-extrabold text-[#2a241c] shadow-[0_16px_38px_rgba(174,122,34,0.22)]">
              Save edits only
            </button>
            <button type="submit" formAction={saveAndPublishDailyPostAction} className="mt-3 w-full rounded-full bg-[#2a241c] px-6 py-4 text-sm font-extrabold text-white">
              Save edits and publish
            </button>
            <button type="submit" formAction={scheduleDailyPostAction} className="mt-3 w-full rounded-full border border-[#efd9a8] bg-white px-6 py-4 text-sm font-extrabold text-[#4b4034]">
              Mark as scheduled
            </button>
            <button type="submit" formAction={publishDailyPostAction} className="mt-3 w-full rounded-full border border-[#efd9a8] bg-white px-6 py-4 text-sm font-extrabold text-[#4b4034]">
              Publish saved version
            </button>
            <button type="submit" formAction={archiveDailyPostAction} className="mt-3 w-full rounded-full bg-[#f3eadb] px-6 py-4 text-sm font-extrabold text-[#4b4034]">
              Archive saved version
            </button>
          </section>

          <section className="rounded-[2rem] border border-[#efd9a8] bg-white p-6 shadow-[0_24px_80px_rgba(110,79,33,0.08)]">
            <h2 className="text-2xl font-black text-[#2a241c]">Featured Offering</h2>
            <p className="mt-2 text-sm text-[#756b5f]">Choose one approved community post to lift into today’s message.</p>
            <select name="featured_offering_id" defaultValue={post.featured_offering_id ?? "none"} className="mt-4 w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]">
              <option value="none">No featured Offering</option>
              {offerings.map((offering) => (
                <option key={offering.id} value={offering.id}>
                  {offering.title}
                </option>
              ))}
            </select>
            {post.featured_offering ? (
              <div className="mt-4 rounded-2xl bg-[#fff8e8] p-4">
                <p className="text-xs font-black uppercase tracking-[0.18em] text-[#8a641a]">Current featured</p>
                <p className="mt-2 font-black text-[#2a241c]">{post.featured_offering.title}</p>
              </div>
            ) : null}
          </section>

          <section className="rounded-[2rem] border border-[#efd9a8] bg-white p-6 shadow-[0_24px_80px_rgba(110,79,33,0.08)]">
            <h2 className="text-2xl font-black text-[#2a241c]">Short video seed</h2>
            <div className="mt-4 space-y-4">
              <input name="video_title" defaultValue={post.video_title ?? ""} placeholder="Video title" className="w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
              <textarea name="video_hook" rows={2} defaultValue={post.video_hook ?? ""} placeholder="First 3 seconds / hook" className="w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
              <textarea name="video_script" rows={6} defaultValue={post.video_script ?? ""} placeholder="Short video script" className="w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
              <textarea name="video_caption" rows={3} defaultValue={post.video_caption ?? ""} placeholder="Caption and hashtags" className="w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
              <input name="youtube_url" defaultValue={post.youtube_url ?? ""} placeholder="YouTube URL after publishing" className="w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]" />
              <select name="video_status" defaultValue={post.video_status ?? "idea"} className="w-full rounded-2xl border border-[#ecd7a8] bg-[#fffaf0] p-4 outline-none focus:border-[#dfa93b]">
                <option value="idea">Idea</option>
                <option value="scripted">Scripted</option>
                <option value="recorded">Recorded</option>
                <option value="published">Published</option>
              </select>
            </div>
          </section>
        </aside>
      </form>
    </main>
  );
}
