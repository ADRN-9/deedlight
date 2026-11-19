import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync, lstatSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";

const requiredJobs = [
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
    "postgres-version.txt", "bootstrap.log", "migrations.log",
    "migration-summary.txt", "privacy.log", "inventory.txt",
  ],
  release_action_privacy: ["app-privacy.log", "inventory.txt"],
  release_provider_pg16: [
    "version.txt", "provider-019-030.log", "provider-031.log",
    "provider-032.log", "provider-033.log", "provider-classification.log",
    "post033-019-030.log", "post033-031.log", "post033-032.log",
    "post033-033.log", "c77-post033.log", "provider-result.txt",
  ],
  release_consent_races: [
    "c76-kind-logs/concurrency-result.txt",
    "c76-kind-logs/daily-transaction.log",
    "c76-kind-logs/kind-and-lease-regressions.log",
    "c76-kind-logs/synthetic-setup.log",
    "c76-kind-logs/weekly-transaction.log",
    "c77-race-logs/assertions.log",
    "c77-race-logs/consent-final.log",
    "c77-race-logs/result.txt",
    "c77-race-logs/setup.log",
    "c77-race-logs/consent-setup.log",
  ],
  release_webhook_http: [
    "signed-webhooks.log", "provider-contract.log", "source-contract.log",
    "http-019-030.log", "route-http.log",
    "202611130031_c74_legacy_lifecycle_guard.sql.log",
    "202611130032_c75_monotone_recipient_conflict_hold.sql.log",
    "202611130033_c76_provider_classification_and_suppression.sql.log",
  ],
};

const mandatorySteps = {
  validate: [
    "C144 migration 034 compatibility and duplicate-prefix guard",
    "TypeScript check",
    "Next.js production build with non-production configuration",
    "Cloudflare packaging build with non-production configuration",
    "Fail closed on high or critical dependency advisories",
  ],
  sprint12_2_database_behavior: ["Run Sprint 12.2 database behavior tests"],
  delivery_reliability_database_behavior: ["Run delivery reliability database behavior tests"],
  gentle_delivery_transport_database_behavior: [
    "Run gentle delivery transport database behavior tests",
    "PostgreSQL synchronized revocation/transport race",
  ],
  auth_pgcrypto_database_behavior: ["Run Auth pgcrypto schema-qualification behavior tests"],
  delivery_migration_order_database_behavior: ["Run migration ordering positive and negative behavior"],
  release_privacy_pg16: [
    "Install exact-source migration chain 001–034",
    "Exercise real anon and authenticated privacy boundaries",
  ],
  release_action_privacy: ["Exercise actual moderation server actions and rendered owner surfaces"],
  release_provider_pg16: ["Exact-commit migrations 019–033, provider security and C77 post-033"],
  release_consent_races: [
    "Exact-head real PostgreSQL sessions, kind isolation, revocation and provider races",
  ],
  release_webhook_http: ["Signed webhooks, provider contract and real synthetic HTTP routing"],
};

const env = process.env;
const root = resolve(env.EVIDENCE_ROOT ?? "release-downloaded");
const platformRoot = resolve(env.PLATFORM_METADATA_DIR ?? "release-platform");
const sha = env.EXPECTED_SHA;
const tree = env.EXPECTED_TREE;
const runId = env.EXPECTED_RUN_ID;
const attemptRaw = env.EXPECTED_RUN_ATTEMPT;
const repo = env.EXPECTED_REPOSITORY;
assert.match(sha ?? "", /^[a-f0-9]{40}$/);
assert.match(tree ?? "", /^[a-f0-9]{40}$/);
assert.match(runId ?? "", /^[1-9]\d{0,19}$/);
assert.match(attemptRaw ?? "", /^[1-9]\d{0,8}$/);
assert.equal(repo, "ADRN-9/deedlight");
const attempt = Number(attemptRaw);

