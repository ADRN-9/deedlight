import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { OfferingCard } from "@/components/offerings/offering-card";
import {
  getPublicProfile,
  getPublicProfileOfferings,
} from "@/lib/data/profiles";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type PageProps = {
  params: Promise<{ username: string }>;
};

export async function generateMetadata({
  params,
}: PageProps): Promise<Metadata> {
  const { username } = await params;
  const profile = await getPublicProfile(username);

  if (!profile) {
    return { title: "Member profile not found" };
  }

  const description =
    profile.bio ||
    `${profile.display_name} shares goodness through Deedlight.`;

  return {
    title: `${profile.display_name} (@${profile.username})`,
    description,
  };
}

export default async function PublicProfilePage({
  params,
}: PageProps) {
  const { username } = await params;
  const profile = await getPublicProfile(username);

  if (!profile) {
    notFound();
  }

  const offerings = await getPublicProfileOfferings(
    profile.username,
    24,
  );

  const memberSince = new Date(
    profile.member_since,
  ).toLocaleDateString("en-US", {
    month: "long",
    year: "numeric",
  });

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6 sm:py-16">
      <div className="deed-card overflow-hidden">
        <div className="bg-[radial-gradient(circle_at_18%_10%,rgba(244,199,107,0.55),transparent_34%),linear-gradient(135deg,#FFF4DC,#F8EFE0)] px-6 py-12 sm:px-10">
          <div className="flex flex-col gap-6 sm:flex-row sm:items-center">
            <div className="flex h-28 w-28 items-center justify-center rounded-full border-4 border-white bg-[#D9A441] font-[var(--font-heading)] text-5xl font-semibold text-[#26231F] shadow-xl">
              {profile.display_name.slice(0, 1).toUpperCase()}
            </div>

            <div>
              <div className="flex flex-wrap items-center gap-2">
                <h1 className="font-[var(--font-heading)] text-5xl font-semibold leading-tight">
                  {profile.display_name}
                </h1>

                {profile.is_verified ? (
                  <span className="rounded-full bg-emerald-100 px-3 py-1 text-xs font-extrabold uppercase tracking-[0.16em] text-emerald-800">
                    Verified
                  </span>
                ) : null}
              </div>

              <p className="mt-2 font-bold text-[#8D681D]">
                @{profile.username}
              </p>

              <p className="mt-3 text-sm font-bold text-[#7C715F]">
                Member since {memberSince}
                {profile.country ? ` · ${profile.country}` : ""}
              </p>
            </div>
          </div>
        </div>

        <div className="p-6 sm:p-10">
          {profile.bio ? (
            <p className="max-w-3xl whitespace-pre-line text-lg leading-8 text-[#5F5548]">
              {profile.bio}
            </p>
          ) : (
            <p className="text-[#7C715F]">
              This member has chosen to let their Offerings speak for
              them.
            </p>
          )}

          {profile.show_contribution_stats ? (
            <div className="mt-8 grid gap-4 sm:grid-cols-4">
              <Stat
                value={profile.published_offering_count ?? 0}
                label="Public Offerings"
              />
              <Stat
                value={profile.total_bless_count ?? 0}
                label="Blessed"
              />
              <Stat
                value={profile.total_inspired_count ?? 0}
                label="Inspired"
              />
              <Stat
                value={profile.total_carried_forward_count ?? 0}
                label="Carried forward"
              />
            </div>
          ) : null}

          <div className="mt-8 rounded-3xl border border-[rgba(217,164,65,0.20)] bg-[#FFF8EA] p-5 text-sm leading-7 text-[#5F5548]">
            Only approved, non-anonymous Offerings appear here.
            Personal daily reflections are private and are never shown
            on profiles.
          </div>
        </div>
      </div>

      <section className="mt-10">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p className="text-xs font-extrabold uppercase tracking-[0.3em] text-[#8D681D]">
              Shared light
            </p>
            <h2 className="mt-2 font-[var(--font-heading)] text-4xl font-semibold">
              Public Offerings
            </h2>
          </div>

          <Link
            className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-6 py-3 text-center text-sm font-extrabold text-[#26231F]"
            href="/offerings"
          >
            Browse all Offerings
          </Link>
        </div>

        {offerings.length ? (
          <div className="mt-6 grid gap-6 md:grid-cols-2">
            {offerings.map((offering) => (
              <OfferingCard
                key={offering.id}
                offering={offering}
              />
            ))}
          </div>
        ) : (
          <div className="deed-card mt-6 p-8 text-center">
            <h3 className="font-[var(--font-heading)] text-3xl font-semibold">
              No public Offerings yet.
            </h3>
          </div>
        )}
      </section>
    </section>
  );
}

function Stat({
  value,
  label,
}: {
  value: number;
  label: string;
}) {
  return (
    <div className="rounded-3xl bg-[#FFF8EA] p-5">
      <p className="font-[var(--font-heading)] text-4xl font-semibold">
        {value}
      </p>
      <p className="mt-1 text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
        {label}
      </p>
    </div>
  );
}
