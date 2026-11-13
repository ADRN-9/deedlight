import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const read = (path) => readFileSync(path, "utf8");
const migration = read("supabase/migrations/202611120023_delivery_consent_linearization.sql");
const aggregate = read("supabase/run_in_sql_editor_all.sql");
const workflow = read(".github/workflows/supabase-migrations.yml");
const guard = "scripts/guard-supabase-migration-target.sh";
const runner = read("lib/delivery/run-delivery.ts");
const runtime = read("lib/delivery/supabase-runtime.ts");
const types = read("lib/delivery/types.ts");
const tests = read("scripts/test-delivery-consent-gates.sql");

assert(aggregate.includes(migration.trim()), "Migration 023 must mirror into aggregate SQL");
assert(migration.includes("create or replace function public.begin_delivery_transport"));
const begin = migration.split("create or replace function public.begin_delivery_transport")[1].split("\n$$;")[0];
for (const predicate of [
  "claim_token is distinct from p_claim_token",
  "claim_expires_at <= now()",
  "drp.daily_enabled = true",
  "np.weekly_enabled = true",
  "np.consented_at is not null",
  "p.is_suspended = false",
  "u.email_confirmed_at is not null",
  "for share of drp, p",
  "for share of np, p, u, f",
  "return null",
]) assert(begin.includes(predicate), `Missing authoritative transport invariant: ${predicate}`);
assert(/revoke all privileges\s+on function public\.begin_delivery_transport\(uuid, uuid\)\s+from public, anon, authenticated/i.test(migration));
assert(/grant execute\s+on function public\.begin_delivery_transport\(uuid, uuid\)\s+to service_role/i.test(migration));

for (const name of ["enqueue_due_daily_reminders", "enqueue_weekly_goodness_delivery"]) {
  const body = migration.split(`create or replace function public.${name}`)[1].split("\n$$;")[0];
  assert(body.indexOf("not exists (") < body.indexOf("limit p_limit"), `${name} must exclude existing deliveries before LIMIT`);
  assert(body.includes("on conflict (kind, user_id, delivery_key) do nothing"));
}

assert(runner.includes('if (firstTransportAt === null) return "cancelled"'));
assert(runner.includes('return requeued ? "retried" : "failed"'));
assert(runtime.includes('typeof data !== "boolean"'));
assert(types.includes("Promise<boolean>"));
assert(tests.includes("public.begin_delivery_transport"));
assert(tests.includes("Daily enqueue stalled"));
assert(tests.includes("Weekly enqueue stalled"));

const section = workflow.split("name: Link and push migrations")[1];
assert(section, "Migration push workflow must retain guarded step");
const guardIndex = section.indexOf("bash scripts/guard-supabase-migration-target.sh");
const linkIndex = section.indexOf("supabase link");
const pushIndex = section.indexOf("supabase db push");
assert(guardIndex >= 0 && guardIndex < linkIndex && linkIndex < pushIndex, "Guard must run before link and push");
assert(/set -euo pipefail/.test(section), "Migration step must stop on guard error");

for (const [ref, success] of [
  [undefined, false],
  ["", false],
  ["xaipiovflxomcbfwtwmu", false],
  ["xaipiovflxomcbfwtwmu\n", false],
  ["../../danger", false],
  ["UPPERCASEPROJECTREFX", false],
  ["abcdefghijklmnopqrst", true],
]) {
  const env = { ...process.env };
  if (ref === undefined) delete env.SUPABASE_PROJECT_REF;
  else env.SUPABASE_PROJECT_REF = ref;
  const result = spawnSync("bash", [guard], { env, encoding: "utf8" });
  assert.equal(result.status === 0, success, `Migration guard misclassified test ref: ${JSON.stringify(ref)}`);
}
console.log("Delivery consent, batching, terminal retry and migration guard assertions: PASS");

const newMigration = read("supabase/migrations/202611120024_delivery_identity_lease_capacity.sql");
const linkedGuard = read("scripts/guard-supabase-linked-project.sh");
const pkg = JSON.parse(read("package.json"));
const validation = read(".github/workflows/pr-validation.yml");
assert(aggregate.includes(newMigration.trim()), "Migration 024 must mirror into aggregate SQL");
assert(/drop function public\.begin_delivery_transport\(uuid,uuid\)/.test(newMigration),
  "Legacy unbound RPC must be removed");
