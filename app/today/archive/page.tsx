import Link from "next/link";

import { getDailyArchive } from "@/lib/data/daily";

export default async function TodayArchivePage() {
  const posts = await getDailyArchive();

  return (
    <main className="mx-auto max-w-6xl px-6 py-14 md:py-20">
      <section>
        <p className="text-xs font-black uppercase tracking-[0.35em] text-[#8a641a]">Daily archive</p>
        <h1 className="mt-4 text-5xl font-black text-[#2a241c] md:text-7xl">Past lights, still glowing.</h1>
        <p className="mt-4 max-w-3xl text-lg text-[#756b5f]">
          A small archive of Deedlights that have already been shared, so goodness can be revisited and carried forward.
        </p>
      </section>

      <section className="mt-10 grid gap-5 md:grid-cols-2">
        {posts.length === 0 ? (
          <div className="rounded-[2rem] border border-[#efd9a8] bg-white p-10 text-center shadow-[0_24px_80px_rgba(110,79,33,0.08)] md:col-span-2">
            <h2 className="text-3xl font-black text-[#2a241c]">No archived lights yet.</h2>
            <p className="mt-3 text-[#756b5f]">Published Deedlights will appear here over time.</p>
          </div>
        ) : (
          posts.map((post) => (
            <article key={post.id} className="rounded-[2rem] border border-[#efd9a8] bg-white p-7 shadow-[0_24px_80px_rgba(110,79,33,0.08)]">
              <div className="flex flex-wrap items-center gap-2">
                <span className="rounded-full bg-[#fff1c8] px-3 py-1 text-[0.68rem] font-black uppercase tracking-[0.18em] text-[#8a641a]">
                  {post.status}
                </span>
                <span className="text-sm font-bold text-[#756b5f]">{post.scheduled_for}</span>
              </div>
              <h2 className="mt-4 text-3xl font-black text-[#2a241c]">{post.title}</h2>
              {post.summary ? <p className="mt-3 text-[#756b5f]">{post.summary}</p> : null}
              {post.small_deed ? (
                <p className="mt-5 rounded-2xl bg-[#fff8e8] p-4 text-sm font-bold text-[#4b4034]">{post.small_deed}</p>
              ) : null}
            </article>
          ))
        )}
      </section>

      <div className="mt-10">
        <Link href="/today" className="rounded-full border border-[#efd9a8] px-5 py-3 text-sm font-extrabold text-[#4b4034]">
          Back to today
        </Link>
      </div>
    </main>
  );
}
