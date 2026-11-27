import test from "node:test";
import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";

const inventory = JSON.parse(readFileSync("supabase/migration-inventory.json", "utf8"));
const sourcePath = "supabase/migrations/202607260005_sprint5_moderation.sql";
const sourceBytes = readFileSync(sourcePath);
const inventoryItem = inventory.migrations.find(item => item.path === sourcePath);
const sourceLines = sourceBytes.toString("utf8").split(/\r?\n/);
const sourceRange = { startLine: 180, endLine: 188 };
const sourceStatement = sourceLines.slice(sourceRange.startLine - 1, sourceRange.endLine).join("\n");
const hash = value => createHash("sha256").update(value).digest("hex");
const gitBlob = bytes => createHash("sha1").update(Buffer.concat([Buffer.from(`blob ${bytes.length}\0`), bytes])).digest("hex");
const stable = value => Array.isArray(value) ? value.map(stable)
  : value && typeof value === "object" ? Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])])) : value;
const canonical = value => JSON.stringify(stable(value));
const iso = offset => new Date(Date.now() + offset).toISOString();
const db = {
  projectRef: "xaipiovflxomcbfwtwmu",
  environment: "test",
  databaseName: "deedlight_backfill_test",
  serverIdentity: "postgres16-ci-disposable-instance-1",
  serverVersion: "16.2",
};
const approver = generateKeyPairSync("ed25519");
const verifier = generateKeyPairSync("ed25519");
const trustRoots = {
  schemaVersion: 1,
  revokedApprovalIds: [],
  keys: [
    { keyId: "backfill-approver-key", signerId: "independent-backfill-approver", role: "backfill-approver",
      algorithm: "Ed25519", status: "active", notBefore: iso(-86400000), notAfter: iso(86400000), revokedAt: null,
      publicKeyPem: approver.publicKey.export({ type: "spki", format: "pem" }).toString() },
    { keyId: "backfill-verifier-key", signerId: "independent-backfill-verifier", role: "backfill-verifier",
      algorithm: "Ed25519", status: "active", notBefore: iso(-86400000), notAfter: iso(86400000), revokedAt: null,
      publicKeyPem: verifier.publicKey.export({ type: "spki", format: "pem" }).toString() },
  ],
};
process.env.DEEDLIGHT_BACKFILL_TRUST_ROOTS_SHA256 = hash(canonical(trustRoots));
const { validateBackfillExecutionRecord, backfillSha256, backfillGitBlobSha1, canonicalBackfillJson } =
  await import("./backfill-execution-evidence.mjs");

