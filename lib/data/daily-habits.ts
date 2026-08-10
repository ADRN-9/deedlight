import { createClient } from "@/lib/supabase/server";

export type DailyDeedCompletion = {
  id: string;
  user_id: string;
  daily_light_id: string;
  created_at: string;
  daily_light?: {
    id: string;
    scheduled_date: string | null;
    title: string | null;
    theme: string | null;
  } | null;
};

export type DailyDeedPractice = {
  total: number;
  items: DailyDeedCompletion[];
};

type DailyLightSummary = {
  id: string;
  scheduled_date: string | null;
  title: string | null;
  theme: string | null;
};

export async function getMyDailyDeedPractice(
  userId: string,
  limit = 14,
): Promise<DailyDeedPractice> {
  const supabase = await createClient({ allowMissingEnv: true });

  if (!supabase || !userId) {
    return { total: 0, items: [] };
  }

  const [historyResult, totalResult] = await Promise.all([
    supabase
      .from("daily_deed_completions")
      .select("id,user_id,daily_light_id,created_at")
      .eq("user_id", userId)
      .not("daily_light_id", "is", null)
      .order("created_at", { ascending: false })
      .limit(limit),
    supabase
      .from("daily_deed_completions")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .not("daily_light_id", "is", null),
  ]);

  if (historyResult.error) {
    console.error(
      "[getMyDailyDeedPractice] completion history query failed",
      historyResult.error,
    );
  }

  if (totalResult.error) {
    console.error(
      "[getMyDailyDeedPractice] completion total query failed",
      totalResult.error,
    );
  }

  const rawItems = (historyResult.data ?? []) as DailyDeedCompletion[];

  if (!rawItems.length) {
    return {
      total: totalResult.count ?? 0,
      items: [],
    };
  }

  const lightIds = Array.from(
    new Set(rawItems.map((item) => item.daily_light_id).filter(Boolean)),
  );

  const { data: lights, error: lightsError } = await supabase
    .from("daily_lights")
    .select("id,scheduled_date,title,theme")
    .in("id", lightIds);

  if (lightsError) {
    console.error(
      "[getMyDailyDeedPractice] Daily Light lookup failed",
      lightsError,
    );
  }

  const lightById = new Map<string, DailyLightSummary>();

  for (const light of (lights ?? []) as DailyLightSummary[]) {
    lightById.set(light.id, light);
  }

  return {
    total: totalResult.count ?? rawItems.length,
    items: rawItems.map((item) => ({
      ...item,
      daily_light: lightById.get(item.daily_light_id) ?? null,
    })),
  };
}
