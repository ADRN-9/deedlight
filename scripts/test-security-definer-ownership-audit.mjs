import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const signatures = [
  'public.is_admin()',
  'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)',
  'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)',
  'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)',
  'public.record_delivery_provider_event(text,text,text,text,text)',
  'public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)',
  'public._record_delivery_provider_integrity_conflict(text,text,text,text,text,text,text,timestamptz,text,text,text,text,text,timestamptz,text,text,text)',
  'public._record_delivery_provider_lifecycle_event_pre037_impl(text,text,text,text,timestamptz,text,text,text,text)',
  'public._record_delivery_provider_suppression_event_pre037_impl(text,text,text,text,text,text,timestamptz,timestamptz,text)',
  'public._deny_delivery_provider_integrity_audit_mutation()',
  'public.admin_list_delivery_provider_integrity_conflicts(text,integer)',
  'public.admin_list_delivery_provider_integrity_evidence(bigint,integer)',
  'public.admin_list_delivery_provider_integrity_history(bigint,integer)',
  'public.admin_resolve_delivery_provider_integrity_conflict(bigint,text)',
  'public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamptz,bigint)',
  'public.admin_get_delivery_provider_integrity_conflict(bigint)',
  'public.admin_list_delivery_provider_integrity_evidence_page(bigint,integer,timestamptz,bigint)',
  'public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)',
];

for (const [key, value] of Object.entries({
  DEEDLIGHT_OWNERSHIP_AUDIT_CI: '1',
  PGHOST: '127.0.0.1',
  PGPORT: '5432',
  PGUSER: 'postgres',
  PGDATABASE: 'deedlight_ownership_audit_test',
})) assert.equal(process.env[key], value, 'Tests require isolated disposable PostgreSQL 16: ' + key);

function sqlBlock(markdown, heading) {
  const start = markdown.indexOf(heading);
  assert.notEqual(start, -1, 'Missing audit heading: ' + heading);
  const end = markdown.indexOf('\n### ', start + heading.length);
  const section = markdown.slice(start, end < 0 ? undefined : end);
  const blocks = [...section.matchAll(/`{3}sql\s*\n([\s\S]*?)\n`{3}/gi)];
  assert.equal(blocks.length, 1, 'Expected one fenced SQL block: ' + heading);
  return blocks[0][1].trim();
}

function psql(sql, user = process.env.PGUSER, password = process.env.PGPASSWORD) {
  const result = spawnSync('psql', [
    '--no-psqlrc', '--no-password', '--quiet', '--tuples-only', '--no-align',
    '--set', 'ON_ERROR_STOP=1', '--command', sql,
  ], { encoding: 'utf8', env: { ...process.env, PGUSER: user, PGPASSWORD: password }, maxBuffer: 8 * 1024 * 1024 });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, 'Disposable PostgreSQL failed:\n' + result.stderr + '\n' + sql);
  return result.stdout.trim();
}

function psqlFails(sql, expected, user = process.env.PGUSER, password = process.env.PGPASSWORD) {
  const result = spawnSync('psql', [
    '--no-psqlrc', '--no-password', '--quiet', '--tuples-only', '--no-align',
    '--set', 'ON_ERROR_STOP=1', '--command', sql,
  ], { encoding: 'utf8', env: { ...process.env, PGUSER: user, PGPASSWORD: password }, maxBuffer: 8 * 1024 * 1024 });
  if (result.error) throw result.error;
  assert.notEqual(result.status, 0, 'Expected PostgreSQL command to fail: ' + sql);
  assert.match(result.stderr, expected, 'Unexpected PostgreSQL failure: ' + result.stderr);
}

function quoteLiteral(value) { return "'" + value.replaceAll("'", "''") + "'"; }

function rows(sql) {
  const query = sql.replace(/;\s*$/, "");
  return JSON.parse(psql("SELECT COALESCE(json_agg(row_to_json(r)), '[]'::json) FROM (" + query + ") r;") || '[]');
}

