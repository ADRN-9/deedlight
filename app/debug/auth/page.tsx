import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getSupabaseConfig } from "@/lib/supabase/config";
import { hasAdminAccess } from "@/lib/auth/admin-access";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default async function DebugAuthPage() {
  const supabase = await createClient({ allowMissingEnv: true });

  if (!supabase) notFound();

  const {
    data: { user }
  } = await supabase.auth.getUser();

  if (!user) notFound();

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("role,is_suspended")
    .eq("user_id", user.id)
    .maybeSingle();

  const isAdmin = hasAdminAccess({
    email: user.email,
    profile,
    profileError,
  });

  if (!isAdmin) notFound();

  const config = getSupabaseConfig();

  return (
    <section className="mx-auto max-w-4xl px-4 py-12 sm:px-6">
      <h1 className="font-[var(--font-heading)] text-4xl font-semibold">Deedlight Auth Debug</h1>
      <p className="mt-3 leading-7 text-[#5F5548]">This protected page verifies Supabase runtime configuration without exposing secrets.</p>

      <pre className="mt-7 overflow-auto rounded-3xl bg-[#111] p-6 text-sm leading-7 text-white">
        {JSON.stringify(
          {
            ok: true,
            protected: "admin_only",
            serverEnv: {
              supabaseUrlSet: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
              supabaseAnonKeySet: Boolean(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY),
              serviceRoleKeySet: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
              siteUrl: process.env.NEXT_PUBLIC_SITE_URL || null
            },
            browserConfig: {
              isConfigured: config.isConfigured,
              normalizedUrl: config.url || null,
              rawUrlIsValid: Boolean(config.url && /^https?:\/\//.test(config.url)),
              anonKeyPresent: Boolean(config.anonKey),
              anonKeyPrefix: config.anonKey ? config.anonKey.slice(0, 14) : null
            },
            notes: [
              "This page is admin-only.",
              "This page intentionally never prints the full anon key or service role key."
            ]
          },
          null,
          2
        )}
      </pre>
    </section>
  );
}
