import { createClient } from "@/lib/supabase/server";

export type NewsletterPreference = {
  exists: boolean;
  weekly_enabled: boolean;
  consented_at: string | null;
  unsubscribed_at: string | null;
  consent_source: "signup" | "settings" | null;
};

const DEFAULT_PREFERENCE: NewsletterPreference = {
  exists: false,
  weekly_enabled: false,
  consented_at: null,
  unsubscribed_at: null,
  consent_source: null,
};

export async function getNewsletterPreference(
  userId: string,
): Promise<NewsletterPreference> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("newsletter_preferences")
    .select(
      "weekly_enabled,consented_at,unsubscribed_at,consent_source",
    )
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    console.error("[getNewsletterPreference] query failed", {
      code: error.code,
      message: error.message,
    });
    throw new Error("Newsletter preference is unavailable.");
  }

  if (!data) return DEFAULT_PREFERENCE;

  return {
    exists: true,
    weekly_enabled: data.weekly_enabled === true,
    consented_at: data.consented_at ?? null,
    unsubscribed_at: data.unsubscribed_at ?? null,
    consent_source:
      data.consent_source === "signup" ||
      data.consent_source === "settings"
        ? data.consent_source
        : null,
  };
}
