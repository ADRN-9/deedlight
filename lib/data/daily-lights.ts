import { createClient } from "@/lib/supabase/server";

export type DailyLightStatus = "draft" | "scheduled" | "published" | "archived";

export type DailyLight = {
  id: string;
  scheduled_date: string;
  status: DailyLightStatus | string;
  kicker: string | null;
  title: string;
  theme: string | null;
  summary: string | null;
  small_deed: string | null;
  reflection_prompt: string | null;
  featured_offering_id: string | null;
  video_title: string | null;
  video_hook: string | null;
  video_script: string | null;
  created_at: string | null;
  updated_at?: string | null;
};

export type DailyReflection = {
  id: string;
  daily_light_id: string;
  user_id: string;
  reflection: string | null;
  intention: string | null;
  created_at: string;
  daily_light?: Pick<DailyLight, "id" | "title" | "scheduled_date" | "theme"> | null;
};

const dailyLightColumns = `
  id,
  scheduled_date,
  status,
  kicker,
  title,
  theme,
  summary,
  small_deed,
  reflection_prompt,
  featured_offering_id,
  video_title,
  video_hook,
  video_script,
  created_at,
  updated_at
`;

const fallbackDailyLight: DailyLight = {
  id: "",
  scheduled_date: new Date().toISOString().slice(0, 10),
  status: "published",
  kicker: "TODAY’S DEEDLIGHT",
  title: "A new light can begin today.",
  theme: "Courage",
  summary: "Beauty is not only found in nature. Sometimes beauty appears when one person refuses to join cruelty.",
  small_deed: "Say one gentle sentence in defense of someone who is being judged unfairly.",
  reflection_prompt: "Where can you protect dignity today?",
  featured_offering_id: null,
  video_title: null,
  video_hook: null,
  video_script: null,
  created_at: null
};

export async function getPublishedDailyLightForToday(): Promise<{ light: DailyLight; isFallback: boolean }> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return { light: fallbackDailyLight, isFallback: true };

  const today = new Date().toISOString().slice(0, 10);

  const { data, error } = await supabase
    .from("daily_lights")
    .select(dailyLightColumns)
    .eq("scheduled_date", today)
    .eq("status", "published")
    .maybeSingle();

  if (error || !data) return { light: fallbackDailyLight, isFallback: true };
  return { light: data as DailyLight, isFallback: false };
}

export async function getMyDailyReflection(dailyLightId: string, userId: string): Promise<DailyReflection | null> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase || !dailyLightId || !userId) return null;

  const { data, error } = await supabase
    .from("daily_reflections")
    .select("id,daily_light_id,user_id,reflection,intention,created_at")
    .eq("daily_light_id", dailyLightId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error || !data) return null;
  return data as DailyReflection;
}

export async function getMyDailyReflectionHistory(userId: string, limit = 14): Promise<DailyReflection[]> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase || !userId) return [];

  const { data, error } = await supabase
    .from("daily_reflections")
    .select("id,daily_light_id,user_id,reflection,intention,created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(limit);

  if (error || !data) return [];

  const reflections = data as DailyReflection[];
  const dailyLightIds = Array.from(new Set(reflections.map((item) => item.daily_light_id).filter(Boolean)));

  if (dailyLightIds.length === 0) return reflections;

  const { data: lights } = await supabase
    .from("daily_lights")
    .select("id,title,scheduled_date,theme")
    .in("id", dailyLightIds);

  const lightById = new Map(((lights || []) as DailyLight[]).map((light) => [light.id, light]));

  return reflections.map((reflection) => ({
    ...reflection,
    daily_light: lightById.get(reflection.daily_light_id) ?? null
  }));
}

export async function getApprovedOfferingsForDailySelect(limit = 80) {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return [];

  const { data, error } = await supabase
    .from("offerings")
    .select("id,title,body,offering_type,author_name,display_name,published_at")
    .eq("status", "approved")
    .order("published_at", { ascending: false })
    .limit(limit);

  if (error || !data) return [];
  return data;
}
