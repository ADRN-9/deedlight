import Link from "next/link";

import { getAdminDailyPosts } from "@/lib/data/daily";
import type { DailyStatus } from "@/lib/types-daily";

type AdminDailyPageProps = {
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
};

const FILTERS: Array<{ label: string; value: "all" | DailyStatus }> = [
  { label: "All", value: "all" },
  { label: "Draft", value: "draft" },
  { label: "Scheduled", value: "scheduled" },
  { label: "Published", value: "published" },
  { label: "Archived", value: "archived" },
];

function readParam(params: Record<string, string | string[] | undefined>, key: string): string | undefined {
  const value = params[key];
  return typeof value === "string" ? value : undefined;
}

export default async function AdminDailyPage({ searchParams }: AdminDailyPageProps) {
  const params = (await searchParams) ?? {};
  const filter = readParam(params, "status") ?? "all";
  const posts = await getAdminDailyPosts(filter);
  const error = readParam(params, "error");

  return (
    <main className="mx-auto max-w-6xl px-6 py-14 md:py-20">
      {error ? (
        <div className="mb-6 rounded-3xl border border-[#f0c7a8] bg-[#fff3e8] px-6 py-4 text-sm font-bold text-[#9a3f1d]">
          {error}
        </div>
      ) : null}

      <section className="flex flex-col gap-6 md:flex-row md:items-end md:justify-between">
        <div>
          <p className="text-xs font-black uppercase tracking-[0.35em] text-[#8a641a]">Admin · Daily Deedlight</p>
          <h1 className="mt-4 text-5xl font-black text-[#2a241c] md:text-7xl">Daily light desk.</h1>
          <p className="mt-4 max-w-3xl text-lg text-[#756b5f]">
            Create, schedule, publish, archive, and prepare the daily short-video seed.
          </p>
        </div>
        <Link
          href="/admin/daily/new"
          className="inline-flex rounded-full bg-[#dfa93b] px-6 py-3 text-sm font-extrabold text-[#2a241c] shadow-[0_16px_38px_rgba(174,122,34,0.22)]"
        >
          Create Today’s Deedlight
        </Link>
      </section>

      <nav className="mt-8 flex flex-wrap gap-3">
        {FILTERS.map((item) => {
          const active = item.value === filter;
          return (
            <Link
              key={item.value}
              href={item.value === "all" ? "/admin/daily" : `/admin/daily?status=${item.value}`}
              className={`rounded-full border px-5 py-3 text-sm font-extrabold ${
                active
                  ? "border-[#dfa93b] bg-[#dfa93b] text-[#2a241c]"
                  : "border-[#efd9a8] bg-white text-[#4b4034]"
              }`}
            >
              {item.label}
            </Link>
          );
        })}
      </nav>

      <section className="mt-8 space-y-5">
        {posts.length === 0 ? (
          <div className="rounded-[2rem] border border-[#efd9a8] bg-white p-10 text-center shadow-[0_24px_80px_rgba(110,79,33,0.08)]">
            <h2 className="text-3xl font-black text-[#2a241c]">No daily posts here yet.</h2>
            <p className="mt-3 text-[#756b5f]">Create the first one to begin the daily rhythm.</p>
          </div>
        ) : (
          posts.map((post) => (
            <article key={post.id} className="rounded-[2rem] border border-[#efd9a8] bg-white p-7 shadow-[0_24px_80px_rgba(110,79,33,0.08)]">
              <div className="flex flex-col gap-5 md:flex-row md:items-center md:justify-between">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="rounded-full bg-[#fff1c8] px-3 py-1 text-[0.68rem] font-black uppercase tracking-[0.18em] text-[#8a641a]">
                      {post.status}
                    </span>
                    <span className="rounded-full border border-[#efd9a8] px-3 py-1 text-[0.68rem] font-black uppercase tracking-[0.18em] text-[#8a641a]">
                      {post.scheduled_for}
                    </span>
                    {post.video_status ? (
                      <span className="rounded-full border border-[#efd9a8] px-3 py-1 text-[0.68rem] font-black uppercase tracking-[0.18em] text-[#8a641a]">
                        video: {post.video_status}
                      </span>
                    ) : null}
                  </div>
                  <h2 className="mt-4 text-3xl font-black text-[#2a241c]">{post.title}</h2>
                  {post.summary ? <p className="mt-3 max-w-3xl text-[#756b5f]">{post.summary}</p> : null}
                </div>
                <Link
                  href={`/admin/daily/${post.id}`}
                  className="inline-flex shrink-0 rounded-full bg-[#dfa93b] px-6 py-3 text-sm font-extrabold text-[#2a241c]"
                >
                  Edit / schedule
                </Link>
              </div>
            </article>
          ))
        )}
      </section>
    </main>
  );
}
