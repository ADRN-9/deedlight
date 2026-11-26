#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createHash, timingSafeEqual } from "node:crypto";
import { chmodSync, closeSync, constants as fsConstants, existsSync, fstatSync, lstatSync, mkdirSync, mkdtempSync, openSync, readFileSync, readSync, realpathSync, rmSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";

export const RECEIPT_SCHEMA_VERSION = 1;
export const PROJECT_REF = "xaipiovflxomcbfwtwmu";
export const SQL_PATH = "scripts/production-migration-readonly-audit.sql";
export const SQL_SHA256 = "afda6bcfc9f7abc7765b8dfb54bf02d1cdb0d8062da2a9f953336b638d13af7d";
export const SQL_GIT_BLOB_SHA1 = "8f8c38ba0c2a463ee25c6dae1dc1b15e24e3819f";
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
  const CR = String.fromCharCode(13), LF = String.fromCharCode(10);
  const rows = []; let row = []; let cell = ""; let quoted = false; let quoteClosed = false;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') { cell += '"'; i += 1; }
        else { quoted = false; quoteClosed = true; }
      } else cell += ch;
      continue;
    }
    if (ch === CR) {
      if (text[i + 1] !== LF) throw new CollectorError("INVALID_CSV_BARE_CR");
      row.push(cell);
      if (!(row.length === 1 && row[0] === "")) rows.push(row);
      row = []; cell = ""; quoteClosed = false; i += 1; continue;
    }
    if (quoteClosed && ch !== "," && ch !== LF) throw new CollectorError("INVALID_CSV_AFTER_QUOTE");
    if (ch === '"' && cell.length === 0 && !quoteClosed) { quoted = true; continue; }
    if (ch === '"') throw new CollectorError("INVALID_CSV_QUOTE");
    if (ch === ",") { row.push(cell); cell = ""; quoteClosed = false; continue; }
    if (ch === LF) {
      row.push(cell);
      if (!(row.length === 1 && row[0] === "")) rows.push(row);
      row = []; cell = ""; quoteClosed = false; continue;
    }
    cell += ch;
  }
  if (quoted) throw new CollectorError("TRUNCATED_CSV_QUOTE");
  if (cell.length || row.length || quoteClosed) { row.push(cell); rows.push(row); }
  if (!rows.length) throw new CollectorError("EMPTY_SQL_OUTPUT");
  return rows;
}
export function validateSqlOutput(csv) {
  const rows = parseCsv(csv);
  const markerHeaderIndex = rows.findIndex((row) => row.length === 1 && row[0] === "collector_transaction_closed");
  if (markerHeaderIndex < 0 || markerHeaderIndex !== rows.length - 2) throw new CollectorError("TRANSACTION_CLOSE_MARKER_MISSING");
  if (rows.at(-1).length !== 1 || rows.at(-1)[0] !== "t") throw new CollectorError("TRANSACTION_ROLLBACK_NOT_VERIFIED");
  const expectedHeader=["evidence_projection","database_count","database_oid","database_name","allows_connections","is_template","owner_oid","owner_name","datacl_was_null","acl_expansion_source","expanded_acl_edges"];
  const projectionHeaderIndex=rows.findIndex(row=>expectedHeader.filter(column=>row.includes(column)).length>=expectedHeader.length-1);
  if(projectionHeaderIndex<0||projectionHeaderIndex>=markerHeaderIndex)throw new CollectorError("DATABASE_ACL_PROJECTION_MISSING");
  const historyHeader=["version","name","recordedStatementCount"];
  const historyHeaderIndex=rows.findIndex(row=>row.length===historyHeader.length&&row.every((value,index)=>value===historyHeader[index]));
  if(historyHeaderIndex<0||historyHeaderIndex>=projectionHeaderIndex)throw new CollectorError("MIGRATION_HISTORY_PROJECTION_MISSING");
  const historyRows=rows.slice(historyHeaderIndex+1,projectionHeaderIndex);
  const seenVersions=new Set();
  let previousVersion="";
  const migrationHistoryRows=historyRows.map((row)=>{
    if(row.length!==3)throw new CollectorError("MIGRATION_HISTORY_ROW_INVALID");
    const [version,rawName,rawCount]=row;
    if(!/^[0-9]{12}$/.test(version)||seenVersions.has(version)||version<=previousVersion)throw new CollectorError("MIGRATION_HISTORY_VERSION_INVALID");
    const name=rawName===""||rawName==="NULL"?null:rawName;
    if(name!==null&&!/^[A-Za-z0-9_-]+$/.test(name))throw new CollectorError("MIGRATION_HISTORY_NAME_INVALID");
    const recordedStatementCount=rawCount===""||rawCount==="NULL"?null:Number(rawCount);
    if(recordedStatementCount!==null&&(!/^(0|[1-9][0-9]*)$/.test(rawCount)||!Number.isSafeInteger(recordedStatementCount)||recordedStatementCount<0))throw new CollectorError("MIGRATION_HISTORY_STATEMENT_COUNT_INVALID");
    seenVersions.add(version);
    previousVersion=version;
    return {version,name,recordedStatementCount};
  });
  const header=rows[projectionHeaderIndex];
  if(header.length!==11||new Set(header).size!==11||header.some((v,i)=>v!==expectedHeader[i]))throw new CollectorError("DATABASE_ACL_PROJECTION_SCHEMA_INVALID");
  const [projectionColumn,countColumn,oidColumn,nameColumn,allowsColumn,templateColumn,ownerOidColumn,ownerNameColumn,dataclNullColumn,aclSourceColumn,edgesColumn]=expectedHeader.map(v=>header.indexOf(v));
  const databaseRows=rows.slice(projectionHeaderIndex+1,markerHeaderIndex);if(!databaseRows.length)throw new CollectorError("DATABASE_ACL_PROJECTION_EMPTY");
  const positiveUint32=v=>typeof v==="string"&&/^[1-9][0-9]*$/.test(v)&&Number(v)<=0xffffffff;
  const expectedCount=Number(databaseRows[0][countColumn]);const databaseOids=new Set();let previousDatabaseOid=-1;
  if(!Number.isSafeInteger(expectedCount)||expectedCount<1||databaseRows.length!==expectedCount||databaseRows.some(row=>
    row.length!==11||row[projectionColumn]!=="database_acl_v1"||!/^[1-9][0-9]*$/.test(row[countColumn]??"")||Number(row[countColumn])!==expectedCount||
    !positiveUint32(row[oidColumn])||!positiveUint32(row[ownerOidColumn])||typeof row[nameColumn]!=="string"||!row[nameColumn]||
    !["t","f"].includes(row[allowsColumn])||!["t","f"].includes(row[templateColumn])||typeof row[ownerNameColumn]!=="string"||!row[ownerNameColumn]||
    !["t","f"].includes(row[dataclNullColumn])||!["built_in_default","explicit"].includes(row[aclSourceColumn])||
    (row[dataclNullColumn]==="t")!==(row[aclSourceColumn]==="built_in_default")))throw new CollectorError("DATABASE_ACL_PROJECTION_INCOMPLETE");
  for(const row of databaseRows){
    const dbOid=Number(row[oidColumn]);if(databaseOids.has(dbOid)||dbOid<=previousDatabaseOid)throw new CollectorError("DATABASE_ACL_PROJECTION_DUPLICATED_OR_UNORDERED");databaseOids.add(dbOid);previousDatabaseOid=dbOid;
    let edges;try{edges=JSON.parse(row[edgesColumn]);}catch{throw new CollectorError("DATABASE_ACL_EDGES_INVALID_JSON");}
    const parseOid=(v,zero=false)=>{if(typeof v==="string"){if(!/^(?:0|[1-9][0-9]*)$/.test(v))return null;const n=Number(v);return Number.isSafeInteger(n)&&n<=0xffffffff&&(zero||n>0)?n:null;}return typeof v==="number"&&Number.isSafeInteger(v)&&v>=(zero?0:1)&&v<=0xffffffff?v:null;};
    const seen=new Set();let previous=null;if(!Array.isArray(edges))throw new CollectorError("DATABASE_ACL_EDGES_INVALID");
    for(const edge of edges){
      const keys=["grantee_oid","grantee_name","grantor_oid","grantor_name","privilege_type","is_grantable"];
      const grantee=edge&&typeof edge==="object"?parseOid(edge.grantee_oid,true):null,grantor=edge&&typeof edge==="object"?parseOid(edge.grantor_oid):null;
      if(!edge||typeof edge!=="object"||Array.isArray(edge)||Object.keys(edge).sort().join("|")!==keys.slice().sort().join("|")||grantee===null||grantor===null||
        typeof edge.grantee_name!=="string"||!edge.grantee_name||typeof edge.grantor_name!=="string"||!edge.grantor_name||
        typeof edge.privilege_type!=="string"||!edge.privilege_type||typeof edge.is_grantable!=="boolean"||
        (grantee===0&&edge.grantee_name!=="PUBLIC")||(grantee!==0&&edge.grantee_name==="PUBLIC"))throw new CollectorError("DATABASE_ACL_EDGES_INVALID");
      const logical=JSON.stringify([grantee,grantor,edge.privilege_type]);if(seen.has(logical))throw new CollectorError("DATABASE_ACL_EDGES_DUPLICATED");seen.add(logical);
      const order=[grantee,grantor,edge.privilege_type,edge.is_grantable?1:0];
      if(previous){const[pg,pr,pp,pf]=previous,[cg,cr,cp,cf]=order;if(!(pg<cg||pg===cg&&(pr<cr||pr===cr&&(pp<cp||pp===cp&&pf<=cf))))throw new CollectorError("DATABASE_ACL_EDGES_UNORDERED");}previous=order;
    }
  }
  const resultRows = rows.slice(0, markerHeaderIndex);
  if (resultRows.length < 15) throw new CollectorError("SQL_RESULT_SET_INCOMPLETE");
  return { rows, resultRows, databaseAclRows: databaseRows.length, migrationHistoryRows, transactionClosed: true };
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
function readFdBytes(fd) {
  const size = fstatSync(fd).size, bytes = Buffer.alloc(size);
  let offset = 0;
  while (offset < size) {
    const count = readSync(fd, bytes, offset, size - offset, offset);
    if (count <= 0) throw new CollectorError("TLS_CA_CHANGED_DURING_COLLECTION");
    offset += count;
  }
  return bytes;
}
function digestFd(fd) { return sha256(readFdBytes(fd)); }
export function openPinnedCa(caPath, expectedDigest) {
  if (!/^[a-f0-9]{64}$/.test(expectedDigest ?? "")) throw new CollectorError("TLS_CA_PIN_INVALID");
  const absolutePath = path.resolve(caPath), parentPath = path.dirname(absolutePath), parent = lstatSync(parentPath);
  if (parent.isSymbolicLink() || !parent.isDirectory() || realpathSync(parentPath) !== parentPath ||
      (parent.mode & 0o077) !== 0 || (typeof process.getuid === "function" && parent.uid !== process.getuid())) {
    throw new CollectorError("TLS_CA_DIRECTORY_INVALID");
  }
  const link = lstatSync(absolutePath);
  if (link.isSymbolicLink() || !link.isFile() || (link.mode & 0o077) !== 0 ||
      (typeof process.getuid === "function" && link.uid !== process.getuid())) throw new CollectorError("TLS_CA_INVALID");
  const fd = openSync(absolutePath, fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0));
  try {
    const opened = fstatSync(fd);
    if (!opened.isFile() || opened.dev !== link.dev || opened.ino !== link.ino) throw new CollectorError("TLS_CA_REPLACED");
    const digest = digestFd(fd);
    if (!timingSafeEqual(Buffer.from(digest, "hex"), Buffer.from(expectedDigest, "hex"))) {
      throw new CollectorError("TLS_CA_DIGEST_MISMATCH");
    }
    return { fd, path: absolutePath, dev: opened.dev, ino: opened.ino, digest, fdClosed: false, privateDirectory: null };
  } catch (error) { closeSync(fd); throw error; }
}

