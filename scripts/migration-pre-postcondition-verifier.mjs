import { createHash, createPublicKey, verify as verifySignature } from "node:crypto";
import { canonicalBackfillJson, validateBackfillExecutionRecord } from "./backfill-execution-evidence.mjs";

const HEX_256 = /^[a-f0-9]{64}$/;
const sha256 = value => createHash("sha256").update(value).digest("hex");
const digest = value => sha256(Buffer.from(canonicalBackfillJson(value), "utf8"));
const exact = (value, keys) => value !== null && typeof value === "object" && !Array.isArray(value)
  && Object.keys(value).sort().join(",") === [...keys].sort().join(",");
const timestamp = value => typeof value === "string" && Number.isFinite(Date.parse(value))
  && new Date(Date.parse(value)).toISOString() === value ? Date.parse(value) : NaN;
const sourceKeys = ["path", "version", "gitBlobSha1", "sha256", "sourceRange", "statementSha256"];
const dbKeys = ["projectRef", "environment", "databaseName", "serverIdentity", "serverVersion"];

function observation(state, key) {
  if (!Array.isArray(state?.rows) || state.rows.length !== 1) return { found: false };
  const facts = state.rows[0]?.facts;
  if (!facts || typeof facts !== "object" || Array.isArray(facts) || !Object.hasOwn(facts, key)) return { found: false };
  return { found: true, value: facts[key] };
}

function evaluateConditions(conditions, state, phase, problems) {
  if (!Array.isArray(conditions) || conditions.length === 0) {
    problems.push(phase + ":EXPECTED_CONDITIONS_MISSING");
    return [];
  }
  const ids = new Set();
  return conditions.map(condition => {
    if (!exact(condition, ["id", "observation", "operator", "expected"])
      || typeof condition.id !== "string" || !condition.id.trim() || ids.has(condition.id)
      || typeof condition.observation !== "string" || !condition.observation.trim()
      || condition.operator !== "equals" && condition.operator !== "not_equals") {
      problems.push(phase + ":CONDITION_INVALID_OR_UNSUPPORTED");
      return { id: condition?.id ?? null, result: "FAIL", reason: "INVALID_OR_UNSUPPORTED_CONDITION" };
    }
    ids.add(condition.id);
    const actual = observation(state, condition.observation);
    if (!actual.found) {
      problems.push(phase + ":OBSERVATION_MISSING:" + condition.id);
      return { id: condition.id, observation: condition.observation, expected: condition.expected, result: "FAIL", reason: "OBSERVATION_MISSING" };
    }
    const equal = canonicalBackfillJson(actual.value) === canonicalBackfillJson(condition.expected);
    const passed = condition.operator === "equals" ? equal : !equal;
    if (!passed) problems.push(phase + ":PRECONDITION_OR_POSTCONDITION_MISMATCH:" + condition.id);
    return { id: condition.id, observation: condition.observation, operator: condition.operator,
      expected: condition.expected, observed: actual.value, result: passed ? "PASS" : "FAIL" };
  });
}

function evaluateRelationships(relationships, preState, postState, problems) {
  if (!Array.isArray(relationships)) {
    problems.push("RELATIONSHIPS:INVALID");
    return [];
  }
  const ids = new Set();
  return relationships.map(relationship => {
    if (!exact(relationship, ["id", "observation", "operator", "expectedDelta"])
      || typeof relationship.id !== "string" || !relationship.id.trim() || ids.has(relationship.id)
      || typeof relationship.observation !== "string" || !relationship.observation.trim()
      || relationship.operator !== "integer_delta_equals" || !Number.isSafeInteger(relationship.expectedDelta)) {
      problems.push("RELATIONSHIPS:UNSUPPORTED_OR_INVALID_SEMANTIC_RELATIONSHIP");
      return { id: relationship?.id ?? null, result: "FAIL", reason: "UNSUPPORTED_OR_INVALID_RELATIONSHIP" };
    }
    ids.add(relationship.id);
    const before = observation(preState, relationship.observation);
    const after = observation(postState, relationship.observation);
    if (!before.found || !after.found || !Number.isSafeInteger(before.value) || !Number.isSafeInteger(after.value)) {
      problems.push("RELATIONSHIPS:OBSERVATION_MISSING_OR_NON_INTEGER:" + relationship.id);
      return { id: relationship.id, result: "FAIL", reason: "OBSERVATION_MISSING_OR_NON_INTEGER" };
    }
    const actualDelta = after.value - before.value;
    const passed = actualDelta === relationship.expectedDelta;
    if (!passed) problems.push("RELATIONSHIPS:EXPECTED_DELTA_MISMATCH:" + relationship.id);
    return { id: relationship.id, observation: relationship.observation, expectedDelta: relationship.expectedDelta,
      observedDelta: actualDelta, result: passed ? "PASS" : "FAIL" };
  });
}

