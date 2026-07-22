import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function requireAdmin(nextPath = "/admin") {
  const supabase = await createClient();
  const {
    data: { user }
  } = await supabase.auth.getUser();

  if (!user) redirect(`/login?next=${encodeURIComponent(nextPath)}`);

  const { data: profile, error } = await supabase
    .from("profiles")
    .select("role, is_suspended")
    .eq("user_id", user.id)
    .maybeSingle();

  if (error || profile?.role !== "admin" || profile?.is_suspended) redirect("/today");

  return { supabase, user, profile };
}

export async function requireSignedIn(nextPath = "/journey") {
  const supabase = await createClient();
  const {
    data: { user }
  } = await supabase.auth.getUser();

  if (!user) redirect(`/login?next=${encodeURIComponent(nextPath)}`);

  return { supabase, user };
}