const markdown = readFileSync('docs/PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md', 'utf8');
const q8a = sqlBlock(markdown, '### Query 8A — exact SECURITY DEFINER ownership inventory (18 signatures)');
const q8b = sqlBlock(markdown, '### Query 8B — direct and transitive memberships of function owners');
const q12 = sqlBlock(markdown, '### Query 12 — schema ACL entries');
const q13 = sqlBlock(markdown, '### Query 13 — routine EXECUTE ACL entries');
const q14 = sqlBlock(markdown, '### Query 14 — default privileges affecting relevant schemas');
for (const [name, query] of [['8A', q8a], ['8B', q8b]]) {
  const found = [...query.matchAll(/^\s*\('([^']+)'\),?\s*$/gm)].map((m) => m[1]);
  assert.deepEqual(found, signatures, 'Query ' + name + ' signature inventory changed');
}

const ownerA = 'deedlight_audit_owner_a';
const ownerB = 'deedlight_audit_owner_b';
const ownerEmpty = 'deedlight_audit_owner_without_memberships';
const parent = 'deedlight_audit_parent';
const transitiveRole = 'deedlight_audit_transitive';
const unexpected = 'deedlight_audit_unexpected_bypassrls';
const login = 'deedlight_audit_login';
const loginPassword = 'fixture-only-password';
const appRoles = ['anon', 'authenticated', 'service_role'];
const privilegedRoles = [
  ['deedlight_audit_superuser', 'rolsuper'],
  ['deedlight_audit_createrole', 'rolcreaterole'],
  ['deedlight_audit_createdb', 'rolcreatedb'],
  ['deedlight_audit_replication', 'rolreplication'],
  ['deedlight_audit_bypassrls', 'rolbypassrls'],
];

psql([
  'CREATE ROLE ' + ownerA + ' NOLOGIN INHERIT;',
  'CREATE ROLE ' + ownerB + ' NOLOGIN NOINHERIT;',
  'CREATE ROLE ' + ownerEmpty + ' NOLOGIN INHERIT;',
  'CREATE ROLE ' + parent + ' NOLOGIN INHERIT;',
  'CREATE ROLE ' + transitiveRole + ' NOLOGIN INHERIT;',
  'CREATE ROLE ' + unexpected + ' NOLOGIN BYPASSRLS;',
  ...appRoles.map((role) => 'CREATE ROLE ' + role + ' NOLOGIN;'),
  ...privilegedRoles.map(([role, attribute]) => 'CREATE ROLE ' + role + ' NOLOGIN ' + ({
    rolsuper: 'SUPERUSER', rolcreaterole: 'CREATEROLE', rolcreatedb: 'CREATEDB',
    rolreplication: 'REPLICATION', rolbypassrls: 'BYPASSRLS',
  })[attribute] + ';'),
  'CREATE ROLE ' + login + ' LOGIN PASSWORD ' + quoteLiteral(loginPassword) + ';',
  'GRANT ' + ownerA + ' TO ' + login + ' WITH INHERIT FALSE, SET TRUE;',
  'GRANT CREATE ON SCHEMA public TO ' + ownerA + ', ' + ownerB + ', ' + ownerEmpty + ';',
  'GRANT ' + parent + ' TO ' + ownerA + ' WITH INHERIT TRUE, SET TRUE;',
  'GRANT ' + transitiveRole + ' TO ' + parent + ' WITH INHERIT FALSE, SET TRUE;',
  'GRANT ' + unexpected + ' TO ' + ownerB + ' WITH INHERIT FALSE, SET TRUE;',
].join('\n'));

const ownerFor = (index) => index === 1 ? ownerEmpty
  : index === signatures.length - 1 ? ownerB : ownerA;
for (const [index, signature] of signatures.entries()) {
  psql('CREATE FUNCTION ' + signature + ' RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$ BEGIN RETURN; END; $$;');
  psql('ALTER FUNCTION ' + signature + ' OWNER TO ' + ownerFor(index) + ';');
}
psql([
  'REVOKE ALL ON FUNCTION ' + signatures[1] + ' FROM PUBLIC;',
  'GRANT EXECUTE ON FUNCTION ' + signatures[1] + ' TO service_role;',
  'ALTER DEFAULT PRIVILEGES FOR ROLE ' + ownerA + ' GRANT EXECUTE ON FUNCTIONS TO authenticated;',
  'ALTER DEFAULT PRIVILEGES FOR ROLE ' + ownerA + ' GRANT USAGE ON SCHEMAS TO authenticated;',
].join('\n'));

const inventory = rows(q8a);
assert.equal(inventory.length, 18);
assert.deepEqual(inventory.map((r) => r.expected_identity_signature).sort(), [...signatures].sort());
for (const r of inventory) {
  const index = signatures.indexOf(r.expected_identity_signature);
  assert.notEqual(index, -1, 'Unexpected function identity returned');
  assert.equal(r.inventory_status, 'PRESENT');
  assert.equal(r.security_definer, true);
  assert.equal(r.function_owner, ownerFor(index));
  assert.ok(r.owner_role_oid);
  assert.ok(r.catalog_identity_signature);
  assert.equal(r.catalog_identity_signature.replace(/timestamp with time zone/g, 'timestamptz').replace(/,\s*/g, ','), r.expected_identity_signature);
  for (const field of ['owner_is_superuser', 'owner_role_inherits_memberships', 'owner_can_create_roles',
    'owner_can_create_databases', 'owner_can_login', 'owner_can_replicate', 'owner_bypasses_rls']) {
    assert.notEqual(r[field], null, 'Missing owner attribute: ' + field);
  }
  assert.deepEqual(r.function_settings_search_path, ['search_path=pg_catalog'],
    'Every synthetic SECURITY DEFINER function must have an explicit restricted search_path');
  assert.equal(r.owner_role_inherits_memberships, ownerFor(index) !== ownerB);
  assert.equal(r.owner_can_login, false);
  assertOwnerPrivilegesFailClosed(r);
}
const bySignature = new Map(inventory.map((r) => [r.expected_identity_signature, r]));
function assertOwnerPrivilegesFailClosed(row) {
  for (const field of ['owner_is_superuser', 'owner_can_create_roles', 'owner_can_create_databases',
    'owner_can_replicate', 'owner_bypasses_rls']) {
    assert.equal(row[field], false, 'Unauthorized function-owner privilege: ' + field);
  }
}
for (const [role, attribute] of privilegedRoles) {
  psql('ALTER FUNCTION ' + signatures[0] + ' OWNER TO ' + role + ';');
  const row = rows(q8a).find((r) => r.expected_identity_signature === signatures[0]);
  const field = ({rolsuper:'owner_is_superuser',rolcreaterole:'owner_can_create_roles',
    rolcreatedb:'owner_can_create_databases',rolreplication:'owner_can_replicate',
    rolbypassrls:'owner_bypasses_rls'})[attribute];
  assert.equal(row.function_owner, role);
  assert.equal(row[field], true, 'Query 8A must expose synthetic privileged owner flag: ' + attribute);
  assert.throws(() => assertOwnerPrivilegesFailClosed(row), assert.AssertionError,
    'Unauthorized synthetic owner must fail closed: ' + attribute);
  psql('ALTER FUNCTION ' + signatures[0] + ' OWNER TO ' + ownerA + ';');
}
for (const signature of signatures) {
  const row = bySignature.get(signature);
  const isExplicit = signature === signatures[1];
  assert.equal(row.explicit_function_acl !== null, isExplicit,
    'Every function must expose its actual explicit-versus-default ACL state: ' + signature);
  if (isExplicit) {
    assert.doesNotMatch(row.effective_defaulted_function_acl, /,=X\//,
      'Explicit ACL must preserve revoked PUBLIC EXECUTE: ' + signature);
  } else {
    assert.match(row.effective_defaulted_function_acl, /=X\//,
      'Default ACL must include PUBLIC EXECUTE: ' + signature);
  }
  for (const role of appRoles) {
    const expected = !isExplicit || role === 'service_role';
    assert.equal(
      psql("SELECT has_function_privilege(" + quoteLiteral(role) + ", " + quoteLiteral(signature) + ", 'EXECUTE');"),
      expected ? 't' : 'f',
      'Effective EXECUTE privilege mismatch for ' + role + ' on ' + signature,
    );
  }
}
const schemaAcl = rows(q12);
assert.ok(schemaAcl.some((r) => r.schema_name === 'public' && r.grantee === ownerA && r.privilege === 'CREATE'),
  'Query 12 must expose the synthetic function-owner schema grant');
assert.equal(psql("SELECT has_schema_privilege('authenticated', 'public', 'CREATE');"), 'f');
const routineAcl = rows(q13);
for (const signature of signatures) {
  const [routineName, argumentText] = signature.slice('public.'.length).split('(');
  const args = argumentText.slice(0, -1);
  assert.ok(routineAcl.some((r) => r.schema_name === 'public'
    && r.routine_name === routineName
    && r.identity_arguments.replace(/,\\s*/g, ',') === args
    && r.privilege === 'EXECUTE'),
  'Query 13 must enumerate EXECUTE ACL entries for every audited signature: ' + signature);
}
const defaultAcl = rows(q14);
assert.ok(defaultAcl.some((r) => r.schema_scope === '(all schemas)'
  && r.object_creator_role === ownerA && r.object_type === 'f'
  && r.grantee === 'authenticated' && r.privilege === 'EXECUTE'),
'Query 14 must expose function default privileges');
assert.ok(defaultAcl.some((r) => r.schema_scope === '(all schemas)'
  && r.object_creator_role === ownerA && r.object_type === 'n'
  && r.grantee === 'authenticated' && r.privilege === 'USAGE'),
'Query 14 must expose schema default privileges');
console.log('Queries 8A, 12, 13 and 14: all 18 effective EXECUTE ACLs, schema ACLs, PUBLIC/application grants and function/schema default privileges PASS');

const missingOwnerSql = q8a.replace('ON owner_role.oid = procedure.proowner', 'ON false');
assert.notEqual(missingOwnerSql, q8a);
assert.ok(rows(missingOwnerSql).every((r) => r.inventory_status === 'MISSING_OWNER_ROLE'),
  'Missing owner-role lookup must fail closed');
const nonDefiner = signatures[0];
psql('ALTER FUNCTION ' + nonDefiner + ' SECURITY INVOKER;');
assert.equal(rows(q8a).find((r) => r.expected_identity_signature === nonDefiner).inventory_status,
  'NOT_SECURITY_DEFINER');
psql('ALTER FUNCTION ' + nonDefiner + ' SECURITY DEFINER;');
const missing = 'public.__deedlight_missing_owner_audit_fixture()';
const missingSql = q8a.replace(
  "('public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)')",
  "('public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)'),\n    ('" + missing + "')",
);
assert.notEqual(missingSql, q8a);
assert.equal(rows(missingSql).find((r) => r.expected_identity_signature === missing).inventory_status, 'MISSING_FUNCTION');
console.log('Query 8A: missing function, missing owner-role lookup and non-definer branches PASS');

const memberships = rows(q8b);
const path = (owner, role) => memberships.find((r) => r.function_owner === owner && r.granted_role === role);
const direct = path(ownerA, parent);
assert.ok(direct);
assert.deepEqual(direct.membership_edge_inherit_options, [true]);
assert.deepEqual(direct.membership_edge_set_options, [true]);
assert.equal(direct.owner_is_member, true);
assert.equal(direct.owner_inherits_privileges, true);
assert.equal(direct.owner_can_set_role, true);
psql('SET ROLE ' + ownerA + '; SET ROLE ' + parent + '; RESET ROLE;', login, loginPassword);

const transitive = path(ownerA, transitiveRole);
assert.ok(transitive);
assert.deepEqual(transitive.membership_edge_inherit_options, [true, false]);
assert.deepEqual(transitive.membership_edge_set_options, [true, true]);
assert.equal(transitive.owner_is_member, true);
assert.equal(transitive.owner_inherits_privileges, false);
assert.equal(transitive.owner_can_set_role, true);
psql('SET ROLE ' + ownerA + '; SET ROLE ' + parent + '; SET ROLE ' + transitiveRole + '; RESET ROLE;', login, loginPassword);

const unexpectedPath = path(ownerB, unexpected);
assert.ok(unexpectedPath, 'Unexpected membership must remain visible for review');
assert.equal(unexpectedPath.owner_inherits_privileges, false);
assert.equal(unexpectedPath.owner_can_set_role, true);
assert.equal(unexpectedPath.granted_role_bypasses_rls, true);
assert.equal(memberships.some((r) => r.function_owner === ownerEmpty), false,
  'Owner without memberships must produce no rows');
console.log('Query 8B: direct/transitive memberships, INHERIT, SET, effective privileges and unexpected membership PASS');

psql('GRANT ' + parent + ' TO ' + ownerA + ' WITH INHERIT FALSE, SET FALSE;');
const changedOptions = rows(q8b).find((r) => r.function_owner === ownerA && r.granted_role === parent);
assert.ok(changedOptions);
assert.deepEqual(changedOptions.membership_edge_inherit_options, [false]);
assert.deepEqual(changedOptions.membership_edge_set_options, [false]);
assert.equal(changedOptions.owner_is_member, true);
assert.equal(changedOptions.owner_inherits_privileges, false);
assert.equal(changedOptions.owner_can_set_role, false);
psqlFails('SET ROLE ' + ownerA + '; SET ROLE ' + parent + ';', /permission denied to set role/, login, loginPassword);

psql('GRANT ' + parent + ' TO ' + ownerA + ' WITH INHERIT TRUE, SET TRUE;');
const restoredOptions = rows(q8b).find((r) => r.function_owner === ownerA && r.granted_role === parent);
assert.deepEqual(restoredOptions.membership_edge_inherit_options, [true]);
assert.deepEqual(restoredOptions.membership_edge_set_options, [true]);
assert.equal(restoredOptions.owner_inherits_privileges, true);
assert.equal(restoredOptions.owner_can_set_role, true);
psql('SET ROLE ' + ownerA + '; SET ROLE ' + parent + '; RESET ROLE;');

psql('GRANT ' + transitiveRole + ' TO ' + parent + ' WITH INHERIT FALSE, SET FALSE;');
const transitiveSetDisabled = rows(q8b).find((r) => r.function_owner === ownerA && r.granted_role === transitiveRole);
assert.ok(transitiveSetDisabled);
assert.equal(transitiveSetDisabled.owner_can_set_role, false);
psqlFails('SET ROLE ' + ownerA + '; SET ROLE ' + parent + '; SET ROLE ' + transitiveRole + ';',
  /permission denied to set role/, login, loginPassword);
psql('GRANT ' + transitiveRole + ' TO ' + parent + ' WITH INHERIT FALSE, SET TRUE;');
assert.equal(rows(q8b).find((r) => r.function_owner === ownerA && r.granted_role === transitiveRole).owner_can_set_role, true);
psql('SET ROLE ' + ownerA + '; SET ROLE ' + parent + '; SET ROLE ' + transitiveRole + '; RESET ROLE;', login, loginPassword);
psql('REVOKE ' + parent + ' FROM ' + ownerA + ';');
const revokedMemberships = rows(q8b);
assert.equal(revokedMemberships.some((r) => r.function_owner === ownerA && r.granted_role === parent), false);
assert.equal(revokedMemberships.some((r) => r.function_owner === ownerA && r.granted_role === transitiveRole), false);
psql('GRANT ' + parent + ' TO ' + ownerA + ' WITH INHERIT TRUE, SET TRUE;');
const restoredMemberships = rows(q8b);
assert.equal(restoredMemberships.some((r) => r.function_owner === ownerA && r.granted_role === parent), true);
assert.equal(restoredMemberships.some((r) => r.function_owner === ownerA && r.granted_role === transitiveRole), true);
console.log('Query 8B: membership option changes, revoke and transitive-path restoration PASS');

for (const signature of signatures) psql('DROP FUNCTION ' + signature + ';');
psql([
  'ALTER DEFAULT PRIVILEGES FOR ROLE ' + ownerA + ' REVOKE EXECUTE ON FUNCTIONS FROM authenticated;',
  'ALTER DEFAULT PRIVILEGES FOR ROLE ' + ownerA + ' REVOKE USAGE ON SCHEMAS FROM authenticated;',
  'REVOKE ' + parent + ' FROM ' + ownerA + ';',
  'REVOKE ' + transitiveRole + ' FROM ' + parent + ';',
  'REVOKE ' + unexpected + ' FROM ' + ownerB + ';',
  'REVOKE ' + ownerA + ' FROM ' + login + ';',
  'REVOKE CREATE ON SCHEMA public FROM ' + ownerA + ', ' + ownerB + ', ' + ownerEmpty + ';',
  'DROP ROLE ' + [ownerA, ownerB, ownerEmpty, parent, transitiveRole, unexpected, login,
    ...appRoles, ...privilegedRoles.map(([role]) => role)].join(', ') + ';',
].join('\n'));
console.log('Disposable PostgreSQL 16 SECURITY DEFINER ownership audit behavior: PASS');
