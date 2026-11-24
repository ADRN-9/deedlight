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

function psql(sql) {
  const result = spawnSync('psql', [
    '--no-psqlrc', '--no-password', '--quiet', '--tuples-only', '--no-align',
    '--set', 'ON_ERROR_STOP=1', '--command', sql,
  ], { encoding: 'utf8', env: process.env, maxBuffer: 8 * 1024 * 1024 });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, 'Disposable PostgreSQL failed:\n' + result.stderr + '\n' + sql);
  return result.stdout.trim();
}

function rows(sql) {
  const query = sql.replace(/;\s*$/, "");
  return JSON.parse(psql("SELECT COALESCE(json_agg(row_to_json(r)), '[]'::json) FROM (" + query + ") r;") || '[]');
}

const markdown = readFileSync('docs/PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md', 'utf8');
const q8a = sqlBlock(markdown, '### Query 8A — exact SECURITY DEFINER ownership inventory (18 signatures)');
const q8b = sqlBlock(markdown, '### Query 8B — direct and transitive memberships of function owners');
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

psql([
  'CREATE ROLE ' + ownerA + ' NOLOGIN INHERIT;',
  'CREATE ROLE ' + ownerB + ' NOLOGIN NOINHERIT;',
  'CREATE ROLE ' + ownerEmpty + ' NOLOGIN INHERIT;',
  'CREATE ROLE ' + parent + ' NOLOGIN INHERIT;',
  'CREATE ROLE ' + transitiveRole + ' NOLOGIN INHERIT;',
  'CREATE ROLE ' + unexpected + ' NOLOGIN BYPASSRLS;',
  'GRANT CREATE ON SCHEMA public TO ' + ownerA + ', ' + ownerB + ', ' + ownerEmpty + ';',
  'GRANT ' + parent + ' TO ' + ownerA + ' WITH INHERIT TRUE, SET TRUE;',
  'GRANT ' + transitiveRole + ' TO ' + parent + ' WITH INHERIT FALSE, SET TRUE;',
  'GRANT ' + unexpected + ' TO ' + ownerB + ' WITH INHERIT FALSE, SET TRUE;',
].join('\n'));

const ownerFor = (index) => index === 1 ? ownerEmpty
  : index === signatures.length - 1 ? ownerB : ownerA;
for (const [index, signature] of signatures.entries()) {
  psql('CREATE FUNCTION ' + signature + ' RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN RETURN; END; $$;');
  psql('ALTER FUNCTION ' + signature + ' OWNER TO ' + ownerFor(index) + ';');
}
psql('REVOKE ALL ON FUNCTION ' + signatures[1] + ' FROM PUBLIC;');

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
  assert.equal(r.catalog_identity_signature.replace(/,\s*/g, ','), r.expected_identity_signature);
  for (const field of ['owner_is_superuser', 'owner_role_inherits_memberships', 'owner_can_create_roles',
    'owner_can_create_databases', 'owner_can_login', 'owner_can_replicate', 'owner_bypasses_rls']) {
    assert.notEqual(r[field], null, 'Missing owner attribute: ' + field);
  }
}
const bySignature = new Map(inventory.map((r) => [r.expected_identity_signature, r]));
assert.equal(bySignature.get(signatures[0]).explicit_function_acl, null, 'Default ACL should leave proacl NULL');
assert.match(bySignature.get(signatures[0]).effective_defaulted_function_acl, /=X\//, 'Default ACL must include PUBLIC EXECUTE');
assert.notEqual(bySignature.get(signatures[1]).explicit_function_acl, null, 'REVOKE must materialize an explicit ACL');
assert.doesNotMatch(bySignature.get(signatures[1]).effective_defaulted_function_acl, /,=X\//, 'Explicit ACL must preserve revoked PUBLIC EXECUTE');
console.log('Query 8A: exact signatures, SECURITY DEFINER, owners, role attributes, explicit/default ACLs PASS');

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

const transitive = path(ownerA, transitiveRole);
assert.ok(transitive);
assert.deepEqual(transitive.membership_edge_inherit_options, [true, false]);
assert.deepEqual(transitive.membership_edge_set_options, [true, true]);
assert.equal(transitive.owner_is_member, true);
assert.equal(transitive.owner_inherits_privileges, false);
assert.equal(transitive.owner_can_set_role, true);

const unexpectedPath = path(ownerB, unexpected);
assert.ok(unexpectedPath, 'Unexpected membership must remain visible for review');
assert.equal(unexpectedPath.owner_inherits_privileges, false);
assert.equal(unexpectedPath.owner_can_set_role, true);
assert.equal(unexpectedPath.granted_role_bypasses_rls, true);
assert.equal(memberships.some((r) => r.function_owner === ownerEmpty), false,
  'Owner without memberships must produce no rows');
console.log('Query 8B: direct/transitive memberships, INHERIT, SET, effective privileges and unexpected membership PASS');

for (const signature of signatures) psql('DROP FUNCTION ' + signature + ';');
psql([
  'REVOKE ' + parent + ' FROM ' + ownerA + ';',
  'REVOKE ' + transitiveRole + ' FROM ' + parent + ';',
  'REVOKE ' + unexpected + ' FROM ' + ownerB + ';',
  'REVOKE CREATE ON SCHEMA public FROM ' + ownerA + ', ' + ownerB + ', ' + ownerEmpty + ';',
  'DROP ROLE ' + [ownerA, ownerB, ownerEmpty, parent, transitiveRole, unexpected].join(', ') + ';',
].join('\n'));
console.log('Disposable PostgreSQL 16 SECURITY DEFINER ownership audit behavior: PASS');
