import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import {
  completeDailyDeedAction,
  undoDailyDeedAction,
} from "@/app/today/actions";

type DailyDeedCompletionCardProps = {
  dailyLightId: string;
  userId: string | null;
};

export async function DailyDeedCompletionCard({
  dailyLightId,
  userId,
}: DailyDeedCompletionCardProps) {
  const supabase = await createClient({ allowMissingEnv: true });

  if (!supabase || !dailyLightId) {
    return null;
  }

  const countPromise = supabase
    .from("daily_deed_completion_counts")
    .select("completion_count")
    .eq("daily_light_id", dailyLightId)
    .maybeSingle();

  const completionPromise = userId
    ? supabase
        .from("daily_deed_completions")
        .select("id")
        .eq("user_id", userId)
        .eq("daily_light_id", dailyLightId)
        .maybeSingle()
    : Promise.resolve({ data: null, error: null });

  const [countResult, completionResult] = await Promise.all([
    countPromise,
    completionPromise,
  ]);

  if (countResult.error) {
    console.error(
      "[DailyDeedCompletionCard] aggregate query failed",
      countResult.error,
    );
  }

  if (completionResult.error) {
    console.error(
      "[DailyDeedCompletionCard] member completion query failed",
      completionResult.error,
    );
  }

  const completionCount = Number(
    countResult.data?.completion_count ?? 0,
  );
  const hasCompleted = Boolean(completionResult.data);

  return (
    <section
      className={`mt-6 rounded-3xl border p-5 ${
        hasCompleted
          ? "border-emerald-100 bg-emerald-50"
          : "border-amber-100 bg-white"
      }`}
    >
      <p
        className={`text-xs font-black uppercase tracking-[0.22em] ${
          hasCompleted ? "text-emerald-800" : "text-amber-800"
        }`}
      >
        Carry the light
      </p>

      <h3 className="mt-2 text-xl font-black text-stone-950">
        {hasCompleted
          ? "You carried today’s deed forward."
          : "Did today’s deed become part of your day?"}
      </h3>

      <p className="mt-2 text-sm leading-7 text-stone-700">
        {completionCount > 0
          ? `${completionCount} ${
              completionCount === 1 ? "person has" : "people have"
            } quietly carried this light forward.`
          : "Mark it only when you have genuinely carried the deed into your day."}
      </p>

      <div className="mt-4">
        {userId ? (
          hasCompleted ? (
            <form action={undoDailyDeedAction}>
              <input
                type="hidden"
                name="daily_light_id"
                value={dailyLightId}
              />
              <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
                <span className="inline-flex rounded-full bg-emerald-100 px-5 py-3 text-sm font-black text-emerald-900">
                  ✓ Carried forward today
                </span>
                <button
                  type="submit"
                  className="rounded-full border border-emerald-200 bg-white px-5 py-3 text-sm font-black text-stone-800 transition hover:bg-emerald-50 active:scale-95"
                >
                  Undo
                </button>
              </div>
            </form>
          ) : (
            <form action={completeDailyDeedAction}>
              <input
                type="hidden"
                name="daily_light_id"
                value={dailyLightId}
              />
              <button
                type="submit"
                className="rounded-full bg-amber-400 px-6 py-3 text-sm font-black text-stone-950 shadow-lg shadow-amber-200 transition hover:bg-amber-500 active:scale-95"
              >
                I did today’s deed
              </button>
            </form>
          )
        ) : (
          <Link
            href="/login?next=/today"
            className="inline-flex rounded-full bg-amber-400 px-6 py-3 text-sm font-black text-stone-950 shadow-lg shadow-amber-200 transition hover:bg-amber-500 active:scale-95"
          >
            Sign in to keep this in your journey
          </Link>
        )}
      </div>

      <p className="mt-4 text-xs leading-5 text-stone-500">
        Your personal completion record is private. Only the anonymous total
        above is visible publicly.
      </p>
    </section>
  );
}
