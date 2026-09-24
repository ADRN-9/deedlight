import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const migrationPath = path.join(
  root,
  "supabase/migrations/202609240022_auth_pgcrypto_schema_qualification.sql",
);
const aggregatePath = path.join(root, "supabase/run_in_sql_editor_all.sql");
const testPath = path.join(root, "scripts/test-auth-pgcrypto-schema-qualification.sql");

const migration = fs.readFileSync(migrationPath, "utf8");
const aggregate = fs.readFileSync(aggregatePath, "utf8");
const behaviorTest = fs.readFileSync(testPath, "utf8");

assert.match(
  migration,
  /to_regprocedure\('extensions\.gen_random_bytes\(integer\)'\)/,
  "migration must fail closed when the expected pgcrypto function is missing",
);
assert.match(
  migration,
  /create or replace function public\.handle_new_user\(\)/i,
  "migration must replace only the Deedlight Auth-user bootstrap function",
);
assert.match(
  migration,
  /security definer/i,
  "Auth-user bootstrap must remain SECURITY DEFINER",
);
assert.match(
  migration,
  /set search_path\s*=\s*public, auth/i,
  "existing hardened function search_path contract must remain explicit",
);
assert.match(
  migration,
  /extensions\.gen_random_bytes\(8\)/,
  "pgcrypto dependency must be schema-qualified",
);
assert.doesNotMatch(
  migration.replace(/extensions\.gen_random_bytes\(8\)/g, ""),
  /\bgen_random_bytes\s*\(/,
  "migration must not retain an unqualified gen_random_bytes call",
);
assert.doesNotMatch(
  migration,
  /alter\s+role\s+supabase_auth_admin|grant\s+usage\s+on\s+schema\s+extensions\s+to\s+supabase_auth_admin/i,
  "hotfix must not widen Supabase Auth platform role privileges or search_path",
);
assert.match(
  behaviorTest,
  /Expected the unqualified pgcrypto call to fail/,
  "behavior test must prove it catches the pre-hotfix failure",
);
assert.match(
  behaviorTest,
  /Auth-trigger profile username was not generated correctly/,
  "behavior test must prove profile bootstrap still succeeds after the fix",
);

assert.ok(
  aggregate.includes(migration.trim()),
  "aggregate SQL must include migration 022 verbatim",
);

console.log("Auth pgcrypto schema-qualification security assertions PASS");
