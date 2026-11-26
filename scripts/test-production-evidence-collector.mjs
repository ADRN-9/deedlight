import test from "node:test";
import assert from "node:assert/strict";
import { closeSync, chmodSync, fstatSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import {
  CollectorError,
  canonicalJson,
  parseCsv,
  validateSqlOutput,
  verifyReceiptAndEvidence,
  validateReceiptSchema,
  openPinnedCa,
  assertPinnedCaUnchanged,
  cleanupPinnedCa,
  createPinnedCaSnapshot,
  withPinnedCaCleanup,
  isStrictRfc3339,
  collect,
  sha256,
  SQL_SHA256,
} from "./collect-production-migration-evidence.mjs";

function serializeCsvField(value) {
  const text = String(value);
  const needsQuotes = text.includes(",") || text.includes('"') ||
    text.includes(String.fromCharCode(13)) || text.includes(String.fromCharCode(10));
  return needsQuotes ? '"' + text.replace(/"/g, '""') + '"' : text;
}

function serializeCsv(rows) {
  const newline = String.fromCharCode(13, 10);
  return rows.map((row) => row.map(serializeCsvField).join(",")).join(newline) + newline;
}

function replaceAclEdges(csv, edges) {
  const rows = parseCsv(csv);
  const row = rows.find((entry) => entry[0] === "database_acl_v1" && entry[2] === "1");
  assert.ok(row, "database_acl_v1 fixture row must exist");
  row[10] = JSON.stringify(edges);
  return serializeCsv(rows);
}

function completeReceipt(csv,validation=validateSqlOutput(csv)){
 const digest=sha256(csv);
 return{schemaVersion:1,kind:"deedlight-production-migration-collection",status:"UNSIGNED_NOT_ACCEPTED",projectRef:"xaipiovflxomcbfwtwmu",
 endpoint:{hostname:"db.xaipiovflxomcbfwtwmu.supabase.co",port:5432,database:"postgres",tlsMode:"verify-full",tlsVerified:true,tlsHostnameVerified:true,tlsChainVerified:true,
 projectIdentityMethod:"independently-pinned-profile-and-project-specific-TLS-hostname",tlsRootCertificateSha256:"a".repeat(64),independentlyPinnedProfileSha256:"b".repeat(64)},
 source:{repositoryCommitSha:"c".repeat(40),migrationInventoryGitBlobSha1:"95d514a0bd97ff448c9507252eb1f5e69a507442",sqlBundlePath:"scripts/production-migration-readonly-audit.sql",
 sqlBundleGitBlobSha1:"e55ed9207e8540d03de51c79e56c75d0bed130d1",sqlBundleSha256:"02f6db1822213453deb9fbe2588b893fbcd3ff312c4bb6b523238c7968db9d13"},
 execution:{collectorId:"deedlight-readonly-collector-v1",authenticatedPrincipal:"deedlight_catalog_auditor",expectedEffectivePrincipal:"deedlight_catalog_auditor",transactionIsolation:"repeatable read",
 readOnly:true,transactionRollbackVerified:true,startedAt:"2026-01-01T00:00:00Z",completedAt:"2026-01-01T00:01:00Z",outputFormat:"PostgreSQL psql CSV",
 canonicalization:"UTF-8 canonical JSON with ordered records and sorted object keys",resultRecordCount:validation.resultRows.length,databaseAclV1RowCount:validation.databaseAclRows,
 canonicalResultSha256:sha256(Buffer.from(canonicalJson(validation.resultRows))),evidenceFileSha256:digest},
 evidence:{file:"evidence.csv",mediaType:"text/csv",byteLength:csv.length,sha256:digest},
 signing:{state:"NOT_SIGNED",keyId:null,signature:null,acceptance:"PROHIBITED_PENDING_INDEPENDENT_SIGNING_AND_VERIFICATION"}};
}

function validCsv() {
  const rows = [];
  for (let i = 0; i < 13; i += 1) {
    rows.push(["projection_" + i, "value"], ["sample", String(i)]);
  }
  rows.push(
    ["evidence_projection","database_count","database_oid","database_name","allows_connections","is_template","owner_oid","owner_name","datacl_was_null","acl_expansion_source","expanded_acl_edges"],
    ["database_acl_v1","2","1","db_one","t","f","10","postgres","t","built_in_default","[]"],
    ["database_acl_v1","2","2","db_two","t","t","10","postgres","f","explicit","[]"],
    ["collector_transaction_closed"],
    ["t"],
  );
  return serializeCsv(rows);
}

test("pinned approved SQL bundle matches its SHA-256", () => {
  const sql = readFileSync(new URL("./production-migration-readonly-audit.sql", import.meta.url));
  assert.equal(sha256(sql), SQL_SHA256);
});

test("canonical JSON sorts object keys but preserves array order", () => {
  assert.equal(canonicalJson({ z: 1, a: { y: 2, b: 3 } }), '{"a":{"b":3,"y":2},"z":1}');
  assert.notEqual(canonicalJson([1, 2]), canonicalJson([2, 1]));
});

test("CSV parser handles escaped quotes, commas, CRLF and embedded newlines", () => {
  assert.deepEqual(parseCsv('"a","b"\r\n"x,y","line 1\nline ""2"""\r\n'), [
    ["a", "b"], ["x,y", 'line 1\nline "2"'],
  ]);
});

test("valid complete output includes the complete database_acl_v1 projection and rollback marker", () => {
  const result = validateSqlOutput(validCsv());
  assert.equal(result.databaseAclRows, 2);
  assert.equal(result.transactionClosed, true);
  assert.ok(result.resultRows.length >= 15);
});

test("missing transaction marker fails closed", () => {
  const csv = validCsv().replace('collector_transaction_closed\r\nt\r\n', "");
  assert.throws(() => validateSqlOutput(csv), (error) => error instanceof CollectorError && error.code === "TRANSACTION_CLOSE_MARKER_MISSING");
});

test("false transaction marker fails closed", () => {
  const csv = validCsv().replace('collector_transaction_closed\r\nt\r\n', 'collector_transaction_closed\r\nf\r\n');
  assert.throws(() => validateSqlOutput(csv), (error) => error instanceof CollectorError && error.code === "TRANSACTION_ROLLBACK_NOT_VERIFIED");
});

test("missing database_acl_v1 projection fails closed", () => {
  const csv = validCsv().replace(
    'evidence_projection,database_count,database_oid,database_name,allows_connections,is_template,owner_oid,owner_name,datacl_was_null,acl_expansion_source,expanded_acl_edges\r\ndatabase_acl_v1,2,1,db_one,t,f,10,postgres,t,built_in_default,[]\r\ndatabase_acl_v1,2,2,db_two,t,t,10,postgres,f,explicit,[]\r\n',
    "",
  );
  assert.throws(() => validateSqlOutput(csv), (error) => error instanceof CollectorError && error.code === "DATABASE_ACL_PROJECTION_MISSING");
});

test("database ACL edge OIDs accept canonical numeric JSON representations", () => {
  const edge = JSON.stringify({
    grantee_oid: "0", grantee_name: "PUBLIC", grantor_oid: 10,
    grantor_name: "postgres", privilege_type: "CONNECT", is_grantable: false,
  });
  const csv = replaceAclEdges(validCsv(), [JSON.parse(edge)]);
  assert.equal(validateSqlOutput(csv).databaseAclRows, 2);
});

test("duplicate database ACL edges fail closed", () => {
  const edge = JSON.stringify({
    grantee_oid: "0", grantee_name: "PUBLIC", grantor_oid: "10",
    grantor_name: "postgres", privilege_type: "CONNECT", is_grantable: false,
  });
  const csv = replaceAclEdges(validCsv(), [JSON.parse(edge), JSON.parse(edge)]);
  assert.throws(() => validateSqlOutput(csv), (error) => error.code === "DATABASE_ACL_EDGES_DUPLICATED");
});

test("duplicate or unordered database rows fail closed", () => {
  const csv = validCsv().replace(
    "database_acl_v1,2,2,db_two,t,t,10,postgres,f,explicit,[]",
    "database_acl_v1,2,1,db_one,t,f,10,postgres,f,explicit,[]",
  );
  assert.throws(() => validateSqlOutput(csv), (error) => error.code === "DATABASE_ACL_PROJECTION_DUPLICATED_OR_UNORDERED");
});

test("database ACL NULL/default provenance must agree", () => {
  const csv = validCsv().replace(
    "database_acl_v1,2,1,db_one,t,f,10,postgres,t,built_in_default,[]",
    "database_acl_v1,2,1,db_one,t,f,10,postgres,t,explicit,[]",
  );
  assert.throws(() => validateSqlOutput(csv), (error) => error.code === "DATABASE_ACL_PROJECTION_INCOMPLETE");
});

test("database ACL edge order must match stable SQL ordering", () => {
  const first = { grantee_oid: 10, grantee_name: "role_a", grantor_oid: 10, grantor_name: "postgres", privilege_type: "CONNECT", is_grantable: false };
  const second = { ...first, grantee_oid: 11, grantee_name: "role_b" };
  const csv = replaceAclEdges(validCsv(), [second, first]);
  assert.throws(() => validateSqlOutput(csv), (error) => error.code === "DATABASE_ACL_EDGES_UNORDERED");
});

test("malformed database ACL JSON fails closed", () => {
  const csv = validCsv().replace("database_acl_v1,2,1,db_one,t,f,10,postgres,t,built_in_default,[]", "database_acl_v1,2,1,db_one,t,f,10,postgres,t,built_in_default,{bad}");
  assert.throws(() => validateSqlOutput(csv), (error) => error instanceof CollectorError && error.code === "DATABASE_ACL_EDGES_INVALID_JSON");
});

test("truncated database ACL rows fail closed", () => {
  const csv = validCsv().replace('database_acl_v1,2,2,db_two,t,t,10,postgres,f,explicit,[]\r\n', "");
  assert.throws(() => validateSqlOutput(csv), (error) => error instanceof CollectorError && error.code === "DATABASE_ACL_PROJECTION_INCOMPLETE");
});

test("malformed or truncated CSV fails closed", () => {
  assert.throws(() => parseCsv('"unterminated'), (error) => error instanceof CollectorError && error.code === "TRUNCATED_CSV_QUOTE");
  assert.throws(() => parseCsv("a\u0000b"), (error) => error instanceof CollectorError && error.code === "INVALID_CSV_NUL");
});

test("receipt binds raw evidence and canonical result digest", () => {
  const csv = Buffer.from(validCsv());
  const rows = validateSqlOutput(csv);
  const receipt = completeReceipt(csv, rows);
  assert.equal(verifyReceiptAndEvidence(receipt, csv), true);
  const tampered = Buffer.from(csv.toString().replace('database_acl_v1,2,1,', 'database_acl_v1,2,9,'));
  assert.throws(() => verifyReceiptAndEvidence(receipt, tampered), (error) => error.code === "EVIDENCE_DIGEST_MISMATCH");
});

test("receipt cannot claim signed or accepted state in E2", () => {
  const csv = Buffer.from(validCsv());
  const rows = validateSqlOutput(csv);
  const receipt = completeReceipt(csv, rows);
  receipt.status = "ACCEPTED"; receipt.signing.state = "SIGNED";
  assert.throws(() => verifyReceiptAndEvidence(receipt, csv), (error) => error.code === "RECEIPT_SCHEMA_INVALID");
});

test("receipt result binding rejects a forged canonical digest", () => {
  const csv = Buffer.from(validCsv());
  const rows = validateSqlOutput(csv);
  const receipt = completeReceipt(csv, rows);
  receipt.execution.canonicalResultSha256 = "0".repeat(64);
  assert.throws(() => verifyReceiptAndEvidence(receipt, csv), (error) => error.code === "RECEIPT_RESULT_BINDING_MISMATCH");
});

test("CSV preserves embedded CRLF and empty leading, middle and trailing fields", () => {
  const cr = String.fromCharCode(13), lf = String.fromCharCode(10), crlf = cr + lf;
  assert.deepEqual(parseCsv(",middle," + crlf), [["", "middle", ""]]);
  assert.deepEqual(parseCsv("a,,c," + crlf), [["a", "", "c", ""]]);
  assert.deepEqual(parseCsv('""' + ",x," + crlf), [["", "x", ""]]);
  assert.deepEqual(parseCsv('"line 1' + crlf + 'line 2",z' + crlf), [["line 1" + crlf + "line 2", "z"]]);
});
test("CSV rejects bare CR, malformed quotes and invalid post-quote characters", () => {
  const cr = String.fromCharCode(13);
  for (const value of ["a" + cr + "b", '"a"x', 'a"b', '"unterminated']) {
    assert.throws(() => parseCsv(value), CollectorError);
  }
});
test("ACL header rejects each missing column, duplicate and unexpected columns", () => {
  const base = parseCsv(validCsv()), index = base.findIndex((row) => row[0] === "evidence_projection");
  for (let n = 0; n < 11; n += 1) {
    const rows = base.map((row) => [...row]); rows[index].splice(n, 1);
    assert.throws(() => validateSqlOutput(serializeCsv(rows)), (error) => error.code === "DATABASE_ACL_PROJECTION_SCHEMA_INVALID");
  }
  const duplicate = base.map((row) => [...row]); duplicate[index][3] = duplicate[index][2];
  assert.throws(() => validateSqlOutput(serializeCsv(duplicate)), (error) => error.code === "DATABASE_ACL_PROJECTION_SCHEMA_INVALID");
  const extra = base.map((row) => [...row]); extra[index].push("unexpected"); extra[index + 1].push("x"); extra[index + 2].push("x");
  assert.throws(() => validateSqlOutput(serializeCsv(extra)), (error) => error.code === "DATABASE_ACL_PROJECTION_SCHEMA_INVALID");
});
test("database and owner OIDs are positive canonical uint32", () => {
  for (const [column, value] of [[2,"0"],[2,"4294967296"],[2,"01"],[6,"0"],[6,"4294967296"]]) {
    const rows = parseCsv(validCsv()); rows[27][column] = value;
    assert.throws(() => validateSqlOutput(serializeCsv(rows)), CollectorError);
  }
});
test("ACL grantor OID and PUBLIC identity are strict", () => {
  const edge = {grantee_oid:0,grantee_name:"PUBLIC",grantor_oid:10,grantor_name:"postgres",privilege_type:"CONNECT",is_grantable:false};
  for (const bad of [{...edge,grantor_oid:0},{...edge,grantor_oid:4294967296},{...edge,grantee_oid:1},
    {...edge,grantee_oid:"1",grantee_name:"PUBLIC"},{...edge,grantee_oid:"0",grantee_name:"role"}]) {
    assert.throws(() => validateSqlOutput(replaceAclEdges(validCsv(), [bad])), CollectorError);
  }
});
test("logical ACL duplicate ignores grantability", () => {
  const edge = {grantee_oid:10,grantee_name:"role_a",grantor_oid:11,grantor_name:"postgres",privilege_type:"CONNECT",is_grantable:false};
  assert.throws(() => validateSqlOutput(replaceAclEdges(validCsv(), [edge, {...edge,is_grantable:true}])),
    (error) => error.code === "DATABASE_ACL_EDGES_DUPLICATED");
});
test("receipt schema rejects missing required fields in every object", () => {
  const csv = Buffer.from(validCsv()), receipt = completeReceipt(csv);
  const objects = ["endpoint","source","execution","evidence","signing"];
  for (const object of objects) for (const key of Object.keys(receipt[object])) {
    const copy = structuredClone(receipt); delete copy[object][key];
    assert.throws(() => validateReceiptSchema(copy), (error) => error.code === "RECEIPT_SCHEMA_INVALID");
  }
  for (const key of Object.keys(receipt)) {
    const copy = structuredClone(receipt); delete copy[key];
    assert.throws(() => verifyReceiptAndEvidence(copy,csv), (error) => error.code === "RECEIPT_SCHEMA_INVALID");
  }
});
test("receipt schema rejects unexpected fields, malformed timestamps and byte-length tampering", () => {
  const csv = Buffer.from(validCsv()), receipt = completeReceipt(csv), extra = structuredClone(receipt);
  extra.endpoint.extra = true;
  assert.throws(() => validateReceiptSchema(extra), (error) => error.code === "RECEIPT_SCHEMA_INVALID");
  const date = structuredClone(receipt); date.execution.startedAt = "bad";
  assert.throws(() => validateReceiptSchema(date), (error) => error.code === "RECEIPT_SCHEMA_INVALID");
  const length = structuredClone(receipt); length.evidence.byteLength += 1;
  assert.throws(() => verifyReceiptAndEvidence(length,csv), (error) => error.code === "EVIDENCE_DIGEST_MISMATCH");
});
test("CA pin detects path replacement and in-place tampering", () => {
  const dir = mkdtempSync(path.join(tmpdir(),"deedlight-ca-")); chmodSync(dir,0o700);
  const ca = path.join(dir,"root.crt"); writeFileSync(ca,"trusted-ca"); chmodSync(ca,0o600);
  let guard = openPinnedCa(ca,sha256("trusted-ca"));
  renameSync(ca,path.join(dir,"original.crt")); writeFileSync(ca,"replacement-ca"); chmodSync(ca,0o600);
  assert.throws(() => assertPinnedCaUnchanged(guard), (error) => error.code === "TLS_CA_CHANGED_DURING_COLLECTION");
  closeSync(guard.fd); rmSync(ca); renameSync(path.join(dir,"original.crt"),ca);
  guard = openPinnedCa(ca,sha256("trusted-ca")); writeFileSync(ca,"tampered-ca");
  assert.throws(() => assertPinnedCaUnchanged(guard), (error) => error.code === "TLS_CA_CHANGED_DURING_COLLECTION");
  closeSync(guard.fd); rmSync(dir,{recursive:true,force:true});
});

test("CA pin rejects unsafe directory and certificate permissions", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "deedlight-ca-perms-"));
  const ca = path.join(dir, "root.crt"); writeFileSync(ca, "trusted-ca"); chmodSync(ca, 0o600);
  chmodSync(dir, 0o755);
  assert.throws(() => openPinnedCa(ca, sha256("trusted-ca")), (error) => error.code === "TLS_CA_DIRECTORY_INVALID");
  chmodSync(dir, 0o700); chmodSync(ca, 0o644);
  assert.throws(() => openPinnedCa(ca, sha256("trusted-ca")), (error) => error.code === "TLS_CA_INVALID");
  rmSync(dir, { recursive: true, force: true });
});

