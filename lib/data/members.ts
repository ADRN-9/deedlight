import { createClient } from "@/lib/supabase/server";

export type AdminMemberState = "all" | "active" | "suspended";

export type AdminMemberSummary = {
  member_user_id: string;
  username: string;
  display_name: string;
  role: string;
  is_verified: boolean;
  is_suspended: boolean;
  is_public: boolean;
  member_since: string;
  offering_count: number;
  approved_offering_count: number;
  pending_offering_count: number;
  open_report_count: number;
  last_action: "suspended" | "restored" | null;
  last_reason: string | null;
  last_moderated_at: string | null;
};

export type AdminMemberContext = {
  profile: {
    user_id: string;
    username: string;
    display_name: string;
    role: string;
    is_verified: boolean;
    is_suspended: boolean;
    is_public: boolean;
    member_since: string;
  };
  offerings: Array<{
    id: string;
    title: string;
    status: string;
    is_anonymous: boolean;
    open_report_count: number;
    moderation_note: string | null;
    created_at: string;
    published_at: string | null;
  }>;
  reports: Array<{
    id: string;
    offering_id: string;
    offering_title: string;
    reason: string;
    status: string;
    details: string | null;
    admin_note: string | null;
    created_at: string;
  }>;
  moderation_events: Array<{
    id: string;
    action: "suspended" | "restored";
    reason: string;
    actor_name: string;
    created_at: string;
  }>;
};

export async function getAdminMembers(
  state: AdminMemberState = "all",
): Promise<AdminMemberSummary[]> {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("admin_list_members", {
    p_state: state,
  });

  if (error) {
    throw new Error(`Unable to load members: ${error.message}`);
  }

  return ((data ?? []) as Array<Record<string, unknown>>).map((item) => ({
    member_user_id: String(item.member_user_id ?? ""),
    username: String(item.username ?? ""),
    display_name: String(item.display_name ?? "Deedlight member"),
    role: String(item.role ?? "member"),
    is_verified: item.is_verified === true,
    is_suspended: item.is_suspended === true,
    is_public: item.is_public === true,
    member_since: String(item.member_since ?? ""),
    offering_count: Number(item.offering_count ?? 0),
    approved_offering_count: Number(item.approved_offering_count ?? 0),
    pending_offering_count: Number(item.pending_offering_count ?? 0),
    open_report_count: Number(item.open_report_count ?? 0),
    last_action:
      item.last_action === "suspended" || item.last_action === "restored"
        ? item.last_action
        : null,
    last_reason:
      typeof item.last_reason === "string" ? item.last_reason : null,
    last_moderated_at:
      typeof item.last_moderated_at === "string"
        ? item.last_moderated_at
        : null,
  }));
}

export async function getAdminMemberContext(
  userId: string,
): Promise<AdminMemberContext | null> {
  const supabase = await createClient();

  const { data, error } = await supabase.rpc("admin_get_member_context", {
    p_member_user_id: userId,
  });

  if (error) {
    throw new Error(`Unable to load member context: ${error.message}`);
  }

  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return null;
  }

  const context = data as unknown as AdminMemberContext;

  if (!context.profile?.user_id) {
    return null;
  }

  return {
    profile: context.profile,
    offerings: Array.isArray(context.offerings) ? context.offerings : [],
    reports: Array.isArray(context.reports) ? context.reports : [],
    moderation_events: Array.isArray(context.moderation_events)
      ? context.moderation_events
      : [],
  };
}
