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
  compareStrictTimestamps,
  collect,
  sha256,
  SQL_SHA256,
  SQL_PROJECTIONS,
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
 source:{repositoryCommitSha:"c".repeat(40),migrationInventoryGitBlobSha1:"4e63f31368d446e905f4f44565be73337c7188fb",sqlBundlePath:"scripts/production-migration-readonly-audit.sql",
 sqlBundleGitBlobSha1:"8f8c38ba0c2a463ee25c6dae1dc1b15e24e3819f",sqlBundleSha256:"afda6bcfc9f7abc7765b8dfb54bf02d1cdb0d8062da2a9f953336b638d13af7d"},
 execution:{collectorId:"deedlight-readonly-collector-v1",authenticatedPrincipal:"deedlight_catalog_auditor",expectedEffectivePrincipal:"deedlight_catalog_auditor",transactionIsolation:"repeatable read",
 readOnly:true,transactionRollbackVerified:true,startedAt:"2026-01-01T00:00:00Z",completedAt:"2026-01-01T00:01:00Z",outputFormat:"PostgreSQL psql CSV",
 canonicalization:"UTF-8 canonical JSON with ordered records and sorted object keys",resultRecordCount:validation.resultRows.length,databaseAclV1RowCount:validation.databaseAclRows,migrationHistoryRowCount:validation.migrationHistoryRows.length,
 canonicalResultSha256:sha256(Buffer.from(canonicalJson(validation.resultRows))),evidenceFileSha256:digest},
 evidence:{file:"evidence.csv",mediaType:"text/csv",byteLength:csv.length,sha256:digest},
 signing:{state:"NOT_SIGNED",keyId:null,signature:null,acceptance:"PROHIBITED_PENDING_INDEPENDENT_SIGNING_AND_VERIFICATION"}};
}

function validCsv() {
  const rows = [];
  for (const projection of SQL_PROJECTIONS) {
    rows.push(projection.columns);
    if (projection.id === "identity_v1") {
      rows.push(["xaipiovflxomcbfwtwmu", "c".repeat(40), "deedlight_migration_order_test",
        "deedlight_catalog_auditor", "deedlight_catalog_auditor", "16.2", "127.0.0.1", "5432",
        "2026-01-01T00:00:00.000Z", "on"]);
    } else if (projection.id === "migration_history_v1") {
      rows.push(["202611240037", "migration_037_fixture", "1"]);
      rows.push(["202611240038", "", ""]);
    } else if (projection.id === "database_acl_v1") {
      rows.push(["database_acl_v1", "2", "1", "db_one", "t", "f", "10", "postgres", "t", "built_in_default", "[]"]);
      rows.push(["database_acl_v1", "2", "2", "db_two", "t", "t", "10", "postgres", "f", "explicit", "[]"]);
    }
  }
  rows.push(["collector_transaction_closed"], ["t"]);
  return serializeCsv(rows);
}

function removeProjection(csv, projectionId) {
  const rows = parseCsv(csv);
  const index = SQL_PROJECTIONS.findIndex((projection) => projection.id === projectionId);
  const header = SQL_PROJECTIONS[index].columns;
  const start = rows.findIndex((row) => row.length === header.length && row.every((cell, i) => cell === header[i]));
  assert.notEqual(start, -1);
  let end = rows.length;
  for (let i = start + 1; i < rows.length; i += 1) {
    if (SQL_PROJECTIONS.some((projection) => projection.columns.length === rows[i].length &&
      projection.columns.every((cell, j) => cell === rows[i][j]))) { end = i; break; }
    if (rows[i].length === 1 && rows[i][0] === "collector_transaction_closed") { end = i; break; }
  }
  rows.splice(start, end - start);
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
  assert.deepEqual(result.migrationHistoryRows, [
    { version: "202611240037", name: "migration_037_fixture", recordedStatementCount: 1 },
    { version: "202611240038", name: null, recordedStatementCount: null },
  ]);
  assert.equal(result.transactionClosed, true);
  assert.equal(result.projections.length, SQL_PROJECTIONS.length);
  assert.deepEqual(result.projections.map((projection) => projection.id), SQL_PROJECTIONS.map((projection) => projection.id));
});

test("every mandatory SQL projection is present exactly once in the pinned order", () => {
  const result = validateSqlOutput(validCsv());
  assert.deepEqual(result.projections.map(({ id }) => id), SQL_PROJECTIONS.map(({ id }) => id));
  assert.equal(result.projections[1].rowCount, 0);
  assert.equal(result.projections[7].rowCount, 0);
  assert.equal(result.projections[17].rowCount, 2);
  assert.equal(result.projections[18].rowCount, 2);
});

