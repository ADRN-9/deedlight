type AdminProfile = {
  role?: string | null;
  is_suspended?: boolean | null;
};

type AdminAccessInput = {
  email?: string | null;
  profile?: AdminProfile | null;
  profileError?: unknown;
};

export function isAdminEmail(email?: string | null) {
  if (!email) return false;

  const normalizedEmail = email.trim().toLowerCase();
  if (!normalizedEmail) return false;

  const adminEmails = (process.env.ADMIN_EMAILS ?? "")
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean);

  return adminEmails.includes(normalizedEmail);
}

export function hasAdminAccess({
  email,
  profile,
  profileError,
}: AdminAccessInput) {
  // Fail closed when the profile lookup itself fails.
  if (profileError) return false;

  // Suspension always overrides role and email fallback access.
  if (profile?.is_suspended === true) return false;

  return profile?.role === "admin" || isAdminEmail(email);
}
