import { Webhook } from "svix";

export type ResendBounceType = "Permanent" | "Transient" | "Undetermined";

export type VerifiedResendDeliveryEvent = {
  kind: "delivery";
  eventId: string;
  providerEmailId: string;
  recipientEmail: string;
  eventType: string;
  eventAt: string;
  payloadSha256: string;
  suppressionReason: "permanent_bounce" | "spam_complaint" | null;
  bounceType: ResendBounceType | null;
};

export type VerifiedResendSuppressionEvent = {
  kind: "account_suppression";
  eventId: string;
  suppressionId: string;
  recipientEmail: string;
  eventType: "suppression.added" | "suppression.removed";
  eventAt: string;
  payloadSha256: string;
  origin: "bounce" | "complaint" | "manual";
  sourceId: string | null;
};

export type VerifiedResendWebhookEvent =
  | VerifiedResendDeliveryEvent
  | VerifiedResendSuppressionEvent;

const DELIVERY_TYPES = new Set([
  "email.sent", "email.delivered", "email.delivery_delayed", "email.failed",
  "email.bounced", "email.complained", "email.suppressed",
]);
const SUPPRESSION_TYPES = new Set(["suppression.added", "suppression.removed"]);
const MAX_WEBHOOK_BYTES = 128 * 1024;
const MAX_TIMESTAMP_SKEW_SECONDS = 300;

export class InvalidResendWebhook extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidResendWebhook";
  }
}

function requiredHeader(headers: Headers, name: string): string {
  const value = headers.get(name);
  if (!value || value.length > 512 || /[\r\n]/.test(value)) {
    throw new InvalidResendWebhook("Missing or invalid signature metadata");
  }
  return value;
}

function requiredEmail(value: unknown): string {
  if (typeof value !== "string" || value.length < 3 || value.length > 320
    || !/^[!-~]+@[A-Za-z0-9.-]+$/.test(value)) {
    throw new InvalidResendWebhook("Provider recipient association is ambiguous");
  }
  return value;
}

function validEventTime(value: unknown, now: Date): string {
  if (typeof value !== "string") {
    throw new InvalidResendWebhook("Missing event creation timestamp");
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime()) || date.getTime() > now.getTime() + 300_000
    || date.getTime() < Date.UTC(2020, 0, 1)) {
    throw new InvalidResendWebhook("Invalid event creation timestamp");
  }
  return date.toISOString();
}

