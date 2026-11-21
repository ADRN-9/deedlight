import fs from "node:fs";

const files = {
  migration: "supabase/migrations/202609230020_delivery_reliability_hardening.sql",
  aggregateSql: "supabase/run_in_sql_editor_all.sql",
  packageJson: "package.json",
  wrangler: "wrangler.jsonc",
  sprintDoc: "docs/DELIVERY_RELIABILITY_HARDENING.md",
};

function read(path) {
  if (!fs.existsSync(path)) {
    throw new Error(`Required delivery reliability file is missing: ${path}`);
  }
  return fs.readFileSync(path, "utf8");
}

function requireMatch(name, text, pattern) {
  if (!pattern.test(text)) {
    throw new Error(`Delivery reliability security assertion failed: ${name}`);
  }
  console.log(`PASS: ${name}`);
}

function requireAbsent(name, text, pattern) {
  if (pattern.test(text)) {
    throw new Error(`Delivery reliability security assertion failed: ${name}`);
  }
  console.log(`PASS: ${name}`);
}

const migration = read(files.migration);
const leaseMigration = read("supabase/migrations/202611210028_delivery_claim_lock_expiry.sql");
const idempotencyMigration = read("supabase/migrations/202611210030_delivery_idempotency_receipt_guard.sql");
const idempotencyTests = read("scripts/test-delivery-idempotency-guard.sql");
const migrationOrderTest = read("scripts/test-delivery-migration-order.sh");
const deliveryRunner = read("lib/delivery/run-delivery.ts");
const deliveryRuntime = read("lib/delivery/supabase-runtime.ts");
const resendTransport = read("lib/delivery/resend-transport.ts");
const transportTests = read("scripts/test-delivery-transport.mjs");
const concurrencyTest = read("scripts/test-delivery-reliability-concurrency.sh");
const workflow = read(".github/workflows/pr-validation.yml");
const aggregateSql = read(files.aggregateSql);
const packageJson = read(files.packageJson);
const wrangler = read(files.wrangler);
const sprintDoc = read(files.sprintDoc);

for (const column of [
  "claim_expires_at",
  "attempt_count",
  "last_attempt_at",
  "next_attempt_at",
]) {
  requireMatch(
    `Delivery ledger adds ${column}`,
    migration,
    new RegExp(`add column ${column}\\b`, "i"),
  );
}

requireMatch(
  "Migration refuses live claimed jobs",
  migration,
  /where state = 'claimed'[\s\S]*?raise exception 'Delivery reliability hardening refuses to migrate live claimed jobs\.'/i,
);

requireMatch(
  "Attempt count is bounded",
  migration,
  /delivery_ledger_attempt_count_check[\s\S]*?attempt_count between 0 and 5/i,
);

requireMatch(
  "Claim state requires a token and finite lease",
  migration,
  /delivery_ledger_claim_lease_check[\s\S]*?state = 'claimed'[\s\S]*?claim_token is not null[\s\S]*?claim_expires_at is not null/i,
);

requireMatch(
  "Claim RPC reclaims expired leases",
  migration,
  /claim_delivery_jobs[\s\S]*?dl\.state = 'claimed'[\s\S]*?dl\.claim_expires_at <= p_now[\s\S]*?dl\.attempt_count < 5/i,
);

requireMatch(
  "Each claim gets a five minute lease and increments attempts",
  migration,
  /claim_expires_at = p_now \+ interval '5 minutes'[\s\S]*?attempt_count = dl\.attempt_count \+ 1/i,
);

requireMatch(
  "Expired fifth attempts become terminal retry exhaustion",
  migration,
  /claim_delivery_jobs[\s\S]*?attempt_count >= 5[\s\S]*?error_code = 'retry_exhausted'/i,
);

for (const fn of [
  "claim_delivery_jobs",
  "authorize_delivery_job",
  "retry_delivery_job",
  "mark_delivery_sent",
  "mark_delivery_failed",
]) {
  requireMatch(
    `${fn} is SECURITY DEFINER with constrained search path`,
    migration,
    new RegExp(
      `create or replace function public\\.${fn}\\([\\s\\S]*?security definer[\\s\\S]*?set search_path = public, auth, pg_temp`,
      "i",
    ),
  );

  requireMatch(
    `${fn} remains service-role only`,
    migration,
    new RegExp(
      `revoke all privileges[\\s\\S]*?on function public\\.${fn}\\([\\s\\S]*?from public, anon, authenticated;[\\s\\S]*?grant execute[\\s\\S]*?to service_role;`,
      "i",
    ),
  );
}

requireMatch(
  "Authorization requires a live lease",
  migration,
  /authorize_delivery_job[\s\S]*?claim_expires_at is null[\s\S]*?claim_expires_at <= now\(\)/i,
);

