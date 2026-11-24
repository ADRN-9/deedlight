import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";

const auditPath = "docs/PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md";
const fixturePath = "scripts/test-ownership-audit-fixtures.sql";
const cleanupPath = "scripts/test-ownership-audit-fixtures-cleanup.sql";
const audit = readFileSync(auditPath, "utf8");

const signatures = [
  "public.is_admin()",
  "public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)",
  "public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)",
  "public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)",
  "public.record_delivery_provider_event(text,text,text,text,text)",
  "public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)",
  "public._record_delivery_provider_integrity_conflict(text,text,text,text,text,text,text,timestamptz,text,text,text,text,text,timestamptz,text,text,text)",
  "public._record_delivery_provider_lifecycle_event_pre037_impl(text,text,text,text,timestamptz,text,text,text,text)",
  "public._record_delivery_provider_suppression_event_pre037_impl(text,text,text,text,text,text,timestamptz,timestamptz,text)",
  "public._deny_delivery_provider_integrity_audit_mutation()",
  "public.admin_list_delivery_provider_integrity_conflicts(text,integer)",
  "public.admin_list_delivery_provider_integrity_evidence(bigint,integer)",
  "public.admin_list_delivery_provider_integrity_history(bigint,integer)",
  "public.admin_resolve_delivery_provider_integrity_conflict(bigint,text)",
  "public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamptz,bigint)",
  "public.admin_get_delivery_provider_integrity_conflict(bigint)",
  "public.admin_list_delivery_provider_integrity_evidence_page(bigint,integer,timestamptz,bigint)",
  "public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)",
];

function extractQuery(heading) {
  const headingIndex = audit.indexOf(heading);
  assert.notEqual(headingIndex, -1, `Missing audit heading: ${heading}`);
  const nextHeadingIndex = audit.indexOf("\n### ", headingIndex + heading.length);
  const section = audit.slice(headingIndex, nextHeadingIndex === -1 ? undefined : nextHeadingIndex);
  const blocks = [...section.matchAll(/```sql\s*\n([\s\S]*?)\n```/g)];
  assert.equal(blocks.length, 1, `${heading} must contain exactly one executable SQL fence`);
  return blocks[0][1].trim().replace(/;\s*$/, "");
}

const query8a = extractQuery("### Query 8A — exact SECURITY DEFINER ownership inventory (18 signatures)");
const query8b = extractQuery("### Query 8B — direct and transitive memberships of function owners");

for (const [name, query] of [["8A", query8a], ["8B", query8b]]) {
  for (const signature of signatures) {
    assert.equal(query.split(`('${signature}')`).length - 1, 1,
      `Query ${name} must include exact signature once: ${signature}`);
  }
}

function psql(sql, { json = false } = {}) {
  const statement = json
    ? `SELECT COALESCE(json_agg(row_to_json(a)), '[]'::json) FROM (${sql}) AS a`
    : sql;
  const result = spawnSync("psql", ["-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-c", statement], {
    encoding: "utf8",
    env: process.env,
    timeout: 30000,
  });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `psql failed: ${result.stderr}`);
  return json ? JSON.parse(result.stdout.trim() || "[]") : result.stdout.trim();
}

function run8a() {
  return psql(query8a, { json: true });
}

function run8b() {
  return psql(query8b, { json: true });
}

function assertCompleteOwnership(rows) {
  assert.equal(rows.length, 18, "Ownership inventory must return all 18 expected signatures");
  for (const row of rows) {
    assert.equal(row.inventory_status, "PRESENT", `Unexpected inventory status: ${row.expected_identity_signature}`);
    assert.equal(row.security_definer, true, `SECURITY DEFINER missing: ${row.expected_identity_signature}`);
    assert.equal(row.function_owner, "deedlight_fixture_owner");
    assert.equal(row.owner_role_oid !== null, true);
    assert.equal(row.owner_role_inherits_memberships, true);
    assert.equal(row.owner_is_superuser, false);
    assert.equal(row.owner_can_create_roles, false);
    assert.equal(row.owner_bypasses_rls, false);
    assert.equal(row.function_settings_search_path?.some((v) => v.includes("search_path=pg_catalog")), true,
      `Restricted search_path missing: ${row.expected_identity_signature}`);
    assert.ok(row.effective_defaulted_function_acl, "Defaulted ACL must always resolve for present functions");
  }
  const explicit = rows.find((row) => row.expected_identity_signature === "public.is_admin()");
  assert.ok(explicit.explicit_function_acl, "Explicit ACL fixture must have proacl");
  assert.ok(explicit.explicit_function_acl.includes("deedlight_fixture_acl_reader"));
  assert.equal(rows.filter((row) => row.explicit_function_acl === null).length, 17,
    "The other 17 functions must exercise PostgreSQL's default ACL path");
}

function assertNoUnexpectedMemberships(rows, allowed) {
  const unexpected = rows.filter((row) => !allowed.has(row.granted_role));
  assert.equal(unexpected.length, 0, `Unexpected owner membership(s): ${unexpected.map((r) => r.granted_role).join(", ")}`);
}

function checkImpossibleOwnerState(rows) {
  for (const row of rows) {
    if (row.inventory_status !== "PRESENT" || !row.function_owner || row.owner_role_oid === null) {
      throw new Error(`Fail-closed ownership inventory: ${row.expected_identity_signature}`);
    }
  }
}

