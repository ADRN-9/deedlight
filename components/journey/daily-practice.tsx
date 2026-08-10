import { getMyDailyDeedPractice } from "@/lib/data/daily-habits";

type DailyPracticeProps = {
  userId: string;
};

function formatDailyDate(value?: string | null) {
  if (!value) return "Daily Light";

  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  }).format(new Date(`${value}T00:00:00Z`));
}

export async function DailyPractice({ userId }: DailyPracticeProps) {
  const practice = await getMyDailyDeedPractice(userId, 14);

  return (
    <section className="mt-10">
      <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p className="text-xs font-extrabold uppercase tracking-[0.32em] text-[#8D681D]">
            Daily practice
          </p>
          <h2 className="mt-2 font-[var(--font-heading)] text-4xl font-semibold">
            Your gentle rhythm
          </h2>
          <p className="mt-2 max-w-2xl text-sm leading-7 text-[#5F5548]">
            A private record of Daily Lights you marked as lived. There are no
            streaks to protect and nothing resets when life gets busy.
          </p>
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="rounded-3xl bg-[#FFF8EA] px-5 py-4">
            <p className="font-[var(--font-heading)] text-4xl font-semibold">
              {practice.recentCount}
            </p>
            <p className="mt-1 text-xs font-extrabold uppercase tracking-[0.18em] text-[#8D681D]">
              Last 7 days
            </p>
          </div>
          <div className="rounded-3xl bg-[#FFF8EA] px-5 py-4">
            <p className="font-[var(--font-heading)] text-4xl font-semibold">
              {practice.total}
            </p>
            <p className="mt-1 text-xs font-extrabold uppercase tracking-[0.18em] text-[#8D681D]">
              {practice.total === 1 ? "Light carried" : "Lights carried"}
            </p>
          </div>
        </div>
      </div>

      <div className="mt-4 rounded-3xl border border-[rgba(217,164,65,0.20)] bg-white px-5 py-4 text-sm leading-7 text-[#5F5548]">
        {practice.lastCarriedDate ? (
          <>
            Last carried: <strong>{formatDailyDate(practice.lastCarriedDate)}</strong>.
            {practice.recentCount === 0
              ? " Your rhythm can begin again whenever a deed feels true."
              : " Keep returning when it feels meaningful."}
          </>
        ) : (
          "Complete a Daily deed when it genuinely becomes part of your day. Your rhythm can start at any time."
        )}
      </div>

      <div className="mt-5 space-y-4">
        {practice.items.length ? (
          practice.items.map((item) => (
            <article key={item.id} className="deed-card p-5">
              <div className="flex flex-wrap items-center gap-2">
                <span className="rounded-full bg-emerald-50 px-3 py-1 text-xs font-extrabold uppercase tracking-[0.16em] text-emerald-800">
                  Carried forward
                </span>
                <span className="text-xs font-bold text-[#7C715F]">
                  {formatDailyDate(item.daily_light?.scheduled_date)}
                </span>
                {item.daily_light?.theme ? (
                  <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
                    {item.daily_light.theme}
                  </span>
                ) : null}
              </div>

              <h3 className="mt-3 font-[var(--font-heading)] text-2xl font-semibold">
                {item.daily_light?.title || "Daily Light"}
              </h3>
            </article>
          ))
        ) : (
          <div className="deed-card p-8 text-center">
            <h3 className="font-[var(--font-heading)] text-3xl font-semibold">
              No Daily Lights carried yet.
            </h3>
            <p className="mt-2 text-[#5F5548]">
              When you genuinely do a Daily deed, mark it on Today and it will
              appear here.
            </p>
          </div>
        )}
      </div>
    </section>
  );
}
