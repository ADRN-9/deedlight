import { createBrowserClient } from "@supabase/ssr";
import { getSupabaseConfig } from "./config";

export function createClient() {
  const { url, anonKey, isConfigured } = getSupabaseConfig();

  if (!isConfigured || !url || !anonKey) {
    throw new Error("Missing Supabase environment variables.");
  }

  return createBrowserClient(url, anonKey);
}
