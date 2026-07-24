"use client";

import { createBrowserClient } from "@supabase/ssr";
import { getSupabaseBrowserConfig } from "./config";

type BrowserClient = ReturnType<typeof createBrowserClient>;

let browserClient: BrowserClient | null = null;

export function createClient() {
  const { url, anonKey, isConfigured } = getSupabaseBrowserConfig();

  if (!isConfigured) {
    throw new Error("Missing Supabase browser configuration.");
  }

  if (!browserClient) {
    browserClient = createBrowserClient(url, anonKey);
  }

  return browserClient;
}
