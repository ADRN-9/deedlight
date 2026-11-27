import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { canonicalJson, INVENTORY_GIT_BLOB_SHA1, PROJECT_REF, RECEIPT_SCHEMA_GIT_BLOB_SHA1, RECEIPT_SCHEMA_SHA256, SQL_GIT_BLOB_SHA1, SQL_PATH, SQL_PROJECTIONS, SQL_SHA256, sha256, validateSqlOutput } from "./collect-production-migration-evidence.mjs";
import { gitBlobSha1 } from "./verify-migration-inventory-aggregate.mjs";
import { adaptCollectorEvidence } from "./adapt-production-migration-evidence.mjs";
const inventoryBytes=readFileSync(new URL("../supabase/migration-inventory.json",import.meta.url));
const schemaBytes=readFileSync(new URL("../schemas/production-migration-collection-receipt-v1.schema.json",import.meta.url));
const inventory=JSON.parse(inventoryBytes);
const cell=v=>{const s=String(v??"");return /[",\r\n]/.test(s)?'"'+s.replaceAll('"','""')+'"':s;};
const serialize=rows=>Buffer.from(rows.map(row=>row.map(cell).join(",")).join("\r\n")+"\r\n");
function fixtureCsv(history=[["202607210001","NULL","12"],["202607210002","\\N","13"],["202607220003","","14"]],historyStructure=[["1","version","text","t"],["2","name","text","f"],["3","statements","text[]","f"]]){
  const data=new Map(SQL_PROJECTIONS.map(p=>[p.id,[]]));
  data.set("identity_v1",[[PROJECT_REF,"a".repeat(40),"postgres","deedlight_catalog_auditor","deedlight_catalog_auditor","16.0","127.0.0.1","5432","2026-11-26T00:00:00.000Z","on"]]);
  data.set("relations_v1",[["public","profiles","r","postgres","p","f","f","1","id","uuid","t","",""]]);
  data.set("schema_acl_v1",[["public","postgres","deedlight_catalog_auditor","postgres","USAGE","f"]]);
  data.set("roles_v1",[["deedlight_catalog_auditor","t","f","f","f","f","f","f","-1",""]]);
  data.set("rls_policies_v1",[["public","profiles","profiles_select","PERMISSIVE","{authenticated}","SELECT","",""]]);
  data.set("migration_history_structure_v1",historyStructure);
  data.set("migration_history_v1",history);
  data.set("database_acl_v1",[["database_acl_v1","1","1","postgres","t","f","10","postgres","t","built_in_default","[]"]]);
  const rows=[];for(const p of SQL_PROJECTIONS)rows.push([...p.columns],...data.get(p.id));
  rows.push(["collector_transaction_closed"],["t"]);return serialize(rows);
}
function receiptFor(bytes){
  const v=validateSqlOutput(bytes);
  return {schemaVersion:1,kind:"deedlight-production-migration-collection",status:"UNSIGNED_NOT_ACCEPTED",projectRef:PROJECT_REF,
    endpoint:{hostname:"db."+PROJECT_REF+".supabase.co",port:5432,database:"postgres",tlsMode:"verify-full",tlsVerified:true,tlsHostnameVerified:true,tlsChainVerified:true,
      projectIdentityMethod:"independently-pinned-profile-and-project-specific-TLS-hostname",tlsRootCertificateSha256:"b".repeat(64),independentlyPinnedProfileSha256:"c".repeat(64)},
    source:{repositoryCommitSha:"a".repeat(40),migrationInventoryGitBlobSha1:INVENTORY_GIT_BLOB_SHA1,sqlBundlePath:SQL_PATH,sqlBundleGitBlobSha1:SQL_GIT_BLOB_SHA1,
      sqlBundleSha256:SQL_SHA256,receiptSchemaGitBlobSha1:RECEIPT_SCHEMA_GIT_BLOB_SHA1,receiptSchemaSha256:RECEIPT_SCHEMA_SHA256},
    execution:{collectorId:"deedlight-readonly-collector-v1",authenticatedPrincipal:"deedlight_catalog_auditor",expectedEffectivePrincipal:"deedlight_catalog_auditor",
      transactionIsolation:"repeatable read",readOnly:true,transactionRollbackVerified:true,startedAt:"2026-11-26T00:00:00.000Z",completedAt:"2026-11-26T00:00:01.000Z",
      outputFormat:"PostgreSQL psql CSV",canonicalization:"RFC4180 CSV parsed as ordered string-cell records; UTF-8 canonical JSON with sorted keys and preserved array order; SHA-256",
      resultRecordCount:v.resultRows.length,databaseAclV1RowCount:v.databaseAclRows,migrationHistoryRowCount:v.migrationHistoryRows.length,
      canonicalResultSha256:sha256(Buffer.from(canonicalJson(v.resultRows),"utf8")),evidenceFileSha256:sha256(bytes)},
    evidence:{file:"evidence.csv",mediaType:"text/csv",byteLength:bytes.length,sha256:sha256(bytes)},
    signing:{state:"NOT_SIGNED",keyId:null,signature:null,acceptance:"PROHIBITED_PENDING_INDEPENDENT_SIGNING_AND_VERIFICATION"}};
}
function mappingFixture(){
  const categories=["schema","privileges","ownership","routines","dataTransformations","backfills","dependencies","preconditions","postconditions"];
  return {schemaVersion:1,migrations:inventory.migrations.map(item=>{
    const effects=Object.fromEntries(categories.map(c=>[c,c==="schema"?[{kind:"tables",identity:"public.profiles",fingerprint:"d".repeat(64),description:"Test-only fixture effect, not Production evidence or approval."}]:[]]));
    const coverage=Object.fromEntries(categories.map(c=>[c,{disposition:effects[c].length?"effects":"none",rationale:"Test-only fixture rationale for adapter contract validation.",sourceRanges:[{startLine:1,endLine:1}]}]));
    return {path:item.path,blobSha1:item.blobSha1,effects,coverage};
  })};
}
function adapt(bytes=fixtureCsv(),mapping=mappingFixture()){
  const receipt=receiptFor(bytes);return {receipt,candidate:adaptCollectorEvidence({receipt,csv:bytes,inventoryBytes,schemaBytes,mapping})};
}
test("normalizes all 19 validated projections without crossing authentication boundary",()=>{
  const {candidate}=adapt();
  assert.equal(candidate.status,"UNSIGNED_NOT_ACCEPTED");assert.equal(candidate.acceptance,"NOT_ACCEPTED");
  assert.equal(candidate.evidence.schemaVersion,2);assert.equal(candidate.evidence.provenance.projectRef,PROJECT_REF);
  assert.equal(candidate.evidence.provenance.queryBundleSha256,SQL_SHA256);assert.equal(candidate.evidence.provenance.capturedAt,"2026-11-26T00:00:00.000Z");assert.equal(candidate.evidence.history.complete,true);
  assert.deepEqual(candidate.evidence.history.rows.map(r=>r.name),["NULL","\\N",null]);
  assert.equal(candidate.evidence.catalog.complete,false);assert.equal(candidate.projections.length,19);
  assert.deepEqual(candidate.projections.map(p=>p.id),SQL_PROJECTIONS.map(p=>p.id));
  assert.equal(candidate.databaseAuthorityCandidate.declaredContract,"catalog_only_v1");
  assert.equal(candidate.databaseAuthorityCandidate.authenticated,false);
  assert.equal(Object.hasOwn(candidate.evidence,"collectorAuthority"),false);
  assert.equal(Object.hasOwn(candidate.evidence,"externalExecutionProvenance"),false);
  assert.equal(candidate.evidence.mapping.migrations.length,40);assert.equal(candidate.receipt.status,"UNSIGNED_NOT_ACCEPTED");assert.equal(candidate.integrity.repositoryCommitSha,"a".repeat(40));
  assert.notEqual(candidate.integrity.csvSha256,candidate.integrity.canonicalResultSha256);
  assert.equal(candidate.integrity.receiptSchemaGitBlobSha1,RECEIPT_SCHEMA_GIT_BLOB_SHA1);
  assert.equal(candidate.integrity.receiptSchemaSha256,RECEIPT_SCHEMA_SHA256);
  assert.ok(candidate.blockers.length>=4);
});
test("does not invent a reviewed mapping or authenticated authority",()=>{
  const bytes=fixtureCsv(),receipt=receiptFor(bytes),candidate=adaptCollectorEvidence({receipt,csv:bytes,inventoryBytes,schemaBytes});
  assert.equal(Object.hasOwn(candidate.evidence,"mapping"),false);assert.ok(candidate.blockers.some(x=>x.includes("mapping")));
  assert.equal(Object.hasOwn(candidate.evidence,"collectorAuthority"),false);
  assert.equal(Object.hasOwn(candidate.evidence,"externalExecutionProvenance"),false);
});
test("literal NULL and literal backslash-N remain strings; empty CSV field is SQL NULL",()=>{
  const {candidate}=adapt(fixtureCsv([["202607210001","NULL","1"],["202607210002","\\N","2"],["202607220003","","3"]]));
  assert.deepEqual(candidate.evidence.history.rows,[
    {version:"202607210001",name:"NULL",recordedStatementCount:1},
    {version:"202607210002",name:"\\N",recordedStatementCount:2},
    {version:"202607220003",name:null,recordedStatementCount:3}]);
});
test("invalid statement counts fail closed",()=>{
  for(const n of ["NULL","\\N","-1","01","1.5","9007199254740992"])assert.throws(()=>adapt(fixtureCsv([["202607210001","valid_name",n]])),/MIGRATION_HISTORY_STATEMENT_COUNT_INVALID/);
});
test("missing, duplicated, reordered, unexpected and truncated projections fail closed",()=>{
  const base=fixtureCsv().toString("utf8"),lines=base.trimEnd().split("\r\n"),header=SQL_PROJECTIONS[4].columns.join(",");
  assert.throws(()=>adapt(Buffer.from(lines.filter(x=>x!==header).join("\r\n")+"\r\n")));
  assert.throws(()=>adapt(Buffer.from(base.replace(header+"\r\n",header+"\r\n"+header+"\r\n"))),/SQL_PROJECTION_DUPLICATED/);
  assert.throws(()=>adapt(Buffer.from(base.replace(SQL_PROJECTIONS[0].columns.join(","),SQL_PROJECTIONS[1].columns.join(",")))),/SQL_PROJECTION/);
  assert.throws(()=>adapt(Buffer.from(base.replace(SQL_PROJECTIONS[1].columns.join(","),"unexpected_header,other_header"))),/SQL_PROJECTION/);
  assert.throws(()=>adapt(Buffer.from(base.slice(0,-20))),/TRANSACTION_CLOSE_MARKER_MISSING|TRUNCATED/);
});
test("row-shape validators reject malformed relation, ACL and role values",()=>{
  const base=fixtureCsv().toString("utf8");
  assert.throws(()=>adapt(Buffer.from(base.replace("public,profiles,r,postgres,p,f,f,1,id,uuid,t,,","public,profiles,r,postgres,p,invalid,f,1,id,uuid,t,,"))),/RELATIONS_PROJECTION_ROW_INVALID/);
  assert.throws(()=>adapt(Buffer.from(base.replace("public,postgres,deedlight_catalog_auditor,postgres,USAGE,f","public,postgres,deedlight_catalog_auditor,postgres,USAGE,maybe"))),/ACL_PROJECTION_ROW_INVALID/);
  assert.throws(()=>adapt(Buffer.from(base.replace("deedlight_catalog_auditor,t,f,f,f,f,f,f,-1,","deedlight_catalog_auditor,t,f,f,f,f,f,x,-1,"))),/ROLES_PROJECTION_ROW_INVALID/);
});
test("receipt, SQL, inventory and receipt-schema fingerprints are independently pinned",()=>{
  const bytes=fixtureCsv(),receipt=receiptFor(bytes);
  for(const mutate of [r=>{r.source.sqlBundleGitBlobSha1="0".repeat(40);},r=>{r.source.sqlBundleSha256="0".repeat(64);},
    r=>{r.source.receiptSchemaGitBlobSha1="0".repeat(40);},r=>{r.source.receiptSchemaSha256="0".repeat(64);}]) {
    const changed=structuredClone(receipt);mutate(changed);assert.throws(()=>adaptCollectorEvidence({receipt:changed,csv:bytes,inventoryBytes,schemaBytes,mapping:mappingFixture()}));
  }
  const changedSchema=Buffer.from(schemaBytes);changedSchema[0]^=1;
  assert.throws(()=>adaptCollectorEvidence({receipt,csv:bytes,inventoryBytes,schemaBytes:changedSchema}),/RECEIPT_SCHEMA_(GIT_BLOB_SHA1|RAW_SHA256)_MISMATCH/);
  const changedInventory=Buffer.from(inventoryBytes);changedInventory[0]^=1;
  assert.throws(()=>adaptCollectorEvidence({receipt,csv:bytes,inventoryBytes:changedInventory,schemaBytes}),/MIGRATION_INVENTORY/);
  assert.equal(gitBlobSha1(inventoryBytes),INVENTORY_GIT_BLOB_SHA1);
});
test("migration mapping must cover exact 40 inventory entries without duplicates",()=>{
  const bytes=fixtureCsv(),receipt=receiptFor(bytes),mapping=mappingFixture();
  assert.equal(mapping.migrations.length,40);
  const duplicate=structuredClone(mapping);duplicate.migrations[1]=duplicate.migrations[0];
  assert.throws(()=>adaptCollectorEvidence({receipt,csv:bytes,inventoryBytes,schemaBytes,mapping:duplicate}),/MIGRATION_MAPPING/);
  const missing=structuredClone(mapping);missing.migrations.pop();
  assert.throws(()=>adaptCollectorEvidence({receipt,csv:bytes,inventoryBytes,schemaBytes,mapping:missing}),/MIGRATION_MAPPING/);
  const mismatch=structuredClone(mapping);mismatch.migrations[0].blobSha1="0".repeat(40);
  assert.throws(()=>adaptCollectorEvidence({receipt,csv:bytes,inventoryBytes,schemaBytes,mapping:mismatch}),/MIGRATION_MAPPING_SOURCE_MISMATCH/);
  const badKind=structuredClone(mapping);badKind.migrations[0].effects.schema[0].kind="routines";
  assert.throws(()=>adaptCollectorEvidence({receipt,csv:bytes,inventoryBytes,schemaBytes,mapping:badKind}),/MIGRATION_MAPPING_EFFECT_INVALID/);
  const duplicateEffect=structuredClone(mapping);duplicateEffect.migrations[0].effects.schema.push(structuredClone(duplicateEffect.migrations[0].effects.schema[0]));
  assert.throws(()=>adaptCollectorEvidence({receipt,csv:bytes,inventoryBytes,schemaBytes,mapping:duplicateEffect}),/MIGRATION_MAPPING_EFFECT_DUPLICATED/);
});
test("inventory preserves both Migration 007 sources and Migration 039",()=>{
  const paths=inventory.migrations.map(x=>x.path);
  assert.equal(paths.length,40);
  assert.ok(paths.includes("supabase/migrations/202607260007_sprint6_daily_deedlight.sql"));
  assert.ok(paths.includes("supabase/migrations/202607260007_sprint7_pwa_daily_engagement.sql"));
  assert.ok(paths.includes("supabase/migrations/202611260039_delivery_kind_scoped_claims.sql"));
  assert.equal(inventory.migrations.filter(x=>x.version==="202607260007").length,2);
});
test("migration history structure validates exact columns without assuming physical column order",()=>{
  const reordered=fixtureCsv(undefined,[["1","version","text","t"],["2","statements","text[]","f"],["3","name","text","f"]]);
  assert.equal(adapt(reordered).candidate.evidence.history.complete,true);
  const malformed=fixtureCsv(undefined,[["1","version","text","t"],["2","version","text","t"],["3","statements","text[]","f"]]);
  assert.throws(()=>adapt(malformed),/MIGRATION_HISTORY_STRUCTURE_INCOMPLETE/);
});
