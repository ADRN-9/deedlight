import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

const root = process.cwd();
const sql = readFileSync(path.join(root, "scripts/production-migration-037-backfill-aggregate-audit.sql"), "utf8");
const fixture = readFileSync(path.join(root, "scripts/test-migration-037-backfill-audit-postgres16-fixture.sql"), "utf8");
const runner = readFileSync(path.join(root, "scripts/test-migration-037-backfill-audit-postgres16.sh"), "utf8");

test("Migration 037 audit is a direct DBA-only read-only transaction", () => {
  assert.match(sql, /BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;/);
  assert.match(sql, /SET LOCAL search_path = pg_catalog;/);
  assert.match(sql, /session_user IS DISTINCT FROM current_user/);
  assert.match(sql, /current_setting\('role', true\) IS DISTINCT FROM 'none'/);
  assert.match(sql, /v_is_superuser OR v_role_oid = v_database_owner/);
  assert.match(sql, /ROLLBACK;\s*$/);
  assert.doesNotMatch(sql.replace(/--[^\n]*/g, "").replace(/'(?:''|[^'])*'/g, " "), /\b(?:INSERT|UPDATE|DELETE|TRUNCATE|CREATE|ALTER|DROP|GRANT|REVOKE|COPY|CALL|EXECUTE|PERFORM|VACUUM|REFRESH|COMMIT)\b/i);
});

test("aggregate output contains counts and status only, never private identifiers or source rows", () => {
  const output = sql.slice(sql.lastIndexOf("\nSELECT\n"));
  for (const field of ["source_anomaly_count", "missing_source_event_count", "missing_stored_event_count",
    "expected_case_count", "missing_case_count", "expected_legacy_evidence_count", "actual_legacy_evidence_count",
    "missing_null_fingerprint_rows", "extra_null_fingerprint_rows", "missing_fingerprint_groups",
    "extra_fingerprint_groups", "conflicting_fingerprint_groups", "unmatched_legacy_evidence_rows",
    "provider_rpc_only_anomaly_rows", "complete"]) assert.ok(output.includes(field), "missing aggregate: " + field);
  assert.doesNotMatch(output, /recipient_email|provider_email_id|event_id|stored_recipient_email|payload_fingerprint/);
  assert.match(sql, /EXCEPT ALL/);
  assert.match(sql, /fingerprint_variants/);
  assert.match(sql, /unmatched_legacy_rows/);
  assert.match(sql, /provider_rpc_only_rows/);
});

test("fixture and integration runner cover incomplete, inconsistent and unauthorized cases", () => {
  assert.match(fixture, /one@example\.invalid/);
  assert.match(fixture, /legacy_anomaly_backfill/);
  assert.match(runner, /incomplete Migration 037 backfill is detected/);
  assert.match(runner, /inconsistent evidence-to-source association fails closed/);
  assert.match(runner, /unauthorized database role cannot read underlying records/);
  assert.match(runner, /deedlight_backfill_unauthorized/);
});
