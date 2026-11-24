import { createHash, createPublicKey, verify as verifySignature } from "node:crypto";
import { closeSync, constants, fstatSync, lstatSync, openSync, realpathSync, readFileSync } from "node:fs";
import path from "node:path";
import { EXPECTED_SIGNATURES, validateProductionOwnerManifest } from "./verify-production-function-owner-manifest.mjs";

const MAX_ARTIFACT_BYTES = 25 * 1024 * 1024;
const ROLE_ATTRIBUTES = Object.freeze([
  "rolsuper", "rolinherit", "rolcreaterole", "rolcreatedb",
  "rolcanlogin", "rolreplication", "rolbypassrls",
]);
const PRIVILEGED_ATTRIBUTES = Object.freeze([
  "rolsuper", "rolcreaterole", "rolcreatedb", "rolreplication", "rolbypassrls",
]);
const APPROVER_ROLES = Object.freeze(["production_dba", "security"]);
const FORBIDDEN_EXECUTION_ROLES = new Set(["postgres", "supabase_admin", "service_role", "supabase_read_only_user"]);

function fail(message) { throw new Error("Production approval bundle rejected: " + message); }
function object(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(label + " must be an object");
  return value;
}
function requiredString(value, label) {
  if (typeof value !== "string" || value.trim() === "") fail(label + " is required");
  return value.trim();
}
function digest(bytes) { return createHash("sha256").update(bytes).digest("hex"); }
function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
  }
  return value;
}
export function canonicalJson(value) { return JSON.stringify(canonicalize(value)); }
function validHash(value, label) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)) fail(label + " must be a lowercase SHA-256 digest");
  return value;
}
function validTimestamp(value, label) {
  requiredString(value, label);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)
      || Number.isNaN(Date.parse(value))) fail(label + " must be an ISO-8601 timestamp with timezone");
  return Date.parse(value);
}
function parseCanonicalJson(bytes, label) {
  let value;
  try { value = JSON.parse(bytes.toString("utf8")); }
  catch { fail(label + " is not valid UTF-8 JSON"); }
  if (canonicalJson(value) !== bytes.toString("utf8")) {
    fail(label + " must use canonical JSON encoding (duplicate keys and alternate encodings are rejected)");
  }
  return value;
}
function safeArtifact(root, relativePath, label) {
  requiredString(relativePath, label + " path");
  if (path.isAbsolute(relativePath) || relativePath.includes("\\") || relativePath.split("/").some((part) => !part || part === "." || part === "..")) {
    fail(label + " path must be a normalized relative path inside the artifact root");
  }
  const rootInfo = lstatSync(root);
  if (!rootInfo.isDirectory() || rootInfo.isSymbolicLink()) fail("artifact root must be a real directory, not a symlink");
  const rootReal = realpathSync(root);
  const parts = relativePath.split("/");
  let current = rootReal;
  for (let index = 0; index < parts.length; index += 1) {
    current = path.join(current, parts[index]);
    const info = lstatSync(current);
    if (info.isSymbolicLink()) fail(label + " path contains a symbolic link");
    if (index < parts.length - 1 && !info.isDirectory()) fail(label + " path parent is not a directory");
    if (index === parts.length - 1 && !info.isFile()) fail(label + " artifact must be a regular file");
  }
  const resolved = realpathSync(current);
  const rel = path.relative(rootReal, resolved);
  if (!rel || rel.startsWith("..") || path.isAbsolute(rel)) fail(label + " path escapes the artifact root");
  const fd = openSync(resolved, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const info = fstatSync(fd);
    if (!info.isFile()) fail(label + " artifact must be a regular file");
    if (info.size > MAX_ARTIFACT_BYTES) fail(label + " exceeds the 25 MiB artifact limit");
    return { path: resolved, bytes: readFileSync(fd) };
  } finally {
    closeSync(fd);
  }
}
function trustedArtifact(trust, relativePath, bytes, label) {
  const expected = trust.artifacts?.[relativePath];
  if (typeof expected !== "string") fail(label + " is absent from the trusted artifact hash index");
  if (digest(bytes) !== validHash(expected, label + " trusted hash")) fail(label + " bytes do not match the trusted artifact hash");
}
function validateEvidenceMetadata(evidence, queryId, root, trust, projectRef, collectorIds) {
  object(evidence, "Query " + queryId + " evidence metadata");
  if (evidence.queryId !== queryId) fail("Query " + queryId + " queryId mismatch");
  if (evidence.projectRef !== projectRef) fail("Query " + queryId + " project reference mismatch");
  if (evidence.querySucceeded !== true || evidence.complete !== true || evidence.truncated !== false) {
    fail("Query " + queryId + " must explicitly attest successful, complete, untruncated execution");
  }
  if (evidence.transactionReadOnly !== true || evidence.roleReadOnly !== true) {
    fail("Query " + queryId + " must attest a read-only transaction and read-only execution role");
  }
  const executionPrincipal = requiredString(evidence.executionPrincipal, "Query " + queryId + " executionPrincipal").toLowerCase();
  if (FORBIDDEN_EXECUTION_ROLES.has(executionPrincipal)) fail("Query " + queryId + " used a forbidden privileged execution principal");
  const collector = requiredString(evidence.collectorIdentity, "Query " + queryId + " collectorIdentity");
  if (!collectorIds.has(collector)) fail("Query " + queryId + " collector is not in the trusted collector registry");
  requiredString(evidence.executionId, "Query " + queryId + " executionId");
  requiredString(evidence.queryVersion, "Query " + queryId + " queryVersion");
  validTimestamp(evidence.executedAt, "Query " + queryId + " executedAt");
  if (!Number.isSafeInteger(evidence.serverVersionNum) || evidence.serverVersionNum < 160000) {
    fail("Query " + queryId + " requires PostgreSQL 16 or newer with an explicit serverVersionNum");
  }
  if (!Number.isSafeInteger(evidence.rowCount) || evidence.rowCount < 0) fail("Query " + queryId + " rowCount is invalid");
  const queryPath = requiredString(evidence.queryPath, "Query " + queryId + " queryPath");
  const resultPath = requiredString(evidence.artifactPath, "Query " + queryId + " artifactPath");
  const queryFile = safeArtifact(root, queryPath, "Query " + queryId + " SQL");
  const resultFile = safeArtifact(root, resultPath, "Query " + queryId + " result");
  trustedArtifact(trust, queryPath, queryFile.bytes, "Query " + queryId + " SQL");
  trustedArtifact(trust, resultPath, resultFile.bytes, "Query " + queryId + " result");
  const queryText = queryFile.bytes.toString("utf8");
  if (queryText.includes("\u0000")) fail("Query " + queryId + " SQL contains a NUL byte");
  if (queryId === "8A" && EXPECTED_SIGNATURES.some((signature) => !queryText.includes(signature))) {
    fail("Query 8A SQL does not contain the exact 18-signature inventory");
  }
  if (queryId === "8B" && ["WITH RECURSIVE", "pg_auth_members", "pg_has_role", "membership_path_role_attributes"]
      .some((fragment) => !queryText.includes(fragment))) {
    fail("Query 8B SQL does not contain the required recursive membership and effective-privilege inventory");
  }
  const queryHash = digest(queryFile.bytes);
  const resultHash = digest(resultFile.bytes);
  if (queryHash !== validHash(evidence.querySha256, "Query " + queryId + " querySha256")) fail("Query " + queryId + " SQL hash mismatch");
  if (resultHash !== validHash(evidence.sha256, "Query " + queryId + " result sha256")) fail("Query " + queryId + " result hash mismatch");
  const rows = parseCanonicalJson(resultFile.bytes, "Query " + queryId + " result");
  if (!Array.isArray(rows) || rows.length !== evidence.rowCount) fail("Query " + queryId + " result row count does not match its actual bytes");
  return { rows, queryHash, resultHash, queryPath, resultPath, collector, executionId: evidence.executionId };
}
function q8aAttributes(row) {
  return {
    rolsuper: row.owner_is_superuser,
    rolinherit: row.owner_role_inherits_memberships,
    rolcreaterole: row.owner_can_create_roles,
    rolcreatedb: row.owner_can_create_databases,
    rolcanlogin: row.owner_can_login,
    rolreplication: row.owner_can_replicate,
    rolbypassrls: row.owner_bypasses_rls,
  };
}
function q8bPath(row) {
  if (!Array.isArray(row.membership_path) || !Array.isArray(row.membership_path_role_attributes)
      || !Array.isArray(row.membership_edge_inherit_options) || !Array.isArray(row.membership_edge_set_options)) {
    fail("Query 8B row is missing its complete path or edge metadata");
  }
  return {
    roles: row.membership_path,
    inheritOptions: row.membership_edge_inherit_options,
    setOptions: row.membership_edge_set_options,
    roleAttributes: row.membership_path_role_attributes,
    effective: {
      member: row.owner_is_member,
      inheritsPrivileges: row.owner_inherits_privileges,
      canSetRole: row.owner_can_set_role,
    },
  };
}
function validateEvidenceRows(manifest, q8a, q8b) {
  if (q8a.rows.length !== EXPECTED_SIGNATURES.length) fail("Query 8A must return exactly 18 rows");
  const owners = new Map();
  const seenSignatures = new Set();
  for (const row of q8a.rows) {
    object(row, "Query 8A row");
    const signature = requiredString(row.expected_identity_signature, "Query 8A expected_identity_signature");
    if (!EXPECTED_SIGNATURES.includes(signature) || seenSignatures.has(signature)) fail("Query 8A has an unexpected or duplicate function signature");
    seenSignatures.add(signature);
    if (row.inventory_status !== "PRESENT" || row.security_definer !== true) fail("Query 8A contains a missing, unresolved or non-SECURITY-DEFINER function");
    const owner = requiredString(row.function_owner, "Query 8A function_owner");
    const attributes = q8aAttributes(row);
    for (const key of ROLE_ATTRIBUTES) if (typeof attributes[key] !== "boolean") fail("Query 8A owner attribute " + key + " is missing or invalid");
    if (owners.has(owner) && canonicalJson(owners.get(owner)) !== canonicalJson(attributes)) fail("Query 8A reports inconsistent attributes for one owner");
    owners.set(owner, attributes);
  }
  if (seenSignatures.size !== EXPECTED_SIGNATURES.length) fail("Query 8A signature inventory is incomplete");
  const expectedOwners = [...owners.keys()].sort();
  if (!Array.isArray(manifest.evidence.query8b.queriedOwnerRoles)
      || canonicalJson([...manifest.evidence.query8b.queriedOwnerRoles].sort()) !== canonicalJson(expectedOwners)) {
    fail("Query 8B queriedOwnerRoles must exactly reconcile every distinct Query 8A owner");
  }
  if (manifest.evidence.query8b.distinctOwnerCount !== expectedOwners.length) fail("Query 8B distinctOwnerCount does not match Query 8A");
  const manifestOwners = new Map(manifest.owners.map((owner) => [owner.role, owner]));
  if (manifestOwners.size !== owners.size || expectedOwners.some((owner) => !manifestOwners.has(owner))) {
    fail("manifest owner records do not exactly reconcile to Query 8A");
  }
  for (const [owner, attributes] of owners) {
    if (canonicalJson(manifestOwners.get(owner).attributes) !== canonicalJson(attributes)) {
      fail("manifest owner attributes do not match actual Query 8A bytes for " + owner);
    }
  }
  const actualPaths = new Map(expectedOwners.map((owner) => [owner, []]));
  for (const row of q8b.rows) {
    object(row, "Query 8B row");
    const owner = requiredString(row.function_owner, "Query 8B function_owner");
    if (!actualPaths.has(owner)) fail("Query 8B contains a path for an owner absent from Query 8A");
    const pathValue = q8bPath(row);
    if (pathValue.roles[0] !== owner) fail("Query 8B path does not start with its function owner");
    actualPaths.get(owner).push(pathValue);
  }
  for (const owner of expectedOwners) {
    const expectedPaths = manifestOwners.get(owner).membershipGraph.paths;
    const actual = actualPaths.get(owner).map(canonicalJson).sort();
    const expected = expectedPaths.map(canonicalJson).sort();
    if (canonicalJson(actual) !== canonicalJson(expected)) fail("manifest membership graph does not match actual Query 8B bytes for " + owner);
  }
  if (q8b.rows.length === 0) {
    const attestation = object(manifest.evidence.query8b.zeroRowsAttestation, "Query 8B zeroRowsAttestation");
    if (attestation.successful !== true || attestation.rowCount !== 0 || attestation.allOwnersQueried !== true) {
      fail("successful zero-row Query 8B requires explicit successful/all-owners/zero-row attestation");
    }
    if (attestation.executionId !== q8b.executionId || attestation.querySha256 !== q8b.queryHash
        || attestation.resultSha256 !== q8b.resultHash || attestation.collectorIdentity !== q8b.collector) {
      fail("Query 8B zero-row attestation is not bound to the actual execution and evidence bytes");
    }
    validTimestamp(attestation.attestedAt, "Query 8B zero-row attestedAt");
    requiredString(attestation.reason, "Query 8B zero-row reason");
  } else if (manifest.evidence.query8b.zeroRowsAttestation !== null) {
    fail("Query 8B zeroRowsAttestation must be null when rows exist");
  }
  if (manifest.evidence.query8a.rowCount !== q8a.rows.length || manifest.evidence.query8b.rowCount !== q8b.rows.length) {
    fail("manifest evidence row counts do not match actual Query 8A/8B bytes");
  }
}
function approvalValueDigest(payload) {
  return createHash("sha256").update(canonicalJson(payload)).digest("hex");
}
function verifyApprovals(approvalsDocument, trust, manifest, manifestDigest, q8aHash, q8bHash, asOf) {
  object(approvalsDocument, "approval artifact");
  if (approvalsDocument.schemaVersion !== 1 || approvalsDocument.projectRef !== manifest.projectRef
      || approvalsDocument.policyVersion !== manifest.policyVersion) fail("approval artifact identity or policy version mismatch");
  if (!Array.isArray(approvalsDocument.approvals)) fail("approval artifact approvals must be an explicit array");
  const keys = new Map();
  const identities = new Map();
  const identityRecords = new Set();
  for (const identity of trust.identities) {
    object(identity, "trusted identity");
    const identityId = requiredString(identity.identityId, "trusted identityId");
    if (identityRecords.has(identityId)) fail("duplicate trusted identityId");
    identityRecords.add(identityId);
    if (typeof identity.active !== "boolean" || !Array.isArray(identity.roles)) fail("trusted identity must explicitly declare active status and roles");
  }
  for (const key of trust.keys) {
    object(key, "trusted key");
    const keyId = requiredString(key.keyId, "trusted keyId");
    if (keys.has(keyId)) fail("duplicate trusted keyId");
    if (key.algorithm !== "Ed25519" || key.active !== true || trust.revokedKeyIds.includes(keyId)) continue;
    const identity = requiredString(key.identityId, "trusted key identityId");
    const publicKeyPem = requiredString(key.publicKeyPem, "trusted publicKeyPem");
    let publicKey;
    try { publicKey = createPublicKey(publicKeyPem); } catch { fail("trusted public key cannot be parsed"); }
    if (publicKey.asymmetricKeyType !== "ed25519") fail("trusted key is not an Ed25519 public key");
    validTimestamp(key.validFrom, "trusted key validFrom");
    validTimestamp(key.validUntil, "trusted key validUntil");
    keys.set(keyId, { identity, publicKey, validFrom: Date.parse(key.validFrom), validUntil: Date.parse(key.validUntil) });
    if (!identities.has(identity)) identities.set(identity, []);
    identities.get(identity).push(keyId);
  }
  if (keys.size === 0) fail("no active supported trusted approval keys are available");
  const seenApprovalIds = new Set();
  const mapped = [];
  for (const envelope of approvalsDocument.approvals) {
    object(envelope, "signed approval envelope");
    const payload = object(envelope.payload, "signed approval payload");
    const approvalId = requiredString(payload.approvalId, "approvalId");
    if (seenApprovalIds.has(approvalId)) fail("approval replay/duplicate approvalId detected");
    seenApprovalIds.add(approvalId);
    if (trust.revokedApprovalIds.includes(approvalId)) fail("approval has been revoked");
    const keyId = requiredString(payload.keyId, "approval keyId");
    const key = keys.get(keyId);
    if (!key) fail("approval references a missing, inactive, revoked or unsupported trusted key");
    if (payload.approverIdentity !== key.identity) fail("approval identity does not match trusted key identity");
    const identity = trust.identities.find((item) => item.identityId === key.identity && item.active === true);
    if (!identity || !identity.roles.includes(payload.approverRole)) fail("approval identity is not trusted for the asserted role");
    if (!APPROVER_ROLES.includes(payload.approverRole)) fail("unsupported approval mechanism or approver role");
    if (payload.projectRef !== manifest.projectRef) fail("individual approval project binding mismatch");
    if (payload.policyVersion !== manifest.policyVersion) fail("individual approval policy-version binding mismatch");
    if (payload.manifestSha256 !== manifestDigest) fail("approval is not bound to the complete immutable manifest digest");
    if (payload.query8aSha256 !== q8aHash || payload.query8bSha256 !== q8bHash) fail("approval evidence hash binding mismatch");
    if (payload.approved !== true) fail("approval must explicitly approve");
    const approvedAt = validTimestamp(payload.approvedAt, "approval approvedAt");
    const expiresAt = validTimestamp(payload.expiresAt, "approval expiresAt");
    if (approvedAt > asOf || expiresAt <= asOf || expiresAt <= approvedAt) fail("approval is expired, not yet valid or has an invalid validity interval");
    if (approvedAt < key.validFrom || expiresAt > key.validUntil || asOf < key.validFrom || asOf > key.validUntil) {
      fail("approval falls outside trusted key validity");
    }
    const signature = requiredString(envelope.signature, "approval signature");
    let signatureBytes;
    try { signatureBytes = Buffer.from(signature, "base64"); } catch { fail("approval signature encoding is invalid"); }
    if (signatureBytes.length !== 64 || signatureBytes.toString("base64") !== signature) fail("approval signature must be canonical Ed25519 base64");
    if (!verifySignature(null, Buffer.from(canonicalJson(payload)), key.publicKey, signatureBytes)) fail("approval signature verification failed");
    const recordSha256 = approvalValueDigest({ payload, signature });
    mapped.push({
      scope: payload.scope, subject: payload.subject, ownerRole: payload.ownerRole,
      projectRef: payload.projectRef, policyVersion: payload.policyVersion,
      query8aSha256: payload.query8aSha256, query8bSha256: payload.query8bSha256,
      approvedValueSha256: payload.approvedValueSha256, approverRole: payload.approverRole,
      approver: payload.approverIdentity, approved: payload.approved, approvedAt: payload.approvedAt,
      recordRef: "approval://" + approvalId, recordSha256,
    });
  }
  return { schemaVersion: 1, projectRef: manifest.projectRef, policyVersion: manifest.policyVersion, approvals: mapped };
}