test("each mandatory SQL projection is independently required", () => {
  for (const projection of SQL_PROJECTIONS) {
    const csv = removeProjection(validCsv(), projection.id);
    assert.throws(() => validateSqlOutput(csv), CollectorError, projection.id);
  }
});

test("duplicate and unexpected SQL projections fail closed", () => {
  const duplicate = parseCsv(validCsv());
  const firstHeader = SQL_PROJECTIONS[0].columns;
  const firstIndex = duplicate.findIndex((row) => row.length === firstHeader.length &&
    row.every((cell, index) => cell === firstHeader[index]));
  duplicate.splice(firstIndex + 1, 0, firstHeader);
  assert.throws(() => validateSqlOutput(serializeCsv(duplicate)),
    (error) => error.code === "SQL_PROJECTION_DUPLICATED");

  const unexpected = parseCsv(validCsv());
  const aclIndex = unexpected.findIndex((row) => row[0] === "evidence_projection");
  unexpected.splice(aclIndex, 0, ["unexpected_a", "unexpected_b", "unexpected_c", "unexpected_d",
    "unexpected_e", "unexpected_f", "unexpected_g", "unexpected_h", "unexpected_i", "unexpected_j", "unexpected_k"]);
  assert.throws(() => validateSqlOutput(serializeCsv(unexpected)), CollectorError);
});

test("incorrect mandatory projection column structures fail closed", () => {
  for (const projection of SQL_PROJECTIONS) {
    const rows = parseCsv(validCsv());
    const index = rows.findIndex((row) => row.length === projection.columns.length &&
      row.every((cell, column) => cell === projection.columns[column]));
    rows[index][0] = "unexpected_column_name";
    assert.throws(() => validateSqlOutput(serializeCsv(rows)), CollectorError, projection.id);
  }
});

test("all contract-permitted empty projections remain valid", () => {
  const rows = [];
  for (const projection of SQL_PROJECTIONS) {
    rows.push(projection.columns);
    if (projection.id === "identity_v1") rows.push(["xaipiovflxomcbfwtwmu", "c".repeat(40),
      "deedlight_migration_order_test", "deedlight_catalog_auditor", "deedlight_catalog_auditor",
      "16.2", "127.0.0.1", "5432", "2026-01-01T00:00:00.000Z", "on"]);
    if (projection.id === "database_acl_v1") rows.push(["database_acl_v1", "1", "1", "db_one",
      "t", "f", "10", "postgres", "t", "built_in_default", "[]"]);
  }
  rows.push(["collector_transaction_closed"], ["t"]);
  const result = validateSqlOutput(serializeCsv(rows));
  assert.equal(result.migrationHistoryRows.length, 0);
  assert.ok(result.projections.filter((projection) =>
    !["identity_v1", "database_acl_v1"].includes(projection.id)).every((projection) => projection.rowCount === 0));
});

test("truncated or malformed projection records fail closed", () => {
  const rows = parseCsv(validCsv());
  const relationHeader = SQL_PROJECTIONS.find((projection) => projection.id === "relations_v1").columns;
  const relationIndex = rows.findIndex((row) => row.length === relationHeader.length &&
    row.every((cell, index) => cell === relationHeader[index]));
  rows.splice(relationIndex + 1, 0, ["short", "row"]);
  assert.throws(() => validateSqlOutput(serializeCsv(rows)),
    (error) => error.code === "SQL_PROJECTION_ROW_WIDTH_INVALID");
  assert.throws(() => validateSqlOutput(validCsv().replace("database_acl_v1,2,1,", '"database_acl_v1,2,1,')),
    CollectorError);
});

test("migration history projection uses the exact analyzer-native field contract", () => {
  const result = validateSqlOutput(validCsv());
  assert.deepEqual(Object.keys(result.migrationHistoryRows[0]).sort(), ["name", "recordedStatementCount", "version"]);
  const missing = serializeCsv(parseCsv(validCsv()).filter((row) => row[0] !== "version"));
  assert.throws(() => validateSqlOutput(missing), (error) => error.code === "MIGRATION_HISTORY_PROJECTION_MISSING");
  const renamed = validCsv().replace("version,name,recordedStatementCount", "version,migration_name,recorded_statement_count");
  assert.throws(() => validateSqlOutput(renamed), CollectorError);
});

