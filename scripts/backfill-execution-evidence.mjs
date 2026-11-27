import { createHash, createPublicKey, verify as verifySignature } from "node:crypto";

const TRUST_ROOTS_SHA256 = process.env.DEEDLIGHT_BACKFILL_TRUST_ROOTS_SHA256;
const HEX_256 = /^[a-f0-9]{64}$/;
const HEX_160 = /^[a-f0-9]{40}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const exact = (value, keys) => value !== null && typeof value === "object" && !Array.isArray(value)
  && Object.keys(value).sort().join(",") === [...keys].sort().join(",");
const sha256 = value => createHash("sha256").update(value).digest("hex");
const canonical = value => Array.isArray(value) ? value.map(canonical)
  : value && typeof value === "object"
    ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]))
    : value;
export const canonicalBackfillJson = value => JSON.stringify(canonical(value));
export const backfillSha256 = value => sha256(value);
export const backfillGitBlobSha1 = bytes => createHash("sha1")
  .update(Buffer.concat([Buffer.from(`blob ${bytes.length}\0`), bytes])).digest("hex");

function timestamp(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)
    && value.slice(0, 4) !== "0000" && Number.isFinite(Date.parse(value))
    && new Date(Date.parse(value)).toISOString() === value ? Date.parse(value) : NaN;
}

function verifyArtifact(artifact, kind, role, roots, now, problems) {
  const fields = ["approvalId", "claims", "expiresAt", "issuedAt", "keyId", "kind", "schemaVersion", "signature", "signerId"];
  if (!exact(artifact, fields) || artifact.schemaVersion !== 1 || artifact.kind !== kind
    || !artifact.claims || typeof artifact.claims !== "object" || Array.isArray(artifact.claims)) {
    problems.push(kind + ":ARTIFACT_MISSING_OR_MALFORMED");
    return null;
  }
  const key = (Array.isArray(roots?.keys) ? roots.keys : []).find(candidate => candidate && candidate.keyId === artifact.keyId && candidate.signerId === artifact.signerId);
  if (!key || key.role !== role || key.algorithm !== "Ed25519" || key.status !== "active") {
    problems.push(kind + ":AUTHORITY_MISSING_OR_INVALID");
    return null;
  }
  const notBefore = timestamp(key.notBefore), notAfter = timestamp(key.notAfter);
  if (!Object.hasOwn(key, "revokedAt") || key.revokedAt !== null
    || !Number.isFinite(notBefore) || !Number.isFinite(notAfter) || notAfter <= notBefore
    || now < notBefore || now > notAfter) {
    problems.push(kind + ":TRUST_KEY_INVALID_OR_OUTSIDE_VALIDITY");
    return null;
  }
  const issuedAt = timestamp(artifact.issuedAt), expiresAt = timestamp(artifact.expiresAt);
  if (!artifact.approvalId || roots.revokedApprovalIds.includes(artifact.approvalId)
    || !Number.isFinite(issuedAt) || !Number.isFinite(expiresAt) || issuedAt > now
    || expiresAt <= now || expiresAt <= issuedAt || issuedAt < notBefore || issuedAt > notAfter) {
    problems.push(kind + ":APPROVAL_EXPIRED_REVOKED_OR_INVALID");
    return null;
  }
  try {
    const publicKey = createPublicKey(key.publicKeyPem);
    const signature = Buffer.from(artifact.signature, "base64");
    const unsigned = Object.fromEntries(Object.entries(artifact).filter(([name]) => name !== "signature"));
    if (publicKey.asymmetricKeyType !== "ed25519" || key.publicKeyPem.includes("PRIVATE KEY")
      || signature.length !== 64 || !verifySignature(null, Buffer.from(canonicalBackfillJson(unsigned)), publicKey, signature)) {
      problems.push(kind + ":SIGNATURE_INVALID");
      return null;
    }
  } catch {
    problems.push(kind + ":SIGNATURE_OR_KEY_PARSE_FAILED");
    return null;
  }
  return artifact.claims;
}

function sourceCore(source) {
  return {
    path: source.path, version: source.version, gitBlobSha1: source.gitBlobSha1,
    sha256: source.sha256, sourceRange: source.sourceRange, statementSha256: source.statementSha256,
  };
}

