"use client";

import { Bookmark, Check } from "lucide-react";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type OfferingSaveButtonProps = {
  offeringId: string;
  signedIn: boolean;
  initialSaved: boolean;
  compact?: boolean;
};

export function OfferingSaveButton({
  offeringId,
  signedIn,
  initialSaved,
  compact = false,
}: OfferingSaveButtonProps) {
  const pathname = usePathname();
  const router = useRouter();
  const [saved, setSaved] = useState(initialSaved);
  const [pending, setPending] = useState(false);
  const [feedback, setFeedback] = useState<string | null>(null);

  useEffect(() => {
    setSaved(initialSaved);
  }, [initialSaved]);

  async function toggleSaved() {
    setFeedback(null);

    if (!signedIn) {
      router.push(`/login?next=${encodeURIComponent(pathname || "/offerings")}`);
      return;
    }

    if (pending) return;

    const previous = saved;
    const next = !previous;
    setSaved(next);
    setPending(true);

    try {
      const supabase = createClient();
      const {
        data: { user },
        error: userError,
      } = await supabase.auth.getUser();

      if (userError || !user) {
        throw userError || new Error("Signed-in member could not be confirmed.");
      }

      const response = previous
        ? await supabase
            .from("saved_lights")
            .delete()
            .eq("user_id", user.id)
            .eq("offering_id", offeringId)
        : await supabase.from("saved_lights").insert({
            user_id: user.id,
            offering_id: offeringId,
          });

      if (response.error && !(response.error.code === "23505" && !previous)) {
        throw response.error;
      }

      if (response.error?.code === "23505") {
        setSaved(true);
      }

      setFeedback(previous ? "Removed from Saved Lights" : "Saved privately");
      router.refresh();
    } catch (error) {
      console.error("[OfferingSaveButton] save update failed", error);
      setSaved(previous);
      setFeedback("Save could not be updated. Please try again.");
    } finally {
      setPending(false);
    }
  }

  const Icon = saved ? Check : Bookmark;

  return (
    <div className={compact ? "" : "min-w-[9rem]"}>
      <button
        type="button"
        onClick={toggleSaved}
        disabled={pending}
        aria-pressed={saved}
        aria-busy={pending}
        className={[
          "focus-ring inline-flex items-center justify-center gap-2 rounded-full border font-extrabold transition active:scale-[0.98] disabled:cursor-wait disabled:opacity-65",
          compact ? "px-3 py-2 text-xs" : "px-5 py-3 text-sm",
          saved
            ? "border-emerald-200 bg-emerald-50 text-emerald-900 hover:bg-emerald-100"
            : "border-[rgba(217,164,65,0.30)] bg-white text-[#4B4034] hover:bg-[#FFF8EA]",
        ].join(" ")}
      >
        <Icon className="h-4 w-4" />
        <span>{pending ? "Saving…" : saved ? "Saved" : "Save"}</span>
      </button>

      {feedback ? (
        <p
          aria-live="polite"
          className={[
            "mt-1.5 text-xs font-bold leading-5",
            feedback.includes("could not") ? "text-red-700" : "text-[#7C715F]",
          ].join(" ")}
        >
          {feedback}
        </p>
      ) : null}
    </div>
  );
}
