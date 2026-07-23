import { getSupabaseConfig } from "@/lib/supabase/config";

export const dynamic = "force-dynamic";

export default function DebugAuthPage() {
  const config = getSupabaseConfig();
  const rawUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  const rawAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

  const safeRawUrl = String(rawUrl || "");
  const safeAnonKey = String(rawAnonKey || "");

  const diagnostics = {
    ok: true,
    serverEnv: {
      supabaseUrlSet: safeRawUrl.length > 0,
      supabaseAnonKeySet: safeAnonKey.length > 0,
      serviceRoleKeySet: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
      siteUrl: process.env.NEXT_PUBLIC_SITE_URL ?? null
    },
    browserConfig: {
      isConfigured: config.isConfigured,
      normalizedUrl: config.url,
      rawUrlIsValid:
        safeRawUrl.startsWith("http://") || safeRawUrl.startsWith("https://"),
      urlFallbackUsed: config.debug.urlFallbackUsed,
      anonKeyPresent: Boolean(config.anonKey),
      anonKeyPrefix: config.debug.anonKeyPrefix
    },
    notes: [
      "This page intentionally never prints the full anon key or service role key.",
      "If urlFallbackUsed is true, check NEXT_PUBLIC_SUPABASE_URL in Cloudflare variables."
    ]
  };

  return (
    <main style={{ padding: "32px", fontFamily: "system-ui, sans-serif" }}>
      <h1>Deedlight Auth Debug</h1>
      <p>This page verifies Supabase runtime configuration without exposing secrets.</p>
      <pre
        style={{
          background: "#111",
          color: "#f7f7f7",
          padding: "20px",
          borderRadius: "12px",
          overflowX: "auto",
          whiteSpace: "pre-wrap"
        }}
      >
        {JSON.stringify(diagnostics, null, 2)}
      </pre>
    </main>
  );
}
