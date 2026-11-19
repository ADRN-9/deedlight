import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const migration = read("supabase/migrations/202611190025_delivery_provider_webhooks.sql");
const aggregate = read("supabase/run_in_sql_editor_all.sql");
const route = read("app/api/webhooks/resend/route.ts");
const parser = read("lib/delivery/resend-webhook.ts");
const transport = read("lib/delivery/resend-transport.ts");
const scheduler = read("lib/delivery/scheduler.ts");
const tests = read("scripts/test-delivery-webhook.mjs");
const routeTests = read("scripts/test-delivery-webhook-route.mjs");
const transportTests = read("scripts/test-delivery-transport.mjs");
const databaseTests = read("scripts/test-delivery-provider-webhooks.sql");
const workflow = read(".github/workflows/pr-validation.yml");
const pkg = JSON.parse(read("package.json"));

assert(aggregate.includes(migration.trim()), "Migration 025 must be mirrored in the SQL Editor aggregate");
for (const name of [
  "delivery_provider_events",
  "delivery_provider_suppressions",
  "record_delivery_provider_event",
]) assert(migration.includes(name), `Missing provider webhook object: ${name}`);

assert(/alter table public\.delivery_provider_events enable row level security/i.test(migration));
assert(/alter table public\.delivery_provider_suppressions enable row level security/i.test(migration));
assert(/revoke all privileges on table public\.delivery_provider_events\s+from public, anon, authenticated, service_role/i.test(migration));
assert(/revoke all privileges on table public\.delivery_provider_suppressions\s+from public, anon, authenticated, service_role/i.test(migration));
assert(/revoke all privileges\s+on function public\.record_delivery_provider_event\(text, text, text, text, text\)\s+from public, anon, authenticated/i.test(migration));
assert(/grant execute\s+on function public\.record_delivery_provider_event\(text, text, text, text, text\)\s+to service_role/i.test(migration));
assert(migration.includes("on conflict (event_id) do nothing"), "Provider event IDs must deduplicate replays");
assert(migration.includes("email.bounced") && migration.includes("email.complained") && migration.includes("email.suppressed"));
assert(migration.includes("p_bounce_type <> 'Transient'"), "Unknown/permanent bounce events must fail closed");
assert(migration.includes("when excluded.reason = 'complaint' then 'complaint'"), "Complaints must outrank bounce reasons");

const record = migration.split("create or replace function public.record_delivery_provider_event")[1]
  .split("\n$$;")[0];
const transportGate = migration.split("create or replace function public.begin_delivery_transport")[1]
  .split("\n$$;")[0];
assert(record.includes("pg_advisory_xact_lock(20261119, hashtext(v_email))"));
assert(transportGate.includes("pg_advisory_xact_lock(20261119, hashtext(v_email))"),
  "Provider suppression and final transport must share the address lock");
assert(transportGate.includes("delivery_provider_suppressions"));
assert(migration.includes("delivery_provider_suppressions s"), "Both enqueue paths must exclude suppressed addresses");
assert(/revoke all privileges\s+on function public\.begin_delivery_transport\(uuid, uuid, text\)\s+from public, anon, authenticated/i.test(migration));
assert(/grant execute\s+on function public\.begin_delivery_transport\(uuid, uuid, text\)\s+to service_role/i.test(migration));

for (const value of [
  "svix-id",
  "svix-timestamp",
  "svix-signature",
  "request.body.getReader()",
  "MAX_BODY_BYTES",
  "verifyResendWebhookSignature",
  "record_delivery_provider_event",
  "RESEND_WEBHOOK_SECRET",
  "SUPABASE_SERVICE_ROLE_KEY",
]) assert(route.includes(value), `Webhook route missing security boundary: ${value}`);
assert(!route.includes("DELIVERY_ENABLED"), "Inbound suppression processing must remain available while outbound delivery is disabled");
assert(!route.includes("console.log") && !route.includes("console.error"), "Webhook route must not log recipient or provider payload data");
assert(!route.includes("NEXT_PUBLIC_RESEND_WEBHOOK_SECRET"));
assert(route.includes('if (!/^[0-9]+$/.test(contentLength))'),
  "Content-Length validation must accept decimal digits without regex escaping");
for (const value of [
  "accepts numeric Content-Length and a valid Svix signature",
  "accepts a valid Svix signature without Content-Length",
  "rejects malformed Content-Length before signature verification",
  "rejects oversized declared Content-Length before reading the body",
  "rejects oversized streamed request bodies without Content-Length",
  "rejects invalid signatures without invoking the database",
  "acknowledges replay attempts while preserving event-id idempotency",
  "returns 503 when provider-event persistence fails",
]) assert(routeTests.includes(value), `Missing HTTP route regression test: ${value}`);


for (const value of [
  "crypto.subtle.verify",
  "whsec_",
  "SIGNATURE_TOLERANCE_SECONDS = 300",
  "${id}.${timestamp}.${payload}",
  "application !== \"deedlight\"",
  "email.bounced",
  "email.complained",
  "email.suppressed",
  "Transient",
  "Unknown",
]) assert(parser.includes(value), `Webhook parser missing security behavior: ${value}`);

assert(transport.includes('tags: [{ name: "application", value: "deedlight" }]'));
assert(scheduler.includes("deliveryScheduleKind"));
assert(transportTests.includes("provider_http_408") || transportTests.includes("[408, 429, 500, 502, 503]"));
assert(transportTests.includes("provider_idempotency_conflict"));
assert(transportTests.includes("provider_idempotency_window_expired"));
assert(tests.includes("rejects stale and future timestamps"));
assert(tests.includes("modified payloads"));
assert(tests.includes("complaints and provider suppressions"));
assert(tests.includes("unknown bounce classification"));
assert(databaseTests.includes("Duplicate provider event ID was processed twice"));
assert(databaseTests.includes("Transient bounce incorrectly suppressed"));
assert(databaseTests.includes("Suppressed daily recipient reached transport"));
// The weekly fixture uses a complaint event; keep this assertion tied to that exact final-gate case.
assert(databaseTests.includes("Complained weekly recipient reached transport"),
  "A complained weekly recipient must be blocked at the final transport gate");
assert(databaseTests.includes("Complaint did not take precedence over a permanent bounce."),
  "Complaint suppression must retain precedence over bounce classification");
assert(pkg.scripts["test:delivery-webhook"] === "node --test scripts/test-delivery-webhook.mjs scripts/test-delivery-webhook-route.mjs");
assert(workflow.includes("node scripts/verify-delivery-provider-webhooks.mjs"));
assert(workflow.includes("npm run test:delivery-webhook"));
assert(workflow.includes("delivery_provider_webhook_database_behavior"));
assert(workflow.includes("scripts/test-delivery-provider-webhooks.sql"));
assert(workflow.includes('test -z "${RESEND_WEBHOOK_SECRET:-}"'));

console.log("Resend webhook authenticity, replay, suppression and privacy assertions: PASS");
