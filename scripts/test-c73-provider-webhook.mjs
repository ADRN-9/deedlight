import assert from "node:assert/strict";
import { createHmac, randomBytes } from "node:crypto";
import { test } from "node:test";

import {
  InvalidResendWebhook,
  verifyResendDeliveryWebhook,
} from "../lib/delivery/resend-webhook.ts";
import { parseDeliveryRuntimeConfig } from "../lib/delivery/config.ts";
import { SupabaseDeliveryRuntime } from "../lib/delivery/supabase-runtime.ts";
import { DEEDLIGHT_SUPABASE_ORIGIN, DEEDLIGHT_SUPABASE_PROJECT_REF } from "../lib/supabase/project-identity.ts";
import { isTrustedSupabaseDestination } from "../lib/supabase/trusted-destination.ts";
import { readFileSync } from "node:fs";

const now = new Date();
const signingKey = randomBytes(32);
const secret = `whsec_${signingKey.toString("base64")}`;
const id = "msg_C73SyntheticSignature001";
const date = new Date(now.getTime() - 2000).toISOString();

function signed(type, data = {}, overrides = {}) {
  const body = JSON.stringify({
    type,
    created_at: date,
    data: {
      email_id: "synthetic-provider-id",
      to: ["synthetic@example.test"],
      ...data,
    },
  });
  const stamp = overrides.timestamp ?? String(Math.floor(now.getTime() / 1000));
  const signedId = overrides.id ?? id;
  const signature = `v1,${createHmac("sha256", signingKey)
    .update(`${signedId}.${stamp}.${body}`)
    .digest("base64")}`;
  return {
    rawBody: overrides.body ?? body,
    headers: new Headers({
      "svix-id": signedId,
      "svix-timestamp": stamp,
      "svix-signature": overrides.signature ?? signature,
    }),
    secret,
    now,
  };
}

test("official Svix verifier authenticates raw Resend envelope", async () => {
  const value = await verifyResendDeliveryWebhook(signed("email.delivered"));
  assert.equal(value.eventId, id);
  assert.equal(value.eventType, "email.delivered");
  assert.equal(value.recipientEmail, "synthetic@example.test");
  assert.equal(value.providerEmailId, "synthetic-provider-id");
  assert.match(value.payloadSha256, /^[0-9a-f]{64}$/);
});

test("signature alteration and replay timestamp fail closed", async () => {
  await assert.rejects(verifyResendDeliveryWebhook(signed("email.sent", {}, { signature: "v1,bad" })), InvalidResendWebhook);
  await assert.rejects(verifyResendDeliveryWebhook(signed("email.sent", {}, { timestamp: "1600000000" })), InvalidResendWebhook);
  const input = signed("email.sent");
  input.rawBody += " ";
  await assert.rejects(verifyResendDeliveryWebhook(input), InvalidResendWebhook);
});

test("verified payload cannot forge multiple recipient associations", async () => {
  await assert.rejects(verifyResendDeliveryWebhook(signed("email.delivered", { to: ["a@example.test", "b@example.test"] })), InvalidResendWebhook);
  await assert.rejects(verifyResendDeliveryWebhook(signed("contact.created")), InvalidResendWebhook);
  await assert.rejects(verifyResendDeliveryWebhook(signed("email.bounced")), InvalidResendWebhook);
});

test("permanent bounce, complaint and provider suppression remain explicit", async () => {
  assert.equal((await verifyResendDeliveryWebhook(signed("email.bounced", { bounce: { type: "Permanent" } }))).suppressionReason, "permanent_bounce");
  assert.equal((await verifyResendDeliveryWebhook(signed("email.bounced", { bounce: { type: "Transient" } }))).suppressionReason, null);
  assert.equal((await verifyResendDeliveryWebhook(signed("email.complained"))).suppressionReason, "spam_complaint");
  assert.equal((await verifyResendDeliveryWebhook(signed("email.suppressed", { suppressed: { type: "OnAccountSuppressionList" } }))).eventType, "email.suppressed");
  await assert.rejects(verifyResendDeliveryWebhook(signed("email.suppressed")), InvalidResendWebhook);
});

