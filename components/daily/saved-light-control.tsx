import Link from "next/link";
import {
  saveDailyLightAction,
  unsaveDailyLightAction,
} from "@/app/actions/saved-lights";
import { createClient } from "@/lib/supabase/server";

type SavedLightControlProps = {
  dailyLightId: string;
  userId: string | null;
  returnTo?: "/today" | "/journey";
};

export async function SavedLightControl({
  dailyLightId,
  userId,
  returnTo = "/today",
}: SavedLightControlProps) {
  if (!dailyLightId) return null;

  if (!userId) {
    return (
      <Link
        href={`/login?next=${encodeURIComponent(returnTo)}`}
        className="rounded-full border border-amber-200 bg-white px-5 py-3 text-center text-sm font-black text-stone-900 shadow-sm transition hover:bg-amber-50 active:scale-95"
      >
        Sign in to save
      </Link>
    );
  }

  const supabase = await createClient({ allowMissingEnv: true });
  let isSaved = false;

  if (supabase) {
    const { data, error } = await supabase
      .from("saved_lights")
      .select("id")
      .eq("user_id", userId)
      .eq("daily_light_id", dailyLightId)
      .maybeSingle();

    if (error) {
      console.error("[SavedLightControl] saved state query failed", error);
    } else {
      isSaved = Boolean(data);
    }
  }

  return (
    <form action={isSaved ? unsaveDailyLightAction : saveDailyLightAction}>
      <input type="hidden" name="daily_light_id" value={dailyLightId} />
      <input type="hidden" name="return_to" value={returnTo} />
      <button
        type="submit"
        className={`rounded-full px-5 py-3 text-center text-sm font-black shadow-sm transition active:scale-95 ${
          isSaved
            ? "border border-emerald-200 bg-emerald-50 text-emerald-900 hover:bg-emerald-100"
            : "border border-amber-200 bg-white text-stone-900 hover:bg-amber-50"
        }`}
      >
        {isSaved ? "Saved privately · Remove" : "Save this Light"}
      </button>
    </form>
  );
}
