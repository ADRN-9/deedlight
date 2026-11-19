export type ResendWebhookHeaders = {
  id: string | null;
  timestamp: string | null;
  signature: string | null;
};

export type ResendBounceType = "Permanent" | "Transient" | "Unknown";

export type ResendProviderEvent = {
  eventId: string;
  eventType: "email.bounced" | "email.complained" | "email.suppressed";
  providerEmailId: string;
  recipientEmail: string;
  bounceType: ResendBounceType | null;
};

export type ResendWebhookParseResult =
  | { status: "ignored" }
  | { status: "accepted"; event: ResendProviderEvent };

const MAX_EVENT_ID_LENGTH = 255;
const MAX_PROVIDER_ID_LENGTH = 255;
const MAX_EMAIL_LENGTH = 320;
const SIGNATURE_TOLERANCE_SECONDS = 300;

function decodeBase64(value: string): Uint8Array | null {
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value) || value.length % 4 !== 0) return null;

  try {
    const binary = atob(value);
    if (!binary.length) return null;
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch {
    return null;
  }
}

function validHeaderId(value: string): boolean {
  return value.length > 0
    && value.length <= MAX_EVENT_ID_LENGTH
    && /^[\x21-\x7e]+$/.test(value);
}

export async function verifyResendWebhookSignature(input: {
  payload: string;
  headers: ResendWebhookHeaders;
  secret: string;
  nowSeconds?: number;
}): Promise<boolean> {
  const { payload, headers, secret } = input;
  const id = headers.id ?? "";
  const timestamp = headers.timestamp ?? "";
  const signature = headers.signature ?? "";

  if (!validHeaderId(id) || !/^\d{1,12}$/.test(timestamp) || !signature || !secret.startsWith("whsec_")) {
    return false;
  }

  const timestampSeconds = Number(timestamp);
  const nowSeconds = input.nowSeconds ?? Math.floor(Date.now() / 1000);
  if (!Number.isSafeInteger(timestampSeconds)
    || !Number.isFinite(nowSeconds)
    || Math.abs(nowSeconds - timestampSeconds) > SIGNATURE_TOLERANCE_SECONDS) {
    return false;
  }

  const secretBytes = decodeBase64(secret.slice("whsec_".length));
  if (!secretBytes) return false;

  const candidates = signature
    .trim()
    .split(/\s+/)
    .filter((part) => part.startsWith("v1,"))
    .map((part) => decodeBase64(part.slice(3)))
    .filter((part): part is Uint8Array => part !== null);

  if (!candidates.length) return false;

  try {
    const key = await crypto.subtle.importKey(
      "raw",
      secretBytes,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const signedPayload = new TextEncoder().encode(`${id}.${timestamp}.${payload}`);

    for (const candidate of candidates) {
      if (await crypto.subtle.verify("HMAC", key, candidate, signedPayload)) return true;
    }
  } catch {
    return false;
  }

  return false;
}

function recordObject(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function normalizedEmail(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const email = value.trim().toLowerCase();
  if (email.length < 3 || email.length > MAX_EMAIL_LENGTH || /[\s\r\n\0]/.test(email)) return null;
  const at = email.indexOf("@");
  if (at < 1 || at !== email.lastIndexOf("@") || at === email.length - 1) return null;
  if (!email.slice(at + 1).includes(".")) return null;
  return email;
}

export function parseResendProviderEvent(
  value: unknown,
  eventId: string,
): ResendWebhookParseResult {
  const envelope = recordObject(value);
  if (!envelope || typeof envelope.type !== "string") {
    throw new Error("Invalid Resend webhook payload.");
  }

  if (
    envelope.type !== "email.bounced"
    && envelope.type !== "email.complained"
    && envelope.type !== "email.suppressed"
  ) {
    return { status: "ignored" };
  }

  const data = recordObject(envelope.data);
  if (!data
    || typeof data.email_id !== "string"
    || data.email_id.length < 1
    || data.email_id.length > MAX_PROVIDER_ID_LENGTH
    || !Array.isArray(data.to)
    || data.to.length !== 1) {
    throw new Error("Invalid Resend delivery event.");
  }

  const recipientEmail = normalizedEmail(data.to[0]);
  if (!recipientEmail) throw new Error("Invalid Resend recipient.");

  let bounceType: ResendBounceType | null = null;
  if (envelope.type === "email.bounced") {
    const bounce = recordObject(data.bounce);
    const rawType = bounce?.type;
    bounceType = rawType === "Permanent" || rawType === "Transient" ? rawType : "Unknown";
  }

  return {
    status: "accepted",
    event: {
      eventId,
      eventType: envelope.type,
      providerEmailId: data.email_id,
      recipientEmail,
      bounceType,
    },
  };
}