function readBytes(path) {
  assert.equal(lstatSync(path).isFile(), true, "Not a regular evidence file: " + path);
  const bytes = readFileSync(path);
  assert.ok(bytes.length > 0, "Empty evidence: " + path);
  return bytes;
}
function readText(path) { return readBytes(path).toString("utf8"); }
function readJson(path) { return JSON.parse(readText(path)); }
function exactStringSet(actual, expected, label) {
  assert.equal(actual.length, expected.length, label + " count differs");
  assert.deepEqual([...actual].sort(), [...expected].sort(), label + " set differs");
}
function validTime(value, label) {
  const epoch = Date.parse(value ?? "");
  assert.ok(Number.isFinite(epoch) && /^\d{4}-\d\d-\d\dT/.test(value),
    "Invalid " + label);
  return epoch;
}
function hasPassJson(path, keys) {
  const contents = readText(path);
  for (const key of keys) {
    assert.match(contents, new RegExp('"' + key + '"\\s*:\\s*"pass"'),
      "Expected tested pass marker " + key + " in " + path);
  }
}
function assertTap(path, count) {
  const contents = readText(path);
  for (const [key, expected] of [
    ["tests", count], ["pass", count], ["fail", 0],
    ["cancelled", 0], ["skipped", 0], ["todo", 0],
  ]) {
    assert.match(contents, new RegExp("^[#ℹ] " + key + " " + expected + "$", "m"),
      "Incomplete TAP " + key + " in " + path);
  }
}
const results = JSON.parse(env.NEEDS_JSON ?? "{}");
exactStringSet(Object.keys(results), requiredJobs, "GitHub needs dependencies");
for (const name of requiredJobs) {
  assert.equal(results[name]?.result, "success", name + " is not successful");
}

// These records are fetched by the gate itself using a GitHub Actions token with
// actions:read. Producer receipts alone are NOT authoritative run/attempt data.
const platformAttempt = readJson(join(platformRoot, "attempt.json"));
const platformJobs = readJson(join(platformRoot, "jobs.json"));
const platformArtifacts = readJson(join(platformRoot, "artifacts.json"));
assert.equal(platformAttempt.id, Number(runId), "Platform run ID mismatch");
assert.equal(platformAttempt.run_attempt, attempt, "Platform attempt mismatch");
assert.equal(platformAttempt.head_sha, sha, "Platform head commit mismatch");
assert.equal(platformAttempt.repository?.full_name, repo);
const runStart = validTime(platformAttempt.run_started_at, "platform attempt start");
assert.equal(platformJobs.total_count, 12, "Unexpected attempt job count");
assert.equal(platformJobs.jobs?.length, 12, "Incomplete attempt job API response");
exactStringSet(platformJobs.jobs.map((job) => job.name),
  [...requiredJobs, "release_security_gate"], "Attempt job identities");

const jobByName = new Map();
for (const job of platformJobs.jobs) {
  assert.ok(!jobByName.has(job.name), "Duplicate platform job identity");
  assert.equal(job.run_id, Number(runId));
  assert.equal(job.run_attempt, attempt, "A job belongs to a different run attempt");
  assert.equal(job.head_sha, sha);
  const started = validTime(job.started_at, job.name + " start");
  assert.ok(started >= runStart - 3000, "Job predates current attempt");
  if (job.name !== "release_security_gate") {
    assert.equal(job.status, "completed");
    assert.equal(job.conclusion, "success");
    const finished = validTime(job.completed_at, job.name + " completed");
    assert.ok(finished >= started, "Job completed before starting");
    for (const step of mandatorySteps[job.name]) {
      assert.ok(job.steps?.some((x) => x.name === step && x.conclusion === "success"),
        "Required real execution step missing/failed " + job.name + "/" + step);
    }
    const uploadName = [
      "validate", "sprint12_2_database_behavior",
      "delivery_reliability_database_behavior",
      "gentle_delivery_transport_database_behavior",
      "auth_pgcrypto_database_behavior",
      "delivery_migration_order_database_behavior",
    ].includes(job.name)
      ? "Retain " + job.name + " check receipt"
      : job.name === "release_privacy_pg16"
        ? "Preserve sanitized evidence on failure and success"
        : job.name === "release_action_privacy"
          ? "Retain sanitized application-action evidence"
          : "Run actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02";
    assert.ok(job.steps?.some((x) =>
      x.name === uploadName && x.conclusion === "success"),
      "Expected successful artifact upload step missing " + job.name);
  } else {
    assert.equal(job.status, "in_progress", "Gate must audit during its own attempt");
    assert.equal(job.conclusion, null);
  }
  jobByName.set(job.name, job);
}

// This is the FULL run-level artifact set, not a fuzzy download-pattern subset.
// Surviving previous-attempt artifacts deliberately block a rerun: no stale
// evidence is silently substituted, even when its source SHA is identical.
assert.equal(platformArtifacts.total_count, 11,
  "Unexpected or stale matching artifacts: rerun requires fresh, unambiguous run");
assert.equal(platformArtifacts.artifacts?.length, 11,
  "Incomplete artifact API pagination/result");
