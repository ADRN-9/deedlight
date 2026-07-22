import { OfferingCard } from "@/components/offerings/offering-card";
import { PrimaryLink } from "@/components/ui/button-link";
import { getApprovedOfferings } from "@/lib/data/offerings";

export default async function OfferingsPage() {
  const offerings = await getApprovedOfferings(24);

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <div className="mb-8 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Offerings</p>
          <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">Goodness shared by people.</h1>
          <p className="mt-3 max-w-2xl leading-8 text-[#7C715F]">
            Offerings rise when they bless, inspire, and lead others to act.
          </p>
        </div>
        <PrimaryLink href="/offerings/new">Share an Offering</PrimaryLink>
      </div>
      <div className="mb-7 flex flex-wrap gap-2 text-sm font-bold text-[#5F5548]">
        {['Rising', 'Latest', 'Good Deeds', 'Gratitude', 'Quiet', 'Community'].map((chip) => (
          <span key={chip} className="rounded-full border border-[rgba(217,164,65,0.25)] bg-white/70 px-4 py-2">{chip}</span>
        ))}
      </div>
      <div className="grid gap-6 md:grid-cols-2">
        {offerings.map((offering) => <OfferingCard key={offering.id} offering={offering} />)}
      </div>
    </section>
  );
}
