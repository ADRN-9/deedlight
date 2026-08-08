const RESERVED_USERNAMES = new Set([
  "admin",
  "api",
  "about",
  "debug",
  "guidelines",
  "journey",
  "login",
  "member",
  "members",
  "offerings",
  "people",
  "privacy",
  "profile",
  "quiet",
  "rising",
  "settings",
  "signup",
  "terms",
  "today",
  "videos",
]);

export type ProfileFormInput = {
  username: string;
  displayName: string;
  bio: string | null;
  country: string | null;
  isPublic: boolean;
  showContributionStats: boolean;
  defaultOfferingAnonymous: boolean;
};

type ProfileFormResult =
  | {
      ok: true;
      data: ProfileFormInput;
    }
  | {
      ok: false;
      error: string;
    };

export function normalizeUsername(value: FormDataEntryValue | null) {
  return String(value ?? "")
    .trim()
    .replace(/^@+/, "")
    .toLowerCase();
}

function cleanOptionalText(
  value: FormDataEntryValue | null,
  maxLength: number,
) {
  const text = String(value ?? "").trim();

  if (!text) {
    return null;
  }

  return text.slice(0, maxLength);
}

export function parseProfileForm(
  formData: FormData,
): ProfileFormResult {
  const username = normalizeUsername(formData.get("username"));

  const displayName = String(formData.get("display_name") ?? "")
    .trim()
    .replace(/\s+/g, " ");

  const bio = cleanOptionalText(
    formData.get("bio"),
    280,
  );

  const country = cleanOptionalText(
    formData.get("country"),
    80,
  );

  if (!/^[a-z0-9][a-z0-9_-]{2,29}$/.test(username)) {
    return {
      ok: false,
      error:
        "Username must be 3–30 lowercase letters, numbers, hyphens, or underscores.",
    };
  }

  if (RESERVED_USERNAMES.has(username)) {
    return {
      ok: false,
      error: "That username is reserved. Please choose another.",
    };
  }

  if (displayName.length < 2 || displayName.length > 60) {
    return {
      ok: false,
      error: "Display name must be between 2 and 60 characters.",
    };
  }

  return {
    ok: true,
    data: {
      username,
      displayName,
      bio,
      country,
      isPublic: formData.get("is_public") === "on",
      showContributionStats:
        formData.get("show_contribution_stats") === "on",
      defaultOfferingAnonymous:
        formData.get("default_offering_anonymous") === "on",
    },
  };
}
