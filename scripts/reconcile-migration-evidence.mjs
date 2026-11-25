import { createHash } from "node:crypto";
import { lstatSync, readFileSync, realpathSync } from "node:fs";
import path from "node:path";
import { gitBlobSha1, validateInventory } from "./verify-migration-inventory-aggregate.mjs";

const EXPECTED_PROJECT_REF = "xaipiovflxomcbfwtwmu";
const EXPECTED_INVENTORY_BLOB_SHA1 = "95d514a0bd97ff448c9507252eb1f5e69a507442";
const MAX_EVIDENCE_AGE_MS = 24 * 60 * 60 * 1000;
const OBJECT_KINDS = ["tables", "columns", "constraints", "indexes", "triggers", "policies", "routines"];

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
export function evidencePayload(evidence) {
  const { provenance, ...payload } = evidence;
  return Buffer.from(JSON.stringify(canonical(payload)));
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
function validateSourceInventory(rootDir, manifest, expectedInventoryBlobSha1) {
  validateInventory(manifest);
  const inventoryBytes = readRegularFile(rootDir, "supabase/migration-inventory.json");
  assert(gitBlobSha1(inventoryBytes) === expectedInventoryBlobSha1, "inventory manifest fingerprint mismatch");
  const source = new Map();
  for (const item of manifest.migrations) {
    const bytes = readRegularFile(rootDir, item.path);
    const actual = gitBlobSha1(bytes);
    if (actual !== item.blobSha1 || bytes.length !== item.byteLength) {
      source.set(item.path, { valid: false, reason: "source fingerprint or byte length differs from pinned inventory", actualBlobSha1: actual });
    } else source.set(item.path, { valid: true, blobSha1: actual });
  }
  return source;
}
function validateEvidence(evidence, now, trustedEvidenceSha256) {
  const reasons = [];
  if (!evidence || evidence.schemaVersion !== 1) reasons.push("unsupported or missing evidence schema");
  const p = evidence && evidence.provenance;
  if (!p || !/^[a-f0-9]{64}$/.test(p.payloadSha256 || "")) reasons.push("missing evidence payload digest");
  else if (sha256(evidencePayload(evidence)) !== p.payloadSha256) reasons.push("evidence payload digest mismatch");
  if (!/^[a-f0-9]{64}$/.test(trustedEvidenceSha256 || "") || trustedEvidenceSha256 !== (p && p.payloadSha256)) {
    reasons.push("independently approved evidence digest is missing or does not match; self-reported hashes are not trusted");
  }
  if (!p || !p.capturedAt || !Number.isFinite(Date.parse(p.capturedAt))) reasons.push("missing or invalid capture timestamp");
  else {
    const age = now - Date.parse(p.capturedAt);
    if (age < 0 || age > MAX_EVIDENCE_AGE_MS) reasons.push("evidence is stale or timestamp is in the future");
  }
  if (!p || p.environment !== "production" || p.projectRef !== EXPECTED_PROJECT_REF) reasons.push("evidence target is not the approved DeedLight Production project");
  if (!p || p.readOnly !== true || typeof p.collector !== "string" || !p.collector.trim()) reasons.push("read-only collector provenance is incomplete");
  if (!p || !/^[a-f0-9]{64}$/.test(p.queryBundleSha256 || "")) reasons.push("missing query-bundle fingerprint");
  if (!p || typeof p.approvalReference !== "string" || !p.approvalReference.trim()) reasons.push("missing DBA evidence approval reference");
  if (!evidence || !evidence.history || evidence.history.complete !== true || !Array.isArray(evidence.history.rows)) reasons.push("migration history export is incomplete");
  if (!evidence || !evidence.catalog || evidence.catalog.complete !== true || !Array.isArray(evidence.catalog.objects)) reasons.push("live catalog export is incomplete");
  for (const kind of OBJECT_KINDS) {
    if (!evidence || !evidence.catalog || !Array.isArray(evidence.catalog.completeKinds) || !evidence.catalog.completeKinds.includes(kind)) reasons.push("catalog export does not attest complete " + kind);
  }
  if (!evidence || !Array.isArray(evidence.migrationEffects) || evidence.migrationEffects.length !== 39) reasons.push("reviewed migration-effect mapping must contain all 39 migrations");
  if (!evidence || !evidence.mapping || !/^[a-f0-9]{64}$/.test(evidence.mapping.reviewedSha256 || "") || typeof evidence.mapping.reviewer !== "string" || !evidence.mapping.reviewer.trim()) {
    reasons.push("reviewed source-to-schema effect mapping is missing");
  }
  return reasons;
}
function classifyOne(item, manifest, evidence, source) {
  const sourceResult = source.get(item.path);
  if (!sourceResult || !sourceResult.valid) return { status: "Unknown", reasons: [sourceResult ? sourceResult.reason : "source evidence missing"] };
  const effects = evidence.migrationEffects.filter((entry) => entry.path === item.path);
  if (effects.length !== 1 || effects[0].blobSha1 !== item.blobSha1 || !Array.isArray(effects[0].expectedObjects) || effects[0].expectedObjects.length === 0) {
    return { status: "Unknown", reasons: ["missing, duplicate or mismatched reviewed effect mapping"] };
  }
  const expected = effects[0].expectedObjects;
  const identities = new Set();
  for (const object of expected) {
    if (!OBJECT_KINDS.includes(object.kind) || typeof object.identity !== "string" || !object.identity.trim() || !/^[a-f0-9]{64}$/.test(object.fingerprint || "")) {
      return { status: "Unknown", reasons: ["malformed expected catalog object fingerprint"] };
    }
    const key = object.kind + "\0" + object.identity;
    if (identities.has(key)) return { status: "Unknown", reasons: ["duplicate expected catalog object identity"] };
    identities.add(key);
  }
  const catalog = new Map();
  for (const object of evidence.catalog.objects) {
    if (!OBJECT_KINDS.includes(object.kind) || typeof object.identity !== "string" || !/^[a-f0-9]{64}$/.test(object.fingerprint || "")) {
      return { status: "Unknown", reasons: ["malformed live catalog object record"] };
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
  if (matches.length === expected.length) {
    if (duplicateVersion || rows.length !== 1) {
      return {
        status: "Schema represented but history ambiguous",
        reasons: [duplicateVersion
          ? "duplicate version identifies multiple distinct migration bodies; one history row cannot attest both"
          : rows.length === 0 ? "all mapped schema effects exist but no unique migration-history row exists" : "migration-history version is not unique"],
        matchedObjects: matches.length,
        historyRows: rows.length,
      };
    }
    return { status: "Applied and verified", reasons: [], matchedObjects: matches.length, historyRows: rows.length };
  }
  if (matches.length > 0 || mismatches.length > 0 || rows.length > 0) {
    return {
      status: "Partial or drifted",
      reasons: [
        ...(matches.length > 0 ? [matches.length + " of " + expected.length + " expected objects match"] : []),
        ...(mismatches.length > 0 ? [mismatches.length + " existing objects have unexpected fingerprints"] : []),
        ...(missing.length > 0 ? [missing.length + " expected objects are absent"] : []),
        ...(rows.length > 0 ? ["migration history claims this version despite incomplete schema effects"] : []),
      ],
      matchedObjects: matches.length,
      historyRows: rows.length,
    };
  }
  return { status: "Verified unapplied", reasons: ["complete history and catalog exports show no mapped effects and no history row"], matchedObjects: 0, historyRows: 0 };
}
export function analyzeMigrationEvidence({ rootDir, manifest, evidence, trustedEvidenceSha256, expectedInventoryBlobSha1 = EXPECTED_INVENTORY_BLOB_SHA1, now = Date.now() }) {
  const source = validateSourceInventory(rootDir, manifest, expectedInventoryBlobSha1);
  const evidenceProblems = validateEvidence(evidence, now, trustedEvidenceSha256);
  const reports = manifest.migrations.map((item) => {
    if (evidenceProblems.length > 0) return { path: item.path, version: item.version, blobSha1: item.blobSha1, status: "Unknown", reasons: evidenceProblems };
    const result = classifyOne(item, manifest, evidence, source);
    return { path: item.path, version: item.version, blobSha1: item.blobSha1, ...result };
  });
  return {
    schemaVersion: 1,
    project: "DeedLight",
    productionEvidenceUsed: evidenceProblems.length === 0,
    evidenceProblems,
    sourceInventory: { migrationCount: manifest.migrations.length, uniqueVersionCount: new Set(manifest.migrations.map((item) => item.version)).size },
    duplicateVersionPolicy: "A history row for 202607260007 never proves both distinct migration bodies executed.",
    classifications: reports,
    counts: Object.fromEntries(["Applied and verified", "Schema represented but history ambiguous", "Verified unapplied", "Partial or drifted", "Unknown"]
      .map((status) => [status, reports.filter((entry) => entry.status === status).length])),
    mutationPerformed: false,
  };
}
function main() {
  const args = process.argv.slice(2);
  if (args.length !== 2) throw new Error("usage: node scripts/reconcile-migration-evidence.mjs <read-only-production-evidence.json> <independently-approved-payload-sha256>");
  const rootDir = process.cwd();
  const manifest = JSON.parse(readFileSync(path.join(rootDir, "supabase/migration-inventory.json"), "utf8"));
  const evidence = JSON.parse(readFileSync(args[0], "utf8"));
  const report = analyzeMigrationEvidence({ rootDir, manifest, evidence, trustedEvidenceSha256: args[1] });
  process.stdout.write(JSON.stringify(report, null, 2) + "\n");
  if (report.evidenceProblems.length || report.counts.Unknown || report.counts["Partial or drifted"]) process.exitCode = 2;
}
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname)) main();
