"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

const offeringSchema = z.object({
  offering_type: z.enum([
    "good_deed",
    "goodness_invitation",
    "gratitude",
    "beauty_reminder",
    "quiet_goodness",
    "community_need"
  ]),
  theme_slug: z.string().min(1).max(60).optional(),
  title: z.string().trim().min(4).max(120),
  body: z.string().trim().min(20).max(5000),
  takeaway: z.string().trim().max(500).optional(),
  media_url: z.string().trim().max(1000).optional(),
  is_anonymous: z.boolean(),
  allow_reflections: z.boolean()
});

export async function createOffering(formData: FormData) {
  const supabase = await createClient();
  const {
    data: { user }
  } = await supabase.auth.getUser();

  if (!user) redirect("/login?next=/offerings/new");

  const mediaUrl = String(formData.get("media_url") || "").trim();

  const parsed = offeringSchema.safeParse({
    offering_type: formData.get("offering_type"),
    theme_slug: String(formData.get("theme_slug") || "kindness"),
    title: formData.get("title"),
    body: formData.get("body"),
    takeaway: String(formData.get("takeaway") || ""),
    media_url: mediaUrl,
    is_anonymous: formData.get("is_anonymous") === "on",
    allow_reflections: formData.get("allow_reflections") === "on"
  });

  if (!parsed.success) {
    redirect("/offerings/new?error=Please complete the required fields with enough detail.");
  }

  let themeId: string | null = null;
  if (parsed.data.theme_slug) {
    const { data: theme } = await supabase
      .from("themes")
      .select("id")
      .eq("slug", parsed.data.theme_slug)
      .maybeSingle();
    themeId = theme?.id ?? null;
  }

  const safeMediaUrl = parsed.data.media_url || null;
  const mediaType = safeMediaUrl
    ? safeMediaUrl.includes("youtube.com") || safeMediaUrl.includes("youtu.be") || safeMediaUrl.endsWith(".mp4")
      ? "video"
      : "image"
    : null;

  const { error } = await supabase.from("offerings").insert({
    user_id: user.id,
    theme_id: themeId,
    offering_type: parsed.data.offering_type,
    title: parsed.data.title,
    body: parsed.data.body,
    takeaway: parsed.data.takeaway || null,
    media_url: safeMediaUrl,
    media_type: mediaType,
    is_anonymous: parsed.data.is_anonymous,
    allow_reflections: parsed.data.allow_reflections,
    status: "pending"
  });

  if (error) {
    redirect(`/offerings/new?error=${encodeURIComponent(error.message)}`);
  }

  redirect("/journey?submitted=1");
}
