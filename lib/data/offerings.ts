import { createClient } from "@/lib/supabase/server";
import { fallbackOfferings } from "./fallback";
import type { Offering } from "@/lib/types";

export async function getApprovedOfferings(limit = 12): Promise<Offering[]> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return fallbackOfferings;

  const { data, error } = await supabase
    .from("offerings_public")
    .select("*")
    .order("bless_score", { ascending: false })
    .limit(limit);

  if (error || !data) return fallbackOfferings;
  return data as Offering[];
}

export async function getOffering(id: string): Promise<Offering | null> {
  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) return fallbackOfferings.find((item) => item.id === id) || null;

  const { data, error } = await supabase
    .from("offerings_public")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) return null;
  return data as Offering | null;
}
