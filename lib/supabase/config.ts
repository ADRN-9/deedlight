const DEEDLIGHT_SUPABASE_URL = "https://xaipiovflxomcbfwtwmu.supabase.co";

function clean(value?: string | null) {
  return (value ?? "").trim().replace(/^['\"]|['\"]$/g, "");
}

export function normalizeSupabaseUrl(value?: string | null) {
  let url = clean(value);

  // Common copy/paste mistakes seen in Cloudflare variables.
  // Example: ttps://project.supabase.co  -> https://project.supabase.co
  if (url.startsWith("ttps://")) url = `h${url}`;

  // Example created by older normalizers: https://ttps://project.supabase.co
  if (url.startsWith("https://ttps://")) url = url.replace("https://ttps://", "https://");
  if (url.startsWith("http://ttps://")) url = url.replace("http://ttps://", "https://");
  if (url.startsWith("https://https://")) url = url.replace("https://https://", "https://");
  if (url.startsWith("http://https://")) url = url.replace("http://https://", "https://");

  if (url && !/^https?:\/\//i.test(url)) {
    url = `https://${url}`;
  }

  try {
    const parsed = new URL(url);
    const isValid = parsed.protocol === "https:" || parsed.protocol === "http:";
    const looksLikeSupabase = parsed.hostname.endsWith(".supabase.co");

    if (isValid && looksLikeSupabase) {
      return {
        url: parsed.toString().replace(/\/$/, ""),
        isValid: true,
        fallbackUsed: false
      };
    }
  } catch {
    // Fall back below.
  }

  return {
    url: DEEDLIGHT_SUPABASE_URL,
    isValid: false,
    fallbackUsed: true
  };
}

export function getSupabaseConfig() {
  const normalized = normalizeSupabaseUrl(process.env.NEXT_PUBLIC_SUPABASE_URL);
  const anonKey = clean(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);
  const serviceRoleKey = clean(process.env.SUPABASE_SERVICE_ROLE_KEY);
  const siteUrl = clean(process.env.NEXT_PUBLIC_SITE_URL) || "https://deedlight.com";

  return {
    url: normalized.url,
    anonKey,
    serviceRoleKey,
    siteUrl,
    isConfigured: Boolean(normalized.url && anonKey),
    debug: {
      rawUrlPresent: Boolean(clean(process.env.NEXT_PUBLIC_SUPABASE_URL)),
      rawUrlIsValid: normalized.isValid,
      urlFallbackUsed: normalized.fallbackUsed,
      anonKeyPresent: Boolean(anonKey),
      anonKeyPrefix: anonKey ? anonKey.slice(0, 14) : null
    }
  };
}

export function getBrowserSupabaseConfig() {
  return getSupabaseConfig();
}
