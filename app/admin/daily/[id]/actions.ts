"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requireAdmin } from "@/lib/data/daily";
import type { DailyStatus, DailyVideoStatus } from "@/lib/types-daily";

const DAILY_STATUSES: DailyStatus[] = ["draft", "scheduled", "published", "archived"];
const VIDEO_STATUSES: DailyVideoStatus[] = ["idea", "scripted", "recorded", "published"];

function textValue(formData: FormData, key: string): string | null {
  const value = formData.get(key);
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function requiredText(formData: FormData, key: string): string {
  return textValue(formData, key) ?? "";
}

function dateValue(formData: FormData, key: string): string {
  const value = textValue(formData, key);
  if (!value) return new Date().toISOString().slice(0, 10);
  return value;
}

function normalizeStatus(value: string | null): DailyStatus {
  if (value && DAILY_STATUSES.includes(value as DailyStatus)) return value as DailyStatus;
  return "draft";
}

function normalizeVideoStatus(value: string | null): DailyVideoStatus {
  if (value && VIDEO_STATUSES.includes(value as DailyVideoStatus)) return value as DailyVideoStatus;
  return "idea";
}

function slugify(input: string): string {
  return input
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

function buildPayload(formData: FormData, userId: string) {
  const title = requiredText(formData, "title");
  const scheduledFor = dateValue(formData, "scheduled_for");
  const submittedSlug = textValue(formData, "slug");
  const featuredOfferingId = textValue(formData, "featured_offering_id");
  const status = normalizeStatus(textValue(formData, "status"));
  const videoStatus = normalizeVideoStatus(textValue(formData, "video_status"));

  return {
    slug: submittedSlug ?? slugify(`${scheduledFor}-${title}`),
    scheduled_for: scheduledFor,
    status,
    kicker: textValue(formData, "kicker") ?? "TODAY’S DEEDLIGHT",
    title,
    theme: textValue(formData, "theme"),
    summary: textValue(formData, "summary"),
    body: textValue(formData, "body"),
    small_deed: textValue(formData, "small_deed"),
    reflection_prompt: textValue(formData, "reflection_prompt"),
    featured_offering_id: featuredOfferingId === "none" ? null : featuredOfferingId,
    image_url: textValue(formData, "image_url"),
    video_title: textValue(formData, "video_title"),
    video_hook: textValue(formData, "video_hook"),
    video_script: textValue(formData, "video_script"),
    video_caption: textValue(formData, "video_caption"),
    youtube_url: textValue(formData, "youtube_url"),
    video_status: videoStatus,
    updated_at: new Date().toISOString(),
    created_by: userId,
  };
}

function validateDailyPost(formData: FormData): string | null {
  const title = requiredText(formData, "title");
  const summary = requiredText(formData, "summary");
  const smallDeed = requiredText(formData, "small_deed");

  if (title.length < 8) return "Title must be at least 8 characters.";
  if (summary.length < 20) return "Summary must be at least 20 characters.";
  if (smallDeed.length < 10) return "Small deed must be at least 10 characters.";
  return null;
}

export async function createDailyPostAction(formData: FormData) {
  const { supabase, user } = await requireAdmin();
  const validationError = validateDailyPost(formData);

  if (validationError) {
    redirect(`/admin/daily/new?error=${encodeURIComponent(validationError)}`);
  }

  const payload = buildPayload(formData, user.id);
  const shouldPublish = formData.get("publish_now") === "yes";
  const finalPayload = {
    ...payload,
    status: shouldPublish ? "published" : payload.status,
    published_at: shouldPublish ? new Date().toISOString() : null,
    archived_at: null,
  };

  const { data, error } = await supabase.from("daily_posts").insert(finalPayload).select("id").single();

  if (error || !data?.id) {
    redirect(`/admin/daily/new?error=${encodeURIComponent(error?.message ?? "Daily Deedlight could not be created.")}`);
  }

  revalidatePath("/today");
  revalidatePath("/today/archive");
  revalidatePath("/admin/daily");
  redirect(`/admin/daily/${data.id}?updated=created`);
}

export async function saveDailyPostAction(formData: FormData) {
  const { supabase, user } = await requireAdmin();
  const id = requiredText(formData, "id");
  const validationError = validateDailyPost(formData);

  if (!id) {
    redirect("/admin/daily?error=Missing%20daily%20post%20id");
  }

  if (validationError) {
    redirect(`/admin/daily/${id}?error=${encodeURIComponent(validationError)}`);
  }

  const payload = buildPayload(formData, user.id);

  const { error, count } = await supabase
    .from("daily_posts")
    .update(payload, { count: "exact" })
    .eq("id", id);

  if (error || count === 0) {
    redirect(`/admin/daily/${id}?error=${encodeURIComponent(error?.message ?? "No daily post was updated.")}`);
  }

  revalidatePath("/today");
  revalidatePath("/today/archive");
  revalidatePath("/admin/daily");
  revalidatePath(`/admin/daily/${id}`);
  redirect(`/admin/daily/${id}?updated=saved`);
}

export async function publishDailyPostAction(formData: FormData) {
  const { supabase } = await requireAdmin();
  const id = requiredText(formData, "id");

  if (!id) {
    redirect("/admin/daily?error=Missing%20daily%20post%20id");
  }

  const { error, count } = await supabase
    .from("daily_posts")
    .update(
      {
        status: "published",
        published_at: new Date().toISOString(),
        archived_at: null,
        updated_at: new Date().toISOString(),
      },
      { count: "exact" }
    )
    .eq("id", id);

  if (error || count === 0) {
    redirect(`/admin/daily/${id}?error=${encodeURIComponent(error?.message ?? "Daily post was not published.")}`);
  }

  revalidatePath("/today");
  revalidatePath("/today/archive");
  revalidatePath("/admin/daily");
  redirect(`/admin/daily/${id}?updated=published`);
}

export async function saveAndPublishDailyPostAction(formData: FormData) {
  const { supabase, user } = await requireAdmin();
  const id = requiredText(formData, "id");
  const validationError = validateDailyPost(formData);

  if (!id) {
    redirect("/admin/daily?error=Missing%20daily%20post%20id");
  }

  if (validationError) {
    redirect(`/admin/daily/${id}?error=${encodeURIComponent(validationError)}`);
  }

  const payload = buildPayload(formData, user.id);

  const { error, count } = await supabase
    .from("daily_posts")
    .update(
      {
        ...payload,
        status: "published",
        published_at: new Date().toISOString(),
        archived_at: null,
      },
      { count: "exact" }
    )
    .eq("id", id);

  if (error || count === 0) {
    redirect(`/admin/daily/${id}?error=${encodeURIComponent(error?.message ?? "Daily post was not saved and published.")}`);
  }

  revalidatePath("/today");
  revalidatePath("/today/archive");
  revalidatePath("/admin/daily");
  redirect(`/admin/daily/${id}?updated=saved_and_published`);
}

export async function scheduleDailyPostAction(formData: FormData) {
  const { supabase } = await requireAdmin();
  const id = requiredText(formData, "id");

  if (!id) {
    redirect("/admin/daily?error=Missing%20daily%20post%20id");
  }

  const { error, count } = await supabase
    .from("daily_posts")
    .update(
      {
        status: "scheduled",
        published_at: null,
        archived_at: null,
        updated_at: new Date().toISOString(),
      },
      { count: "exact" }
    )
    .eq("id", id);

  if (error || count === 0) {
    redirect(`/admin/daily/${id}?error=${encodeURIComponent(error?.message ?? "Daily post was not scheduled.")}`);
  }

  revalidatePath("/admin/daily");
  redirect(`/admin/daily/${id}?updated=scheduled`);
}

export async function archiveDailyPostAction(formData: FormData) {
  const { supabase } = await requireAdmin();
  const id = requiredText(formData, "id");

  if (!id) {
    redirect("/admin/daily?error=Missing%20daily%20post%20id");
  }

  const { error, count } = await supabase
    .from("daily_posts")
    .update(
      {
        status: "archived",
        archived_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      },
      { count: "exact" }
    )
    .eq("id", id);

  if (error || count === 0) {
    redirect(`/admin/daily/${id}?error=${encodeURIComponent(error?.message ?? "Daily post was not archived.")}`);
  }

  revalidatePath("/today");
  revalidatePath("/today/archive");
  revalidatePath("/admin/daily");
  redirect(`/admin/daily/${id}?updated=archived`);
}
