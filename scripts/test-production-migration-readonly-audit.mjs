import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

const sql = readFileSync(
  path.join(process.cwd(), "scripts/production-migration-readonly-audit.sql"),
  "utf8",
);

test("audit uses a repeatable-read read-only transaction and rolls back", () => {
  assert.match(sql, /BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;/i);
  assert.match(sql, /current_setting\('transaction_read_only'\)\s*<>\s*'on'/i);
  assert.match(sql, /ROLLBACK;\s*$/i);
});

test("audit requires exact non-secret project and repository metadata", () => {
  assert.match(sql, /deedlight\.expected_project_ref/);
  assert.match(sql, /xaipiovflxomcbfwtwmu/);
  assert.match(sql, /deedlight\.repository_sha/);
  assert.match(sql, /\[0-9a-f\]\{40\}/);
});

test("audit fails closed for missing catalogs and unsupported migration history", () => {
  assert.match(sql, /Required catalog SELECT access unavailable/);
  assert.match(sql, /Required Supabase migration-history table is unavailable/);
  assert.match(sql, /expected version, name and array statements columns/);
});

test("collector contract rejects role escalation, memberships and effective application access", () => {
  for (const token of [
    "rolsuper", "rolcreaterole", "rolcreatedb", "rolreplication", "rolbypassrls",
    "pg_read_all_data", "pg_write_all_data", "pg_has_role",
    "has_table_privilege", "has_any_column_privilege", "has_sequence_privilege",
    "has_schema_privilege", "has_database_privilege",
  ]) assert.ok(sql.includes(token), `missing least-privilege guard: ${token}`);
  assert.doesNotMatch(sql, /rolconfig/);
});

test("sequence definitions, ownership, ACLs and index health are captured", () => {
  for (const token of [
    "pg_catalog.pg_sequence", "pg_catalog.pg_depend", "owned_table_schema",
    "pg_catalog.acldefault('S'", "pg_catalog.pg_index", "indisvalid",
    "indisready", "indislive", "indisunique", "indisprimary",
  ]) assert.ok(sql.includes(token), `missing catalog evidence: ${token}`);
});

test("migration history uses explicit version/name/array projections only", () => {
  assert.match(sql, /h\.version::text AS version/);
  assert.match(sql, /h\.name::text AS migration_name/);
  assert.match(sql, /cardinality\(h\.statements\)/);
  assert.doesNotMatch(sql, /to_jsonb\(h\)|row_to_json\(h\)/i);
});

test("audit contains no SQL mutation or privilege-changing statements", () => {
  const withoutCommentsAndLiterals = sql
    .replace(/--[^\n]*/g, "")
    .replace(/'(?:''|[^'])*'/g, " ");
  assert.doesNotMatch(
    withoutCommentsAndLiterals,
    /\b(?:INSERT|UPDATE|DELETE|TRUNCATE|CREATE|ALTER|DROP|GRANT|REVOKE|COPY|CALL|EXECUTE|PERFORM|VACUUM|REFRESH|COMMIT)\b/i,
  );
});

test("audit excludes application rows, function bodies and credential material", () => {
  assert.match(sql, /Function bodies are excluded/i);
  assert.match(sql, /Migration-history identifiers only/i);
  assert.doesNotMatch(sql, /SUPABASE_SERVICE_ROLE_KEY|postgres:\/\/|password\s*=/i);
  assert.doesNotMatch(sql, /SELECT\s+\*\s+FROM\s+public\./i);
});