export function cleanupPinnedCa(guard, fsOps = {}) {
  if (!guard) return;
  try {
    if (!guard.fdClosed) {
      closeSync(guard.fd);
      guard.fdClosed = true;
    }
  } finally {
    if (guard.privateDirectory) {
      const directory = guard.privateDirectory;
      guard.privateDirectory = null;
      (fsOps.rmSync ?? rmSync)(directory, { recursive: true, force: true });
    }
  }
}

export function createPinnedCaSnapshot(guard, fsOps = {}) {
  const makeDirectory = fsOps.mkdtempSync ?? mkdtempSync;
  const makeDirectoryMode = fsOps.chmodSync ?? chmodSync;
  const writeFile = fsOps.writeFileSync ?? writeFileSync;
  const remove = fsOps.rmSync ?? rmSync;
  let directory;
  try {
    const copiedBytes = readFdBytes(guard.fd);
    if (sha256(copiedBytes) !== guard.digest) throw new CollectorError("TLS_CA_CHANGED_DURING_COLLECTION");
    directory = makeDirectory(path.join(fsOps.tmpdir ?? tmpdir(), "deedlight-ca-"));
    makeDirectoryMode(directory, 0o700);
    const snapshotPath = path.join(directory, "root.crt");
    writeFile(snapshotPath, copiedBytes, { flag: "wx", mode: 0o600 });
    makeDirectoryMode(snapshotPath, 0o600);
    if (sha256(readFileSync(snapshotPath)) !== guard.digest) throw new CollectorError("TLS_CA_SNAPSHOT_DIGEST_MISMATCH");
    guard.privateDirectory = directory;
    return snapshotPath;
  } catch (error) {
    try {
      if (directory) remove(directory, { recursive: true, force: true });
    } finally {
      cleanupPinnedCa(guard);
    }
    throw error;
  }
}

