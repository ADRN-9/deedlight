import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const folder = ".github/workflows";
const expectedJobs = [
  "validate",
  "sprint12_2_database_behavior",
  "delivery_reliability_database_behavior",
  "gentle_delivery_transport_database_behavior",
  "auth_pgcrypto_database_behavior",
  "delivery_migration_order_database_behavior",
  "release_privacy_pg16",
  "release_action_privacy",
  "release_provider_pg16",
  "release_consent_races",
  "release_webhook_http",
  "release_security_gate",
];
const seen = new Map();
for (const filename of readdirSync(folder).filter((x) => /\.ya?ml$/.test(x))) {
  const source = readFileSync(join(folder, filename), "utf8");
  assert.doesNotMatch(source, /^  pull_request_target:/m,
    "Do not run untrusted PR code with pull_request_target");
  if (!/^  pull_request:/m.test(source)) continue;
  const jobs = source.split(/^jobs:\s*$/m)[1];
  assert.ok(jobs, "Missing jobs: " + filename);
  for (const match of jobs.matchAll(/^  ([a-z][a-z0-9_-]+):\s*$/gm)) {
    const id = match[1];
    assert.ok(!seen.has(id),
      "Duplicate PR check identity " + id + " in " + seen.get(id) + " and " + filename);
    seen.set(id, filename);
  }
}
assert.deepEqual([...seen.keys()].sort(), [...expectedJobs].sort(),
  "Unexpected or missing release PR job/check identities");
assert.ok([...seen.values()].every((x) => x === "pr-validation.yml"),
  "All mandatory release checks must be produced by the durable PR Validation workflow");
for (const legacy of ["c101-member-privacy.yml", "c103-moderation-feedback.yml"]) {
  const source = readFileSync(join(folder, legacy), "utf8");
  assert.doesNotMatch(source, /^  pull_request:/m,
    legacy + " must not publish a duplicate PR check");
}
console.log("RELEASE_WORKFLOW_IDENTITIES_PASS " + seen.size +
  " unique PR check contexts; no duplicate privacy job or privileged PR trigger");
