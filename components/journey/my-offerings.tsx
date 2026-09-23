import Link from "next/link";
import { OfferingOwnerMenu } from "@/components/offerings/offering-owner-menu";
import type { AdminOffering } from "@/lib/types";

type MyOfferingFilter = "all" | "published" | "review" | "attention" | "removed";

type MyOfferingsProps = {
  offerings: AdminOffering[];
  filter?: string;
};

const FILTERS: Array<{ value: MyOfferingFilter; label: string }> = [
  { value: "all", label: "All" },
  { value: "published", label: "Published" },
  { value: "review", label: "In review" },
  { value: "attention", label: "Needs attention" },
  { value: "removed", label: "Removed" },
];

function normalizeFilter(value?: string): MyOfferingFilter {
  return FILTERS.some((item) => item.value === value)
    ? (value as MyOfferingFilter)
    : "all";
}

function isOwnerRemoved(offering: AdminOffering) {
  return Boolean(offering.owner_removed_at);
}

function matchesFilter(offering: AdminOffering, filter: MyOfferingFilter) {
  if (filter === "all") return true;
  if (filter === "removed") return isOwnerRemoved(offering);
  if (isOwnerRemoved(offering)) return false;
  if (filter === "published") return offering.status === "approved";
  if (filter === "review") return offering.status === "pending";

  return ["draft", "needs_edit", "rejected", "hidden"].includes(
    offering.status,
  );
}

function statusLabel(offering: AdminOffering) {
  if (isOwnerRemoved(offering)) return "Removed by you";

  const labels: Record<AdminOffering["status"], string> = {
    draft: "Draft",
    pending: "In review",
    approved: "Published",
    rejected: "Not approved",
    needs_edit: "Needs edit",
    hidden: "Hidden by moderation",
  };

  return labels[offering.status];
}

function statusClass(offering: AdminOffering) {
  if (isOwnerRemoved(offering)) return "bg-stone-100 text-stone-700";
  if (offering.status === "approved") return "bg-emerald-50 text-emerald-800";
  if (offering.status === "pending") return "bg-sky-50 text-sky-800";
  if (offering.status === "needs_edit") return "bg-amber-50 text-amber-900";
  if (offering.status === "rejected" || offering.status === "hidden") {
    return "bg-red-50 text-red-800";
  }
  return "bg-[#FFF8EA] text-[#8D681D]";
}

function formatType(value: string) {
  return value
    .split("_")
    .map((word) => word[0]?.toUpperCase() + word.slice(1))
    .join(" ");
}