function verifyConditionAttestation(attestation, trustRoots, now, expected, problems) {
  const fields = ["schemaVersion", "kind", "signerId", "keyId", "issuedAt", "expiresAt", "claims", "signature"];
  if (!exact(attestation, fields) || attestation.schemaVersion !== 1
    || attestation.kind !== "deedlight-migration-pre-postcondition-verification"
    || !attestation.claims || typeof attestation.claims !== "object" || Array.isArray(attestation.claims)) {
    problems.push("VERIFIER:ATTESTATION_MISSING_OR_MALFORMED");
    return false;
  }
  const key = Array.isArray(trustRoots?.keys)
    ? trustRoots.keys.find(item => item?.keyId === attestation.keyId && item?.signerId === attestation.signerId) : null;
  if (!key || key.role !== "backfill-verifier" || key.algorithm !== "Ed25519" || key.status !== "active"
    || key.revokedAt !== null) {
    problems.push("VERIFIER:AUTHORITY_MISSING_OR_INVALID");
    return false;
  }
  const issued = timestamp(attestation.issuedAt), expires = timestamp(attestation.expiresAt);
  const keyStart = timestamp(key.notBefore), keyEnd = timestamp(key.notAfter);
  if (![issued, expires, keyStart, keyEnd, now].every(Number.isFinite)
    || issued > now || expires <= now || expires <= issued || issued < keyStart || issued > keyEnd
    || now < keyStart || now > keyEnd) {
    problems.push("VERIFIER:AUTHORITY_EXPIRED_OR_TIME_INVALID");
    return false;
  }
  try {
    const publicKey = createPublicKey(key.publicKeyPem);
    const signature = Buffer.from(attestation.signature, "base64");
    const unsigned = Object.fromEntries(Object.entries(attestation).filter(([name]) => name !== "signature"));
    if (publicKey.asymmetricKeyType !== "ed25519" || signature.length !== 64
      || !verifySignature(null, Buffer.from(canonicalBackfillJson(unsigned)), publicKey, signature)) {
      problems.push("VERIFIER:SIGNATURE_INVALID");
      return false;
    }
  } catch {
    problems.push("VERIFIER:SIGNATURE_OR_KEY_PARSE_FAILED");
    return false;
  }
  if (canonicalBackfillJson(attestation.claims) !== canonicalBackfillJson(expected)) {
    problems.push("VERIFIER:SIGNED_RESULTS_OR_EVIDENCE_BINDING_MISMATCH");
    return false;
  }
  return true;
}

