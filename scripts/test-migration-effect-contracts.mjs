import assert from "node:assert/strict";
import test from "node:test";
import { createHash } from "node:crypto";
import { strictCategoryTimestamp, validateCategoryEffectContract } from "./migration-effect-contracts.mjs";

const hash = value => createHash("sha256").update(value).digest("hex");
const sourcePath = "supabase/migrations/fixture.sql";
const sourceBlobSha1 = "a".repeat(40);
const inventory = new Map([[sourcePath, sourceBlobSha1]]);
const sourceText = "UPDATE public.offerings SET bless_count = bless_count + 1 WHERE id = 1;";
const sourceRange = { startLine: 1, endLine: 1 };
const sourceStatementSha256 = hash(sourceText);
const base = {
  identity: "fixture.effect",
  fingerprint: "b".repeat(64),
  description: "A synthetic category contract used only by validator tests.",
  sourcePath,
};

test("category contract timestamp accepts canonical UTC and rejects malformed or normalized values", () => {
  assert.equal(strictCategoryTimestamp("2026-11-27T12:34:56.789Z"), true);
  for (const value of [
    "2026-11-27T12:34:56Z",
    "2026-11-27T12:34:56.78Z",
    "2026-11-27T12:34:56.789+00:00",
    "2026-02-30T12:34:56.789Z",
    "2026-11-27 12:34:56.789Z",
    "not-a-timestamp",
    null,
  ]) assert.equal(strictCategoryTimestamp(value), false, String(value));
});

test("transformation contract accepts matching SQL and rejects missing, inconsistent and malformed source relations", () => {
  const effect = {
    ...base,
    contract: {
      operation: "UPDATE",
      sourceRelations: [{ schema: "public", relation: "offerings" }],
      targetRelation: { schema: "public", relation: "offerings" },
      predicate: { sql: "id = 1", sha256: hash("id = 1") },
      sourceRange,
      sourceStatementSha256,
    },
  };
  assert.equal(validateCategoryEffectContract("dataTransformations", effect, inventory, { sourceText }), null);
  const missingSources = structuredClone(effect);
  missingSources.contract.sourceRelations = [];
  assert.match(validateCategoryEffectContract("dataTransformations", missingSources, inventory, { sourceText }), /malformed|source\/target/);
  const wrongOperation = structuredClone(effect);
  wrongOperation.contract.operation = "DELETE";
  assert.match(validateCategoryEffectContract("dataTransformations", wrongOperation, inventory, { sourceText }), /operation does not match/);
  const badRange = structuredClone(effect);
  badRange.contract.sourceRange = { startLine: 0, endLine: 1 };
  assert.match(validateCategoryEffectContract("dataTransformations", badRange, inventory, { sourceText }), /invalid source range/);
  const badPredicate = structuredClone(effect);
  badPredicate.contract.predicate.sha256 = "0".repeat(64);
  assert.match(validateCategoryEffectContract("dataTransformations", badPredicate, inventory, { sourceText }), /predicate is malformed/);
});

test("backfill contract accepts canonical measured evidence and rejects malformed timestamps", () => {
  const effect = {
    ...base,
    contract: {
      targetRelation: { schema: "public", relation: "offerings" },
      predicate: { sql: "id = 1", sha256: hash("id = 1") },
      measurement: {
        status: "independently_measured",
        rowCount: 1,
        querySha256: hash("SELECT count(*) FROM public.offerings WHERE id = 1"),
        evidenceDigest: hash("fixture-result"),
        capturedAt: "2026-11-27T12:34:56.789Z",
        executionId: "fixture-execution",
        sourceBlobSha1,
      },
      sourceRange,
      sourceStatementSha256,
    },
  };
  assert.equal(validateCategoryEffectContract("backfills", effect, inventory, { sourceText }), null);
  for (const capturedAt of ["2026-02-30T12:34:56.789Z", "2026-11-27T12:34:56Z", "2026-11-27T12:34:56.789+00:00"]) {
    const changed = structuredClone(effect);
    changed.contract.measurement.capturedAt = capturedAt;
    assert.match(validateCategoryEffectContract("backfills", changed, inventory, { sourceText }), /independently evidenced/);
  }
});

test("condition verification records the actual predicate result and rejects missing or contradictory outcomes", () => {
  const effect = {
    ...base,
    contract: {
      predicateSql: "SELECT true",
      predicateSha256: hash("SELECT true"),
      expectedOutcome: "true",
      verification: {
        status: "independently_verified",
        observedOutcome: "true",
        predicateSha256: hash("SELECT true"),
        evidenceDigest: hash("fixture-condition-result"),
        querySha256: hash("SELECT true"),
        capturedAt: "2026-11-27T12:34:56.789Z",
        executionId: "fixture-condition-execution",
        sourceBlobSha1,
      },
      sourceRange,
      sourceStatementSha256,
    },
  };
  assert.equal(validateCategoryEffectContract("preconditions", effect, inventory, { sourceText }), null);
  assert.equal(validateCategoryEffectContract("postconditions", effect, inventory, { sourceText }), null);
  const missing = structuredClone(effect);
  delete missing.contract.verification.observedOutcome;
  assert.match(validateCategoryEffectContract("preconditions", missing, inventory, { sourceText }), /independently evidenced/);
  const contradiction = structuredClone(effect);
  contradiction.contract.verification.observedOutcome = "false";
  assert.match(validateCategoryEffectContract("preconditions", contradiction, inventory, { sourceText }), /independently evidenced/);
  const wrongPredicate = structuredClone(effect);
  wrongPredicate.contract.verification.predicateSha256 = "0".repeat(64);
  assert.match(validateCategoryEffectContract("postconditions", wrongPredicate, inventory, { sourceText }), /independently evidenced/);
  const ambiguous = structuredClone(effect);
  ambiguous.contract.verification.observedOutcome = "unknown";
  assert.match(validateCategoryEffectContract("postconditions", ambiguous, inventory, { sourceText }), /independently evidenced/);
});
