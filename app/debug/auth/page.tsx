import { getSupabaseConfig, normalizeSupabaseUrl } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

export default function DebugAuthPage() {
  const config = getSupabaseConfig();
  const rawUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? null;
  const normalized = normalizeSupabaseUrl(rawUrl);

  const payload = {
    ok: config.isConfigured,
    serverEnv: {
      supabaseUrlSet: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
      supabaseAnonKeySet: Boolean(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY),
      serviceRoleKeySet: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
      siteUrl: process.env.NEXT_PUBLIC_SITE_URL ?? null
    },
    browserConfig: {
      isConfigured: config.isConfigured,
      normalizedUrl: normalized.url,
      rawUrlIsValid: normalized.isValid,
      urlFallbackUsed: normalized.fallbackUsed,
      anonKeyPresent: Boolean(config.anonKey),
      anonKeyPrefix: config.anonKey ? config.anonKey.slice(0, 14) : null
    },
    notes: [
      "This page intentionally never prints the full anon key or service role key.",
      "If urlFallbackUsed is true, fix NEXT_PUBLIC_SUPABASE_URL in both Cloudflare runtime and build variables."
    ]
  };

  return (
    <main className="mx-auto max-w-7xl px-6 py-10">
      <h1 className="text-xl font-semibold text-charcoal">Deedlight Auth Debug</h1>
      <p className="mt-2 text-sm text-muted">This page verifies Supabase runtime configuration without exposing secrets.</p>
      <pre className="mt-4 overflow-auto rounded-2xl bg-black p-6 text-sm leading-7 text-white">
        {JSON.stringify(payload, null, 2)}
      </pre>
    </main>
  );
}
