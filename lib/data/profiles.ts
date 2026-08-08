import { createClient } from "@/lib/supabase/server";
import type { Offering } from "@/lib/types";

export type PublicProfile = {
  username: string;
  display_name: string;
  bio: string | null;
  country: string | null;
  is_verified: boolean;
  member_since: string;
  show_contribution_stats: boolean;
  published_offering_count: number | null;
  total_bless_count: number | null;
  total_inspired_count: number | null;
  total_carried_forward_count: number | null;
};

const publicProfileColumns = `
  username,
  display_name,
  bio,
  country,
  is_verified,
  member_since,
  show_contribution_stats,
  published_offering_count,
  total_bless_count,
  total_inspired_count,
  total_carried_forward_count
`;

const profileOfferingColumns = `
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

export async function getPublicProfile(
  username: string,
): Promise<PublicProfile | null> {
  const supabase = await createClient({ allowMissingEnv: true });

  if (!supabase) {
    return null;
  }

  const { data, error } = await supabase
    .from("profiles_public")
    .select(publicProfileColumns)
    .eq("username", username.toLowerCase())
    .maybeSingle();

  if (error || !data) {
    return null;
  }

  return data as PublicProfile;
}

export async function getPublicProfileOfferings(
  username: string,
  limit = 24,
): Promise<Offering[]> {
  const supabase = await createClient({ allowMissingEnv: true });

  if (!supabase) {
    return [];
  }

  const { data, error } = await supabase
    .from("offerings_public")
    .select(profileOfferingColumns)
    .eq("author_username", username.toLowerCase())
    .order("published_at", { ascending: false })
    .limit(limit);

  if (error || !data) {
    return [];
  }

  return data as Offering[];
}
