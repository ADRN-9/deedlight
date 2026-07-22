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
  title: z.string().min(4).max(120),
  body: z.string().min(20).max(5000),
  takeaway: z.string().max(500).optional(),
  is_anonymous: z.boolean(),
  allow_reflections: z.boolean()
});

export async function createOffering(formData: FormData) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) redirect("/login?next=/offerings/new");

  const parsed = offeringSchema.safeParse({
    offering_type: formData.get("offering_type"),
    title: formData.get("title"),
    body: formData.get("body"),
    takeaway: String(formData.get("takeaway") || ""),
    is_anonymous: formData.get("is_anonymous") === "on",
    allow_reflections: formData.get("allow_reflections") === "on"
  });

  if (!parsed.success) {
    redirect("/offerings/new?error=Please complete the required fields with enough detail.");
  }

  const { error } = await supabase.from("offerings").insert({
    user_id: user.id,
    ...parsed.data,
    status: "pending"
  });

  if (error) {
    redirect(`/offerings/new?error=${encodeURIComponent(error.message)}`);
  }

  redirect("/journey?submitted=1");
}
