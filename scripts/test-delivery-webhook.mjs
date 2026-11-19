import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";

import {
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
  return {
    type,
    created_at: "2026-11-19T00:00:00.000Z",
    data: {
      email_id: "resend_email_fixture_01",
      to: ["Member@Example.test"],
      tags: { application: "deedlight" },
      ...data,
    },
  };
}

test("verifies the raw Svix HMAC signature", async () => {
  const payload = JSON.stringify(event("email.bounced", { bounce: { type: "Permanent" } }));
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
  const payload = JSON.stringify(event("email.bounced", { bounce: { type: "Permanent" } }));
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
  const payload = JSON.stringify(event("email.bounced", { bounce: { type: "Permanent" } }));
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
    event("email.bounced", { to: [" Member@Example.test "], bounce: { type: "Permanent" } }),
    id,
  );
  assert.deepEqual(parsed, {
    status: "accepted",
    event: {
      eventId: id,
      eventType: "email.bounced",
      providerEmailId: "resend_email_fixture_01",
      recipientEmail: "member@example.test",
      bounceType: "Permanent",
    },
  });
});

test("transient bounces are distinguished from permanent bounces", () => {
  const parsed = parseResendProviderEvent(
    event("email.bounced", { bounce: { type: "Transient" } }),
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
    event("email.bounced", { to: ["one@example.test", "two@example.test"], bounce: { type: "Permanent" } }),
    event("email.bounced", { email_id: "", bounce: { type: "Permanent" } }),
    event("email.bounced", { to: ["not-an-email"], bounce: { type: "Permanent" } }),
  ]) {
    assert.throws(() => parseResendProviderEvent(payload, id));
  }
});

test("unknown bounce classification is preserved for fail-closed suppression", () => {
  const parsed = parseResendProviderEvent(event("email.bounced"), id);
  assert.equal(parsed.status, "accepted");
  if (parsed.status === "accepted") assert.equal(parsed.event.bounceType, "Unknown");
});

test("accepts all seven lifecycle events and preserves provider event timestamps", () => {
  const cases = [
    ["email.sent", {}],
    ["email.delivered", {}],
    ["email.delivery_delayed", {}],
    ["email.bounced", { bounce: { type: "Permanent" } }],
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
    }
  }
});

test("normalizes failed-event reasons without retaining provider diagnostics", () => {
  const cases = [
    ["invalid_recipient", "invalid_recipient"],
    ["api_key_invalid", "provider_authentication"],
    ["domain_not_verified", "domain_verification"],
    ["reached_daily_quota", "quota_exceeded"],
    ["content_rejected", "content_rejected"],
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

test("failed lifecycle events require a reason and bounce metadata stays event-specific", () => {
  assert.throws(() => parseResendProviderEvent(event("email.failed"), id));
  assert.throws(() => parseResendProviderEvent(event("email.sent", {
    failed: { reason: "reached_daily_quota" },
  }), id));
  assert.throws(() => parseResendProviderEvent(event("email.delivered", {
    bounce: { type: "Permanent" },
  }), id));
});
