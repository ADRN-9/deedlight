import { cache } from "react";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";
import { hasAdminAccess } from "@/lib/auth/admin-access";
import type { DailyPost, DailyReflection, DailyStatus, FeaturedOffering } from "@/lib/types-daily";

type SupabaseLike = Awaited<ReturnType<typeof createClient>>;

const TODAY_FALLBACK: DailyPost = {
  id: "fallback-today",
  slug: "a-new-light-can-begin-today",
  scheduled_for: new Date().toISOString().slice(0, 10),
  status: "published",
  kicker: "TODAY’S DEEDLIGHT",
  title: "A new light can begin today.",
  theme: "courage",
  summary: "Beauty is not only found in nature. Sometimes beauty appears when one person refuses to join cruelty.",
  body: "Goodness does not prevail by accident. Today, choose one small act that protects dignity, reduces loneliness, or gives someone courage.",
  small_deed: "Say one gentle sentence in defense of someone who is being judged unfairly.",
  reflection_prompt: "Where can I make one situation kinder today?",
  featured_offering_id: null,
  image_url: null,
  video_title: "A new light can begin today",
  video_hook: "Goodness does not need a stage; it needs one person to begin.",
  video_script: "Today’s Deedlight is simple: notice one place where dignity needs protection, then add one sentence of gentleness.",
  video_caption: "One small deed can keep light alive. #Deedlight #Goodness #Kindness",
  youtube_url: null,
  video_status: "idea",
  published_at: null,
  archived_at: null,
  created_by: null,
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
  featured_offering: null,
};

function todayIsoDate(): string {
  return new Date().toISOString().slice(0, 10);
}

function normalizeDailyPost(row: unknown): DailyPost {
  const value = row as Partial<DailyPost> & { featured_offering?: FeaturedOffering | FeaturedOffering[] | null };
  const featured = Array.isArray(value.featured_offering)
    ? value.featured_offering[0] ?? null
    : value.featured_offering ?? null;

  return {
    id: String(value.id ?? ""),
    slug: value.slug ?? null,
    scheduled_for: String(value.scheduled_for ?? todayIsoDate()),
    status: (value.status ?? "draft") as DailyStatus,
    kicker: value.kicker ?? null,
    title: String(value.title ?? "Untitled Deedlight"),
    theme: value.theme ?? null,
    summary: value.summary ?? null,
    body: value.body ?? null,
    small_deed: value.small_deed ?? null,
    reflection_prompt: value.reflection_prompt ?? null,
    featured_offering_id: value.featured_offering_id ?? null,
    image_url: value.image_url ?? null,
    video_title: value.video_title ?? null,
    video_hook: value.video_hook ?? null,
    video_script: value.video_script ?? null,
    video_caption: value.video_caption ?? null,
    youtube_url: value.youtube_url ?? null,
    video_status: value.video_status ?? "idea",
    published_at: value.published_at ?? null,
    archived_at: value.archived_at ?? null,
    created_by: value.created_by ?? null,
    created_at: String(value.created_at ?? new Date().toISOString()),
    updated_at: String(value.updated_at ?? new Date().toISOString()),
    featured_offering: featured,
  };
}

function normalizeOffering(row: unknown): FeaturedOffering {
  const value = row as Partial<FeaturedOffering>;
  return {
    id: String(value.id ?? ""),
    title: String(value.title ?? "Untitled Offering"),
    story: value.story ?? null,
    small_deed: value.small_deed ?? null,
    offering_type: value.offering_type ?? null,
    author_display_name: value.author_display_name ?? null,
    bless_count: Number(value.bless_count ?? 0),
    inspired_count: Number(value.inspired_count ?? 0),
    carried_forward_count: Number(value.carried_forward_count ?? 0),
    bless_score: Number(value.bless_score ?? 0),
  };
}

export async function getCurrentUser() {
  const supabase = await createClient();
  if (!supabase) return { supabase: null, user: null };
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return { supabase, user };
}

export async function requireAdmin() {
  const supabase = await createClient();
  if (!supabase) {
    redirect("/login?error=Supabase%20is%20not%20configured");
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login?next=/admin/daily");
  }

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("role,is_suspended")
    .eq("user_id", user.id)
    .maybeSingle();

  if (!hasAdminAccess({ email: user.email, profile, profileError })) {
    redirect("/today?error=admin_required");
  }

  return { supabase, user };
}

