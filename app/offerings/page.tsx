import Link from "next/link";
import { OfferingCard } from "@/components/offerings/offering-card";
import { PrimaryLink } from "@/components/ui/button-link";
import {
  getApprovedOfferings,
  getApprovedOfferingsByType,
  getViewerOwnedOfferingIds,
} from "@/lib/data/offerings";
import { getViewerSavedOfferingIds } from "@/lib/data/saved-lights";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

type Filter = {
  label: string;
  href: string;
  type?: string;
};

const FILTERS: Filter[] = [
  { label: "Latest", href: "/offerings" },
  { label: "Rising", href: "/rising" },
  { label: "Good Deeds", href: "/offerings?type=good_deed", type: "good_deed" },
  {
    label: "Invitations",
    href: "/offerings?type=goodness_invitation",
    type: "goodness_invitation",
  },
  { label: "Gratitude", href: "/offerings?type=gratitude", type: "gratitude" },
  {
    label: "Beauty",
    href: "/offerings?type=beauty_reminder",
    type: "beauty_reminder",
  },
  { label: "Quiet", href: "/offerings?type=quiet_goodness", type: "quiet_goodness" },
  {
    label: "Community",
    href: "/offerings?type=community_need",
    type: "community_need",
  },
];

function getString(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

export default async function OfferingsPage({
  searchParams,
}: {
  searchParams?: SearchParams;
}) {
  const params = searchParams ? await searchParams : {};
  const requestedType = getString(params.type);
  const activeType = FILTERS.some((item) => item.type === requestedType)
    ? requestedType
    : undefined;

  const offerings = activeType
    ? await getApprovedOfferingsByType(activeType, 24)
    : await getApprovedOfferings(24);

  const ids = offerings.map((offering) => offering.id);
  const [savedState, ownedIds] = await Promise.all([
    getViewerSavedOfferingIds(ids),
    getViewerOwnedOfferingIds(ids),
  ]);

  const activeLabel =
    FILTERS.find((item) => item.type === activeType)?.label || "Latest";

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <div className="mb-8 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
            Offerings
          </p>
          <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">
            Goodness shared by people.
          </h1>
          <p className="mt-3 max-w-2xl leading-8 text-[#7C715F]">
            Bless what moves you, save a light privately, or carry a deed forward. New and edited Offerings are reviewed before appearing publicly.
          </p>
        </div>
        <PrimaryLink href="/offerings/new">Share an Offering</PrimaryLink>
      </div>

      <nav aria-label="Browse Offerings" className="mb-4 flex flex-wrap gap-2">
        {FILTERS.map((filter) => {
          const active =
            filter.label === "Latest"
              ? !activeType
              : filter.type === activeType;

          return (
            <Link
              key={filter.label}
              href={filter.href}
              aria-current={active ? "page" : undefined}
              className={[
                "focus-ring rounded-full border px-4 py-2 text-sm font-bold transition",
                active
                  ? "border-[#D9A441] bg-[#FFF4DC] text-[#6F4F12]"
                  : "border-[rgba(217,164,65,0.25)] bg-white/80 text-[#5F5548] hover:bg-[#FFF8EA]",
              ].join(" ")}
            >
              {filter.label}
            </Link>
          );
        })}
      </nav>

      <div className="mb-7 flex flex-wrap items-center justify-between gap-3 text-xs font-bold leading-5 text-[#7C715F]">
        <span>Viewing: {activeLabel}</span>
        <span>Saved Offerings are private and never contribute to public rankings or totals.</span>
      </div>

      {offerings.length === 0 ? (
        <div className="deed-card p-8 text-center">
          <div className="mx-auto mb-5 flex h-20 w-20 items-center justify-center rounded-full bg-[#FFF4DC] text-3xl">
            🔥
          </div>
          <h2 className="font-[var(--font-heading)] text-3xl font-semibold">
            No Offerings here yet.
          </h2>
          <p className="mx-auto mt-3 max-w-xl leading-8 text-[#7C715F]">
            Try another category or be the first to share a little light. Your Offering will be reviewed before it becomes public.
          </p>
          <PrimaryLink href="/offerings/new" className="mt-6">
            Share an Offering
          </PrimaryLink>
        </div>
      ) : (
        <div className="grid gap-6 md:grid-cols-2">
          {offerings.map((offering) => (
            <OfferingCard
              key={offering.id}
              offering={offering}
              signedIn={savedState.signedIn}
              initialSaved={savedState.savedIds.has(offering.id)}
              isOwner={ownedIds.has(offering.id)}
            />
          ))}
        </div>
      )}
    </section>
  );
}
