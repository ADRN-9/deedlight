// components/share-button.tsx
"use client";

import { useState } from "react";

type ShareButtonProps = {
  title: string;
  text: string;
  url: string;
  label?: string;
};

type WebSharePayload = {
  title?: string;
  text?: string;
  url?: string;
};

type BrowserNavigator = Navigator & {
  share?: (data: WebSharePayload) => Promise<void>;
  clipboard?: {
    writeText: (text: string) => Promise<void>;
  };
};

async function copyTextFallback(value: string) {
  const textarea = document.createElement("textarea");
  textarea.value = value;
  textarea.setAttribute("readonly", "true");
  textarea.style.position = "fixed";
  textarea.style.left = "-9999px";

  document.body.appendChild(textarea);
  textarea.select();

  const copied = document.execCommand("copy");
  document.body.removeChild(textarea);

  if (!copied) {
    throw new Error("Clipboard copy failed.");
  }
}

export function ShareButton({
  title,
  text,
  url,
  label = "Share",
}: ShareButtonProps) {
  const [state, setState] = useState<"idle" | "copied" | "failed">("idle");

  async function handleShare() {
    const payload: WebSharePayload = { title, text, url };

    try {
      const nav =
        typeof window !== "undefined"
          ? (window.navigator as BrowserNavigator)
          : null;

      if (nav?.share) {
        await nav.share(payload);
        return;
      }

      if (nav?.clipboard?.writeText) {
        await nav.clipboard.writeText(url);
      } else {
        await copyTextFallback(url);
      }

      setState("copied");
      window.setTimeout(() => setState("idle"), 2200);
    } catch {
      setState("failed");
      window.setTimeout(() => setState("idle"), 2200);
    }
  }

  return (
    <button
      type="button"
      onClick={handleShare}
      className="rounded-full border border-amber-200 bg-white px-5 py-3 text-sm font-black text-stone-900 shadow-sm transition active:scale-95"
    >
      {state === "copied"
        ? "Link copied"
        : state === "failed"
          ? "Could not share"
          : label}
    </button>
  );
}