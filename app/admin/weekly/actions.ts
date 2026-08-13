"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireDatabaseAdmin } from "@/lib/auth/admin";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function saveWeeklyFeatureAction(formData: FormData) {
  const { supabase } = await requireDatabaseAdmin("/admin/weekly");

  const raw = String(formData.get("offering_id") || "").trim();
  let offeringId: string | null = null;

  if (raw && raw !== "none") {
    if (!UUID_PATTERN.test(raw)) {
      redirect("/admin/weekly?error=invalid_offering");
    }
    offeringId = raw;
  }

  const { error } = await supabase.rpc("set_weekly_goodness_feature", {
    p_offering_id: offeringId,
  });

  if (error) {
    redirect(
      `/admin/weekly?error=${encodeURIComponent(
        error.message || "Unable to update Weekly Goodness.",
      )}`,
    );
  }

  revalidatePath("/weekly");
  revalidatePath("/admin/weekly");
  revalidatePath("/api/share/weekly");

  redirect("/admin/weekly?updated=weekly_feature");
}
