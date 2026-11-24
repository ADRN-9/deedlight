import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, randomBytes, sign } from "node:crypto";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { EXPECTED_SIGNATURES } from "./verify-production-function-owner-manifest.mjs";
import { canonicalJson, verifyProductionOwnerApprovalBundle } from "./verify-production-owner-approval-bundle.mjs";

const PROJECT = "xaipiovflxomcbfwtwmu";
const AS_OF = "2026-11-24T00:10:00.000Z";
const hash = (value) => createHash("sha256").update(value).digest("hex");
const attrs = () => ({ rolsuper:false, rolinherit:true, rolcreaterole:false, rolcreatedb:false,
  rolcanlogin:false, rolreplication:false, rolbypassrls:false });
const canonicalPath = (pathValue) => ({
  roles:pathValue.roles, inheritOptions:pathValue.inheritOptions, setOptions:pathValue.setOptions,
  roleAttributes:pathValue.roleAttributes, effective:pathValue.effective,
});
const writeCanonical = (root, name, value) => {
  writeFileSync(path.join(root,name), canonicalJson(value), {mode:0o600});
  return hash(readFileSync(path.join(root,name)));
};
const writeBytes = (root,name,bytes) => {
  writeFileSync(path.join(root,name),bytes,{mode:0o600});
  return hash(readFileSync(path.join(root,name)));
};

