import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const migration = read("supabase/migrations/202611190025_delivery_provider_webhooks.sql");
const lifecycleMigration = read("supabase/migrations/202611190026_delivery_provider_lifecycle.sql");
const integrityMigration = read("supabase/migrations/202611200027_delivery_provider_integrity.sql");
const aggregate = read("supabase/run_in_sql_editor_all.sql");
const route = read("app/api/webhooks/resend/route.ts");
const parser = read("lib/delivery/resend-webhook.ts");
const transport = read("lib/delivery/resend-transport.ts");
const scheduler = read("lib/delivery/scheduler.ts");
const tests = read("scripts/test-delivery-webhook.mjs");
const routeTests = read("scripts/test-delivery-webhook-route.mjs");
const transportTests = read("scripts/test-delivery-transport.mjs");
const databaseTests = read("scripts/test-delivery-provider-webhooks.sql");
const concurrencyTests = read("scripts/test-delivery-provider-webhook-concurrency.sh");
const workflow = read(".github/workflows/pr-validation.yml");
const pkg = JSON.parse(read("package.json"));

assert(aggregate.includes(migration.trim()), "Migration 025 must remain mirrored in the SQL Editor aggregate");
assert(aggregate.includes(lifecycleMigration.trim()), "Migration 026 must be mirrored verbatim in the SQL Editor aggregate");
assert(aggregate.includes(integrityMigration.trim()), "Migration 027 must be mirrored verbatim in the SQL Editor aggregate");

for (const name of [
  "delivery_provider_events",
  "delivery_provider_suppressions",
  "record_delivery_provider_event",
]) assert(migration.includes(name), "Migration 025 provider suppression objects must remain intact");

const eventTypes = [
  "email.sent",
  "email.delivered",
  "email.delivery_delayed",
  "email.bounced",
  "email.complained",
  "email.suppressed",
  "email.failed",
];
for (const type of eventTypes) {
  assert(lifecycleMigration.includes(type), "Missing lifecycle event type: " + type);
  assert(parser.includes('"' + type + '"'), "Parser missing lifecycle event type: " + type);
}
assert(/add column provider_created_at timestamptz/i.test(lifecycleMigration));
assert(/add column failure_class text/i.test(lifecycleMigration));
assert(/create table public\.delivery_provider_lifecycle/i.test(lifecycleMigration));
assert(/create table public\.delivery_provider_integrity_anomalies/i.test(integrityMigration));
assert(integrityMigration.includes("duplicate_event_id_conflict"));
assert(integrityMigration.includes("contradictory_terminal_outcome"));
assert(integrityMigration.includes("p_payload_fingerprint"));
assert(integrityMigration.includes("v_existing.payload_fingerprint is not distinct from p_payload_fingerprint"));
assert(integrityMigration.includes("'previous_complaint' then 'complaint'"));
assert(integrityMigration.includes("'previous_bounce' then 'permanent_bounce'"));
assert(/grant execute[\s\S]*record_delivery_provider_lifecycle_event\(text, text, text, text, timestamptz, text, text, text, text\)[\s\S]*to service_role/i.test(integrityMigration));
assert(!/raw_payload|diagnostic_code|diagnostic_message|failure_reason|provider_error/i.test(integrityMigration));
assert(/received_at timestamptz not null/i.test(lifecycleMigration));
assert(/revoke all privileges on table public\.delivery_provider_lifecycle\s+from public, anon, authenticated, service_role/i.test(lifecycleMigration));
assert(/alter table public\.delivery_provider_lifecycle enable row level security/i.test(lifecycleMigration));
assert(/grant execute\s+on function public\.record_delivery_provider_lifecycle_event[\s\S]*?to service_role/i.test(lifecycleMigration));
assert(/revoke all privileges\s+on function public\.record_delivery_provider_lifecycle_event[\s\S]*?from public, anon, authenticated/i.test(lifecycleMigration));
assert(lifecycleMigration.includes("pg_advisory_xact_lock(20261119, hashtext(v_email))"));
assert(lifecycleMigration.includes("pg_advisory_xact_lock(20261126, hashtext(p_provider_email_id))"));
assert(lifecycleMigration.includes("on conflict (event_id) do nothing"));
assert(lifecycleMigration.includes("create or replace function public.record_delivery_provider_event"));
assert(lifecycleMigration.includes("clock_timestamp()"));
assert(lifecycleMigration.includes("when excluded.reason = 'complaint' then 'complaint'"));
assert(lifecycleMigration.includes("greatest("));
assert(lifecycleMigration.includes("excluded.status_rank > delivery_provider_lifecycle.status_rank"));
assert(lifecycleMigration.includes("(excluded.provider_created_at, excluded.event_id)"));
assert(!/raw_payload|diagnostic_code|diagnostic_message|failure_reason|provider_error/i.test(lifecycleMigration));

const lifecycleFunction = lifecycleMigration
  .split("create or replace function public.record_delivery_provider_lifecycle_event")[1]
  .split("\n$$;")[0];
assert(!/delivery_ledger|enqueue_|retry_delivery_job|claim_delivery_jobs|begin_delivery_transport|resend\.com|send_email/i.test(lifecycleFunction),
  "Lifecycle intake must never mutate queue/claim/retry state or send mail");

