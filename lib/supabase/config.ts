const FALLBACK_SUPABASE_URL = "https://xaipiovflxomcbfwtwmu.supabase.co";

function stripWrappingQuotes(value: string) {
  return value.trim().replace(/^['\"]|['\"]$/g, "");
}

function normalizeSupabaseUrl(value: string | null | undefined) {
  const raw = stripWrappingQuotes(value ?? "");

  if (raw.startsWith("http://") || raw.startsWith("https://")) {
    try {
      const parsed = new URL(raw);
      return parsed.toString().replace(/\/$/, "");
    } catch {
      return FALLBACK_SUPABASE_URL;
    }
  }

  // Common mistake: dashboard value pasted without https://
  if (raw.endsWith(".supabase.co")) {
    return `https://${raw}`;
  }

  return FALLBACK_SUPABASE_URL;
}

export function getSupabaseConfig() {
  const rawUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  const rawAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

  const url = normalizeSupabaseUrl(rawUrl);
  const anonKey = stripWrappingQuotes(rawAnonKey);

  const isConfigured = Boolean(
    url &&
      anonKey &&
      !anonKey.includes("YOUR_SUPABASE_ANON_KEY") &&
      !anonKey.includes("YOUR_ANON_KEY")
  );

  return {
    url,
    anonKey,
    isConfigured,
    debug: {
      rawUrlPresent: Boolean(rawUrl),
      rawUrl,
      normalizedUrl: url,
      rawUrlIsValid: rawUrl ? url === normalizeSupabaseUrl(rawUrl) : false,
      urlFallbackUsed: rawUrl ? url === FALLBACK_SUPABASE_URL && rawUrl !== FALLBACK_SUPABASE_URL : true,
      anonKeyPresent: Boolean(anonKey),
      anonKeyPrefix: anonKey ? anonKey.slice(0, 14) : null
    }
  };
}