function recordCore(record) {
  return {
    schemaVersion: record.schemaVersion,
    kind: record.kind,
    recordId: record.recordId,
    executionId: record.executionId,
    sourceIdentity: record.sourceIdentity,
    databaseIdentity: record.databaseIdentity,
    execution: record.execution,
    preExecutionState: record.preExecutionState,
    postExecutionState: record.postExecutionState,
    executionEvidence: record.executionEvidence,
    provenance: record.provenance,
  };
}

function validateState(state, label, databaseIdentity, problems) {
  const keys = ["observedAt", "observerIdentity", "querySha256", "rows", "rowsSha256"];
  if (!exact(state, keys) || !Number.isFinite(timestamp(state.observedAt))
    || typeof state.observerIdentity !== "string" || !state.observerIdentity.trim()
    || !HEX_256.test(state.querySha256 || "") || !Array.isArray(state.rows) || state.rows.length === 0
    || !HEX_256.test(state.rowsSha256 || "")
    || sha256(Buffer.from(canonicalBackfillJson(state.rows), "utf8")) !== state.rowsSha256) {
    problems.push(label + ":OBSERVATION_MISSING_OR_INTEGRITY_INVALID");
    return false;
  }
  if (state.observerIdentity.length > 256) problems.push(label + ":OBSERVER_IDENTITY_INVALID");
  for (const row of state.rows) {
    if (!row || typeof row !== "object" || Array.isArray(row)
      || canonicalBackfillJson(row.databaseIdentity) !== canonicalBackfillJson(databaseIdentity)) {
      problems.push(label + ":CROSS_DATABASE_OR_MALFORMED_ROW");
      return false;
    }
  }
  return true;
}

