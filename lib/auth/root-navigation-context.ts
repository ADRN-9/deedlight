import type { User } from "@supabase/supabase-js";
import { hasAdminAccess } from "@/lib/auth/admin-access";
import { createClient } from "@/lib/supabase/server";

export type RootNavigationContext = {
  user: User | null;
  isAdmin: boolean;
};

const anonymousContext: RootNavigationContext = {
  user: null,
  isAdmin: false
};

export async function getRootNavigationContext(): Promise<RootNavigationContext> {
  let supabase;

  try {
    supabase = await createClient({ allowMissingEnv: true });
  } catch {
    console.error("Root navigation auth initialization failed");
    return anonymousContext;
  }

  if (!supabase) {
    return anonymousContext;
  }

  let user: User | null;

  try {
    const { data, error } = await supabase.auth.getUser();
    if (error) {
      console.error("Root navigation auth lookup failed");
      return anonymousContext;
    }
    user = data.user;
  } catch {
    console.error("Root navigation auth lookup failed");
    return anonymousContext;
  }

  if (!user) {
    return anonymousContext;
  }

  try {
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("role,is_suspended")
      .eq("user_id", user.id)
      .maybeSingle();

    return {
      user,
      isAdmin: hasAdminAccess({
        email: user.email,
        profile,
        profileError
      })
    };
  } catch {
    console.error("Root navigation admin lookup failed");
    return { user, isAdmin: false };
  }
}
