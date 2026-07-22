import { OfferingCard } from "@/components/offerings/offering-card";
import { getApprovedOfferings } from "@/lib/data/offerings";

export default async function RisingPage() {
  const offerings = await getApprovedOfferings(12);

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <div className="mb-8">
        <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Rising Goodness</p>
        <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">Offerings carrying light today.</h1>
        <p className="mt-4 max-w-2xl leading-8 text-[#7C715F]">
          Offerings rise when they bless, inspire, and lead others to act. Deedlight shows rising deeds, not top users.
        </p>
      </div>
      <div className="grid gap-6 md:grid-cols-2">
        {offerings.map((offering) => <OfferingCard key={offering.id} offering={offering} />)}
      </div>
    </section>
  );
}
