const FALLBACK_SUPABASE_URL = "https://xaipiovflxomcbfwtwmu.supabase.co";

function stripWrappingQuotes(value: string) {
  return value.replace(/^['\"]+|['\"]+$/g, "").trim();
}

export function normalizeSupabaseUrl(rawValue?: string | null) {
  const raw = stripWrappingQuotes(rawValue ?? "");

  if (!raw || raw.includes("YOUR_PROJECT_REF")) {
    return {
      url: FALLBACK_SUPABASE_URL,
      rawUrlIsValid: false,
      fallbackUsed: true
    };
  }

  // If the correct project ref is present, always recover to the canonical URL.
  // This protects the browser bundle from cached/malformed values such as:
  //   ttps://xaipiovflxomcbfwtwmu.supabase.co
  //   https://ttps://xaipiovflxomcbfwtwmu.supabase.co
  if (raw.includes("xaipiovflxomcbfwtwmu.supabase.co")) {
    const canonical = FALLBACK_SUPABASE_URL;
    return {
      url: canonical,
      rawUrlIsValid: raw === canonical,
      fallbackUsed: raw !== canonical
    };
  }

  let candidate = raw;

  // Common copy/paste mistakes.
  candidate = candidate.replace(/^https:\/\/https:\/\//i, "https://");
  candidate = candidate.replace(/^https:\/\/ttps:\/\//i, "https://");
  candidate = candidate.replace(/^ttps:\/\//i, "https://");
  candidate = candidate.replace(/^http:\/\/https:\/\//i, "https://");

  if (!/^https?:\/\//i.test(candidate) && candidate.includes(".supabase.co")) {
    candidate = `https://${candidate.replace(/^\/+/, "")}`;
  }

  try {
    const parsed = new URL(candidate);
    const isHttp = parsed.protocol === "https:" || parsed.protocol === "http:";
    const isSupabase = parsed.hostname.endsWith(".supabase.co");

    if (isHttp && isSupabase) {
      return {
        url: parsed.origin,
        rawUrlIsValid: raw === parsed.origin,
        fallbackUsed: false
      };
    }
  } catch {
    // fall through to fallback
  }

  return {
    url: FALLBACK_SUPABASE_URL,
    rawUrlIsValid: false,
    fallbackUsed: true
  };
}

function isPlaceholder(value?: string | null) {
  return !value || value.includes("YOUR_") || value.includes("REPLACE_");
}

export function getSupabaseConfig() {
  const normalized = normalizeSupabaseUrl(process.env.NEXT_PUBLIC_SUPABASE_URL);
  const anonKey = stripWrappingQuotes(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "");

  return {
    url: normalized.url,
    anonKey,
    isConfigured: Boolean(normalized.url && anonKey && !isPlaceholder(anonKey)),
    rawUrlIsValid: normalized.rawUrlIsValid,
    urlFallbackUsed: normalized.fallbackUsed
  };
}

export function getSupabaseBrowserConfig() {
  const normalized = normalizeSupabaseUrl(process.env.NEXT_PUBLIC_SUPABASE_URL);
  const anonKey = stripWrappingQuotes(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "");

  return {
    url: normalized.url,
    anonKey,
    isConfigured: Boolean(normalized.url && anonKey && !isPlaceholder(anonKey)),
    rawUrlIsValid: normalized.rawUrlIsValid,
    urlFallbackUsed: normalized.fallbackUsed
  };
}
