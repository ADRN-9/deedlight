"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { normalizeInvitationCode } from "@/lib/data/invitations";

export async function signup(formData: FormData) {
  const email = String(formData.get("email") || "")
    .trim()
    .toLowerCase();
  const password = String(formData.get("password") || "");
  const displayName = String(
    formData.get("display_name") || "",
  ).trim();

  const inviteCode = normalizeInvitationCode(
    formData.get("invite_code"),
  );

  const newsletterOptIn =
    formData.get("newsletter_weekly_opt_in") === "on";

  const supabase = await createClient();
  const { error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: {
        display_name: displayName || "Deedlight member",
        deedlight_invite_code: inviteCode,
        newsletter_weekly_opt_in: newsletterOptIn,
      },
      emailRedirectTo: `${
        process.env.NEXT_PUBLIC_SITE_URL ||
        "http://localhost:3000"
      }/today`,
    },
  });

  if (error) {
    redirect(`/signup?error=${encodeURIComponent(error.message)}`);
  }

  redirect("/today?joined=1");
}