export const getTodayDailyPost = cache(async (): Promise<DailyPost> => {
  const supabase = await createClient();
  if (!supabase) return TODAY_FALLBACK;

  const { data, error } = await supabase
    .from("daily_posts")
    .select(
      "*, featured_offering:offerings!daily_posts_featured_offering_id_fkey(id,title,story,small_deed,offering_type,bless_count,inspired_count,carried_forward_count,bless_score)"
    )
    .eq("status", "published")
    .lte("scheduled_for", todayIsoDate())
    .order("scheduled_for", { ascending: false })
    .order("published_at", { ascending: false, nullsFirst: false })
    .limit(1)
    .maybeSingle();

  if (error || !data) {
    return TODAY_FALLBACK;
  }

  return normalizeDailyPost(data);
});

export const getDailyArchive = cache(async (): Promise<DailyPost[]> => {
  const supabase = await createClient();
  if (!supabase) return [];

  const { data, error } = await supabase
    .from("daily_posts")
    .select("*")
    .in("status", ["published", "archived"])
    .order("scheduled_for", { ascending: false })
    .limit(60);

  if (error || !data) return [];
  return (data as unknown[]).map((row: unknown) => normalizeDailyPost(row));
});

export async function getAdminDailyPosts(status?: string): Promise<DailyPost[]> {
  const { supabase } = await requireAdmin();

  let query = supabase
    .from("daily_posts")
    .select("*")
    .order("scheduled_for", { ascending: false })
    .order("created_at", { ascending: false })
    .limit(100);

  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const { data, error } = await query;
  if (error || !data) return [];
  return (data as unknown[]).map((row: unknown) => normalizeDailyPost(row));
}

export async function getAdminDailyPostById(id: string): Promise<DailyPost | null> {
  const { supabase } = await requireAdmin();

  const { data, error } = await supabase
    .from("daily_posts")
    .select(
      "*, featured_offering:offerings!daily_posts_featured_offering_id_fkey(id,title,story,small_deed,offering_type,bless_count,inspired_count,carried_forward_count,bless_score)"
    )
    .eq("id", id)
    .maybeSingle();

  if (error || !data) return null;
  return normalizeDailyPost(data);
}

export async function getApprovedOfferingsForFeature(): Promise<FeaturedOffering[]> {
  const { supabase } = await requireAdmin();

  const { data, error } = await supabase
    .from("offerings")
    .select("id,title,story,small_deed,offering_type,bless_count,inspired_count,carried_forward_count,bless_score")
    .eq("status", "approved")
    .order("bless_score", { ascending: false })
    .order("created_at", { ascending: false })
    .limit(50);

  if (error || !data) return [];
  return (data as unknown[]).map((row: unknown) => normalizeOffering(row));
}

export async function getMyReflectionForDailyPost(dailyPostId: string): Promise<DailyReflection | null> {
  const { supabase, user } = await getCurrentUser();
  if (!supabase || !user || dailyPostId === TODAY_FALLBACK.id) return null;

  const { data, error } = await supabase
    .from("daily_reflections")
    .select("*")
    .eq("daily_post_id", dailyPostId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (error || !data) return null;
  return data as DailyReflection;
}

export async function getDailyReflectionCounts(dailyPostId: string): Promise<{ reflectionCount: number; completedCount: number }> {
  const supabase = await createClient();
  if (!supabase || dailyPostId === TODAY_FALLBACK.id) return { reflectionCount: 0, completedCount: 0 };

  const [{ count: reflectionCount }, { count: completedCount }] = await Promise.all([
    supabase
      .from("daily_reflections")
      .select("id", { count: "exact", head: true })
      .eq("daily_post_id", dailyPostId),
    supabase
      .from("daily_reflections")
      .select("id", { count: "exact", head: true })
      .eq("daily_post_id", dailyPostId)
      .eq("did_today_deed", true),
  ]);

  return {
    reflectionCount: reflectionCount ?? 0,
    completedCount: completedCount ?? 0,
  };
}
