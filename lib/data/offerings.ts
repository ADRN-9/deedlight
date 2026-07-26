import { createClient } from "@/lib/supabase/server";
import { fallbackOfferings } from "./fallback";
import type { AdminOffering, Offering, ProfileSummary } from "@/lib/types";

const publicOfferingColumns = `
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
  author_name
`;

const risingOfferingColumns = `
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
  rising_score,
  published_at,
  theme_name,
  author_name
`;

const adminOfferingColumns = `
  id,
  user_id,
  theme_id,
  offering_type,
  title,
  body,
  takeaway,
  media_url,
  media_type,
  is_anonymous,
  allow_reflections,
  location_label,
  status,
  moderation_note,
  bless_count,
  inspired_count,
  carried_forward_count,
  reflection_count,
  open_report_count,
  bless_score,
  published_at,
  created_at,
  updated_at
`;

export async function getApprovedOfferings(limit = 12): Promise<Offering[]> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return fallbackOfferings;

  const { data, error } = await supabase
    .from("offerings_public")
    .select(publicOfferingColumns)
    .order("published_at", { ascending: false })
    .limit(limit);

  if (error || !data) return fallbackOfferings;
  return data as Offering[];
}

export async function getRisingOfferings(limit = 12): Promise<Offering[]> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) {
    return [...fallbackOfferings].sort((a, b) => (b.bless_score || 0) - (a.bless_score || 0));
  }

  // Prefer the Sprint 4 rising view. If the migration has not been pushed yet,
  // gracefully fall back to the approved Offerings view ordered by bless_score.
  const rising = await supabase
    .from("offerings_rising")
    .select(risingOfferingColumns)
    .order("rising_score", { ascending: false })
    .order("published_at", { ascending: false })
    .limit(limit);

  if (!rising.error && rising.data) return rising.data as Offering[];

  const fallback = await supabase
    .from("offerings_public")
    .select(publicOfferingColumns)
    .order("bless_score", { ascending: false })
    .order("published_at", { ascending: false })
    .limit(limit);

  if (fallback.error || !fallback.data) {
    return [...fallbackOfferings].sort((a, b) => (b.bless_score || 0) - (a.bless_score || 0));
  }

  return fallback.data as Offering[];
}

export async function getOffering(id: string): Promise<Offering | null> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return fallbackOfferings.find((item) => item.id === id) || null;

  const { data, error } = await supabase
    .from("offerings_public")
    .select(publicOfferingColumns)
    .eq("id", id)
    .maybeSingle();

  if (error) return null;
  return data as Offering | null;
}

export async function getAdminOfferings(status = "pending", limit = 50): Promise<AdminOffering[]> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return [];

  const query = supabase
    .from("offerings")
    .select(adminOfferingColumns)
    .order("created_at", { ascending: false })
    .limit(limit);

  const { data, error } = status === "all" ? await query : await query.eq("status", status);

  if (error || !data) return [];
  return addAuthorNames(data as AdminOffering[]);
}

export async function getAdminOffering(id: string): Promise<AdminOffering | null> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("offerings")
    .select(adminOfferingColumns)
    .eq("id", id)
    .maybeSingle();

  if (error || !data) return null;
  const withAuthors = await addAuthorNames([data as AdminOffering]);
  return withAuthors[0] ?? null;
}

export async function getMyOfferings(limit = 24): Promise<AdminOffering[]> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return [];

  const {
    data: { user }
  } = await supabase.auth.getUser();

  if (!user) return [];

  const { data, error } = await supabase
    .from("offerings")
    .select(adminOfferingColumns)
    .eq("user_id", user.id)
    .order("created_at", { ascending: false })
    .limit(limit);

  if (error || !data) return [];
  return addAuthorNames(data as AdminOffering[]);
}

async function addAuthorNames<T extends { user_id: string; is_anonymous?: boolean; author_name?: string | null }>(items: T[]): Promise<T[]> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase || items.length === 0) return items;

  const userIds = Array.from(new Set(items.map((item) => item.user_id).filter(Boolean)));
  if (userIds.length === 0) return items;

  const { data: profiles } = await supabase
    .from("profiles")
    .select("user_id, display_name, username, avatar_url")
    .in("user_id", userIds);

  const profileByUserId = new Map(((profiles || []) as ProfileSummary[]).map((profile) => [profile.user_id, profile]));

  return items.map((item) => {
    const profile = profileByUserId.get(item.user_id);
    return {
      ...item,
      author_name: item.is_anonymous ? null : profile?.display_name || item.author_name || "Deedlight member"
    };
  });
}
