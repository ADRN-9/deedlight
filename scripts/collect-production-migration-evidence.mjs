#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createHash, timingSafeEqual } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";

export const RECEIPT_SCHEMA_VERSION = 1;
export const PROJECT_REF = "xaipiovflxomcbfwtwmu";
export const SQL_PATH = "scripts/production-migration-readonly-audit.sql";
export const SQL_SHA256 = "02f6db1822213453deb9fbe2588b893fbcd3ff312c4bb6b523238c7968db9d13";
export const SQL_GIT_BLOB_SHA1 = "e55ed9207e8540d03de51c79e56c75d0bed130d1";
export const INVENTORY_GIT_BLOB_SHA1 = "95d514a0bd97ff448c9507252eb1f5e69a507442";
const MAX_OUTPUT_BYTES = 64 * 1024 * 1024;
const EXECUTION_TIMEOUT_MS = 90_000;
const COLLECTOR_ID = "deedlight-readonly-collector-v1";
const PSQL_BINARY = "/usr/bin/psql";
const GIT_BINARY = "/usr/bin/git";

export class CollectorError extends Error {
  constructor(code) { super(code); this.name = "CollectorError"; this.code = code; }
}
export function sha256(value) { return createHash("sha256").update(value).digest("hex"); }
export function canonicalJson(value) {
  if (value === null || typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new CollectorError("INVALID_CANONICAL_NUMBER");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return "[" + value.map(canonicalJson).join(",") + "]";
  if (typeof value !== "object") throw new CollectorError("INVALID_CANONICAL_VALUE");
  return "{" + Object.keys(value).sort().map((key) => JSON.stringify(key) + ":" + canonicalJson(value[key])).join(",") + "}";
}
export function parseCsv(input) {
  const text = Buffer.isBuffer(input) ? input.toString("utf8") : String(input);
  if (Buffer.isBuffer(input) && !Buffer.from(text, "utf8").equals(input)) throw new CollectorError("INVALID_CSV_UTF8");
  if (text.includes("\u0000")) throw new CollectorError("INVALID_CSV_NUL");
  const normalized = text.replace(/\r\n/g, "\n");
  const rows = []; let row = []; let cell = ""; let quoted = false; let quoteClosed = false;
  for (let i = 0; i < normalized.length; i += 1) {
    const ch = normalized[i];
    if (quoted) {
      if (ch === '"') {
        if (normalized[i + 1] === '"') { cell += '"'; i += 1; }
        else { quoted = false; quoteClosed = true; }
      } else cell += ch;
    } else if (quoteClosed && ch !== "," && ch !== "\n") {
      throw new CollectorError("INVALID_CSV_AFTER_QUOTE");
    } else if (ch === '"' && cell.length === 0 && !quoteClosed) quoted = true;
    else if (ch === '"') throw new CollectorError("INVALID_CSV_QUOTE");
    else if (ch === ",") { row.push(cell); cell = ""; quoteClosed = false; }
    else if (ch === "\n") {
      row.push(cell);
      if (!(row.length === 1 && row[0] === "")) rows.push(row);
      row = []; cell = ""; quoteClosed = false;
    } else cell += ch;
  }
  if (quoted) throw new CollectorError("TRUNCATED_CSV_QUOTE");
  if (cell.length || row.length) { row.push(cell); rows.push(row); }
  if (!rows.length) throw new CollectorError("EMPTY_SQL_OUTPUT");
  return rows;
}
export function validateSqlOutput(csv) {
  const rows = parseCsv(csv);
  const markerHeaderIndex = rows.findIndex((row) => row.length === 1 && row[0] === "collector_transaction_closed");
  if (markerHeaderIndex < 0 || markerHeaderIndex !== rows.length - 2) throw new CollectorError("TRANSACTION_CLOSE_MARKER_MISSING");
  if (rows.at(-1).length !== 1 || rows.at(-1)[0] !== "t") throw new CollectorError("TRANSACTION_ROLLBACK_NOT_VERIFIED");
  const projectionHeaderIndex = rows.findIndex((row) =>
    row.includes("evidence_projection") && row.includes("database_count") &&
    row.includes("database_oid") && row.includes("expanded_acl_edges"));
  if (projectionHeaderIndex < 0 || projectionHeaderIndex >= markerHeaderIndex) throw new CollectorError("DATABASE_ACL_PROJECTION_MISSING");
  const header = rows[projectionHeaderIndex];
  const projectionColumn = header.indexOf("evidence_projection");
  const countColumn = header.indexOf("database_count");
  const oidColumn = header.indexOf("database_oid");
  const databaseRows = rows.slice(projectionHeaderIndex + 1, markerHeaderIndex)
    .filter((row) => row[projectionColumn] === "database_acl_v1");
  if (!databaseRows.length) throw new CollectorError("DATABASE_ACL_PROJECTION_EMPTY");
  const expectedCount = Number(databaseRows[0][countColumn]);
  if (!Number.isSafeInteger(expectedCount) || expectedCount < 1 || databaseRows.length !== expectedCount ||
      databaseRows.some((row) => Number(row[countColumn]) !== expectedCount || row.length !== header.length ||
        !/^\d+$/.test(row[oidColumn] ?? ""))) throw new CollectorError("DATABASE_ACL_PROJECTION_INCOMPLETE");
  const resultRows = rows.slice(0, markerHeaderIndex);
  if (resultRows.length < 15) throw new CollectorError("SQL_RESULT_SET_INCOMPLETE");
  return { rows, resultRows, databaseAclRows: databaseRows.length, transactionClosed: true };
}
function assertOutsideRepository(filePath, repoPath, code) {
  const resolved = realpathSync(filePath);
  const relative = path.relative(repoPath, resolved);
  if (relative === "" || (relative !== ".." && !relative.startsWith(".." + path.sep)) || path.isAbsolute(relative)) throw new CollectorError(code);
  return resolved;
}
function requirePrivateRegularFile(filePath, code) {
  const linkStat = lstatSync(filePath);
  if (linkStat.isSymbolicLink() || !linkStat.isFile()) throw new CollectorError(code);
  const fileStat = statSync(filePath);
  if ((fileStat.mode & 0o077) !== 0 ||
      (typeof process.getuid === "function" && fileStat.uid !== process.getuid())) throw new CollectorError(code);
  return realpathSync(filePath);
}
function gitValue(repoPath, args, code) {
  const result = spawnSync(GIT_BINARY, args, {
    cwd: repoPath, encoding: "utf8",
    env: { PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: process.env.HOME ?? "/tmp", LC_ALL: "C" },
    timeout: 5_000, maxBuffer: 1024 * 1024, windowsHide: true,
  });
  if (result.error || result.status !== 0) throw new CollectorError(code);
  return result.stdout.trim();
}
function loadProfile(profilePath, repoPath) {
  const profileRealPath = requirePrivateRegularFile(profilePath, "ENDPOINT_PROFILE_FILE_INVALID");
  assertOutsideRepository(profileRealPath, repoPath, "ENDPOINT_PROFILE_MUST_BE_EXTERNAL");
  const bytes = readFileSync(profileRealPath);
  const expectedDigest = process.env.DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256 ?? "";
  if (!/^[a-f0-9]{64}$/.test(expectedDigest) ||
      !timingSafeEqual(Buffer.from(sha256(bytes), "hex"), Buffer.from(expectedDigest, "hex"))) {
    throw new CollectorError("ENDPOINT_PROFILE_DIGEST_MISMATCH");
  }
  let profile;
  try { profile = JSON.parse(bytes.toString("utf8")); }
  catch { throw new CollectorError("ENDPOINT_PROFILE_INVALID_JSON"); }
  const allowedKeys = ["schemaVersion", "projectRef", "host", "port", "database", "username", "tlsRootCertPath", "passwordFilePath"];
  if (!profile || Object.keys(profile).sort().join("|") !== allowedKeys.sort().join("|") ||
      profile.schemaVersion !== 1 || profile.projectRef !== PROJECT_REF ||
      profile.host !== "db." + PROJECT_REF + ".supabase.co" || profile.port !== 5432 ||
      !(profile.database === "postgres" || (profile.database === "deedlight_migration_order_test" && process.env.CI === "true" && process.env.DEEDLIGHT_DISPOSABLE_FIXTURE_AUTHORIZATION === "deedlight-postgres16-ci-disposable-v1")) || profile.username !== "deedlight_catalog_auditor") {
    throw new CollectorError("ENDPOINT_IDENTITY_MISMATCH");
  }
  if (typeof profile.tlsRootCertPath !== "string" || !path.isAbsolute(profile.tlsRootCertPath) ||
      typeof profile.passwordFilePath !== "string" || !path.isAbsolute(profile.passwordFilePath)) {
    throw new CollectorError("ENDPOINT_CREDENTIAL_PROFILE_INVALID");
  }
  profile.tlsRootCertPath = assertOutsideRepository(profile.tlsRootCertPath, repoPath, "TLS_CA_MUST_BE_EXTERNAL");
  profile.passwordFilePath = requirePrivateRegularFile(profile.passwordFilePath, "PASSWORD_FILE_INVALID");
  assertOutsideRepository(profile.passwordFilePath, repoPath, "PASSWORD_FILE_MUST_BE_EXTERNAL");
  if (!statSync(profile.tlsRootCertPath).isFile()) throw new CollectorError("TLS_CA_INVALID");
  return { profile, profileDigest: sha256(bytes) };
}
function runPsql({ repoPath, profile, sqlPath, commitSha }) {
  const options = [
    "--no-psqlrc", "--no-password", "--set=ON_ERROR_STOP=1", "--csv", "--quiet",
    "--host", profile.host, "--port", String(profile.port), "--username", profile.username, "--dbname", profile.database,
    "--command",
    "SET deedlight.expected_project_ref = '" + PROJECT_REF + "'; " +
    "SET deedlight.repository_sha = '" + commitSha + "'; " +
    "SET deedlight.authenticated_principal = 'deedlight_catalog_auditor';",
    "--file", sqlPath,
    "--command",
    "SELECT (pg_catalog.current_setting('transaction_read_only') = 'off' " +
    "AND pg_catalog.txid_current_if_assigned() IS NULL) AS collector_transaction_closed;",
  ];
  const cleanEnv = {
    PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: process.env.HOME ?? "/tmp", LC_ALL: "C",
    PGHOST: profile.host, PGPORT: String(profile.port), PGUSER: profile.username, PGDATABASE: profile.database,
    PGPASSFILE: profile.passwordFilePath, PGSSLROOTCERT: profile.tlsRootCertPath, PGSSLMODE: "verify-full",
    PGCONNECT_TIMEOUT: "8", PGAPPNAME: "deedlight-production-evidence-collector",
  };
  const result = spawnSync(PSQL_BINARY, options, {
    cwd: repoPath, env: cleanEnv, encoding: null,
    timeout: EXECUTION_TIMEOUT_MS, maxBuffer: MAX_OUTPUT_BYTES, windowsHide: true,
  });
  if (result.error || result.status !== 0 || !Buffer.isBuffer(result.stdout) ||
      result.stdout.length === 0 || result.stdout.length >= MAX_OUTPUT_BYTES) {
    result.stdout?.fill?.(0); result.stderr?.fill?.(0);
    throw new CollectorError(result.error?.code === "ETIMEDOUT" ? "COLLECTION_TIMEOUT" : "SQL_EXECUTION_FAILED");
  }
  result.stderr?.fill?.(0);
  return result.stdout;
}
export function buildReceipt({ profile, profileDigest, commitSha, startedAt, completedAt, csv, validation }) {
  return {
    schemaVersion: 1,
    kind: "deedlight-production-migration-collection",
    status: "UNSIGNED_NOT_ACCEPTED",
    projectRef: PROJECT_REF,
    endpoint: {
      hostname: profile.host, port: profile.port, database: profile.database, tlsMode: "verify-full",
      tlsVerified: true, tlsHostnameVerified: true, tlsChainVerified: true,
      projectIdentityMethod: "independently-pinned-profile-and-project-specific-TLS-hostname",
      tlsRootCertificateSha256: sha256(readFileSync(profile.tlsRootCertPath)),
      independentlyPinnedProfileSha256: profileDigest,
    },
    source: {
      repositoryCommitSha: commitSha, migrationInventoryGitBlobSha1: INVENTORY_GIT_BLOB_SHA1,
      sqlBundlePath: SQL_PATH, sqlBundleGitBlobSha1: SQL_GIT_BLOB_SHA1, sqlBundleSha256: SQL_SHA256,
    },
    execution: {
      collectorId: COLLECTOR_ID, authenticatedPrincipal: profile.username, expectedEffectivePrincipal: profile.username,
      transactionIsolation: "repeatable read", readOnly: true, transactionRollbackVerified: validation.transactionClosed,
      startedAt, completedAt, outputFormat: "PostgreSQL psql CSV",
      canonicalization: "RFC4180 CSV parsed as ordered string-cell records; UTF-8 canonical JSON with lexicographically sorted object keys and preserved array order; SHA-256",
      resultRecordCount: validation.resultRows.length, databaseAclV1RowCount: validation.databaseAclRows,
      canonicalResultSha256: sha256(Buffer.from(canonicalJson(validation.resultRows), "utf8")),
      evidenceFileSha256: sha256(csv),
    },
    evidence: { file: "evidence.csv", mediaType: "text/csv", byteLength: csv.length, sha256: sha256(csv) },
    signing: {
      state: "NOT_SIGNED", keyId: null, signature: null,
      acceptance: "PROHIBITED_PENDING_INDEPENDENT_SIGNING_AND_VERIFICATION",
    },
  };
}
export function verifyReceiptAndEvidence(receipt, csv) {
  if (!receipt || receipt.schemaVersion !== 1 || receipt.kind !== "deedlight-production-migration-collection" ||
      receipt.status !== "UNSIGNED_NOT_ACCEPTED" || receipt.signing?.state !== "NOT_SIGNED") {
    throw new CollectorError("RECEIPT_SCHEMA_OR_STATUS_INVALID");
  }
  if (sha256(csv) !== receipt.evidence?.sha256 || sha256(csv) !== receipt.execution?.evidenceFileSha256) {
    throw new CollectorError("EVIDENCE_DIGEST_MISMATCH");
  }
  const validation = validateSqlOutput(csv);
  const digest = sha256(Buffer.from(canonicalJson(validation.resultRows), "utf8"));
  if (digest !== receipt.execution?.canonicalResultSha256 ||
      validation.databaseAclRows !== receipt.execution?.databaseAclV1RowCount || !validation.transactionClosed) {
    throw new CollectorError("RECEIPT_RESULT_BINDING_MISMATCH");
  }
  return true;
}
export function collect({ profilePath, outputDir }) {
  const repoPath = realpathSync(process.cwd());
  const commitSha = gitValue(repoPath, ["rev-parse", "HEAD"], "REPOSITORY_COMMIT_UNAVAILABLE");
  if (!/^[a-f0-9]{40}$/.test(commitSha)) throw new CollectorError("REPOSITORY_COMMIT_INVALID");
  const inventoryBlob = gitValue(repoPath, ["rev-parse", "HEAD:supabase/migration-inventory.json"], "INVENTORY_BLOB_UNAVAILABLE");
  const sqlBlob = gitValue(repoPath, ["rev-parse", "HEAD:" + SQL_PATH], "SQL_BUNDLE_BLOB_UNAVAILABLE");
  if (inventoryBlob !== INVENTORY_GIT_BLOB_SHA1) throw new CollectorError("MIGRATION_INVENTORY_PIN_MISMATCH");
  if (sqlBlob !== SQL_GIT_BLOB_SHA1) throw new CollectorError("SQL_BUNDLE_GIT_PIN_MISMATCH");
  const sqlPath = path.join(repoPath, SQL_PATH);
  if (sha256(readFileSync(sqlPath)) !== SQL_SHA256) throw new CollectorError("SQL_BUNDLE_SHA256_MISMATCH");
  const { profile, profileDigest } = loadProfile(profilePath, repoPath);
  const absoluteOutput = path.resolve(outputDir);
  const outputParent = realpathSync(path.dirname(absoluteOutput));
  assertOutsideRepository(outputParent, repoPath, "EVIDENCE_OUTPUT_MUST_BE_EXTERNAL");
  if (existsSync(absoluteOutput)) throw new CollectorError("OUTPUT_DIRECTORY_ALREADY_EXISTS");
  mkdirSync(absoluteOutput, { mode: 0o700 });
  const outputRealPath = realpathSync(absoluteOutput);
  assertOutsideRepository(outputRealPath, repoPath, "EVIDENCE_OUTPUT_MUST_BE_EXTERNAL");
  const startedAt = new Date().toISOString();
  const csv = runPsql({ repoPath, profile, sqlPath, commitSha });
  let evidencePath;
  let receiptPath;
  try {
    const validation = validateSqlOutput(csv);
    const completedAt = new Date().toISOString();
    const receipt = buildReceipt({ profile, profileDigest, commitSha, startedAt, completedAt, csv, validation });
    const receiptBytes = Buffer.from(canonicalJson(receipt) + "\n", "utf8");
    evidencePath = path.join(outputRealPath, "evidence.csv");
    receiptPath = path.join(outputRealPath, "receipt.json");
    writeFileSync(evidencePath, csv, { flag: "wx", mode: 0o600 });
    writeFileSync(receiptPath, receiptBytes, { flag: "wx", mode: 0o600 });
    return {
      status: receipt.status, receiptPath, receiptSha256: sha256(receiptBytes),
      evidenceSha256: receipt.evidence.sha256, databaseAclV1RowCount: validation.databaseAclRows,
    };
  } catch (error) {
    for (const filePath of [receiptPath, evidencePath]) {
      if (filePath && existsSync(filePath)) unlinkSync(filePath);
    }
    csv.fill(0);
    throw error;
  } finally { csv.fill(0); }
}
function main() {
  const args = process.argv.slice(2); const values = {};
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === "--profile" && args[i + 1]) values.profilePath = args[++i];
    else if (args[i] === "--output" && args[i + 1]) values.outputDir = args[++i];
    else throw new CollectorError("USAGE_INVALID");
  }
  if (!values.profilePath || !values.outputDir) throw new CollectorError("USAGE_INVALID");
  try { process.stdout.write(JSON.stringify(collect(values)) + "\n"); }
  catch (error) {
    const code = error instanceof CollectorError ? error.code : "COLLECTION_FAILED";
    process.stderr.write("DeedLight evidence collection failed closed: " + code + "\n");
    process.exitCode = 1;
  }
}
if (process.argv[1] && path.resolve(process.argv[1]) === new URL(import.meta.url).pathname) main();
