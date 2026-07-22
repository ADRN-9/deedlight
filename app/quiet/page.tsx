import { OfferingCard } from "@/components/offerings/offering-card";
import { getApprovedOfferings } from "@/lib/data/offerings";

export default async function QuietPage() {
  const offerings = (await getApprovedOfferings(24)).filter((item) => item.is_anonymous || item.offering_type === "quiet_goodness");

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Quiet Goodness</p>
      <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">Goodness without showing off.</h1>
      <div className="mt-8 grid gap-6 md:grid-cols-2">
        {offerings.map((offering) => <OfferingCard key={offering.id} offering={offering} />)}
      </div>
    </section>
  );
}
