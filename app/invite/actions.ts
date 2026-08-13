"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireSignedIn } from "@/lib/auth/admin";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function createInvitationLinkAction(
  _formData: FormData,
) {
  const { supabase } = await requireSignedIn("/invite");
  const { error } = await supabase.rpc("create_invitation_link");

  if (error) {
    const message =
      error.code === "42501"
        ? "Invitation links cannot be created while community access is suspended."
        : "An invitation link could not be created right now.";

    redirect(`/invite?error=${encodeURIComponent(message)}`);
  }

  revalidatePath("/invite");
  redirect("/invite?created=1");
}

export async function revokeInvitationLinkAction(
  formData: FormData,
) {
  const { supabase } = await requireSignedIn("/invite");
  const invitationId = String(
    formData.get("invitation_id") || "",
  ).trim();

  if (!UUID_PATTERN.test(invitationId)) {
    redirect(
      "/invite?error=" +
        encodeURIComponent(
          "That invitation link could not be identified.",
        ),
    );
  }

  const { data, error } = await supabase.rpc(
    "revoke_invitation_link",
    { p_invitation_id: invitationId },
  );

  if (error || data !== true) {
    redirect(
      "/invite?error=" +
        encodeURIComponent(
          "That invitation link could not be revoked.",
        ),
    );
  }

  revalidatePath("/invite");
  redirect("/invite?revoked=1");
}
