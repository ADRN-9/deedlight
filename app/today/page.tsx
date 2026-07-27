import type { Metadata } from "next";
import Link from "next/link";
import { DailyReflectionForm } from "@/components/daily-light/daily-reflection-form";
import { ShareButton } from "@/components/share-button";
import { getMyDailyReflection, getPublishedDailyLightForToday } from "@/lib/data/daily-lights";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export const metadata: Metadata = {
  title: "Today’s Deedlight",
  description: "A daily invitation to goodness, beauty, and better deeds.",
  openGraph: {
    title: "Today’s Deedlight",
    description: "A daily invitation to goodness, beauty, and better deeds.",
    url: "/today",
    images: ["/og/deedlight-og.png"]
  },
  twitter: {
    card: "summary_large_image",
    title: "Today’s Deedlight",
    description: "A daily invitation to goodness, beauty, and better deeds.",
    images: ["/og/deedlight-og.png"]
  }
};

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

type FeaturedOffering = {
  id: string;
  title: string;
  body: string | null;
  offering_type: string | null;
  author_name: string | null;
  display_name?: string | null;
};

export default async function TodayPage({ searchParams }: { searchParams?: SearchParams }) {
  const params = searchParams ? await searchParams : {};
  const { light, isFallback } = await getPublishedDailyLightForToday();
  const supabase = await createClient({ allowMissingEnv: true });

  const { data: authData } = supabase ? await supabase.auth.getUser() : { data: { user: null } };
  const user = authData.user;

  const reflection = user && light.id ? await getMyDailyReflection(light.id, user.id) : null;
  let featuredOffering: FeaturedOffering | null = null;

  if (supabase && light.featured_offering_id) {
    const { data } = await supabase
      .from("offerings")
      .select("id,title,body,offering_type,author_name,display_name")
      .eq("id", light.featured_offering_id)
      .eq("status", "approved")
      .maybeSingle();

    featuredOffering = (data as FeaturedOffering | null) ?? null;
  }

  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "https://deedlight.com";
  const shareUrl = `${siteUrl.replace(/\/$/, "")}/today`;

  return (
    <section className="mx-auto max-w-5xl px-4 py-12 sm:px-6 sm:py-16">
      {params.reflected ? (
        <div className="mb-8 rounded-3xl border border-emerald-100 bg-emerald-50 p-5 text-sm font-extrabold text-emerald-900">
          Reflection saved. Thank you for carrying today’s light.
        </div>
      ) : null}

      {params.error ? (
        <div className="mb-8 rounded-3xl border border-red-100 bg-red-50 p-5 text-sm font-extrabold text-red-900">
          {String(params.error)}
        </div>
      ) : null}

      {isFallback ? (
        <div className="mb-8 rounded-3xl border border-[rgba(217,164,65,0.24)] bg-[#FFF4DC] p-5 text-sm font-bold text-[#8D681D]">
          Today’s published Deedlight is not scheduled yet, so the fallback light is showing.
        </div>
      ) : null}

      <div className="text-center">
        <p className="text-xs font-extrabold uppercase tracking-[0.32em] text-[#8D681D]">{light.kicker || "TODAY’S DEEDLIGHT"}</p>
        <h1 className="mx-auto mt-4 max-w-4xl font-[var(--font-heading)] text-5xl font-semibold leading-tight sm:text-7xl">
          {light.title}
        </h1>
      </div>

      <article className="deed-card mx-auto mt-10 max-w-4xl overflow-hidden">
        <div className="h-72 bg-[radial-gradient(circle_at_30%_15%,rgba(244,199,107,0.55),transparent_34%),linear-gradient(135deg,#FFF4DC,#DCE9F5)]" />
        <div className="p-6 sm:p-8">
          {light.theme ? (
            <span className="rounded-full bg-[#FFF4DC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
              {light.theme}
            </span>
          ) : null}

          <h2 className="mt-5 font-[var(--font-heading)] text-4xl font-semibold leading-tight">{light.title}</h2>

          {light.summary ? <p className="mt-5 whitespace-pre-line leading-8 text-[#5F5548]">{light.summary}</p> : null}

          {light.small_deed ? (
            <div className="mt-7 rounded-3xl border border-[rgba(217,164,65,0.20)] bg-[#FFF8EA] p-5">
              <p className="text-xs font-extrabold uppercase tracking-[0.18em] text-[#8D681D]">Today’s small deed</p>
              <p className="mt-2 font-bold leading-7 text-[#26231F]">{light.small_deed}</p>
            </div>
          ) : null}

          {featuredOffering ? (
            <div className="mt-7 rounded-3xl border border-[rgba(217,164,65,0.20)] bg-[#FFFDF7] p-5">
              <p className="text-xs font-extrabold uppercase tracking-[0.18em] text-[#8D681D]">Inspired by the community</p>
              <h3 className="mt-2 font-[var(--font-heading)] text-2xl font-semibold">{featuredOffering.title}</h3>
              {featuredOffering.body ? <p className="mt-2 line-clamp-3 leading-7 text-[#5F5548]">{featuredOffering.body}</p> : null}
              <Link href={`/offerings/${featuredOffering.id}`} className="focus-ring mt-4 inline-flex rounded-full border border-[rgba(217,164,65,0.30)] px-4 py-2 text-sm font-extrabold">
                Open inspiration
              </Link>
            </div>
          ) : null}

          <div className="mt-7 flex flex-col gap-3 sm:flex-row">
            <ShareButton title="Today’s Deedlight" text={light.title} url={shareUrl} label="Share Today’s Deedlight" />
            <Link href="/offerings/new" className="focus-ring inline-flex items-center justify-center rounded-full bg-[#D9A441] px-5 py-3 text-sm font-extrabold text-[#26231F] shadow-[0_12px_25px_rgba(217,164,65,0.30)]">
              Share an Offering
            </Link>
          </div>
        </div>
      </article>

      <div className="mx-auto mt-10 max-w-2xl">
        <DailyReflectionForm dailyLightId={light.id} hasReflected={Boolean(reflection)} isSignedIn={Boolean(user)} prompt={light.reflection_prompt} />
      </div>
    </section>
  );
}