function fixture({ withPath = false, intermediateAttribute = null } = {}) {
  const root = mkdtempSync(path.join(os.tmpdir(),"deedlight-owner-approval-"));
  mkdirSync(path.join(root,"evidence"));
  mkdirSync(path.join(root,"sql"));
  const dba = generateKeyPairSync("ed25519");
  const security = generateKeyPairSync("ed25519");
  const ownerAttributes = attrs();
  const parentAttributes = {role:"fixture_parent",...attrs()};
  if (intermediateAttribute) parentAttributes[intermediateAttribute] = true;
  const pathValue = {
    roles:["fixture_owner_only","fixture_parent"], inheritOptions:[true], setOptions:[true],
    roleAttributes:[{role:"fixture_owner_only",...ownerAttributes},parentAttributes],
    effective:{member:true,inheritsPrivileges:true,canSetRole:true},
  };
  const query8aRows = EXPECTED_SIGNATURES.map((expected_identity_signature) => ({
    expected_identity_signature, inventory_status:"PRESENT", security_definer:true,
    function_owner:"fixture_owner_only", owner_is_superuser:ownerAttributes.rolsuper,
    owner_role_inherits_memberships:ownerAttributes.rolinherit,
    owner_can_create_roles:ownerAttributes.rolcreaterole,
    owner_can_create_databases:ownerAttributes.rolcreatedb,
    owner_can_login:ownerAttributes.rolcanlogin,
    owner_can_replicate:ownerAttributes.rolreplication,
    owner_bypasses_rls:ownerAttributes.rolbypassrls,
  }));
  const query8bRows = withPath ? [{
    function_owner:"fixture_owner_only", membership_path:pathValue.roles,
    membership_path_role_attributes:pathValue.roleAttributes,
    membership_edge_inherit_options:pathValue.inheritOptions,
    membership_edge_set_options:pathValue.setOptions,
    owner_is_member:true, owner_inherits_privileges:true, owner_can_set_role:true,
  }] : [];
  const q8aSql = Buffer.from(EXPECTED_SIGNATURES.join("\n") + "\nSELECT /* fixture Query 8A */ 1;\n");
  const q8bSql = Buffer.from("WITH RECURSIVE membership_walk AS (SELECT 1) SELECT pg_auth_members, pg_has_role, membership_path_role_attributes /* fixture Query 8B */;\n");
  const q8aResult = Buffer.from(canonicalJson(query8aRows));
  const q8bResult = Buffer.from(canonicalJson(query8bRows));
  const files = {
    "sql/query-8a.sql":writeBytes(root,"sql/query-8a.sql",q8aSql),
    "sql/query-8b.sql":writeBytes(root,"sql/query-8b.sql",q8bSql),
    "evidence/query-8a.json":writeBytes(root,"evidence/query-8a.json",q8aResult),
    "evidence/query-8b.json":writeBytes(root,"evidence/query-8b.json",q8bResult),
  };
  const q8a = {
    queryId:"8A", projectRef:PROJECT, querySucceeded:true, complete:true, truncated:false,
    transactionReadOnly:true, roleReadOnly:true, executionPrincipal:"deedlight_audit_reader",
    collectorIdentity:"fixture-collector", executionId:"fixture-execution-8a", queryVersion:"fixture-query-8a-v1",
    executedAt:"2026-11-24T00:00:00.000Z", serverVersionNum:160004, rowCount:18,
    queryPath:"sql/query-8a.sql", querySha256:files["sql/query-8a.sql"],
    artifactPath:"evidence/query-8a.json", sha256:files["evidence/query-8a.json"],
  };
  const q8b = {
    queryId:"8B", projectRef:PROJECT, querySucceeded:true, complete:true, truncated:false,
    transactionReadOnly:true, roleReadOnly:true, executionPrincipal:"deedlight_audit_reader",
    collectorIdentity:"fixture-collector", executionId:"fixture-execution-8b", queryVersion:"fixture-query-8b-v1",
    executedAt:"2026-11-24T00:00:01.000Z", serverVersionNum:160004, rowCount:query8bRows.length,
    queryPath:"sql/query-8b.sql", querySha256:files["sql/query-8b.sql"],
    artifactPath:"evidence/query-8b.json", sha256:files["evidence/query-8b.json"],
    queriedOwnerRoles:["fixture_owner_only"], distinctOwnerCount:1,
    zeroRowsAttestation:query8bRows.length === 0 ? {
      successful:true,rowCount:0,allOwnersQueried:true,executionId:"fixture-execution-8b",
      querySha256:files["sql/query-8b.sql"],resultSha256:files["evidence/query-8b.json"],
      collectorIdentity:"fixture-collector",attestedAt:"2026-11-24T00:00:02.000Z",
      reason:"Successful complete Query 8B returned no membership paths for the complete owner inventory",
    } : null,
  };
  const manifest = {
    schemaVersion:1, projectRef:PROJECT, policyVersion:"deedlight-owner-policy-fixture-v1",
    evidence:{query8a:q8a,query8b:q8b},
    functions:EXPECTED_SIGNATURES.map((identitySignature)=>({
      identitySignature,expectedOwnerRole:"fixture_owner_only",securityDefiner:true,
    })),
    owners:[{
      role:"fixture_owner_only",attributes:ownerAttributes,
      membershipGraph:{complete:true,paths:withPath?[pathValue]:[]},
    }],
  };
  const manifestSha256 = hash(Buffer.from(canonicalJson(manifest)));
  writeCanonical(root,"manifest.json",manifest);
  const approvals = [];
  const signApproval = (payload, privateKey) => ({
    payload, signature:sign(null,Buffer.from(canonicalJson(payload)),privateKey).toString("base64"),
  });
  const add = (scope,subject,ownerRole,approvedValue,privateKey,identityId,approverRole,index) => {
    const payload = {
      approvalId:"fixture-approval-"+String(index).padStart(3,"0"),
      nonce:randomBytes(16).toString("hex"),
      scope,subject,ownerRole,projectRef:PROJECT,policyVersion:manifest.policyVersion,
      manifestSha256,query8aSha256:q8a.sha256,query8bSha256:q8b.sha256,
      approvedValueSha256:hash(Buffer.from(canonicalJson(approvedValue))),
      approverIdentity:identityId,approverRole,keyId:identityId+"-key",
      approved:true,approvedAt:"2026-11-24T00:01:00.000Z",expiresAt:"2026-11-24T00:30:00.000Z",
    };
    approvals.push(signApproval(payload,privateKey));
  };
  let index=0;
  for (const identitySignature of EXPECTED_SIGNATURES) {
    const approvedValue={identitySignature,expectedOwnerRole:"fixture_owner_only",securityDefiner:true};
    add("function_owner",identitySignature,"fixture_owner_only",approvedValue,dba.privateKey,"fixture-dba","production_dba",++index);
    add("function_owner",identitySignature,"fixture_owner_only",approvedValue,security.privateKey,"fixture-security","security",++index);
  }
  for (const [scope,approvedValue] of [
    ["owner_attributes",ownerAttributes],
    ["membership_graph",{complete:true,paths:manifest.owners[0].membershipGraph.paths.map((p)=>JSON.stringify(canonicalPath(p))).sort()}],
  ]) {
    add(scope,"fixture_owner_only","fixture_owner_only",approvedValue,dba.privateKey,"fixture-dba","production_dba",++index);
    add(scope,"fixture_owner_only","fixture_owner_only",approvedValue,security.privateKey,"fixture-security","security",++index);
  }
  const approvalDocument = {schemaVersion:1,projectRef:PROJECT,policyVersion:manifest.policyVersion,approvals};
  const approvalHash = writeCanonical(root,"approvals.json",approvalDocument);
  const trust = {
    schemaVersion:1,purpose:"deedlight-production-owner-approval-trust-root",
    keys:[
      {keyId:"fixture-dba-key",identityId:"fixture-dba",algorithm:"Ed25519",active:true,
        publicKeyPem:dba.publicKey.export({type:"spki",format:"pem"}),
        validFrom:"2026-01-01T00:00:00.000Z",validUntil:"2027-01-01T00:00:00.000Z"},
      {keyId:"fixture-security-key",identityId:"fixture-security",algorithm:"Ed25519",active:true,
        publicKeyPem:security.publicKey.export({type:"spki",format:"pem"}),
        validFrom:"2026-01-01T00:00:00.000Z",validUntil:"2027-01-01T00:00:00.000Z"},
    ],
    identities:[
      {identityId:"fixture-dba",active:true,roles:["production_dba"]},
      {identityId:"fixture-security",active:true,roles:["security"]},
    ],
    collectors:[{identityId:"fixture-collector",active:true}],
    revokedKeyIds:[],revokedApprovalIds:[],consumedApprovalIds:[],
    artifacts:{...files,"approvals.json":approvalHash},
  };
  writeCanonical(root,"trust.json",trust);
  return {root,manifest,approvalDocument,trust,dba,security,signApproval,asOf:AS_OF};
}
function cleanup(f) { rmSync(f.root,{recursive:true,force:true}); }
function saveApprovalDocument(f) {
  const approvalHash=writeCanonical(f.root,"approvals.json",f.approvalDocument);
  f.trust.artifacts["approvals.json"]=approvalHash;
  writeCanonical(f.root,"trust.json",f.trust);
}
function saveManifest(f) { writeCanonical(f.root,"manifest.json",f.manifest); }
function resignEnvelope(f,index) {
  const envelope=f.approvalDocument.approvals[index];
  const key=envelope.payload.approverIdentity==="fixture-dba"?f.dba.privateKey:f.security.privateKey;
  envelope.signature=sign(null,Buffer.from(canonicalJson(envelope.payload)),key).toString("base64");
  saveApprovalDocument(f);
}
function run(f, overrides={}) {
  return verifyProductionOwnerApprovalBundle({
    rootDir:f.root,manifestPath:"manifest.json",approvalsPath:"approvals.json",trustPath:"trust.json",
    asOf:f.asOf,...overrides,
  });
}

