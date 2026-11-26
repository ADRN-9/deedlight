import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  CollectorError,
  canonicalJson,
  parseCsv,
  validateSqlOutput,
  verifyReceiptAndEvidence,
  sha256,
  SQL_SHA256,
} from "./collect-production-migration-evidence.mjs";

function serializeCsvField(value) {
  const text = String(value);
  return /[",\\x0d\\x0a]/.test(text) ? '"' + text.replace(/"/g, '""') + '"' : text;
}

function serializeCsv(rows) {
  const newline = String.fromCharCode(13, 10);
  return rows.map((row) => row.map(serializeCsvField).join(",")).join(newline) + newline;
}

function replaceAclEdges(csv, edges) {
  const rows = parseCsv(csv);
  const row = rows.find((entry) => entry[0] === "database_acl_v1" && entry[2] === "1");
  assert.ok(row, "database_acl_v1 fixture row must exist");
  row[6] = JSON.stringify(edges);
  return serializeCsv(rows);
}

function validCsv() {
  const rows = [];
  for (let i = 0; i < 13; i += 1) {
    rows.push(["projection_" + i, "value"], ["sample", String(i)]);
  }
  rows.push(
    ["evidence_projection", "database_count", "database_oid", "owner_oid", "datacl_was_null", "acl_expansion_source", "expanded_acl_edges"],
    ["database_acl_v1", "2", "1", "10", "t", "built_in_default", "[]"],
    ["database_acl_v1", "2", "2", "10", "f", "explicit", "[]"],
    ["collector_transaction_closed"],
    ["t"],
  );
  return rows.map((row) => row.map((cell) => {
    const value = String(cell);
    return /[",\r\n]/.test(value) ? '"' + value.replace(/"/g, '""') + '"' : value;
  }).join(",")).join("\r\n") + "\r\n";
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
    'evidence_projection,database_count,database_oid,owner_oid,datacl_was_null,acl_expansion_source,expanded_acl_edges\r\ndatabase_acl_v1,2,1,10,t,built_in_default,[]\r\ndatabase_acl_v1,2,2,10,f,explicit,[]\r\n',
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
    "database_acl_v1,2,2,10,f,explicit,[]",
    "database_acl_v1,2,1,10,f,explicit,[]",
  );
  assert.throws(() => validateSqlOutput(csv), (error) => error.code === "DATABASE_ACL_PROJECTION_DUPLICATED_OR_UNORDERED");
});

test("database ACL NULL/default provenance must agree", () => {
  const csv = validCsv().replace(
    "database_acl_v1,2,1,10,t,built_in_default,[]",
    "database_acl_v1,2,1,10,t,explicit,[]",
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
  const csv = validCsv().replace("database_acl_v1,2,1,10,t,built_in_default,[]", "database_acl_v1,2,1,10,t,built_in_default,{bad}");
  assert.throws(() => validateSqlOutput(csv), (error) => error instanceof CollectorError && error.code === "DATABASE_ACL_EDGES_INVALID_JSON");
});

test("truncated database ACL rows fail closed", () => {
  const csv = validCsv().replace('database_acl_v1,2,2,10,f,explicit,[]\r\n', "");
  assert.throws(() => validateSqlOutput(csv), (error) => error instanceof CollectorError && error.code === "DATABASE_ACL_PROJECTION_INCOMPLETE");
});

test("malformed or truncated CSV fails closed", () => {
  assert.throws(() => parseCsv('"unterminated'), (error) => error instanceof CollectorError && error.code === "TRUNCATED_CSV_QUOTE");
  assert.throws(() => parseCsv("a\u0000b"), (error) => error instanceof CollectorError && error.code === "INVALID_CSV_NUL");
});

test("receipt binds raw evidence and canonical result digest", () => {
  const csv = Buffer.from(validCsv());
  const rows = validateSqlOutput(csv);
  const receipt = {
    schemaVersion: 1,
    kind: "deedlight-production-migration-collection",
    status: "UNSIGNED_NOT_ACCEPTED",
    execution: {
      canonicalResultSha256: sha256(Buffer.from(canonicalJson(rows.resultRows))),
      evidenceFileSha256: sha256(csv),
      databaseAclV1RowCount: rows.databaseAclRows,
    },
    evidence: { sha256: sha256(csv) },
    signing: { state: "NOT_SIGNED" },
  };
  assert.equal(verifyReceiptAndEvidence(receipt, csv), true);
  const tampered = Buffer.from(csv.toString().replace('database_acl_v1,2,1,', 'database_acl_v1,2,9,'));
  assert.throws(() => verifyReceiptAndEvidence(receipt, tampered), (error) => error.code === "EVIDENCE_DIGEST_MISMATCH");
});

test("receipt cannot claim signed or accepted state in E2", () => {
  const csv = Buffer.from(validCsv());
  const rows = validateSqlOutput(csv);
  const receipt = {
    schemaVersion: 1, kind: "deedlight-production-migration-collection", status: "ACCEPTED",
    execution: { canonicalResultSha256: sha256(Buffer.from(canonicalJson(rows.resultRows))), evidenceFileSha256: sha256(csv), databaseAclV1RowCount: 2 },
    evidence: { sha256: sha256(csv) }, signing: { state: "SIGNED" },
  };
  assert.throws(() => verifyReceiptAndEvidence(receipt, csv), (error) => error.code === "RECEIPT_SCHEMA_OR_STATUS_INVALID");
});

test("receipt result binding rejects a forged canonical digest", () => {
  const csv = Buffer.from(validCsv());
  const rows = validateSqlOutput(csv);
  const receipt = {
    schemaVersion: 1, kind: "deedlight-production-migration-collection", status: "UNSIGNED_NOT_ACCEPTED",
    execution: { canonicalResultSha256: "0".repeat(64), evidenceFileSha256: sha256(csv), databaseAclV1RowCount: 2 },
    evidence: { sha256: sha256(csv) }, signing: { state: "NOT_SIGNED" },
  };
  assert.throws(() => verifyReceiptAndEvidence(receipt, csv), (error) => error.code === "RECEIPT_RESULT_BINDING_MISMATCH");
});
