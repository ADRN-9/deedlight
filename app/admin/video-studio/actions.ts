"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

const allowedVideoStatuses = new Set([
  "not_started",
  "planned",
  "scripted",
  "recorded",
  "posted",
  "archived",
]);

function cleanText(value: FormDataEntryValue | null, maxLength = 5000) {
  const text = String(value ?? "").trim();
  if (!text) return null;
  return text.slice(0, maxLength);
}

function cleanStatus(value: FormDataEntryValue | null) {
  const status = String(value ?? "not_started").trim();
  return allowedVideoStatuses.has(status) ? status : "not_started";
}

function cleanUrl(value: FormDataEntryValue | null) {
  const text = cleanText(value, 800);
  if (!text) return null;

  try {
    const url = new URL(text);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    return url.toString();
  } catch {
    return text;
  }
}

async function getAdminSupabase(next = "/admin/video-studio") {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect(`/login?next=${encodeURIComponent(next)}`);
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("role,is_suspended")
    .eq("user_id", user.id)
    .maybeSingle();

  const isAdmin = profile?.role === "admin" && profile?.is_suspended !== true;

  if (!isAdmin) {
    redirect("/today");
  }

  return supabase;
}

export async function updateVideoStudioAction(id: string, formData: FormData) {
  const supabase = await getAdminSupabase(`/admin/video-studio/${id}`);
  const videoStatus = cleanStatus(formData.get("video_status"));

  const existing = await supabase
    .from("daily_lights")
    .select("video_posted_at")
    .eq("id", id)
    .maybeSingle();

  const shortVideoPublic = formData.get("short_video_public") === "on";
  const shouldStampPostedAt =
    videoStatus === "posted" && !existing.data?.video_posted_at;

  const { error } = await supabase
    .from("daily_lights")
    .update({
      video_status: videoStatus,
      video_platform: cleanText(formData.get("video_platform"), 80),
      video_title: cleanText(formData.get("video_title"), 180),
      video_hook: cleanText(formData.get("video_hook"), 500),
      video_script: cleanText(formData.get("video_script"), 6000),
      video_caption: cleanText(formData.get("video_caption"), 2200),
      video_hashtags: cleanText(formData.get("video_hashtags"), 600),
      video_notes: cleanText(formData.get("video_notes"), 2000),
      video_asset_url: cleanUrl(formData.get("video_asset_url")),
      youtube_url: cleanUrl(formData.get("youtube_url")),
      tiktok_url: cleanUrl(formData.get("tiktok_url")),
      instagram_url: cleanUrl(formData.get("instagram_url")),
      short_video_public: shortVideoPublic,
      video_posted_at: shouldStampPostedAt
        ? new Date().toISOString()
        : existing.data?.video_posted_at ?? null,
    })
    .eq("id", id);

  if (error) {
    redirect(
      `/admin/video-studio/${id}?error=${encodeURIComponent(error.message)}`,
    );
  }

  revalidatePath("/admin/video-studio");
  revalidatePath(`/admin/video-studio/${id}`);
  revalidatePath("/today");
  revalidatePath("/videos");

  redirect(`/admin/video-studio/${id}?updated=saved`);
}

export async function generateVideoDraftAction(id: string) {
  const supabase = await getAdminSupabase(`/admin/video-studio/${id}`);

  const { data: light, error: readError } = await supabase
    .from("daily_lights")
    .select(
      "title,theme,summary,body,small_deed,reflection_prompt,video_title,video_hook,video_script,video_caption,video_hashtags",
    )
    .eq("id", id)
    .maybeSingle();

  if (readError || !light) {
    redirect(`/admin/video-studio/${id}?error=Daily%20light%20not%20found`);
  }

  const title = light.video_title || light.title || "A new light can begin today";
  const hook =
    light.video_hook ||
    light.small_deed ||
    light.summary ||
    "One small act of goodness can become light for someone else.";

  const script = `Hook: ${hook}\n\nToday’s Deedlight: ${light.title}\n\n${
    light.summary || light.body || "Goodness grows when someone chooses it in a real moment."
  }\n\nSmall deed: ${
    light.small_deed || "Choose one small act of goodness and do it quietly today."
  }\n\nReflection: ${
    light.reflection_prompt || "Where can I choose goodness today?"
  }\n\nClose: If this helped you, carry one small light forward today.`;

  const caption = `${light.title}\n\n${
    light.small_deed || light.summary || "One small act of goodness can become light."
  }\n\nCarry one small light forward today.`;

  const hashtags = light.video_hashtags || "#Deedlight #GoodDeeds #Kindness #DailyReflection";

  const { error } = await supabase
    .from("daily_lights")
    .update({
      video_status: "scripted",
      video_platform: "YouTube Shorts / TikTok / Reels",
      video_title: title.slice(0, 180),
      video_hook: hook.slice(0, 500),
      video_script: script.slice(0, 6000),
      video_caption: caption.slice(0, 2200),
      video_hashtags: hashtags.slice(0, 600),
    })
    .eq("id", id);

  if (error) {
    redirect(
      `/admin/video-studio/${id}?error=${encodeURIComponent(error.message)}`,
    );
  }

  revalidatePath("/admin/video-studio");
  revalidatePath(`/admin/video-studio/${id}`);

  redirect(`/admin/video-studio/${id}?updated=generated`);
}
