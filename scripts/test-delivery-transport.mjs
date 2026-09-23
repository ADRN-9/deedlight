import assert from "node:assert/strict";
import test from "node:test";

import { parseDeliveryRuntimeConfig } from "../lib/delivery/config.ts";
import { createResendTransport } from "../lib/delivery/resend-transport.ts";
import { processClaimedDelivery } from "../lib/delivery/run-delivery.ts";

const job = {
  jobId: "11111111-1111-1111-1111-111111111111",
  userId: "22222222-2222-2222-2222-222222222222",
  kind: "daily_reminder",
  deliveryKey: "daily:2026-09-23",
  scheduledFor: "2026-09-23T15:00:00.000Z",
  claimToken: "33333333-3333-3333-3333-333333333333",
};

function runtimeEnv(overrides = {}) {
  return {
    DELIVERY_ENABLED: "true",
    DELIVERY_PROVIDER: "resend",
    SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "service-role-test",
    RESEND_API_KEY: "re_test",
    DELIVERY_FROM_EMAIL: "Deedlight <hello@example.com>",
    NEXT_PUBLIC_SITE_URL: "https://deedlight.example",
    DELIVERY_BATCH_SIZE: "25",
    ...overrides,
  };
}

function fakeGateway(options = {}) {
  const events = [];
  let authorizeIndex = 0;
  const authorizations = options.authorizations ?? [true, true];
  return {
    events,
    gateway: {
      async authorize() {
        events.push("authorize");
        return authorizations[authorizeIndex++] ?? authorizations.at(-1) ?? false;
      },
      async beginTransport() {
        events.push("begin");
        return options.firstTransportAt ?? new Date("2026-09-23T20:00:00.000Z");
      },
      async markSent(_job, id) {
        events.push(`sent:${id}`);
      },
      async markFailed(_job, code) {
        events.push(`failed:${code}`);
      },
      async retry(_job, retryAt, code) {
        events.push(`retry:${code}:${retryAt.toISOString()}`);
      },
    },
  };
}

test("delivery is disabled without requiring secrets", () => {
  assert.deepEqual(parseDeliveryRuntimeConfig({ DELIVERY_ENABLED: "false" }), { enabled: false });
});

test("enabled delivery fails closed on missing secrets and unsupported provider", () => {
  assert.throws(() => parseDeliveryRuntimeConfig(runtimeEnv({ RESEND_API_KEY: "" })), /RESEND_API_KEY/);
  assert.throws(() => parseDeliveryRuntimeConfig(runtimeEnv({ DELIVERY_PROVIDER: "other" })), /Unsupported/);
});

test("Resend transport uses stable idempotency and generic content", async () => {
  const calls = [];
  const transport = createResendTransport(
    { apiKey: "re_test", fromEmail: "Deedlight <hello@example.com>", siteOrigin: "https://deedlight.example" },
    async (url, init) => {
      calls.push({ url, init });
      return new Response(JSON.stringify({ id: "provider-123" }), { status: 200, headers: { "content-type": "application/json" } });
    },
  );

  const outcome = await transport.send(job, { email: "member@example.com" });
  assert.deepEqual(outcome, { status: "sent", providerResultId: "provider-123" });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].init.headers["Idempotency-Key"], `deedlight/${job.kind}/${job.jobId}`);
  const payload = JSON.parse(calls[0].init.body);
  assert.deepEqual(payload.to, ["member@example.com"]);
  assert.match(payload.text, /settings\/reminders/);
  assert.doesNotMatch(payload.text, new RegExp(job.userId));
});

test("Resend transport classifies retryable, permanent and ambiguous responses", async () => {
  const temporary = createResendTransport({ apiKey: "x", fromEmail: "x@y.com", siteOrigin: "https://example.com" }, async () => new Response("", { status: 503 }));
  assert.deepEqual(await temporary.send(job, { email: "a@b.com" }), { status: "temporary_failure", errorCode: "provider_http_503" });

  const permanent = createResendTransport({ apiKey: "x", fromEmail: "x@y.com", siteOrigin: "https://example.com" }, async () => new Response("", { status: 400 }));
  assert.deepEqual(await permanent.send(job, { email: "a@b.com" }), { status: "permanent_failure", errorCode: "provider_http_400" });

  const malformed = createResendTransport({ apiKey: "x", fromEmail: "x@y.com", siteOrigin: "https://example.com" }, async () => new Response("{}", { status: 200 }));
  assert.deepEqual(await malformed.send(job, { email: "a@b.com" }), { status: "temporary_failure", errorCode: "provider_ambiguous_response" });
});

test("revocation before recipient lookup prevents transport", async () => {
  const { gateway, events } = fakeGateway({ authorizations: [false] });
  let resolved = false;
  let sent = false;
  const result = await processClaimedDelivery({
    job,
    gateway,
    recipientResolver: { async resolve() { resolved = true; return { email: "a@b.com" }; } },
    transport: { async send() { sent = true; return { status: "sent", providerResultId: "x" }; } },
    now: new Date("2026-09-23T20:00:00.000Z"),
  });
  assert.equal(result, "cancelled");
  assert.equal(resolved, false);
  assert.equal(sent, false);
  assert.deepEqual(events, ["authorize"]);
});

test("revocation after recipient lookup is checked again immediately before transport", async () => {
  const { gateway, events } = fakeGateway({ authorizations: [true, false] });
  let sent = false;
  const result = await processClaimedDelivery({
    job,
    gateway,
    recipientResolver: { async resolve() { return { email: "a@b.com" }; } },
    transport: { async send() { sent = true; return { status: "sent", providerResultId: "x" }; } },
    now: new Date("2026-09-23T20:00:00.000Z"),
  });
  assert.equal(result, "cancelled");
  assert.equal(sent, false);
  assert.deepEqual(events, ["authorize", "authorize"]);
});

test("temporary provider failure requeues while permanent failure terminates", async () => {
  {
    const { gateway, events } = fakeGateway();
    const result = await processClaimedDelivery({
      job,
      gateway,
      recipientResolver: { async resolve() { return { email: "a@b.com" }; } },
      transport: { async send() { return { status: "temporary_failure", errorCode: "provider_http_503" }; } },
      now: new Date("2026-09-23T20:00:00.000Z"),
    });
    assert.equal(result, "retried");
    assert(events.some((event) => event.startsWith("retry:provider_http_503:")));
  }
  {
    const { gateway, events } = fakeGateway();
    const result = await processClaimedDelivery({
      job,
      gateway,
      recipientResolver: { async resolve() { return { email: "a@b.com" }; } },
      transport: { async send() { return { status: "permanent_failure", errorCode: "provider_http_400" }; } },
      now: new Date("2026-09-23T20:00:00.000Z"),
    });
    assert.equal(result, "failed");
    assert(events.includes("failed:provider_http_400"));
  }
});

test("ambiguous delivery older than the provider safety window never sends again", async () => {
  const { gateway, events } = fakeGateway({ firstTransportAt: new Date("2026-09-22T20:59:59.000Z") });
  let sent = false;
  const result = await processClaimedDelivery({
    job,
    gateway,
    recipientResolver: { async resolve() { return { email: "a@b.com" }; } },
    transport: { async send() { sent = true; return { status: "sent", providerResultId: "x" }; } },
    now: new Date("2026-09-23T20:00:00.000Z"),
  });
  assert.equal(result, "failed");
  assert.equal(sent, false);
  assert(events.includes("failed:provider_idempotency_window_expired"));
});
