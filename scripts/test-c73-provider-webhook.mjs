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
import { createResendWebhookHandler, POST as resendWebhookPOST } from "../app/api/webhooks/resend/route.ts";

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
  const client = source.indexOf("createPrivilegedClient(supabaseUrl, serviceRoleKey");
  assert.notEqual(guard, -1);
  assert.notEqual(client, -1);
  assert.ok(guard < client);
});


test("actual webhook handler rejects invalid destinations with 503 and no privileged operations", async () => {
  const invalidDestinations = [
    "https://anotherproject.supabase.co",
    "https://xaipiovflxomcbfwtwmu.supabase.co:8443",
    "https://xaipiovflxomcbfwtwmu.supabase.co:443",
    "https://user@xaipiovflxomcbfwtwmu.supabase.co",
    "https://user:password@xaipiovflxomcbfwtwmu.supabase.co",
    "https://xaipiovflxomcbfwtwmu.supabase.co/rest/v1",
    "https://xaipiovflxomcbfwtwmu.supabase.co?target=other",
    "https://xaipiovflxomcbfwtwmu.supabase.co#fragment",
    "not a URL",
    "https://[malformed",
  ];
  for (const destination of invalidDestinations) {
    let clientConstructions = 0;
    let databaseRequests = 0;
    let signatureVerifications = 0;
    const handler = createResendWebhookHandler({
      env: {
        RESEND_WEBHOOK_SECRET: "test-webhook-secret",
        SUPABASE_SERVICE_ROLE_KEY: "test-service-role-key",
        SUPABASE_URL: destination,
      },
      createPrivilegedClient: (() => {
        clientConstructions += 1;
        return { rpc: async () => {
          databaseRequests += 1;
          return { data: "recorded", error: null };
        }};
      }),
      verifyWebhook: async () => {
        signatureVerifications += 1;
        throw new Error("Invalid destination must fail before verification");
      },
    });
    const response = await handler(new Request("https://deedlight.test/api/webhooks/resend", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ type: "email.delivered" }),
    }));
    assert.equal(response.status, 503, destination);
    assert.equal(clientConstructions, 0, destination);
    assert.equal(databaseRequests, 0, destination);
    assert.equal(signatureVerifications, 0, destination);
  }
});

test("actual webhook handler rejects missing destination and required secrets with 503", async () => {
  const configurations = [
    { RESEND_WEBHOOK_SECRET: "secret", SUPABASE_SERVICE_ROLE_KEY: "key" },
    { RESEND_WEBHOOK_SECRET: "secret", SUPABASE_SERVICE_ROLE_KEY: "key", SUPABASE_URL: "" },
    { RESEND_WEBHOOK_SECRET: "", SUPABASE_SERVICE_ROLE_KEY: "key", SUPABASE_URL: DEEDLIGHT_SUPABASE_ORIGIN },
    { RESEND_WEBHOOK_SECRET: "secret", SUPABASE_SERVICE_ROLE_KEY: "", SUPABASE_URL: DEEDLIGHT_SUPABASE_ORIGIN },
  ];
  for (const env of configurations) {
    let clientConstructions = 0;
    let databaseRequests = 0;
    const handler = createResendWebhookHandler({
      env,
      createPrivilegedClient: (() => {
        clientConstructions += 1;
        return { rpc: async () => {
          databaseRequests += 1;
          return { data: "recorded", error: null };
        }};
      }),
      verifyWebhook: async () => {
        throw new Error("Missing configuration must fail before verification");
      },
    });
    const response = await handler(new Request("https://deedlight.test/api/webhooks/resend", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    }));
    assert.equal(response.status, 503);
    assert.equal(clientConstructions, 0);
    assert.equal(databaseRequests, 0);
  }
});

test("actual webhook handler constructs the client only after a trusted destination and verified event", async () => {
  let clientConstructions = 0;
  let databaseRequests = 0;
  let signatureVerifications = 0;
  const payload = JSON.stringify({ type: "email.delivered" });
  const handler = createResendWebhookHandler({
    env: {
      RESEND_WEBHOOK_SECRET: "test-webhook-secret",
      SUPABASE_SERVICE_ROLE_KEY: "test-service-role-key",
      SUPABASE_URL: DEEDLIGHT_SUPABASE_ORIGIN,
    },
    createPrivilegedClient: (() => {
      clientConstructions += 1;
      return { rpc: async (operation, args) => {
        databaseRequests += 1;
        assert.equal(operation, "deedlight_record_resend_delivery_v2");
        assert.equal(args.p_event_id, id);
        return { data: "recorded", error: null };
      }};
    }),
    verifyWebhook: async ({ rawBody, headers, secret: suppliedSecret }) => {
      signatureVerifications += 1;
      assert.equal(suppliedSecret, "test-webhook-secret");
      assert.equal(headers.get("content-type"), "application/json");
      assert.equal(rawBody, payload);
      return {
        kind: "delivery",
        eventId: id,
        providerEmailId: "synthetic-provider-id",
        recipientEmail: "synthetic@example.test",
        eventType: "email.delivered",
        eventAt: date,
        payloadSha256: "a".repeat(64),
        suppressionReason: null,
        bounceType: null,
      };
    },
  });
  const response = await handler(new Request("https://deedlight.test/api/webhooks/resend", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: payload,
  }));
  assert.equal(response.status, 200);
  assert.equal(signatureVerifications, 1);
  assert.equal(clientConstructions, 1);
  assert.equal(databaseRequests, 1);
});


test("exported Next.js POST route returns 503 for an unrelated Supabase destination", async () => {
  const keys = ["RESEND_WEBHOOK_SECRET", "SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_URL"];
  const previous = new Map(keys.map((key) => [key, process.env[key]]));
  try {
    process.env.RESEND_WEBHOOK_SECRET = "synthetic-webhook-secret";
    process.env.SUPABASE_SERVICE_ROLE_KEY = "synthetic-service-role-key";
    for (const destination of [
      "https://anotherproject.supabase.co",
      "https://xaipiovflxomcbfwtwmu.supabase.co:8443",
      "https://user:password@xaipiovflxomcbfwtwmu.supabase.co",
      "not a URL",
    ]) {
      process.env.SUPABASE_URL = destination;
      const response = await resendWebhookPOST(new Request("https://deedlight.test/api/webhooks/resend", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ type: "email.delivered" }),
      }));
      assert.equal(response.status, 503, destination);
    }
  } finally {
    for (const [key, value] of previous) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
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
