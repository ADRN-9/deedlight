import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { hasAdminAccess } from "@/lib/auth/admin-access";

export async function requireAdmin(nextPath = "/admin") {
  const supabase = await createClient();
  const {
    data: { user }
  } = await supabase.auth.getUser();

  if (!user) redirect(`/login?next=${encodeURIComponent(nextPath)}`);

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("role, is_suspended")
    .eq("user_id", user.id)
    .maybeSingle();

  if (!hasAdminAccess({ email: user.email, profile, profileError })) {
    redirect("/today");
  }

  return { supabase, user, profile };
}

export async function requireDatabaseAdmin(nextPath = "/admin/members") {
  const context = await requireAdmin(nextPath);

  if (
    context.profile?.role !== "admin" ||
    context.profile?.is_suspended === true
  ) {
    redirect("/admin?error=database_admin_required");
  }

  return context;
}

export async function requireSignedIn(nextPath = "/journey") {
  const supabase = await createClient();
  const {
    data: { user }
  } = await supabase.auth.getUser();

  if (!user) redirect(`/login?next=${encodeURIComponent(nextPath)}`);

  return { supabase, user };
}
