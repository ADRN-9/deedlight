import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

const sql = readFileSync(
  path.join(process.cwd(), "scripts/production-migration-readonly-audit.sql"),
  "utf8",
);

function sqlLexicalError(source) {
  let state = "code";
  let returnState = "code";
  let dollarReturnState = "code";
  let dollarTag = "";
  let depth = 0;
  const openParens = [];
  let line = 1;

  for (let i = 0; i < source.length;) {
    const char = source[i];
    const next = source[i + 1];

    if (state === "line-comment") {
      if (char === "\n") { state = returnState; line += 1; }
      i += 1;
      continue;
    }
    if (state === "block-comment") {
      if (char === "*" && next === "/") { state = returnState; i += 2; continue; }
      if (char === "\n") line += 1;
      i += 1;
      continue;
    }
    if (state === "single-quote") {
      if (char === "'" && next === "'") { i += 2; continue; }
      if (char === "'") state = returnState;
      if (char === "\n") line += 1;
      i += 1;
      continue;
    }
    if (state === "double-quote") {
      if (char === '"' && next === '"') { i += 2; continue; }
      if (char === '"') state = returnState;
      if (char === "\n") line += 1;
      i += 1;
      continue;
    }
    if (state === "dollar-quote" && source.startsWith(dollarTag, i)) {
      state = dollarReturnState;
      i += dollarTag.length;
      continue;
    }

    if (char === "-" && next === "-") {
      returnState = state;
      state = "line-comment";
      i += 2;
      continue;
    }
    if (char === "/" && next === "*") {
      returnState = state;
      state = "block-comment";
      i += 2;
      continue;
    }
    if (char === "'") {
      returnState = state;
      state = "single-quote";
      i += 1;
      continue;
    }
    if (char === '"') {
      returnState = state;
      state = "double-quote";
      i += 1;
      continue;
    }
    if (char === "$") {
      const tag = source.slice(i).match(/^\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/)?.[0];
      if (tag) {
        dollarTag = tag;
        dollarReturnState = state;
        state = "dollar-quote";
        i += tag.length;
        continue;
      }
    }
    if (char === "(") {
      depth += 1;
      openParens.push(line);
    } else if (char === ")") {
      depth -= 1;
      if (depth < 0) return `unmatched closing parenthesis at line ${line}`;
      openParens.pop();
    }
    if (char === "\n") line += 1;
    i += 1;
  }

  if (state !== "code" && state !== "line-comment") return `unterminated ${state}`;
  if (depth !== 0) return `unclosed parenthesis opened at line ${openParens.at(-1)}`;
  return null;
}

test("audit SQL is structurally complete and lexically well formed", () => {
  const declaration = sql.slice(sql.indexOf("DECLARE"), sql.indexOf("BEGIN", sql.indexOf("DECLARE")));
  assert.doesNotMatch(declaration, /to_regclass\('supabase_migrations\.schema_migrations'\)/);
  assert.match(sql, /SET ROLE is prohibited for the migration audit collector\.[\s\S]*?v_history_oid := to_regclass\('supabase_migrations\.schema_migrations'\)/);
  assert.equal(sqlLexicalError(sql), null, sqlLexicalError(sql) ?? undefined);
  assert.equal((sql.match(/^BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;$/gim) ?? []).length, 1);
  assert.equal((sql.match(/^DO \$audit_preflight\$/gm) ?? []).length, 1);
  assert.equal((sql.match(/^END\n\$audit_preflight\$;$/gm) ?? []).length, 1);
  assert.equal((sql.match(/^ROLLBACK;$/gm) ?? []).length, 1);
  assert.match(sql, /ROLLBACK;\s*$/);
  const sections = [...sql.matchAll(/^-- (\d{2})\./gm)].map((match) => Number(match[1]));
  assert.deepEqual(sections, Array.from({ length: 13 }, (_, index) => index + 1));
});

test("SQL malformed-input detector rejects broken delimiters and quotes", () => {
  assert.match(sqlLexicalError("SELECT (1;"), /unclosed parenthesis/);
  assert.match(sqlLexicalError("SELECT 'unterminated;"), /unterminated single-quote/);
  assert.match(sqlLexicalError("DO $broken$ BEGIN NULL;"), /unterminated dollar-quote/);
  assert.match(sqlLexicalError("SELECT 1);"), /unmatched closing parenthesis/);
});

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

