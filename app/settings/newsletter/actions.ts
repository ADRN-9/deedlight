"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireSignedIn } from "@/lib/auth/admin";

export async function updateNewsletterPreferenceAction(
  formData: FormData,
) {
  const enabled = formData.get("weekly_enabled") === "on";
  const { supabase } = await requireSignedIn(
    "/settings/newsletter",
  );

  const { data, error } = await supabase.rpc(
    "set_newsletter_preference",
    { p_enabled: enabled },
  );

  if (error) {
    const message =
      error.code === "42501" && enabled
        ? "While community access is suspended, newsletter consent can be turned off but cannot be enabled."
        : "Your newsletter preference could not be saved. Please try again.";

    redirect(
      "/settings/newsletter?error=" +
        encodeURIComponent(message),
    );
  }

  if (data !== enabled) {
    redirect(
      "/settings/newsletter?error=" +
        encodeURIComponent(
          "Your newsletter preference could not be verified.",
        ),
    );
  }

  revalidatePath("/settings/newsletter");
  revalidatePath("/settings/profile");

  redirect(
    `/settings/newsletter?updated=${
      enabled ? "enabled" : "disabled"
    }`,
  );
}
