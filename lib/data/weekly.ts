import { createClient } from "@/lib/supabase/server";
import type { Offering } from "@/lib/types";
import type {
  WeeklyFeature,
  WeeklyFeatureOption,
  WeeklyOffering,
} from "@/lib/types-weekly";

type PublicOfferingRpcRow = {
  id: string;
  title: string;
  body: string;
  takeaway: string | null;
  offering_type: string;
  media_url: string | null;
  media_type: string | null;
  is_anonymous: boolean;
  allow_reflections: boolean;
  location_label: string | null;
  bless_count: number | null;
  inspired_count: number | null;
  carried_forward_count: number | null;
  published_at: string | null;
  theme_name: string | null;
  author_name: string | null;
  author_username: string | null;
};

type WeeklyOfferingRpcRow = PublicOfferingRpcRow & {
  weekly_bless_count: number | null;
  weekly_inspired_count: number | null;
  weekly_carried_forward_count: number | null;
  weekly_reaction_count: number | null;
};

type WeeklyFeatureRpcRow = PublicOfferingRpcRow & {
  week_start: string;
};

function normalizePublicOffering(row: PublicOfferingRpcRow): Offering {
  return {
    id: row.id,
    user_id: null,
    title: row.title,
    body: row.body,
    takeaway: row.takeaway,
    offering_type: row.offering_type,
    media_url: row.media_url,
    media_type: row.media_type,
    is_anonymous: row.is_anonymous === true,
    allow_reflections: row.allow_reflections !== false,
    location_label: row.location_label,
    bless_count: Number(row.bless_count ?? 0),
    inspired_count: Number(row.inspired_count ?? 0),
    carried_forward_count: Number(row.carried_forward_count ?? 0),
    reflection_count: 0,
    bless_score: 0,
    rising_score: null,
    published_at: row.published_at,
    theme_name: row.theme_name,
    author_name: row.author_name,
    author_username: row.author_username,
  };
}

export async function getWeeklyGoodness(
  limit = 12,
): Promise<WeeklyOffering[]> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return [];

  const safeLimit = Math.min(
    24,
    Math.max(1, Number.isFinite(limit) ? Math.floor(limit) : 12),
  );

  const { data, error } = await supabase.rpc("get_weekly_goodness", {
    p_limit: safeLimit,
  });

  if (error || !data) {
    if (error) {
      console.error("[getWeeklyGoodness] query failed", {
        code: error.code,
        message: error.message,
      });
    }
    return [];
  }

  return (data as WeeklyOfferingRpcRow[]).map((row) => ({
    ...normalizePublicOffering(row),
    weekly_bless_count: Number(row.weekly_bless_count ?? 0),
    weekly_inspired_count: Number(row.weekly_inspired_count ?? 0),
    weekly_carried_forward_count: Number(
      row.weekly_carried_forward_count ?? 0,
    ),
    weekly_reaction_count: Number(row.weekly_reaction_count ?? 0),
  }));
}

export async function getCurrentWeeklyFeature(): Promise<WeeklyFeature | null> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return null;

  const { data, error } = await supabase.rpc(
    "get_current_weekly_goodness_feature",
  );

  if (error || !data) {
    if (error) {
      console.error("[getCurrentWeeklyFeature] query failed", {
        code: error.code,
        message: error.message,
      });
    }
    return null;
  }

  const row = (data as WeeklyFeatureRpcRow[])[0];
  if (!row) return null;

  return {
    week_start: row.week_start,
    offering: normalizePublicOffering(row),
  };
}

export async function getWeeklyFeatureOptions(
  limit = 100,
): Promise<WeeklyFeatureOption[]> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return [];

  const safeLimit = Math.min(
    200,
    Math.max(1, Number.isFinite(limit) ? Math.floor(limit) : 100),
  );

  const { data, error } = await supabase
    .from("offerings_public")
    .select(
      "id,title,is_anonymous,author_name,author_username,published_at",
    )
    .order("published_at", { ascending: false })
    .limit(safeLimit);

  if (error || !data) return [];

  return data as WeeklyFeatureOption[];
}
