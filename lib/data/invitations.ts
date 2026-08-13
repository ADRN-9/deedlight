import { createClient } from "@/lib/supabase/server";

export const INVITATION_CODE_PATTERN = /^[a-f0-9]{36}$/;

export type InvitationLink = {
  id: string;
  code: string;
  accepted_count: number;
  expires_at: string;
  revoked_at: string | null;
  created_at: string;
};

export function normalizeInvitationCode(value: unknown) {
  const code = String(value || "").trim().toLowerCase();
  return INVITATION_CODE_PATTERN.test(code) ? code : null;
}

export async function isInvitationCodeActive(code: string) {
  const normalized = normalizeInvitationCode(code);
  if (!normalized) return false;

  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return false;

  const { data, error } = await supabase.rpc(
    "validate_invitation_code",
    { p_code: normalized },
  );

  if (error) {
    console.error("[isInvitationCodeActive] validation failed", {
      code: error.code,
      message: error.message,
    });
    return false;
  }

  return data === true;
}

export async function getMyInvitationLinks(
  userId: string,
): Promise<InvitationLink[]> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("invitation_links")
    .select(
      "id,code,accepted_count,expires_at,revoked_at,created_at",
    )
    .eq("inviter_user_id", userId)
    .order("created_at", { ascending: false })
    .limit(20);

  if (error) {
    console.error("[getMyInvitationLinks] query failed", {
      code: error.code,
      message: error.message,
    });
    throw new Error("Invitation links are unavailable.");
  }

  return (data || []) as InvitationLink[];
}
