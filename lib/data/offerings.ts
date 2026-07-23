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

function normalizeOffering(item: Partial<Offering>): Offering {
  return {
    id: String(item.id || ""),
    user_id: String(item.user_id || ""),
    title: String(item.title || "Untitled Offering"),
    body: String(item.body || ""),
    takeaway: item.takeaway ?? null,
    offering_type: String(item.offering_type || "good_deed"),
    media_url: item.media_url ?? null,
    media_type: item.media_type ?? null,
    is_anonymous: Boolean(item.is_anonymous),
    allow_reflections: item.allow_reflections ?? true,
    location_label: item.location_label ?? null,
    bless_count: Number(item.bless_count || 0),
    inspired_count: Number(item.inspired_count || 0),
    carried_forward_count: Number(item.carried_forward_count || 0),
    reflection_count: Number(item.reflection_count || 0),
    bless_score: Number(item.bless_score || 0),
    published_at: item.published_at ?? null,
    created_at: item.created_at ?? null,
    updated_at: item.updated_at ?? null,
    theme_name: item.theme_name ?? null,
    author_name: item.author_name ?? null
  };
}

function logDataError(scope: string, error: unknown) {
  console.error(`[Deedlight data] ${scope} failed`, error);
}

export async function getApprovedOfferings(limit = 12): Promise<Offering[]> {
  try {
    const supabase = await createClient({ allowMissingEnv: true });
    if (!supabase) return fallbackOfferings;

    const { data, error } = await supabase
      .from("offerings_public")
      .select(publicOfferingColumns)
      .order("bless_score", { ascending: false })
      .order("published_at", { ascending: false })
      .limit(limit);

    if (error || !data) {
      if (error) logDataError("getApprovedOfferings", error);
      return fallbackOfferings;
    }

    return (data as Partial<Offering>[]).map(normalizeOffering);
  } catch (error) {
    logDataError("getApprovedOfferings threw", error);
    return fallbackOfferings;
  }
}

export async function getOffering(id: string): Promise<Offering | null> {
  try {
    const supabase = await createClient({ allowMissingEnv: true });
    if (!supabase) return fallbackOfferings.find((item) => item.id === id) || null;

    const { data, error } = await supabase
      .from("offerings_public")
      .select(publicOfferingColumns)
      .eq("id", id)
      .maybeSingle();

    if (error) {
      logDataError("getOffering", error);
      return null;
    }

    return data ? normalizeOffering(data as Partial<Offering>) : null;
  } catch (error) {
    logDataError("getOffering threw", error);
    return null;
  }
}

export async function getAdminOfferings(status = "pending", limit = 50): Promise<AdminOffering[]> {
  try {
    const supabase = await createClient({ allowMissingEnv: true });
    if (!supabase) return [];

    const query = supabase
      .from("offerings")
      .select(adminOfferingColumns)
      .order("created_at", { ascending: false })
      .limit(limit);

    const { data, error } = status === "all" ? await query : await query.eq("status", status);

    if (error || !data) {
      if (error) logDataError("getAdminOfferings", error);
      return [];
    }

    return addAuthorNames(data as AdminOffering[]);
  } catch (error) {
    logDataError("getAdminOfferings threw", error);
    return [];
  }
}

export async function getAdminOffering(id: string): Promise<AdminOffering | null> {
  try {
    const supabase = await createClient({ allowMissingEnv: true });
    if (!supabase) return null;

    const { data, error } = await supabase
      .from("offerings")
      .select(adminOfferingColumns)
      .eq("id", id)
      .maybeSingle();

    if (error || !data) {
      if (error) logDataError("getAdminOffering", error);
      return null;
    }

    const withAuthors = await addAuthorNames([data as AdminOffering]);
    return withAuthors[0] ?? null;
  } catch (error) {
    logDataError("getAdminOffering threw", error);
    return null;
  }
}

export async function getMyOfferings(limit = 24): Promise<AdminOffering[]> {
  try {
    const supabase = await createClient({ allowMissingEnv: true });
    if (!supabase) return [];

    const {
      data: { user },
      error: userError
    } = await supabase.auth.getUser();

    if (userError || !user) return [];

    const { data, error } = await supabase
      .from("offerings")
      .select(adminOfferingColumns)
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(limit);

    if (error || !data) {
      if (error) logDataError("getMyOfferings", error);
      return [];
    }

    return addAuthorNames(data as AdminOffering[]);
  } catch (error) {
    logDataError("getMyOfferings threw", error);
    return [];
  }
}

async function addAuthorNames<T extends { user_id: string; is_anonymous?: boolean; author_name?: string | null }>(items: T[]): Promise<T[]> {
  try {
    const supabase = await createClient({ allowMissingEnv: true });
    if (!supabase || items.length === 0) return items;

    const userIds = Array.from(new Set(items.map((item) => item.user_id).filter(Boolean)));
    if (userIds.length === 0) return items;

    const { data: profiles, error } = await supabase
      .from("profiles")
      .select("user_id, display_name, username, avatar_url")
      .in("user_id", userIds);

    if (error) {
      logDataError("addAuthorNames", error);
      return items;
    }

    const profileByUserId = new Map(
      ((profiles || []) as ProfileSummary[]).map((profile) => [profile.user_id, profile])
    );

    return items.map((item) => {
      const profile = profileByUserId.get(item.user_id);
      return {
        ...item,
        author_name: item.is_anonymous ? null : profile?.display_name || item.author_name || "Deedlight member"
      };
    });
  } catch (error) {
    logDataError("addAuthorNames threw", error);
    return items;
  }
}