test("accepts a signed fixture-only bundle with authenticated identities and successful zero-row Query 8B",()=>{
  const f=fixture();
  try {
    const result=run(f);
    assert.equal(result.valid,true);
    assert.equal(result.functionCount,18);
    assert.equal(result.membershipPathCount,0);
    assert.equal(result.approvalCount,40);
  } finally { cleanup(f); }
});

test("accepts actual Query 8B bytes and a complete transitive membership path",()=>{
  const f=fixture({withPath:true});
  try {
    const result=run(f);
    assert.equal(result.membershipPathCount,1);
  } finally { cleanup(f); }
});

test("rejects manifest tampering and cross-manifest approval replay",()=>{
  const f=fixture();
  try {
    f.manifest.functions[0].expectedOwnerRole="substituted_role";
    saveManifest(f);
    assert.throws(()=>run(f),/manifest digest/);
  } finally { cleanup(f); }
});

test("rejects approval artifact tampering against the trusted recorded hash",()=>{
  const f=fixture();
  try {
    f.approvalDocument.approvals[0].payload.approved=false;
    writeCanonical(f.root,"approvals.json",f.approvalDocument);
    assert.throws(()=>run(f),/trusted artifact hash/);
  } finally { cleanup(f); }
});

test("rejects Query 8A evidence-byte substitution",()=>{
  const f=fixture();
  try {
    writeCanonical(f.root,"evidence/query-8a.json",[]);
    assert.throws(()=>run(f),/trusted artifact hash/);
  } finally { cleanup(f); }
});

test("rejects Query 8B SQL tampering",()=>{
  const f=fixture();
  try {
    writeFileSync(path.join(f.root,"sql/query-8b.sql"),"SELECT 1;\\n");
    assert.throws(()=>run(f),/trusted artifact hash/);
  } finally { cleanup(f); }
});

test("rejects individual approval policy-version substitution even with a valid signer",()=>{
  const f=fixture();
  try {
    f.approvalDocument.approvals[0].payload.policyVersion="older-policy";
    resignEnvelope(f,0);
    assert.throws(()=>run(f),/individual approval policy-version binding mismatch/);
  } finally { cleanup(f); }
});