requireMatch(
  "Retry time is bounded to 24 hours",
  migration,
  /retry_delivery_job[\s\S]*?p_retry_at <= now\(\)[\s\S]*?p_retry_at > now\(\) \+ interval '24 hours'/i,
);

requireMatch(
  "Temporary retry uses next_attempt_at",
  migration,
  /retry_delivery_job[\s\S]*?state = 'queued'[\s\S]*?next_attempt_at = p_retry_at/i,
);

const retryFunction = migration.match(
  /create or replace function public\.retry_delivery_job\([\s\S]*?\n\$\$;/i,
)?.[0] ?? "";

requireAbsent(
  "Retry does not rewrite semantic scheduled_for",
  retryFunction,
  /scheduled_for\s*=/i,
);

for (const fn of ["mark_delivery_sent", "mark_delivery_failed"]) {
  requireMatch(
    `${fn} requires an unexpired lease`,
    migration,
    new RegExp(
      `${fn}[\\s\\S]*?claim_expires_at is not null[\\s\\S]*?claim_expires_at > now\\(\\)`,
      "i",
    ),
  );
}

requireAbsent(
  "Reliability migration does not add recipient email storage",
  migration,
  /add column\s+(?:recipient_)?email\b/i,
);

requireAbsent(
  "No outbound provider dependency is introduced",
  packageJson,
  /"(?:resend|@sendgrid\/mail|postmark|mailgun|twilio|web-push)"\s*:/i,
);

const wranglerConfig = JSON.parse(wrangler);
if (
  !Array.isArray(wranglerConfig.triggers?.crons) ||
  wranglerConfig.triggers.crons.length !== 0
) {
  throw new Error(
    "Delivery reliability security assertion failed: Cloudflare Cron Triggers remain disabled",
  );
}
console.log("PASS: Cloudflare Cron Triggers remain disabled");

requireMatch(
  "Reliability documentation keeps outbound delivery inactive",
  sprintDoc,
  /does \*\*not\*\* add:[\s\S]*?email\/SMS\/push provider[\s\S]*?Cloudflare Cron Trigger/i,
);

if (!aggregateSql.includes(migration.trim())) {
  throw new Error(
    "Delivery reliability security assertion failed: canonical migration is not mirrored verbatim in supabase/run_in_sql_editor_all.sql",
  );
}
console.log("PASS: canonical migration is mirrored verbatim in aggregate SQL");

if (!aggregateSql.includes(leaseMigration.trim())) {
  throw new Error("Delivery reliability security assertion failed: migration 028 is not mirrored verbatim in aggregate SQL.");
}
console.log("PASS: additive lease correction is mirrored verbatim in aggregate SQL");
for (const fn of ["authorize_delivery_job", "retry_delivery_job", "mark_delivery_sent", "mark_delivery_failed"]) {
  const start = leaseMigration.indexOf("create or replace function public." + fn + "(");
  const end = leaseMigration.indexOf("\n$", start);
  const definition = start < 0 ? "" : leaseMigration.slice(start, end < 0 ? undefined : end);
  if (!/for update[\s\S]*?clock_timestamp\(\)/i.test(definition)) {
    throw new Error(fn + " must lock the ledger row before wall-clock lease validation.");
  }
  if (/claim_expires_at\s*(?:<=|>)\s*now\(\)/i.test(definition)) {
    throw new Error(fn + " must not validate lease expiry using transaction-start now().");
  }
  if (!/security definer[\s\S]*?set search_path = public, auth, pg_temp/i.test(definition)
    || !leaseMigration.includes("revoke all privileges on function public." + fn)
    || !leaseMigration.includes("grant execute on function public." + fn)) {
    throw new Error(fn + " security-definer or service-role privilege boundary regressed.");
  }
  if (!concurrencyTest.includes(fn)) {
    throw new Error("Missing row-lock expiry concurrency case: " + fn);
  }
}
if (!/retry_delivery_job[\s\S]*?for update[\s\S]*?p_retry_at <= v_now[\s\S]*?p_retry_at > v_now \+ interval '24 hours'/i.test(leaseMigration)) {
  throw new Error("Retry time must remain bounded against wall-clock time after the row lock.");
}
if (!/attempt_count >= 5[\s\S]*?error_code = 'retry_exhausted'/i.test(leaseMigration)) {
  throw new Error("Fifth-attempt retry exhaustion must remain terminal.");
}
if (!/wait_for_row_lock_wait[\s\S]*?wait_event_type='Lock'/i.test(concurrencyTest)) {
  throw new Error("Concurrency harness must wait for an actual PostgreSQL row-lock wait.");
}
if (!workflow.includes("bash scripts/test-delivery-reliability-concurrency.sh")) {
  throw new Error("PR Validation must run the lease lock-contention test.");
}

if (!aggregateSql.includes(idempotencyMigration.trim())) {
  throw new Error("Migration 030 is not mirrored verbatim in the SQL Editor aggregate.");
}
console.log("PASS: migration 030 is mirrored verbatim in aggregate SQL");

const retryStart = idempotencyMigration.indexOf("create or replace function public.retry_delivery_job(");
const retryEnd = idempotencyMigration.indexOf("\n$retry$;", retryStart);
const authoritativeRetry = idempotencyMigration.slice(retryStart, retryEnd);
const compactRetry = authoritativeRetry.replace(/\s+/g, "");
const compactMigration = idempotencyMigration.replace(/\s+/g, "");
if (retryStart < 0 || retryEnd < 0
  || compactRetry.includes("p_retry_at")
  || !compactRetry.includes("v_now:=clock_timestamp()")
  || !compactRetry.includes("v_retry_at:=v_now+interval'5minutes'")
  || !compactRetry.includes("transport_started_at+interval'23hours'")) {
  throw new Error("Migration 030 retry must use PostgreSQL time and persisted transport-start evidence.");
}
if (!idempotencyMigration.includes("return public.retry_delivery_job(p_job_id,p_claim_token,p_error_code);")) {
  throw new Error("Legacy retry overload must ignore its Worker-supplied timestamp.");
}
if (!idempotencyMigration.includes("authorize_delivery_idempotency_window")
  || !idempotencyMigration.includes("public.authorize_delivery_job(p_job_id,p_claim_token)")
  || !idempotencyMigration.includes("return 'cancelled'")
  || !idempotencyMigration.includes("return 'expired'")
  || !idempotencyMigration.includes("return 'authorized'")
  || !idempotencyMigration.includes("clock_timestamp()")
  || !idempotencyMigration.includes("interval '23 hours'")
  || !idempotencyMigration.includes("interval '30 seconds'")) {
  throw new Error("Migration 030 pre-send provider idempotency authorization is incomplete.");
}
if (!compactMigration.includes("p_provider_result_idisnull")
  || !compactMigration.includes("char_length(p_provider_result_id)<>36")
  || !compactMigration.includes("p_provider_result_id<>btrim(p_provider_result_id)")
  || !compactMigration.includes("transport_started_atisnull")) {
  throw new Error("Migration 030 sent transition must require transport evidence and a validated receipt.");
}
if (!deliveryRunner.includes("authorizeProviderIdempotencyWindow")
  || deliveryRunner.includes("PROVIDER_IDEMPOTENCY_SAFETY_MS")
  || deliveryRunner.includes("RETRY_DELAY_MS")
  || deliveryRunner.includes("clock?:")) {
  throw new Error("Worker must delegate provider horizon and retry timing to PostgreSQL.");
}
if (!deliveryRuntime.includes("authorize_delivery_idempotency_window")
  || !deliveryRuntime.includes("p_error_code: errorCode")
  || deliveryRuntime.includes("p_retry_at")) {
  throw new Error("Supabase runtime must call DB-authoritative RPCs without Worker timestamps.");
}
if (!resendTransport.includes("RESEND_EMAIL_ID_PATTERN")
  || !resendTransport.includes("value === value.trim()")) {
  throw new Error("Resend transport must reject malformed, whitespace and control-character receipt IDs.");
}
if (!idempotencyTests.includes("worker_clock_two_hours_behind")
  || !idempotencyTests.includes("24 hours 1 second")
  || !idempotencyTests.includes("provider-message-123")
  || !idempotencyTests.includes("missing transport-start evidence")) {
  throw new Error("Migration 030 PostgreSQL regression coverage is incomplete.");
}
if (!migrationOrderTest.includes("C226 deliberate source drift")
  || !migrationOrderTest.includes("Migration 029 source identity drift rejection")
  || !migrationOrderTest.includes("scripts/test-delivery-idempotency-guard.sql")) {
  throw new Error("Migration-order CI must prove migration 029 drift rejection and migration 030 behavior.");
}
if (!transportTests.includes("database-authoritative idempotency expiry")
  || !transportTests.includes("final provider gate cancels when consent is revoked")
  || !transportTests.includes("retry and provider-window RPCs never trust a Worker timestamp")
  || !transportTests.includes("canonical UUIDs")) {
  throw new Error("Transport tests must cover DB-authoritative timing and Resend receipt validation.");
}
console.log("PASS: C226 migration 030, Worker timing and receipt validation assertions");

console.log("Delivery reliability security assertions: PASS");
