import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { EXPECTED_SIGNATURES, validateProductionOwnerManifest } from "./verify-production-function-owner-manifest.mjs";

const projectRef = "xaipiovflxomcbfwtwmu";
const hash = (value) => createHash("sha256").update(value).digest("hex");
const canonicalize = (value) => Array.isArray(value) ? value.map(canonicalize)
  : value && typeof value === "object" ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])])) : value;
const digest = (value) => hash(JSON.stringify(canonicalize(value)));
const attrs = () => ({ rolsuper:false, rolinherit:true, rolcreaterole:false, rolcreatedb:false,
  rolcanlogin:false, rolreplication:false, rolbypassrls:false });

function fixture() {
  const q8a = hash("fixture-query-8a");
  const q8b = hash("fixture-query-8b");
  const functions = EXPECTED_SIGNATURES.map((identitySignature) => ({
    identitySignature, expectedOwnerRole:"fixture_owner_only", securityDefiner:true,
  }));
  const manifest = {
    schemaVersion:1, projectRef, policyVersion:"fixture-only-v1",
    evidence:{
      query8a:{projectRef,sha256:q8a,ref:"fixture://query-8a/immutable",collectedAt:"2026-11-24T00:00:00Z",complete:true,rowCount:18},
      query8b:{projectRef,sha256:q8b,ref:"fixture://query-8b/immutable",collectedAt:"2026-11-24T00:00:01Z",complete:true,rowCount:0,ownersReconciled:true,distinctOwnerCount:1},
    },
    functions,
    owners:[{role:"fixture_owner_only",attributes:attrs(),membershipGraph:{complete:true,paths:[]}}],
  };
  const approvals=[];
  const add = (scope, subject, ownerRole, approvedValue) => {
    for (const [approverRole, approver] of [["production_dba","Fixture DBA"],["security","Fixture Security"]]) {
      approvals.push({scope,subject,ownerRole,projectRef,query8aSha256:q8a,query8bSha256:q8b,approvedValueSha256:digest(approvedValue),
        approverRole,approver,approved:true,approvedAt:"2026-11-24T00:01:00Z",
        recordRef:"fixture://approvals/"+approvals.length,recordSha256:hash("approval-"+approvals.length)});
    }
  };
  for (const identitySignature of EXPECTED_SIGNATURES) add("function_owner",identitySignature,"fixture_owner_only",
    {identitySignature,expectedOwnerRole:"fixture_owner_only",securityDefiner:true});
  add("owner_attributes","fixture_owner_only","fixture_owner_only",attrs());
  add("membership_graph","fixture_owner_only","fixture_owner_only",{complete:true,paths:[]});
  return {manifest,approvals:{schemaVersion:1,projectRef,policyVersion:"fixture-only-v1",approvals}};
}

test("accepts a complete, explicitly approved fixture-only manifest including a proven empty graph", () => {
  const {manifest,approvals}=fixture();
  assert.deepEqual(validateProductionOwnerManifest(manifest,approvals,projectRef),{
    valid:true,projectRef,policyVersion:"fixture-only-v1",functionCount:18,distinctOwnerCount:1,membershipPathCount:0,
  });
});

test("rejects missing manifest or approvals", () => {
  const {manifest,approvals}=fixture();
  assert.throws(() => validateProductionOwnerManifest(null,approvals,projectRef),/manifest must be an object/);
  approvals.approvals.pop();
  assert.throws(() => validateProductionOwnerManifest(manifest,approvals,projectRef),/exactly two approvals/);
});

test("rejects wrong Production target, partial Query 8A and unknown Query 8B graph", () => {
  const a=fixture();
  assert.throws(() => validateProductionOwnerManifest(a.manifest,a.approvals,"wrong-project"),/designated DeedLight Production project/);
  a.manifest.evidence.query8a.rowCount=17;
  assert.throws(() => validateProductionOwnerManifest(a.manifest,a.approvals,projectRef),/rowCount must equal 18/);
  const b=fixture(); b.manifest.evidence.query8b.complete=false;
  assert.throws(() => validateProductionOwnerManifest(b.manifest,b.approvals,projectRef),/complete=true/);
});