export async function verifyResendDeliveryWebhook(input: {
  rawBody: string;
  headers: Headers;
  secret: string;
  now?: Date;
}): Promise<VerifiedResendWebhookEvent> {
  const { rawBody, headers, secret, now = new Date() } = input;
  if (!/^whsec_[A-Za-z0-9+/=_-]{20,}$/.test(secret)) {
    throw new Error("Resend webhook signing secret is unavailable");
  }
  if (new TextEncoder().encode(rawBody).byteLength > MAX_WEBHOOK_BYTES) {
    throw new InvalidResendWebhook("Webhook payload is too large");
  }
  const eventId = requiredHeader(headers, "svix-id");
  const timestamp = requiredHeader(headers, "svix-timestamp");
  const signature = requiredHeader(headers, "svix-signature");
  if (!/^msg_[A-Za-z0-9_-]{6,180}$/.test(eventId)
    || !/^[0-9]{10,12}$/.test(timestamp)) {
    throw new InvalidResendWebhook("Invalid signed event identity");
  }
  const signedAt = Number(timestamp);
  if (!Number.isSafeInteger(signedAt) || !Number.isFinite(now.getTime())
    || Math.abs(now.getTime() / 1000 - signedAt) > MAX_TIMESTAMP_SKEW_SECONDS) {
    throw new InvalidResendWebhook("Webhook signature timestamp outside allowed window");
  }

  let envelope: unknown;
  try {
    new Webhook(secret).verify(rawBody, {
      "svix-id": eventId,
      "svix-timestamp": timestamp,
      "svix-signature": signature,
    });
    // Parse only the exact raw bytes authenticated by Svix.
    envelope = JSON.parse(rawBody);
  } catch {
    throw new InvalidResendWebhook("Webhook signature verification failed");
  }
  if (!envelope || typeof envelope !== "object" || Array.isArray(envelope)) {
    throw new InvalidResendWebhook("Invalid verified event envelope");
  }
  const obj = envelope as Record<string, unknown>;
  const type = obj.type;
  const data = obj.data;
  if (typeof type !== "string" || !data || typeof data !== "object"
    || Array.isArray(data)) {
    throw new InvalidResendWebhook("Unsupported verified provider event");
  }
  const body = data as Record<string, unknown>;
  const eventAt = validEventTime(obj.created_at, now);
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(rawBody));
  const payloadSha256 = Array.from(new Uint8Array(hash),
    (byte) => byte.toString(16).padStart(2, "0")).join("");

  if (SUPPRESSION_TYPES.has(type)) {
    // These account-level events have NO outbound email_id and cannot be
    // correlated using the delivery-only webhook schema.
    if (typeof body.id !== "string" || !/^[A-Za-z0-9-]{10,128}$/.test(body.id)
      || !["bounce", "complaint", "manual"].includes(String(body.origin))
      || !(body.source_id === null || (typeof body.source_id === "string"
        && body.source_id.length >= 1 && body.source_id.length <= 255
        && !/[\x00-\x1f\x7f]/.test(body.source_id)))) {
      throw new InvalidResendWebhook("Invalid account suppression event");
    }
    validEventTime(body.created_at, now);
    return {
      kind: "account_suppression",
      eventId,
      suppressionId: body.id,
      recipientEmail: requiredEmail(body.email),
      eventType: type as VerifiedResendSuppressionEvent["eventType"],
      eventAt,
      payloadSha256,
      origin: body.origin as VerifiedResendSuppressionEvent["origin"],
      sourceId: body.source_id,
    } as VerifiedResendSuppressionEvent;
  }

  if (!DELIVERY_TYPES.has(type)) {
    throw new InvalidResendWebhook("Unsupported verified provider event");
  }
  const to = body.to;
  if (typeof body.email_id !== "string" || body.email_id.length < 1
    || body.email_id.length > 255 || /[\x00-\x1f\x7f]/.test(body.email_id)
    || !Array.isArray(to) || to.length !== 1) {
    throw new InvalidResendWebhook("Provider recipient association is ambiguous");
  }
  const recipientEmail = requiredEmail(to[0]);
  let suppressionReason: VerifiedResendDeliveryEvent["suppressionReason"] = null;
  let bounceType: ResendBounceType | null = null;
  if (type === "email.complained") suppressionReason = "spam_complaint";
  if (type === "email.bounced") {
    const bounce = body.bounce;
    if (!bounce || typeof bounce !== "object" || Array.isArray(bounce)) {
      throw new InvalidResendWebhook("Ambiguous provider bounce classification");
    }
    const classification = (bounce as Record<string, unknown>).type;
    if (classification !== "Permanent" && classification !== "Transient"
      && classification !== "Undetermined") {
      throw new InvalidResendWebhook("Unsupported provider bounce classification");
    }
    bounceType = classification;
    if (bounceType === "Permanent") suppressionReason = "permanent_bounce";
  }
  if (type === "email.suppressed") {
    const suppressed = body.suppressed;
    if (!suppressed || typeof suppressed !== "object" || Array.isArray(suppressed)) {
      throw new InvalidResendWebhook("Provider suppression classification missing");
    }
  }
  return {
    kind: "delivery",
    eventId,
    providerEmailId: body.email_id,
    recipientEmail,
    eventType: type,
    eventAt,
    payloadSha256,
    suppressionReason,
    bounceType,
  };
}