function signedArtifact(kind, signer, key, claims, id) {
  const issuedAt = kind.includes("authorization") ? iso(-30 * 60 * 1000) : iso(-5 * 60 * 1000);
  const expiresAt = iso(3 * 60 * 60 * 1000);
  const boundClaims = kind.includes("authorization")
    ? { ...claims, authorizedAt: issuedAt, expiresAt }
    : { ...claims, verifiedAt: issuedAt };
  const unsigned = {
    schemaVersion: 1, kind, signerId: signer, keyId: kind.includes("authorization")
      ? "backfill-approver-key" : "backfill-verifier-key",
    approvalId: id, issuedAt, expiresAt, claims: boundClaims,
  };
  return { ...unsigned, signature: sign(null, Buffer.from(canonical(unsigned)), key.privateKey).toString("base64") };
}
function resign(record) {
  const core = {
    schemaVersion: record.schemaVersion, kind: record.kind, recordId: record.recordId, executionId: record.executionId,
    sourceIdentity: record.sourceIdentity, databaseIdentity: record.databaseIdentity, execution: record.execution,
    preExecutionState: record.preExecutionState, postExecutionState: record.postExecutionState,
    executionEvidence: record.executionEvidence, provenance: record.provenance,
  };
  const coreDigest = hash(canonical(core));
  record.authorization = signedArtifact("deedlight-backfill-execution-authorization", "independent-backfill-approver", approver,
    { recordId: record.recordId, executionId: record.executionId, sourceIdentity: record.sourceIdentity,
      databaseIdentity: record.databaseIdentity, environment: record.databaseIdentity.environment, coreDigest,
      authorizedBy: "independent-backfill-approver" }, "authorization-" + record.recordId);
  record.verification = signedArtifact("deedlight-backfill-independent-verification", "independent-backfill-verifier", verifier,
    { recordId: record.recordId, executionId: record.executionId, sourceIdentity: record.sourceIdentity,
      databaseIdentity: record.databaseIdentity, coreDigest,
      executionEvidenceSha256: hash(canonical(record.executionEvidence)),
      preExecutionEvidenceSha256: hash(canonical(record.preExecutionState)),
      postExecutionEvidenceSha256: hash(canonical(record.postExecutionState)),
      outcome: record.execution.outcome, result: "PASS",
      verifierIdentity: "independent-backfill-verifier", verifierVersion: "deedlight-backfill-verifier/1.0.0" },
    "verification-" + record.recordId);
}
function fixture() {
  const recordId = "123e4567-e89b-42d3-a456-426614174000";
  const executionId = "123e4567-e89b-42d3-a456-426614174001";
  const statementSha256 = hash(Buffer.from(sourceStatement));
  const sourceIdentity = { path: sourcePath, version: inventoryItem.version, gitBlobSha1: inventoryItem.blobSha1,
    sha256: hash(sourceBytes), sourceRange, statementSha256 };
  const startedAt = iso(-20 * 60 * 1000), completedAt = iso(-15 * 60 * 1000);
  const preExecutionState = {
    observedAt: iso(-25 * 60 * 1000), observerIdentity: "readonly-observer/1.0.0",
    querySha256: hash("SELECT pre-state"), rows: [{ databaseIdentity: db, relation: "public.offerings", observedRows: 25 }],
  };
  preExecutionState.rowsSha256 = hash(canonical(preExecutionState.rows));
  const postExecutionState = {
    observedAt: iso(-10 * 60 * 1000), observerIdentity: "readonly-observer/1.0.0",
    querySha256: hash("SELECT post-state"), rows: [{ databaseIdentity: db, relation: "public.offerings", observedRows: 25 }],
  };
  postExecutionState.rowsSha256 = hash(canonical(postExecutionState.rows));
  const executionEvidence = {
    observedAt: iso(-12 * 60 * 1000), observerIdentity: "database-audit-reader/1.0.0",
    querySha256: hash("SELECT execution audit event"),
    rows: [{
      executionId, sourcePath, sourceBlobSha1: sourceIdentity.gitBlobSha1, databaseIdentity: db,
      outcome: "success", startedAt, completedAt, affectedRows: 25,
      transactionId: "tx-backfill-0001", executorIdentity: "migration-runner/1.0.0",
      commandSha256: statementSha256,
    }],
  };
  executionEvidence.rowsSha256 = hash(canonical(executionEvidence.rows));
  const provenance = {
    collectorIdentity: "independent-readonly-collector", collectorVersion: "1.0.0",
    capturedAt: iso(-8 * 60 * 1000), method: "independent_read_only_database_observation",
  };
  provenance.evidenceBundleSha256 = hash(canonical({ executionEvidence, preExecutionState, postExecutionState }));
  const record = {
    schemaVersion: 1, kind: "deedlight-backfill-execution-evidence", recordId, executionId,
    sourceIdentity, databaseIdentity: db,
    execution: { executionId, startedAt, completedAt, outcome: "success", executorIdentity: "migration-runner/1.0.0",
      commandSha256: statementSha256, transactionId: "tx-backfill-0001", attempt: 1 },
    preExecutionState, postExecutionState, executionEvidence, provenance,
  };
  resign(record);
  return {
    record,
    context: {
      inventory, sourceBytesByPath: new Map([[sourcePath, sourceBytes]]),
      expectedDatabaseIdentity: db, trustRoots,
      replayRegistry: { status: "VERIFIED", databaseIdentity: db, executionIds: [], recordIds: [] },
      now: iso(0),
    },
  };
}
const validate = f => validateBackfillExecutionRecord(f.record, f.context);

test("complete backfill evidence validates structurally but never self-accepts", () => {
  const f = fixture();
  const result = validate(f);
  assert.equal(result.structuralValidation, "PASS", result.problems.join(","));
  assert.equal(result.acceptance, "NOT_ACCEPTED");
  assert.ok(result.blockers.includes("DURABLE_ATOMIC_REPLAY_REGISTRY_NOT_IMPLEMENTED"));
  assert.ok(result.blockers.includes("PRODUCTION_TRUST_ROOTS_NOT_PROVISIONED"));
});

test("missing execution identity fails closed", () => {
  const f = fixture();
  f.record.executionId = "";
  assert.equal(validate(f).structuralValidation, "FAIL");
});

test("altered source bytes and digest fail source identity binding", () => {
  const f = fixture();
  f.context.sourceBytesByPath.set(sourcePath, Buffer.concat([sourceBytes, Buffer.from("-- altered")]));
  assert.ok(validate(f).problems.some(x => x.startsWith("SOURCE:EXACT_INVENTORY_OR_BYTES_MISMATCH")));
});