test("migration history preserves literal NULL names and rejects nonnumeric statement-count text", () => {
  const literalName = validCsv().replace(
    "202611240037,migration_037_fixture,1",
    "202611240037,NULL,1",
  );
  assert.equal(validateSqlOutput(literalName).migrationHistoryRows[0].name, "NULL");

  const invalidCount = validCsv().replace(
    "202611240037,migration_037_fixture,1",
    "202611240037,migration_037_fixture,NULL",
  );
  assert.throws(() => validateSqlOutput(invalidCount),
    (error) => error.code === "MIGRATION_HISTORY_STATEMENT_COUNT_INVALID");
});

test("migration history rejects malformed versions, duplicate versions, names and statement counts", () => {
  for (const [from, to, code] of [
    ["202611240037,migration_037_fixture,1", "bad-version,migration_037_fixture,1", "MIGRATION_HISTORY_VERSION_INVALID"],
    ["202611240038,,", "202611240037,,", "MIGRATION_HISTORY_VERSION_INVALID"],
    ["202611240037,migration_037_fixture,1", "202611240037,bad/name,1", "MIGRATION_HISTORY_NAME_INVALID"],
    ["202611240037,migration_037_fixture,1", "202611240037,migration_037_fixture,1.5", "MIGRATION_HISTORY_STATEMENT_COUNT_INVALID"],
  ]) {
    const csv = validCsv().replace(from, to);
    assert.throws(() => validateSqlOutput(csv), (error) => error.code === code);
  }
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
    assert.throws(() => validateSqlOutput(serializeCsv(rows)), CollectorError);
  }
  const duplicate = base.map((row) => [...row]); duplicate[index][3] = duplicate[index][2];
  assert.throws(() => validateSqlOutput(serializeCsv(duplicate)), CollectorError);
  const extra = base.map((row) => [...row]); extra[index].push("unexpected"); extra[index + 1].push("x"); extra[index + 2].push("x");
  assert.throws(() => validateSqlOutput(serializeCsv(extra)), CollectorError);
});
test("database and owner OIDs are positive canonical uint32", () => {
  for (const [column, value] of [[2,"0"],[2,"4294967296"],[2,"01"],[6,"0"],[6,"4294967296"]]) {
    const rows = parseCsv(validCsv()); rows.find((row) => row[0] === "database_acl_v1" && row[2] === "1")[column] = value;
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
  assert.throws(() => readFileSync(snapshot), { code: "ENOENT" });
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

test("receipt timestamp profile rejects leap seconds and unknown local offsets", () => {
  const supported = [
    "2016-12-31T23:59:59Z",
    "2024-02-29T12:30:45.12345678901234567890Z",
    "2026-11-26T06:45:00-08:00",
  ];
  const unsupported = [
    "2016-12-31T23:59:60Z",
    "2016-12-31T18:59:60-05:00",
    "2017-12-31T23:59:60Z",
    "2016-12-30T23:59:60Z",
    "2024-01-01T00:00:00-00:00",
    "2024-01-01T00:00:00+",
    "2024-01-01T00:00:00+01:000",
  ];
  for (const value of supported) assert.equal(isStrictRfc3339(value), true, value);
  for (const value of unsupported) assert.equal(isStrictRfc3339(value), false, value);
});

test("receipt JSON Schema enforces DeedLight timestamp lexical profile", () => {
  const receiptSchema = JSON.parse(readFileSync(new URL("../schemas/production-migration-collection-receipt-v1.schema.json", import.meta.url), "utf8"));
  const fields = ["startedAt", "completedAt"];
  const supported = ["0001-01-01T00:00:00Z", "2024-02-29T12:30:45.12345678901234567890Z", "2026-11-26T06:45:00-08:00", "2024-01-01T00:00:00+00:00", "2024-01-01T00:00:00-00:01"];
  const rejected = ["2016-12-31T23:59:60Z", "2016-12-31T18:59:60-05:00", "2024-01-01T00:00:00-00:00", "2024-01-01T00:00:00+", "2024-01-01T00:00:00+01:000", "2024-01-01T24:00:00Z", "2024-01-01T00:60:00Z"];
  for (const field of fields) {
    const definition = receiptSchema.properties.execution.properties[field];
    assert.equal(definition.format, "date-time");
    assert.match(definition.description, /Leap seconds/);
    assert.match(definition.description, /semantic verification/);
    assert.equal(typeof definition.pattern, "string");
    const lexical = new RegExp(definition.pattern);
    for (const value of supported) assert.equal(lexical.test(value), true, field + ": " + value);
    for (const value of rejected) assert.equal(lexical.test(value), false, field + ": " + value);
  }
});

test("receipt JSON Schema timestamp patterns require absolute end of input", () => {
  const receiptSchema = JSON.parse(readFileSync(new URL("../schemas/production-migration-collection-receipt-v1.schema.json", import.meta.url), "utf8"));
  const suffixes = ["\n","\r","\r\n"," "," "];
  const valid = ["2024-02-29T12:30:45.12345678901234567890Z", "2026-11-26T06:45:00-08:00"];
  for (const field of ["startedAt", "completedAt"]) {
    const pattern = new RegExp(receiptSchema.properties.execution.properties[field].pattern);
    for (const timestamp of valid) assert.equal(pattern.test(timestamp), true, field + ": valid timestamp " + timestamp);
    for (const timestamp of valid) {
      for (const suffix of suffixes) {
        assert.equal(pattern.test(timestamp + suffix), false, field + ": trailing code point " + JSON.stringify(suffix));
      }
    }
  }
});

test("strict timestamp ordering preserves fractional precision and timezone equivalence", () => {
  assert.equal(compareStrictTimestamps("2024-01-01T00:00:00.1234567891Z", "2024-01-01T00:00:00.1234567890Z"), 1);
  assert.equal(compareStrictTimestamps("2024-01-01T00:00:00.1234567889Z", "2024-01-01T00:00:00.1234567890Z"), -1);
  assert.equal(compareStrictTimestamps("2024-01-01T00:00:00.123456789Z", "2023-12-31T19:00:00.123456789-05:00"), 0);
  assert.equal(compareStrictTimestamps("2024-01-01T00:00:00.000000001Z", "2023-12-31T19:00:00.000000002-05:00"), -1);
  assert.equal(compareStrictTimestamps("2024-01-01T00:00:00.1234000Z", "2024-01-01T00:00:00.1234Z"), 0);
});

test("semantic receipt verifier rejects cross-field timestamp inversions and accepts equivalent instants", () => {
  const csv = Buffer.from(validCsv());
  const inverted = completeReceipt(csv);
  inverted.execution.startedAt = "2026-01-01T00:00:00.0000009Z";
  inverted.execution.completedAt = "2026-01-01T00:00:00.0000008Z";
  assert.throws(() => verifyReceiptAndEvidence(inverted, csv), (error) => error.code === "RECEIPT_SCHEMA_INVALID");

  const equivalent = completeReceipt(csv);
  equivalent.execution.startedAt = "2026-01-01T05:00:00.123456789Z";
  equivalent.execution.completedAt = "2026-01-01T00:00:00.123456789-05:00";
  assert.equal(verifyReceiptAndEvidence(equivalent, csv), true);
});

test("receipt rejects sub-millisecond completion inversions", () => {
  const csv = Buffer.from(validCsv()), receipt = completeReceipt(csv);
  receipt.execution.startedAt = "2026-01-01T00:00:00.0000009Z";
  receipt.execution.completedAt = "2026-01-01T00:00:00.0000008Z";
  assert.throws(() => validateReceiptSchema(receipt), (error) => error.code === "RECEIPT_SCHEMA_INVALID");
});

test("receipt accepts equal instants expressed with different timezone offsets", () => {
  const csv = Buffer.from(validCsv()), receipt = completeReceipt(csv);
  receipt.execution.startedAt = "2026-01-01T05:00:00.123456789Z";
  receipt.execution.completedAt = "2026-01-01T00:00:00.123456789-05:00";
  assert.equal(validateReceiptSchema(receipt), true);
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
  const descriptorCount = () => readdirSync("/proc/self/fd").length;
  const descriptorsBefore = descriptorCount();
  const outputInsideRepository = path.join(process.cwd(), ".deedlight-output-must-not-be-created");
  try {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      assert.throws(() => collect({ profilePath, outputDir: outputInsideRepository }),
        (error) => error.code === "EVIDENCE_OUTPUT_MUST_BE_EXTERNAL");
    }
    assert.equal(readdirSync(tmpdir()).filter((name) => name.startsWith("deedlight-ca-")).filter((name) => !before.has(name)).length, 0);
    assert.equal(descriptorCount(), descriptorsBefore);
    assert.equal(readFileSync(profilePath).equals(profileBytes), true);
  } finally {
    if (oldProfilePin === undefined) delete process.env.DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256;
    else process.env.DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256 = oldProfilePin;
    if (oldCaPin === undefined) delete process.env.DEEDLIGHT_COLLECTOR_TLS_CA_SHA256;
    else process.env.DEEDLIGHT_COLLECTOR_TLS_CA_SHA256 = oldCaPin;
    rmSync(root, { recursive: true, force: true });
  }
});
