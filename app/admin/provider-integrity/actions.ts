"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireDatabaseAdmin } from "@/lib/auth/admin";

const MAX_BIGINT = "9223372036854775807";

function readConflictId(formData: FormData) {
  const value = String(formData.get("conflict_id") || "").trim();
  if (
    !/^[1-9]\d{0,18}$/.test(value) ||
    (value.length === 19 && value > MAX_BIGINT)
  ) {
    redirect("/admin/provider-integrity?error=invalid_case");
  }
  return value;
}

export async function resolveProviderIntegrityConflict(formData: FormData) {
  const conflictId = readConflictId(formData);
  const note = String(formData.get("resolution_note") || "").trim();
  const detailPath = `/admin/provider-integrity/${conflictId}`;

  if (note.length < 12 || note.length > 2000) {
    redirect(`${detailPath}?error=note_required`);
  }

  const { supabase } = await requireDatabaseAdmin(detailPath);
  const { data, error } = await supabase.rpc(
    "admin_resolve_delivery_provider_integrity_conflict",
    {
      p_conflict_id: conflictId,
      p_resolution_note: note,
    },
  );

  if (error) {
    redirect(`${detailPath}?error=failed`);
  }

  if (data !== true) {
    redirect(`${detailPath}?error=already_resolved`);
  }

  revalidatePath("/admin");
  revalidatePath("/admin/provider-integrity");
  revalidatePath(detailPath);

  redirect(`${detailPath}?updated=resolved`);
}
