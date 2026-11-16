import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const env = process.env;
const job = env.GITHUB_JOB;
const runId = env.GITHUB_RUN_ID;
const attemptRaw = env.GITHUB_RUN_ATTEMPT;
const sha = env.GITHUB_SHA;
const repository = env.GITHUB_REPOSITORY;
const expectedJobs = [
  "validate", "sprint12_2_database_behavior",
  "delivery_reliability_database_behavior",
  "gentle_delivery_transport_database_behavior",
  "auth_pgcrypto_database_behavior",
  "delivery_migration_order_database_behavior",
  "release_privacy_pg16", "release_action_privacy",
  "release_provider_pg16", "release_consent_races",
  "release_webhook_http",
];

assert.ok(env.GITHUB_ACTIONS === "true", "GitHub Actions runner required");
assert.equal(repository, "ADRN-9/deedlight");
assert.ok(expectedJobs.includes(job), "Unrecognized evidence-producing job");
assert.match(runId ?? "", /^[1-9]\d{0,19}$/);
assert.match(attemptRaw ?? "", /^[1-9]\d{0,8}$/);
assert.match(sha ?? "", /^[a-f0-9]{40}$/);
const tree = execFileSync("git", ["rev-parse", "HEAD^{tree}"], { encoding: "utf8" }).trim();
assert.equal(execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim(), sha);
assert.match(tree, /^[a-f0-9]{40}$/);
const artifact = "release-evidence-" + job + "-run-" + runId + "-attempt-" + attemptRaw;
const dir = join("release-evidence", job);
mkdirSync(dir, { recursive: true });
const receipt = {
  version: 1,
  repository,
  workflow: "PR Validation",
  job,
  run_id: runId,
  run_attempt: Number(attemptRaw),
  source_sha: sha,
  source_tree: tree,
  artifact_name: artifact,
};
writeFileSync(join(dir, "receipt.json"), JSON.stringify(receipt, null, 2) + "\n");
console.log("RELEASE_PRODUCER_RECEIPT_WRITTEN " + job + " run=" + runId +
  " attempt=" + attemptRaw);
