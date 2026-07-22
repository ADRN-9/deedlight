import { DailyLightCard } from "@/components/daily-light/daily-light-card";
import { getTodayPost } from "@/lib/data/daily-posts";

export default async function TodayPage() {
  const post = await getTodayPost();

  return (
    <section className="mx-auto max-w-3xl px-4 py-12 sm:px-6">
      <div className="mb-8 text-center">
        <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Today’s Deedlight</p>
        <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">A new light can begin today.</h1>
      </div>
      <DailyLightCard post={post} />
    </section>
  );
}
