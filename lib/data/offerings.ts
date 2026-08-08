import { createClient } from "@/lib/supabase/server";
import { fallbackOfferings } from "./fallback";
import type { AdminOffering, Offering, ProfileSummary, ReportItem } from "@/lib/types";

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
  author_name,
  author_username
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
  author_name,
  author_username
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

const reportColumns = `
  id,
  offering_id,
  reflection_id,
  reported_by,
  reason,
  details,
  status,
  admin_note,
  resolved_by,
  resolved_at,
  created_at
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
    .order("open_report_count", { ascending: false })
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

export async function getReportsForOffering(offeringId: string): Promise<ReportItem[]> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return [];

  const { data, error } = await supabase
    .from("reports")
    .select(reportColumns)
    .eq("offering_id", offeringId)
    .order("created_at", { ascending: false })
    .limit(50);

  if (error || !data) return [];
  return addReporterNames(data as ReportItem[]);
}

export async function getAdminReports(status = "open", limit = 80): Promise<ReportItem[]> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return [];

  const query = supabase
    .from("reports")
    .select(reportColumns)
    .order("created_at", { ascending: false })
    .limit(limit);

  const { data, error } = status === "all" ? await query : await query.eq("status", status);
  if (error || !data) return [];

  const reports = await addReporterNames(data as ReportItem[]);
  const offeringIds = Array.from(new Set(reports.map((report) => report.offering_id).filter(Boolean))) as string[];

  if (offeringIds.length === 0) return reports;

  const { data: offerings } = await supabase
    .from("offerings")
    .select(adminOfferingColumns)
    .in("id", offeringIds);

  const offeringsWithAuthors = await addAuthorNames((offerings || []) as AdminOffering[]);
  const offeringById = new Map(offeringsWithAuthors.map((offering) => [offering.id, offering]));

  return reports.map((report) => ({
    ...report,
    offering: report.offering_id ? offeringById.get(report.offering_id) ?? null : null
  }));
}

async function addAuthorNames<T extends { user_id: string | null; is_anonymous?: boolean; author_name?: string | null }>(items: T[]): Promise<T[]> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase || items.length === 0) return items;

  const userIds = Array.from(
    new Set(
      items
        .map((item) => item.user_id)
        .filter((value): value is string => Boolean(value)),
    ),
  );
  if (userIds.length === 0) return items;

  const { data: profiles } = await supabase
    .from("profiles")
    .select("user_id, display_name, username, avatar_url")
    .in("user_id", userIds);

  const profileByUserId = new Map(((profiles || []) as ProfileSummary[]).map((profile) => [profile.user_id, profile]));

  return items.map((item) => {
    const profile = item.user_id
      ? profileByUserId.get(item.user_id)
      : undefined;
    return {
      ...item,
      author_name: item.is_anonymous ? null : profile?.display_name || item.author_name || "Deedlight member"
    };
  });
}

async function addReporterNames(items: ReportItem[]): Promise<ReportItem[]> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase || items.length === 0) return items;

  const userIds = Array.from(new Set(items.map((item) => item.reported_by).filter(Boolean))) as string[];
  if (userIds.length === 0) return items;

  const { data: profiles } = await supabase
    .from("profiles")
    .select("user_id, display_name, username, avatar_url")
    .in("user_id", userIds);

  const profileByUserId = new Map(((profiles || []) as ProfileSummary[]).map((profile) => [profile.user_id, profile]));

  return items.map((item) => {
    const profile = item.reported_by ? profileByUserId.get(item.reported_by) : null;
    return {
      ...item,
      reporter_name: profile?.display_name || profile?.username || (item.reported_by ? "Deedlight member" : "Unknown reporter")
    };
  });
}