test("CA resources are cleaned after output-directory validation failure", () => {
  const root = mkdtempSync(path.join(tmpdir(), "deedlight-ca-output-")); chmodSync(root, 0o700);
  const ca = path.join(root, "root.crt"); writeFileSync(ca, "pinned-ca"); chmodSync(ca, 0o600);
  const guard = openPinnedCa(ca, sha256("pinned-ca"));
  const snapshot = createPinnedCaSnapshot(guard);
  const privateDirectory = guard.privateDirectory;
  assert.throws(() => withPinnedCaCleanup({ profile: { tlsCaGuard: guard } }, () => {
    throw new CollectorError("EVIDENCE_OUTPUT_MUST_BE_EXTERNAL");
  }), (error) => error.code === "EVIDENCE_OUTPUT_MUST_BE_EXTERNAL");
  assert.equal(guard.fdClosed, true);
  assert.throws(() => fstatSync(guard.fd));
  assert.equal(readFileSync(snapshot, "utf8"), "pinned-ca");
  assert.throws(() => readFileSync(privateDirectory), { code: "ENOENT" });
  rmSync(root, { recursive: true, force: true });
});

test("CA snapshot creation failure removes temporary directory and closes descriptor", () => {
  const root = mkdtempSync(path.join(tmpdir(), "deedlight-ca-snapshot-failure-")); chmodSync(root, 0o700);
  const ca = path.join(root, "root.crt"); writeFileSync(ca, "pinned-ca"); chmodSync(ca, 0o600);
  const guard = openPinnedCa(ca, sha256("pinned-ca"));
  let createdDirectory;
  assert.throws(() => createPinnedCaSnapshot(guard, {
    tmpdir: root,
    mkdtempSync: (prefix) => { createdDirectory = mkdtempSync(prefix); return createdDirectory; },
    writeFileSync: () => { throw new Error("simulated snapshot write failure"); },
  }), /simulated snapshot write failure/);
  assert.equal(guard.fdClosed, true);
  assert.throws(() => fstatSync(guard.fd));
  assert.throws(() => readFileSync(createdDirectory), { code: "ENOENT" });
  rmSync(root, { recursive: true, force: true });
});

