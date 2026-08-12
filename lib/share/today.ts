import { createClient } from "@/lib/supabase/server";

export type TodayShareLight = {
  id: string;
  scheduled_date: string | null;
  title: string | null;
  theme: string | null;
  summary: string | null;
  small_deed: string | null;
};

export async function getTodayShareLight(): Promise<TodayShareLight | null> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return null;

  const today = new Date().toISOString().slice(0, 10);

  const { data, error } = await supabase
    .from("daily_lights")
    .select("id,scheduled_date,title,theme,summary,small_deed")
    .eq("status", "published")
    .lte("scheduled_date", today)
    .order("scheduled_date", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error || !data) return null;
  return data as TodayShareLight;
}