test("wrong database identity or environment fails cross-database substitution", () => {
  const f = fixture();
  f.record.databaseIdentity = { ...db, databaseName: "another_database" };
  assert.ok(validate(f).problems.some(x => x.startsWith("DATABASE:IDENTITY_OR_ENVIRONMENT_MISMATCH")));
});

test("missing pre-execution state is rejected", () => {
  const f = fixture();
  f.record.preExecutionState = null;
  assert.ok(validate(f).problems.some(x => x.startsWith("PRE_EXECUTION:OBSERVATION_MISSING")));
});

test("failed execution is not accepted", () => {
  const f = fixture();
  f.record.execution.outcome = "failed";
  assert.ok(validate(f).problems.includes("EXECUTION:FAILED_OR_PARTIAL_OUTCOME_NOT_ACCEPTED"));
});

test("partial execution is not accepted", () => {
  const f = fixture();
  f.record.execution.outcome = "partial";
  assert.ok(validate(f).problems.includes("EXECUTION:FAILED_OR_PARTIAL_OUTCOME_NOT_ACCEPTED"));
});

test("missing post-execution evidence is rejected", () => {
  const f = fixture();
  f.record.postExecutionState = null;
  assert.ok(validate(f).problems.some(x => x.startsWith("POST_EXECUTION:OBSERVATION_MISSING")));
});

test("contradictory post-state bytes fail integrity and independent verification binding", () => {
  const f = fixture();
  f.record.postExecutionState.rows[0].observedRows = 999;
  const result = validate(f);
  assert.ok(result.problems.some(x => x.startsWith("POST_EXECUTION:OBSERVATION_MISSING_OR_INTEGRITY_INVALID")));
  assert.ok(result.problems.some(x => x.startsWith("VERIFICATION:INDEPENDENT_VERIFIER_OR_EVIDENCE_BINDING_INVALID")));
});

test("replay of an existing execution identity is rejected", () => {
  const f = fixture();
  f.context.replayRegistry.executionIds.push(f.record.executionId);
  assert.ok(validate(f).problems.includes("REPLAY:EXECUTION_ID_ALREADY_RECORDED"));
});

test("missing verifier authority is rejected", () => {
  const f = fixture();
  f.record.verification = null;
  assert.ok(validate(f).problems.some(x => x.startsWith("deedlight-backfill-independent-verification:ARTIFACT_MISSING")));
});

test("invalid verifier signature is rejected", () => {
  const f = fixture();
  f.record.verification.signature = Buffer.alloc(64).toString("base64");
  assert.ok(validate(f).problems.includes("deedlight-backfill-independent-verification:SIGNATURE_INVALID"));
});

test("missing independent authorization is rejected", () => {
  const f = fixture();
  f.record.authorization = null;
  assert.ok(validate(f).problems.some(x => x.startsWith("deedlight-backfill-execution-authorization:ARTIFACT_MISSING")));
});

test("SQL NULL, quoted-empty and literal backslash-N observations remain distinct", () => {
  const f = fixture();
  const rows = [{ databaseIdentity: db, sqlNull: null, quotedEmpty: "", literalBackslashN: String.raw`\\N` }];
  f.record.preExecutionState.rows = rows;
  f.record.preExecutionState.rowsSha256 = hash(canonical(rows));
  resign(f.record);
  const result = validate(f);
  assert.equal(result.structuralValidation, "PASS", result.problems.join(","));
  assert.equal(rows[0].sqlNull, null);
  assert.equal(rows[0].quotedEmpty, "");
  assert.equal(rows[0].literalBackslashN, "\\N");
});

test("Migration 007 source identities cannot be substituted by version alone", () => {
  const f = fixture();
  const duplicate = inventory.migrations.filter(item => item.version === "202607260007");
  assert.equal(duplicate.length, 2);
  f.record.sourceIdentity = { ...f.record.sourceIdentity, path: duplicate[0].path, version: duplicate[0].version,
    gitBlobSha1: duplicate[1].blobSha1 };
  assert.ok(validate(f).problems.some(x => x.startsWith("SOURCE:EXACT_INVENTORY_OR_BYTES_MISMATCH")));
});

test("unavailable atomic replay registry remains a hard blocker", () => {
  const f = fixture();
  f.context.replayRegistry = null;
  const result = validate(f);
  assert.ok(result.problems.includes("REPLAY:AUTHORITATIVE_DATABASE_SCOPED_REGISTRY_UNAVAILABLE"));
  assert.equal(result.acceptance, "NOT_ACCEPTED");
});
