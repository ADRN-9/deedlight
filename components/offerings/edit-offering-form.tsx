import Link from "next/link";
import { updateOwnOfferingAction } from "@/app/offerings/owner-actions";
import { PendingOwnerActionButton } from "@/components/offerings/pending-owner-action-button";
import type { AdminOffering } from "@/lib/types";

const OFFERING_TYPES = [
  ["good_deed", "Good Deed"],
  ["goodness_invitation", "Goodness Invitation"],
  ["gratitude", "Gratitude"],
  ["beauty_reminder", "Beauty Reminder"],
  ["quiet_goodness", "Quiet Goodness"],
  ["community_need", "Community Need"],
] as const;

type EditOfferingFormProps = {
  offering: AdminOffering;
};

export function EditOfferingForm({ offering }: EditOfferingFormProps) {
  const wasPublic = offering.status === "approved";
  const wasRemoved = Boolean(offering.owner_removed_at);

  return (
    <form action={updateOwnOfferingAction} className="space-y-6">
      <input type="hidden" name="offering_id" value={offering.id} />

      <div className="rounded-3xl border border-[rgba(217,164,65,0.25)] bg-[#FFF8EA] p-5 text-sm leading-7 text-[#5F5548]">
        <p className="font-extrabold text-[#26231F]">Moderation stays in place.</p>
        <p className="mt-1">
          {wasPublic
            ? "Saving edits will take the current public version out of discovery and send the edited Offering back to review."
            : wasRemoved
              ? "Saving edits will restore this Offering into the review queue. It will not become public until approved."
              : "Saving edits sends this Offering to review. It will not become public until approved."}
        </p>
        <p className="mt-2">
          Existing Bless, Inspired, and Did too activity stays attached to the Offering. Anonymous mode never exposes your account identity through the public Offering projection.
        </p>
      </div>

      <label className="block">
        <span className="text-sm font-extrabold text-[#4B4034]">Offering type</span>
        <select
          name="offering_type"
          defaultValue={offering.offering_type}
          className="mt-2 w-full rounded-2xl border border-[#ead7ad] bg-white px-4 py-3 font-bold text-[#26231F] outline-none focus:border-[#D9A441]"
        >
          {OFFERING_TYPES.map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </label>

      <label className="block">
        <span className="text-sm font-extrabold text-[#4B4034]">Title</span>
        <input
          name="title"
          defaultValue={offering.title}
          required
          minLength={4}
          maxLength={120}
          className="mt-2 w-full rounded-2xl border border-[#ead7ad] bg-white px-4 py-3 outline-none focus:border-[#D9A441]"
        />
      </label>

      <label className="block">
        <span className="text-sm font-extrabold text-[#4B4034]">Offering</span>
        <textarea
          name="body"
          defaultValue={offering.body}
          required
          minLength={20}
          maxLength={5000}
          className="mt-2 min-h-48 w-full rounded-2xl border border-[#ead7ad] bg-white px-4 py-3 leading-7 outline-none focus:border-[#D9A441]"
        />
      </label>

      <label className="block">
        <span className="text-sm font-extrabold text-[#4B4034]">Small deed others can try</span>
        <textarea
          name="takeaway"
          defaultValue={offering.takeaway ?? ""}
          maxLength={500}
          className="mt-2 min-h-28 w-full rounded-2xl border border-[#ead7ad] bg-white px-4 py-3 leading-7 outline-none focus:border-[#D9A441]"
        />
      </label>

      <label className="block">
        <span className="text-sm font-extrabold text-[#4B4034]">Optional image/video URL</span>
        <input
          name="media_url"
          type="url"
          defaultValue={offering.media_url ?? ""}
          maxLength={1000}
          placeholder="https://…"
          className="mt-2 w-full rounded-2xl border border-[#ead7ad] bg-white px-4 py-3 outline-none focus:border-[#D9A441]"
        />
      </label>

      <div className="grid gap-3 md:grid-cols-2">
        <label className="flex items-start gap-3 rounded-2xl border border-[#ead7ad] bg-[#FFF8EA] p-4">
          <input
            type="checkbox"
            name="is_anonymous"
            defaultChecked={offering.is_anonymous}
            className="mt-1"
          />
          <span>
            <span className="block font-extrabold text-[#26231F]">Post as Anonymous Light</span>
            <span className="text-sm leading-6 text-[#7C715F]">
              Your public Offering does not expose your account ID, name, or username.
            </span>
          </span>
        </label>

        <label className="flex items-start gap-3 rounded-2xl border border-[#ead7ad] bg-[#FFF8EA] p-4">
          <input
            type="checkbox"
            name="allow_reflections"
            defaultChecked={offering.allow_reflections !== false}
            className="mt-1"
          />
          <span>
            <span className="block font-extrabold text-[#26231F]">Allow Reflections</span>
            <span className="text-sm leading-6 text-[#7C715F]">
              Let members leave kind reflections after the Offering is approved.
            </span>
          </span>
        </label>
      </div>

      <div className="flex flex-col-reverse gap-3 border-t border-[rgba(217,164,65,0.18)] pt-6 sm:flex-row sm:items-center sm:justify-between">
        <Link
          href="/journey#my-offerings"
          className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-6 py-3 text-center text-sm font-extrabold text-[#4B4034] hover:bg-[#FFF8EA]"
        >
          Cancel
        </Link>

        <PendingOwnerActionButton
          pendingText="Saving & sending to review…"
          className="focus-ring rounded-full bg-[#D9A441] px-7 py-3 text-sm font-extrabold text-[#26231F] shadow-[0_12px_28px_rgba(217,164,65,0.25)] transition hover:bg-[#e1ae47] disabled:cursor-wait disabled:opacity-65"
        >
          Save edits & send to review
        </PendingOwnerActionButton>
      </div>
    </form>
  );
}
