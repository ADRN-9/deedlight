import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";
import { notFound } from "next/navigation";
import { CheckCircle2, Heart, MessageCircle, Sparkles } from "lucide-react";
import { ReactionButtons } from "@/components/offerings/reaction-buttons";
import { ReportOfferingForm } from "@/components/offerings/report-offering-form";
import { ShareButton } from "@/components/share-button";
import { getOffering } from "@/lib/data/offerings";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type OfferingPageProps = {
  params: Promise<{ id: string }>;
};

export async function generateMetadata({ params }: OfferingPageProps): Promise<Metadata> {
  const { id } = await params;
  const offering = await getOffering(id);

  if (!offering) {
    return {
      title: "Offering not found"
    };
  }

  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "https://deedlight.com";
  const description = offering.body ? offering.body.slice(0, 155) : "A Deedlight Offering.";

  return {
    title: offering.title,
    description,
    openGraph: {
      title: offering.title,
      description,
      url: `${siteUrl.replace(/\/$/, "")}/offerings/${offering.id}`,
      images: ["/og/deedlight-og.png"]
    },
    twitter: {
      card: "summary_large_image",
      title: offering.title,
      description,
      images: ["/og/deedlight-og.png"]
    }
  };
}

export default async function OfferingDetailPage({ params }: OfferingPageProps) {
  const { id } = await params;
  const offering = await getOffering(id);

  if (!offering) notFound();

  const author = offering.is_anonymous ? "Anonymous Light" : offering.author_name || "Deedlight member";
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "https://deedlight.com";
  const shareUrl = `${siteUrl.replace(/\/$/, "")}/offerings/${offering.id}`;

  return (
    <section className="mx-auto max-w-5xl px-4 py-12 sm:px-6">
      <Link href="/offerings" className="focus-ring mb-6 inline-flex rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-sm font-extrabold text-[#26231F]">
        ← Back to Offerings
      </Link>

      <article className="deed-card overflow-hidden">
        {offering.media_url ? (
          <div className="h-80 bg-cover bg-center" style={{ backgroundImage: `url(${offering.media_url})` }} />
        ) : (
          <div className="h-72 bg-[radial-gradient(circle_at_30%_15%,rgba(244,199,107,0.55),transparent_34%),linear-gradient(135deg,#FFF4DC,#F8EFE0)]" />
        )}
        <div className="p-6 sm:p-8">
          <div className="mb-4 flex flex-wrap gap-2">
            <span className="rounded-full bg-[#FFF4DC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
              {formatOfferingType(offering.offering_type)}
            </span>
            {offering.theme_name ? (
              <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
                {offering.theme_name}
              </span>
            ) : null}
          </div>
          <p className="text-sm font-extrabold text-[#26231F]">{author}</p>
          <h1 className="mt-3 font-[var(--font-heading)] text-4xl font-semibold leading-tight sm:text-5xl">{offering.title}</h1>
          <p className="mt-6 whitespace-pre-line leading-8 text-[#5F5548]">{offering.body}</p>
          {offering.takeaway ? (
            <div className="mt-7 rounded-3xl border border-[rgba(217,164,65,0.20)] bg-[#FFF8EA] p-5">
              <p className="text-xs font-extrabold uppercase tracking-[0.18em] text-[#8D681D]">Small deed others can try</p>
              <p className="mt-2 font-bold leading-7 text-[#5F5548]">{offering.takeaway}</p>
            </div>
          ) : null}

          <div className="mt-7">
            <ShareButton title={offering.title} text={offering.body ? offering.body.slice(0, 120) : "A Deedlight Offering"} url={shareUrl} label="Share this Offering" />
          </div>
        </div>
      </article>

      <div className="deed-card mt-6 p-6">
        <h2 className="font-[var(--font-heading)] text-2xl font-semibold">This light inspired</h2>
        <div className="mt-4 grid gap-3 sm:grid-cols-4">
          <Stat icon={<Sparkles className="h-5 w-5" />} label="Blessed" value={offering.bless_count} />
          <Stat icon={<Heart className="h-5 w-5" />} label="Inspired" value={offering.inspired_count} />
          <Stat icon={<CheckCircle2 className="h-5 w-5" />} label="Did too" value={offering.carried_forward_count} />
          <Stat icon={<MessageCircle className="h-5 w-5" />} label="Reflections" value={offering.reflection_count} />
        </div>

        <div className="mt-6 rounded-3xl border border-[rgba(217,164,65,0.20)] bg-[#FFFDF7] p-5">
          <p className="mb-3 text-sm font-bold leading-7 text-[#7C715F]">
            React to this Offering only if it genuinely blesses, inspires, or invites you to carry the deed forward.
          </p>
          <ReactionButtons
            offeringId={offering.id}
            initialCounts={{
              bless_count: offering.bless_count || 0,
              inspired_count: offering.inspired_count || 0,
              carried_forward_count: offering.carried_forward_count || 0
            }}
          />
        </div>

        <ReportOfferingForm offeringId={offering.id} />
      </div>
    </section>
  );
}

function Stat({ label, value, icon }: { label: string; value: number; icon: ReactNode }) {
  return (
    <div className="rounded-3xl bg-[#FFF8EA] p-5 text-center">
      <div className="mx-auto mb-2 flex h-9 w-9 items-center justify-center rounded-full bg-[#FFF4DC] text-[#8D681D]">{icon}</div>
      <p className="font-[var(--font-heading)] text-3xl font-semibold">{value}</p>
      <p className="text-xs font-extrabold uppercase tracking-[0.18em] text-[#8D681D]">{label}</p>
    </div>
  );
}

function formatOfferingType(value: string) {
  return value
    .split("_")
    .map((word) => word[0]?.toUpperCase() + word.slice(1))
    .join(" ");
}
