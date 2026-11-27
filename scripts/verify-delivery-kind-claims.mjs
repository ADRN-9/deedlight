import fs from "node:fs";
import path from "node:path";
const read = (file) => fs.readFileSync(path.join(process.cwd(), file), "utf8");
const migration = read("supabase/migrations/202611260039_delivery_kind_scoped_claims.sql");
const aggregate = read("supabase/run_in_sql_editor_all.sql");
const runtime = read("lib/delivery/supabase-runtime.ts");
const scheduler = read("lib/delivery/scheduler.ts");
const workflow = read(".github/workflows/pr-validation.yml");
const migrationOrder = read("scripts/test-delivery-migration-order.sh");
const sqlTests = read("scripts/test-delivery-kind-claims.sql");
const transportTests = read("scripts/test-delivery-transport.mjs");
function expect(condition, message) { if (!condition) throw new Error(`Delivery kind claim assertion failed: ${message}`); }
for (const [kind, rpc] of [["daily_reminder","claim_daily_delivery_jobs"],["weekly_newsletter","claim_weekly_delivery_jobs"]]) {
  expect(migration.includes(`public.${rpc}`), `${rpc} migration function exists`);
  expect(migration.includes(`where dl.kind = '${kind}'`), `${rpc} filters by its immutable kind`);
  expect(migration.includes(`grant execute\non function public.${rpc}(integer)\nto service_role`), `${rpc} is service-role only`);
}
expect((migration.match(/security invoker/gi) ?? []).length === 2, "both claim RPCs are SECURITY INVOKER");
for (const [kind, rpc] of [["Daily","claim_daily_delivery_jobs"],["Weekly","claim_weekly_delivery_jobs"]]) {
  const signature = new RegExp(`create\s+or\s+replace\s+function\s+public\.${rpc}\s*\(\s*p_limit\s+integer`, "i");
  expect(signature.test(migration), `${kind} claim accepts only the batch limit, never a caller-controlled timestamp`);
  const definition = migration.match(new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${rpc}\\s*\\(\\s*p_limit\\s+integer[\\s\\S]*?as\\s+\\$\\$([\\s\\S]*?)\\$\\$;`, "i"));
  expect(definition, `${kind} claim function body is statically extractable`);
  const body = definition[1];
  expect(/claim_expires_at\s*<=\s*clock_timestamp\(\)/i.test(body), `${kind} lease expiry uses database wall-clock time`);
  expect(/coalesce\(dl\.next_attempt_at,\s*dl\.scheduled_for\)\s*<=\s*clock_timestamp\(\)/i.test(body), `${kind} due-job eligibility uses database wall-clock time`);
  expect(/claim_expires_at\s*=\s*clock_timestamp\(\)\s*\+\s*interval\s+'5 minutes'/i.test(body), `${kind} claim lease duration uses database wall-clock time`);
  expect(!/\bnow\s*\(/i.test(body), `${kind} claim contains no transaction-start now() time decision`);

  expect(!new RegExp(`create\s+or\s+replace\s+function\s+public\.${rpc}\s*\([^)]*timestamptz`, "i").test(migration), `${kind} claim has no caller-supplied timestamptz`);
  expect(!new RegExp(`create\s+or\s+replace\s+function\s+public\.${rpc}\s*\([^)]*timestamp\s+with\s+time\s+zone`, "i").test(migration), `${kind} claim has no caller-supplied timestamp with time zone`);
}
expect((migration.match(/clock_timestamp\(\)/g) ?? []).length >= 16, "claim lease and eligibility decisions use PostgreSQL clock_timestamp()");
expect(!/claim_expires_at\s*<=\s*now\(\)/i.test(migration), "claim lease expiry never uses transaction-start now()");
expect(!/scheduled_for\s*<=\s*now\(\)/i.test(migration), "claim scheduling eligibility never uses caller or transaction timestamp");

expect(!/^\s*security\s+definer\b/im.test(migration), "migration introduces no SECURITY DEFINER functions");
expect((migration.match(/dl.kind = 'daily_reminder'/g) ?? []).length >= 3, "Daily lease cleanup, pick and update are kind scoped");
expect((migration.match(/dl.kind = 'weekly_newsletter'/g) ?? []).length >= 3, "Weekly lease cleanup, pick and update are kind scoped");
expect(!migration.includes("_claim_delivery_jobs_for_kind"), "no generic kind-selecting helper exists");
expect(migration.includes("revoke all privileges\non function public.claim_delivery_jobs(timestamptz, integer)\nfrom public, anon, authenticated, service_role"), "legacy unrestricted RPC is revoked from application roles");
expect(aggregate.includes(migration.trim()), "migration 039 is mirrored verbatim in SQL Editor aggregate");
expect(runtime.includes('kind === "daily_reminder"\n      ? "claim_daily_delivery_jobs"\n      : "claim_weekly_delivery_jobs"'), "runtime chooses the RPC by requested kind");
expect(runtime.includes("parseClaimedJob(row as Record<string, unknown>, kind)"), "runtime validates every returned job against requested kind");
expect(runtime.includes("kind !== expectedKind"), "runtime rejects a cross-kind row");
expect(scheduler.includes("runtime.claim(expectedKind, deliveryClaimBatchSize(config.batchSize))"), "scheduler requests only its schedule's delivery kind");
expect(scheduler.includes("jobs.some((job) => job.kind !== expectedKind)"), "scheduler independently rejects cross-kind results");
expect(scheduler.indexOf("if (!config.enabled)") < scheduler.indexOf("weeklyDeliveryScheduleEnabled(env)"), "global kill switch is checked first");
expect(scheduler.indexOf("weeklyDeliveryScheduleEnabled(env)") < scheduler.indexOf("createSupabaseDeliveryRuntime(config)"), "Weekly opt-in is checked before runtime construction");
expect(scheduler.includes('env.WEEKLY_DELIVERY_ENABLED === "true"'), "Weekly remains explicit opt-in");
expect(sqlTests.includes("claim_daily_delivery_jobs(10)") && sqlTests.includes("claim_weekly_delivery_jobs(10)"), "database tests exercise both kind RPCs");
expect(sqlTests.includes("Daily claim mutated a Weekly queued, expired, or exhausted job"), "Daily adversarial cross-kind mutation check exists");
expect(sqlTests.includes("Weekly claim mutated an already-claimed Daily job"), "Weekly adversarial cross-kind mutation check exists");
expect(sqlTests.includes("Weekly claim mutated a Daily queued, expired, or exhausted job"), "Weekly adversarial cross-kind eligible-job isolation check exists");
expect(sqlTests.includes("Anonymous role executed legacy unrestricted claim") && sqlTests.includes("Authenticated role executed legacy unrestricted claim"), "browser denial of legacy unrestricted RPC is exercised");
expect(sqlTests.includes("claim_daily_delivery_jobs(null)") && sqlTests.includes("claim_weekly_delivery_jobs(null)"), "null batch sizes rejected");
expect(sqlTests.includes("Legacy unrestricted claim function remains callable"), "legacy unrestricted RPC denial tested");
expect(sqlTests.includes("SECURITY INVOKER") && sqlTests.includes("to_regprocedure('public._claim_delivery_jobs_for_kind"), "database test asserts invoker functions and absence of generic helper");
expect(sqlTests.includes("set role anon") && sqlTests.includes("set role authenticated"), "browser role denial tested");
expect(sqlTests.includes("authorize_delivery_job("), "stale pre-reclaim token rejection tested");
expect(sqlTests.includes("weekly_stale_reclaim_token_rejected") && sqlTests.includes("v_old_token") && sqlTests.includes("Weekly second reclaim"), "Weekly stale token cannot authorize after reclaim");
expect(migrationOrder.includes("202611260039_delivery_kind_scoped_claims.sql"), "migration-order CI applies migration 039");
expect(migrationOrder.includes("scripts/test-delivery-kind-claims.sql"), "migration-order CI executes adversarial DB test");
expect(workflow.includes("node scripts/verify-delivery-kind-claims.mjs"), "full PR validation runs claim security verifier");
expect(transportTests.includes('runtime.claim("daily_reminder"'), "runtime Daily claim test exists");
console.log("Daily/Weekly database-enforced claim isolation assertions: PASS");
