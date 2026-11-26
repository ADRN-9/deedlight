import {
  DEEDLIGHT_SUPABASE_ORIGIN,
  DEEDLIGHT_SUPABASE_PROJECT_REF,
} from "./project-identity.ts";

export function isTrustedSupabaseDestination(value: unknown): value is string {
  if (typeof value !== "string" || value.length > 256 || value.trim() !== value) {
    return false;
  }

  try {
    const url = new URL(value);
    return value === DEEDLIGHT_SUPABASE_ORIGIN
      && url.protocol === "https:"
      && url.hostname === `${DEEDLIGHT_SUPABASE_PROJECT_REF}.supabase.co`
      && url.origin === DEEDLIGHT_SUPABASE_ORIGIN
      && url.port === ""
      && url.username === ""
      && url.password === ""
      && url.pathname === "/"
      && url.search === ""
      && url.hash === "";
  } catch {
    return false;
  }
}
