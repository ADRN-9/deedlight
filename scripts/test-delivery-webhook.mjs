import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";

import {
  fingerprintResendWebhookPayload,
  parseResendProviderEvent,
  verifyResendWebhookSignature,
} from "../lib/delivery/resend-webhook.ts";

const nowSeconds = 1_800_000_000;
const secretBytes = Buffer.from("deedlight-resend-webhook-fixture-secret");
const secret = `whsec_${secretBytes.toString("base64")}`;
const id = "msg_deedlight_fixture_01";
const timestamp = String(nowSeconds);

function signed(payload, options = {}) {
  const eventId = options.id ?? id;
  const eventTimestamp = options.timestamp ?? timestamp;
  const key = options.secretBytes ?? secretBytes;
  const signature = createHmac("sha256", key)
    .update(`${eventId}.${eventTimestamp}.${payload}`)
    .digest("base64");
  return {
    id: eventId,
    timestamp: eventTimestamp,
    signature: `v1,${signature}`,
  };
}

function event(type, data = {}) {
  const eventData = {
    email_id: "resend_email_fixture_01",
    created_at: "2026-11-19T00:00:00.000Z",
    from: "Deedlight <no-reply@deedlight.example>",
    to: ["Member@Example.test"],
    subject: "Daily Deedlight",
    tags: { application: "deedlight" },
    ...(type === "email.bounced" ? {
      bounce: {
        diagnosticCode: [],
        message: "The recipient server rejected the message.",
        subType: "General",
        type: "Permanent",
      },
    } : {}),
    ...(type === "email.suppressed" ? {
      suppressed: {
        diagnosticCode: [],
        message: "The address is on the suppression list.",
        reason: "previous_bounce",
        type: "Suppressed",
      },
    } : {}),
    ...(type === "email.failed" ? {
      failed: { reason: "reached_daily_quota" },
    } : {}),
    ...data,
  };

  return {
    type,
    created_at: "2026-11-19T00:00:00.000Z",
    data: eventData,
  };
}

test("verifies the raw Svix HMAC signature", async () => {
  const payload = JSON.stringify(event("email.bounced", { bounce: { diagnosticCode: [], message: "Rejected by recipient server.", subType: "General", type: "Permanent" } }));
  assert.equal(await verifyResendWebhookSignature({
    payload,
    headers: signed(payload),
    secret,
    nowSeconds,
  }), true);
});

test("accepts a valid v1 signature among rotated signature candidates", async () => {
  const payload = JSON.stringify(event("email.complained"));
  const headers = signed(payload);
  headers.signature = `v1,${Buffer.from("invalid").toString("base64")} ${headers.signature}`;
  assert.equal(await verifyResendWebhookSignature({
    payload,
    headers,
    secret,
    nowSeconds,
  }), true);
});

test("rejects modified payloads, wrong secrets and malformed signatures", async () => {
  const payload = JSON.stringify(event("email.bounced", { bounce: { diagnosticCode: [], message: "Rejected by recipient server.", subType: "General", type: "Permanent" } }));
  const headers = signed(payload);
  assert.equal(await verifyResendWebhookSignature({
    payload: payload + " ",
    headers,
    secret,
    nowSeconds,
  }), false);
  assert.equal(await verifyResendWebhookSignature({
    payload,
    headers,
    secret: `whsec_${Buffer.from("wrong-secret").toString("base64")}`,
    nowSeconds,
  }), false);
  assert.equal(await verifyResendWebhookSignature({
    payload,
    headers: { ...headers, signature: "v2,not-supported" },
    secret,
    nowSeconds,
  }), false);
});

test("rejects stale and future timestamps outside the five-minute window", async () => {
  const payload = JSON.stringify(event("email.complained"));
  for (const offset of [-301, 301]) {
    const headers = signed(payload, { timestamp: String(nowSeconds + offset) });
    assert.equal(await verifyResendWebhookSignature({
      payload,
      headers,
      secret,
      nowSeconds,
    }), false);
  }
  const boundary = signed(payload, { timestamp: String(nowSeconds - 300) });
  assert.equal(await verifyResendWebhookSignature({
    payload,
    headers: boundary,
    secret,
    nowSeconds,
  }), true);
});

