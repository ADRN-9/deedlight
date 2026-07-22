import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { getSupabaseConfig } from "./config";

export async function updateSession(request: NextRequest) {
  try {
    const { url, anonKey, isConfigured } = getSupabaseConfig();

    if (!isConfigured || !url || !anonKey) {
      return NextResponse.next({ request });
    }

    let supabaseResponse = NextResponse.next({ request });

    const supabase = createServerClient(url, anonKey, {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          supabaseResponse = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) => supabaseResponse.cookies.set(name, value, options));
        }
      }
    });

    await supabase.auth.getUser();

    return supabaseResponse;
  } catch (error) {
    // Middleware should never make the whole public website unavailable.
    console.error("Supabase middleware session refresh failed", error);
    return NextResponse.next({ request });
  }
}
