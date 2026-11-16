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

type OfferingUpdate = Record<string, string | number | boolean | null>;

function readId(formData: FormData) {
  return idSchema.parse(String(formData.get("id") || ""));
}

// These fields have different audiences. Never use the internal note as
// member-visible feedback, including when the feedback field is blank.
const decisionTextSchema = z.object({
  moderation_note: z.string().trim().max(1000),
  owner_feedback: z.string().trim().max(1000),
});

function readModerationDecision(formData: FormData, id: string): {
  moderation_note: string | null;
  owner_feedback: string | null;
} {
  const parsed = decisionTextSchema.safeParse({
    moderation_note: formData.get("moderation_note") ?? "",
    owner_feedback: formData.get("owner_feedback") ?? "",
  });
  if (!parsed.success) {
    redirect(`/admin/offerings/${id}?error=Moderation%20fields%20must%20be%20text%20of%20at%20most%201000%20characters`);
  }
  return {
    moderation_note: parsed.data.moderation_note || null,
    owner_feedback: parsed.data.owner_feedback || null,
  };
}

// Decision transitions replace both fields. Empty feedback deliberately clears
// prior owner-facing text instead of revealing, copying, or retaining staff notes.
function readNote(formData: FormData) {
  const parsed = z.string().trim().max(1000).safeParse(formData.get("moderation_note") ?? "");
  return parsed.success ? parsed.data || null : null;
}

function cleanOptional(value: string | undefined) {
  const clean = (value || "").trim();
  return clean.length ? clean : null;
}

function parseEditedOffering(formData: FormData) {
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

  return parsed.data;
}

function editedOfferingPayload(value: z.infer<typeof editSchema>): OfferingUpdate {
  return {
    title: value.title,
    body: value.body,
    takeaway: cleanOptional(value.takeaway),
    offering_type: value.offering_type,
    media_url: cleanOptional(value.media_url),
    media_type: cleanOptional(value.media_type),
    location_label: cleanOptional(value.location_label),
    is_anonymous: value.is_anonymous,
    allow_reflections: value.allow_reflections
  };
}

async function updateOfferingOrRedirect(
  supabase: Awaited<ReturnType<typeof requireAdmin>>["supabase"],
  id: string,
  payload: OfferingUpdate,
  updatedSlug: string
) {
  const { data, error } = await supabase
    .from("offerings")
    .update({ ...payload, updated_at: new Date().toISOString() })
    .eq("id", id)
    .select("id,status")
    .maybeSingle();

  if (error) redirect(`/admin/offerings/${id}?error=${encodeURIComponent(error.message)}`);

  if (!data) {
    redirect(
      `/admin/offerings/${id}?error=${encodeURIComponent(
        "No Offering row was updated. Please confirm this account is admin and the Sprint 5 RLS migration has been applied."
      )}`
    );
  }

  revalidatePath("/offerings");
  revalidatePath(`/offerings/${id}`);
  revalidatePath("/rising");
  revalidatePath("/admin");
  revalidatePath("/admin/offerings");
  revalidatePath(`/admin/offerings/${id}`);
  revalidatePath("/admin/reports");
  redirect(`/admin/offerings/${id}?updated=${updatedSlug}`);
}

export async function editOfferingContent(formData: FormData) {
  const value = parseEditedOffering(formData);
  const { supabase } = await requireAdmin(`/admin/offerings/${value.id}`);

  await updateOfferingOrRedirect(supabase, value.id, editedOfferingPayload(value), "edited");
}

export async function editAndApproveOffering(formData: FormData) {
  const value = parseEditedOffering(formData);
  const { supabase } = await requireAdmin(`/admin/offerings/${value.id}`);

  await updateOfferingOrRedirect(
    supabase,
    value.id,
    {
      ...editedOfferingPayload(value),
      status: "approved",
      published_at: new Date().toISOString(),
      moderation_note: null,
      owner_feedback: null
    },
    "edited_and_approved"
  );
}

export async function approveOffering(formData: FormData) {
  const id = readId(formData);
  const { supabase } = await requireAdmin(`/admin/offerings/${id}`);

  await updateOfferingOrRedirect(
    supabase,
    id,
    { status: "approved", published_at: new Date().toISOString(), moderation_note: null, owner_feedback: null },
    "approved"
  );
}

export async function rejectOffering(formData: FormData) {
  const id = readId(formData);
  const { supabase } = await requireAdmin(`/admin/offerings/${id}`);
  const notes = readModerationDecision(formData, id);

  await updateOfferingOrRedirect(supabase, id, { status: "rejected", ...notes }, "rejected");
}

export async function requestOfferingEdit(formData: FormData) {
  const id = readId(formData);
  const { supabase } = await requireAdmin(`/admin/offerings/${id}`);
  const notes = readModerationDecision(formData, id);

  await updateOfferingOrRedirect(
    supabase,
    id,
    { status: "needs_edit", ...notes },
    "needs_edit"
  );
}

export async function hideOffering(formData: FormData) {
  const id = readId(formData);
  const { supabase } = await requireAdmin(`/admin/offerings/${id}`);
  const notes = readModerationDecision(formData, id);

  await updateOfferingOrRedirect(
    supabase,
    id,
    { status: "hidden", ...notes },
    "hidden"
  );
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
      admin_note: note || "Dismissed after review.",
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
