import { requireAdmin } from "@/lib/auth/admin";
import { getSupabaseBrowserConfig, getSupabaseConfig } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

export default async function DebugAuthPage() {
  await requireAdmin("/debug/auth");

  const serverConfig = getSupabaseConfig();
  const browserConfig = getSupabaseBrowserConfig();

  const safePayload = {
    ok: true,
    protected: "admin_only",
    serverEnv: {
      supabaseUrlSet: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
      supabaseAnonKeySet: Boolean(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY),
      serviceRoleKeySet: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
      siteUrl: process.env.NEXT_PUBLIC_SITE_URL || null
    },
    browserConfig: {
      isConfigured: browserConfig.isConfigured,
      normalizedUrl: browserConfig.url,
      rawUrlIsValid: browserConfig.rawUrlIsValid,
      urlFallbackUsed: browserConfig.urlFallbackUsed,
      anonKeyPresent: Boolean(browserConfig.anonKey),
      anonKeyPrefix: browserConfig.anonKey ? browserConfig.anonKey.slice(0, 14) : null
    },
    serverConfig: {
      isConfigured: serverConfig.isConfigured,
      normalizedUrl: serverConfig.url,
      rawUrlIsValid: serverConfig.rawUrlIsValid,
      urlFallbackUsed: serverConfig.urlFallbackUsed
    },
    notes: [
      "This page is now admin-only.",
      "This page intentionally never prints the full anon key or service role key."
    ]
  };

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Admin · Debug</p>
      <h1 className="mt-3 font-[var(--font-heading)] text-4xl font-semibold">Deedlight Auth Debug</h1>
      <p className="mt-3 leading-8 text-[#7C715F]">This protected page verifies Supabase runtime configuration without exposing secrets.</p>
      <pre className="mt-6 overflow-x-auto rounded-3xl bg-[#111] p-6 text-sm leading-7 text-white">
        {JSON.stringify(safePayload, null, 2)}
      </pre>
    </section>
  );
}
