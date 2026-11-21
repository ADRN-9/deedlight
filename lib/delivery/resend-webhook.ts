export type ResendWebhookHeaders = {
  id: string | null;
  timestamp: string | null;
  signature: string | null;
};

export type ResendBounceType = "Permanent" | "Transient" | "Unknown";

export type ResendLifecycleEventType =
  | "email.sent"
  | "email.delivered"
  | "email.delivery_delayed"
  | "email.bounced"
  | "email.complained"
  | "email.suppressed"
  | "email.failed";

export type ResendSuppressionReason = "previous_bounce" | "previous_complaint" | "provider_suppressed";

export type ResendFailureClass =
  | "invalid_recipient"
  | "provider_authentication"
  | "domain_verification"
  | "quota_exceeded"
  | "content_rejected"
  | "unknown";

export type ResendProviderEvent = {
  eventId: string;
  eventType: ResendLifecycleEventType;
  providerEmailId: string;
  recipientEmail: string;
  providerCreatedAt: string;
  bounceType: ResendBounceType | null;
  failureClass: ResendFailureClass | null;
  suppressionReason: ResendSuppressionReason | null;
};

export type ResendWebhookParseResult =
  | { status: "ignored" }
  | { status: "accepted"; event: ResendProviderEvent };

const MAX_EVENT_ID_LENGTH = 255;
const MAX_PROVIDER_ID_LENGTH = 255;
const MAX_EMAIL_LENGTH = 320;
const SIGNATURE_TOLERANCE_SECONDS = 300;