test("CA snapshot hashes exact copied bytes against independent pin", () => {
  const root = mkdtempSync(path.join(tmpdir(), "deedlight-ca-snapshot-hash-")); chmodSync(root, 0o700);
  const ca = path.join(root, "root.crt"); writeFileSync(ca, "pinned-ca"); chmodSync(ca, 0o600);
  const guard = openPinnedCa(ca, sha256("pinned-ca"));
  const snapshot = createPinnedCaSnapshot(guard);
  assert.equal(sha256(readFileSync(snapshot)), guard.digest);
  cleanupPinnedCa(guard);
  assert.equal(guard.fdClosed, true);
  rmSync(root, { recursive: true, force: true });
});

test("strict RFC3339 validates calendar, leap years, clock and timezone ranges", () => {
  const valid = [
    "2024-02-29T23:59:59Z",
    "2024-02-29T12:30:45.123456Z",
    "2026-11-26T06:45:00-08:00",
    "2000-02-29T00:00:00+14:00",
  ];
  const invalid = [
    "2026-02-31T12:00:00Z",
    "2023-02-29T12:00:00Z",
    "2024-04-31T12:00:00Z",
    "2024-01-01T24:00:00Z",
    "2024-01-01T12:60:00Z",
    "2024-01-01T12:00:60Z",
    "2024-01-01T12:00:00+24:00",
    "2024-01-01T12:00:00+12:60",
    "2024-01-01T12:00:00+1:00",
    "0000-01-01T00:00:00Z",
  ];
  for (const value of valid) assert.equal(isStrictRfc3339(value), true, value);
  for (const value of invalid) assert.equal(isStrictRfc3339(value), false, value);
});

