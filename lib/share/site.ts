export const DEEDLIGHT_SITE_NAME = "Deedlight";
export const DEEDLIGHT_TAGLINE = "Where good deeds become light";

export function getSiteUrl() {
  const configured =
    process.env.NEXT_PUBLIC_SITE_URL?.trim() || "https://deedlight.com";

  return configured.replace(/\/+$/, "");
}

export function absoluteUrl(path: string) {
  if (/^https?:\/\//i.test(path)) return path;

  const normalized = path.startsWith("/") ? path : `/${path}`;
  return `${getSiteUrl()}${normalized}`;
}

export function cleanShareDescription(
  value: string | null | undefined,
  fallback: string,
  maxLength = 155,
) {
  const clean = String(value ?? "")
    .replace(/\s+/g, " ")
    .trim();

  if (!clean) return fallback;
  if (clean.length <= maxLength) return clean;

  const sliced = clean.slice(0, Math.max(1, maxLength - 1)).trimEnd();
  return `${sliced}…`;
}