test("rejects missing, malformed and oversized signing metadata", async () => {
  const payload = JSON.stringify(event("email.bounced", { bounce: { diagnosticCode: [], message: "Rejected by recipient server.", subType: "General", type: "Permanent" } }));
  const headers = signed(payload);
  for (const candidate of [
    { ...headers, id: "" },
    { ...headers, id: "message id with spaces" },
    { ...headers, timestamp: "1.5" },
    { ...headers, timestamp: "not-a-time" },
    { ...headers, signature: "" },
  ]) {
    assert.equal(await verifyResendWebhookSignature({
      payload,
      headers: candidate,
      secret,
      nowSeconds,
    }), false);
  }
  assert.equal(await verifyResendWebhookSignature({
    payload,
    headers,
    secret: "not-a-webhook-secret",
    nowSeconds,
  }), false);
});

test("parses permanent bounce and normalizes the recipient", () => {
  const parsed = parseResendProviderEvent(
    event("email.bounced", { to: [" Member@Example.test "], bounce: { diagnosticCode: [], message: "Rejected by recipient server.", subType: "General", type: "Permanent" } }),
    id,
  );
  assert.deepEqual(parsed, {
    status: "accepted",
    event: {
      eventId: id,
      eventType: "email.bounced",
      providerEmailId: "resend_email_fixture_01",
      recipientEmail: "member@example.test",
      providerCreatedAt: "2026-11-19T00:00:00.000Z",
      bounceType: "Permanent",
      failureClass: null,
      suppressionReason: null,
    },
  });
});

test("transient bounces are distinguished from permanent bounces", () => {
  const parsed = parseResendProviderEvent(
    event("email.bounced", { bounce: { diagnosticCode: [], message: "Temporary recipient failure.", subType: "MailboxFull", type: "Transient" } }),
    id,
  );
  assert.equal(parsed.status, "accepted");
  if (parsed.status === "accepted") assert.equal(parsed.event.bounceType, "Transient");
});

test("complaints and provider suppressions are recognized", () => {
  const complaint = parseResendProviderEvent(event("email.complained"), id);
  const suppressed = parseResendProviderEvent(event("email.suppressed"), id);
  assert.equal(complaint.status, "accepted");
  assert.equal(suppressed.status, "accepted");
  if (complaint.status === "accepted") {
    assert.equal(complaint.event.eventType, "email.complained");
    assert.equal(complaint.event.bounceType, null);
  }
  if (suppressed.status === "accepted") {
    assert.equal(suppressed.event.eventType, "email.suppressed");
    assert.equal(suppressed.event.bounceType, null);
    assert.equal(suppressed.event.suppressionReason, "previous_bounce");
  }
});

test("unknown event types and other application tags are ignored", () => {
  assert.deepEqual(parseResendProviderEvent(event("email.opened"), id), { status: "ignored" });
  const otherApp = event("email.complained", {
    tags: { application: "another-app" },
  });
  assert.deepEqual(parseResendProviderEvent(otherApp, id), { status: "ignored" });
  const untagged = event("email.bounced", { tags: {} });
  assert.deepEqual(parseResendProviderEvent(untagged, id), { status: "ignored" });
});

test("malformed Deedlight delivery events fail closed", () => {
  for (const payload of [
    event("email.bounced", { to: ["one@example.test", "two@example.test"], bounce: { diagnosticCode: [], message: "Rejected by recipient server.", subType: "General", type: "Permanent" } }),
    event("email.bounced", { email_id: "", bounce: { diagnosticCode: [], message: "Rejected by recipient server.", subType: "General", type: "Permanent" } }),
    event("email.bounced", { to: ["not-an-email"], bounce: { diagnosticCode: [], message: "Rejected by recipient server.", subType: "General", type: "Permanent" } }),
  ]) {
    assert.throws(() => parseResendProviderEvent(payload, id));
  }
});

test("unknown bounce classification is preserved for fail-closed suppression", () => {
  const parsed = parseResendProviderEvent(event("email.bounced", {
    bounce: {
      diagnosticCode: [],
      message: "Provider could not classify the bounce.",
      subType: "Undetermined",
      type: "Undetermined",
    },
  }), id);
  assert.equal(parsed.status, "accepted");
  if (parsed.status === "accepted") assert.equal(parsed.event.bounceType, "Unknown");
});

test("accepts provider-shaped fixtures for all seven lifecycle events", () => {
  const cases = [
    ["email.sent", {}],
    ["email.delivered", {}],
    ["email.delivery_delayed", {}],
    ["email.bounced", {}],
    ["email.complained", {}],
    ["email.suppressed", {}],
    ["email.failed", { failed: { reason: "reached_daily_quota" } }],
  ];
  for (const [type, data] of cases) {
    const parsed = parseResendProviderEvent(event(type, data), id);
    assert.equal(parsed.status, "accepted", type);
    if (parsed.status === "accepted") {
      assert.equal(parsed.event.eventType, type);
      assert.equal(parsed.event.providerCreatedAt, "2026-11-19T00:00:00.000Z");
      assert.equal(parsed.event.suppressionReason, type === "email.suppressed" ? "previous_bounce" : null);
    }
  }
});