export function verifyProductionOwnerApprovalBundle({
  rootDir, manifestPath, approvalsPath, trustPath, asOf = new Date().toISOString(),
}) {
  requiredString(rootDir, "artifact root");
  const now = validTimestamp(asOf, "verification asOf");
  const trustFile = safeArtifact(rootDir, trustPath, "trusted identity registry");
  const trust = parseCanonicalJson(trustFile.bytes, "trusted identity registry");
  object(trust, "trusted identity registry");
  if (trust.schemaVersion !== 1 || trust.purpose !== "deedlight-production-owner-approval-trust-root") {
    fail("unsupported or untrusted identity registry format");
  }
  if (!Array.isArray(trust.keys) || !Array.isArray(trust.identities)
      || !Array.isArray(trust.collectors) || !Array.isArray(trust.revokedKeyIds)
      || !Array.isArray(trust.revokedApprovalIds) || !trust.artifacts || typeof trust.artifacts !== "object") {
    fail("trusted identity registry is incomplete");
  }
  const manifestFile = safeArtifact(rootDir, manifestPath, "manifest");
  const manifest = parseCanonicalJson(manifestFile.bytes, "manifest");
  object(manifest, "manifest");
  const manifestDigest = digest(Buffer.from(canonicalJson(manifest)));
  const approvalsFile = safeArtifact(rootDir, approvalsPath, "approval artifact");
  trustedArtifact(trust, approvalsPath, approvalsFile.bytes, "approval artifact");
  const approvalsDocument = parseCanonicalJson(approvalsFile.bytes, "approval artifact");
  if (approvalsDocument.schemaVersion !== 1) fail("unsupported approval artifact schema");
  if (approvalsDocument.projectRef !== manifest.projectRef) fail("approval artifact project substitution detected");
  if (approvalsDocument.policyVersion !== manifest.policyVersion) fail("approval artifact policy substitution detected");
  const collectorIds = new Set(trust.collectors.filter((item) => item && item.active === true).map((item) => item.identityId));
  if (collectorIds.size === 0) fail("trusted collector registry is missing");
  const q8a = validateEvidenceMetadata(manifest.evidence?.query8a, "8A", rootDir, trust, manifest.projectRef, collectorIds);
  const q8b = validateEvidenceMetadata(manifest.evidence?.query8b, "8B", rootDir, trust, manifest.projectRef, collectorIds);
  validateEvidenceRows(manifest, q8a, q8b);
  const mappedApprovals = verifyApprovals(
    approvalsDocument, trust, manifest, manifestDigest, q8a.resultHash, q8b.resultHash, now,
  );
  validateProductionOwnerManifest(manifest, mappedApprovals, manifest.projectRef);
  return {
    valid: true, projectRef: manifest.projectRef, policyVersion: manifest.policyVersion,
    manifestSha256: manifestDigest, query8aSha256: q8a.resultHash, query8bSha256: q8b.resultHash,
    approvalCount: mappedApprovals.approvals.length, functionCount: EXPECTED_SIGNATURES.length,
    distinctOwnerCount: manifest.owners.length, membershipPathCount: q8b.rows.length,
  };
}


