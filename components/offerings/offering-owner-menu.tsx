import Link from "next/link";
import { MoreHorizontal, PencilLine, RotateCcw, Trash2 } from "lucide-react";
import {
  removeOwnOfferingAction,
  restoreOwnOfferingAction,
} from "@/app/offerings/owner-actions";
import { PendingOwnerActionButton } from "@/components/offerings/pending-owner-action-button";
import type { AdminOffering } from "@/lib/types";

type OfferingOwnerMenuProps = {
  offering: Pick<AdminOffering, "id" | "status" | "owner_removed_at">;
};

export function OfferingOwnerMenu({ offering }: OfferingOwnerMenuProps) {
  const removedByOwner = Boolean(offering.owner_removed_at);
  const moderatorHidden = offering.status === "hidden" && !removedByOwner;
  const canEdit = offering.status !== "rejected" && !moderatorHidden;
  const canRemove =
    offering.status !== "rejected" && !removedByOwner && !moderatorHidden;
  const canRestore = offering.status === "hidden" && removedByOwner;

  if (!canEdit && !canRemove && !canRestore) return null;

  return (
    <details className="relative z-20">
      <summary
        aria-label="Manage your Offering"
        className="focus-ring flex h-10 w-10 cursor-pointer list-none items-center justify-center rounded-full border border-[rgba(217,164,65,0.30)] bg-white text-[#5F5548] shadow-sm transition hover:bg-[#FFF8EA] [&::-webkit-details-marker]:hidden"
      >
        <MoreHorizontal className="h-5 w-5" />
      </summary>

      <div className="absolute right-0 mt-2 w-72 overflow-hidden rounded-3xl border border-[rgba(217,164,65,0.24)] bg-white p-2 shadow-[0_22px_60px_rgba(38,35,31,0.18)]">
        <p className="px-3 pb-2 pt-2 text-xs font-extrabold uppercase tracking-[0.16em] text-[#8D681D]">
          Your Offering
        </p>

        {canEdit ? (
          <Link
            href={`/offerings/${offering.id}/edit`}
            className="focus-ring flex w-full items-start gap-3 rounded-2xl px-3 py-3 text-left transition hover:bg-[#FFF8EA]"
          >
            <PencilLine className="mt-0.5 h-4 w-4 shrink-0 text-[#8D681D]" />
            <span>
              <span className="block text-sm font-extrabold text-[#26231F]">
                Edit & resubmit
              </span>
              <span className="mt-0.5 block text-xs leading-5 text-[#7C715F]">
                Changes return to review before becoming public.
              </span>
            </span>
          </Link>
        ) : null}

        {canRestore ? (
          <form action={restoreOwnOfferingAction}>
            <input type="hidden" name="offering_id" value={offering.id} />
            <PendingOwnerActionButton
              pendingText="Restoring…"
              className="focus-ring flex w-full items-start gap-3 rounded-2xl px-3 py-3 text-left transition hover:bg-emerald-50 disabled:cursor-wait disabled:opacity-60"
            >
              <RotateCcw className="mt-0.5 h-4 w-4 shrink-0 text-emerald-700" />
              <span>
                <span className="block text-sm font-extrabold text-[#26231F]">
                  Restore & send to review
                </span>
                <span className="mt-0.5 block text-xs leading-5 text-[#7C715F]">
                  It stays private until moderation approves it again.
                </span>
              </span>
            </PendingOwnerActionButton>
          </form>
        ) : null}

        {canRemove ? (
          <form action={removeOwnOfferingAction}>
            <input type="hidden" name="offering_id" value={offering.id} />
            <PendingOwnerActionButton
              pendingText="Removing…"
              confirmMessage="Remove this Offering from Deedlight? It will disappear from public discovery and can be restored later from your Journey."
              className="focus-ring flex w-full items-start gap-3 rounded-2xl px-3 py-3 text-left transition hover:bg-red-50 disabled:cursor-wait disabled:opacity-60"
            >
              <Trash2 className="mt-0.5 h-4 w-4 shrink-0 text-red-700" />
              <span>
                <span className="block text-sm font-extrabold text-red-800">
                  Remove from Deedlight
                </span>
                <span className="mt-0.5 block text-xs leading-5 text-[#7C715F]">
                  This is a reversible soft removal, not permanent deletion.
                </span>
              </span>
            </PendingOwnerActionButton>
          </form>
        ) : null}
      </div>
    </details>
  );
}