export function validateMigrationPrePostconditions({
  executionRecord, contract, conditionVerification,
}, context = {}) {
  const problems = [];
  const base = validateBackfillExecutionRecord(executionRecord, context);
  if (base.structuralValidation !== "PASS") problems.push("EXECUTION_RECORD:BASE_EVIDENCE_INVALID");
  const contractKeys = ["schemaVersion", "kind", "contractId", "sourceIdentity", "databaseIdentity",
    "preconditions", "postconditions", "relationships"];
  if (!exact(contract, contractKeys) || contract.schemaVersion !== 1
    || contract.kind !== "deedlight-migration-pre-postcondition-contract"
    || typeof contract.contractId !== "string" || !contract.contractId.trim()
    || !exact(contract.sourceIdentity, sourceKeys) || !exact(contract.databaseIdentity, dbKeys)
    || canonicalBackfillJson(contract.sourceIdentity) !== canonicalBackfillJson(executionRecord?.sourceIdentity)
    || canonicalBackfillJson(contract.databaseIdentity) !== canonicalBackfillJson(executionRecord?.databaseIdentity)) {
    problems.push("CONTRACT:SOURCE_DATABASE_OR_SCHEMA_BINDING_INVALID");
  }
  const preconditionResults = evaluateConditions(contract?.preconditions, executionRecord?.preExecutionState, "PRECONDITIONS", problems);
  const postconditionResults = evaluateConditions(contract?.postconditions, executionRecord?.postExecutionState, "POSTCONDITIONS", problems);
  const relationshipResults = evaluateRelationships(contract?.relationships, executionRecord?.preExecutionState,
    executionRecord?.postExecutionState, problems);
  const execution = executionRecord?.execution;
  if (!execution || execution.outcome !== "success" || execution.executionId !== executionRecord?.executionId
    || executionRecord?.executionEvidence?.rows?.[0]?.executionId !== executionRecord?.executionId) {
    problems.push("EXECUTION:IDENTITY_OUTCOME_OR_COMPLETION_NOT_VERIFIED");
  }
  const expectedClaims = {
    contractId: contract?.contractId,
    contractSha256: digest(contract),
    executionId: executionRecord?.executionId,
    sourceIdentity: executionRecord?.sourceIdentity,
    databaseIdentity: executionRecord?.databaseIdentity,
    executionOutcome: execution?.outcome,
    preExecutionEvidenceSha256: digest(executionRecord?.preExecutionState),
    postExecutionEvidenceSha256: digest(executionRecord?.postExecutionState),
    preconditionResults,
    postconditionResults,
    relationshipResults,
    result: problems.length === 0 ? "PASS" : "FAIL",
    verifierIdentity: conditionVerification?.signerId,
    verifierVersion: conditionVerification?.claims?.verifierVersion,
  };
  const roots = context.trustRoots;
  const rootDigest = process.env.DEEDLIGHT_BACKFILL_TRUST_ROOTS_SHA256;
  if (!exact(roots, ["schemaVersion", "keys", "revokedApprovalIds"]) || roots.schemaVersion !== 1
    || !Array.isArray(roots.keys) || !Array.isArray(roots.revokedApprovalIds) || !HEX_256.test(rootDigest || "")
    || sha256(Buffer.from(canonicalBackfillJson(roots), "utf8")) !== rootDigest) {
    problems.push("TRUST:PINNED_VERIFIER_TRUST_ROOTS_UNAVAILABLE");
  }
  const attestationValid = verifyConditionAttestation(conditionVerification, roots,
    timestamp(context.now ?? new Date().toISOString()), expectedClaims, problems);
  const verifierVersion = conditionVerification?.claims?.verifierVersion;
  if (typeof verifierVersion !== "string" || !verifierVersion.trim()
    || !Number.isFinite(timestamp(conditionVerification?.issuedAt))
    || timestamp(conditionVerification.issuedAt) < timestamp(executionRecord?.postExecutionState?.observedAt)
    || conditionVerification?.signerId === executionRecord?.execution?.executorIdentity
    || conditionVerification?.signerId === executionRecord?.authorization?.signerId
    || conditionVerification?.signerId === executionRecord?.provenance?.collectorIdentity) {
    problems.push("VERIFIER:IDENTITY_VERSION_OR_POST_OBSERVATION_TIME_INVALID");
  }
  const accepted = problems.length === 0 && attestationValid
    && preconditionResults.every(item => item.result === "PASS")
    && postconditionResults.every(item => item.result === "PASS")
    && relationshipResults.every(item => item.result === "PASS");
  return {
    verification: accepted ? "PASS" : "FAIL",
    acceptance: "NOT_ACCEPTED",
    preconditionResults, postconditionResults, relationshipResults,
    verifierIdentity: conditionVerification?.signerId ?? "UNKNOWN",
    verifierVersion: verifierVersion ?? "UNKNOWN",
    evidenceProvenance: executionRecord?.provenance?.collectorIdentity ?? "UNKNOWN",
    problems,
    blockers: [...(base.blockers ?? []), "DURABLE_ATOMIC_REPLAY_REGISTRY_NOT_IMPLEMENTED",
      "PRODUCTION_DATABASE_OBSERVATION_AND_VERIFIER_AUTHORITY_NOT_ESTABLISHED"],
  };
}
