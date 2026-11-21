import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";

import { POST } from "../app/api/webhooks/resend/route.ts";

const secretBytes = Buffer.from("deedlight-route-fixture-secret");
const secret = "whsec_" + secretBytes.toString("base64");
const encoder = new TextEncoder();
const envNames = [
  "RESEND_WEBHOOK_SECRET",
  "SUPABASE_URL",
  "SUPABASE_SERVICE_ROLE_KEY",
];

function eventPayload() {
  return JSON.stringify({
    type: "email.bounced",
    created_at: "2026-11-19T00:00:00.000Z",
    data: {
      email_id: "resend_email_route_fixture_01",
      created_at: "2026-11-19T00:00:00.000Z",
      from: "Deedlight <no-reply@deedlight.example>",
      to: ["Member@Example.test"],
      subject: "Daily Deedlight",
      tags: { application: "deedlight" },
      bounce: {
        diagnosticCode: [],
        message: "The recipient server rejected the message.",
        subType: "General",
        type: "Permanent",
      },
    },
  });
}

function lifecyclePayload(type) {
  const payload = JSON.parse(eventPayload());
  payload.type = type;
  if (type === "email.failed") {
    delete payload.data.bounce;
    payload.data.failed = { reason: "reached_daily_quota" };
  } else if (type === "email.suppressed") {
    delete payload.data.bounce;
    payload.data.suppressed = {
      diagnosticCode: [],
      message: "Resend suppressed the address.",
      reason: "previous_bounce",
      type: "OnAccountSuppressionList",
    };
  } else if (type !== "email.bounced") {
    delete payload.data.bounce;
  }
  return JSON.stringify(payload);
}

function signedHeaders(payload, eventId = "msg_route_fixture_01") {
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = createHmac("sha256", secretBytes)
    .update(eventId + "." + timestamp + "." + payload)
    .digest("base64");

  return new Headers({
    "svix-id": eventId,
    "svix-timestamp": timestamp,
    "svix-signature": "v1," + signature,
  });
}

function makeRequest(payload, options = {}) {
  const headers = signedHeaders(payload, options.eventId);
  if (options.signature !== undefined) {
    headers.set("svix-signature", options.signature);
  }
  if (options.contentLength !== null) {
    const value = options.contentLength === undefined
      ? String(encoder.encode(payload).byteLength)
      : String(options.contentLength);
    headers.set("content-length", value);
  }

  return new Request("https://deedlight.test/api/webhooks/resend", {
    method: "POST",
    headers,
    body: payload,
  });
}

async function invoke(payload, options = {}) {
  const previousEnv = Object.fromEntries(
    envNames.map((name) => [name, process.env[name]]),
  );
  const originalFetch = globalThis.fetch;
  const calls = [];

  process.env.RESEND_WEBHOOK_SECRET = secret;
  process.env.SUPABASE_URL = "https://fixture.supabase.co";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "fixture-service-role-key";

  globalThis.fetch = async (input, init) => {
    calls.push({
      url: String(input),
      method: init?.method,
      body: String(init?.body ?? ""),
    });
    const status = options.databaseStatus ?? 200;
    const body = options.databaseBody ?? "true";
    return new Response(body, {
      status,
      headers: { "content-type": "application/json" },
    });
  };

  try {
    const response = await POST(makeRequest(payload, options));
    return { response, calls };
  } finally {
    globalThis.fetch = originalFetch;
    for (const name of envNames) {
      if (previousEnv[name] === undefined) delete process.env[name];
      else process.env[name] = previousEnv[name];
    }
  }
}

test("accepts numeric Content-Length and a valid Svix signature", async () => {
  const payload = eventPayload();
  const { response, calls } = await invoke(payload);

  assert.equal(response.status, 204);
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /\/rest\/v1\/rpc\/record_delivery_provider_lifecycle_event$/);
  assert.equal(calls[0].method, "POST");
  assert.equal(JSON.parse(calls[0].body).p_event_id, "msg_route_fixture_01");
});