for (const value of [
  "svix-id",
  "svix-timestamp",
  "svix-signature",
  "request.body.getReader()",
  "MAX_BODY_BYTES",
  "verifyResendWebhookSignature",
  "record_delivery_provider_lifecycle_event",
  "RESEND_WEBHOOK_SECRET",
  "SUPABASE_SERVICE_ROLE_KEY",
]) assert(route.includes(value), "Webhook route missing security boundary: " + value);
assert(!route.includes("DELIVERY_ENABLED"), "Inbound lifecycle intake must remain available while outbound delivery is disabled");
assert(!route.includes("console.log") && !route.includes("console.error"), "Webhook route must not log recipient or provider payload data");
assert(!route.includes("NEXT_PUBLIC_RESEND_WEBHOOK_SECRET"));
assert(route.includes('if (!/^[0-9]+$/.test(contentLength))'));
assert(route.includes("p_provider_created_at"));
assert(route.includes("p_failure_class"));
assert(route.includes("p_suppression_reason"));
assert(route.includes("p_payload_fingerprint"));
assert(route.includes("data !== true && data !== false"));
assert(parser.includes("fingerprintResendWebhookPayload"));
assert(parser.includes("data.created_at"));
assert(parser.includes("data.from"));
assert(parser.includes("data.subject"));

for (const value of [
  "accepts numeric Content-Length and a valid Svix signature",
  "accepts a valid Svix signature without Content-Length",
  "rejects malformed Content-Length before signature verification",
  "rejects oversized declared Content-Length before reading the body",
  "rejects oversized streamed request bodies without Content-Length",
  "rejects invalid signatures without invoking the database",
  "acknowledges replay attempts while preserving event-id idempotency",
  "returns 503 when provider-event persistence fails",
  "returns 503 for a persisted integrity anomaly",
  "persists all seven lifecycle event types through one database RPC and never sends email",
]) assert(routeTests.includes(value), "Missing HTTP route regression test: " + value);

for (const value of [
  "crypto.subtle.verify",
  "whsec_",
  "SIGNATURE_TOLERANCE_SECONDS = 300",
  "email.sent",
  "email.delivered",
  "email.delivery_delayed",
  "email.bounced",
  "email.complained",
  "email.suppressed",
  "email.failed",
  "providerCreatedAt",
  "normalizeFailureClass",
  "suppressionReason",
  "previous_bounce",
  "previous_complaint",
  "crypto.subtle.digest",
  "quota_exceeded",
]) assert(parser.includes(value), "Webhook parser missing behavior: " + value);

assert(transport.includes('tags: [{ name: "application", value: "deedlight" }]'));
assert(scheduler.includes("deliveryScheduleKind"));
assert(transportTests.includes("provider_http_408") || transportTests.includes("[408, 429, 500, 502, 503]"));
assert(transportTests.includes("provider_idempotency_conflict"));
assert(transportTests.includes("provider_idempotency_window_expired"));
assert(tests.includes("provider-shaped fixtures for all seven lifecycle events"));
assert(tests.includes("maps both Resend suppression reasons"));
assert(tests.includes("rejects missing or malformed bounce and suppression objects"));
assert(tests.includes("computes a stable SHA-256 fingerprint"));
assert(tests.includes("rejects missing common event data"));
assert(tests.includes("normalizes failed-event reasons without retaining provider diagnostics"));
assert(tests.includes("rejects missing or malformed provider event timestamps"));
assert(databaseTests.includes("Conflicting duplicate event ID was not recorded as an integrity anomaly."));
assert(databaseTests.includes("Exact duplicate provider event was not a successful no-op."));
assert(databaseTests.includes("Payload fingerprint conflict was not recorded as an integrity anomaly."));
assert(databaseTests.includes("Delivered then bounced was not flagged."));
assert(databaseTests.includes("Bounced then delivered was not flagged."));
assert(databaseTests.includes("Resend nested suppression reasons were not mapped"));
assert(databaseTests.includes("Transient bounce incorrectly suppressed"));
assert(databaseTests.includes("Suppressed daily recipient reached transport"));
assert(databaseTests.includes("Complained weekly recipient reached transport"));
assert(databaseTests.includes("Complaint did not take precedence over a permanent bounce."));
assert(databaseTests.includes("Out-of-order event regressed delivered lifecycle evidence."));
assert(databaseTests.includes("Lifecycle webhook mutated delivery queue, claim or retry state."));
assert(databaseTests.includes("Provider webhook and integrity tables are directly readable."));
assert(concurrencyTests.includes("Concurrent conflicting duplicate integrity anomaly"));
assert(concurrencyTests.includes("Concurrent contradictory terminal outcomes in both arrival orders"));
assert(concurrencyTests.includes("Concurrent out-of-order lifecycle monotonicity"));
assert(concurrencyTests.includes("Shared suppression-first transport authorization"));
assert(concurrencyTests.includes("Shared transport-first suppression ordering"));
assert(pkg.scripts["test:delivery-webhook"] === "node --test scripts/test-delivery-webhook.mjs scripts/test-delivery-webhook-route.mjs");
assert(workflow.includes("node scripts/verify-delivery-provider-webhooks.mjs"));
assert(workflow.includes("npm run test:delivery-webhook"));
assert(workflow.includes("delivery_provider_webhook_database_behavior"));
assert(workflow.includes("scripts/test-delivery-provider-webhooks.sql"));
assert(workflow.includes("scripts/test-delivery-provider-webhook-concurrency.sh"));
assert(workflow.includes('test -z "' + "$" + '{RESEND_WEBHOOK_SECRET:-}"'));

console.log("Resend webhook authenticity, seven-event lifecycle, ordering, suppression and privacy assertions: PASS");
