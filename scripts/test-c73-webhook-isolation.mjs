import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

test("exported Resend POST denies network before imports and never leaks recipient or payload canaries", () => {
  const preload = `
import { syncBuiltinESMExports } from "node:module";
import net from "node:net";
import tls from "node:tls";
import http from "node:http";
import https from "node:https";
import dgram from "node:dgram";
import http2 from "node:http2";
import dns from "node:dns";

globalThis.__networkAttempts = 0;
const denyNetwork = () => {
  globalThis.__networkAttempts += 1;
  throw new Error("Outbound network is disabled in webhook isolation test");
};
globalThis.fetch = denyNetwork;
for (const name of ["connect", "createConnection"]) net[name] = denyNetwork;
net.Socket.prototype.connect = denyNetwork;
tls.connect = denyNetwork;
for (const name of ["request", "get"]) {
  http[name] = denyNetwork;
  https[name] = denyNetwork;
}
dgram.createSocket = denyNetwork;
http2.connect = denyNetwork;
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
  const OriginalWebSocket = globalThis.WebSocket;
  globalThis.WebSocket = class extends OriginalWebSocket {
    constructor(...args) { denyNetwork(...args); }
  };
}
syncBuiltinESMExports();
`;
  const child = `
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const capturedLogs = [];
for (const name of ["debug", "info", "log", "warn", "error"]) {
  console[name] = (...args) => capturedLogs.push(args.map(String).join(" "));
}

const recipientCanary = "deedlight-recipient-canary-7f31@example.test";
const payloadCanary = "deedlight-raw-payload-canary-92bd";
const rawPayload = JSON.stringify({
  type: "email.delivered",
  created_at: new Date().toISOString(),
  data: { email_id: "synthetic-email-id", to: [recipientCanary], marker: payloadCanary }
});

process.env.RESEND_WEBHOOK_SECRET = "whsec_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
process.env.SUPABASE_SERVICE_ROLE_KEY = "synthetic-service-role-key";
const { POST } = await import(pathToFileURL(resolve("app/api/webhooks/resend/route.ts")).href);

const invalidStatuses = [];
for (const destination of [
  "https://anotherproject.supabase.co",
  "https://xaipiovflxomcbfwtwmu.supabase.co:8443",
  "https://user:password@xaipiovflxomcbfwtwmu.supabase.co",
  "https://xaipiovflxomcbfwtwmu.supabase.co/rest/v1",
  "not a URL"
]) {
  process.env.SUPABASE_URL = destination;
  const response = await POST(new Request("https://deedlight.test/api/webhooks/resend", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: rawPayload
  }));
  invalidStatuses.push(response.status);
}

process.env.SUPABASE_URL = "https://xaipiovflxomcbfwtwmu.supabase.co";
const privacyResponse = await POST(new Request("https://deedlight.test/api/webhooks/resend", {
  method: "POST",
  headers: {
    "content-type": "application/json",
    "svix-id": "msg_C73PrivacyCanary001",
    "svix-timestamp": String(Math.floor(Date.now() / 1000)),
    "svix-signature": "v1,invalid"
  },
  body: rawPayload
}));
const privacyText = await privacyResponse.text();
const logsText = capturedLogs.join("\\n");
const sensitiveOutput = [privacyText, logsText].join("\\n");
if (sensitiveOutput.includes(recipientCanary) || sensitiveOutput.includes(payloadCanary)
  || sensitiveOutput.includes(rawPayload)) {
  throw new Error("Webhook output exposed a synthetic privacy canary");
}
if (globalThis.__networkAttempts !== 0) {
  throw new Error("Webhook attempted outbound network activity");
}
if (invalidStatuses.some((status) => status !== 503) || privacyResponse.status !== 400) {
  throw new Error("Unexpected webhook response status");
}
process.stdout.write(JSON.stringify({
  invalidStatuses,
  privacyStatus: privacyResponse.status,
  networkAttempts: globalThis.__networkAttempts,
  capturedLogCount: capturedLogs.length,
  canariesAbsent: true
}));
`;
  const preloadUrl = `data:text/javascript,${encodeURIComponent(preload)}`;
  const result = spawnSync(process.execPath, [
    "--import", preloadUrl,
    "--input-type=module",
    "-e", child
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
  assert.doesNotMatch(result.stdout, /deedlight-recipient-canary|deedlight-raw-payload-canary/);
  const report = JSON.parse(result.stdout);
  assert.deepEqual(report.invalidStatuses, [503, 503, 503, 503, 503]);
  assert.equal(report.privacyStatus, 400);
  assert.equal(report.networkAttempts, 0);
  assert.equal(report.canariesAbsent, true);
});