export function assertPinnedCaUnchanged(guard) {
  try {
    const currentPath = lstatSync(guard.path), opened = fstatSync(guard.fd);
    if (currentPath.isSymbolicLink() || !currentPath.isFile() || currentPath.dev !== guard.dev ||
        currentPath.ino !== guard.ino || opened.dev !== guard.dev || opened.ino !== guard.ino ||
        digestFd(guard.fd) !== guard.digest) throw new CollectorError("TLS_CA_CHANGED_DURING_COLLECTION");
  } catch (error) {
    if (error instanceof CollectorError) throw error;
    throw new CollectorError("TLS_CA_CHANGED_DURING_COLLECTION");
  }
  return true;
}

export function withPinnedCaCleanup(loaded, action) {
  try { return action(); }
  finally { cleanupPinnedCa(loaded?.profile?.tlsCaGuard); }
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
  profile.tlsCaGuard = openPinnedCa(profile.tlsRootCertPath, process.env.DEEDLIGHT_COLLECTOR_TLS_CA_SHA256 ?? "");
  profile.tlsRootCertificateSha256 = profile.tlsCaGuard.digest;
  profile.tlsRootCertPath = createPinnedCaSnapshot(profile.tlsCaGuard);
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
  assertPinnedCaUnchanged(profile.tlsCaGuard);
  return {
    schemaVersion: 1,
    kind: "deedlight-production-migration-collection",
    status: "UNSIGNED_NOT_ACCEPTED",
    projectRef: PROJECT_REF,
    endpoint: {
      hostname: profile.host, port: profile.port, database: profile.database, tlsMode: "verify-full",
      tlsVerified: true, tlsHostnameVerified: true, tlsChainVerified: true,
      projectIdentityMethod: "independently-pinned-profile-and-project-specific-TLS-hostname",
      tlsRootCertificateSha256: profile.tlsRootCertificateSha256,
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
      resultRecordCount: validation.resultRows.length, databaseAclV1RowCount: validation.databaseAclRows, migrationHistoryRowCount: validation.migrationHistoryRows.length,
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
const exactKeys=(v,keys)=>v&&typeof v==="object"&&!Array.isArray(v)&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
const hex=(v,n)=>typeof v==="string"&&new RegExp("^[a-f0-9]{"+n+"}$").test(v);
function parseStrictTimestamp(value) {
  if (typeof value !== "string") return null;
  const match = /^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]+))?(Z|([+-])([0-9]{2}):([0-9]{2}))$/.exec(value);
  if (!match) return null;
  const year = Number(match[1]), month = Number(match[2]), day = Number(match[3]);
  const hour = Number(match[4]), minute = Number(match[5]), second = Number(match[6]);
  const offsetHour = match[10] === undefined ? 0 : Number(match[10]);
  const offsetMinute = match[11] === undefined ? 0 : Number(match[11]);
  if (year < 1 || month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59 ||
      offsetHour > 23 || offsetMinute > 59 || (match[9] === "-" && offsetHour === 0 && offsetMinute === 0)) return null;
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (day < 1 || day > monthDays[month - 1]) return null;
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  date.setUTCHours(hour, minute, second, 0);
  const offsetSign = match[9] === "-" ? -1 : 1;
  const offsetSeconds = offsetSign * (offsetHour * 3600 + offsetMinute * 60);
  const epochSeconds = BigInt(date.getTime() / 1000 - offsetSeconds);
  return { epochSeconds, fraction: (match[7] ?? "").replace(/0+$/, "") };
}

