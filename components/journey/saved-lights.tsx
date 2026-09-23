import Link from "next/link";
import { unsaveDailyLightAction } from "@/app/actions/saved-lights";
import { OfferingSaveButton } from "@/components/offerings/offering-save-button";
import { OfferingShareButton } from "@/components/offerings/offering-share-button";
import {
  getMySavedDailyLights,
  getMySavedOfferings,
} from "@/lib/data/saved-lights";

type SavedLightsProps = {
  userId: string;
};

function formatDate(value?: string | null) {
  if (!value) return "Daily Light";

  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  }).format(new Date(`${value}T00:00:00Z`));
}

function formatOfferingType(value: string) {
  return value
    .split("_")
    .map((word) => word[0]?.toUpperCase() + word.slice(1))
    .join(" ");
}

export async function SavedLights({ userId }: SavedLightsProps) {
  const [savedOfferings, savedDailyLights] = await Promise.all([
    getMySavedOfferings(userId, 12),
    getMySavedDailyLights(userId, 12),
  ]);

  const total = savedOfferings.length + savedDailyLights.length;

  return (
    <section className="mt-10">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-extrabold uppercase tracking-[0.32em] text-[#8D681D]">
            Saved Lights
          </p>
          <h2 className="mt-2 font-[var(--font-heading)] text-4xl font-semibold">
            Keep a few lights close.
          </h2>
          <p className="mt-2 max-w-2xl text-sm leading-7 text-[#5F5548]">
            Saved Daily Lights and Offerings are private to your Journey. Saving never affects rankings, public profiles, or community totals.
          </p>
        </div>

        <div className="rounded-full bg-[#FFF8EA] px-4 py-2 text-xs font-extrabold uppercase tracking-[0.18em] text-[#8D681D]">
          {total} saved
        </div>
      </div>

      {savedOfferings.length ? (
        <div className="mt-6">
          <p className="text-xs font-extrabold uppercase tracking-[0.16em] text-[#8D681D]">
            Saved Offerings
          </p>
          <div className="mt-3 grid gap-4 md:grid-cols-2">
            {savedOfferings.map((item) => (
              <article key={item.id} className="deed-card p-5">
                <div className="flex flex-wrap gap-2">
                  <span className="rounded-full bg-emerald-50 px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-emerald-800">
                    Saved privately
                  </span>
                  <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
                    {formatOfferingType(item.offering.offering_type)}
                  </span>
                </div>

                <Link
                  href={`/offerings/${item.offering.id}`}
                  className="focus-ring mt-3 block rounded-xl"
                >
                  <h3 className="font-[var(--font-heading)] text-2xl font-semibold text-[#26231F] hover:text-[#8D681D]">
                    {item.offering.title}
                  </h3>
                </Link>

                <p className="mt-2 line-clamp-3 text-sm leading-7 text-[#5F5548]">
                  {item.offering.body}
                </p>

                <div className="mt-4 flex flex-wrap items-start gap-2">
                  <OfferingSaveButton
                    offeringId={item.offering.id}
                    signedIn
                    initialSaved
                    compact
                  />
                  <OfferingShareButton
                    offeringId={item.offering.id}
                    title={item.offering.title}
                    text={item.offering.body}
                    compact
                  />
                </div>
              </article>
            ))}
          </div>
        </div>
      ) : null}

      {savedDailyLights.length ? (
        <div className="mt-6">
          <p className="text-xs font-extrabold uppercase tracking-[0.16em] text-[#8D681D]">
            Saved Daily Lights
          </p>
          <div className="mt-3 grid gap-4 md:grid-cols-2">
            {savedDailyLights.map((item) => (
              <article key={item.id} className="deed-card p-5">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
                    Saved privately
                  </span>
                  <span className="text-xs font-bold text-[#7C715F]">
                    {formatDate(item.daily_light.scheduled_date)}
                  </span>
                  {item.daily_light.theme ? (
                    <span className="rounded-full bg-white px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
                      {item.daily_light.theme}
                    </span>
                  ) : null}
                </div>

                <h3 className="mt-3 font-[var(--font-heading)] text-2xl font-semibold">
                  {item.daily_light.title || "Daily Light"}
                </h3>

                {item.daily_light.summary ? (
                  <p className="mt-2 text-sm leading-7 text-[#5F5548]">
                    {item.daily_light.summary}
                  </p>
                ) : null}

                {item.daily_light.small_deed ? (
                  <p className="mt-4 rounded-2xl bg-[#FFF8EA] p-4 text-sm font-bold leading-6 text-[#4B4034]">
                    {item.daily_light.small_deed}
                  </p>
                ) : null}

                <form action={unsaveDailyLightAction} className="mt-4">
                  <input type="hidden" name="daily_light_id" value={item.daily_light_id} />
                  <input type="hidden" name="return_to" value="/journey" />
                  <button
                    type="submit"
                    className="rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-4 py-2 text-xs font-extrabold text-[#4B4034] transition hover:bg-[#FFF8EA] active:scale-95"
                  >
                    Remove from Saved Lights
                  </button>
                </form>
              </article>
            ))}
          </div>
        </div>
      ) : null}

      {!total ? (
        <div className="deed-card mt-5 p-8 text-center">
          <h3 className="font-[var(--font-heading)] text-3xl font-semibold">
            No Saved Lights yet.
          </h3>
          <p className="mx-auto mt-2 max-w-xl text-[#5F5548]">
            Save a Daily Light from Today or bookmark an Offering you want to revisit.
          </p>
        </div>
      ) : null}
    </section>
  );
}