test("rejects invalid approval signatures and untrusted approver roles",()=>{
  const f=fixture();
  try {
    const signature=f.approvalDocument.approvals[0].signature;
    f.approvalDocument.approvals[0].signature=(signature[0]==="A"?"B":"A")+signature.slice(1);
    saveApprovalDocument(f);
    assert.throws(()=>run(f),/signature verification failed/);
  } finally { cleanup(f); }
  const g=fixture();
  try {
    g.trust.identities.find((x)=>x.identityId==="fixture-security").roles=[];
    writeCanonical(g.root,"trust.json",g.trust);
    assert.throws(()=>run(g),/not trusted for the asserted role/);
  } finally { cleanup(g); }
});

test("rejects expired, revoked and not-yet-valid approvals",()=>{
  const f=fixture();
  try { assert.throws(()=>run(f,{asOf:"2026-11-25T00:00:00.000Z"}),/expired/); }
  finally { cleanup(f); }
  const g=fixture();
  try {
    g.trust.revokedApprovalIds.push(g.approvalDocument.approvals[0].payload.approvalId);
    writeCanonical(g.root,"trust.json",g.trust);
    assert.throws(()=>run(g),/revoked/);
  } finally { cleanup(g); }
  const h=fixture();
  try {
    h.approvalDocument.approvals[0].payload.approvedAt="2026-11-24T00:20:00.000Z";
    resignEnvelope(h,0);
    assert.throws(()=>run(h),/not yet valid/);
  } finally { cleanup(h); }
});

test("fails closed when trusted keys are absent or the approval mechanism is unsupported",()=>{
  const f=fixture();
  try {
    f.trust.keys=[];
    writeCanonical(f.root,"trust.json",f.trust);
    assert.throws(()=>run(f),/no active supported trusted approval keys/);
  } finally { cleanup(f); }
  const g=fixture();
  try {
    g.trust.keys[0].algorithm="RSA-PSS";
    writeCanonical(g.root,"trust.json",g.trust);
    assert.throws(()=>run(g),/no active supported trusted approval keys/);
  } finally { cleanup(g); }
});

test("rejects missing evidence provenance, incomplete execution and non-read-only execution",()=>{
  const f=fixture();
  try {
    f.manifest.evidence.query8a.queryVersion="";
    saveManifest(f);
    assert.throws(()=>run(f),/queryVersion is required/);
  } finally { cleanup(f); }
  const g=fixture();
  try {
    g.manifest.evidence.query8b.truncated=true;
    saveManifest(g);
    assert.throws(()=>run(g),/successful, complete, untruncated/);
  } finally { cleanup(g); }
  const h=fixture();
  try {
    h.manifest.evidence.query8a.transactionReadOnly=false;
    saveManifest(h);
    assert.throws(()=>run(h),/successful, complete, untruncated/);
  } finally { cleanup(h); }
});

test("requires a successful zero-row Query 8B attestation bound to actual result bytes",()=>{
  const f=fixture();
  try {
    f.manifest.evidence.query8b.zeroRowsAttestation=null;
    saveManifest(f);
    assert.throws(()=>run(f),/explicit successful\/all-owners\/zero-row attestation/);
  } finally { cleanup(f); }
  const g=fixture();
  try {
    g.manifest.evidence.query8b.zeroRowsAttestation.resultSha256="0".repeat(64);
    saveManifest(g);
    assert.throws(()=>run(g),/not bound to the actual execution/);
  } finally { cleanup(g); }
});

for (const attribute of ["rolsuper","rolcreaterole","rolcreatedb","rolreplication","rolbypassrls"]) {
  test("rejects privileged intermediate membership attribute " + attribute,()=>{
    const f=fixture({withPath:true,intermediateAttribute:attribute});
    try {
      assert.throws(()=>run(f),/privileged role attribute/);
    } finally { cleanup(f); }
  });
}

test("rejects duplicate approval replay identifiers",()=>{
  const f=fixture();
  try {
    f.approvalDocument.approvals[1]=structuredClone(f.approvalDocument.approvals[0]);
    saveApprovalDocument(f);
    assert.throws(()=>run(f),/approval replay\/duplicate approvalId/);
  } finally { cleanup(f); }
});

test("rejects untrusted paths and symbolic-link artifact substitution",()=>{
  const f=fixture();
  try {
    assert.throws(()=>verifyProductionOwnerApprovalBundle({
      rootDir:f.root,manifestPath:"../outside.json",approvalsPath:"approvals.json",trustPath:"trust.json",asOf:f.asOf,
    }),/normalized relative path/);
  } finally { cleanup(f); }
});


test("rejects approval identifiers already recorded as consumed by the trusted authority",()=>{
  const f=fixture();
  try {
    f.trust.consumedApprovalIds.push(f.approvalDocument.approvals[0].payload.approvalId);
    writeCanonical(f.root,"trust.json",f.trust);
    assert.throws(()=>run(f),/already been consumed/);
  } finally { cleanup(f); }
});