test("receipt rejects impossible RFC3339 dates despite Date.parse normalization", () => {
  const csv = Buffer.from(validCsv()), receipt = completeReceipt(csv);
  receipt.execution.startedAt = "2026-02-31T12:00:00Z";
  assert.throws(() => validateReceiptSchema(receipt), (error) => error.code === "RECEIPT_SCHEMA_INVALID");
});

test("collect cleans CA descriptor and snapshot when output-directory validation fails", () => {
  const root = mkdtempSync(path.join(tmpdir(), "deedlight-collect-output-failure-")); chmodSync(root, 0o700);
  const caPath = path.join(root, "root.crt"), passwordPath = path.join(root, "passfile"), profilePath = path.join(root, "profile.json");
  writeFileSync(caPath, "collector-test-ca", { mode: 0o600 });
  writeFileSync(passwordPath, "localhost:5432:postgres:deedlight_catalog_auditor:placeholder\n", { mode: 0o600 });
  const profile = {
    schemaVersion: 1, projectRef: "xaipiovflxomcbfwtwmu", host: "db.xaipiovflxomcbfwtwmu.supabase.co",
    port: 5432, database: "postgres", username: "deedlight_catalog_auditor",
    tlsRootCertPath: caPath, passwordFilePath: passwordPath,
  };
  const profileBytes = Buffer.from(JSON.stringify(profile));
  writeFileSync(profilePath, profileBytes, { mode: 0o600 });
  const oldProfilePin = process.env.DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256;
  const oldCaPin = process.env.DEEDLIGHT_COLLECTOR_TLS_CA_SHA256;
  process.env.DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256 = sha256(profileBytes);
  process.env.DEEDLIGHT_COLLECTOR_TLS_CA_SHA256 = sha256("collector-test-ca");
  const before = new Set(readdirSync(tmpdir()).filter((name) => name.startsWith("deedlight-ca-")));
  const outputInsideRepository = path.join(process.cwd(), ".deedlight-output-must-not-be-created");
  try {
    assert.throws(() => collect({ profilePath, outputDir: outputInsideRepository }),
      (error) => error.code === "EVIDENCE_OUTPUT_MUST_BE_EXTERNAL");
    assert.equal(readdirSync(tmpdir()).filter((name) => name.startsWith("deedlight-ca-")).filter((name) => !before.has(name)).length, 0);
    assert.equal(readFileSync(profilePath).equals(profileBytes), true);
  } finally {
    if (oldProfilePin === undefined) delete process.env.DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256;
    else process.env.DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256 = oldProfilePin;
    if (oldCaPin === undefined) delete process.env.DEEDLIGHT_COLLECTOR_TLS_CA_SHA256;
    else process.env.DEEDLIGHT_COLLECTOR_TLS_CA_SHA256 = oldCaPin;
    rmSync(root, { recursive: true, force: true });
  }
});