export function MyOfferings({ offerings, filter: rawFilter }: MyOfferingsProps) {
  const filter = normalizeFilter(rawFilter);
  const visible = offerings.filter((item) => matchesFilter(item, filter));

  return (
    <section id="my-offerings" className="mt-10 scroll-mt-24">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-extrabold uppercase tracking-[0.32em] text-[#8D681D]">
            My Offerings
          </p>
          <h2 className="mt-2 font-[var(--font-heading)] text-4xl font-semibold">
            Manage what you shared.
          </h2>
          <p className="mt-2 max-w-2xl text-sm leading-7 text-[#5F5548]">
            Edit, remove, restore, and follow moderation status from one private workspace. Your controls never reveal anonymous authorship publicly.
          </p>
        </div>
        <Link
          href="/offerings/new"
          className="focus-ring rounded-full bg-[#D9A441] px-5 py-3 text-center text-sm font-extrabold text-[#26231F] shadow-[0_10px_22px_rgba(217,164,65,0.22)]"
        >
          Share another Offering
        </Link>
      </div>

      <nav aria-label="Filter your Offerings" className="mt-5 flex flex-wrap gap-2">
        {FILTERS.map((item) => {
          const active = item.value === filter;
          const href =
            item.value === "all"
              ? "/journey#my-offerings"
              : `/journey?offering_view=${item.value}#my-offerings`;

          return (
            <Link
              key={item.value}
              href={href}
              aria-current={active ? "page" : undefined}
              className={[
                "focus-ring rounded-full border px-4 py-2 text-xs font-extrabold transition",
                active
                  ? "border-[#D9A441] bg-[#FFF4DC] text-[#6F4F12]"
                  : "border-[rgba(217,164,65,0.24)] bg-white text-[#5F5548] hover:bg-[#FFF8EA]",
              ].join(" ")}
            >
              {item.label}
            </Link>
          );
        })}
      </nav>

      <div className="mt-5 space-y-4">
        {visible.length ? (
          visible.map((item) => {
            const removedByOwner = isOwnerRemoved(item);
            const moderatorHidden = item.status === "hidden" && !removedByOwner;
            const canEdit = item.status !== "rejected" && !moderatorHidden;
            const publicNow = item.status === "approved" && !removedByOwner;
            const lightActions =
              Number(item.bless_count || 0) +
              Number(item.inspired_count || 0) +
              Number(item.carried_forward_count || 0);

            return (
              <article key={item.id} className="deed-card p-5 sm:p-6">
                <div className="flex items-start justify-between gap-4">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap gap-2">
                      <span
                        className={`rounded-full px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] ${statusClass(item)}`}
                      >
                        {statusLabel(item)}
                      </span>
                      <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
                        {formatType(item.offering_type)}
                      </span>
                      {item.is_anonymous ? (
                        <span className="rounded-full bg-stone-100 px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-stone-700">
                          Anonymous Light
                        </span>
                      ) : null}
                    </div>

                    <h3 className="mt-3 font-[var(--font-heading)] text-2xl font-semibold text-[#26231F]">
                      {item.title}
                    </h3>

                    <p className="mt-2 text-sm leading-7 text-[#5F5548]">
                      {lightActions} light {lightActions === 1 ? "action" : "actions"} received
                      {item.reflection_count
                        ? ` · ${item.reflection_count} ${item.reflection_count === 1 ? "reflection" : "reflections"}`
                        : ""}
                    </p>

                    {item.moderation_note && ["needs_edit", "rejected", "hidden"].includes(item.status) ? (
                      <div className="mt-4 rounded-2xl border border-amber-100 bg-amber-50 p-4 text-sm leading-6 text-amber-950">
                        <span className="font-extrabold">Moderation note:</span>{" "}
                        {item.moderation_note}
                      </div>
                    ) : null}

                    {moderatorHidden ? (
                      <p className="mt-3 text-xs font-bold leading-5 text-red-800">
                        Hidden by moderation. Member controls cannot restore or bypass this state.
                      </p>
                    ) : removedByOwner ? (
                      <p className="mt-3 text-xs font-bold leading-5 text-[#7C715F]">
                        Removed from public discovery. Restore sends it back to review.
                      </p>
                    ) : item.status === "pending" ? (
                      <p className="mt-3 text-xs font-bold leading-5 text-[#7C715F]">
                        In review. You may still refine it; saving again keeps it in review.
                      </p>
                    ) : null}

                    <div className="mt-4 flex flex-wrap gap-2">
                      {publicNow ? (
                        <Link
                          href={`/offerings/${item.id}`}
                          className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-4 py-2 text-xs font-extrabold text-[#4B4034] hover:bg-[#FFF8EA]"
                        >
                          View public Offering
                        </Link>
                      ) : null}

                      {canEdit ? (
                        <Link
                          href={`/offerings/${item.id}/edit`}
                          className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-4 py-2 text-xs font-extrabold text-[#4B4034] hover:bg-[#FFF8EA]"
                        >
                          Edit
                        </Link>
                      ) : null}
                    </div>
                  </div>

                  <OfferingOwnerMenu offering={item} />
                </div>
              </article>
            );
          })
        ) : (
          <div className="deed-card p-8 text-center">
            <h3 className="font-[var(--font-heading)] text-3xl font-semibold">
              {offerings.length ? "No Offerings in this view." : "No Offerings yet."}
            </h3>
            <p className="mx-auto mt-2 max-w-xl text-sm leading-7 text-[#5F5548]">
              {offerings.length
                ? "Choose another filter to review the rest of your Offerings."
                : "When you share an Offering, its review status and owner controls will appear here."}
            </p>
          </div>
        )}
      </div>
    </section>
  );
}
