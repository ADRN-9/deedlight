import { createClient } from "@/lib/supabase/server";
import type { Offering } from "@/lib/types";

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

export type SavedOffering = {
  id: string;
  offering_id: string;
  created_at: string;
  offering: Offering;
};

type SavedDailyRow = {
  id: string;
  daily_light_id: string;
  created_at: string;
};

type SavedOfferingRow = {
  id: string;
  offering_id: string;
  created_at: string;
};

type DailyLightSummary = SavedDailyLight["daily_light"];

const savedOfferingColumns = `
  id,
  user_id,
  title,
  body,
  takeaway,
  offering_type,
  media_url,
  media_type,
  is_anonymous,
  allow_reflections,
  location_label,
  bless_count,
  inspired_count,
  carried_forward_count,
  reflection_count,
  bless_score,
  published_at,
  theme_name,
  author_name,
  author_username
`;

export async function getViewerSavedOfferingIds(
  offeringIds: string[],
): Promise<{ signedIn: boolean; savedIds: Set<string> }> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return { signedIn: false, savedIds: new Set() };

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { signedIn: false, savedIds: new Set() };
  if (!offeringIds.length) return { signedIn: true, savedIds: new Set() };

  const { data, error } = await supabase
    .from("saved_lights")
    .select("offering_id")
    .eq("user_id", user.id)
    .not("offering_id", "is", null)
    .in("offering_id", offeringIds);

  if (error || !data) {
    if (error) console.error("[getViewerSavedOfferingIds] query failed", error);
    return { signedIn: true, savedIds: new Set() };
  }

  const rows = data as Array<{ offering_id: string | null }>;

  return {
    signedIn: true,
    savedIds: new Set(
      rows
        .map((item) => item.offering_id)
        .filter((value): value is string => Boolean(value)),
    ),
  };
}

export async function getMySavedOfferings(
  userId: string,
  limit = 12,
): Promise<SavedOffering[]> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase || !userId) return [];

  const { data: savedRows, error: savedError } = await supabase
    .from("saved_lights")
    .select("id,offering_id,created_at")
    .eq("user_id", userId)
    .not("offering_id", "is", null)
    .order("created_at", { ascending: false })
    .limit(limit);

  if (savedError) {
    console.error("[getMySavedOfferings] saved rows query failed", savedError);
    return [];
  }

  const rows = (savedRows ?? []) as SavedOfferingRow[];
  if (!rows.length) return [];

  const offeringIds = Array.from(
    new Set(rows.map((item) => item.offering_id).filter(Boolean)),
  );

  const { data: offerings, error: offeringsError } = await supabase
    .from("offerings_public")
    .select(savedOfferingColumns)
    .in("id", offeringIds);

  if (offeringsError) {
    console.error("[getMySavedOfferings] Offering lookup failed", offeringsError);
    return [];
  }

  const offeringById = new Map<string, Offering>();
  for (const offering of (offerings ?? []) as Offering[]) {
    offeringById.set(offering.id, offering);
  }

  const result: SavedOffering[] = [];
  for (const row of rows) {
    const offering = offeringById.get(row.offering_id);
    if (!offering) continue;
    result.push({ ...row, offering });
  }

  return result;
}

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

  const rows = (savedRows ?? []) as SavedDailyRow[];
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
