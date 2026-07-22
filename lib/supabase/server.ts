import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { getSupabaseConfig } from "./config";

type ServerClient = ReturnType<typeof createServerClient>;
type Options = {
  allowMissingEnv?: boolean;
};

export async function createClient(): Promise<ServerClient>;
export async function createClient(options: { allowMissingEnv: true }): Promise<ServerClient | null>;
export async function createClient(options: Options = {}): Promise<ServerClient | null> {
  const { url, anonKey, isConfigured } = getSupabaseConfig();

  if (!isConfigured || !url || !anonKey) {
    if (options.allowMissingEnv) return null;
    throw new Error("Missing Supabase environment variables.");
  }

  const cookieStore = await cookies();

  return createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options));
        } catch {
          // Server Components cannot set cookies. Middleware refreshes sessions.
        }
      }
    }
  });
}