test("routine configuration is canonical, trusted, bounded and deterministically serialized", () => {
  for (const setting of [
    "search_path", "row_security", "default_transaction_read_only",
    "statement_timeout", "lock_timeout", "idle_in_transaction_session_timeout",
    "temp_file_limit",
  ]) assert.ok(sql.includes(setting), `missing reviewed routine setting: ${setting}`);
  assert.match(sql, /Unexpected or unsafe routine configuration/);
  assert.match(sql, /pg_catalog\|public\|extensions\|auth\|storage/);
  assert.match(sql, /array_position\([\s\S]*?pg_temp/);
  assert.match(sql, /cardinality\(string_to_array\([\s\S]*?cardinality\(ARRAY\(/);
  assert.match(sql, /pg_catalog\.acldefault\('n'/);
  assert.match(sql, /acl\.grantee = 0 AND acl\.privilege_type = 'CREATE'/);
  assert.match(sql, /path_owner\.rolcanlogin/);
  assert.match(sql, /database_owner\.datdba/);
  assert.doesNotMatch(sql, /path_owner\.rolname <> 'pg_database_owner'/);
  assert.match(sql, /row_security' AND parsed\.setting_value = 'on'/);
  assert.match(sql, /default_transaction_read_only' AND parsed\.setting_value = 'on'/);
  assert.match(sql, /timeout_value\.parts IS NOT NULL/);
  assert.match(sql, /statement_timeout' THEN 300000/);
  assert.match(sql, /lock_timeout' THEN 30000/);
  assert.match(sql, /idle_in_transaction_session_timeout' THEN 60000/);
  assert.match(sql, /temp_file_value\.parts IS NOT NULL/);
  assert.match(sql, /temp_file_value\.parts\[1\]::numeric/);
  assert.match(sql, /WHEN 'gb' THEN 1073741824/);
  assert.match(sql, /<= 1073741824/);
  assert.match(sql, /\^\(\[1-9\]\[0-9\]\{0,9\}\)\(kb\|mb\|gb\)\?\$/);
  assert.match(sql, /regexp_replace\(cfg\.setting, '\^\[\^=\]\*=', ''\)/);
  assert.match(sql, /pg_catalog\.btrim\(regexp_replace\(cfg\.setting, '\^\[\^=\]\*=', ''\), '\"'\)/);
  assert.match(sql, /WHEN split_part\(cfg\.setting, '=', 1\) = 'search_path'/);
  assert.match(sql, /jsonb_agg\([\s\S]*?ORDER BY split_part\(cfg\.setting, '=', 1\)/);
  assert.doesNotMatch(sql, /substring\(cfg\.setting FROM position\('/);
  assert.doesNotMatch(sql, /p\.proconfig\s+AS\s+routine_settings/i);
  assert.doesNotMatch(sql, /rolconfig/);
  assert.doesNotMatch(sql, /pg_catalog\.pg_size_bytes\(parsed\.setting_value\)/);
  assert.match(sql, /\^\(\[1-9\]\[0-9\]\{0,8\}\)\(us\|ms\|s\|min\|h\|d\)\?\$/);
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
  assert.match(sql, /WHERE path_ns\.nspname = path\.schema_name/);
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
  const fixture = readFileSync(
    path.join(process.cwd(), "scripts/test-production-migration-readonly-audit-postgres16-fixture.sql"),
    "utf8",
  );
  const runner = readFileSync(
    path.join(process.cwd(), "scripts/test-production-migration-readonly-audit-postgres16.sh"),
    "utf8",
  );
  assert.match(runner, /missing_search_path_schema/);
  assert.match(runner, /deedlight_audit_missing_schema/);
  assert.match(runner, /login_owned_routine_schema/);
  assert.match(runner, /untrusted_routine_schema_creator/);
  assert.match(runner, /public_create_routine_search_path/);
  assert.match(runner, /psql_as deedlight_catalog_auditor -X -qAt/);
  assert.match(runner, /schema-trust\.log/);
  assert.match(runner, /routine-search-path\.log/);
  assert.doesNotMatch(runner, /^SQLL$/m);
  assert.match(runner, /pg_catalog\.btrim\(regexp_replace\(cfg\.setting/);
  assert.doesNotMatch(runner, /proconfig.*setting_value.*schema-trust\.log/s);
  assert.match(fixture, /REVOKE CREATE ON SCHEMA public FROM PUBLIC/);
  assert.match(fixture, /SET search_path = 'pg_catalog'/);
  assert.match(fixture, /SET search_path = 'pg_catalog, public'/);
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

test("SECURITY DEFINER fixture mirrors the audit authenticated/effective identity contract", () => {
  const fixture = readFileSync(
    path.join(process.cwd(), "scripts/test-production-migration-readonly-audit-postgres16-fixture.sql"),
    "utf8",
  );
  const sharedRules = [
    ["session_user <> 'deedlight_catalog_auditor'", "session_user <> 'deedlight_catalog_auditor'"],
    ["v_authenticated_principal IS DISTINCT FROM session_user", "current_setting('deedlight.authenticated_principal', true) IS DISTINCT FROM session_user"],
    ["v_role_setting IS DISTINCT FROM 'none'", "current_setting('role', true) IS DISTINCT FROM 'none'"],
    ["WHERE oid = v_session_role_oid AND rolcanlogin", "WHERE oid = v_session_role_oid AND rolcanlogin"],
    ["WHERE oid = v_effective_role_oid", "WHERE oid = v_effective_role_oid"],
    ["pg_catalog.pg_has_role(v_session_role_oid, r.oid, 'MEMBER')", "pg_catalog.pg_has_role(v_session_role_oid, r.oid, 'MEMBER')"],
    ["pg_catalog.pg_has_role(v_effective_role_oid, r.oid, 'MEMBER')", "pg_catalog.pg_has_role(v_effective_role_oid, r.oid, 'MEMBER')"],
  ];
  for (const [auditRule, fixtureRule] of sharedRules) {
    assert.ok(sql.includes(auditRule), `audit preflight missing shared identity rule: ${auditRule}`);
    assert.ok(fixture.includes(fixtureRule), `SECURITY DEFINER fixture missing shared identity rule: ${fixtureRule}`);
  }
});
