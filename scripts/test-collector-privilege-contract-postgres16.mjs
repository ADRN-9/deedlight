import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { validateCollectorPrivilegeEvidence } from "./reconcile-migration-evidence.mjs";

const evidence = JSON.parse(readFileSync(0, "utf8"));
assert.ok(Array.isArray(evidence.inventoryObjects), "PostgreSQL privilege evidence lacks its inventory");
assert.ok(evidence.databaseAuthority && typeof evidence.databaseAuthority === "object",
  "PostgreSQL privilege evidence lacks database authority");
const problems = validateCollectorPrivilegeEvidence(evidence.databaseAuthority, evidence.inventoryObjects);
if (problems.length) {
  console.error(JSON.stringify({
    problems,
    schemaPrivileges: evidence.databaseAuthority.schemaPrivileges,
    inventoryObjects: evidence.inventoryObjects,
    objectPrivileges: evidence.databaseAuthority.objectPrivileges,
    columnPrivileges: evidence.databaseAuthority.columnPrivileges.filter((row) => row.privileges.length > 0),
  }, null, 2));
}
assert.deepEqual(problems, [], "actual PostgreSQL privileges violate the approved collector contract");

const db = evidence.databaseAuthority;
const appSchemas = db.schemaPrivileges.filter((row) => row.scope === "application_data");
const historySchema = db.schemaPrivileges.find((row) => row.schema === "supabase_migrations");
const appObjects = db.objectPrivileges.filter((row) => row.scope === "application_data");
const appColumns = db.columnPrivileges.filter((row) => row.scope === "application_data");
const historyColumns = db.columnPrivileges.filter((row) => row.scope === "migration_history");
const historyTable = db.objectPrivileges.find((row) => row.identity === "supabase_migrations.schema_migrations");
assert.ok(appSchemas.length > 0, "fixture must include an application schema");
assert.ok(appSchemas.every((row) => row.privileges.length === 0),
  "collector unexpectedly has effective application-schema privileges");
assert.deepEqual(historySchema?.privileges, ["USAGE"]);
assert.ok(appObjects.length > 0, "fixture must include application objects");
assert.ok(appObjects.every((row) => row.privileges.length === 0),
  "collector unexpectedly has effective application-object privileges");
assert.ok(Array.isArray(appColumns) && appColumns.length > 0, "fixture must include application columns");
assert.ok(appColumns.every((row) => row.privileges.length === 0),
  "collector unexpectedly has effective application-column privileges");
assert.ok(historyColumns.length > 0 && historyColumns.every((row) => row.privileges.length === 1 && row.privileges[0] === "SELECT"),
  "migration-history columns must be readable only through the approved history scope");
assert.deepEqual(historyTable?.privileges, ["SELECT"]);

// Exercise the same analyzer contract against adversarial mutations of real PostgreSQL-derived evidence.
const rejects = (label, mutate) => {
  const altered = structuredClone(db);
  mutate(altered);
  const violations = validateCollectorPrivilegeEvidence(altered, evidence.inventoryObjects);
  assert.ok(violations.length > 0, label + " must fail the collector-to-analyzer contract");
};
rejects("application-schema USAGE", (authority) => {
  authority.schemaPrivileges.find((row) => row.scope === "application_data").privileges.push("USAGE");
});
rejects("application-schema CREATE", (authority) => {
  authority.schemaPrivileges.find((row) => row.scope === "application_data").privileges.push("CREATE");
});
rejects("application-table SELECT", (authority) => {
  authority.objectPrivileges.find((row) => row.scope === "application_data" && row.kind === "tables").privileges.push("SELECT");
});
rejects("application-sequence USAGE", (authority) => {
  authority.objectPrivileges.find((row) => row.scope === "application_data" && row.kind === "sequences").privileges.push("USAGE");
});
rejects("application-routine EXECUTE", (authority) => {
  authority.objectPrivileges.find((row) => row.scope === "application_data" && row.kind === "routines").privileges.push("EXECUTE");
});
rejects("application-column SELECT", (authority) => {
  authority.columnPrivileges.find((row) => row.scope === "application_data").privileges.push("SELECT");
});
rejects("unexpected database TEMPORARY", (authority) => authority.databasePrivileges.push("TEMPORARY"));
rejects("missing application column evidence", (authority) => {
  authority.columnPrivileges.pop();
});
rejects("duplicate object evidence", (authority) => {
  authority.objectPrivileges.push(structuredClone(authority.objectPrivileges[0]));
});
rejects("incorrect history scope", (authority) => {
  authority.schemaPrivileges.find((row) => row.schema === "supabase_migrations").scope = "application_data";
});
console.log("PASS: PostgreSQL-derived collector authority matches catalog_only_v1; application schemas/objects remain inaccessible");
console.log("PASS: analyzer rejects application grants, missing/duplicate evidence and unauthorized privilege scope");
