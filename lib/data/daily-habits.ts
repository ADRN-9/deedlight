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
  recentCount: number;
  lastCarriedDate: string | null;
  items: DailyDeedCompletion[];
};

type DailyLightSummary = {
  id: string;
  scheduled_date: string | null;
  title: string | null;
  theme: string | null;
};

function emptyPractice(): DailyDeedPractice {
  return {
    total: 0,
    recentCount: 0,
    lastCarriedDate: null,
    items: [],
  };
}

function isWithinRecentWindow(value: string | null, days = 7) {
  if (!value) return false;

  const target = Date.parse(`${value}T00:00:00Z`);
  const today = Date.parse(`${new Date().toISOString().slice(0, 10)}T00:00:00Z`);

  if (!Number.isFinite(target) || !Number.isFinite(today)) return false;

  const difference = Math.floor((today - target) / 86_400_000);
  return difference >= 0 && difference < days;
}

export async function getMyDailyDeedPractice(
  userId: string,
  limit = 14,
): Promise<DailyDeedPractice> {
  const supabase = await createClient({ allowMissingEnv: true });

  if (!supabase || !userId) {
    return emptyPractice();
  }

  const historyLimit = Math.max(limit, 32);

  const [historyResult, totalResult] = await Promise.all([
    supabase
      .from("daily_deed_completions")
      .select("id,user_id,daily_light_id,created_at")
      .eq("user_id", userId)
      .not("daily_light_id", "is", null)
      .order("created_at", { ascending: false })
      .limit(historyLimit),
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
      ...emptyPractice(),
      total: totalResult.count ?? 0,
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

  const hydratedItems = rawItems.map((item) => ({
    ...item,
    daily_light: lightById.get(item.daily_light_id) ?? null,
  }));

  const recentCount = hydratedItems.filter((item) =>
    isWithinRecentWindow(item.daily_light?.scheduled_date ?? null),
  ).length;

  const lastCarriedDate =
    hydratedItems.find((item) => item.daily_light?.scheduled_date)?.daily_light
      ?.scheduled_date ?? null;

  return {
    total: totalResult.count ?? rawItems.length,
    recentCount,
    lastCarriedDate,
    items: hydratedItems.slice(0, limit),
  };
}
