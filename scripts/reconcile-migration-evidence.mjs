import { createHash, createPublicKey, verify as verifySignature } from "node:crypto";
import { lstatSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { gitBlobSha1, validateInventory } from "./verify-migration-inventory-aggregate.mjs";
import { categoryEffectKeys, validateCategoryEffectContract } from "./migration-effect-contracts.mjs";

const PROJECT_REF = "xaipiovflxomcbfwtwmu";
const INVENTORY_BLOB_SHA1 = "4e63f31368d446e905f4f44565be73337c7188fb";
const MAX_EVIDENCE_AGE_MS = 24 * 60 * 60 * 1000;
const PROVISIONED_TRUST_ROOTS_SHA256 = process.env.DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256;
const CATEGORIES = ["schema", "privileges", "ownership", "routines", "dataTransformations", "backfills", "dependencies", "preconditions", "postconditions"];
const CATALOG_KINDS = ["schemas", "tables", "sequences", "columns", "constraints", "indexes", "triggers", "policies", "routines", "privileges", "ownership", "dataTransformations", "backfills", "dependencies", "preconditions", "postconditions"];
const PRIVILEGE_OBJECT_KINDS = new Set(["tables", "sequences", "routines"]);
const REQUIRED_ACCESS_SUMMARY = ["DATABASE_CONNECT", "SYSTEM_CATALOG_SELECT", "MIGRATION_HISTORY_SCHEMA_USAGE", "MIGRATION_HISTORY_SELECT"];
const SCHEMA_KINDS = new Set(["tables", "columns", "constraints", "indexes", "triggers", "policies"]);
export const SQL_NULL_SENTINEL = "__DEEDLIGHT_SQL_NULL_V1__";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  }
  return value;
}
export function canonicalJson(value) {
  const encoded = JSON.stringify(canonical(value));
  return encoded === undefined ? "null" : encoded;
}
export function validateCollectorPrivilegeEvidence(db, inventoryObjects) {
  const problems = [];
  if (!db || db.privilegeContractVersion !== "catalog_only_v1") {
    problems.push("collector privilege evidence contract version is missing or unsupported");
  }
  if (db && Object.hasOwn(db, "effectivePrivileges")) {
    problems.push("legacy flattened effectivePrivileges is not accepted; scoped privilege evidence is required");
  }
  if (!Array.isArray(db && db.requiredAccessSummary)
    || canonicalJson(db.requiredAccessSummary) !== canonicalJson(REQUIRED_ACCESS_SUMMARY)) {
    problems.push("collector required-access summary does not match the catalog-only privilege contract");
  }
  if (!Array.isArray(db && db.databasePrivileges)
    || db.databasePrivileges.length !== 1 || db.databasePrivileges[0] !== "CONNECT") {
    problems.push("collector database-level privilege export is incomplete or not read-only");
  }
  if (!Array.isArray(db && db.catalogPrivileges)
    || db.catalogPrivileges.length !== 1 || db.catalogPrivileges[0] !== "SELECT") {
    problems.push("collector catalog read privileges are not completely attested");
  }
  const inventory = Array.isArray(inventoryObjects) ? inventoryObjects : [];
  const expectedSchemas = inventory.filter((entry) => entry && entry.kind === "schemas").map((entry) => entry.identity).sort();
  const expectedObjects = inventory.filter((entry) => entry && PRIVILEGE_OBJECT_KINDS.has(entry.kind))
    .map((entry) => ({ kind: entry.kind, identity: entry.identity }))
    .sort((a, b) => String(a.kind).localeCompare(String(b.kind)) || String(a.identity).localeCompare(String(b.identity)));
  const schemaRows = Array.isArray(db && db.schemaPrivileges) ? db.schemaPrivileges : [];
  const objectRows = Array.isArray(db && db.objectPrivileges) ? db.objectPrivileges : [];
  const columnRows = Array.isArray(db && db.columnPrivileges) ? db.columnPrivileges : [];
  const schemaIds = schemaRows.map((entry) => entry && entry.schema).sort();
  const objectKeys = objectRows.map((entry) => ({ kind: entry && entry.kind, identity: entry && entry.identity }))
    .sort((a, b) => String(a.kind).localeCompare(String(b.kind)) || String(a.identity).localeCompare(String(b.identity)));
  if (!expectedSchemas.length || schemaIds.some((value) => typeof value !== "string")
    || new Set(schemaIds).size !== schemaIds.length || canonicalJson(schemaIds) !== canonicalJson(expectedSchemas)
    || schemaRows.some((entry) => {
      if (!entry) return true;
      const history = entry.schema === "supabase_migrations";
      return Object.keys(entry).sort().join(",") !== "privileges,schema,scope"
        || entry.scope !== (history ? "migration_history" : "application_data")
        || !Array.isArray(entry.privileges)
        || canonicalJson(entry.privileges) !== canonicalJson(history ? ["USAGE"] : []);
    })) {
    problems.push("collector schema privilege evidence does not match the least-privilege contract: only supabase_migrations USAGE is allowed");
  }
  if (!expectedObjects.length || objectKeys.some((entry) => typeof entry.kind !== "string" || typeof entry.identity !== "string")
    || new Set(objectKeys.map((entry) => canonicalJson([entry.kind, entry.identity]))).size !== objectKeys.length
    || canonicalJson(objectKeys) !== canonicalJson(expectedObjects)
    || objectRows.some((entry) => {
      if (!entry) return true;
      const history = entry.kind === "tables" && entry.identity === "supabase_migrations.schema_migrations";
      return Object.keys(entry).sort().join(",") !== "identity,kind,privileges,scope"
        || entry.scope !== (history ? "migration_history" : "application_data")
        || !Array.isArray(entry.privileges)
        || canonicalJson(entry.privileges) !== canonicalJson(history ? ["SELECT"] : []);
    })) {
    problems.push("collector object privilege evidence does not match the least-privilege contract: only migration-history SELECT is allowed");
  }
  const expectedColumns = inventory.filter((entry) => entry && entry.kind === "columns");
  const expectedColumnKeys = expectedColumns.map((entry) => {
    if ([entry.schema, entry.relation, entry.column].some((value) => typeof value !== "string" || !value.length)
      || entry.identity !== [entry.schema, entry.relation, entry.column].join(".")) return null;
    return canonicalJson([entry.schema, entry.relation, entry.column]);
  });
  const columnKeys = columnRows.map((entry) => entry && canonicalJson([entry.schema, entry.relation, entry.column]));
  if (!expectedColumns.length || expectedColumnKeys.some((value) => value === null)
    || columnKeys.some((value) => typeof value !== "string")
    || new Set(expectedColumnKeys).size !== expectedColumnKeys.length
    || new Set(columnKeys).size !== columnKeys.length
    || canonicalJson([...columnKeys].sort()) !== canonicalJson([...expectedColumnKeys].sort())
    || columnRows.some((entry) => {
      if (!entry || Object.keys(entry).sort().join(",") !== "column,privileges,relation,schema,scope"
        || [entry.schema, entry.relation, entry.column].some((value) => typeof value !== "string" || !value.length)) return true;
      const history = entry.schema === "supabase_migrations" && entry.relation === "schema_migrations";
      return entry.scope !== (history ? "migration_history" : "application_data")
        || !Array.isArray(entry.privileges)
        || canonicalJson(entry.privileges) !== canonicalJson(history ? ["SELECT"] : []);
    })) {
    problems.push("collector column privilege evidence does not match the least-privilege contract: structured schema/relation/column identities must exactly match inventory and only migration-history SELECT is allowed");
  }
  return problems;
}
export function evidencePayload(evidence) {
  return Buffer.from(canonicalJson(evidence));
}
export function mappingDigest(mapping) {
  return sha256(Buffer.from(canonicalJson(mapping)));
}
// Require canonical UTC RFC 3339 timestamps with millisecond precision; reject coercion and calendar normalization.
export function strictTimestamp(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)
    || value.slice(0, 4) === "0000") return NaN;
  const time = Date.parse(value);
  if (!Number.isFinite(time)) return NaN;
  try {
    return new Date(time).toISOString() === value ? time : NaN;
  } catch {
    return NaN;
  }
}
function parseTime(value, label, reasons) {
  const time = strictTimestamp(value);
  if (!Number.isFinite(time)) reasons.push(label + " must be a canonical UTC timestamp in years 0001–9999 (YYYY-MM-DDTHH:mm:ss.sssZ)");
  return time;
}
function readRegularFile(rootDir, relativePath) {
  const root = path.resolve(rootDir);
  const absolute = path.resolve(root, relativePath);
  assert(absolute.startsWith(root + path.sep), "migration source path escapes repository root");
  const stat = lstatSync(absolute);
  assert(stat.isFile() && !stat.isSymbolicLink(), "migration source must be a regular non-symlink file: " + relativePath);
  assert(realpathSync(absolute).startsWith(realpathSync(root) + path.sep), "migration source resolves outside repository: " + relativePath);
  return readFileSync(absolute);
}
function validateSourceInventory(rootDir, manifest) {
  validateInventory(manifest);
  const inventoryBytes = readRegularFile(rootDir, "supabase/migration-inventory.json");
  assert(gitBlobSha1(inventoryBytes) === INVENTORY_BLOB_SHA1, "pinned inventory manifest fingerprint mismatch");
  const migrationDir = path.join(rootDir, "supabase/migrations");
  const entries = readdirSync(migrationDir, { withFileTypes: true });
  assert(!entries.some((entry) => entry.isSymbolicLink()), "migration directory contains a symlink");
  const actualSql = entries.filter((entry) => entry.isFile() && entry.name.endsWith(".sql")).map((entry) => entry.name).sort();
  const expectedSql = manifest.migrations.map((item) => path.basename(item.path)).sort();
  assert(JSON.stringify(actualSql) === JSON.stringify(expectedSql), "migration source directory has missing or unexpected SQL files");
  const source = new Map();
  for (const item of manifest.migrations) {
    const bytes = readRegularFile(rootDir, item.path);
    const actual = gitBlobSha1(bytes);
    source.set(item.path, actual === item.blobSha1 && bytes.length === item.byteLength
      ? { valid: true, blobSha1: actual, lineCount: bytes.toString("utf8").split(/\r?\n/).length, content: bytes.toString("utf8") }
      : { valid: false, reason: "source fingerprint or byte length differs from pinned inventory", actualBlobSha1: actual });
  }
  return source;
}
export function normalizeMigrationHistoryRows(tuples) {
  assert(Array.isArray(tuples), "migration-history SQL output must be an array of rows");
  return tuples.map((tuple, index) => {
    assert(Array.isArray(tuple) && tuple.length === 3,
      "migration-history SQL row " + index + " must contain exactly version, name and recorded statement count");
    const [version, rawName, rawCount] = tuple;
    assert(typeof version === "string" && /^[0-9]{12}$/.test(version),
      "migration-history SQL row " + index + " has an invalid version");
    assert(rawName === null || typeof rawName === "string",
      "migration-history SQL row " + index + " has an invalid name type");
    const name = rawName === SQL_NULL_SENTINEL || rawName === null ? null : rawName;
    let recordedStatementCount = null;
    if (rawCount === "" || rawCount === null || rawCount === "NULL" || rawCount === SQL_NULL_SENTINEL) recordedStatementCount = null;
    else if (typeof rawCount === "string" && /^(0|[1-9][0-9]*)$/.test(rawCount)) recordedStatementCount = Number(rawCount);
    assert(rawCount === "" || rawCount === null || rawCount === "NULL" || rawCount === SQL_NULL_SENTINEL || (typeof rawCount === "string" && /^(0|[1-9][0-9]*)$/.test(rawCount)),
      "migration-history SQL row " + index + " has a noncanonical recorded statement count");
    assert(recordedStatementCount === null || (Number.isSafeInteger(recordedStatementCount) && recordedStatementCount >= 0),
      "migration-history SQL row " + index + " has an invalid recorded statement count");
    return { version, name, recordedStatementCount };
  });
}
export function validateMigrationHistoryRows(rows, manifest) {
  const problems = [];
  if (!Array.isArray(rows)) return ["migration history export is incomplete"];
  const versions = new Set(manifest.migrations.map((item) => item.version));
  const seenVersions = new Set();
  let previousVersion = null;
  for (const row of rows) {
    if (!row || Object.keys(row).sort().join(",") !== "name,recordedStatementCount,version"
      || typeof row.version !== "string" || !/^[0-9]{12}$/.test(row.version) || !versions.has(row.version)) {
      problems.push("migration history row must contain only recognized version, name and recorded statement-count database facts");
      continue;
    }
    if (seenVersions.has(row.version)) {
      problems.push("migration history contains duplicate version rows despite the required version primary key");
    } else {
      seenVersions.add(row.version);
    }
    if (previousVersion !== null && row.version <= previousVersion) {
      problems.push("migration history rows are not strictly ascending by version");
    }
    previousVersion = row.version;
    if ((row.name !== null && (typeof row.name !== "string" || !row.name.trim()))
      || (row.recordedStatementCount !== null && (!Number.isSafeInteger(row.recordedStatementCount) || row.recordedStatementCount < 0))) {
      problems.push("migration history row has an invalid migration name or recorded statement count");
    }
  }
  return problems;
}
function verifySignedArtifact(artifact, requiredKind, requiredRole, trustRoots, now, problems) {
  if (!artifact || artifact.schemaVersion !== 1 || artifact.kind !== requiredKind) {
    problems.push(requiredKind + " signed artifact is missing or has an unsupported schema/kind");
    return null;
  }
  const artifactKeys = ["approvalId", "claims", "expiresAt", "issuedAt", "keyId", "kind", "schemaVersion", "signature", "signerId"];
  if (Object.keys(artifact).sort().join(",") !== artifactKeys.sort().join(",")
    || !artifact.claims || typeof artifact.claims !== "object" || Array.isArray(artifact.claims)) {
    problems.push(requiredKind + " signed artifact has missing claims or an unsupported envelope");
    return null;
  }
  const roots = trustRoots && Array.isArray(trustRoots.keys) ? trustRoots.keys : [];
  const key = roots.find((candidate) => candidate && candidate.keyId === artifact.keyId && candidate.signerId === artifact.signerId);
  if (!key || key.algorithm !== "Ed25519" || key.role !== requiredRole || key.status !== "active") {
    problems.push(requiredKind + " signer is untrusted, revoked, inactive or lacks the required role");
    return null;
  }
  const keyStart = parseTime(key.notBefore, requiredKind + " trust-root notBefore", problems);
  const keyEnd = parseTime(key.notAfter, requiredKind + " trust-root notAfter", problems);
  if (!Object.prototype.hasOwnProperty.call(key, "revokedAt")) {
    problems.push(requiredKind + " trust-root revokedAt must be explicitly null for an active key");
    return null;
  }
  if (key.revokedAt !== null) {
    const revokedAt = parseTime(key.revokedAt, requiredKind + " trust-root revokedAt", problems);
    if (Number.isFinite(revokedAt)) problems.push(requiredKind + " signing key is revoked");
    else problems.push(requiredKind + " trust-root revokedAt must be null or a canonical UTC timestamp in years 0001–9999");
    return null;
  }
  if (!Number.isFinite(keyStart) || !Number.isFinite(keyEnd) || keyEnd <= keyStart || now < keyStart || now > keyEnd) {
    problems.push(requiredKind + " signing key is outside its validity window");
    return null;
  }
  if (!artifact.approvalId || (Array.isArray(trustRoots.revokedApprovalIds) && trustRoots.revokedApprovalIds.includes(artifact.approvalId))) {
    problems.push(requiredKind + " approval is missing an ID or has been revoked");
    return null;
  }
  const issuedAt = parseTime(artifact.issuedAt, requiredKind + " approval issuedAt", problems);
  const expiresAt = parseTime(artifact.expiresAt, requiredKind + " approval expiresAt", problems);
  if (!Number.isFinite(issuedAt) || !Number.isFinite(expiresAt) || issuedAt > now || expiresAt <= now || expiresAt <= issuedAt) {
    problems.push(requiredKind + " approval is unsigned-in-time, expired or has an invalid validity interval");
    return null;
  }
  if (issuedAt < keyStart || issuedAt > keyEnd) {
    problems.push(requiredKind + " approval was issued outside signer key validity");
    return null;
  }
  try {
    const publicKey = createPublicKey(key.publicKeyPem);
    assert(publicKey.asymmetricKeyType === "ed25519", "trust root is not an Ed25519 key");
    const unsigned = {
      schemaVersion: artifact.schemaVersion,
      kind: artifact.kind,
      signerId: artifact.signerId,
      keyId: artifact.keyId,
      approvalId: artifact.approvalId,
      issuedAt: artifact.issuedAt,
      expiresAt: artifact.expiresAt,
      claims: artifact.claims,
    };
    const signatureText = artifact.signature;
    const signature = Buffer.from(typeof signatureText === "string" && signatureText.length <= 128 ? signatureText : "", "base64");
    if (typeof key.publicKeyPem !== "string" || key.publicKeyPem.length > 4096 || key.publicKeyPem.includes("PRIVATE KEY")
      || signature.length !== 64 || !verifySignature(null, Buffer.from(canonicalJson(unsigned)), publicKey, signature)) {
      problems.push(requiredKind + " signature verification failed");
      return null;
    }
  } catch {
    problems.push(requiredKind + " signature or trust-root parsing failed");
    return null;
  }
  return artifact.claims;
}
function sameClaims(actual, expected) {
  return canonicalJson(actual) === canonicalJson(expected);
}
function validateCollectorAuthority(claims, provenance, evidenceDigest, authority, evidence, now, problems) {
  if (!claims) return;
  const expected = {
    projectRef: PROJECT_REF,
    queryBundleSha256: provenance.queryBundleSha256,
    collectorIdentity: provenance.collectorIdentity,
    capturedAt: provenance.capturedAt,
    evidenceDigest,
  };
  for (const [key, value] of Object.entries(expected)) {
    if (claims[key] !== value) problems.push("collector attestation does not bind exact " + key);
  }
  const authorityKeys = ["capturedAt", "collectorIdentity", "completed", "databaseAuthority", "executionEvidence", "executionId", "projectRef", "queryBundleSha256", "readOnlyTransaction", "schemaVersion"];
  if (!authority || Object.keys(authority).sort().join(",") !== authorityKeys.sort().join(",")
    || authority.schemaVersion !== 1 || authority.projectRef !== PROJECT_REF
    || authority.queryBundleSha256 !== provenance.queryBundleSha256
    || authority.collectorIdentity !== provenance.collectorIdentity || authority.capturedAt !== provenance.capturedAt
    || authority.completed !== true || authority.readOnlyTransaction !== true
    || typeof authority.executionId !== "string" || !authority.executionId.trim()) {
    problems.push("collector authority evidence is missing, incomplete or not bound to the approved read-only query execution");
    return;
  }
  const execution = authority.executionEvidence;
  const executionKeys = ["capturedAt", "collectorIdentity", "completed", "completedAt", "executionId", "projectRef", "queryBundleSha256", "readOnlyTransaction", "resultDigest", "startedAt", "statementCount"];
  const startedAt = parseTime(execution && execution.startedAt, "collector execution startedAt", problems);
  const completedAt = parseTime(execution && execution.completedAt, "collector execution completedAt", problems);
  const capturedAt = strictTimestamp(provenance.capturedAt);
  if (!execution || Object.keys(execution).sort().join(",") !== executionKeys.sort().join(",")
    || execution.projectRef !== PROJECT_REF || execution.collectorIdentity !== provenance.collectorIdentity
    || execution.queryBundleSha256 !== provenance.queryBundleSha256 || execution.capturedAt !== provenance.capturedAt
    || execution.executionId !== authority.executionId || execution.completed !== true || execution.readOnlyTransaction !== true
    || !Number.isInteger(execution.statementCount) || execution.statementCount < 1
    || !/^[a-f0-9]{64}$/.test(execution.resultDigest || "")
    || !Number.isFinite(startedAt) || !Number.isFinite(completedAt)
    || startedAt > completedAt || completedAt > capturedAt || capturedAt > now
    || execution.resultDigest !== sha256(Buffer.from(canonicalJson({
      history: evidence && evidence.history,
      catalog: evidence && evidence.catalog,
      databaseAuthority: authority.databaseAuthority,
    })))) {
    problems.push("collector query execution receipt is incomplete or not bound to the exact approved query, project, identity, capture and result");
  }
  const authorityEvidenceDigest = sha256(Buffer.from(canonicalJson(authority)));
  if (claims.authorityEvidenceDigest !== authorityEvidenceDigest || claims.executionId !== authority.executionId) {
    problems.push("collector attestation does not bind the exact privilege-query evidence digest and execution");
  }
  const db = claims.databaseAuthority;
  if (canonicalJson(db) !== canonicalJson(authority.databaseAuthority)) {
    problems.push("signed collector authority differs from the evidence-bound privilege-query result");
  }
  if (!db || typeof db.databaseRole !== "string" || !db.databaseRole.trim()) {
    problems.push("collector attestation lacks the effective database role");
    return;
  }
  for (const flag of ["isSuperuser", "canCreateRole", "canCreateDatabase", "bypassRls", "isReplication", "ownsObjects"]) {
    if (db[flag] !== false) problems.push("collector database role is elevated or its " + flag + " status is not proven false");
  }
  // The complete database_acl_v1 projection is part of the signed result, not optional metadata.
  const databaseAclRows = db.databaseAclV1;
  if (!Array.isArray(databaseAclRows) || databaseAclRows.length === 0) {
    problems.push("collector complete database_acl_v1 projection is missing");
  } else {
    const rowKeys = ["acl_expansion_source", "allows_connections", "database_count", "database_name", "database_oid",
      "datacl_was_null", "expanded_acl_edges", "is_template", "owner_name", "owner_oid"];
    const edgeKeys = ["grantee_name", "grantee_oid", "grantor_name", "grantor_oid", "is_grantable", "privilege_type"];
    const seenDatabases = new Set();
    let previousDatabaseOid = -1;
    for (const row of databaseAclRows) {
      if (!row || Object.keys(row).sort().join(",") !== [...rowKeys].sort().join(",")
        || !Number.isSafeInteger(row.database_oid) || row.database_oid <= 0
        || !Number.isSafeInteger(row.database_count) || row.database_count !== databaseAclRows.length
        || row.database_oid <= previousDatabaseOid
        || typeof row.database_name !== "string" || !row.database_name.trim()
        || !Number.isSafeInteger(row.owner_oid) || row.owner_oid <= 0
        || typeof row.owner_name !== "string" || !row.owner_name.trim()
        || typeof row.allows_connections !== "boolean" || typeof row.is_template !== "boolean"
        || typeof row.datacl_was_null !== "boolean"
        || row.acl_expansion_source !== (row.datacl_was_null ? "built_in_default" : "explicit")
        || !Array.isArray(row.expanded_acl_edges)) {
        problems.push("collector database_acl_v1 projection contains an incomplete, malformed or unordered database row");
        break;
      }
      previousDatabaseOid = row.database_oid;
      if (seenDatabases.has(row.database_oid)) {
        problems.push("collector database_acl_v1 projection repeats a database identity");
        break;
      }
      seenDatabases.add(row.database_oid);
      let previousEdge = null;
      const seenEdges = new Set();
      for (const edge of row.expanded_acl_edges) {
        if (!edge || Object.keys(edge).sort().join(",") !== [...edgeKeys].sort().join(",")
          || !Number.isSafeInteger(edge.grantee_oid) || edge.grantee_oid < 0
          || !Number.isSafeInteger(edge.grantor_oid) || edge.grantor_oid <= 0
          || typeof edge.grantee_name !== "string" || !edge.grantee_name.trim()
          || (edge.grantee_oid === 0 ? edge.grantee_name !== "PUBLIC" : edge.grantee_name === "PUBLIC")
          || typeof edge.grantor_name !== "string" || !edge.grantor_name.trim()
          || !["CONNECT", "CREATE", "TEMPORARY"].includes(edge.privilege_type)
          || typeof edge.is_grantable !== "boolean") {
          problems.push("collector database_acl_v1 projection contains a malformed ACL edge");
          break;
        }
        const edgeIdentity = canonicalJson(edge);
        if (seenEdges.has(edgeIdentity)) {
          problems.push("collector database_acl_v1 projection repeats an ACL edge");
          break;
        }
        seenEdges.add(edgeIdentity);
        if (previousEdge && (previousEdge.grantee_oid > edge.grantee_oid
          || (previousEdge.grantee_oid === edge.grantee_oid && previousEdge.grantor_oid > edge.grantor_oid)
          || (previousEdge.grantee_oid === edge.grantee_oid && previousEdge.grantor_oid === edge.grantor_oid
            && previousEdge.privilege_type > edge.privilege_type)
          || (previousEdge.grantee_oid === edge.grantee_oid && previousEdge.grantor_oid === edge.grantor_oid
            && previousEdge.privilege_type === edge.privilege_type
            && Number(previousEdge.is_grantable) > Number(edge.is_grantable)))) {
          problems.push("collector database_acl_v1 ACL edges are not in canonical order");
          break;
        }
        previousEdge = edge;
      }
    }
  }
  const inventoryObjects = evidence && evidence.catalog && Array.isArray(evidence.catalog.objects) ? evidence.catalog.objects : [];
  for (const problem of validateCollectorPrivilegeEvidence(db, inventoryObjects)) problems.push(problem);
  if (!Array.isArray(db.roleMemberships) || db.roleMemberships.length !== 0) {
    problems.push("collector has inherited role memberships or membership evidence is missing");
  }
  if (!Array.isArray(db.ownedSchemas) || db.ownedSchemas.length !== 0) {
    problems.push("collector owns schemas or ownership evidence is missing");
  }
  if (db.proofQueryBundleSha256 !== provenance.queryBundleSha256) {
    problems.push("collector privilege proof was not produced by the approved query bundle");
  }
}
function validateMapping(mapping, manifest, source, problems) {
  if (!mapping || mapping.schemaVersion !== 1 || !Array.isArray(mapping.migrations)
    || mapping.migrations.length !== manifest.migrations.length) {
    problems.push("migration mapping must contain exactly one reviewed entry for every source migration");
    return new Map();
  }
  if (Object.keys(mapping).sort().join(",") !== ["migrations", "schemaVersion"].sort().join(",")) {
    problems.push("migration mapping contains unsupported top-level fields");
  }
  const byPath = new Map();
  for (const entry of mapping.migrations) {
    if (!entry || typeof entry.path !== "string" || byPath.has(entry.path)) {
      problems.push("migration mapping contains a missing or duplicate source path");
      continue;
    }
    if (Object.keys(entry).sort().join(",") !== ["blobSha1", "coverage", "effects", "path"].sort().join(",")) {
      problems.push("migration mapping entry contains unsupported fields for " + entry.path);
    }
    byPath.set(entry.path, entry);
  }
  const result = new Map();
  const inventoryPaths = new Map(manifest.migrations.map((item) => [item.path, item.blobSha1]));
  const allowedDispositions = new Set(["effects", "none", "unsupported", "unknown"]);
  for (const item of manifest.migrations) {
    const entry = byPath.get(item.path);
    if (!entry || entry.blobSha1 !== item.blobSha1 || !source.get(item.path)?.valid) {
      problems.push("mapping does not bind the exact pinned migration source: " + item.path);
      continue;
    }
    if (!entry.effects || Object.keys(entry.effects).sort().join(",") !== [...CATEGORIES].sort().join(",")
      || CATEGORIES.some((category) => !Array.isArray(entry.effects[category]))) {
      problems.push("mapping omits, or adds unsupported, effect domains for " + item.path);
      continue;
    }
    const coverage = entry.coverage;
    if (!coverage || Object.keys(coverage).sort().join(",") !== [...CATEGORIES].sort().join(",")
      || CATEGORIES.some((category) => !coverage[category])) {
      problems.push("mapping lacks an explicit reviewed coverage disposition for every effect domain: " + item.path);
      continue;
    }
    const flattened = [];
    const unsupportedCategories = [];
    const unknownCategories = [];
    const seenEffects = new Set();
    let coverageMalformed = false;
    for (const category of CATEGORIES) {
      const review = coverage[category];
      const effects = entry.effects[category];
      const disposition = review && review.disposition;
      const ranges = review && review.sourceRanges;
      if (!review || Object.keys(review).sort().join(",") !== ["disposition", "rationale", "sourceRanges"].sort().join(",")
        || !allowedDispositions.has(disposition)
        || (disposition === "effects" && effects.length === 0)
        || (disposition !== "effects" && effects.length !== 0)
        || typeof review.rationale !== "string" || review.rationale.trim().length < 20
        || !Array.isArray(ranges) || ranges.length === 0) {
        coverageMalformed = true;
        break;
      }
      let previousEnd = 0;
      for (const range of ranges) {
        if (!range || Object.keys(range).sort().join(",") !== ["endLine", "startLine"].sort().join(",")
          || !Number.isSafeInteger(range.startLine) || !Number.isSafeInteger(range.endLine)
          || range.startLine <= previousEnd || range.endLine < range.startLine
          || range.endLine > source.get(item.path).lineCount) {
          coverageMalformed = true;
          break;
        }
        previousEnd = range.endLine;
      }
      if (coverageMalformed) break;
      if (disposition === "unsupported") {
        unsupportedCategories.push(category);
        problems.push("mapping explicitly classifies " + category + " as unsupported for " + item.path + ": " + review.rationale);
      } else if (disposition === "unknown") {
        unknownCategories.push(category);
        problems.push("mapping explicitly classifies " + category + " as unknown for " + item.path + ": " + review.rationale);
      }
      for (const effect of effects) {
        const allowed = category === "schema" ? SCHEMA_KINDS
          : category === "routines" ? new Set(["routines"]) : new Set([category]);
        if (!effect || Object.keys(effect).sort().join(",") !== categoryEffectKeys(category).sort().join(",")
          || !allowed.has(effect.kind) || typeof effect.identity !== "string" || !effect.identity.trim()
          || !/^[a-f0-9]{64}$/.test(effect.fingerprint || "")
          || typeof effect.description !== "string" || !effect.description.trim()
          || (categoryEffectKeys(category).includes("sourcePath") && effect.sourcePath !== item.path)) {
          coverageMalformed = true;
          break;
        }
        const contractRange = effect.contract && effect.contract.sourceRange;
        if (!contractRange || !ranges.some((range) => contractRange.startLine >= range.startLine && contractRange.endLine <= range.endLine)) {
          problems.push("category-specific effect source range is not covered by reviewed mapping ranges for " + item.path);
          coverageMalformed = true;
          break;
        }
        const contractProblem = validateCategoryEffectContract(category, effect, inventoryPaths, { sourceText: source.get(item.path).content });
        if (contractProblem) {
          problems.push(contractProblem + " for " + item.path);
          coverageMalformed = true;
          break;
        }
        const key = effect.kind + "\0" + effect.identity;
        if (seenEffects.has(key)) {
          problems.push("mapping repeats an effect identity across effect domains for " + item.path);
          coverageMalformed = true;
          break;
        }
        seenEffects.add(key);
        flattened.push({ kind: effect.kind, identity: effect.identity, fingerprint: effect.fingerprint, category });
      }
      if (coverageMalformed) break;
    }
    if (coverageMalformed) {
      problems.push("mapping has incomplete, malformed, unordered or overlapping source-linked coverage/effects for " + item.path);
      continue;
    }
    if (flattened.length === 0) {
      problems.push("mapping contains no deterministic effects for " + item.path);
    }
    result.set(item.path, { effects: flattened, unsupportedCategories, unknownCategories });
  }
  if (byPath.size !== manifest.migrations.length || manifest.migrations.some((item) => !byPath.has(item.path))) {
    problems.push("mapping path set does not exactly match the pinned 40-file inventory");
  }
  return result;
}
function validateEvidence(evidence, now, manifest, problems) {
  const exactKeys = (value, keys) => value && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).sort().join(",") === [...keys].sort().join(",");
  const required = ["catalog", "collectorAuthority", "history", "mapping", "provenance", "schemaVersion"];
  const allowed = [...required, "externalExecutionProvenance"];
  if (!evidence || evidence.schemaVersion !== 2
    || required.some((key) => !Object.prototype.hasOwnProperty.call(evidence || {}, key))
    || Object.keys(evidence || {}).some((key) => !allowed.includes(key))) {
    problems.push("evidence has an unsupported schema version, missing required property or unexpected property");
  }
  const p = evidence && evidence.provenance;
  if (!exactKeys(p, ["environment", "projectRef", "capturedAt", "collectorIdentity", "queryBundleSha256"])) {
    problems.push("evidence provenance schema is incomplete or contains unsupported properties");
  }
  if (!p || p.environment !== "production" || p.projectRef !== PROJECT_REF) problems.push("evidence target is not the approved DeedLight Production project");
  if (!p || typeof p.collectorIdentity !== "string" || !p.collectorIdentity.trim()) problems.push("collector identity is missing");
  if (!p || !/^[a-f0-9]{64}$/.test(p.queryBundleSha256 || "")) problems.push("query-bundle fingerprint is missing");
  const captured = parseTime(p && p.capturedAt, "evidence capture timestamp", problems);
  if (Number.isFinite(captured) && (now - captured < 0 || now - captured > MAX_EVIDENCE_AGE_MS)) problems.push("evidence is stale or timestamp is in the future");
  const history = evidence && evidence.history;
  if (!exactKeys(history, ["complete", "rows"]) || typeof history.complete !== "boolean" || !Array.isArray(history.rows)) {
    problems.push("migration history export is incomplete or contains unsupported properties");
  }
  const catalog = evidence && evidence.catalog;
  if (!exactKeys(catalog, ["complete", "completeKinds", "objects"]) || typeof catalog.complete !== "boolean" || !Array.isArray(catalog.objects)) {
    problems.push("live catalog export is incomplete or contains unsupported properties");
  }
  if (catalog && Array.isArray(catalog.objects)) {
    for (const object of catalog.objects) {
      const expectedObjectKeys = object && object.kind === "columns"
        ? ["kind", "identity", "fingerprint", "schema", "relation", "column"]
        : ["kind", "identity", "fingerprint"];
      if (!exactKeys(object, expectedObjectKeys)
        || (object.kind === "columns" && ([object.schema, object.relation, object.column].some((value) => typeof value !== "string" || !value.length)
          || object.identity !== [object.schema, object.relation, object.column].join(".")))) {
        problems.push("catalog object contains an unexpected or missing property, or an ambiguous structured column identity");
        break;
      }
    }
  }
  const completeKinds = catalog && catalog.completeKinds;
  if (!Array.isArray(completeKinds) || new Set(completeKinds).size !== CATALOG_KINDS.length
    || canonicalJson([...completeKinds].sort()) !== canonicalJson([...CATALOG_KINDS].sort())) {
    problems.push("catalog completeness dimensions are missing, duplicated or unexpected");
  }
  for (const kind of CATALOG_KINDS) if (!Array.isArray(completeKinds) || !completeKinds.includes(kind)) {
    problems.push("catalog export does not attest complete " + kind);
  }
  if (history && Array.isArray(history.rows)) problems.push(...validateMigrationHistoryRows(history.rows, manifest));
  if (evidence && evidence.externalExecutionProvenance !== undefined) {
    if (!Array.isArray(evidence.externalExecutionProvenance)) problems.push("external migration execution provenance must be an array of candidate records");
    else {
      for (const record of evidence.externalExecutionProvenance) parseTime(record && record.executedAt, "external migration execution timestamp", problems);
      if (evidence.externalExecutionProvenance.length > 0) problems.push("external migration execution provenance is unverified: no authenticated authoritative source is configured");
    }
  }
}
function classifyOne(item, manifest, evidence, source, mappedEffects) {
  if (!source.get(item.path)?.valid) return { status: "Unknown", reasons: ["migration source fingerprint is not verified"] };
  const mapping = mappedEffects.get(item.path);
  if (!mapping) return { status: "Unknown", reasons: ["migration has no complete authenticated effect mapping"] };
  if (mapping.unsupportedCategories.length || mapping.unknownCategories.length) {
    return { status: "Unknown", reasons: [
      ...mapping.unsupportedCategories.map((category) => "effect domain is explicitly unsupported: " + category),
      ...mapping.unknownCategories.map((category) => "effect domain is explicitly unknown: " + category),
    ], exactExecutionEstablished: false };
  }
  const expected = mapping.effects;
  if (!expected.length) return { status: "Unknown", reasons: ["migration mapping contains no deterministic effects"] };
  const catalog = new Map();
  for (const object of evidence.catalog.objects) {
    const expectedObjectKeys = object && object.kind === "columns"
      ? "column,fingerprint,identity,kind,relation,schema"
      : "fingerprint,identity,kind";
    if (!object || Object.keys(object).sort().join(",") !== expectedObjectKeys || !CATALOG_KINDS.includes(object.kind)
      || typeof object.identity !== "string" || !/^[a-f0-9]{64}$/.test(object.fingerprint || "")
      || (object.kind === "columns" && ([object.schema, object.relation, object.column].some((value) => typeof value !== "string" || !value.length)
        || object.identity !== [object.schema, object.relation, object.column].join(".")))) {
      return { status: "Unknown", reasons: ["malformed live catalog object fingerprint or structured column identity"] };
    }
    const key = object.kind + "\0" + object.identity;
    if (catalog.has(key)) return { status: "Unknown", reasons: ["duplicate live catalog object identity"] };
    catalog.set(key, object.fingerprint);
  }
  const matches = expected.filter((object) => catalog.get(object.kind + "\0" + object.identity) === object.fingerprint);
  const mismatches = expected.filter((object) => catalog.has(object.kind + "\0" + object.identity)
    && catalog.get(object.kind + "\0" + object.identity) !== object.fingerprint);
  const missing = expected.filter((object) => !catalog.has(object.kind + "\0" + object.identity));
  const rows = evidence.history.rows.filter((row) => row.version === item.version);
  const duplicateVersion = manifest.migrations.filter((entry) => entry.version === item.version).length > 1;
  const expectedName = path.basename(item.path).replace(/^\d{12}_/, "").replace(/\.sql$/, "");
  const wrongName = rows.some((row) => row.name !== expectedName);
  if (matches.length === expected.length) {
    return {
      status: "Schema represented but history ambiguous",
      schemaRepresented: true,
      historyRecorded: rows.length > 0,
      reasons: [duplicateVersion ? "duplicate migration version cannot establish exact source execution"
        : wrongName ? "history version is associated with a different migration name"
          : rows.length === 0 ? "schema effects exist without a migration-history row"
            : "schema_migrations records version, name and statement count only; no authenticated external provenance binds the executed source blob, actor, timestamp or execution identity"],
      matchedObjects: matches.length,
      historyRows: rows.length,
      exactExecutionEstablished: false,
    };
  }
  if (matches.length > 0 || mismatches.length > 0 || rows.length > 0) {
    return {
      status: "Partial or drifted",
      schemaRepresented: matches.length === expected.length,
      historyRecorded: rows.length > 0,
      reasons: [
        ...(matches.length ? [matches.length + " of " + expected.length + " expected effects match"] : []),
        ...(mismatches.length ? [mismatches.length + " effects have conflicting fingerprints"] : []),
        ...(missing.length ? [missing.length + " expected effects are absent"] : []),
        ...(rows.length ? ["migration history exists but mapped effects are incomplete or drifted"] : []),
      ],
      matchedObjects: matches.length,
      historyRows: rows.length,
      exactExecutionEstablished: false,
    };
  }
  return { status: "Unknown", schemaRepresented: false, historyRecorded: false,
    reasons: ["absence of a migration-history row and current catalog effects cannot prove no manual, partial or historical execution without authenticated external execution provenance"],
    matchedObjects: 0, historyRows: 0, exactExecutionEstablished: false };
}
export function analyzeMigrationEvidence({ rootDir, manifest, evidence, approvals, trustRoots, expectedInventoryBlobSha1 = INVENTORY_BLOB_SHA1 }) {
  const problems = [];
  const now = Date.now();
  // Captured at process startup: callers cannot replace the trusted digest through API arguments or later env mutation.
  const trustedTrustRootsSha256 = PROVISIONED_TRUST_ROOTS_SHA256;
  const trustRootBundleKeys = ["keys", "revokedApprovalIds", "schemaVersion"];
  const requiredTrustRootBundleKeys = ["keys", "schemaVersion"];
  if (!trustRoots || typeof trustRoots !== "object" || Array.isArray(trustRoots)
    || trustRoots.schemaVersion !== 1 || !Array.isArray(trustRoots.keys)
    || requiredTrustRootBundleKeys.some((key) => !Object.prototype.hasOwnProperty.call(trustRoots, key))
    || Object.keys(trustRoots).some((key) => !trustRootBundleKeys.includes(key))) {
    problems.push("external trust-root bundle is missing, malformed or contains unsupported fields");
  } else {
    const rootDigest = sha256(Buffer.from(canonicalJson(trustRoots)));
    if (!/^[a-f0-9]{64}$/.test(trustedTrustRootsSha256 || "") || trustedTrustRootsSha256 !== rootDigest) {
      problems.push("external trust roots do not match the independently provisioned trust-root digest");
    }
    const keyIds = trustRoots.keys.map((key) => key && key.keyId);
    if (new Set(keyIds).size !== keyIds.length) problems.push("trust-root bundle contains duplicate key IDs");
    const publicKeyFingerprints = new Set();
    const allowedRoles = new Set(["evidence-approver", "mapping-approver", "collector"]);
    const allowedTrustRootKeyFields = ["algorithm", "keyId", "notAfter", "notBefore", "publicKeyPem", "revokedAt", "role", "signerId", "status"];
    for (const key of trustRoots.keys) {
      if (!key || typeof key !== "object" || Array.isArray(key)
        || Object.keys(key).length !== allowedTrustRootKeyFields.length
        || Object.keys(key).some((field) => !allowedTrustRootKeyFields.includes(field))
        || allowedTrustRootKeyFields.some((field) => !Object.prototype.hasOwnProperty.call(key, field))
        || typeof key.keyId !== "string" || !key.keyId || typeof key.signerId !== "string" || !key.signerId
        || key.algorithm !== "Ed25519" || !allowedRoles.has(key.role)
        || typeof key.publicKeyPem !== "string" || key.publicKeyPem.length > 4096 || key.publicKeyPem.includes("PRIVATE KEY")) {
        problems.push("trust-root bundle contains an unsupported key, role or private signing material");
        continue;
      }
      try {
        const publicKey = createPublicKey(key.publicKeyPem);
        if (publicKey.asymmetricKeyType !== "ed25519") {
          problems.push("trust-root bundle contains a non-Ed25519 public key");
        } else {
          const fingerprint = sha256(publicKey.export({ type: "spki", format: "der" }));
          if (publicKeyFingerprints.has(fingerprint)) problems.push("trust-root bundle reuses one public key across signer identities");
          publicKeyFingerprints.add(fingerprint);
        }
      } catch {
        problems.push("trust-root bundle contains an invalid public key");
      }
      if (!["active", "revoked"].includes(key.status)) problems.push("trust-root key status is unsupported");
      if (key.status === "active"
        && (!Object.prototype.hasOwnProperty.call(key, "revokedAt") || key.revokedAt !== null)) {
        problems.push("every active trust-root key must explicitly provide revokedAt: null");
      }
    }
    if (trustRoots.revokedApprovalIds !== undefined && !Array.isArray(trustRoots.revokedApprovalIds)) {
      problems.push("trust-root revoked approval registry is malformed");
    }
  }
  let source;
  try { source = validateSourceInventory(rootDir, manifest); }
  catch (error) {
    problems.push("source inventory validation failed: " + error.message);
    source = new Map(manifest.migrations.map((item) => [item.path, { valid: false, reason: error.message }]));
  }
  if (expectedInventoryBlobSha1 !== INVENTORY_BLOB_SHA1) problems.push("caller attempted to override the pinned inventory fingerprint");
  validateEvidence(evidence, now, manifest, problems);
  const mapping = evidence && evidence.mapping;
  const mappedEffects = validateMapping(mapping, manifest, source, problems);
  const evidenceDigest = sha256(evidencePayload(evidence));
  const mapDigest = mappingDigest(mapping);
  const provenance = evidence && evidence.provenance || {};
  const bundle = approvals || {};
  const evidenceClaims = verifySignedArtifact(bundle.evidenceApproval, "production-evidence-approval", "evidence-approver", trustRoots, now, problems);
  const mappingClaims = verifySignedArtifact(bundle.mappingApproval, "migration-mapping-approval", "mapping-approver", trustRoots, now, problems);
  const collectorClaims = verifySignedArtifact(bundle.collectorAttestation, "read-only-collector-attestation", "collector", trustRoots, now, problems);
  const signerIds = [bundle.evidenceApproval?.signerId, bundle.mappingApproval?.signerId, bundle.collectorAttestation?.signerId];
  const keyIds = [bundle.evidenceApproval?.keyId, bundle.mappingApproval?.keyId, bundle.collectorAttestation?.keyId];
  const approvalIds = [bundle.evidenceApproval?.approvalId, bundle.mappingApproval?.approvalId, bundle.collectorAttestation?.approvalId];
  if (signerIds.some((value) => typeof value !== "string") || new Set(signerIds).size !== 3
    || keyIds.some((value) => typeof value !== "string") || new Set(keyIds).size !== 3
    || approvalIds.some((value) => typeof value !== "string" || !value) || new Set(approvalIds).size !== 3) {
    problems.push("evidence, mapping and collector attestations must use three distinct trusted signers, keys and approval IDs");
  }
  for (const approval of [bundle.evidenceApproval, bundle.collectorAttestation]) {
    const issuedAt = strictTimestamp(approval?.issuedAt);
    const capturedAt = strictTimestamp(provenance.capturedAt);
    if (Number.isFinite(issuedAt) && Number.isFinite(capturedAt) && issuedAt <= capturedAt) {
      problems.push("evidence and collector approvals must be issued after the exact evidence capture");
    }
  }
  const expectedEvidenceClaims = {
    projectRef: PROJECT_REF,
    evidenceDigest,
    mappingDigest: mapDigest,
    queryBundleSha256: provenance.queryBundleSha256,
    collectorIdentity: provenance.collectorIdentity,
    capturedAt: provenance.capturedAt,
  };
  const expectedMappingClaims = {
    projectRef: PROJECT_REF,
    mappingDigest: mapDigest,
    inventoryBlobSha1: INVENTORY_BLOB_SHA1,
    migrationCount: manifest.migrations.length,
    versionCount: new Set(manifest.migrations.map((item) => item.version)).size,
  };
  if (evidenceClaims && !sameClaims(evidenceClaims, expectedEvidenceClaims)) problems.push("signed evidence approval does not bind the exact evidence, mapping, project, collector, query bundle and capture timestamp");
  if (mappingClaims && !sameClaims(mappingClaims, expectedMappingClaims)) problems.push("signed mapping approval does not bind the exact complete mapping and inventory");
  validateCollectorAuthority(collectorClaims, provenance, evidenceDigest, evidence && evidence.collectorAuthority,
    evidence, now, problems);
  const reports = manifest.migrations.map((item) => {
    if (problems.length) return { path: item.path, version: item.version, blobSha1: item.blobSha1, status: "Unknown", reasons: ["one or more evidence, approval, mapping or collector trust checks failed"] };
    return { path: item.path, version: item.version, blobSha1: item.blobSha1, ...classifyOne(item, manifest, evidence, source, mappedEffects) };
  });
  const counts = Object.fromEntries(["Applied and verified", "Schema represented but history ambiguous", "Verified unapplied", "Partial or drifted", "Unknown"]
    .map((status) => [status, reports.filter((entry) => entry.status === status).length]));
  const unresolved = counts["Schema represented but history ambiguous"] + counts["Partial or drifted"] + counts.Unknown;
  return {
    schemaVersion: 2,
    project: "DeedLight",
    trustVerified: problems.length === 0,
    trustProblems: problems,
    evidenceDigest,
    mappingDigest: mapDigest,
    sourceInventory: { migrationCount: manifest.migrations.length, uniqueVersionCount: new Set(manifest.migrations.map((item) => item.version)).size },
    duplicateVersionPolicy: "A history row for 202607260007 never establishes exact execution of either or both distinct source bodies.",
    classifications: reports,
    counts,
    acceptance: problems.length === 0 && unresolved === 0 ? "ACCEPTED" : "NOT_ACCEPTED",
    mutationPerformed: false,
  };
}
function readJson(file) {
  return JSON.parse(readFileSync(file, "utf8"));
}
function main() {
  const args = process.argv.slice(2);
  const options = Object.fromEntries(args.map((arg) => {
    const match = arg.match(/^--(evidence|approvals|trust-roots|mode)=(.+)$/);
    assert(match, "usage: node scripts/reconcile-migration-evidence.mjs --evidence=<json> --approvals=<json> --trust-roots=<external-json> [--mode=accept|report]");
    return [match[1], match[2]];
  }));
  assert(options.evidence && options.approvals && options["trust-roots"], "evidence, approvals and external trust roots are required");
  assert(/^[a-f0-9]{64}$/.test(process.env.DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256 || ""), "DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256 must be provisioned independently of repository evidence");
  const rootDir = process.cwd();
  const repoPath = realpathSync(rootDir);
  const trustPath = realpathSync(options["trust-roots"]);
  assert(!trustPath.startsWith(repoPath + path.sep) && trustPath !== repoPath, "trust roots must be provisioned outside the repository");
  const manifest = readJson(path.join(rootDir, "supabase/migration-inventory.json"));
  const evidence = readJson(options.evidence);
  const approvals = readJson(options.approvals);
  const trustRoots = readJson(trustPath);
  const report = analyzeMigrationEvidence({ rootDir, manifest, evidence, approvals, trustRoots, trustedTrustRootsSha256: process.env.DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256 });
  const mode = options.mode || "accept";
  assert(mode === "accept" || mode === "report", "mode must be accept or report");
  report.analysisAcceptance = report.acceptance;
  report.executionMode = mode === "report" ? "REPORT_ONLY" : "ACCEPTANCE";
  report.reconciliationAccepted = mode === "accept" && report.analysisAcceptance === "ACCEPTED";
  if (mode === "report") report.acceptance = "REPORT_ONLY";
  process.stdout.write(JSON.stringify(report, null, 2) + "\n");
  if (mode === "accept" && report.analysisAcceptance !== "ACCEPTED") process.exitCode = 2;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
