import { OfferingCard } from "@/components/offerings/offering-card";
import { getRisingOfferings } from "@/lib/data/offerings";

export default async function RisingPage() {
  const offerings = await getRisingOfferings(24);

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <div className="mb-8">
        <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Rising Goodness</p>
        <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">Offerings carrying light today.</h1>
        <p className="mt-4 max-w-2xl leading-8 text-[#7C715F]">
          Rising Goodness is ranked by Bless, Inspired, and Did too actions, with a gentle lift for newer approved Offerings.
          Deedlight ranks deeds, not ego.
        </p>
      </div>

      {offerings.length === 0 ? (
        <div className="deed-card p-8 text-center">
          <h2 className="font-[var(--font-heading)] text-3xl font-semibold">No rising Offerings yet.</h2>
          <p className="mx-auto mt-3 max-w-xl leading-8 text-[#7C715F]">
            Once people begin blessing and carrying Offerings forward, the most inspiring lights will appear here.
          </p>
        </div>
      ) : (
        <div className="grid gap-6 md:grid-cols-2">
          {offerings.map((offering, index) => (
            <OfferingCard key={offering.id} offering={offering} showRank={index + 1} />
          ))}
        </div>
      )}
    </section>
  );
}
