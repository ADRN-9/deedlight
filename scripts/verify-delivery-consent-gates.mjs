import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
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
