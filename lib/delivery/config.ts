export type DisabledDeliveryRuntimeConfig = {
  enabled: false;
};

export type EnabledDeliveryRuntimeConfig = {
  enabled: true;
  provider: "resend";
  supabaseUrl: string;
  supabaseServiceRoleKey: string;
  resendApiKey: string;
  fromEmail: string;
  siteOrigin: string;
  batchSize: number;
};

export type DeliveryRuntimeConfig =
  | DisabledDeliveryRuntimeConfig
  | EnabledDeliveryRuntimeConfig;

function requireValue(env: Record<string, string | undefined>, name: string) {
  const value = env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required delivery configuration: ${name}`);
  }
  return value;
}

function requireHttpsOrigin(value: string, name: string) {
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error(`Invalid delivery configuration URL: ${name}`);
  }

  if (parsed.protocol !== "https:" || parsed.username || parsed.password) {
    throw new Error(`Delivery configuration must use a credential-free HTTPS URL: ${name}`);
  }

  return parsed.origin;
}

export function parseDeliveryRuntimeConfig(
  env: Record<string, string | undefined>,
): DeliveryRuntimeConfig {
  if (env.DELIVERY_ENABLED !== "true") {
    return { enabled: false };
  }

  const provider = requireValue(env, "DELIVERY_PROVIDER");
  if (provider !== "resend") {
    throw new Error("Unsupported delivery provider.");
  }

  const supabaseUrl = requireHttpsOrigin(
    requireValue(env, "SUPABASE_URL"),
    "SUPABASE_URL",
  );
  if (!new URL(supabaseUrl).hostname.endsWith(".supabase.co")) {
    throw new Error("SUPABASE_URL must be a Supabase project URL.");
  }

  const siteOrigin = requireHttpsOrigin(
    requireValue(env, "NEXT_PUBLIC_SITE_URL"),
    "NEXT_PUBLIC_SITE_URL",
  );

  const fromEmail = requireValue(env, "DELIVERY_FROM_EMAIL");
  if (
    fromEmail.length > 320 ||
    /[\r\n]/.test(fromEmail) ||
    !fromEmail.includes("@")
  ) {
    throw new Error("DELIVERY_FROM_EMAIL is invalid.");
  }

  const rawBatchSize = env.DELIVERY_BATCH_SIZE?.trim() || "25";
  const batchSize = Number.parseInt(rawBatchSize, 10);
  if (!Number.isInteger(batchSize) || String(batchSize) !== rawBatchSize || batchSize < 1 || batchSize > 100) {
    throw new Error("DELIVERY_BATCH_SIZE must be an integer between 1 and 100.");
  }

  return {
    enabled: true,
    provider,
    supabaseUrl,
    supabaseServiceRoleKey: requireValue(env, "SUPABASE_SERVICE_ROLE_KEY"),
    resendApiKey: requireValue(env, "RESEND_API_KEY"),
    fromEmail,
    siteOrigin,
    batchSize,
  };
}
