const DEEDLIGHT_SUPABASE_URL_FALLBACK = "https://xaipiovflxomcbfwtwmu.supabase.co";

function cleanEnvValue(value: string | undefined) {
  if (!value) return undefined;

  const cleaned = value.trim().replace(/^['"]|['"]$/g, "");

  if (!cleaned) return undefined;
  if (["undefined", "null"].includes(cleaned.toLowerCase())) return undefined;

  return cleaned;
}

function isValidHttpUrl(value: string | undefined) {
  if (!value) return false;

  try {
    const parsed = new URL(value);
    return parsed.protocol === "http:" || parsed.protocol === "https:";
  } catch {
    return false;
  }
}

export function getSupabaseConfig() {
  const rawUrl = cleanEnvValue(process.env.NEXT_PUBLIC_SUPABASE_URL);
  const rawAnonKey = cleanEnvValue(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);

  // Cloudflare/OpenNext can occasionally leave client-side NEXT_PUBLIC_* values malformed
  // while server-side runtime variables are correct. The Supabase URL is public, so we
  // keep a safe project-url fallback for the browser bundle. Do not do this for secrets.
  const url = isValidHttpUrl(rawUrl) ? rawUrl : DEEDLIGHT_SUPABASE_URL_FALLBACK;
  const anonKey = rawAnonKey;

  return {
    url,
    anonKey,
    isConfigured: Boolean(
      isValidHttpUrl(url) &&
        anonKey &&
        !url.includes("YOUR_PROJECT_REF") &&
        !anonKey.includes("YOUR_SUPABASE_ANON_KEY")
    ),
    debug: {
      rawUrl,
      normalizedUrl: url,
      urlFallbackUsed: rawUrl !== url,
      rawUrlIsValid: isValidHttpUrl(rawUrl),
      anonKeySet: Boolean(anonKey),
      anonKeyPrefix: anonKey ? `${anonKey.slice(0, 14)}...` : null
    }
  };
}