test("accepts a valid Svix signature without Content-Length", async () => {
  const { response, calls } = await invoke(eventPayload(), { contentLength: null });

  assert.equal(response.status, 204);
  assert.equal(calls.length, 1);
});

test("rejects malformed Content-Length before signature verification", async () => {
  const { response, calls } = await invoke(eventPayload(), { contentLength: "12x" });

  assert.equal(response.status, 400);
  assert.equal(calls.length, 0);
});

test("rejects oversized declared Content-Length before reading the body", async () => {
  const { response, calls } = await invoke(eventPayload(), {
    contentLength: 64 * 1024 + 1,
  });

  assert.equal(response.status, 413);
  assert.equal(calls.length, 0);
});

test("rejects oversized streamed request bodies without Content-Length", async () => {
  const { response, calls } = await invoke("x".repeat(64 * 1024 + 1), {
    contentLength: null,
  });

  assert.equal(response.status, 413);
  assert.equal(calls.length, 0);
});

test("rejects invalid signatures without invoking the database", async () => {
  const invalidSignature = "v1," + Buffer.from("not-a-valid-signature").toString("base64");
  const { response, calls } = await invoke(eventPayload(), {
    signature: invalidSignature,
  });

  assert.equal(response.status, 401);
  assert.equal(calls.length, 0);
});

test("acknowledges replay attempts while preserving event-id idempotency", async () => {
  const payload = eventPayload();
  const eventId = "msg_route_replay_fixture";
  const first = await invoke(payload, { eventId, databaseBody: "true" });
  const replay = await invoke(payload, { eventId, databaseBody: "false" });

  assert.equal(first.response.status, 204);
  assert.equal(replay.response.status, 204);
  assert.equal(first.calls.length, 1);
  assert.equal(replay.calls.length, 1);
  assert.equal(JSON.parse(first.calls[0].body).p_event_id, eventId);
  assert.equal(JSON.parse(replay.calls[0].body).p_event_id, eventId);
});

test("returns 503 when provider-event persistence fails", async () => {
  const { response, calls } = await invoke(eventPayload(), {
    databaseStatus: 500,
    databaseBody: JSON.stringify({ message: "fixture database failure" }),
  });

  assert.equal(response.status, 503);
  assert.equal(calls.length, 1);
  assert.equal(await response.text(), "");
});

test("persists all seven lifecycle event types through one database RPC and never sends email", async () => {
  const types = [
    "email.sent",
    "email.delivered",
    "email.delivery_delayed",
    "email.bounced",
    "email.complained",
    "email.suppressed",
    "email.failed",
  ];

  for (const type of types) {
    const { response, calls } = await invoke(lifecyclePayload(type), {
      eventId: "msg_route_" + type.replaceAll(".", "_"),
    });
    assert.equal(response.status, 204, type);
    assert.equal(calls.length, 1, type);
    assert.ok(calls[0].url.endsWith("/rest/v1/rpc/record_delivery_provider_lifecycle_event"));
    assert.equal(calls[0].url.includes("/emails"), false);

    const body = JSON.parse(calls[0].body);
    assert.equal(body.p_event_type, type);
    assert.equal(body.p_provider_created_at, "2026-11-19T00:00:00.000Z");
    assert.equal(body.p_suppression_reason, type === "email.suppressed" ? "previous_bounce" : null);
    assert.match(body.p_payload_fingerprint, /^[a-f0-9]{64}$/);
    if (type === "email.failed") {
      assert.equal(body.p_failure_class, "quota_exceeded");
      assert.equal(body.p_failure_reason, undefined);
      assert.equal(calls[0].body.includes("reached_daily_quota"), false);
    }
  }
});


test("returns 503 for a persisted integrity anomaly instead of acknowledging it as a duplicate", async () => {
  const { response, calls } = await invoke(eventPayload(), {
    databaseBody: "null",
  });
  assert.equal(response.status, 503);
  assert.equal(calls.length, 1);
});
