import Link from "next/link";
import { ReactionButtons } from "@/components/offerings/reaction-buttons";
import type { WeeklyOffering } from "@/lib/types-weekly";

export function WeeklyOfferingCard({
  offering,
}: {
  offering: WeeklyOffering;
}) {
  const author = offering.is_anonymous
    ? "Anonymous Light"
    : offering.author_name || "Deedlight member";

  return (
    <article className="deed-card p-5 sm:p-6">
      <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
        <div>
          {!offering.is_anonymous && offering.author_username ? (
            <Link
              className="text-sm font-extrabold text-[#26231F] hover:text-[#8D681D]"
              href={`/people/${offering.author_username}`}
            >
              {author}
            </Link>
          ) : (
            <p className="text-sm font-extrabold text-[#26231F]">{author}</p>
          )}
          <p className="text-xs font-bold text-[#8D7C66]">
            {offering.theme_name || formatOfferingType(offering.offering_type)}
          </p>
        </div>

        <span className="rounded-full bg-[#FFF4DC] px-3 py-1 text-xs font-extrabold text-[#8D681D]">
          {formatOfferingType(offering.offering_type)}
        </span>
      </div>

      {offering.media_url ? (
        <div
          className="mb-4 h-52 rounded-3xl bg-cover bg-center"
          style={{ backgroundImage: `url(${offering.media_url})` }}
        />
      ) : (
        <div className="mb-4 h-40 rounded-3xl bg-[radial-gradient(circle_at_30%_15%,rgba(244,199,107,0.55),transparent_34%),linear-gradient(135deg,#FFF4DC,#F8EFE0)]" />
      )}

      <Link
        href={`/offerings/${offering.id}`}
        className="focus-ring rounded-xl"
      >
        <h2 className="font-[var(--font-heading)] text-2xl font-semibold leading-tight text-[#26231F] hover:text-[#8D681D]">
          {offering.title}
        </h2>
      </Link>

      <p className="mt-3 line-clamp-3 text-sm leading-7 text-[#5F5548]">
        {offering.body}
      </p>

      <div className="mt-5 rounded-2xl border border-[rgba(217,164,65,0.20)] bg-[#FFFBF3] p-4">
        <p className="text-[11px] font-extrabold uppercase tracking-[0.16em] text-[#8D681D]">
          Carried in the last seven days
        </p>
        <div className="mt-3 flex flex-wrap gap-x-4 gap-y-2 text-xs font-bold text-[#6F6253]">
          <span>{offering.weekly_bless_count} blessed</span>
          <span>{offering.weekly_inspired_count} inspired</span>
          <span>{offering.weekly_carried_forward_count} did this too</span>
        </div>
      </div>

      <ReactionButtons
        offeringId={offering.id}
        compact
        initialCounts={{
          bless_count: offering.bless_count || 0,
          inspired_count: offering.inspired_count || 0,
          carried_forward_count: offering.carried_forward_count || 0,
        }}
      />
    </article>
  );
}

function formatOfferingType(value: string) {
  return value
    .split("_")
    .map((word) => word[0]?.toUpperCase() + word.slice(1))
    .join(" ");
}