if (process.argv[1] && import.meta.url === new URL("file://" + process.argv[1]).href) {
  const args = process.argv.slice(2);
  const value = (name) => {
    const index = args.indexOf(name);
    return index >= 0 ? args[index + 1] : undefined;
  };
  const rootDir = value("--artifact-root");
  const manifestPath = value("--manifest");
  const approvalsPath = value("--approvals");
  const trustPath = value("--trust-root");
  const asOf = value("--as-of") ?? new Date().toISOString();
  if (!rootDir || !manifestPath || !approvalsPath || !trustPath
      || args.some((item, index) => item.startsWith("--") && !["--artifact-root","--manifest","--approvals","--trust-root","--as-of"].includes(item))
      || args.length < 8 || args.length > 10) {
    console.error("Usage: node scripts/verify-production-owner-approval-bundle.mjs --artifact-root <protected-directory> --manifest <relative-manifest.json> --approvals <relative-approvals.json> --trust-root <relative-trust-root.json> [--as-of <ISO-8601>]");
    process.exitCode = 2;
  } else {
    try {
      const result = verifyProductionOwnerApprovalBundle({ rootDir, manifestPath, approvalsPath, trustPath, asOf });
      console.log("Cryptographic Production owner approval and evidence verification PASS:", JSON.stringify(result));
    } catch (error) {
      console.error(error instanceof Error ? error.message : "Production approval bundle verification failed");
      process.exitCode = 1;
    }
  }
}
