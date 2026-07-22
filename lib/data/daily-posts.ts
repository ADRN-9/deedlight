import { createClient } from "@/lib/supabase/server";
import { fallbackDailyPost } from "./fallback";
import type { DailyPost } from "@/lib/types";

export async function getTodayPost(): Promise<DailyPost> {
  try {
    const supabase = await createClient({ allowMissingEnv: true });
    if (!supabase) return fallbackDailyPost;

    const { data, error } = await supabase
      .from("daily_posts")
      .select("id,date,slug,title,reflection,daily_action,reflection_question,image_url,youtube_url,themes(name)")
      .eq("status", "published")
      .lte("date", new Date().toISOString().slice(0, 10))
      .order("date", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error || !data) {
      if (error) console.error("getTodayPost Supabase error", error);
      return fallbackDailyPost;
    }

    return {
      id: data.id,
      date: data.date,
      slug: data.slug,
      title: data.title,
      reflection: data.reflection,
      daily_action: data.daily_action,
      reflection_question: data.reflection_question,
      image_url: data.image_url,
      youtube_url: data.youtube_url,
      theme_name: Array.isArray(data.themes) ? data.themes[0]?.name : data.themes?.name
    };
  } catch (error) {
    console.error("getTodayPost failed", error);
    return fallbackDailyPost;
  }
}
