import { getSupabaseBrowserConfig, getSupabaseConfig } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

export default function AuthDebugPage() {
  const serverConfig = getSupabaseConfig();
  const browserConfig = getSupabaseBrowserConfig();

  const payload = {
    ok: serverConfig.isConfigured && browserConfig.isConfigured,
    serverEnv: {
      supabaseUrlSet: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
      supabaseAnonKeySet: Boolean(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY),
      serviceRoleKeySet: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
      siteUrl: process.env.NEXT_PUBLIC_SITE_URL ?? null
    },
    browserConfig: {
      isConfigured: browserConfig.isConfigured,
      normalizedUrl: browserConfig.url,
      rawUrlIsValid: browserConfig.rawUrlIsValid,
      urlFallbackUsed: browserConfig.urlFallbackUsed,
      anonKeyPresent: Boolean(browserConfig.anonKey),
      anonKeyPrefix: browserConfig.anonKey ? browserConfig.anonKey.split("_").slice(0, 2).join("_") : null
    },
    notes: [
      "This page intentionally never prints the full anon key or service role key.",
      "If urlFallbackUsed is true, fix NEXT_PUBLIC_SUPABASE_URL in both Cloudflare runtime and build variables."
    ]
  };

  return (
    <main className="mx-auto max-w-6xl px-6 py-10">
      <h1 className="text-2xl font-bold">Deedlight Auth Debug</h1>
      <p className="mt-2 text-sm text-stone-700">This page verifies Supabase runtime configuration without exposing secrets.</p>
      <pre className="mt-6 overflow-auto rounded-2xl bg-black p-6 text-sm leading-7 text-white">
        {JSON.stringify(payload, null, 2)}
      </pre>
    </main>
  );
}
