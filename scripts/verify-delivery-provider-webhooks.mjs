import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const migration = read("supabase/migrations/202611190025_delivery_provider_webhooks.sql");
const lifecycleMigration = read("supabase/migrations/202611190026_delivery_provider_lifecycle.sql");
const integrityMigration = read("supabase/migrations/202611200027_delivery_provider_integrity.sql");
const legacyGuardMigration = read("supabase/migrations/202611210029_delivery_legacy_replay_guard.sql");
const suppressionSyncMigration = read("supabase/migrations/202611220032_resend_suppression_list_sync.sql");
const crossStreamMigration = read("supabase/migrations/202611220033_delivery_cross_stream_suppression_order.sql");
const leaseMigration = read("supabase/migrations/202611210028_delivery_claim_lock_expiry.sql");
const idempotencyMigration = read("supabase/migrations/202611210030_delivery_idempotency_receipt_guard.sql");
const suppressionTests = read("scripts/test-delivery-provider-suppressions.sql");
const migrationOrderTest = read("scripts/test-delivery-migration-order.sh");
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
const migration027Body = integrityMigration
  .split("create or replace function public.record_delivery_provider_lifecycle_event(")[1]
  ?.split("as $$")[1]
  ?.split("$$;")[0];
assert(migration027Body, "Migration 027 canonical lifecycle implementation source must exist");
const migration027Sha256 = createHash("sha256").update(migration027Body, "utf8").digest("hex");
assert.equal(
  migration027Sha256,
  "8dbfc65b93677f9928114561d372dad69f16c9c746dadf80551c662161ba3ed5",
  "Migration 027 implementation source fingerprint changed; review migration 029 identity pin",
);
assert(legacyGuardMigration.includes(migration027Sha256), "Migration 029 must pin the exact migration-027 source fingerprint");
assert(legacyGuardMigration.includes("p.prosecdef") && legacyGuardMigration.includes("p.proconfig"));
assert(legacyGuardMigration.includes("deedlight:027:provider-lifecycle-integrity-and-suppression-reasons:v1"));
assert(legacyGuardMigration.includes("pg_catalog.pg_extension") && legacyGuardMigration.includes("''sha256''"));
assert(databaseTests.includes("create extension if not exists pgcrypto"), "Migration 029 CI fixture must provide pgcrypto");
assert(migrationOrderTest.includes("C226 deliberate source drift"));
assert(migrationOrderTest.includes("Migration 029 source identity drift rejection, atomic rollback and legacy replay compatibility: PASS"));
assert(aggregate.includes(legacyGuardMigration.trim()), "Migration 029 must be mirrored verbatim in the SQL Editor aggregate");
assert(aggregate.includes(suppressionSyncMigration.trim()), "Migration 032 must be mirrored verbatim in the SQL Editor aggregate");
assert(migrationOrderTest.includes("202611220032_resend_suppression_list_sync.sql"));
assert(migrationOrderTest.includes("scripts/test-delivery-provider-suppressions.sql"));
assert(databaseTests.includes("202611220032_resend_suppression_list_sync.sql"));
assert(databaseTests.includes("test-delivery-provider-suppressions.sql"));
assert(/alter function public\.record_delivery_provider_lifecycle_event\([\s\S]*?rename to _record_delivery_provider_lifecycle_event_fingerprinted_impl/i.test(legacyGuardMigration));
for (const signature of [
  "record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)",
  "record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)",
  "record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)",
  "record_delivery_provider_event(text,text,text,text,text)",
]) {
  assert(legacyGuardMigration.includes("to_regprocedure('public." + signature + "') is null"),
    "Migration 029 must verify every canonical and legacy RPC overload: " + signature);
}
assert(/create or replace function public\.record_delivery_provider_lifecycle_event\([\s\S]*?p_payload_fingerprint text[\s\S]*?if p_payload_fingerprint is null[\s\S]*?pg_advisory_xact_lock\(20261119, hashtext\(v_email\)\)[\s\S]*?pg_advisory_xact_lock\(20261126, hashtext\(p_provider_email_id\)\)[\s\S]*?select e\.\* into v_existing[\s\S]*?for update[\s\S]*?if not found[\s\S]*?errcode = '42501'[\s\S]*?_record_delivery_provider_lifecycle_event_fingerprinted_impl/i.test(legacyGuardMigration),
  "New events must require a fingerprint and legacy replays must preserve canonical advisory-lock ordering.");
assert(/revoke all privileges[\s\S]*?_record_delivery_provider_lifecycle_event_fingerprinted_impl[\s\S]*?from public, anon, authenticated, service_role/i.test(legacyGuardMigration),
  "The renamed lifecycle implementation must not be directly executable by service_role or browser roles.");
const compactLegacyGuard = legacyGuardMigration.replace(/\s+/g, "");
for (const signature of [
  "record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text)",
  "record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)",
  "record_delivery_provider_event(text, text, text, text, text)",
]) {
  const compactSignature = signature.replace(/\s+/g, "");
  assert(compactLegacyGuard.includes("revokeallprivilegesonfunctionpublic." + compactSignature),
    "Migration 029 must explicitly revoke browser execution for legacy overload: " + signature);
  assert(compactLegacyGuard.includes("grantexecuteonfunctionpublic." + compactSignature),
    "Migration 029 must retain service_role execution for legacy overload: " + signature);
}

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
const suppressionEventTypes = ["suppression.added", "suppression.removed"];
for (const type of eventTypes) {
  assert(lifecycleMigration.includes(type), "Missing lifecycle event type: " + type);
  assert(parser.includes('"' + type + '"'), "Parser missing lifecycle event type: " + type);
}
for (const type of suppressionEventTypes) {
  assert(suppressionSyncMigration.includes(type), "Migration 032 missing suppression event type: " + type);
  assert(parser.includes('"' + type + '"'), "Parser missing suppression event type: " + type);
}
assert(/provider_email_id drop not null/i.test(suppressionSyncMigration));
assert(/provider_suppression_id text/i.test(suppressionSyncMigration));
assert(/create table public\.delivery_provider_suppression_state/i.test(suppressionSyncMigration));
assert(/create function public\.record_delivery_provider_suppression_event/i.test(suppressionSyncMigration));
assert(suppressionSyncMigration.includes("pg_advisory_xact_lock(20261119, hashtext(v_email))"));
assert(suppressionSyncMigration.includes("pg_advisory_xact_lock(20261127, hashtext(p_provider_suppression_id))"));
assert(suppressionSyncMigration.includes("e.provider_suppression_id = p_provider_suppression_id"));
assert(suppressionSyncMigration.includes("e.recipient_email <> v_email"));
assert(suppressionSyncMigration.includes("p_provider_created_at > v_state.provider_created_at"));
assert(suppressionSyncMigration.includes("suppression_event_timestamp_conflict"));
assert(suppressionSyncMigration.includes("is_active = true"));
assert(suppressionSyncMigration.includes("added.event_type = 'suppression.added'"));
assert(suppressionSyncMigration.includes("added.suppression_origin = 'manual'"));
assert(suppressionSyncMigration.includes("reason = 'provider_suppressed'"));
assert(suppressionSyncMigration.includes("p_suppression_origin in ('bounce', 'complaint')"));
assert(suppressionSyncMigration.includes("when v_state.origin = 'complaint' then v_state.event_id"));
assert(/add column provider_created_at timestamptz/i.test(lifecycleMigration));
assert(/add column failure_class text/i.test(lifecycleMigration));
assert(/create table public\.delivery_provider_lifecycle/i.test(lifecycleMigration));
assert(/create table public\.delivery_provider_integrity_anomalies/i.test(integrityMigration));
assert(integrityMigration.includes("duplicate_event_id_conflict"));
assert(integrityMigration.includes("contradictory_terminal_outcome"));
assert(integrityMigration.includes("p_payload_fingerprint"));
assert(integrityMigration.includes("v_existing.payload_fingerprint is null"));
assert(integrityMigration.includes("p_payload_fingerprint is not null"));
assert(integrityMigration.includes("v_existing.payload_fingerprint = p_payload_fingerprint"));
assert(!/v_existing\.payload_fingerprint is null\s+or\s+p_payload_fingerprint is null/i.test(integrityMigration),
  "A NULL incoming fingerprint must not wildcard-match a stored fingerprint.");
assert(integrityMigration.includes("v_existing.suppression_reason is null"));
assert(integrityMigration.includes("p_suppression_reason is null"));
assert(integrityMigration.includes("v_existing.suppression_reason = p_suppression_reason"));
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
assert(route.includes("persisted.data !== true && persisted.data !== false"));
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
  "suppression.added",
  "suppression.removed",
  "providerSuppressionId",
  "suppressionOrigin",
  "suppressionSourceId",
  "suppressionCreatedAt",
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
assert(transportTests.includes("database-authoritative idempotency expiry"));
assert(transportTests.includes("final provider gate cancels when consent is revoked"));
assert(transportTests.includes("final provider gate fails closed for cancelled and expired authorization"));
assert(tests.includes("provider-shaped fixtures for all seven lifecycle events"));
assert(tests.includes("maps both Resend suppression reasons"));
assert(tests.includes("accepts Resend's documented bounce shape without diagnosticCode"));
assert(tests.includes("unknown bounce type and subtype classifications normalize to Unknown"));
assert(tests.includes("unknown suppression classifications normalize to generic provider suppression"));
assert(tests.includes("rejects malformed diagnostic codes even for unknown provider classifications"));
assert(tests.includes("accepts Resend's documented suppression shape without optional diagnostics or reason"));
assert(routeTests.includes("accepts Resend's documented bounce shape without diagnosticCode"));
assert(routeTests.includes("accepts Resend's documented suppression shape without optional diagnostics or reason"));
assert(route.includes("record_delivery_provider_suppression_event"));
assert(route.includes("p_provider_suppression_id"));
assert(route.includes("p_suppression_origin"));
assert(routeTests.includes("persists suppression.added and suppression.removed through the dedicated private RPC"));
assert(routeTests.includes("rejects malformed signed suppression events before database persistence"));
assert(routeTests.includes("returns 503 when suppression event persistence reports an integrity conflict"));
assert(parser.includes('"provider_suppressed"'));
assert(parser.includes('"Suppressed"'));
assert(tests.includes("rejects missing or malformed bounce and suppression objects"));
assert(tests.includes("computes a stable SHA-256 fingerprint"));
assert(tests.includes("rejects missing common event data"));
assert(tests.includes("parses official suppression.added and suppression.removed payloads without email tags"));
assert(tests.includes("accepts documented suppression origins and nullable source IDs"));
assert(tests.includes("rejects malformed suppression-list schemas and timestamps"));
assert(tests.includes("ignores unknown provider event types without accepting them as suppression events"));
assert(tests.includes("normalizes failed-event reasons without retaining provider diagnostics"));
assert(tests.includes("rejects missing or malformed provider event timestamps"));
assert(databaseTests.includes("Conflicting duplicate event ID was not recorded as an integrity anomaly."));
assert(databaseTests.includes("Pre-026 historical event replay was not a compatible no-op."));
assert(databaseTests.includes("Pre-027 historical event replay was not a compatible no-op."));
assert(databaseTests.includes("Historical NULL fingerprint was not compatible through the eight-argument RPC."));
assert(databaseTests.includes("Historical NULL fingerprint was not compatible through the seven-argument RPC."));
assert(databaseTests.includes("Historical NULL fingerprint was not compatible through the five-argument RPC."));
assert(databaseTests.includes("Eight-argument legacy RPC unexpectedly inserted a new event."));
assert(databaseTests.includes("Seven-argument legacy RPC unexpectedly inserted a new event."));
assert(databaseTests.includes("Five-argument legacy RPC unexpectedly inserted a new event."));
assert(databaseTests.includes("Canonical RPC unexpectedly inserted a new event without a fingerprint."));
assert(databaseTests.includes("Legacy fingerprint conflicts mutated or removed existing event records."));
assert(databaseTests.includes("Five-argument legacy fingerprint conflict mutated existing suppression state."));
assert(databaseTests.includes("e.payload_fingerprint is distinct from expected.payload_fingerprint"));
assert(databaseTests.includes("a.grantee = 0 and a.privilege_type = 'EXECUTE'"));
assert(databaseTests.includes("Private provider lifecycle implementation ACLs regressed."));
assert(databaseTests.includes("Canonical provider lifecycle RPC ACLs regressed."));
const privateImplementationSignature = "public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)";
const canonicalLifecycleSignature = "public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)";
for (const role of ["anon", "authenticated", "service_role"]) {
  assert(databaseTests.includes("has_function_privilege('" + role + "',\n       '" + privateImplementationSignature + "','EXECUTE')"),
    "SQL regression suite must explicitly deny private implementation execution to " + role + ".");
}
for (const role of ["anon", "authenticated"]) {
  assert(databaseTests.includes("has_function_privilege('" + role + "',\n       '" + canonicalLifecycleSignature + "','EXECUTE')"),
    "SQL regression suite must preserve canonical RPC denial for " + role + ".");
}
assert(databaseTests.includes("not has_function_privilege('service_role',\n       '" + canonicalLifecycleSignature + "','EXECUTE')"),
  "SQL regression suite must preserve canonical RPC service_role execution.");
assert(/p\.oid = to_regprocedure\('public\._record_delivery_provider_lifecycle_event_fingerprinted_impl\([^)]+\)'\)\s+and a\.grantee = 0 and a\.privilege_type = 'EXECUTE'/s.test(databaseTests),
  "SQL regression suite must deny PUBLIC direct execution of the private implementation.");
assert(/p\.oid = to_regprocedure\('public\.record_delivery_provider_lifecycle_event\([^)]+\)'\)\s+and a\.grantee = 0 and a\.privilege_type = 'EXECUTE'/s.test(databaseTests),
  "SQL regression suite must deny PUBLIC direct execution of the canonical RPC.");
assert(databaseTests.includes("Eight-argument legacy RPC bypassed a stored provider payload fingerprint."));
assert(databaseTests.includes("Seven-argument legacy RPC bypassed a stored provider payload fingerprint."));
assert(databaseTests.includes("Five-argument legacy provider-event RPC bypassed a stored provider payload fingerprint."));
assert(databaseTests.includes("Conflicting duplicate mutated original event history or suppression row."));
assert(databaseTests.includes("Exact duplicate provider event was not a successful no-op."));
assert(databaseTests.includes("Payload fingerprint conflict was not recorded as an integrity anomaly."));
assert(databaseTests.includes("Delivered then bounced was not flagged."));
assert(databaseTests.includes("Bounced then delivered was not flagged."));
assert(databaseTests.includes("Resend nested suppression reasons were not mapped"));
assert(databaseTests.includes("Transient bounce incorrectly suppressed"));
assert(databaseTests.includes("Suppressed daily recipient reached transport"));
assert(databaseTests.includes("Complained weekly recipient reached transport"));
assert(databaseTests.includes("Complaint did not take precedence over a permanent bounce."));
for (const value of [
  "Manual provider suppression was not cleared after its matching removal.",
  "suppression.removed cleared a complaint-origin hold.",
  "suppression.removed cleared a bounce-origin hold.",
  "Manual suppression removal cleared an independent complaint.",
  "Manual suppression removal cleared an independent permanent bounce.",
  "A removal without its matching add cleared an existing provider suppression.",
  "Older suppression.added regressed a later removal.",
  "Older suppression.removed regressed a later addition.",
  "Equal-time contradictory suppression events did not fail closed.",
  "Cross-recipient suppression ID reuse was accepted.",
]) assert(suppressionTests.includes(value), "Missing suppression-list SQL behavior assertion: " + value);
assert(suppressionTests.includes("'suppression_add_remove_manual_sync','pass'"));
assert(suppressionTests.includes("'cross_recipient_suppression_id_binding','pass'"));
assert(databaseTests.includes("Out-of-order event regressed delivered lifecycle evidence."));
assert(databaseTests.includes("Lifecycle webhook mutated delivery queue, claim or retry state."));
assert(databaseTests.includes("Provider webhook and integrity tables are directly readable."));
assert(concurrencyTests.includes("Concurrent exact duplicate event"));
assert(concurrencyTests.includes("Concurrent conflicting duplicate integrity anomaly"));
assert(concurrencyTests.includes("Concurrent cross-recipient provider email ID collision"));
assert(concurrencyTests.includes("CROSS_RECIPIENT_PROVIDER_ID_LOCK_HELD"));
assert(concurrencyTests.includes("Provider email correlation does not match."));
for (const value of [
  "collision_event_count",
  "collision_first_event",
  "collision_second_event",
  "collision_lifecycle",
  "collision_suppression",
  "collision_anomaly",
]) assert(concurrencyTests.includes(value), "Missing cross-recipient collision integrity assertion: " + value);
assert(integrityMigration.includes("pg_advisory_xact_lock(20261126, hashtext(p_provider_email_id))"));
assert(integrityMigration.includes("e.provider_email_id = p_provider_email_id"));
assert(integrityMigration.includes("e.recipient_email <> v_email"));
assert(concurrencyTests.includes("Concurrent historical event without fingerprint"));
assert(concurrencyTests.includes("Concurrent previous complaint/bounce suppression precedence"));
assert(concurrencyTests.includes("--pset=null=__NULL__"));
assert(concurrencyTests.includes("--quiet --no-align --tuples-only"));
assert(!concurrencyTests.includes("-Atc"), "Concurrency scalar assertions must not include psql command status output");
assert(concurrencyTests.includes("Concurrent contradictory terminal outcomes in both arrival orders"));
assert(concurrencyTests.includes("Concurrent out-of-order lifecycle monotonicity"));
assert(concurrencyTests.includes("Shared suppression-first transport authorization"));
assert(concurrencyTests.includes("Shared transport-first suppression ordering"));
assert(concurrencyTests.includes("Concurrent exact duplicate suppression event: PASS"));
assert(concurrencyTests.includes("Concurrent conflicting duplicate suppression event: PASS"));
assert(concurrencyTests.includes("Concurrent cross-recipient suppression ID collision: PASS"));
assert(pkg.scripts["test:delivery-webhook"] === "node --test scripts/test-delivery-webhook.mjs scripts/test-delivery-webhook-route.mjs");
assert(workflow.includes("node scripts/verify-delivery-provider-webhooks.mjs"));
assert(workflow.includes("npm run test:delivery-webhook"));
assert(workflow.includes("delivery_provider_webhook_database_behavior"));
assert(workflow.includes("scripts/test-delivery-provider-webhooks.sql"));
assert(workflow.includes("scripts/test-delivery-provider-webhook-concurrency.sh"));
assert(workflow.includes('test -z "' + "$" + '{RESEND_WEBHOOK_SECRET:-}"'));

const migration028FunctionBody = (source, tag) => {
  const marker = "as $" + tag + "$";
  const endMarker = "$" + tag + "$;";
  const start = source.indexOf(marker);
  const end = source.indexOf(endMarker, start + marker.length);
  assert(start >= 0 && end >= 0, "Migration 028 " + tag + " source is missing");
  return source.slice(start + marker.length, end);
};
assert.equal(
  createHash("sha256").update(migration028FunctionBody(leaseMigration, "authorize"), "utf8").digest("hex"),
  "dea4d0ecb1518edec6c60f1ec998669af65b2164a547cffe67f5cbdaa8644215",
  "Migration 028 authorize_delivery_job source fingerprint changed",
);
assert.equal(
  createHash("sha256").update(migration028FunctionBody(leaseMigration, "failed"), "utf8").digest("hex"),
  "c7830ca2281fa85e4466fa45c32c1067dba4c9766eeeb26d26dcdb3b46b72b78",
  "Migration 028 mark_delivery_failed source fingerprint changed",
);
for (const value of [
  "Migration 030 requires the exact hardened migration-028 authorize_delivery_job and mark_delivery_failed implementations.",
  "v_authorize_oid oid := to_regprocedure('public.authorize_delivery_job(uuid,uuid)')",
  "v_failed_oid oid := to_regprocedure('public.mark_delivery_failed(uuid,uuid,text)')",
  "p.prosrc",
  "p.prosecdef",
  "p.proconfig",
  "has_function_privilege('service_role'",
  "dea4d0ecb1518edec6c60f1ec998669af65b2164a547cffe67f5cbdaa8644215",
  "c7830ca2281fa85e4466fa45c32c1067dba4c9766eeeb26d26dcdb3b46b72b78",
]) assert(idempotencyMigration.includes(value), "Migration 030 missing migration-028 attestation: " + value);
assert(migrationOrderTest.includes("202611210028_delivery_claim_lock_expiry.sql"));
assert(migrationOrderTest.includes("Migration 030 rejects missing and drifted migration-028 prerequisite RPCs atomically: PASS"));
assert(migrationOrderTest.includes("C323 deliberate source drift"));
assert(migrationOrderTest.includes("revoke all privileges on function public.mark_delivery_failed"));
assert(aggregate.includes(idempotencyMigration.trim()), "Migration 030 must be mirrored verbatim in aggregate SQL");
assert(aggregate.includes(crossStreamMigration.trim()), "Migration 033 must be mirrored verbatim in aggregate SQL");
assert(migrationOrderTest.includes("202611220033_delivery_cross_stream_suppression_order.sql"));
assert(migrationOrderTest.includes('--file scripts/test-delivery-idempotency-guard.sql >"$tmp/idempotency-guard.log"'), "Migration-order idempotency test command must remain shell-valid");
assert(/p_payload_fingerprint is null[\s\S]*?_record_delivery_provider_lifecycle_event_fingerprinted_impl/i.test(crossStreamMigration),
  "Migration 033 must preserve migration 029 fingerprint and legacy replay protections");
for (const value of [
  "v_result is true",
  "p_event_type = 'email.suppressed'",
  "p_suppression_reason = 'provider_suppressed'",
  "s.origin = 'manual'",
  "s.is_active = false",
  "s.provider_created_at > p_provider_created_at",
  "reason = 'provider_suppressed'",
  "deedlight:033:cross-stream-suppression-order:v1",
]) assert(crossStreamMigration.includes(value), "Migration 033 missing cross-stream ordering guard: " + value);
for (const value of [
  "Older email.suppressed lifecycle event reinstated a newer manual provider removal.",
  "Equal-time cross-stream suppression did not fail closed.",
  "Cross-stream stale lifecycle handling cleared a previous_complaint hold.",
  "Cross-stream stale lifecycle handling cleared a previous_bounce hold.",
]) assert(suppressionTests.includes(value), "Missing cross-stream SQL regression assertion: " + value);
assert(suppressionTests.includes("'cross_stream_older_email_suppressed_after_manual_removal','pass'"));
assert(suppressionTests.includes("Cross-stream lifecycle reconciliation cleared a removal without a matching manual add."));
assert(crossStreamMigration.includes("added.event_type = 'suppression.added'"));
assert(crossStreamMigration.includes("added.provider_suppression_id = s.provider_suppression_id"));
assert(crossStreamMigration.includes("added.suppression_origin = 'manual'"));
assert(concurrencyTests.includes("C323_CROSS_STREAM_REMOVAL_FIRST_LOCK_HELD"));
assert(concurrencyTests.includes("C323_CROSS_STREAM_LIFECYCLE_FIRST_LOCK_HELD"));
assert(concurrencyTests.includes("Concurrent cross-stream removal-first ordering: PASS"));
assert(concurrencyTests.includes("Concurrent cross-stream lifecycle-first ordering: PASS"));
assert(parser.includes("MAX_SIGNATURE_HEADER_LENGTH = 4096"));
assert(parser.includes("MAX_SIGNATURE_CANDIDATES = 5"));
assert(parser.includes("HMAC_SHA256_SIGNATURE_LENGTH = 32"));
assert(parser.includes("signature.length > MAX_SIGNATURE_HEADER_LENGTH"));
assert(parser.includes("candidate.byteLength !== HMAC_SHA256_SIGNATURE_LENGTH"));
const signatureVerifier = parser.slice(parser.indexOf("export async function verifyResendWebhookSignature"));
assert(signatureVerifier.indexOf("candidate.byteLength !== HMAC_SHA256_SIGNATURE_LENGTH")
  < signatureVerifier.indexOf("crypto.subtle.importKey"),
  "Signature candidates must be bounded and validated before cryptographic verification");
assert(tests.includes("accepts five well-formed SHA-256 v1 rotation candidates"));
assert(tests.includes("rejects excessive or malformed v1 candidates"));
assert(tests.includes("rejects oversized Svix signature headers"));


console.log("Resend webhook authenticity, bounded signatures, cross-stream suppression ordering, migration-028 attestation and privacy assertions: PASS");
