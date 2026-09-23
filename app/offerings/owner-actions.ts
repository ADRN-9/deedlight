"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const offeringSchema = z.object({
  offeringType: z.enum([
    "good_deed",
    "goodness_invitation",
    "gratitude",
    "beauty_reminder",
    "quiet_goodness",
    "community_need",
  ]),
  title: z.string().trim().min(4).max(120),
  body: z.string().trim().min(20).max(5000),
  takeaway: z.string().trim().max(500),
  mediaUrl: z
    .string()
    .trim()
    .max(1000)
    .refine((value) => !value || /^https?:\/\//i.test(value), {
      message: "Media URL must start with http:// or https://.",
    }),
  isAnonymous: z.boolean(),
  allowReflections: z.boolean(),
});

function cleanUuid(value: FormDataEntryValue | null) {
  const candidate = String(value ?? "").trim();
  return UUID_PATTERN.test(candidate) ? candidate : "";
}

function inferMediaType(url: string) {
  const clean = url.trim().toLowerCase();
  if (!clean) return null;

  if (
    clean.includes("youtube.com") ||
    clean.includes("youtu.be") ||
    /\.(mp4|mov|webm|m4v)(\?.*)?$/.test(clean)
  ) {
    return "video";
  }

  return "image";
}

function editErrorPath(offeringId: string, message: string) {
  return `/offerings/${encodeURIComponent(offeringId)}/edit?error=${encodeURIComponent(message)}`;
}

async function requireOwnerActionUser(nextPath: string) {
  const supabase = await createClient({ allowMissingEnv: true });

  if (!supabase) {
    redirect(`/login?next=${encodeURIComponent(nextPath)}`);
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect(`/login?next=${encodeURIComponent(nextPath)}`);
  }

  return { supabase, user };
}

function revalidateOfferingSurfaces(offeringId: string) {
  revalidatePath("/");
  revalidatePath("/offerings");
  revalidatePath(`/offerings/${offeringId}`);
  revalidatePath("/rising");
  revalidatePath("/weekly");
  revalidatePath("/today");
  revalidatePath("/journey");
}

export async function updateOwnOfferingAction(formData: FormData) {
  const offeringId = cleanUuid(formData.get("offering_id"));

  if (!offeringId) {
    redirect("/journey?error=This%20Offering%20could%20not%20be%20identified.#my-offerings");
  }

  const nextPath = `/offerings/${offeringId}/edit`;
  const { supabase } = await requireOwnerActionUser(nextPath);

  const parsed = offeringSchema.safeParse({
    offeringType: formData.get("offering_type"),
    title: String(formData.get("title") ?? ""),
    body: String(formData.get("body") ?? ""),
    takeaway: String(formData.get("takeaway") ?? ""),
    mediaUrl: String(formData.get("media_url") ?? ""),
    isAnonymous: formData.get("is_anonymous") === "on",
    allowReflections: formData.get("allow_reflections") === "on",
  });

  if (!parsed.success) {
    const message =
      parsed.error.issues[0]?.message ||
      "Please review the Offering fields and try again.";
    redirect(editErrorPath(offeringId, message));
  }

  const value = parsed.data;
  const mediaUrl = value.mediaUrl || null;

  const { error } = await supabase.rpc("update_own_offering", {
    p_offering_id: offeringId,
    p_offering_type: value.offeringType,
    p_title: value.title,
    p_body: value.body,
    p_takeaway: value.takeaway || null,
    p_media_url: mediaUrl,
    p_media_type: mediaUrl ? inferMediaType(mediaUrl) : null,
    p_is_anonymous: value.isAnonymous,
    p_allow_reflections: value.allowReflections,
  });

  if (error) {
    console.error("[updateOwnOfferingAction] RPC failed", {
      code: error.code,
      message: error.message,
      details: error.details,
      hint: error.hint,
    });

    redirect(
      editErrorPath(
        offeringId,
        "Your Offering could not be updated right now. Please try again.",
      ),
    );
  }

  revalidateOfferingSurfaces(offeringId);
  redirect("/journey?offering=updated#my-offerings");
}

export async function removeOwnOfferingAction(formData: FormData) {
  const offeringId = cleanUuid(formData.get("offering_id"));

  if (!offeringId) {
    redirect("/journey?error=This%20Offering%20could%20not%20be%20identified.#my-offerings");
  }

  const { supabase } = await requireOwnerActionUser("/journey");
  const { error } = await supabase.rpc("remove_own_offering", {
    p_offering_id: offeringId,
  });

  if (error) {
    console.error("[removeOwnOfferingAction] RPC failed", {
      code: error.code,
      message: error.message,
      details: error.details,
      hint: error.hint,
    });

    redirect(
      "/journey?error=This%20Offering%20could%20not%20be%20removed%20right%20now.#my-offerings",
    );
  }

  revalidateOfferingSurfaces(offeringId);
  redirect("/journey?offering=removed#my-offerings");
}

export async function restoreOwnOfferingAction(formData: FormData) {
  const offeringId = cleanUuid(formData.get("offering_id"));

  if (!offeringId) {
    redirect("/journey?error=This%20Offering%20could%20not%20be%20identified.#my-offerings");
  }

  const { supabase } = await requireOwnerActionUser("/journey");
  const { error } = await supabase.rpc("restore_own_offering", {
    p_offering_id: offeringId,
  });

  if (error) {
    console.error("[restoreOwnOfferingAction] RPC failed", {
      code: error.code,
      message: error.message,
      details: error.details,
      hint: error.hint,
    });

    redirect(
      "/journey?error=This%20Offering%20could%20not%20be%20restored%20right%20now.#my-offerings",
    );
  }

  revalidateOfferingSurfaces(offeringId);
  redirect("/journey?offering=restored#my-offerings");
}
