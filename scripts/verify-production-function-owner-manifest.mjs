import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

export const EXPECTED_SIGNATURES = Object.freeze([
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
  "public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)"
]);
const ROLE_ATTRIBUTES = Object.freeze([
  "rolsuper", "rolinherit", "rolcreaterole", "rolcreatedb",
  "rolcanlogin", "rolreplication", "rolbypassrls",
]);
const APPROVER_ROLES = Object.freeze(["production_dba", "security"]);

function fail(message) {
  throw new Error("Production owner manifest rejected: " + message);
}
function object(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(label + " must be an object");
  return value;
}
function nonEmpty(value, label) {
  if (typeof value !== "string" || value.trim() === "") fail(label + " is required");
  return value.trim();
}
function sha256(value, label) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)) fail(label + " must be a lowercase SHA-256 digest");
}
function timestamp(value, label) {
  nonEmpty(value, label);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)
      || Number.isNaN(Date.parse(value))) fail(label + " must be an ISO-8601 timestamp with timezone");
}
function reference(value, label) {
  nonEmpty(value, label);
  if (!/^[a-z][a-z0-9+.-]*:\/\/\S+$/i.test(value)) fail(label + " must be an immutable URI reference");
}
function validateEvidence(record, label, projectRef, expectedRows) {
  object(record, label);
  if (record.projectRef !== projectRef) fail(label + " projectRef mismatch");
  sha256(record.sha256, label + ".sha256");
  reference(record.ref, label + ".ref");
  timestamp(record.collectedAt, label + ".collectedAt");
  if (record.complete !== true) fail(label + " must explicitly attest complete=true");
  if (!Number.isSafeInteger(record.rowCount) || record.rowCount < 0) fail(label + ".rowCount is invalid");
  if (expectedRows !== undefined && record.rowCount !== expectedRows) {
    fail(label + ".rowCount must equal " + expectedRows);
  }
}
function validateAttributes(attributes, label) {
  object(attributes, label);
  for (const key of ROLE_ATTRIBUTES) {
    if (typeof attributes[key] !== "boolean") fail(label + "." + key + " must be an explicit boolean");
  }
  if (attributes.rolsuper || attributes.rolcreaterole || attributes.rolcreatedb
      || attributes.rolreplication || attributes.rolbypassrls) {
    fail(label + " contains a privileged role attribute; explicit exception policy is not implemented");
  }
}
function canonicalPath(path, owner) {
  object(path, "membership path");
  if (!Array.isArray(path.roles) || path.roles.length < 2) fail("membership path roles must contain owner and at least one granted role");
  if (path.roles[0] !== owner) fail("membership path must begin with its function owner");
  for (const role of path.roles) nonEmpty(role, "membership path role");
  const edgeCount = path.roles.length - 1;
  for (const key of ["inheritOptions", "setOptions"]) {
    if (!Array.isArray(path[key]) || path[key].length !== edgeCount
        || path[key].some((value) => typeof value !== "boolean")) {
      fail("membership path " + key + " must explicitly describe every edge");
    }
  }
  if (!Array.isArray(path.roleAttributes) || path.roleAttributes.length !== path.roles.length) {
    fail("membership path roleAttributes must describe every role node");
  }
  path.roleAttributes.forEach((attrs, index) => {
    validateAttributes(attrs, "membership path roleAttributes[" + index + "]");
    if (attrs.role !== path.roles[index]) fail("membership path roleAttributes role mismatch at depth " + index);
  });
  object(path.effective, "membership path effective privileges");
  for (const key of ["member", "inheritsPrivileges", "canSetRole"]) {
    if (typeof path.effective[key] !== "boolean") fail("membership path effective." + key + " must be explicit");
  }
  return JSON.stringify({
    roles: path.roles,
    inheritOptions: path.inheritOptions,
    setOptions: path.setOptions,
    roleAttributes: path.roleAttributes,
    effective: path.effective,
  });
}
function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
  return value;
}
function valueDigest(value) {
  return createHash("sha256").update(JSON.stringify(canonicalize(value))).digest("hex");
}
function approvalsFor(approvals, scope, subject, ownerRole, approvedValueSha256, q8aHash, q8bHash, projectRef) {
  const matching = approvals.filter((item) => item.scope === scope && item.subject === subject
    && item.ownerRole === ownerRole);
  if (matching.length !== 2) fail(scope + " requires exactly two approvals for " + subject);
  const seenRoles = new Set();
  const seenPeople = new Set();
  for (const item of matching) {
    object(item, "approval record");
    if (item.projectRef !== projectRef || item.query8aSha256 !== q8aHash || item.query8bSha256 !== q8bHash
        || item.approvedValueSha256 !== approvedValueSha256) {
      fail(scope + " approval is not bound to the exact Production project and evidence hashes");
    }
    if (!APPROVER_ROLES.includes(item.approverRole) || seenRoles.has(item.approverRole)) {
      fail(scope + " requires one distinct DBA and one distinct security approver");
    }
    seenRoles.add(item.approverRole);
    const person = nonEmpty(item.approver, "approval approver");
    if (seenPeople.has(person)) fail("DBA and security approvals must be from distinct people");
    seenPeople.add(person);
    if (item.approved !== true) fail(scope + " approval must explicitly set approved=true");
    timestamp(item.approvedAt, "approval approvedAt");
    reference(item.recordRef, "approval recordRef");
    sha256(item.recordSha256, "approval recordSha256");
  }
  if (seenRoles.size !== 2) fail(scope + " approval roles incomplete");
}

