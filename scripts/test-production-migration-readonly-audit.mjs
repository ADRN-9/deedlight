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

test("authenticated and effective role identities are separately validated", () => {
  for (const token of [
    "deedlight_catalog_auditor",
    "deedlight.authenticated_principal",
    "session_user",
    "current_user",
    "current_setting('role', true)",
    "rolcanlogin",
    "rolsuper",
    "rolcreaterole",
    "rolcreatedb",
    "rolreplication",
    "rolbypassrls",
    "pg_catalog.pg_has_role",
  ]) assert.ok(sql.includes(token), `missing authenticated-principal guard: ${token}`);
  assert.doesNotMatch(sql, /session_user\s*=\s*current_user|current_user\s*=\s*session_user/i);
  assert.match(sql, /SET ROLE is prohibited/);
  assert.match(sql, /Authenticated or effective collector role has role membership/);
});

test("routine configuration is an explicit allowlist with deterministic serialization", () => {
  for (const setting of [
    "search_path", "row_security", "default_transaction_read_only",
    "statement_timeout", "lock_timeout", "idle_in_transaction_session_timeout",
    "temp_file_limit",
  ]) assert.ok(sql.includes(setting), `missing reviewed routine setting: ${setting}`);
  assert.match(sql, /Unexpected or unsafe routine configuration/);
  assert.match(sql, /jsonb_agg\([\s\S]*?ORDER BY split_part\(cfg\.setting, '=', 1\)/);
  assert.doesNotMatch(sql, /p\.proconfig\s+AS\s+routine_settings/i);
  assert.doesNotMatch(sql, /rolconfig/);
});

test("audit requires exact migration-history columns, types, nullability, constraints and index", () => {
  for (const token of [
    "v_history_column_count <> 3",
    "'pg_catalog.text'::regtype",
    "'pg_catalog.text[]'::regtype",
    "a.attnotnull",
    "a.attgenerated",
    "a.attidentity",
    "pg_catalog.pg_attrdef",
    "pg_catalog.pg_constraint",
    "conkey = ARRAY[v_version_attnum]::smallint[]",
    "pg_catalog.pg_index",
    "indisprimary",
    "indisunique",
    "indisvalid",
    "indisready",
    "indislive",
    "am.amname = 'btree'",
    "^[0-9]{12}$",
  ]) assert.ok(sql.includes(token), `missing migration-history schema guard: ${token}`);
  assert.match(sql, /exactly version text NOT NULL, name text NULL, statements text\[\] NULL/);
});

test("audit fails closed for missing catalogs and unsupported migration history", () => {
  assert.match(sql, /Required catalog SELECT access unavailable/);
  assert.match(sql, /Required Supabase migration-history table is unavailable/);
  assert.match(sql, /Unsupported migration-history schema/);
  assert.match(sql, /Unsupported migration-history constraints/);
  assert.match(sql, /Unsupported migration-history indexes/);
});

test("collector rejects effective application access and role escalation", () => {
  for (const token of [
    "has_table_privilege", "has_any_column_privilege", "has_sequence_privilege",
    "has_schema_privilege", "has_database_privilege",
  ]) assert.ok(sql.includes(token), `missing least-privilege guard: ${token}`);
  assert.match(sql, /pg_read_all_data/);
  assert.match(sql, /pg_write_all_data/);
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
