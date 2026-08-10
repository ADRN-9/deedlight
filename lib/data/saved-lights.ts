import { createClient } from "@/lib/supabase/server";

export type SavedDailyLight = {
  id: string;
  daily_light_id: string;
  created_at: string;
  daily_light: {
    id: string;
    scheduled_date: string | null;
    title: string | null;
    theme: string | null;
    summary: string | null;
    small_deed: string | null;
  };
};

type SavedRow = {
  id: string;
  daily_light_id: string;
  created_at: string;
};

type DailyLightSummary = SavedDailyLight["daily_light"];

export async function getMySavedDailyLights(
  userId: string,
  limit = 12,
): Promise<SavedDailyLight[]> {
  const supabase = await createClient({ allowMissingEnv: true });

  if (!supabase || !userId) return [];

  const { data: savedRows, error: savedError } = await supabase
    .from("saved_lights")
    .select("id,daily_light_id,created_at")
    .eq("user_id", userId)
    .not("daily_light_id", "is", null)
    .order("created_at", { ascending: false })
    .limit(limit);

  if (savedError) {
    console.error("[getMySavedDailyLights] saved rows query failed", savedError);
    return [];
  }

  const rows = (savedRows ?? []) as SavedRow[];
  if (!rows.length) return [];

  const lightIds = Array.from(
    new Set(rows.map((item) => item.daily_light_id).filter(Boolean)),
  );

  const { data: lights, error: lightsError } = await supabase
    .from("daily_lights")
    .select("id,scheduled_date,title,theme,summary,small_deed")
    .eq("status", "published")
    .in("id", lightIds);

  if (lightsError) {
    console.error("[getMySavedDailyLights] Daily Light lookup failed", lightsError);
    return [];
  }

  const lightById = new Map<string, DailyLightSummary>();
  for (const light of (lights ?? []) as DailyLightSummary[]) {
    lightById.set(light.id, light);
  }

  const result: SavedDailyLight[] = [];

  for (const row of rows) {
    const light = lightById.get(row.daily_light_id);
    if (!light) continue;

    result.push({
      ...row,
      daily_light: light,
    });
  }

  return result;
}