export function validateProductionOwnerManifest(manifest, approvalsDocument, expectedProjectRef) {
  object(manifest, "manifest");
  object(approvalsDocument, "approvals");
  const projectRef = nonEmpty(expectedProjectRef, "expected Production project reference");
  if (projectRef !== "xaipiovflxomcbfwtwmu") fail("expected project reference is not the designated DeedLight Production project");
  if (manifest.schemaVersion !== 1 || approvalsDocument.schemaVersion !== 1) fail("unsupported manifest or approval schema version");
  if (manifest.projectRef !== projectRef || approvalsDocument.projectRef !== projectRef) fail("project identity mismatch");
  const version = nonEmpty(manifest.policyVersion, "policyVersion");
  if (approvalsDocument.policyVersion !== version) fail("approval policyVersion mismatch");

  object(manifest.evidence, "evidence");
  validateEvidence(manifest.evidence.query8a, "Query 8A evidence", projectRef, EXPECTED_SIGNATURES.length);
  validateEvidence(manifest.evidence.query8b, "Query 8B evidence", projectRef);
  if (manifest.evidence.query8b.ownersReconciled !== true) fail("Query 8B must explicitly reconcile every distinct Query 8A owner");
  if (!Number.isSafeInteger(manifest.evidence.query8b.distinctOwnerCount) || manifest.evidence.query8b.distinctOwnerCount < 1) fail("Query 8B distinctOwnerCount must be explicitly positive");
  const q8aHash = manifest.evidence.query8a.sha256;
  const q8bHash = manifest.evidence.query8b.sha256;
  if (!Array.isArray(approvalsDocument.approvals)) fail("approvals must be an explicit array");
  const approvalRefs = new Set();
  for (const approval of approvalsDocument.approvals) {
    object(approval, "approval record");
    reference(approval.recordRef, "approval recordRef");
    if (approvalRefs.has(approval.recordRef)) fail("duplicate approval recordRef");
    approvalRefs.add(approval.recordRef);
  }

  if (!Array.isArray(manifest.functions) || manifest.functions.length !== EXPECTED_SIGNATURES.length) {
    fail("manifest must contain exactly 18 function mappings");
  }
  const expected = new Set(EXPECTED_SIGNATURES);
  const functionOwners = new Map();
  for (const item of manifest.functions) {
    object(item, "function mapping");
    const signature = nonEmpty(item.identitySignature, "function identitySignature");
    if (!expected.has(signature)) fail("unexpected function signature: " + signature);
    if (functionOwners.has(signature)) fail("duplicate function signature: " + signature);
    if (item.securityDefiner !== true) fail("function must be explicitly SECURITY DEFINER: " + signature);
    const owner = nonEmpty(item.expectedOwnerRole, "expectedOwnerRole");
    functionOwners.set(signature, owner);
    approvalsFor(approvalsDocument.approvals, "function_owner", signature, owner,
      valueDigest({ identitySignature: signature, expectedOwnerRole: owner, securityDefiner: true }), q8aHash, q8bHash, projectRef);
  }
  for (const signature of EXPECTED_SIGNATURES) {
    if (!functionOwners.has(signature)) fail("missing exact function signature: " + signature);
  }

  if (!Array.isArray(manifest.owners)) fail("owners must be an explicit array; unknown is not an empty graph");
  const distinctOwners = [...new Set(functionOwners.values())].sort();
  const owners = new Map();
  let observedPathCount = 0;
  for (const owner of manifest.owners) {
    object(owner, "owner record");
    const role = nonEmpty(owner.role, "owner role");
    if (owners.has(role)) fail("duplicate owner record: " + role);
    validateAttributes(owner.attributes, "owner attributes for " + role);
    object(owner.membershipGraph, "membership graph for " + role);
    if (owner.membershipGraph.complete !== true) fail("membership graph must explicitly attest complete=true for " + role);
    if (!Array.isArray(owner.membershipGraph.paths)) fail("membership graph paths must be an explicit array for " + role);
    const paths = owner.membershipGraph.paths.map((path) => {
      const canonical = canonicalPath(path, role);
      if (JSON.stringify(canonicalize(path.roleAttributes[0])) !== JSON.stringify(canonicalize({ role, ...owner.attributes }))) {
        fail("membership path owner attributes disagree with Query 8A owner attributes for " + role);
      }
      const parsed = JSON.parse(canonical);
      if (new Set(parsed.roles).size !== parsed.roles.length) fail("membership path contains a cycle for " + role);
      return canonical;
    });
    if (new Set(paths).size !== paths.length) fail("duplicate membership path for " + role);
    observedPathCount += paths.length;
    owners.set(role, owner);
    approvalsFor(approvalsDocument.approvals, "owner_attributes", role, role,
      valueDigest(owner.attributes), q8aHash, q8bHash, projectRef);
    approvalsFor(approvalsDocument.approvals, "membership_graph", role, role,
      valueDigest({ complete: true, paths: [...paths].sort() }), q8aHash, q8bHash, projectRef);
  }
  if (manifest.evidence.query8b.distinctOwnerCount !== distinctOwners.length) fail("Query 8B distinctOwnerCount does not match the function-owner inventory");
  if (distinctOwners.length !== owners.size || distinctOwners.some((role) => !owners.has(role))) {
    fail("owner records must exactly equal the distinct owners in the 18 function mappings");
  }
  if (manifest.evidence.query8b.rowCount !== observedPathCount) {
    fail("Query 8B rowCount does not equal the complete membership path inventory; empty graph requires explicit zero-row evidence");
  }
  const expectedApprovalCount = EXPECTED_SIGNATURES.length * 2 + distinctOwners.length * 4;
  if (!Array.isArray(approvalsDocument.approvals) || approvalsDocument.approvals.length !== expectedApprovalCount) {
    fail("approval document contains missing, duplicate or unexpected approval records");
  }
  return { valid: true, projectRef, policyVersion: version, functionCount: EXPECTED_SIGNATURES.length,
    distinctOwnerCount: distinctOwners.length, membershipPathCount: observedPathCount };
}

if (process.argv[1] && import.meta.url === new URL("file://" + process.argv[1]).href) {
  const args = process.argv.slice(2);
  const value = (name) => {
    const index = args.indexOf(name);
    return index >= 0 ? args[index + 1] : undefined;
  };
  const manifestPath = value("--manifest");
  const approvalsPath = value("--approvals");
  const expectedProjectRef = value("--expected-project-ref");
  if (!manifestPath || !approvalsPath || !expectedProjectRef || args.length !== 6) {
    console.error("Usage: node scripts/verify-production-function-owner-manifest.mjs --manifest <protected-manifest.json> --approvals <protected-approvals.json> --expected-project-ref xaipiovflxomcbfwtwmu");
    process.exitCode = 2;
  } else {
    try {
      const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
      const approvals = JSON.parse(readFileSync(approvalsPath, "utf8"));
      const result = validateProductionOwnerManifest(manifest, approvals, expectedProjectRef);
      console.log("Production owner manifest structure and approval coverage PASS:", JSON.stringify(result));
    } catch (error) {
      console.error(error instanceof Error ? error.message : "Production owner manifest validation failed");
      process.exitCode = 1;
    }
  }
}
