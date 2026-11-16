import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

const mandatory = [
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
];

const requiredFiles = {
  release_privacy_pg16: [
    "postgres-version.txt", "migrations.log", "migration-summary.txt",
    "privacy.log", "inventory.txt",
  ],
  release_action_privacy: ["app-privacy.log", "inventory.txt"],
  release_provider_pg16: [
    "version.txt", "provider-019-030.log", "provider-031.log",
    "provider-032.log", "provider-033.log",
    "provider-classification.log", "post033-019-030.log",
    "post033-031.log", "post033-032.log", "post033-033.log",
    "post033-regressions.log",
  ],
  release_consent_races: ["c76-kind-logs", "c77-race-logs"],
  release_webhook_http: [
    "signed-webhooks.log", "provider-contract.log",
    "source-contract.log", "http-019-030.log", "route-http.log",
  ],
};

function readable(path) {
  const data = readFileSync(path);
  assert.ok(data.length > 0, "Empty or missing required evidence: " + path);
  return data;
}

const root = resolve(process.env.EVIDENCE_ROOT ?? "release-downloaded");
const sha = process.env.EXPECTED_SHA;
const tree = process.env.EXPECTED_TREE;
assert.match(sha ?? "", /^[0-9a-f]{40}$/);
assert.match(tree ?? "", /^[0-9a-f]{40}$/);
const results = JSON.parse(process.env.NEEDS_JSON ?? "{}");
assert.deepEqual(Object.keys(results).sort(), [...mandatory].sort(),
  "Required security dependency missing, unexpected or not scheduled");
for (const name of mandatory) {
  assert.equal(results[name]?.result, "success",
    "Security dependency " + name + " is not successful (fail/skip/cancel/neutral block release)");
}

const hashes = {};
for (const name of mandatory) {
  const directory = join(root, "release-evidence-" + name);
  assert.equal(readable(join(directory, "commit.txt")).toString("utf8").trim(), sha,
    "Source SHA mismatch: " + name);
  assert.equal(readable(join(directory, "tree.txt")).toString("utf8").trim(), tree,
    "Git tree mismatch: " + name);
  assert.equal(readable(join(directory, "result.txt")).toString("utf8").trim(), "PASS",
    "Missing successful test attestation: " + name);
  for (const file of requiredFiles[name] ?? []) {
    if (file.endsWith("-logs")) {
      assert.ok(readdirSync(join(directory, file)).length >= 2,
        "Missing nonempty race evidence directory " + name + "/" + file);
      continue;
    }
    const data = readable(join(directory, file));
    hashes[name + "/" + file] = createHash("sha256").update(data).digest("hex");
  }
}

const privacy = readable(join(root,
  "release-evidence-release_privacy_pg16", "inventory.txt")).toString("utf8");
assert.match(privacy, /RELEASE_PRIVACY_INVENTORY_PASS 64\/64/);
const migration = readable(join(root,
  "release-evidence-release_privacy_pg16", "migration-summary.txt")).toString("utf8");
assert.match(migration, /ALL 001–034 source migrations applied/);
const actions = readable(join(root,
  "release-evidence-release_action_privacy", "inventory.txt")).toString("utf8");
assert.match(actions, /RELEASE_ACTION_INVENTORY_PASS 19\/19/);

writeFileSync("release-security-gate-manifest.json", JSON.stringify({
  source_sha: sha,
  source_tree: tree,
  required_jobs: mandatory,
  completed: mandatory.map((name) => ({ job: name, conclusion: results[name].result })),
  evidence_sha256: hashes,
}, null, 2) + "\n");
console.log("RELEASE_SECURITY_GATE_PASS " + mandatory.length + "/" + mandatory.length +
  " unique mandatory jobs, matching source SHA/tree and retained evidence");