export function isStrictRfc3339(value) {
  // Supported receipt profile deliberately excludes RFC3339 leap seconds and unknown offsets (-00:00).
  return parseStrictTimestamp(value) !== null;
}

export function compareStrictTimestamps(left, right) {
  const a = parseStrictTimestamp(left), b = parseStrictTimestamp(right);
  if (!a || !b) throw new CollectorError("RECEIPT_TIMESTAMP_INVALID");
  if (a.epochSeconds !== b.epochSeconds) return a.epochSeconds < b.epochSeconds ? -1 : 1;
  const width = Math.max(a.fraction.length, b.fraction.length);
  const af = a.fraction.padEnd(width, "0"), bf = b.fraction.padEnd(width, "0");
  return af === bf ? 0 : af < bf ? -1 : 1;
}
const dateTime = isStrictRfc3339;
export function validateReceiptSchema(r){
 const invalid=()=>{throw new CollectorError("RECEIPT_SCHEMA_INVALID");};
 if(!exactKeys(r,["schemaVersion","kind","status","projectRef","endpoint","source","execution","evidence","signing"])||r.schemaVersion!==1||r.kind!=="deedlight-production-migration-collection"||r.status!=="UNSIGNED_NOT_ACCEPTED"||r.projectRef!==PROJECT_REF)invalid();
 const e=r.endpoint;if(!exactKeys(e,["hostname","port","database","tlsMode","tlsVerified","tlsHostnameVerified","tlsChainVerified","projectIdentityMethod","tlsRootCertificateSha256","independentlyPinnedProfileSha256"])||
 e.hostname!=="db."+PROJECT_REF+".supabase.co"||e.port!==5432||!["postgres","deedlight_migration_order_test"].includes(e.database)||e.tlsMode!=="verify-full"||
 e.tlsVerified!==true||e.tlsHostnameVerified!==true||e.tlsChainVerified!==true||e.projectIdentityMethod!=="independently-pinned-profile-and-project-specific-TLS-hostname"||
 !hex(e.tlsRootCertificateSha256,64)||!hex(e.independentlyPinnedProfileSha256,64))invalid();
 const s=r.source;if(!exactKeys(s,["repositoryCommitSha","migrationInventoryGitBlobSha1","sqlBundlePath","sqlBundleGitBlobSha1","sqlBundleSha256"])||
 !hex(s.repositoryCommitSha,40)||s.migrationInventoryGitBlobSha1!==INVENTORY_GIT_BLOB_SHA1||s.sqlBundlePath!==SQL_PATH||s.sqlBundleGitBlobSha1!==SQL_GIT_BLOB_SHA1||s.sqlBundleSha256!==SQL_SHA256)invalid();
 const x=r.execution;if(!exactKeys(x,["collectorId","authenticatedPrincipal","expectedEffectivePrincipal","transactionIsolation","readOnly","transactionRollbackVerified","startedAt","completedAt","outputFormat","canonicalization","resultRecordCount","databaseAclV1RowCount","migrationHistoryRowCount","canonicalResultSha256","evidenceFileSha256"])||
 x.collectorId!==COLLECTOR_ID||x.authenticatedPrincipal!=="deedlight_catalog_auditor"||x.expectedEffectivePrincipal!=="deedlight_catalog_auditor"||
 x.transactionIsolation!=="repeatable read"||x.readOnly!==true||x.transactionRollbackVerified!==true||!dateTime(x.startedAt)||!dateTime(x.completedAt)||compareStrictTimestamps(x.completedAt,x.startedAt)<0||
 x.outputFormat!=="PostgreSQL psql CSV"||typeof x.canonicalization!=="string"||x.canonicalization.length<20||!Number.isSafeInteger(x.resultRecordCount)||x.resultRecordCount<1||
 !Number.isSafeInteger(x.databaseAclV1RowCount)||x.databaseAclV1RowCount<1||!Number.isSafeInteger(x.migrationHistoryRowCount)||x.migrationHistoryRowCount<0||!hex(x.canonicalResultSha256,64)||!hex(x.evidenceFileSha256,64))invalid();
 const v=r.evidence;if(!exactKeys(v,["file","mediaType","byteLength","sha256"])||v.file!=="evidence.csv"||v.mediaType!=="text/csv"||!Number.isSafeInteger(v.byteLength)||v.byteLength<1||!hex(v.sha256,64))invalid();
 const g=r.signing;if(!exactKeys(g,["state","keyId","signature","acceptance"])||g.state!=="NOT_SIGNED"||g.keyId!==null||g.signature!==null||g.acceptance!=="PROHIBITED_PENDING_INDEPENDENT_SIGNING_AND_VERIFICATION")invalid();
 return true;
}
export function verifyReceiptAndEvidence(receipt,csv){
 // Mandatory semantic gate before receipt acceptance or any future signing stage.
 validateReceiptSchema(receipt);
 if(sha256(csv)!==receipt.evidence.sha256||sha256(csv)!==receipt.execution.evidenceFileSha256||csv.length!==receipt.evidence.byteLength)throw new CollectorError("EVIDENCE_DIGEST_MISMATCH");
 const validation=validateSqlOutput(csv),digest=sha256(Buffer.from(canonicalJson(validation.resultRows),"utf8"));
 if(digest!==receipt.execution.canonicalResultSha256||validation.databaseAclRows!==receipt.execution.databaseAclV1RowCount||validation.migrationHistoryRows.length!==receipt.execution.migrationHistoryRowCount||validation.resultRows.length!==receipt.execution.resultRecordCount||!validation.transactionClosed)
  throw new CollectorError("RECEIPT_RESULT_BINDING_MISMATCH");
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
  const loaded = loadProfile(profilePath, repoPath);
  return withPinnedCaCleanup(loaded, () => {
    const { profile, profileDigest } = loaded;
    const absoluteOutput = path.resolve(outputDir);
    let outputRealPath;
    let csv;
    let evidencePath;
    let receiptPath;
    let outputCreated = false;
    try {
      const outputParent = realpathSync(path.dirname(absoluteOutput));
      assertOutsideRepository(outputParent, repoPath, "EVIDENCE_OUTPUT_MUST_BE_EXTERNAL");
      if (existsSync(absoluteOutput)) throw new CollectorError("OUTPUT_DIRECTORY_ALREADY_EXISTS");
      mkdirSync(absoluteOutput, { mode: 0o700 });
      outputCreated = true;
      outputRealPath = realpathSync(absoluteOutput);
      assertOutsideRepository(outputRealPath, repoPath, "EVIDENCE_OUTPUT_MUST_BE_EXTERNAL");
      const startedAt = new Date().toISOString();
      csv = runPsql({ repoPath, profile, sqlPath, commitSha });
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
      if (Buffer.isBuffer(csv)) csv.fill(0);
      if (outputCreated) rmSync(absoluteOutput, { recursive: true, force: true });
      throw error;
    } finally {
      if (Buffer.isBuffer(csv)) csv.fill(0);
    }
  });
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
