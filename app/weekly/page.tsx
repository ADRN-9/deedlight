import type { Metadata } from "next";
import Link from "next/link";
import { OfferingCard } from "@/components/offerings/offering-card";
import { ShareButton } from "@/components/share-button";
import { WeeklyOfferingCard } from "@/components/weekly/weekly-offering-card";
import {
  getCurrentWeeklyFeature,
  getWeeklyGoodness,
} from "@/lib/data/weekly";
import { absoluteUrl } from "@/lib/share/site";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const canonical = absoluteUrl("/weekly");
const socialImage = absoluteUrl("/api/share/weekly");

export const metadata: Metadata = {
  title: "Weekly Goodness",
  description:
    "Public Offerings carrying light across the last seven days — surfaced gently, without a leaderboard.",
  alternates: {
    canonical,
  },
  openGraph: {
    title: "Weekly Goodness",
    description:
      "A week of public goodness, surfaced without turning kindness into a competition.",
    url: canonical,
    siteName: "Deedlight",
    type: "website",
    images: [
      {
        url: socialImage,
        width: 1200,
        height: 630,
        alt: "Weekly Goodness on Deedlight",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Weekly Goodness",
    description:
      "A week of public goodness, surfaced without turning kindness into a competition.",
    images: [socialImage],
  },
};

export default async function WeeklyGoodnessPage() {
  const [offerings, feature] = await Promise.all([
    getWeeklyGoodness(12),
    getCurrentWeeklyFeature(),
  ]);

  const featuredId = feature?.offering.id ?? null;
  const weeklyOfferings = featuredId
    ? offerings.filter((item) => item.id !== featuredId)
    : offerings;

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6 sm:py-16">
      <div className="rounded-[2.4rem] border border-[rgba(217,164,65,0.20)] bg-[radial-gradient(circle_at_82%_12%,rgba(244,199,107,0.45),transparent_28%),linear-gradient(135deg,#FFF9EE,#F8EBD5)] p-7 shadow-[0_30px_90px_rgba(42,32,16,0.08)] sm:p-10">
        <p className="text-xs font-extrabold uppercase tracking-[0.22em] text-[#8D681D]">
          Weekly Goodness
        </p>
        <h1 className="mt-4 max-w-4xl font-[var(--font-heading)] text-5xl font-semibold leading-tight sm:text-6xl">
          A week of light, without a leaderboard.
        </h1>
        <p className="mt-5 max-w-3xl text-base leading-8 text-[#675B4D] sm:text-lg">
          These public Offerings were newly shared or gently carried through
          Bless, Inspired, and Did too actions during the last seven days.
          Deedlight surfaces the activity without ranking people or turning
          goodness into a contest.
        </p>

        <div className="mt-6 flex flex-wrap gap-2">
          {["Last seven days", "Public Offerings only", "No numbered ranks"].map(
            (label) => (
              <span
                key={label}
                className="rounded-full border border-[rgba(217,164,65,0.28)] bg-white/75 px-4 py-2 text-xs font-extrabold text-[#725A2D]"
              >
                {label}
              </span>
            ),
          )}
        </div>

        <div className="mt-7 flex flex-wrap gap-3">
          <ShareButton
            title="Weekly Goodness"
            text="A week of public goodness, surfaced without turning kindness into a competition."
            url={canonical}
            label="Share Weekly Goodness"
          />
          <Link
            href="/offerings/new"
            className="focus-ring rounded-full border border-[rgba(217,164,65,0.34)] bg-white px-5 py-3 text-sm font-extrabold text-[#3F352B]"
          >
            Share an Offering
          </Link>
        </div>
      </div>

      {feature ? (
        <section className="mt-10">
          <div className="mb-5">
            <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
              Featured Light
            </p>
            <h2 className="mt-2 font-[var(--font-heading)] text-4xl font-semibold">
              Chosen with care, not by rank.
            </h2>
            <p className="mt-3 max-w-2xl leading-7 text-[#756A5E]">
              A Deedlight curator selected this approved public Offering for the
              current week. Curation never reveals an anonymous author.
            </p>
          </div>

          <div className="max-w-2xl">
            <OfferingCard offering={feature.offering} />
          </div>
        </section>
      ) : null}

      <section className="mt-12">
        <div className="mb-6">
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
            Carried this week
          </p>
          <h2 className="mt-2 font-[var(--font-heading)] text-4xl font-semibold">
            Goodness people are responding to.
          </h2>
          <p className="mt-3 max-w-2xl leading-7 text-[#756A5E]">
            The order is only a gentle discovery aid. There are no podiums,
            badges, or public member rankings.
          </p>
        </div>

        {weeklyOfferings.length === 0 ? (
          <div className="deed-card p-8 text-center">
            <h3 className="font-[var(--font-heading)] text-3xl font-semibold">
              A quiet week can still hold goodness.
            </h3>
            <p className="mx-auto mt-3 max-w-xl leading-8 text-[#756A5E]">
              Newly approved Offerings and recent public reactions will appear
              here as the next seven-day rhythm develops.
            </p>
          </div>
        ) : (
          <div className="grid gap-6 md:grid-cols-2">
            {weeklyOfferings.map((offering) => (
              <WeeklyOfferingCard
                key={offering.id}
                offering={offering}
              />
            ))}
          </div>
        )}
      </section>
    </section>
  );
}
