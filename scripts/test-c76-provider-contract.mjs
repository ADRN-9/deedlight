import assert from "node:assert/strict";
import { createHmac, randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";

import { InvalidResendWebhook, verifyResendDeliveryWebhook } from "../lib/delivery/resend-webhook.ts";
import { DAILY_DELIVERY_CRON, WEEKLY_DELIVERY_CRON, runScheduledDelivery } from "../lib/delivery/scheduler.ts";

const signingKey = randomBytes(32);
const secret = `whsec_${signingKey.toString("base64")}`;
const now = new Date();
let sequence = 0;
function signed(type, data, options = {}) {
  const rawBody = JSON.stringify({ type, created_at: now.toISOString(), data });
  const eventId = `msg_c76_${String(++sequence).padStart(8, "0")}`;
  const stamp = options.timestamp ?? String(Math.floor(now.getTime() / 1000));
  const sig = `v1,${createHmac("sha256", signingKey)
    .update(`${eventId}.${stamp}.${rawBody}`).digest("base64")}`;
  return {
    rawBody: options.modified ?? rawBody,
    headers: new Headers({
      "svix-id": eventId,
      "svix-timestamp": stamp,
      "svix-signature": options.signature ?? sig,
    }),
    secret,
    now,
  };
}
const delivery = (extra = {}) => ({
  email_id: "provider-c76-synthetic-01",
  to: ["c76@example.test"],
  ...extra,
});
const suppression = (extra = {}) => ({
  id: "fe9751fd-9b5f-4aa8-9e04-50abbb6ad241",
  email: "c76@example.test",
  origin: "manual",
  source_id: null,
  created_at: now.toISOString(),
  ...extra,
});

test("official signed suppression.added is distinct from a message event", async () => {
  const result = await verifyResendDeliveryWebhook(signed("suppression.added", suppression()));
  assert.equal(result.kind, "account_suppression");
  assert.equal(result.eventType, "suppression.added");
  assert.equal(result.recipientEmail, "c76@example.test");
  assert.equal(result.sourceId, null);
  assert.match(result.payloadSha256, /^[0-9a-f]{64}$/);
});

test("signed suppression.removed retains classification; removal is audit-only", async () => {
  const result = await verifyResendDeliveryWebhook(signed("suppression.removed", suppression({
    origin: "complaint", source_id: "provider-c76-synthetic-01",
  })));
  assert.equal(result.kind, "account_suppression");
  assert.equal(result.origin, "complaint");
  assert.equal(result.sourceId, "provider-c76-synthetic-01");
});

test("missing or forged suppression identity and classification fail closed", async () => {
  for (const payload of [
    suppression({ email: undefined }),
    suppression({ id: null }),
    suppression({ origin: "unknown" }),
    suppression({ source_id: { id: "provider" } }),
    suppression({ created_at: "not-a-time" }),
  ]) {
    await assert.rejects(verifyResendDeliveryWebhook(signed("suppression.added", payload)), InvalidResendWebhook);
  }
  await assert.rejects(verifyResendDeliveryWebhook(signed("suppression.added", suppression(), {
    signature: "v1,invalid",
  })), InvalidResendWebhook);
  await assert.rejects(verifyResendDeliveryWebhook(signed("suppression.added", suppression(), {
    timestamp: "1600000000",
  })), InvalidResendWebhook);
  const altered = signed("suppression.removed", suppression());
  altered.rawBody += " ";
  await assert.rejects(verifyResendDeliveryWebhook(altered), InvalidResendWebhook);
});

test("Permanent, Transient, and Undetermined retain original bounce class", async () => {
  for (const type of ["Permanent", "Transient", "Undetermined"]) {
    const result = await verifyResendDeliveryWebhook(signed("email.bounced", delivery({
      bounce: { type, subType: "Undetermined", message: "synthetic", diagnosticCode: [] },
    })));
    assert.equal(result.kind, "delivery");
    assert.equal(result.bounceType, type);
    assert.equal(result.suppressionReason, type === "Permanent" ? "permanent_bounce" : null);
  }
  await assert.rejects(verifyResendDeliveryWebhook(signed("email.bounced", delivery({
    bounce: { type: "Unknown" },
  }))), InvalidResendWebhook);
});

test("no arbitrary recipient association or unsigned provider event", async () => {
  await assert.rejects(verifyResendDeliveryWebhook(signed("email.delivered", delivery({
    to: ["a@example.test", "b@example.test"],
  }))), InvalidResendWebhook);
  await assert.rejects(verifyResendDeliveryWebhook(signed("contact.created", {})), InvalidResendWebhook);
});

test("Cloudflare Monday is MON (not Sunday numeric 1); Production cron remains disabled", async () => {
  assert.equal(DAILY_DELIVERY_CRON, "*/5 * * * *");
  assert.equal(WEEKLY_DELIVERY_CRON, "0 16 * * MON");
  assert.deepEqual(JSON.parse(readFileSync("wrangler.jsonc", "utf8")).triggers.crons, []);
  const validConfig = {
    DELIVERY_ENABLED: "true", DELIVERY_PROVIDER: "resend", SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic", RESEND_API_KEY: "re_synthetic",
    DELIVERY_FROM_EMAIL: "hello@example.test", NEXT_PUBLIC_SITE_URL: "https://example.test",
  };
  for (const iso of ["2026-11-15T16:00:00Z", "2026-11-17T16:00:00Z", "2026-11-16T16:01:00Z"]) {
    const out = await runScheduledDelivery(validConfig, { cron: WEEKLY_DELIVERY_CRON,
      scheduledTime: Date.parse(iso) });
    assert.equal(out.ignored, true);
    assert.equal(out.claimed, 0);
  }
  const oldSunday = await runScheduledDelivery(validConfig, {
    cron: "0 16 * * 1", scheduledTime: Date.parse("2026-11-15T16:00:00Z"),
  });
  assert.equal(oldSunday.ignored, true);
  const disabled = await runScheduledDelivery({ DELIVERY_ENABLED: "false" }, {
    cron: WEEKLY_DELIVERY_CRON, scheduledTime: Date.parse("2026-11-16T16:00:00Z"),
  });
  assert.equal(disabled.enabled, false);
  assert.equal(disabled.sent, 0);
});
