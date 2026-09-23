"use client";

import { Check, Share2 } from "lucide-react";
import { useState } from "react";

type OfferingShareButtonProps = {
  offeringId: string;
  title: string;
  text?: string;
  compact?: boolean;
};

async function copyText(value: string) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(value);
    return;
  }

  const textarea = document.createElement("textarea");
  textarea.value = value;
  textarea.setAttribute("readonly", "");
  textarea.style.position = "fixed";
  textarea.style.opacity = "0";
  document.body.appendChild(textarea);
  textarea.select();
  document.execCommand("copy");
  document.body.removeChild(textarea);
}

export function OfferingShareButton({
  offeringId,
  title,
  text = "A Deedlight Offering",
  compact = false,
}: OfferingShareButtonProps) {
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState(false);

  async function share() {
    if (busy) return;
    setBusy(true);
    setCopied(false);

    const url = `${window.location.origin}/offerings/${encodeURIComponent(offeringId)}`;

    try {
      if (typeof navigator.share === "function") {
        await navigator.share({
          title,
          text: text.slice(0, 160),
          url,
        });
      } else {
        await copyText(url);
        setCopied(true);
      }
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") {
        return;
      }

      try {
        await copyText(url);
        setCopied(true);
      } catch (copyError) {
        console.error("[OfferingShareButton] share failed", error, copyError);
      }
    } finally {
      setBusy(false);
    }
  }

  const Icon = copied ? Check : Share2;

  return (
    <button
      type="button"
      onClick={share}
      disabled={busy}
      aria-busy={busy}
      className={[
        "focus-ring inline-flex items-center justify-center gap-2 rounded-full border border-[rgba(217,164,65,0.30)] bg-white font-extrabold text-[#4B4034] transition hover:bg-[#FFF8EA] active:scale-[0.98] disabled:cursor-wait disabled:opacity-65",
        compact ? "px-3 py-2 text-xs" : "px-5 py-3 text-sm",
      ].join(" ")}
    >
      <Icon className="h-4 w-4" />
      <span>{busy ? "Sharing…" : copied ? "Link copied" : "Share"}</span>
    </button>
  );
}
