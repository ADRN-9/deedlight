import { Sparkles } from "lucide-react";
import { PrimaryLink, SecondaryLink } from "@/components/ui/button-link";
import type { DailyPost } from "@/lib/types";

export function DailyLightCard({ post, compact = false }: { post: DailyPost; compact?: boolean }) {
  return (
    <article className="deed-card overflow-hidden">
      <div className="h-56 bg-[radial-gradient(circle_at_30%_15%,rgba(244,199,107,0.65),transparent_35%),linear-gradient(135deg,#FFF4DC,#DCE9F5)] sm:h-72" />
      <div className="p-6 sm:p-8">
        <div className="mb-4 inline-flex items-center gap-2 rounded-full bg-[#FFF4DC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.18em] text-[#8D681D]">
          <Sparkles className="h-3.5 w-3.5" />
          {post.theme_name || "Today"}
        </div>
        <h2 className="font-[var(--font-heading)] text-3xl font-semibold leading-tight text-[#26231F] sm:text-4xl">
          {post.title}
        </h2>
        <p className="mt-4 text-base leading-8 text-[#5F5548]">{post.reflection}</p>
        <div className="mt-6 rounded-3xl border border-[rgba(217,164,65,0.22)] bg-[#FFF8EA] p-5">
          <p className="text-xs font-extrabold uppercase tracking-[0.18em] text-[#8D681D]">Today’s small deed</p>
          <p className="mt-2 text-lg font-bold leading-7 text-[#26231F]">{post.daily_action}</p>
        </div>
        {!compact && post.reflection_question ? (
          <div className="mt-4 rounded-3xl bg-[#DCE9F5]/65 p-5">
            <p className="text-xs font-extrabold uppercase tracking-[0.18em] text-[#506577]">Reflection</p>
            <p className="mt-2 text-base font-semibold leading-7 text-[#26231F]">{post.reflection_question}</p>
          </div>
        ) : null}
        <div className="mt-7 flex flex-col gap-3 sm:flex-row">
          <PrimaryLink href="/today">Open Today’s Light</PrimaryLink>
          <SecondaryLink href="/offerings/new">Share an Offering</SecondaryLink>
        </div>
      </div>
    </article>
  );
}
