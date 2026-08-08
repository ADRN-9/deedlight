"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireSignedIn } from "@/lib/auth/admin";
import { parseProfileForm } from "@/lib/profile/validation";

export async function updateProfileAction(formData: FormData) {
  const parsed = parseProfileForm(formData);

  if (!parsed.ok) {
    redirect(
      `/settings/profile?error=${encodeURIComponent(parsed.error)}`,
    );
  }

  const { supabase, user } = await requireSignedIn(
    "/settings/profile",
  );

  const value = parsed.data;

  const { error } = await supabase
    .from("profiles")
    .update({
      username: value.username,
      display_name: value.displayName,
      bio: value.bio,
      country: value.country,
      is_public: value.isPublic,
      show_contribution_stats:
        value.showContributionStats,
      default_offering_anonymous:
        value.defaultOfferingAnonymous,
    })
    .eq("user_id", user.id);

  if (error) {
    const message =
      error.code === "23505"
        ? "That username is already in use."
        : "Your profile could not be saved. Please try again.";

    redirect(
      `/settings/profile?error=${encodeURIComponent(message)}`,
    );
  }

  revalidatePath("/settings/profile");
  revalidatePath(`/people/${value.username}`);
  revalidatePath("/offerings");
  revalidatePath("/today");

  redirect("/settings/profile?updated=1");
}
