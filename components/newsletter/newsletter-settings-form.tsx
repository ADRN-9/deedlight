"use client";

import { useState } from "react";
import { updateNewsletterPreferenceAction } from "@/app/settings/newsletter/actions";
import { PendingActionButton } from "@/components/growth/pending-action-button";

export function NewsletterSettingsForm({
  initialEnabled,
  isSuspended,
}: {
  initialEnabled: boolean;
  isSuspended: boolean;
}) {
  const [enabled, setEnabled] = useState(initialEnabled);
  const cannotEnable = isSuspended && !enabled;

  return (
    <form
      action={updateNewsletterPreferenceAction}
      className="mt-8"
    >
      <label className="flex items-start gap-4 rounded-3xl border border-[rgba(217,164,65,0.22)] bg-[#FFF8EA] p-5">
        <input
          className="mt-1 h-5 w-5 accent-[#D9A441]"
          type="checkbox"
          name="weekly_enabled"
          checked={enabled}
          disabled={cannotEnable}
          onChange={(event) => setEnabled(event.target.checked)}
        />

        <span>
          <span className="block font-extrabold text-[#26231F]">
            Keep my Weekly Goodness newsletter preference on
          </span>
          <span className="mt-1 block text-sm leading-7 text-[#6B6054]">
            Off by default. This private preference records your
            explicit consent. Newsletter delivery is not active
            yet, and you can turn the preference off at any time.
          </span>
        </span>
      </label>

      {isSuspended ? (
        <p className="mt-4 rounded-2xl bg-[#FFF4DC] p-4 text-sm font-bold leading-7 text-[#7A4A33]">
          While community access is suspended, an enabled
          preference may be turned off, but a new opt-in cannot
          be enabled.
        </p>
      ) : null}

      <div className="mt-5 flex items-center gap-3">
        <PendingActionButton
          idleLabel="Save newsletter preference"
          pendingLabel="Saving preference…"
          className="focus-ring rounded-full bg-[#D9A441] px-6 py-3 text-sm font-extrabold text-[#26231F] shadow-[0_12px_25px_rgba(217,164,65,0.30)] disabled:cursor-not-allowed disabled:opacity-60"
        />

        <span className="rounded-full bg-white px-4 py-2 text-xs font-extrabold text-[#725A2D]">
          {enabled ? "Preference on" : "Preference off"}
        </span>
      </div>
    </form>
  );
}