const expectedNames = requiredJobs.map((name) =>
  "release-evidence-" + name + "-run-" + runId + "-attempt-" + attemptRaw);
exactStringSet(platformArtifacts.artifacts.map((x) => x.name), expectedNames,
  "GitHub artifact identities (no duplicates/substitutes/previous attempts)");
const platformByName = new Map();
const ids = new Set();
const gateStart = validTime(jobByName.get("release_security_gate").started_at, "gate start");
for (const item of platformArtifacts.artifacts) {
  assert.ok(Number.isSafeInteger(item.id) && item.id > 0 && !ids.has(item.id),
    "Invalid/duplicate platform artifact ID");
  ids.add(item.id);
  assert.equal(item.expired, false);
  assert.ok(item.size_in_bytes > 0);
  assert.match(item.digest ?? "", /^sha256:[a-f0-9]{64}$/);
  assert.equal(item.workflow_run?.id, Number(runId));
  assert.equal(item.workflow_run?.head_sha, sha);
  const name = requiredJobs.find((job) =>
    item.name === "release-evidence-" + job + "-run-" + runId + "-attempt-" + attemptRaw);
  assert.ok(name, "Unrecognized platform artifact name");
  const job = jobByName.get(name);
  const created = validTime(item.created_at, "artifact creation");
  assert.ok(created >= runStart - 3000, "Artifact predates attempt");
  assert.ok(created >= validTime(job.started_at, "job start") - 3000,
    "Artifact predates producing job");
  assert.ok(created <= validTime(job.completed_at, "job completed") + 60000,
    "Artifact cannot be tied to producing job completion");
  assert.ok(created <= gateStart, "Artifact created after gate started");
  platformByName.set(item.name, item);
}

exactStringSet(readdirSync(root), expectedNames, "Downloaded artifact directory names");
const hashes = {};
const recorded = [];
for (const job of requiredJobs) {
  const artifactName = "release-evidence-" + job + "-run-" + runId + "-attempt-" + attemptRaw;
  const dir = join(root, artifactName);
  assert.ok(lstatSync(dir).isDirectory() && !lstatSync(dir).isSymbolicLink(),
    "Unsafe evidence directory");
  const expectedReceipt = {
    version: 1,
    repository: repo,
    workflow: "PR Validation",
    job,
    run_id: runId,
    run_attempt: attempt,
    source_sha: sha,
    source_tree: tree,
    artifact_name: artifactName,
  };
  const receipt = readText(join(dir, "receipt.json"));
  assert.equal(receipt, JSON.stringify(expectedReceipt, null, 2) + "\n",
    "Malformed/duplicated/mismatched provenance receipt for " + job);
  assert.equal(readText(join(dir, "commit.txt")).trim(), sha);
  assert.equal(readText(join(dir, "tree.txt")).trim(), tree);
  assert.equal(readText(join(dir, "result.txt")).trim(), "PASS");
  for (const file of ["receipt.json", "commit.txt", "tree.txt", "result.txt",
    ...(requiredFiles[job] ?? [])]) {
    const bytes = readBytes(join(dir, file));
    hashes[job + "/" + file] = createHash("sha256").update(bytes).digest("hex");
  }
  recorded.push({
    job, artifact_id: platformByName.get(artifactName).id,
    artifact_name: artifactName,
    artifact_digest: platformByName.get(artifactName).digest,
    job_id: jobByName.get(job).id, run_id: runId, run_attempt: attempt,
  });
}

const pathFor = (job, file) => join(root,
  "release-evidence-" + job + "-run-" + runId + "-attempt-" + attemptRaw, file);
assert.match(readText(pathFor("release_privacy_pg16", "postgres-version.txt")), /^16\./);
assert.match(readText(pathFor("release_privacy_pg16", "inventory.txt")),
  /RELEASE_PRIVACY_INVENTORY_PASS 64\/64/);
assert.match(readText(pathFor("release_privacy_pg16", "migration-summary.txt")),
  /ALL 001–034 source migrations applied/);