function decodeBase64(value: string): Uint8Array<ArrayBuffer> | null {
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
    .filter((part): part is Uint8Array<ArrayBuffer> => part !== null);

  if (!candidates.length) return false;

  try {
    const key = await crypto.subtle.importKey(
      "raw",
      secretBytes,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const signedPayload = new TextEncoder().encode(id + "." + timestamp + "." + payload);

    for (const candidate of candidates) {
      if (await crypto.subtle.verify("HMAC", key, candidate, signedPayload)) return true;
    }
  } catch {
    return false;
  }

  return false;
}


export async function fingerprintResendWebhookPayload(payload: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(payload),
  );
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function recordObject(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function validOptionalDiagnosticCode(value: unknown): boolean {
  return value === undefined
    || (Array.isArray(value) && value.every((item) => typeof item === "string"));
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

function normalizedProviderTimestamp(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const match = value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(?:Z|[+-](\d{2}):(\d{2}))$/i);
  if (!match) return null;

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  const offsetHour = Number(match[7] ?? 0);
  const offsetMinute = Number(match[8] ?? 0);
  const leapYear = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const monthDays = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

  if (month < 1 || month > 12
    || day < 1 || day > monthDays[month - 1]
    || hour > 23 || minute > 59 || second > 59
    || offsetHour > 23 || offsetMinute > 59) {
    return null;
  }

  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) return null;
  return new Date(timestamp).toISOString();
}

export function normalizeFailureClass(value: unknown): ResendFailureClass {
  if (typeof value !== "string" || value.length > 256) return "unknown";
  const reason = value.trim().toLowerCase();

  if (/(invalid[_\s-]*(recipient|email)|recipient[_\s-]*invalid|email[_\s-]*invalid)/.test(reason)) {
    return "invalid_recipient";
  }
  if (/(api[_\s-]*key|auth|credential|unauthori[sz]ed|forbidden)/.test(reason)) {
    return "provider_authentication";
  }
  if (/(domain.*(verify|verification|verified)|not[_\s-]*verified)/.test(reason)) {
    return "domain_verification";
  }
  if (/(quota|rate[_\s-]*limit|daily[_\s-]*limit)/.test(reason)) {
    return "quota_exceeded";
  }
  if (/(content|policy|spam|blocked)/.test(reason)) {
    return "content_rejected";
  }
  return "unknown";
}

const LIFECYCLE_EVENT_TYPES = new Set<ResendLifecycleEventType>([
  "email.sent",
  "email.delivered",
  "email.delivery_delayed",
  "email.bounced",
  "email.complained",
  "email.suppressed",
  "email.failed",
]);

export function parseResendProviderEvent(
  value: unknown,
  eventId: string,
): ResendWebhookParseResult {
  const envelope = recordObject(value);
  if (!envelope || typeof envelope.type !== "string") {
    throw new Error("Invalid Resend webhook payload.");
  }

  if (!LIFECYCLE_EVENT_TYPES.has(envelope.type as ResendLifecycleEventType)) {
    return { status: "ignored" };
  }

  const data = recordObject(envelope.data);
  const tags = recordObject(data?.tags);
  if (tags?.application !== "deedlight") return { status: "ignored" };

  if (!data
    || typeof data.email_id !== "string"
    || data.email_id.length < 1
    || data.email_id.length > MAX_PROVIDER_ID_LENGTH
    || typeof data.created_at !== "string"
    || !normalizedProviderTimestamp(data.created_at)
    || typeof data.from !== "string"
    || data.from.trim().length === 0
    || typeof data.subject !== "string"
    || !Array.isArray(data.to)
    || data.to.length !== 1) {
    throw new Error("Invalid Resend delivery event.");
  }

  const recipientEmail = normalizedEmail(data.to[0]);
  if (!recipientEmail) throw new Error("Invalid Resend recipient.");

  const providerCreatedAt = normalizedProviderTimestamp(envelope.created_at);
  if (!providerCreatedAt) throw new Error("Invalid Resend provider timestamp.");

  let bounceType: ResendBounceType | null = null;
  if (envelope.type === "email.bounced") {
    const bounce = recordObject(data.bounce);
    if (!bounce
      || !validOptionalDiagnosticCode(bounce.diagnosticCode)
      || typeof bounce.message !== "string"
      || bounce.message.trim().length === 0
      || typeof bounce.subType !== "string"
      || bounce.subType.trim().length === 0
      || typeof bounce.type !== "string"
      || bounce.type.trim().length === 0) {
      throw new Error("Invalid Resend bounce event.");
    }
    // Provider classifications may expand. Preserve only known actionable
    // classes; unknown values remain Unknown and therefore suppress safely.
    bounceType = bounce.type === "Permanent" || bounce.type === "Transient"
      ? bounce.type
      : "Unknown";
  }

  let suppressionReason: ResendSuppressionReason | null = null;
  if (envelope.type === "email.suppressed") {
    const suppressed = recordObject(data.suppressed);
    if (!suppressed
      || !validOptionalDiagnosticCode(suppressed.diagnosticCode)
      || typeof suppressed.message !== "string"
      || suppressed.message.trim().length === 0
      || typeof suppressed.type !== "string"
      || suppressed.type.trim().length === 0
      || (suppressed.reason !== undefined && suppressed.reason !== null
        && (typeof suppressed.reason !== "string" || suppressed.reason.trim().length === 0))) {
      throw new Error("Invalid Resend suppression event.");
    }
    const knownSuppressionType = suppressed.type === "Suppressed"
      || suppressed.type === "OnAccountSuppressionList";
    suppressionReason = knownSuppressionType
      && (suppressed.reason === "previous_bounce" || suppressed.reason === "previous_complaint")
      ? suppressed.reason
      : "provider_suppressed";
  }

  let failureClass: ResendFailureClass | null = null;
  if (envelope.type === "email.failed") {
    const failed = recordObject(data.failed);
    if (typeof failed?.reason !== "string" || failed.reason.trim().length === 0) {
      throw new Error("Invalid Resend failure event.");
    }
    failureClass = normalizeFailureClass(failed.reason);
  }

  return {
    status: "accepted",
    event: {
      eventId,
      eventType: envelope.type as ResendLifecycleEventType,
      providerEmailId: data.email_id,
      recipientEmail,
      providerCreatedAt,
      bounceType,
      failureClass,
      suppressionReason,
    },
  };
}
