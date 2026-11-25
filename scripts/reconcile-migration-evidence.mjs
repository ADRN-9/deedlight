import { createHash, createPublicKey, verify as verifySignature } from "node:crypto";
import { lstatSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { gitBlobSha1, validateInventory } from "./verify-migration-inventory-aggregate.mjs";

const PROJECT_REF = "xaipiovflxomcbfwtwmu";
const INVENTORY_BLOB_SHA1 = "95d514a0bd97ff448c9507252eb1f5e69a507442";
const MAX_EVIDENCE_AGE_MS = 24 * 60 * 60 * 1000;
const CATEGORIES = ["schema", "privileges", "ownership", "routines", "data", "dependencies", "preconditions", "postconditions"];
const CATALOG_KINDS = ["tables", "columns", "constraints", "indexes", "triggers", "policies", "routines", "privileges", "ownership", "data", "dependencies", "preconditions", "postconditions"];
const SCHEMA_KINDS = new Set(["tables", "columns", "constraints", "indexes", "triggers", "policies"]);
const READ_ONLY_PRIVILEGES = new Set(["CONNECT", "USAGE", "SELECT"]);

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
  return JSON.stringify(canonical(value));
}
export function evidencePayload(evidence) {
  return Buffer.from(canonicalJson(evidence));
}
export function mappingDigest(mapping) {
  return sha256(Buffer.from(canonicalJson(mapping)));
}
function parseTime(value, label, reasons) {
  const time = Date.parse(value);
  if (typeof value !== "string" || !Number.isFinite(time)) reasons.push(label + " is missing or invalid");
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
      ? { valid: true, blobSha1: actual }
      : { valid: false, reason: "source fingerprint or byte length differs from pinned inventory", actualBlobSha1: actual });
  }
  return source;
}
function verifySignedArtifact(artifact, requiredKind, requiredRole, trustRoots, now, problems) {
  if (!artifact || artifact.schemaVersion !== 1 || artifact.kind !== requiredKind) {
    problems.push(requiredKind + " signed artifact is missing or has an unsupported schema/kind");
    return null;
  }
  const roots = trustRoots && Array.isArray(trustRoots.keys) ? trustRoots.keys : [];
  const key = roots.find((candidate) => candidate.keyId === artifact.keyId && candidate.signerId === artifact.signerId);
  if (!key || key.algorithm !== "Ed25519" || key.role !== requiredRole || key.status !== "active") {
    problems.push(requiredKind + " signer is untrusted, revoked, inactive or lacks the required role");
    return null;
  }
  const keyStart = Date.parse(key.notBefore);
  const keyEnd = Date.parse(key.notAfter);
  if (!Number.isFinite(keyStart) || !Number.isFinite(keyEnd) || now < keyStart || now > keyEnd || key.revokedAt) {
    problems.push(requiredKind + " signing key is outside its validity window or revoked");
    return null;
  }
  if (!artifact.approvalId || (Array.isArray(trustRoots.revokedApprovalIds) && trustRoots.revokedApprovalIds.includes(artifact.approvalId))) {
    problems.push(requiredKind + " approval is missing an ID or has been revoked");
    return null;
  }
  const issuedAt = Date.parse(artifact.issuedAt);
  const expiresAt = Date.parse(artifact.expiresAt);
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
    const signature = Buffer.from(artifact.signature || "", "base64");
    if (signature.length !== 64 || !verifySignature(null, Buffer.from(canonicalJson(unsigned)), publicKey, signature)) {
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
function validateCollectorAuthority(claims, provenance, problems) {
  if (!claims) return;
  const expected = {
    projectRef: PROJECT_REF,
    queryBundleSha256: provenance.queryBundleSha256,
    collectorIdentity: provenance.collectorIdentity,
    capturedAt: provenance.capturedAt,
  };
  for (const [key, value] of Object.entries(expected)) {
    if (claims[key] !== value) problems.push("collector attestation does not bind exact " + key);
  }
  const db = claims.databaseAuthority;
  if (!db || typeof db.databaseRole !== "string" || !db.databaseRole.trim()) {
    problems.push("collector attestation lacks the effective database role");
    return;
  }
  for (const flag of ["isSuperuser", "canCreateRole", "canCreateDatabase", "bypassRls", "isReplication", "ownsObjects"]) {
    if (db[flag] !== false) problems.push("collector database role is elevated or its " + flag + " status is not proven false");
  }
  if (!Array.isArray(db.effectivePrivileges)
    || db.effectivePrivileges.length !== READ_ONLY_PRIVILEGES.size
    || [...READ_ONLY_PRIVILEGES].some((privilege) => !db.effectivePrivileges.includes(privilege))
    || db.effectivePrivileges.some((privilege) => !READ_ONLY_PRIVILEGES.has(privilege))) {
    problems.push("collector effective privileges are not exactly CONNECT, USAGE and SELECT");
  }
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
  if (!mapping || mapping.schemaVersion !== 1 || !Array.isArray(mapping.migrations) || mapping.migrations.length !== manifest.migrations.length) {
    problems.push("migration mapping must contain exactly one reviewed entry for every source migration");
    return new Map();
  }
  const byPath = new Map();
  for (const entry of mapping.migrations) {
    if (!entry || typeof entry.path !== "string" || byPath.has(entry.path)) {
      problems.push("migration mapping contains a missing or duplicate source path");
      continue;
    }
    byPath.set(entry.path, entry);
  }
  const result = new Map();
  for (const item of manifest.migrations) {
    const entry = byPath.get(item.path);
    if (!entry || entry.blobSha1 !== item.blobSha1 || !source.get(item.path)?.valid) {
      problems.push("mapping does not bind the exact pinned migration source: " + item.path);
      continue;
    }
    if (!entry.effects || CATEGORIES.some((category) => !Array.isArray(entry.effects[category]))) {
      problems.push("mapping omits one or more required effect domains for " + item.path);
      continue;
    }
    const flattened = [];
    let malformed = false;
    for (const category of CATEGORIES) {
      for (const effect of entry.effects[category]) {
        const allowed = category === "schema" ? SCHEMA_KINDS : category === "routines" ? new Set(["routines"]) : new Set([category]);
        if (!effect || !allowed.has(effect.kind) || typeof effect.identity !== "string" || !effect.identity.trim()
          || !/^[a-f0-9]{64}$/.test(effect.fingerprint || "") || typeof effect.description !== "string" || !effect.description.trim()) {
          malformed = true;
          break;
        }
        flattened.push({ kind: effect.kind, identity: effect.identity, fingerprint: effect.fingerprint, category });
      }
    }
    if (malformed || flattened.length === 0) {
      problems.push("mapping contains malformed or empty effects for " + item.path);
      continue;
    }
    const keys = new Set();
    for (const effect of flattened) {
      const key = effect.kind + "\0" + effect.identity;
      if (keys.has(key)) problems.push("mapping repeats an effect identity for " + item.path);
      keys.add(key);
    }
    result.set(item.path, flattened);
  }
  if (byPath.size !== manifest.migrations.length || manifest.migrations.some((item) => !byPath.has(item.path))) {
    problems.push("mapping path set does not exactly match the pinned 39-file inventory");
  }
  return result;
}
function validateEvidence(evidence, now, manifest, problems) {
  if (!evidence || evidence.schemaVersion !== 2) problems.push("unsupported or missing evidence schema version 2");
  const p = evidence && evidence.provenance;
  if (!p || p.environment !== "production" || p.projectRef !== PROJECT_REF) problems.push("evidence target is not the approved DeedLight Production project");
  if (!p || typeof p.collectorIdentity !== "string" || !p.collectorIdentity.trim()) problems.push("collector identity is missing");
  if (!p || !/^[a-f0-9]{64}$/.test(p.queryBundleSha256 || "")) problems.push("query-bundle fingerprint is missing");
  const captured = parseTime(p && p.capturedAt, "evidence capture timestamp", problems);
  if (Number.isFinite(captured) && (now - captured < 0 || now - captured > MAX_EVIDENCE_AGE_MS)) problems.push("evidence is stale or timestamp is in the future");
  if (!evidence || !evidence.history || evidence.history.complete !== true || !Array.isArray(evidence.history.rows)) problems.push("migration history export is incomplete");
  if (!evidence || !evidence.catalog || evidence.catalog.complete !== true || !Array.isArray(evidence.catalog.objects)) problems.push("live catalog export is incomplete");
  for (const kind of CATALOG_KINDS) {
    if (!evidence || !evidence.catalog || !Array.isArray(evidence.catalog.completeKinds) || !evidence.catalog.completeKinds.includes(kind)) {
      problems.push("catalog export does not attest complete " + kind);
    }
  }
  if (evidence && evidence.history && Array.isArray(evidence.history.rows)) {
    const versions = new Set(manifest.migrations.map((item) => item.version));
    for (const row of evidence.history.rows) {
      if (!row || typeof row.version !== "string" || !/^\d{12}$/.test(row.version) || !versions.has(row.version)) {
        problems.push("migration history contains malformed or unrecognized version");
      } else if (typeof row.name !== "string" || !row.name.trim() || !row.executedAt || !row.executedBy || !row.executionId) {
        problems.push("migration history row lacks exact name or execution metadata");
      }
    }
  }
}
function classifyOne(item, manifest, evidence, source, mappedEffects) {
  if (!source.get(item.path)?.valid) return { status: "Unknown", reasons: ["migration source fingerprint is not verified"] };
  const expected = mappedEffects.get(item.path);
  if (!expected) return { status: "Unknown", reasons: ["migration has no complete authenticated effect mapping"] };
  const catalog = new Map();
  for (const object of evidence.catalog.objects) {
    if (!object || !CATALOG_KINDS.includes(object.kind) || typeof object.identity !== "string" || !/^[a-f0-9]{64}$/.test(object.fingerprint || "")) {
      return { status: "Unknown", reasons: ["malformed live catalog object fingerprint"] };
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
  const exactRows = rows.filter((row) => row.name === expectedName && row.sourceBlobSha1 === item.blobSha1
    && Number.isFinite(Date.parse(row.executedAt)) && typeof row.executedBy === "string" && typeof row.executionId === "string");
  const wrongName = rows.some((row) => row.name !== expectedName);
  if (matches.length === expected.length) {
    if (duplicateVersion || rows.length !== 1 || exactRows.length !== 1) {
      return {
        status: "Schema represented but history ambiguous",
        schemaRepresented: true,
        historyRecorded: rows.length > 0,
        reasons: [duplicateVersion ? "duplicate migration version cannot establish exact source execution"
          : wrongName ? "history version is associated with a different migration name"
            : rows.length === 0 ? "schema effects exist without a history record"
              : "history does not bind the exact source blob and execution metadata"],
        matchedObjects: matches.length,
        historyRows: rows.length,
        exactExecutionEstablished: false,
      };
    }
    return { status: "Applied and verified", schemaRepresented: true, historyRecorded: true, reasons: [], matchedObjects: matches.length, historyRows: rows.length, exactExecutionEstablished: true };
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
  return { status: "Verified unapplied", schemaRepresented: false, historyRecorded: false, reasons: ["complete authenticated history and effect exports show no execution or represented effects"], matchedObjects: 0, historyRows: 0, exactExecutionEstablished: false };
}
export function analyzeMigrationEvidence({ rootDir, manifest, evidence, approvals, trustRoots, trustedTrustRootsSha256, now = Date.now(), expectedInventoryBlobSha1 = INVENTORY_BLOB_SHA1 }) {
  const problems = [];
  if (!trustRoots || trustRoots.schemaVersion !== 1 || !Array.isArray(trustRoots.keys)) problems.push("external trust-root bundle is missing or malformed");
  else {
    const rootDigest = sha256(Buffer.from(canonicalJson(trustRoots)));
    if (!/^[a-f0-9]{64}$/.test(trustedTrustRootsSha256 || "") || trustedTrustRootsSha256 !== rootDigest) {
      problems.push("external trust roots do not match the independently provisioned trust-root digest");
    }
    const keyIds = trustRoots.keys.map((key) => key.keyId);
    if (new Set(keyIds).size !== keyIds.length) problems.push("trust-root bundle contains duplicate key IDs");
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
  validateCollectorAuthority(collectorClaims, provenance, problems);
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
  process.stdout.write(JSON.stringify(report, null, 2) + "\n");
  const mode = options.mode || "accept";
  assert(mode === "accept" || mode === "report", "mode must be accept or report");
  if (mode === "accept" && report.acceptance !== "ACCEPTED") process.exitCode = 2;
  if (mode === "report" && report.acceptance !== "ACCEPTED") process.exitCode = 0;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
