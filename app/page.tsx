import { ArrowRight, Flame, HandHeart, Sparkles, type LucideIcon } from "lucide-react";
import { DailyLightCard } from "@/components/daily-light/daily-light-card";
import { OfferingCard } from "@/components/offerings/offering-card";
import { PrimaryLink, SecondaryLink } from "@/components/ui/button-link";
import { getTodayPost } from "@/lib/data/daily-posts";
import { getApprovedOfferings } from "@/lib/data/offerings";

export default async function HomePage() {
  const [today, offerings] = await Promise.all([getTodayPost(), getApprovedOfferings(2)]);

  return (
    <>
      <section className="mx-auto grid max-w-6xl items-center gap-12 px-4 py-16 sm:px-6 lg:grid-cols-[1fr_0.9fr] lg:py-24">
        <div>
          <div className="mb-6 inline-flex items-center gap-2 rounded-full border border-[rgba(217,164,65,0.22)] bg-white/60 px-4 py-2 text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
            <Flame className="h-4 w-4" fill="currentColor" />
            Where good deeds become light
          </div>
          <h1 className="font-[var(--font-heading)] text-5xl font-semibold leading-[0.95] tracking-tight text-[#26231F] sm:text-7xl">
            Goodness does not prevail by accident.
          </h1>
          <p className="mt-7 max-w-2xl text-lg leading-9 text-[#5F5548]">
            Deedlight is a daily social space where good deeds become light — shared, blessed, and carried forward by people who still believe goodness is worth choosing.
          </p>
          <div className="mt-8 flex flex-col gap-3 sm:flex-row">
            <PrimaryLink href="/today">See Today’s Deedlight <ArrowRight className="ml-2 h-4 w-4" /></PrimaryLink>
            <SecondaryLink href="/offerings/new">Share an Offering</SecondaryLink>
          </div>
        </div>
        <div className="relative">
          <div className="absolute -inset-10 -z-10 rounded-full bg-[#F4C76B]/20 blur-3xl" />
          <DailyLightCard post={today} compact />
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
        <div className="grid gap-5 md:grid-cols-3">
          {steps.map(({ Icon, title, body }) => (
            <div key={title} className="deed-card p-6">
              <Icon className="mb-5 h-8 w-8 text-[#D9A441]" />
              <h2 className="font-[var(--font-heading)] text-2xl font-semibold">{title}</h2>
              <p className="mt-3 leading-7 text-[#7C715F]">{body}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
        <div className="mb-8 flex items-end justify-between gap-4">
          <div>
            <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Rising today</p>
            <h2 className="mt-2 font-[var(--font-heading)] text-4xl font-semibold">Goodness rising</h2>
          </div>
          <SecondaryLink href="/offerings" className="hidden sm:inline-flex">See all</SecondaryLink>
        </div>
        <div className="grid gap-6 md:grid-cols-2">
          {offerings.map((offering) => <OfferingCard key={offering.id} offering={offering} />)}
        </div>
      </section>
    </>
  );
}


type Step = { Icon: LucideIcon; title: string; body: string };

const steps: Step[] = [
  { Icon: Sparkles, title: "Receive Light", body: "Begin with one daily reflection and one small deed." },
  { Icon: HandHeart, title: "Share an Offering", body: "Share goodness you practiced, witnessed, or invite others to try." },
  { Icon: Flame, title: "Carry It Forward", body: "Bless what inspires you and help good deeds rise." }
];