const privacyLog = readText(pathFor("release_privacy_pg16", "privacy.log"));
assert.equal((privacyLog.match(/\{"status": "PASS", "scenario": "[^"]+"\}/g) ?? []).length, 64);
assert.match(privacyLog, /"failed": 0, "passed": 64/);
assert.match(readText(pathFor("release_action_privacy", "inventory.txt")),
  /RELEASE_ACTION_INVENTORY_PASS 19\/19/);
assertTap(pathFor("release_action_privacy", "app-privacy.log"), 19);

assert.match(readText(pathFor("release_provider_pg16", "version.txt")), /^16\./);
assert.match(readText(pathFor("release_provider_pg16", "provider-result.txt")),
  /Synthetic 019–033 provider migration and post-033 tests PASS/);
for (const prefix of ["provider", "post033"]) {
  hasPassJson(pathFor("release_provider_pg16", prefix + "-019-030.log"), [
    "c73_postgresql16_integrated_provider_security", "claim_kind_isolation",
    "identity_conflict_quarantine", "complaint_suppression",
  ]);
  for (const version of ["031", "032", "033"]) {
    assert.match(readText(pathFor("release_provider_pg16", prefix + "-" + version + ".log")),
      /\bCOMMIT\b/, "Incomplete forward migration " + version);
  }
}
hasPassJson(pathFor("release_provider_pg16", "provider-classification.log"), [
  "provider_removal_no_auto_release", "undetermined_hold_survives_success",
  "cross_kind_final_send_denied",
]);
hasPassJson(pathFor("release_provider_pg16", "c77-post033.log"), [
  "unknown_key_version", "guessed_recipient_denied",
]);

assert.match(readText(pathFor("release_consent_races", "c76-kind-logs/concurrency-result.txt")),
  /C76 real two-session Daily\/Weekly claim race.*PASS/);
hasPassJson(pathFor("release_consent_races", "c76-kind-logs/kind-and-lease-regressions.log"), [
  "stale_claim_token_rejected", "expired_lease_kind_isolation",
  "revoked_daily_consent_denied", "revoked_weekly_consent_denied",
  "browser_claim_privilege_denied", "concurrent_daily_weekly_claims",
  "idempotent_delivery_key_preserved",
]);
for (const kind of ["daily", "weekly"]) {
  const log = readText(pathFor("release_consent_races",
    "c76-kind-logs/" + kind + "-transaction.log"));
  assert.match(log, /\bBEGIN\b/);
  assert.match(log, /\bCOMMIT\b/);
}
hasPassJson(pathFor("release_consent_races", "c77-race-logs/assertions.log"), [
  "synthetic_only", "complaint_vs_final_send", "cross_session_postgresql",
  "identity_conflict_vs_retry", "removal_vs_permanent_bounce",
]);
hasPassJson(pathFor("release_consent_races", "c77-race-logs/consent-final.log"), [
  "no_transport_after_revocation", "daily_claim_vs_consent_revocation",
  "weekly_claim_vs_consent_revocation",
]);
assert.match(readText(pathFor("release_consent_races", "c77-race-logs/result.txt")),
  /C77 cross-session provider \+ Daily\/Weekly consent races PASS/);

assertTap(pathFor("release_webhook_http", "signed-webhooks.log"), 6);
assertTap(pathFor("release_webhook_http", "provider-contract.log"), 6);
assert.match(readText(pathFor("release_webhook_http", "source-contract.log")),
  /C73 provider event, webhook and kind-isolation security assertions: PASS/);
hasPassJson(pathFor("release_webhook_http", "http-019-030.log"), [
  "c73_postgresql16_integrated_provider_security",
]);
for (const version of ["031", "032", "033"]) {
  assert.match(readText(pathFor("release_webhook_http",
    "202611130" + version + "_" +
    ({ "031": "c74_legacy_lifecycle_guard", "032": "c75_monotone_recipient_conflict_hold",
      "033": "c76_provider_classification_and_suppression" })[version] + ".sql.log")),
    /\bCOMMIT\b/);
}
assert.match(readText(pathFor("release_webhook_http", "route-http.log")),
  /"c76_end_to_end":"pass","cases":12/);
assert.match(readText(pathFor("release_webhook_http", "route-http.log")),
  /"real_provider_calls":0/);

writeFileSync("release-security-gate-manifest.json", JSON.stringify({
  source_sha: sha, source_tree: tree, repository: repo,
  run_id: runId, run_attempt: attempt,
  trusted_platform_job_count: platformJobs.total_count,
  verified: recorded, inspected_sha256: hashes,
}, null, 2) + "\n");
console.log("RELEASE_SECURITY_GATE_PASS 11/11 current-attempt GitHub jobs and artifacts; " +
  "64/64 SQL, 19/19 application, provider/webhook/race contracts verified; run=" +
  runId + " attempt=" + attemptRaw);
