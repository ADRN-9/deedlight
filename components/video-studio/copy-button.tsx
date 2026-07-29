"use client";

import { useState } from "react";

type CopyButtonProps = {
  value: string;
  label?: string;
  copiedLabel?: string;
};

type BrowserNavigator = Navigator & {
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
    throw new Error("Copy failed.");
  }
}

export function CopyButton({
  value,
  label = "Copy",
  copiedLabel = "Copied",
}: CopyButtonProps) {
  const [state, setState] = useState<"idle" | "copied" | "failed">("idle");

  async function handleCopy() {
    try {
      const nav =
        typeof window !== "undefined"
          ? (window.navigator as BrowserNavigator)
          : null;

      if (nav?.clipboard?.writeText) {
        await nav.clipboard.writeText(value);
      } else {
        await copyTextFallback(value);
      }

      setState("copied");
      window.setTimeout(() => setState("idle"), 1800);
    } catch {
      setState("failed");
      window.setTimeout(() => setState("idle"), 1800);
    }
  }

  return (
    <button
      type="button"
      onClick={handleCopy}
      className="rounded-full border border-amber-200 bg-white px-4 py-2 text-xs font-black text-stone-900 transition active:scale-95"
    >
      {state === "copied" ? copiedLabel : state === "failed" ? "Copy failed" : label}
    </button>
  );
}