test("rejects duplicate, missing and unexpected function mappings", () => {
  const a=fixture(); a.manifest.functions[1]=structuredClone(a.manifest.functions[0]);
  assert.throws(() => validateProductionOwnerManifest(a.manifest,a.approvals,projectRef),/duplicate function signature/);
  const b=fixture(); b.manifest.functions.pop();
  assert.throws(() => validateProductionOwnerManifest(b.manifest,b.approvals,projectRef),/exactly 18/);
  const c=fixture(); c.manifest.functions[0].identitySignature="public.unexpected()";
  assert.throws(() => validateProductionOwnerManifest(c.manifest,c.approvals,projectRef),/unexpected function signature/);
});

test("rejects unapproved privileged owner attributes and missing membership completeness", () => {
  const a=fixture(); a.manifest.owners[0].attributes.rolbypassrls=true;
  assert.throws(() => validateProductionOwnerManifest(a.manifest,a.approvals,projectRef),/privileged role attribute/);
  const b=fixture(); b.manifest.owners[0].membershipGraph.complete=false;
  assert.throws(() => validateProductionOwnerManifest(b.manifest,b.approvals,projectRef),/membership graph must explicitly attest complete/);
});

test("rejects membership path ambiguity, incomplete edge options and row-count mismatch", () => {
  const a=fixture();
  a.manifest.owners[0].membershipGraph.paths=[{roles:["fixture_owner_only","fixture_parent"],
    inheritOptions:[true],setOptions:[true],roleAttributes:[attrs(),attrs()],
    effective:{member:true,inheritsPrivileges:true,canSetRole:true}}];
  a.manifest.evidence.query8b.rowCount=0;
  assert.throws(() => validateProductionOwnerManifest(a.manifest,a.approvals,projectRef),/rowCount does not equal/);
  a.manifest.evidence.query8b.rowCount=1;
  a.manifest.owners[0].membershipGraph.paths[0].setOptions=[];
  assert.throws(() => validateProductionOwnerManifest(a.manifest,a.approvals,projectRef),/setOptions/);
});

test("requires independent DBA and security approvals bound to both evidence hashes", () => {
  const a=fixture();
  a.approvals.approvals[0].query8aSha256="0".repeat(64);
  assert.throws(() => validateProductionOwnerManifest(a.manifest,a.approvals,projectRef),/not bound to the exact Production project and evidence hashes/);
  const b=fixture();
  b.approvals.approvals[1].approver="Fixture DBA";
  assert.throws(() => validateProductionOwnerManifest(b.manifest,b.approvals,projectRef),/distinct people/);
  const c=fixture();
  c.approvals.approvals[1].approved=false;
  assert.throws(() => validateProductionOwnerManifest(c.manifest,c.approvals,projectRef),/approved=true/);
});


test("accepts a complete transitive membership path with attributes for every node", () => {
  const {manifest,approvals}=fixture();
  const ownerAttrs={role:"fixture_owner_only",...attrs()};
  const parentAttrs={role:"fixture_parent",...attrs()};
  const path={roles:["fixture_owner_only","fixture_parent"],inheritOptions:[true],setOptions:[true],
    roleAttributes:[ownerAttrs,parentAttrs],effective:{member:true,inheritsPrivileges:true,canSetRole:true}};
  const canonicalPath=JSON.stringify({roles:path.roles,inheritOptions:path.inheritOptions,setOptions:path.setOptions,
    roleAttributes:path.roleAttributes,effective:path.effective});
  manifest.owners[0].membershipGraph.paths=[path];
  manifest.evidence.query8b.rowCount=1;
  const approvedDigest=digest({complete:true,paths:[canonicalPath]});
  for (const approval of approvals.approvals.filter((item)=>item.scope==="membership_graph")) {
    approval.approvedValueSha256=approvedDigest;
  }
  assert.equal(validateProductionOwnerManifest(manifest,approvals,projectRef).membershipPathCount,1);
  path.roleAttributes[1].role="fixture_other_role";
  assert.throws(()=>validateProductionOwnerManifest(manifest,approvals,projectRef),/role mismatch/);
});
