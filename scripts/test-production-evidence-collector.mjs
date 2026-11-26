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

function validCsv() {
  const rows = [];
  for (let i = 0; i < 13; i += 1) {
    rows.push(["projection_" + i, "value"], ["sample", String(i)]);
  }
  rows.push(
    ["evidence_projection", "database_count", "database_oid", "expanded_acl_edges"],
    ["database_acl_v1", "2", "1", "[]"],
    ["database_acl_v1", "2", "2", "[]"],
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
    'evidence_projection,database_count,database_oid,expanded_acl_edges\r\ndatabase_acl_v1,2,1,[]\r\ndatabase_acl_v1,2,2,[]\r\n',
    "",
  );
  assert.throws(() => validateSqlOutput(csv), (error) => error instanceof CollectorError && error.code === "DATABASE_ACL_PROJECTION_MISSING");
});

test("truncated database ACL rows fail closed", () => {
  const csv = validCsv().replace('database_acl_v1,2,2,[]\r\n', "");
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
