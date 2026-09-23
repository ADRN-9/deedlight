import assert from "node:assert/strict";
import test from "node:test";

import { parseDeliveryRuntimeConfig } from "../lib/delivery/config.ts";
import { createResendTransport } from "../lib/delivery/resend-transport.ts";
import { processClaimedDelivery } from "../lib/delivery/run-delivery.ts";
import {
  DAILY_DELIVERY_CRON,
  runScheduledDelivery,
} from "../lib/delivery/scheduler.ts";

const job = {
  jobId: "11111111-1111-1111-1111-111111111111",
  userId: "22222222-2222-2222-2222-222222222222",
  kind: "daily_reminder",
  deliveryKey: "daily:2026-09-23",
  scheduledFor: "2026-09-23T15:00:00.000Z",
  claimToken: "33333333-3333-3333-3333-333333333333",
};

const weeklyJob = {
  ...job,
  jobId: "44444444-4444-4444-4444-444444444444",
  kind: "weekly_newsletter",
  deliveryKey: "weekly:2026-09-21",
};

const fixedNow = new Date("2026-09-23T20:00:00.000Z");
const fixedClock = () => new Date(fixedNow);

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
        return options.firstTransportAt ?? new Date(fixedNow);
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

test("disabled scheduler performs no work and unknown schedules are ignored", async () => {
  const disabled = await runScheduledDelivery(
    { DELIVERY_ENABLED: "false" },
    { cron: DAILY_DELIVERY_CRON, scheduledTime: fixedNow.getTime() },
  );
  assert.equal(disabled.enabled, false);
  assert.equal(disabled.claimed, 0);
  assert.equal(disabled.sent, 0);

  const ignored = await runScheduledDelivery(
    runtimeEnv(),
    { cron: "17 4 * * *", scheduledTime: fixedNow.getTime() },
  );
  assert.equal(ignored.enabled, true);
  assert.equal(ignored.ignored, true);
  assert.equal(ignored.claimed, 0);
});

test("Resend transport uses stable idempotency and generic daily content", async () => {
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

test("weekly transport uses the weekly preference route and a distinct idempotency key", async () => {
  let captured;
  const transport = createResendTransport(
    { apiKey: "re_test", fromEmail: "Deedlight <hello@example.com>", siteOrigin: "https://deedlight.example" },
    async (_url, init) => {
      captured = init;
      return new Response(JSON.stringify({ id: "provider-weekly" }), { status: 200 });
    },
  );

  await transport.send(weeklyJob, { email: "member@example.com" });
  assert.equal(captured.headers["Idempotency-Key"], `deedlight/${weeklyJob.kind}/${weeklyJob.jobId}`);
  const payload = JSON.parse(captured.body);
  assert.match(payload.text, /settings\/newsletter/);
  assert.match(payload.text, /\/weekly/);
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
    clock: fixedClock,
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
    clock: fixedClock,
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
      clock: fixedClock,
    });
    assert.equal(result, "retried");
    assert(events.includes("retry:provider_http_503:2026-09-23T20:05:00.000Z"));
  }
  {
    const { gateway, events } = fakeGateway();
    const result = await processClaimedDelivery({
      job,
      gateway,
      recipientResolver: { async resolve() { return { email: "a@b.com" }; } },
      transport: { async send() { return { status: "permanent_failure", errorCode: "provider_http_400" }; } },
      clock: fixedClock,
    });
    assert.equal(result, "failed");
    assert(events.includes("failed:provider_http_400"));
  }
});

test("small database/worker clock skew does not fail a new transport attempt", async () => {
  const { gateway, events } = fakeGateway({
    firstTransportAt: new Date("2026-09-23T20:00:00.250Z"),
  });
  const result = await processClaimedDelivery({
    job,
    gateway,
    recipientResolver: { async resolve() { return { email: "a@b.com" }; } },
    transport: { async send() { return { status: "sent", providerResultId: "clock-safe" }; } },
    clock: fixedClock,
  });
  assert.equal(result, "sent");
  assert(events.includes("sent:clock-safe"));
});

test("ambiguous delivery older than the provider safety window never sends again", async () => {
  const { gateway, events } = fakeGateway({ firstTransportAt: new Date("2026-09-22T20:59:59.000Z") });
  let sent = false;
  const result = await processClaimedDelivery({
    job,
    gateway,
    recipientResolver: { async resolve() { return { email: "a@b.com" }; } },
    transport: { async send() { sent = true; return { status: "sent", providerResultId: "x" }; } },
    clock: fixedClock,
  });
  assert.equal(result, "failed");
  assert.equal(sent, false);
  assert(events.includes("failed:provider_idempotency_window_expired"));
});