let setup = false;
try {
  const version = Number(psql("SHOW server_version_num"));
  assert.ok(version >= 160000, `PostgreSQL 16+ required, received server_version_num=${version}`);

  psql(readFileSync(fixturePath, "utf8"));
  setup = true;

  const baseline8a = run8a();
  assertCompleteOwnership(baseline8a);
  checkImpossibleOwnerState(baseline8a);

  const baseline8b = run8b();
  const direct = (role) => baseline8b.find((row) => row.granted_role === role);
  assert.equal(direct("deedlight_fixture_middle")?.depth, 1);
  assert.equal(direct("deedlight_fixture_middle")?.is_direct_membership, true);
  assert.equal(direct("deedlight_fixture_middle")?.owner_is_member, true);
  assert.equal(direct("deedlight_fixture_middle")?.owner_inherits_privileges, true);
  assert.equal(direct("deedlight_fixture_middle")?.owner_can_set_role, true);
  assert.deepEqual(direct("deedlight_fixture_middle")?.membership_edge_inherit_options, [true]);
  assert.deepEqual(direct("deedlight_fixture_middle")?.membership_edge_set_options, [true]);

  const recursiveSetOnly = direct("deedlight_fixture_privileged");
  assert.equal(recursiveSetOnly?.depth, 2);
  assert.equal(recursiveSetOnly?.is_direct_membership, false);
  assert.equal(recursiveSetOnly?.owner_is_member, true);
  assert.equal(recursiveSetOnly?.owner_inherits_privileges, false);
  assert.equal(recursiveSetOnly?.owner_can_set_role, true);
  assert.deepEqual(recursiveSetOnly?.membership_edge_inherit_options, [true, false]);
  assert.deepEqual(recursiveSetOnly?.membership_edge_set_options, [true, true]);
  assert.equal(recursiveSetOnly?.granted_role_can_create_roles, true);
  assert.equal(recursiveSetOnly?.granted_role_bypasses_rls, true);

  const inherited = direct("deedlight_fixture_inherited");
  assert.equal(inherited?.depth, 1);
  assert.equal(inherited?.owner_inherits_privileges, true);
  const setOnly = direct("deedlight_fixture_setonly");
  assert.equal(setOnly?.depth, 1);
  assert.equal(setOnly?.owner_inherits_privileges, false);
  assert.equal(setOnly?.owner_can_set_role, true);

  const allowed = new Set([
    "deedlight_fixture_middle",
    "deedlight_fixture_privileged",
    "deedlight_fixture_inherited",
    "deedlight_fixture_setonly",
  ]);
  assertNoUnexpectedMemberships(baseline8b, allowed);
  assert.throws(() => assertNoUnexpectedMemberships(baseline8b, new Set()), /Unexpected owner membership/);
  const assertNoPrivilegedMemberships = (rows) => {
    const privileged = rows.filter((row) => row.granted_role_is_superuser
      || row.granted_role_can_create_roles || row.granted_role_can_create_databases
      || row.granted_role_can_replicate || row.granted_role_bypasses_rls);
    assert.equal(privileged.length, 0, "Function owner reaches a privileged role");
  };
  assert.throws(() => assertNoPrivilegedMemberships(baseline8b), /Function owner reaches a privileged role/);

  // Removing one direct edge must also remove its recursive path.
  psql("REVOKE deedlight_fixture_middle FROM deedlight_fixture_owner");
  const afterRevoke = run8b();
  assert.equal(afterRevoke.some((row) => row.granted_role === "deedlight_fixture_middle"), false);
  assert.equal(afterRevoke.some((row) => row.granted_role === "deedlight_fixture_privileged"), false);

  psql("GRANT deedlight_fixture_middle TO deedlight_fixture_owner WITH INHERIT TRUE, SET TRUE");
  const afterGrant = run8b();
  assert.equal(afterGrant.some((row) => row.granted_role === "deedlight_fixture_privileged"), true);

  // A missing expected routine remains visible as a negative inventory row.
  psql("DROP FUNCTION public.is_admin()");
  const missing = run8a();
  assert.equal(missing.length, 18);
  assert.equal(missing.find((row) => row.expected_identity_signature === "public.is_admin()")?.inventory_status, "MISSING_FUNCTION");
  assert.equal(missing.filter((row) => row.inventory_status === "MISSING_FUNCTION").length, 1);

  // A missing owner role cannot be represented by a valid pg_proc ownership dependency.
  assert.throws(() => checkImpossibleOwnerState([{
    expected_identity_signature: "public.is_admin()",
    inventory_status: "MISSING_OWNER_ROLE",
    function_owner: null,
    owner_role_oid: null,
  }]), /Fail-closed ownership inventory/);
  assert.throws(() => checkImpossibleOwnerState([{
    expected_identity_signature: "public.is_admin()",
    inventory_status: "PRESENT",
    function_owner: null,
    owner_role_oid: null,
  }]), /Fail-closed ownership inventory/);

  console.log("PostgreSQL 16 Query 8A/8B execution against exact extracted audit SQL: PASS");
  console.log("18 exact signatures, SECURITY DEFINER, owner identity, search_path, explicit/default ACL: PASS");
  console.log("Direct/recursive memberships, INHERIT, SET ROLE, MEMBER, USAGE and privileged-role detection: PASS");
  console.log("Membership revoke/grant and missing-function negative fixtures: PASS");
  console.log("Unrepresentable missing-owner catalog state fail-closed assertion: PASS");
} finally {
  if (setup) psql(readFileSync(cleanupPath, "utf8"));
}
