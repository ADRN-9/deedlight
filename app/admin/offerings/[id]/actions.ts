"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth/admin";

const idSchema = z.string().uuid();

function readId(formData: FormData) {
  return idSchema.parse(String(formData.get("id") || ""));
}

function readNote(formData: FormData) {
  const note = String(formData.get("moderation_note") || "").trim();
  return note.length ? note.slice(0, 1000) : null;
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
  revalidatePath("/admin/offerings");
  redirect(`/admin/offerings/${id}?updated=rejected`);
}

export async function requestOfferingEdit(formData: FormData) {
  const id = readId(formData);
  const note = readNote(formData);
  const { supabase } = await requireAdmin(`/admin/offerings/${id}`);

  const { error } = await supabase
    .from("offerings")
    .update({ status: "needs_edit", moderation_note: note })
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
    .update({ status: "hidden", moderation_note: note })
    .eq("id", id);

  if (error) redirect(`/admin/offerings/${id}?error=${encodeURIComponent(error.message)}`);

  revalidatePath("/offerings");
  revalidatePath(`/offerings/${id}`);
  revalidatePath("/admin/offerings");
  redirect(`/admin/offerings/${id}?updated=hidden`);
}
