import { notFound } from "next/navigation";
import { OfferingCard } from "@/components/offerings/offering-card";
import { getOffering } from "@/lib/data/offerings";

export default async function OfferingDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const offering = await getOffering(id);

  if (!offering) notFound();

  return (
    <section className="mx-auto max-w-3xl px-4 py-12 sm:px-6">
      <OfferingCard offering={offering} />
      <div className="deed-card mt-6 p-6">
        <h2 className="font-[var(--font-heading)] text-2xl font-semibold">This light inspired</h2>
        <div className="mt-4 grid gap-3 sm:grid-cols-3">
          <Stat label="Blessed" value={offering.bless_count} />
          <Stat label="Inspired" value={offering.inspired_count} />
          <Stat label="Carried forward" value={offering.carried_forward_count} />
        </div>
      </div>
    </section>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-3xl bg-[#FFF8EA] p-5 text-center">
      <p className="font-[var(--font-heading)] text-3xl font-semibold">{value}</p>
      <p className="text-xs font-extrabold uppercase tracking-[0.18em] text-[#8D681D]">{label}</p>
    </div>
  );
}