test("DELIVERY_ENABLED=false is strictly no-send even with missing provider secrets", () => {
  assert.deepEqual(parseDeliveryRuntimeConfig({ DELIVERY_ENABLED: "false" }), { enabled: false });
  assert.deepEqual(parseDeliveryRuntimeConfig({}), { enabled: false });
  assert.throws(() => parseDeliveryRuntimeConfig({ DELIVERY_ENABLED: "true" }), /Missing required delivery configuration/);
});


test("webhook accepts only the exact canonical DeedLight Supabase destination", () => {
  assert.equal(DEEDLIGHT_SUPABASE_PROJECT_REF, "xaipiovflxomcbfwtwmu");
  assert.equal(DEEDLIGHT_SUPABASE_ORIGIN, "https://xaipiovflxomcbfwtwmu.supabase.co");
  assert.equal(isTrustedSupabaseDestination(DEEDLIGHT_SUPABASE_ORIGIN), true);
});

test("webhook rejects unrelated Supabase projects and deceptive hostname variants", () => {
  for (const value of [
    "https://anotherproject.supabase.co",
    "https://xaipiovflxomcbfwtwmu.supabase.co.attacker.example",
    "https://xaipiovflxomcbfwtwmu.supabase.co.evil",
    "https://xaipiovflxomcbfwtwmu.supabase.com",
    "https://XAIPIOVFLXOMCBFWTWMU.supabase.co",
    "https://xaipiovflxomcbfwtwmu.supabase.co.",
  ]) {
    assert.equal(isTrustedSupabaseDestination(value), false, value);
  }
});

test("webhook rejects noncanonical origins, unexpected ports, credentials, paths, queries and fragments", () => {
  for (const value of [
    "http://xaipiovflxomcbfwtwmu.supabase.co",
    "https://xaipiovflxomcbfwtwmu.supabase.co:443",
    "https://xaipiovflxomcbfwtwmu.supabase.co:8443",
    "https://user@xaipiovflxomcbfwtwmu.supabase.co",
    "https://user:password@xaipiovflxomcbfwtwmu.supabase.co",
    "https://xaipiovflxomcbfwtwmu.supabase.co/",
    "https://xaipiovflxomcbfwtwmu.supabase.co/rest/v1",
    "https://xaipiovflxomcbfwtwmu.supabase.co?redirect=evil",
    "https://xaipiovflxomcbfwtwmu.supabase.co#fragment",
    " https://xaipiovflxomcbfwtwmu.supabase.co",
    "https://xaipiovflxomcbfwtwmu.supabase.co ",
    "",
    "not a url",
  ]) {
    assert.equal(isTrustedSupabaseDestination(value), false, value);
  }
  assert.equal(isTrustedSupabaseDestination(null), false);
  assert.equal(isTrustedSupabaseDestination(undefined), false);
});

test("webhook destination guard executes before privileged Supabase client construction", () => {
  const source = readFileSync(new URL("../app/api/webhooks/resend/route.ts", import.meta.url), "utf8");
  const guard = source.indexOf("!isTrustedSupabaseDestination(supabaseUrl)");
  const client = source.indexOf("createClient(supabaseUrl, serviceRoleKey");
  assert.notEqual(guard, -1);
  assert.notEqual(client, -1);
  assert.ok(guard < client);
});

test("kind-isolated claim RPC includes kind and fails on a cross-kind response", async () => {
  const calls = [];
  const client = { rpc: async (name, args) => {
    calls.push([name, args]);
    return { data: [{
      job_id: "00000000-0000-0000-0000-000000000001",
      user_id: "00000000-0000-0000-0000-000000000002",
      kind: "weekly_newsletter",
      delivery_key: "weekly:2026-11-09",
      scheduled_for: now.toISOString(),
      claim_token: "00000000-0000-0000-0000-000000000003",
    }], error: null };
  }};
  const gateway = new SupabaseDeliveryRuntime(client);
  await assert.rejects(gateway.claim("daily_reminder", now, 10), /cross-kind claim response/);
  assert.equal(calls[0][0], "claim_delivery_jobs");
  assert.equal(calls[0][1].p_kind, "daily_reminder");
});
