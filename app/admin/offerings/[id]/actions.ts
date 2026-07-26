"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth/admin";

const idSchema = z.string().uuid();

const editSchema = z.object({
  id: z.string().uuid(),
  title: z.string().trim().min(8, "Title needs at least 8 characters.").max(160, "Title is too long."),
  body: z.string().trim().min(20, "Story needs at least 20 characters.").max(3000, "Story is too long."),
  takeaway: z.string().trim().max(500, "Small deed is too long.").optional(),
  offering_type: z.string().trim().min(2).max(80),
  media_url: z.string().trim().max(1000).optional(),
  media_type: z.string().trim().max(60).optional(),
  location_label: z.string().trim().max(140).optional(),
  is_anonymous: z.boolean(),
  allow_reflections: z.boolean()
});

function readId(formData: FormData) {
  return idSchema.parse(String(formData.get("id") || ""));
}

function readNote(formData: FormData) {
  const note = String(formData.get("moderation_note") || "").trim();
  return note.length ? note.slice(0, 1000) : null;
}

function cleanOptional(value: string | undefined) {
  const clean = (value || "").trim();
  return clean.length ? clean : null;
}

export async function editOfferingContent(formData: FormData) {
  const parsed = editSchema.safeParse({
    id: String(formData.get("id") || ""),
    title: String(formData.get("title") || ""),
    body: String(formData.get("body") || ""),
    takeaway: String(formData.get("takeaway") || ""),
    offering_type: String(formData.get("offering_type") || "good_deed"),
    media_url: String(formData.get("media_url") || ""),
    media_type: String(formData.get("media_type") || ""),
    location_label: String(formData.get("location_label") || ""),
    is_anonymous: formData.get("is_anonymous") === "on",
    allow_reflections: formData.get("allow_reflections") === "on"
  });

  if (!parsed.success) {
    const firstError = parsed.error.issues[0]?.message || "Please check the edited content.";
    const fallbackId = String(formData.get("id") || "");
    redirect(`/admin/offerings/${fallbackId}?error=${encodeURIComponent(firstError)}`);
  }

  const value = parsed.data;
  const { supabase } = await requireAdmin(`/admin/offerings/${value.id}`);

  const { error } = await supabase
    .from("offerings")
    .update({
      title: value.title,
      body: value.body,
      takeaway: cleanOptional(value.takeaway),
      offering_type: value.offering_type,
      media_url: cleanOptional(value.media_url),
      media_type: cleanOptional(value.media_type),
      location_label: cleanOptional(value.location_label),
      is_anonymous: value.is_anonymous,
      allow_reflections: value.allow_reflections
    })
    .eq("id", value.id);

  if (error) redirect(`/admin/offerings/${value.id}?error=${encodeURIComponent(error.message)}`);

  revalidatePath("/offerings");
  revalidatePath(`/offerings/${value.id}`);
  revalidatePath("/rising");
  revalidatePath("/admin/offerings");
  revalidatePath(`/admin/offerings/${value.id}`);
  redirect(`/admin/offerings/${value.id}?updated=edited`);
}

export async function approveOffering(formData: FormData) {
  const id = readId(formData);
  const { supabase } = await requireAdmin(`/admin/offerings/${id}`);

  const { error } = await supabase
    .from("offerings")
    .update({ status: "approved", published_at: new Date().toISOString(), moderation_note: null })
    .eq("id", id);

  if (error) redirect(`/admin/offerings/${id}?error=${encodeURIComponent(error.message)}`);

  revalidatePath("/offerings");
  revalidatePath(`/offerings/${id}`);
  revalidatePath("/rising");
  revalidatePath("/admin/offerings");
  redirect(`/admin/offerings/${id}?updated=approved`);
}

export async function rejectOffering(formData: FormData) {
  const id = readId(formData);
  const note = readNote(formData);
  const { supabase } = await requireAdmin(`/admin/offerings/${id}`);

  const { error } = await supabase
    .from("offerings")
    .update({ status: "rejected", moderation_note: note })
    .eq("id", id);

  if (error) redirect(`/admin/offerings/${id}?error=${encodeURIComponent(error.message)}`);

  revalidatePath("/offerings");
  revalidatePath("/rising");
  revalidatePath("/admin/offerings");
  redirect(`/admin/offerings/${id}?updated=rejected`);
}

export async function requestOfferingEdit(formData: FormData) {
  const id = readId(formData);
  const note = readNote(formData);
  const { supabase } = await requireAdmin(`/admin/offerings/${id}`);

  const { error } = await supabase
    .from("offerings")
    .update({ status: "needs_edit", moderation_note: note || "Please revise this Offering so it better protects dignity and inspires goodness." })
    .eq("id", id);

  if (error) redirect(`/admin/offerings/${id}?error=${encodeURIComponent(error.message)}`);

  revalidatePath("/admin/offerings");
  redirect(`/admin/offerings/${id}?updated=needs_edit`);
}

export async function hideOffering(formData: FormData) {
  const id = readId(formData);
  const note = readNote(formData);
  const { supabase } = await requireAdmin(`/admin/offerings/${id}`);

  const { error } = await supabase
    .from("offerings")
    .update({ status: "hidden", moderation_note: note || "Hidden by admin review." })
    .eq("id", id);

  if (error) redirect(`/admin/offerings/${id}?error=${encodeURIComponent(error.message)}`);

  revalidatePath("/offerings");
  revalidatePath(`/offerings/${id}`);
  revalidatePath("/rising");
  revalidatePath("/admin/offerings");
  redirect(`/admin/offerings/${id}?updated=hidden`);
}

export async function resolveReportsForOffering(formData: FormData) {
  const id = readId(formData);
  const note = readNote(formData);
  const { supabase, user } = await requireAdmin(`/admin/offerings/${id}`);

  const { error } = await supabase
    .from("reports")
    .update({
      status: "resolved",
      admin_note: note || "Resolved during admin review.",
      resolved_by: user.id,
      resolved_at: new Date().toISOString()
    })
    .eq("offering_id", id)
    .in("status", ["open", "reviewing"]);

  if (error) redirect(`/admin/offerings/${id}?error=${encodeURIComponent(error.message)}`);

  revalidatePath("/admin/reports");
  revalidatePath("/admin/offerings");
  revalidatePath(`/admin/offerings/${id}`);
  redirect(`/admin/offerings/${id}?updated=reports_resolved`);
}

export async function dismissReportsForOffering(formData: FormData) {
  const id = readId(formData);
  const note = readNote(formData);
  const { supabase, user } = await requireAdmin(`/admin/offerings/${id}`);

  const { error } = await supabase
    .from("reports")
    .update({
      status: "dismissed",
      admin_note: note || "Dismissed after admin review.",
      resolved_by: user.id,
      resolved_at: new Date().toISOString()
    })
    .eq("offering_id", id)
    .in("status", ["open", "reviewing"]);

  if (error) redirect(`/admin/offerings/${id}?error=${encodeURIComponent(error.message)}`);

  revalidatePath("/admin/reports");
  revalidatePath("/admin/offerings");
  revalidatePath(`/admin/offerings/${id}`);
  redirect(`/admin/offerings/${id}?updated=reports_dismissed`);
}
