import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

test("exported POST instruments all privileged boundaries for every invalid destination", () => {
  const child = `
import { mock } from "node:test";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { syncBuiltinESMExports } from "node:module";
import net from "node:net";
import tls from "node:tls";
import http from "node:http";
import https from "node:https";
import http2 from "node:http2";
import dgram from "node:dgram";
import dns from "node:dns";

const counts = { clients: 0, verifier: 0, database: 0, outbound: 0 };
const denyNetwork = () => {
  counts.outbound += 1;
  throw new Error("Network access denied by C516 webhook test");
};
globalThis.fetch = denyNetwork;
for (const name of ["connect", "createConnection"]) net[name] = denyNetwork;
net.Socket.prototype.connect = denyNetwork;
tls.connect = denyNetwork;
for (const name of ["request", "get"]) {
  http[name] = denyNetwork;
  https[name] = denyNetwork;
}
http2.connect = denyNetwork;
dgram.createSocket = denyNetwork;
for (const name of [
  "lookup", "lookupService", "resolve", "resolve4", "resolve6", "resolveAny",
  "resolveCname", "resolveMx", "resolveNaptr", "resolveNs", "resolvePtr",
  "resolveSoa", "resolveSrv", "resolveTxt", "reverse"
]) {
  if (typeof dns[name] === "function") dns[name] = denyNetwork;
}
for (const name of [
  "lookup", "lookupService", "resolve", "resolve4", "resolve6", "resolveAny",
  "resolveCname", "resolveMx", "resolveNaptr", "resolveNs", "resolvePtr",
  "resolveSoa", "resolveSrv", "resolveTxt", "reverse"
]) {
  if (typeof dns.promises[name] === "function") {
    dns.promises[name] = async (...args) => denyNetwork(...args);
  }
}
if (typeof globalThis.WebSocket === "function") {
  globalThis.WebSocket = class extends globalThis.WebSocket {
    constructor(...args) { denyNetwork(...args); }
  };
}
syncBuiltinESMExports();

const InvalidResendWebhook = class InvalidResendWebhook extends Error {};
const verifierModule = pathToFileURL(resolve("lib/delivery/resend-webhook.ts")).href;
const supabaseModule = "@supabase/supabase-js";
mock.module(verifierModule, {
  namedExports: {
    InvalidResendWebhook,
    verifyResendDeliveryWebhook: async () => {
      counts.verifier += 1;
      return {
        kind: "delivery",
        eventId: "msg_C516Synthetic001",
        providerEmailId: "synthetic-provider-id",
        recipientEmail: "recipient-canary@example.test",
        eventType: "email.delivered",
        eventAt: new Date().toISOString(),
        payloadSha256: "a".repeat(64),
        suppressionReason: null,
        bounceType: null
      };
    }
  }
});
mock.module(supabaseModule, {
  namedExports: {
    createClient: () => {
      counts.clients += 1;
      return {
        rpc: async () => {
          counts.database += 1;
          return { data: "recorded", error: null };
        }
      };
    }
  }
});

process.env.RESEND_WEBHOOK_SECRET = "whsec_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
process.env.SUPABASE_SERVICE_ROLE_KEY = "synthetic-service-role-key";
const { POST } = await import(pathToFileURL(resolve("app/api/webhooks/resend/route.ts")).href);

process.env.SUPABASE_URL = "https://xaipiovflxomcbfwtwmu.supabase.co";
const validResponse = await POST(new Request("https://deedlight.test/api/webhooks/resend", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: "{}"
}));
if (validResponse.status !== 200
  || counts.clients !== 1
  || counts.verifier !== 1
  || counts.database !== 1) {
  throw new Error("Exported POST dependency mocks were not exercised by the valid control request");
}
counts.clients = 0;
counts.verifier = 0;
counts.database = 0;
counts.outbound = 0;

const destinations = [
  "https://anotherproject.supabase.co",
  "https://xaipiovflxomcbfwtwmu.supabase.co.attacker.example",
  "https://xaipiovflxomcbfwtwmu.supabase.co:443",
  "https://xaipiovflxomcbfwtwmu.supabase.co:8443",
  "https://user:password@xaipiovflxomcbfwtwmu.supabase.co",
  "https://xaipiovflxomcbfwtwmu.supabase.co/rest/v1",
  "https://xaipiovflxomcbfwtwmu.supabase.co?target=other",
  "https://xaipiovflxomcbfwtwmu.supabase.co#fragment",
  " https://xaipiovflxomcbfwtwmu.supabase.co",
  "not a URL",
  "https://[malformed"
];
const statuses = [];
for (const destination of destinations) {
  process.env.SUPABASE_URL = destination;
  const response = await POST(new Request("https://deedlight.test/api/webhooks/resend", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ type: "email.delivered", data: { to: ["recipient-canary@example.test"] } })
  }));
  statuses.push(response.status);
}
process.stdout.write(JSON.stringify({ statuses, counts, validControlStatus: validResponse.status }));
`;
  const result = spawnSync(process.execPath, [
    "--experimental-test-module-mocks",
    "--input-type=module",
    "-e",
    child
  ], {
    cwd: process.cwd(),
    encoding: "utf8",
    timeout: 20_000,
    env: {
      ...process.env,
      DELIVERY_ENABLED: "false",
      RESEND_WEBHOOK_SECRET: "",
      SUPABASE_SERVICE_ROLE_KEY: "",
      SUPABASE_URL: ""
    }
  });

  assert.equal(result.error, undefined, result.error?.message);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(result.stderr, "");
  const report = JSON.parse(result.stdout);
  assert.equal(report.validControlStatus, 200);
  assert.deepEqual(report.statuses, Array(11).fill(503));
  assert.deepEqual(report.counts, {
    clients: 0,
    verifier: 0,
    database: 0,
    outbound: 0
  });
});
