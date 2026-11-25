import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

const sql = readFileSync(
  path.join(process.cwd(), "scripts/production-migration-readonly-audit.sql"),
  "utf8",
);

test("audit runs in a repeatable-read read-only transaction and rolls back", () => {
  assert.match(sql, /BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;/i);
  assert.match(sql, /current_setting\('transaction_read_only'\)\s*<>\s*'on'/i);
  assert.match(sql, /ROLLBACK;\s*$/i);
});

test("audit requires the exact project reference and a 40-character repository SHA", () => {
  assert.match(sql, /deedlight\.expected_project_ref/);
  assert.match(sql, /xaipiovflxomcbfwtwmu/);
  assert.match(sql, /deedlight\.repository_sha/);
  assert.match(sql, /\[0-9a-f\]\{40\}/);
});

test("audit fails closed when migration history or SELECT authority is missing", () => {
  assert.match(sql, /to_regclass\('supabase_migrations\.schema_migrations'\)/);
  assert.match(sql, /has_table_privilege\(current_user, v_history_oid, 'SELECT'\)/);
  assert.match(sql, /Required Supabase migration-history table is unavailable/);
});

test("audit includes all required catalog evidence surfaces", () => {
  for (const token of [
    "pg_class", "pg_attribute", "pg_proc", "pg_roles", "pg_auth_members",
    "pg_policies", "pg_constraint", "pg_indexes", "pg_trigger",
    "pg_default_acl", "pg_extension", "supabase_migrations.schema_migrations",
    "pg_get_function_identity_arguments", "prosecdef", "relrowsecurity",
    "relforcerowsecurity", "aclexplode",
  ]) assert.ok(sql.includes(token), `missing catalog evidence: ${token}`);
});

test("audit contains no SQL mutation or privilege-changing statements, including DO blocks", () => {
  const withoutCommentsAndLiterals = sql
    .replace(/--[^\n]*/g, "")
    .replace(/'(?:''|[^'])*'/g, " ");
  assert.doesNotMatch(
    withoutCommentsAndLiterals,
    /\b(?:INSERT|UPDATE|DELETE|TRUNCATE|CREATE|ALTER|DROP|GRANT|REVOKE|COPY|CALL|EXECUTE|PERFORM|VACUUM|REFRESH|COMMIT)\b/i,
  );
});

test("audit excludes application rows, function bodies and secrets", () => {
  assert.match(sql, /Function bodies are excluded/i);
  assert.match(sql, /Migration-history identifiers only/i);
  assert.doesNotMatch(sql, /SUPABASE_SERVICE_ROLE_KEY|postgres:\/\/|password\s*=/i);
  assert.doesNotMatch(sql, /SELECT\s+\*\s+FROM\s+public\./i);
});