export function validateBackfillExecutionRecord(record, {
  inventory,
  sourceBytesByPath,
  expectedDatabaseIdentity,
  trustRoots,
  replayRegistry,
  now = new Date().toISOString(),
} = {}) {
  const problems = [];
  const blockers = [
    "DURABLE_ATOMIC_REPLAY_REGISTRY_NOT_IMPLEMENTED",
    "MIGRATION_RECONCILIATION_ANALYZER_INTEGRATION_NOT_IMPLEMENTED",
    "PRODUCTION_TRUST_ROOTS_NOT_PROVISIONED",
  ];
  const recordKeys = ["schemaVersion", "kind", "recordId", "executionId", "sourceIdentity", "databaseIdentity",
    "execution", "preExecutionState", "postExecutionState", "executionEvidence", "provenance", "authorization", "verification"];
  if (!exact(record, recordKeys) || record.schemaVersion !== 1 || record.kind !== "deedlight-backfill-execution-evidence") {
    problems.push("RECORD:SCHEMA_OR_EXACT_FIELDS_INVALID");
    return { structuralValidation: "FAIL", acceptance: "NOT_ACCEPTED", problems, blockers };
  }
  const source = record.sourceIdentity;
  const sourceKeys = ["path", "version", "gitBlobSha1", "sha256", "sourceRange", "statementSha256"];
  if (!exact(source, sourceKeys) || typeof source.path !== "string" || !source.path.startsWith("supabase/migrations/")
    || !HEX_160.test(source.gitBlobSha1 || "") || !HEX_256.test(source.sha256 || "")
    || !HEX_256.test(source.statementSha256 || "")
    || !exact(source.sourceRange, ["startLine", "endLine"])
    || !Number.isSafeInteger(source.sourceRange.startLine) || !Number.isSafeInteger(source.sourceRange.endLine)
    || source.sourceRange.startLine < 1 || source.sourceRange.endLine < source.sourceRange.startLine) {
    problems.push("SOURCE:IDENTITY_OR_RANGE_INVALID");
  } else {
    const item = inventory?.migrations?.find(candidate => candidate.path === source.path);
    const bytes = sourceBytesByPath instanceof Map ? sourceBytesByPath.get(source.path) : sourceBytesByPath?.[source.path];
    if (!item || item.version !== source.version || item.blobSha1 !== source.gitBlobSha1
      || !Buffer.isBuffer(bytes) || backfillGitBlobSha1(bytes) !== source.gitBlobSha1
      || sha256(bytes) !== source.sha256) {
      problems.push("SOURCE:EXACT_INVENTORY_OR_BYTES_MISMATCH");
    } else {
      const lines = bytes.toString("utf8").split(/\r?\n/);
      const statement = lines.slice(source.sourceRange.startLine - 1, source.sourceRange.endLine).join("\n");
      if (source.sourceRange.endLine > lines.length || sha256(Buffer.from(statement, "utf8")) !== source.statementSha256) {
        problems.push("SOURCE:STATEMENT_RANGE_DIGEST_MISMATCH");
      }
    }
  }

  const dbKeys = ["projectRef", "environment", "databaseName", "serverIdentity", "serverVersion"];
  if (!exact(record.databaseIdentity, dbKeys) || !exact(expectedDatabaseIdentity, dbKeys)
    || canonicalBackfillJson(record.databaseIdentity) !== canonicalBackfillJson(expectedDatabaseIdentity)
    || !["production", "staging", "development", "test"].includes(record.databaseIdentity?.environment)) {
    problems.push("DATABASE:IDENTITY_OR_ENVIRONMENT_MISMATCH");
  }

  const executionKeys = ["executionId", "startedAt", "completedAt", "outcome", "executorIdentity",
    "commandSha256", "transactionId", "attempt"];
  const startedAt = timestamp(record.execution?.startedAt), completedAt = timestamp(record.execution?.completedAt);
  if (!exact(record.execution, executionKeys) || !UUID.test(record.executionId || "")
    || record.execution.executionId !== record.executionId || !Number.isFinite(startedAt)
    || !Number.isFinite(completedAt) || startedAt >= completedAt
    || !["success", "failed", "partial"].includes(record.execution.outcome)
    || typeof record.execution.executorIdentity !== "string" || !record.execution.executorIdentity.trim()
    || !HEX_256.test(record.execution.commandSha256 || "")
    || record.execution.commandSha256 !== source?.statementSha256
    || typeof record.execution.transactionId !== "string" || !record.execution.transactionId.trim()
    || !Number.isSafeInteger(record.execution.attempt) || record.execution.attempt < 1) {
    problems.push("EXECUTION:IDENTITY_OR_OUTCOME_INVALID");
  } else if (record.execution.outcome !== "success") {
    problems.push("EXECUTION:FAILED_OR_PARTIAL_OUTCOME_NOT_ACCEPTED");
  }

  const preValid = validateState(record.preExecutionState, "PRE_EXECUTION", record.databaseIdentity, problems);
  const postValid = validateState(record.postExecutionState, "POST_EXECUTION", record.databaseIdentity, problems);
  if (preValid && timestamp(record.preExecutionState.observedAt) > startedAt) {
    problems.push("PRE_EXECUTION:OBSERVATION_AFTER_EXECUTION_START");
  }
  if (postValid && timestamp(record.postExecutionState.observedAt) < completedAt) {
    problems.push("POST_EXECUTION:OBSERVATION_BEFORE_EXECUTION_COMPLETION");
  }

  const audit = record.executionEvidence;
  const auditKeys = ["observedAt", "observerIdentity", "querySha256", "rows", "rowsSha256"];
  if (!exact(audit, auditKeys) || !Number.isFinite(timestamp(audit.observedAt))
    || typeof audit.observerIdentity !== "string" || !audit.observerIdentity.trim()
    || !HEX_256.test(audit.querySha256 || "") || !Array.isArray(audit.rows) || audit.rows.length !== 1
    || !HEX_256.test(audit.rowsSha256 || "")
    || sha256(Buffer.from(canonicalBackfillJson(audit.rows), "utf8")) !== audit.rowsSha256) {
    problems.push("EXECUTION_EVIDENCE:OBSERVATION_MISSING_OR_INTEGRITY_INVALID");
  } else {
    const row = audit.rows[0];
    const rowKeys = ["executionId", "sourcePath", "sourceBlobSha1", "databaseIdentity", "outcome",
      "startedAt", "completedAt", "affectedRows", "transactionId", "executorIdentity", "commandSha256"];
    if (!exact(row, rowKeys) || row.executionId !== record.executionId || row.sourcePath !== source?.path
      || row.sourceBlobSha1 !== source?.gitBlobSha1
      || canonicalBackfillJson(row.databaseIdentity) !== canonicalBackfillJson(record.databaseIdentity)
      || row.outcome !== record.execution?.outcome || row.startedAt !== record.execution?.startedAt
      || row.completedAt !== record.execution?.completedAt || row.transactionId !== record.execution?.transactionId
      || row.executorIdentity !== record.execution?.executorIdentity || row.commandSha256 !== record.execution?.commandSha256
      || !Number.isSafeInteger(row.affectedRows) || row.affectedRows < 0) {
      problems.push("EXECUTION_EVIDENCE:CONTRADICTORY_DATABASE_AUDIT_OBSERVATION");
    }
  }

  const provenanceKeys = ["collectorIdentity", "collectorVersion", "capturedAt", "method", "evidenceBundleSha256"];
  const coreDigest = sha256(Buffer.from(canonicalBackfillJson(recordCore(record)), "utf8"));
  const evidenceBundleSha256 = sha256(Buffer.from(canonicalBackfillJson({
    executionEvidence: record.executionEvidence,
    preExecutionState: record.preExecutionState,
    postExecutionState: record.postExecutionState,
  }), "utf8"));
  if (!exact(record.provenance, provenanceKeys) || typeof record.provenance.collectorIdentity !== "string"
    || !record.provenance.collectorIdentity.trim() || typeof record.provenance.collectorVersion !== "string"
    || !record.provenance.collectorVersion.trim() || !Number.isFinite(timestamp(record.provenance.capturedAt))
    || record.provenance.method !== "independent_read_only_database_observation"
    || record.provenance.evidenceBundleSha256 !== evidenceBundleSha256) {
    problems.push("PROVENANCE:CAPTURE_OR_BUNDLE_BINDING_INVALID");
  }

  if (Number.isFinite(timestamp(record.provenance?.capturedAt)) && postValid
    && timestamp(record.provenance.capturedAt) < timestamp(record.postExecutionState.observedAt)) {
    problems.push("PROVENANCE:CAPTURE_PRECEDES_POST_EXECUTION_OBSERVATION");
  }
  if (Number.isFinite(timestamp(audit?.observedAt)) && Number.isFinite(completedAt)
    && timestamp(audit.observedAt) < completedAt) {
    problems.push("EXECUTION_EVIDENCE:AUDIT_OBSERVATION_PRECEDES_EXECUTION_COMPLETION");
  }

  const rootsKeys = ["schemaVersion", "keys", "revokedApprovalIds"];
  if (!exact(trustRoots, rootsKeys) || trustRoots.schemaVersion !== 1 || !Array.isArray(trustRoots.keys)
    || !Array.isArray(trustRoots.revokedApprovalIds) || trustRoots.keys.length !== 2
    || !HEX_256.test(TRUST_ROOTS_SHA256 || "")
    || sha256(Buffer.from(canonicalBackfillJson(trustRoots), "utf8")) !== TRUST_ROOTS_SHA256) {
    problems.push("TRUST:INDEPENDENT_BACKFILL_TRUST_ROOTS_NOT_PROVISIONED_OR_PIN_MISMATCH");
  }
  const roles = new Set(["backfill-approver", "backfill-verifier"]);
  const keyIds = new Set();
  for (const key of (Array.isArray(trustRoots?.keys) ? trustRoots.keys : [])) {
    if (!exact(key, ["algorithm", "keyId", "notAfter", "notBefore", "publicKeyPem", "revokedAt", "role", "signerId", "status"])
      || !roles.has(key.role) || key.algorithm !== "Ed25519" || key.status !== "active"
      || typeof key.keyId !== "string" || !key.keyId || typeof key.signerId !== "string" || !key.signerId
      || typeof key.publicKeyPem !== "string" || key.publicKeyPem.includes("PRIVATE KEY")
      || keyIds.has(key.keyId)) problems.push("TRUST:KEY_BUNDLE_INVALID");
    keyIds.add(key.keyId);
  }
  const nowMs = timestamp(now);
  if (!Number.isFinite(nowMs)) problems.push("CLOCK:NOW_TIMESTAMP_INVALID");
  const authorizationClaims = verifyArtifact(record.authorization, "deedlight-backfill-execution-authorization",
    "backfill-approver", trustRoots || { keys: [], revokedApprovalIds: [] }, nowMs, problems);
  const verificationClaims = verifyArtifact(record.verification, "deedlight-backfill-independent-verification",
    "backfill-verifier", trustRoots || { keys: [], revokedApprovalIds: [] }, nowMs, problems);

  const expectedAuthorization = {
    recordId: record.recordId, executionId: record.executionId, sourceIdentity: sourceCore(source || {}),
    databaseIdentity: record.databaseIdentity, environment: record.databaseIdentity?.environment,
    coreDigest, authorizedBy: record.authorization?.signerId,
    authorizedAt: record.authorization?.claims?.authorizedAt, expiresAt: record.authorization?.claims?.expiresAt,
  };
  const authorizationIssuedAt = timestamp(record.authorization?.issuedAt);
  const authorizationExpiresAt = timestamp(record.authorization?.expiresAt);
  if (!UUID.test(record.recordId || "") || !authorizationClaims
    || canonicalBackfillJson(authorizationClaims) !== canonicalBackfillJson(expectedAuthorization)
    || !Number.isFinite(authorizationIssuedAt) || !Number.isFinite(authorizationExpiresAt)
    || authorizationIssuedAt > startedAt || authorizationExpiresAt < completedAt) {
    problems.push("AUTHORIZATION:NOT_BOUND_TO_EXACT_SOURCE_EXECUTION_AND_DATABASE");
  }
  const expectedVerification = {
    recordId: record.recordId, executionId: record.executionId, sourceIdentity: sourceCore(source || {}),
    databaseIdentity: record.databaseIdentity, coreDigest,
    executionEvidenceSha256: sha256(Buffer.from(canonicalBackfillJson(record.executionEvidence), "utf8")),
    preExecutionEvidenceSha256: sha256(Buffer.from(canonicalBackfillJson(record.preExecutionState), "utf8")),
    postExecutionEvidenceSha256: sha256(Buffer.from(canonicalBackfillJson(record.postExecutionState), "utf8")),
    outcome: record.execution?.outcome, result: "PASS",
    verifierIdentity: record.verification?.signerId, verifierVersion: record.verification?.claims?.verifierVersion,
    verifiedAt: record.verification?.claims?.verifiedAt,
  };
  const verifierIssuedAt = timestamp(record.verification?.issuedAt);
  if (!verificationClaims || canonicalBackfillJson(verificationClaims) !== canonicalBackfillJson(expectedVerification)
    || !Number.isFinite(verifierIssuedAt) || !postValid || verifierIssuedAt < timestamp(record.postExecutionState.observedAt)
    || typeof verificationClaims.verifierVersion !== "string" || !verificationClaims.verifierVersion.trim()
    || record.verification?.signerId === record.execution?.executorIdentity
    || record.authorization?.signerId === record.verification?.signerId
    || record.authorization?.signerId === record.execution?.executorIdentity) {
    problems.push("VERIFICATION:INDEPENDENT_VERIFIER_OR_EVIDENCE_BINDING_INVALID");
  }

  if (replayRegistry?.status !== "VERIFIED" || !Array.isArray(replayRegistry.executionIds)
    || !Array.isArray(replayRegistry.recordIds)
    || canonicalBackfillJson(replayRegistry.databaseIdentity) !== canonicalBackfillJson(record.databaseIdentity)) {
    problems.push("REPLAY:AUTHORITATIVE_DATABASE_SCOPED_REGISTRY_UNAVAILABLE");
  } else {
    if (replayRegistry.executionIds.includes(record.executionId)) problems.push("REPLAY:EXECUTION_ID_ALREADY_RECORDED");
    if (replayRegistry.recordIds.includes(record.recordId)) problems.push("REPLAY:RECORD_ID_ALREADY_RECORDED");
  }
  if (record.authorization?.claims?.authorizedBy === record.verification?.signerId) {
    problems.push("AUTHORIZATION:APPROVER_AND_VERIFIER_MUST_BE_DISTINCT");
  }

  const uniqueActors = new Set([record.execution?.executorIdentity, record.authorization?.signerId, record.verification?.signerId]);
  if (uniqueActors.size !== 3) problems.push("SEPARATION_OF_DUTIES:EXECUTOR_APPROVER_VERIFIER_MUST_BE_DISTINCT");
  return {
    structuralValidation: problems.length === 0 ? "PASS" : "FAIL",
    acceptance: "NOT_ACCEPTED",
    problems,
    blockers,
    recordId: record.recordId,
    executionId: record.executionId,
    sourceIdentity: sourceCore(source || {}),
    databaseIdentity: record.databaseIdentity,
    executionOutcome: record.execution?.outcome ?? "UNKNOWN",
    replayChecked: replayRegistry?.status === "VERIFIED",
  };
}
