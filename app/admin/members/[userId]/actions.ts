"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireDatabaseAdmin } from "@/lib/auth/admin";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function readUserId(formData: FormData) {
  const userId = String(formData.get("user_id") || "").trim();

  if (!UUID_PATTERN.test(userId)) {
    redirect("/admin/members?error=Invalid%20member%20identifier.");
  }

  return userId;
}

function readReason(formData: FormData) {
  const reason = String(formData.get("reason") || "").trim();

  if (reason.length < 8 || reason.length > 500) {
    return null;
  }

  return reason;
}

async function updateMemberSuspension(
  formData: FormData,
  suspended: boolean,
) {
  const userId = readUserId(formData);
  const reason = readReason(formData);

  if (!reason) {
    redirect(
      `/admin/members/${userId}?error=${encodeURIComponent(
        "Please provide a moderation reason between 8 and 500 characters.",
      )}`,
    );
  }

  const { supabase } = await requireDatabaseAdmin(
    `/admin/members/${userId}`,
  );

  const { error } = await supabase.rpc("set_member_suspension", {
    p_member_user_id: userId,
    p_suspended: suspended,
    p_reason: reason,
  });

  if (error) {
    redirect(
      `/admin/members/${userId}?error=${encodeURIComponent(error.message)}`,
    );
  }

  const { data: target } = await supabase
    .from("profiles")
    .select("username")
    .eq("user_id", userId)
    .maybeSingle();

  revalidatePath("/");
  revalidatePath("/offerings");
  revalidatePath("/rising");
  revalidatePath("/quiet");
  revalidatePath("/admin");
  revalidatePath("/admin/members");
  revalidatePath(`/admin/members/${userId}`);
  revalidatePath("/admin/offerings");
  revalidatePath("/admin/reports");

  if (target?.username) {
    revalidatePath(`/people/${target.username}`);
  }

  redirect(
    `/admin/members/${userId}?updated=${
      suspended ? "suspended" : "restored"
    }`,
  );
}

export async function suspendMember(formData: FormData) {
  await updateMemberSuspension(formData, true);
}

export async function restoreMember(formData: FormData) {
  await updateMemberSuspension(formData, false);
}