test("normalizes failed-event reasons without retaining provider diagnostics", () => {
  const cases = [
    ["invalid recipient address", "invalid_recipient"],
    ["api key invalid", "provider_authentication"],
    ["domain not verified", "domain_verification"],
    ["daily quota reached", "quota_exceeded"],
    ["content rejected by policy", "content_rejected"],
    ["unrecognized_provider_detail", "unknown"],
  ];
  for (const [reason, expected] of cases) {
    const parsed = parseResendProviderEvent(event("email.failed", {
      failed: { reason },
    }), id);
    assert.equal(parsed.status, "accepted");
    if (parsed.status === "accepted") {
      assert.equal(parsed.event.failureClass, expected);
      assert.equal(JSON.stringify(parsed).includes(reason), false);
    }
  }
});

test("rejects missing or malformed provider event timestamps", () => {
  for (const createdAt of [
    undefined,
    "not-a-timestamp",
    "2026-11-19",
    "2026-02-30T00:00:00Z",
  ]) {
    const payload = event("email.sent");
    payload.created_at = createdAt;
    assert.throws(() => parseResendProviderEvent(payload, id));
  }
});

test("failed lifecycle events require a reason and event-specific metadata stays isolated", () => {
  assert.throws(() => parseResendProviderEvent(event("email.failed", { failed: undefined }), id));
  const sent = parseResendProviderEvent(event("email.sent", {
    failed: { reason: "daily quota reached" },
  }), id);
  const delivered = parseResendProviderEvent(event("email.delivered", {
    bounce: { diagnosticCode: [], message: "Rejected by recipient server.", subType: "General", type: "Permanent" },
  }), id);
  assert.equal(sent.status, "accepted");
  assert.equal(delivered.status, "accepted");
  if (sent.status === "accepted") assert.equal(sent.event.failureClass, null);
  if (delivered.status === "accepted") assert.equal(delivered.event.bounceType, null);
});


test("maps both Resend suppression reasons without retaining provider diagnostics", () => {
  for (const [reason, expected] of [
    ["previous_bounce", "previous_bounce"],
    ["previous_complaint", "previous_complaint"],
  ]) {
    const parsed = parseResendProviderEvent(event("email.suppressed", {
      suppressed: {
        diagnosticCode: ["smtp; 550 suppression"],
        message: "Resend suppressed this address.",
        reason,
        type: "OnAccountSuppressionList",
      },
    }), id);
    assert.equal(parsed.status, "accepted");
    if (parsed.status === "accepted") {
      assert.equal(parsed.event.suppressionReason, expected);
      assert.equal(JSON.stringify(parsed).includes("smtp; 550"), false);
      assert.equal(JSON.stringify(parsed).includes("Resend suppressed"), false);
    }
  }
});

test("rejects missing or malformed bounce and suppression objects", () => {
  for (const payload of [
    event("email.bounced", { bounce: undefined }),
    event("email.bounced", { bounce: { type: "Permanent" } }),
    event("email.bounced", { bounce: {
      diagnosticCode: [],
      message: "Rejected.",
      subType: "NotAProviderSubtype",
      type: "Permanent",
    } }),
    event("email.suppressed", { suppressed: undefined }),
    event("email.suppressed", { suppressed: {
      diagnosticCode: [],
      message: "Suppressed.",
      type: "Suppressed",
    } }),
    event("email.suppressed", { suppressed: {
      diagnosticCode: [],
      message: "Suppressed.",
      reason: "manual",
      type: "Suppressed",
    } }),
  ]) {
    assert.throws(() => parseResendProviderEvent(payload, id));
  }
});

test("computes a stable SHA-256 fingerprint of the exact signed webhook body", async () => {
  const payload = JSON.stringify(event("email.bounced"));
  const fingerprint = await fingerprintResendWebhookPayload(payload);
  assert.match(fingerprint, /^[a-f0-9]{64}$/);
  assert.equal(await fingerprintResendWebhookPayload(payload), fingerprint);
  assert.notEqual(await fingerprintResendWebhookPayload(payload + " "), fingerprint);
});


test("rejects missing common event data required by Resend", () => {
  for (const payload of [
    event("email.sent", { created_at: undefined }),
    event("email.sent", { from: undefined }),
    event("email.sent", { subject: undefined }),
  ]) {
    assert.throws(() => parseResendProviderEvent(payload, id));
  }
});
