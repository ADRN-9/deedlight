import assert from "node:assert/strict";
import fs from "node:fs";
import { createHmac, createHash, randomBytes } from "node:crypto";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { resolve } from "node:path";

const nativeRequire = createRequire(resolve("package.json"));
const ts = nativeRequire("typescript");
const realVerifier = loadTs("lib/delivery/resend-webhook.ts");
const calls = [];
let rpcResult = { data: "recorded", error: null };
const stubSupabase = {
  createClient(url, key, options) {
    assert.equal(url, "https://c74-synthetic.supabase.co");
    assert.equal(key, "nonproduction-synthetic-service-role");
    assert.equal(options.auth.persistSession, false);
    return {
      async rpc(name, args) {
        assert.equal(name, "deedlight_record_resend_verified");
        calls.push(args);
        return rpcResult;
      },
    };
  },
};
const route = loadTs("app/api/webhooks/resend/route.ts", {
  "@supabase/supabase-js": stubSupabase,
  "@/lib/delivery/resend-webhook": realVerifier,
});

function loadTs(path, overrides = {}) {
  const src = fs.readFileSync(resolve(path), "utf8");
  const output = ts.transpileModule(src, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    fileName: path,
    reportDiagnostics: true,
  });
  if (output.diagnostics?.length) throw Error("TypeScript compilation diagnostics");
  const module = { exports: {} };
  const req = (name) => Object.hasOwn(overrides, name) ? overrides[name] : nativeRequire(name);
  new Function("module", "exports", "require", "process", output.outputText)(
    module, module.exports, req, process,
  );
  return module.exports;
}

const signingKey = randomBytes(32);
const secret = "whsec_" + signingKey.toString("base64");
const now = new Date();
const id = "msg_c74_routetest_valid001";
const event = (type = "email.delivered", data = {}) => ({
  type,
  created_at: now.toISOString(),
  data: {
    email_id: "provider-synthetic-route-001",
    to: ["c74-user@example.test"],
    ...data,
  },
});
function signed(type, data = {}, opt = {}) {
  const raw = opt.raw ?? JSON.stringify(event(type, data));
  const stamp = opt.stamp ?? String(Math.floor(Date.now() / 1000));
  const signedId = opt.id ?? id;
  const sig = "v1," + createHmac("sha256", signingKey)
    .update(signedId + "." + stamp + "." + raw)
    .digest("base64");
  return {
    body: opt.modified ?? raw,
    headers: {
      "content-type": "application/json",
      "svix-id": signedId,
      "svix-timestamp": stamp,
      "svix-signature": opt.signature ?? sig,
    },
  };
}

process.env.RESEND_WEBHOOK_SECRET = secret;
process.env.SUPABASE_URL = "https://c74-synthetic.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "nonproduction-synthetic-service-role";
const server = createServer(async (request, response) => {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  const data = Buffer.concat(chunks);
  const req = new Request("http://127.0.0.1/webhooks/resend", {
    method: "POST",
    body: data,
    headers: request.headers,
  });
  const result = await route.POST(req);
  response.writeHead(result.status, Object.fromEntries(result.headers.entries()));
  response.end(Buffer.from(await result.arrayBuffer()));
});
await new Promise((ok) => server.listen(0, "127.0.0.1", ok));
const address = server.address();
const url = "http://127.0.0.1:" + address.port + "/webhooks/resend";
let cases = 0;
async function expectCode(name, data, expected) {
  const result = await fetch(url, { method: "POST", headers: data.headers, body: data.body });
  const body = await result.text();
  assert.equal(result.status, expected, name + ": " + body);
  assert(!body.includes("c74-user@example.test"), "Recipient leaked");
  assert(!body.includes("nonproduction-synthetic-service-role"), "Credential leaked");
  cases++;
  console.log(name + ": HTTP " + expected + " PASS");
}
try {
  const valid = signed();
  await expectCode("raw-body signed Resend delivery", valid, 200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].p_recipient_email, "c74-user@example.test");
  assert.equal(calls[0].p_event_id, id);
  assert.equal(calls[0].p_payload_sha256, createHash("sha256").update(valid.body).digest("hex"));
  rpcResult = { data: "pending", error: null };
  await expectCode("out-of-order durable pending", signed(), 202);
  rpcResult = { data: "duplicate", error: null };
  await expectCode("idempotent signed replay", signed(), 200);
  rpcResult = { data: "quarantined", error: null };
  await expectCode("conflicting signed association quarantined", signed(), 200);
  rpcResult = { data: null, error: { code: "23505" } };
  await expectCode("database error requests provider retry", signed(), 503);
  rpcResult = { data: "recorded", error: null };
  const prior = calls.length;
  await expectCode("invalid signed payload rejected", signed("email.delivered", {}, {
    modified: JSON.stringify(event()) + " ",
  }), 400);
  await expectCode("invalid svix signature rejected", signed("email.sent", {}, {
    signature: "v1,invalid",
  }), 400);
  await expectCode("timestamp outside replay window rejected", signed("email.sent", {}, {
    stamp: String(Math.floor(Date.now() / 1000) - 1200),
  }), 400);
  await expectCode("unsupported event type denied", signed("contact.created"), 400);
  await expectCode("multiple recipient association denied", signed("email.delivered", {
    to: ["c74-user@example.test", "other@example.test"],
  }), 400);
  await expectCode("unclassified bounce denied", signed("email.bounced"), 400);
  await expectCode("oversized signed envelope denied", signed("email.sent", {}, {
    modified: " ".repeat(129 * 1024),
  }), 413);
  assert.equal(calls.length, prior, "Unauthenticated or invalid requests reached RPC");
  const oldKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  await expectCode("missing privileged configuration fails closed", signed(), 503);
  process.env.SUPABASE_SERVICE_ROLE_KEY = oldKey;
  console.log("C74 real localhost HTTP adapter + actual route handler + official Svix: " + cases + " PASS; no external provider calls");
} finally {
  await new Promise((ok) => server.close(ok));
}