assert(newMigration.includes("p_expected_email text"));
assert(newMigration.includes("btrim(u.email) = p_expected_email"));
assert(newMigration.includes("for share of drp, p, u"));
assert(newMigration.includes("for share of np, p, u, f"));
assert(newMigration.includes("clock_timestamp()"));
assert(newMigration.includes("claim_expires_at > clock_timestamp()"));
assert(newMigration.includes("using errcode = '54000'"));
assert(runtime.includes("p_expected_email: recipient.email"));
assert(runner.includes("gateway.beginTransport(job, recipient)"));
assert(types.includes("recipient: AuthorizedRecipient"));
assert(linkedGuard.includes("supabase/.temp/project-ref"));
assert(pkg.scripts["supabase:push"].startsWith("bash scripts/guard-supabase-linked-project.sh && "));
assert(pkg.scripts["supabase:link"].startsWith("bash scripts/guard-supabase-migration-target.sh && "));
assert(workflow.includes("bash scripts/guard-supabase-linked-project.sh"));
assert(validation.includes("npm audit --audit-level=high"));
assert(!validation.includes("audit --omit=dev"));
assert(tests.includes("weekly_capacity_5001_fail_closed"));
const race = read("scripts/test-delivery-consent-concurrency.sh");
assert(race.includes("Concurrent consent lock wait with expiring claim: PASS"));
console.log("Cycle 5 recipient, lease, capacity and migration guard assertions: PASS");

const guardRoot=mkdtempSync(join(tmpdir(),"deedlight-guard-test-"));
try{
  mkdirSync(join(guardRoot,"scripts"),{recursive:true});
  mkdirSync(join(guardRoot,"supabase",".temp"),{recursive:true});
  writeFileSync(join(guardRoot,"scripts","guard-supabase-migration-target.sh"),read(guard));
  writeFileSync(join(guardRoot,"scripts","guard-supabase-linked-project.sh"),linkedGuard);
  const linked=join(guardRoot,"supabase",".temp","project-ref");
  for(const [approved,actual,allowed] of [
    ["abcdefghijklmnopqrst","abcdefghijklmnopqrst",true],
    ["abcdefghijklmnopqrst","xaipiovflxomcbfwtwmu",false],
    ["xaipiovflxomcbfwtwmu","xaipiovflxomcbfwtwmu",false],
    ["abcdefghijklmnopqrst","",false],
  ]){
    if(actual) writeFileSync(linked,actual);
    else rmSync(linked,{force:true});
    const result=spawnSync("bash",["scripts/guard-supabase-linked-project.sh"],{
      cwd:guardRoot,encoding:"utf8",env:{...process.env,SUPABASE_PROJECT_REF:approved}
    });
    assert.equal(result.status===0,allowed,"Linked-project guard did not fail closed");
  }
}finally{
  rmSync(guardRoot,{recursive:true,force:true});
}
assert(pkg.overrides?.["source-map-js"]==="^1.2.2");
console.log("Linked project mismatch and missing-link checks: PASS");

assert(pkg.overrides?.["miniflare@5.20261110.2-beta"]?.undici==="7.30.2",
  "Miniflare Undici must be patched for GHSA-mqg3-3v4r-cm32");

const migration23 = read("supabase/migrations/202611120023_delivery_consent_linearization.sql");
for (const marker of [
  "deedlight:023:daily-exclusion-before-limit:v1",
  "deedlight:023:weekly-exclusion-before-limit:v1",
  "deedlight:023:locked-consent-before-transport:v1",
]) {
  assert(migration23.includes(marker), "Missing migration-023 attestation");
  assert(newMigration.includes(marker), "Migration 024 must require the 023 attestation");
}
assert(newMigration.includes("pg_get_functiondef("),
  "Prerequisite may not trust markers without checking reviewed function definitions");
assert(newMigration.includes("pg_advisory_xact_lock("),
  "All weekly RPCs must serialize capacity updates");
assert(newMigration.includes("current_setting('transaction_isolation')"),
  "Serializable lock protocol requires READ COMMITTED isolation");
assert(newMigration.includes("v_existing > 5000"));
assert(newMigration.includes("v_room := least(5000 - v_existing, p_limit)"));
assert(newMigration.includes("v_candidate_count > v_room"));
assert(newMigration.includes("get diagnostics v_inserted = row_count"));
assert(newMigration.includes("return public.enqueue_weekly_goodness_delivery("),
  "Scheduler wrapper must delegate to guarded lower-level RPC");
assert(tests.includes("existing_5000_plus_1_denied"));
assert(tests.includes("terminal_rows_counted"));
assert(race.includes("Concurrent weekly scheduler issue-wide capacity and late opt-in: PASS"));
assert(validation.includes("delivery_migration_order_database_behavior"),
  "CI must execute positive and negative migration ordering tests");
console.log("Cycle 7 migration attestation and serialized weekly-capacity assertions: PASS");
