import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { canonicalJson, INVENTORY_GIT_BLOB_SHA1, PROJECT_REF, RECEIPT_SCHEMA_GIT_BLOB_SHA1, RECEIPT_SCHEMA_SHA256, SQL_GIT_BLOB_SHA1, SQL_PATH, SQL_PROJECTIONS, SQL_SHA256, SQL_NULL_SENTINEL, CSV_QUOTED_EMPTY, parseCsv, sha256, validateSqlOutput } from "./collect-production-migration-evidence.mjs";
import { gitBlobSha1 } from "./verify-migration-inventory-aggregate.mjs";
import { adaptCollectorEvidence } from "./adapt-production-migration-evidence.mjs";
import { analyzeMigrationEvidence, validateCollectorPrivilegeEvidence } from "./reconcile-migration-evidence.mjs";
const inventoryBytes=readFileSync(new URL("../supabase/migration-inventory.json",import.meta.url));
const schemaBytes=readFileSync(new URL("../schemas/production-migration-collection-receipt-v1.schema.json",import.meta.url));
const inventory=JSON.parse(inventoryBytes);
const cell=v=>{if(v===null)return SQL_NULL_SENTINEL;if(v===CSV_QUOTED_EMPTY)return '""';const s=String(v);return s===""||/[",\r\n]/.test(s)?'"'+s.replaceAll('"','""')+'"':s;};
const serialize=rows=>Buffer.from(rows.map(row=>row.map(cell).join(",")).join("\r\n")+"\r\n");
function fixtureCsv(history=[["202607210001","NULL","12"],["202607210002","\\N","13"],["202607220003",null,"14"]],historyStructure=[["1","version","text","t"],["2","name","text","f"],["3","statements","text[]","f"]],overrides={}){
  const data=new Map(SQL_PROJECTIONS.map(p=>[p.id,[]]));
  data.set("identity_v1",[[PROJECT_REF,"a".repeat(40),"postgres","deedlight_catalog_auditor","deedlight_catalog_auditor","16.0","127.0.0.1","5432","2026-11-26T00:00:00.000Z","on"]]);
  data.set("relations_v1",[
    ["public","profiles","r","postgres","p","f","f","1","id","uuid","t","",""],
    ["supabase_migrations","schema_migrations","r","postgres","p","f","f","1","version","text","t","",""],
    ["supabase_migrations","schema_migrations","r","postgres","p","f","f","2","statements","_text","f","",""],
    ["supabase_migrations","schema_migrations","r","postgres","p","f","f","3","name","text","f","",""]
  ]);
  data.set("relation_acl_v1",[["relation","supabase_migrations","schema_migrations","","deedlight_catalog_auditor","postgres","SELECT","f"]]);
  data.set("schema_acl_v1",[["supabase_migrations","postgres","deedlight_catalog_auditor","postgres","USAGE","f"]]);
  data.set("roles_v1",[["deedlight_catalog_auditor","t","f","f","f","f","f","f","-1",""]]);
  data.set("rls_policies_v1",[["public","profiles","profiles_select","PERMISSIVE","{authenticated}","SELECT","",""]]);
  data.set("migration_history_structure_v1",historyStructure);
  data.set("migration_history_v1",history);
  data.set("database_acl_v1",[["database_acl_v1","1","1","postgres","t","f","10","postgres","t","built_in_default",
    JSON.stringify([{grantee_oid:0,grantee_name:"PUBLIC",grantor_oid:10,grantor_name:"postgres",privilege_type:"CONNECT",is_grantable:false}])]]);
  for(const [id,rows] of Object.entries(overrides))data.set(id,rows);
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
  assert.equal(candidate.evidence.provenance.queryBundleSha256,SQL_SHA256);assert.equal(candidate.evidence.provenance.capturedAt,"2026-11-26T00:00:01.000Z");assert.equal(candidate.databaseCaptureTimestamp,"2026-11-26T00:00:00.000Z");assert.equal(candidate.evidence.history.complete,true);
  assert.deepEqual(candidate.evidence.history.rows.map(r=>r.name),["NULL","\\N",null]);
  assert.equal(candidate.evidence.catalog.complete,false);assert.equal(candidate.projections.length,19);
  assert.equal(candidate.evidence.provenance.environment,"production");
  assert.equal(candidate.unmappedCatalogEvidence.extensions_v1.status,"PRESERVED_NOT_NORMALIZED");
  assert.equal(candidate.databaseAuthorityCandidate.privilegeContractVersion,"catalog_only_v1");
  assert.deepEqual(validateCollectorPrivilegeEvidence(candidate.databaseAuthorityCandidate,candidate.evidence.catalog.objects),[]);
  assert.deepEqual(candidate.databaseAuthorityCandidate.requiredAccessSummary,["DATABASE_CONNECT","SYSTEM_CATALOG_SELECT","MIGRATION_HISTORY_SCHEMA_USAGE","MIGRATION_HISTORY_SELECT"]);
  assert.deepEqual(candidate.databaseAuthorityCandidate.databasePrivileges,["CONNECT"]);
  assert.deepEqual(candidate.databaseAuthorityCandidate.schemaPrivileges,[
    {schema:"public",scope:"application_data",privileges:[]},
    {schema:"supabase_migrations",scope:"migration_history",privileges:["USAGE"]}
  ]);
  assert.deepEqual(candidate.databaseAuthorityCandidate.objectPrivileges,[
    {kind:"tables",identity:"public.profiles",scope:"application_data",privileges:[]},
    {kind:"tables",identity:"supabase_migrations.schema_migrations",scope:"migration_history",privileges:["SELECT"]}
  ]);
  assert.equal(candidate.databaseAuthorityCandidate.columnPrivileges.length,4);
  assert.ok(candidate.databaseAuthorityCandidate.columnPrivileges.filter(x=>x.scope==="application_data").every(x=>x.privileges.length===0));
  assert.ok(candidate.databaseAuthorityCandidate.columnPrivileges.filter(x=>x.scope==="migration_history").every(x=>JSON.stringify(x.privileges)==='["SELECT"]'));
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
test("quoted dotted schema and relation names remain application-data columns",()=>{
  const relations=[
    ["public","profiles","r","postgres","p","f","f","1","id","uuid","t","",""],
    ["supabase_migrations","schema_migrations","r","postgres","p","f","f","1","version","text","t","",""],
    ["supabase_migrations","schema_migrations","r","postgres","p","f","f","2","statements","_text","f","",""],
    ["supabase_migrations","schema_migrations","r","postgres","p","f","f","3","name","text","f","",""],
    ["supabase_migrations.schema_migrations","x","r","postgres","p","f","f","1","a","text","f","",""],
    ["supabase_migrations","schema_migrations.impostor","r","postgres","p","f","f","1","b","text","f","",""],
  ];
  const {candidate}=adapt(fixtureCsv(undefined,undefined,{relations_v1:relations}));
  const columns=candidate.databaseAuthorityCandidate.columnPrivileges;
  const dottedSchema=columns.find(row=>row.schema==="supabase_migrations.schema_migrations");
  const dottedRelation=columns.find(row=>row.schema==="supabase_migrations"&&row.relation==="schema_migrations.impostor");
  assert.deepEqual([dottedSchema.scope,dottedSchema.privileges],["application_data",[]]);
  assert.deepEqual([dottedRelation.scope,dottedRelation.privileges],["application_data",[]]);
  assert.deepEqual(validateCollectorPrivilegeEvidence(candidate.databaseAuthorityCandidate,candidate.evidence.catalog.objects),[]);
  dottedSchema.privileges=["SELECT"];
  assert.ok(validateCollectorPrivilegeEvidence(candidate.databaseAuthorityCandidate,candidate.evidence.catalog.objects)
    .some(problem=>problem.includes("structured schema/relation/column identities")));
  const grant=[
    "column","supabase_migrations.schema_migrations","x","a","deedlight_catalog_auditor","postgres","SELECT","f",
  ];
  assert.throws(()=>adapt(fixtureCsv(undefined,undefined,{
    relations_v1:relations,
    relation_acl_v1:[["relation","supabase_migrations","schema_migrations","","deedlight_catalog_auditor","postgres","SELECT","f"],grant],
  })),/PRIVILEGE_COLUMN_SCOPE_INVALID/);
});

test("does not invent a reviewed mapping or authenticated authority",()=>{
  const bytes=fixtureCsv(),receipt=receiptFor(bytes),candidate=adaptCollectorEvidence({receipt,csv:bytes,inventoryBytes,schemaBytes});
  assert.equal(Object.hasOwn(candidate.evidence,"mapping"),false);assert.ok(candidate.blockers.some(x=>x.includes("mapping")));
  assert.equal(Object.hasOwn(candidate.evidence,"collectorAuthority"),false);
  assert.equal(Object.hasOwn(candidate.evidence,"externalExecutionProvenance"),false);
});
test("literal NULL and literal backslash-N remain strings; SQL NULL and quoted empty remain distinct",()=>{
  const {candidate}=adapt(fixtureCsv([["202607210001","NULL","1"],["202607210002","\\N","2"],["202607220003",null,"3"],["202607220004","","4"]]));
  assert.deepEqual(candidate.evidence.history.rows,[
    {version:"202607210001",name:"NULL",recordedStatementCount:1},
    {version:"202607210002",name:"\\N",recordedStatementCount:2},
    {version:"202607220003",name:null,recordedStatementCount:3},
    {version:"202607220004",name:"",recordedStatementCount:4}]);
});
test("invalid statement counts fail closed",()=>{
  for(const n of ["NULL","\\N","-1","01","1.5","9007199254740992"])assert.throws(()=>adapt(fixtureCsv([["202607210001","valid_name",n]])),/MIGRATION_HISTORY_STATEMENT_COUNT_INVALID/);
});
test("whole projection blocks cannot be reordered",()=>{
  const rows=parseCsv(fixtureCsv()),headers=new Map(SQL_PROJECTIONS.map(p=>[p.columns.join("\0"),p.id]));
  const blocks=[];let active=null,tail=[],closed=false;
  for(const row of rows){
    const id=headers.get(row.join("\0"));
    if(id){active={id,rows:[row]};blocks.push(active);}
    else if(row.length===1&&row[0]==="collector_transaction_closed"){tail.push(row);active=null;closed=true;}
    else if(closed||!active)tail.push(row);
    else active.rows.push(row);
  }
  assert.equal(blocks.length,19);
  [blocks[0],blocks[1]]=[blocks[1],blocks[0]];
  assert.throws(()=>adapt(serialize([...blocks.flatMap(block=>block.rows),...tail])),/SQL_PROJECTION/);
});
test("non-allowlisted empty projections and invalid role identities fail closed",()=>{
  assert.throws(()=>adapt(fixtureCsv(undefined,undefined,{relations_v1:[]})),/PROJECTION_EMPTY_NOT_ALLOWED/);
  assert.throws(()=>adapt(fixtureCsv(undefined,undefined,{roles_v1:[]})),/PROJECTION_EMPTY_NOT_ALLOWED/);
  const role=["deedlight_catalog_auditor","t","f","f","f","f","f","f","-1",""];
  assert.throws(()=>adapt(fixtureCsv(undefined,undefined,{roles_v1:[role,role]})),/ROLE_IDENTITY_DUPLICATED/);
  assert.throws(()=>adapt(fixtureCsv(undefined,undefined,{roles_v1:[["other_role",...role.slice(1)]]})),/COLLECTOR_ROLE_MISSING_OR_DUPLICATED/);
});
test("ACL values and application-data privilege scopes fail closed",()=>{
  assert.throws(()=>adapt(fixtureCsv(undefined,undefined,{relation_acl_v1:[["relation","public","profiles","","deedlight_catalog_auditor","postgres","CREATE","f"]]})),/ACL_PROJECTION_ROW_INVALID/);
  assert.throws(()=>adapt(fixtureCsv(undefined,undefined,{relation_acl_v1:[
    ["relation","supabase_migrations","schema_migrations","","deedlight_catalog_auditor","postgres","SELECT","f"],
    ["relation","public","profiles","","deedlight_catalog_auditor","postgres","SELECT","f"]
  ]})),/PRIVILEGE_OBJECT_SCOPE_INVALID/);
  assert.throws(()=>adapt(fixtureCsv(undefined,undefined,{relation_acl_v1:[
    ["relation","supabase_migrations","schema_migrations","","deedlight_catalog_auditor","postgres","SELECT","f"],
    ["column","public","profiles","id","deedlight_catalog_auditor","postgres","SELECT","f"]
  ]})),/PRIVILEGE_COLUMN_SCOPE_INVALID/);
});
test("default privileges and duplicate membership identities fail closed",()=>{
  const membership=["auditor_parent","deedlight_catalog_auditor","postgres","f","f","f"];
  assert.throws(()=>adapt(fixtureCsv(undefined,undefined,{role_memberships_v1:[membership,membership]})),/ROLE_MEMBERSHIP_DUPLICATED/);
  assert.throws(()=>adapt(fixtureCsv(undefined,undefined,{default_privileges_v1:[["postgres","public","r","deedlight_catalog_auditor","postgres","SELECT","f"]]})),/PRIVILEGE_DEFAULT_SCOPE_INVALID/);
  const unrelatedRoles=[["deedlight_catalog_auditor","t","f","f","f","f","f","f","-1",""],["deedlight_unrelated_parent","f","f","f","f","f","f","f","-1",""],["deedlight_unrelated_member","f","f","f","f","f","f","f","-1",""]];
  const unrelatedMembership=[["deedlight_unrelated_parent","deedlight_unrelated_member","postgres","f","f","f"]];
  assert.equal(adapt(fixtureCsv(undefined,undefined,{roles_v1:unrelatedRoles,role_memberships_v1:unrelatedMembership})).candidate.acceptance,"NOT_ACCEPTED");
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
  assert.throws(()=>adapt(fixtureCsv(undefined,undefined,{relations_v1:[["public","profiles","r","postgres","p","invalid","f","1","id","uuid","t","",""]]})),/RELATIONS_PROJECTION_ROW_INVALID/);
  assert.throws(()=>adapt(fixtureCsv(undefined,undefined,{schema_acl_v1:[["supabase_migrations","postgres","deedlight_catalog_auditor","postgres","USAGE","maybe"]]})),/ACL_PROJECTION_ROW_INVALID/);
  assert.throws(()=>adapt(fixtureCsv(undefined,undefined,{roles_v1:[["deedlight_catalog_auditor","t","f","f","f","f","f","x","-1",""]]})),/ROLES_PROJECTION_ROW_INVALID/);
});
test("receipt endpoint database and repository SHA must bind to SQL identity",()=>{
  const bytes=fixtureCsv(),receipt=receiptFor(bytes);
  const databaseMismatch=Buffer.from(bytes.toString("utf8").replace("postgres,deedlight_catalog_auditor","deedlight_migration_order_test,deedlight_catalog_auditor"));
  assert.throws(()=>adaptCollectorEvidence({receipt:receiptFor(databaseMismatch),csv:databaseMismatch,inventoryBytes,schemaBytes}),/PROVENANCE_DATABASE_IDENTITY_MISMATCH/);
  const changedRepo=Buffer.from(bytes.toString("utf8").replace("a".repeat(40)+",postgres,","b".repeat(40)+",postgres,"));
  const changedRepoReceipt=receiptFor(changedRepo);
  assert.throws(()=>adaptCollectorEvidence({receipt:changedRepoReceipt,csv:changedRepo,inventoryBytes,schemaBytes}),/PROVENANCE_REPOSITORY_IDENTITY_MISMATCH/);
  const missingDatabase=structuredClone(receipt);delete missingDatabase.endpoint.database;
  assert.throws(()=>adaptCollectorEvidence({receipt:missingDatabase,csv:bytes,inventoryBytes,schemaBytes}));
  const missingCommit=structuredClone(receipt);delete missingCommit.source.repositoryCommitSha;
  assert.throws(()=>adaptCollectorEvidence({receipt:missingCommit,csv:bytes,inventoryBytes,schemaBytes}));
  const testDatabase="deedlight_migration_order_test";
  const testRows=parseCsv(bytes);
  const identityHeaderIndex=testRows.findIndex(row=>row[0]==="expected_project_ref");
  const identityRow=testRows[identityHeaderIndex+1];
  const databaseRow=testRows.find(row=>row[0]==="database_acl_v1");
  assert.ok(identityRow&&databaseRow);
  identityRow[2]=testDatabase;
  databaseRow[3]=testDatabase;
  const testBytes=serialize(testRows);
  const testReceipt=receiptFor(testBytes);testReceipt.endpoint.database=testDatabase;
  const candidate=adaptCollectorEvidence({receipt:testReceipt,csv:testBytes,inventoryBytes,schemaBytes});
  assert.equal(candidate.evidence.provenance.environment,"test");
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


test("explicit unsupported and unknown migration effect domains are retained without acceptance",()=>{
  for(const disposition of ["unsupported","unknown"]){
    const mapping=mappingFixture();
    mapping.migrations[0].effects.backfills=[];
    mapping.migrations[0].coverage.backfills.disposition=disposition;
    mapping.migrations[0].coverage.backfills.rationale="Fixture explicitly records an unresolved backfill review disposition.";
    const {candidate}=adapt(fixtureCsv(),mapping);
    assert.equal(candidate.evidence.mapping.migrations[0].coverage.backfills.disposition,disposition);
    assert.equal(candidate.status,"UNSIGNED_NOT_ACCEPTED");
    assert.equal(candidate.acceptance,"NOT_ACCEPTED");
  }
});

test("mapping rejects disposition/effect contradictions, unordered ranges and category confusion",()=>{
  const mutations=[
    mapping=>{mapping.migrations[0].coverage.schema.disposition="unsupported";},
    mapping=>{mapping.migrations[0].coverage.dependencies.disposition="effects";},
    mapping=>{mapping.migrations[0].coverage.schema.sourceRanges=[{startLine:5,endLine:8},{startLine:4,endLine:9}];},
    mapping=>{mapping.migrations[0].coverage.schema.sourceRanges=[{startLine:1,endLine:4},{startLine:4,endLine:8}];},
    mapping=>{mapping.migrations[0].effects.dataTransformations[0].kind="backfills";},
    mapping=>{mapping.migrations[0].effects.preconditions=[{kind:"preconditions",identity:"x",fingerprint:"bad",description:"Malformed fingerprint fixture."}];mapping.migrations[0].coverage.preconditions.disposition="effects";},
  ];
  for(const mutate of mutations){const mapping=mappingFixture();mutate(mapping);assert.throws(()=>adapt(fixtureCsv(),mapping));}
});

test("adapter candidate cannot enter authenticated analyzer acceptance by structural validation alone",()=>{
  const {candidate}=adapt();
  assert.deepEqual(validateCollectorPrivilegeEvidence(candidate.databaseAuthorityCandidate,candidate.evidence.catalog.objects),[]);
  assert.equal(Object.hasOwn(candidate.evidence,"collectorAuthority"),false);
  const report=analyzeMigrationEvidence({rootDir:process.cwd(),manifest:inventory,evidence:candidate.evidence,approvals:{},trustRoots:{schemaVersion:1,keys:[]}});
  assert.equal(report.trustVerified,false);
  assert.equal(report.acceptance,"NOT_ACCEPTED");
  assert.ok(report.trustProblems.some(reason=>reason.includes("missing required property")));
  assert.ok(report.trustProblems.some(reason=>reason.includes("signed artifact is missing")));
});


function sourceLineBinding(entry){
  const line=readFileSync(new URL("../"+entry.path,import.meta.url),"utf8").split(/\r?\n/)[0];
  return {sourceRange:{startLine:1,endLine:1},sourceStatementSha256:sha256(Buffer.from(line))};
}

function sourceLineBinding(entry){
  const line=readFileSync(new URL("../"+entry.path,import.meta.url),"utf8").split(/\r?\n/)[0];
  return {sourceRange:{startLine:1,endLine:1},sourceStatementSha256:sha256(Buffer.from(line))};
}

test("category-specific transformation contract requires exact source and target relations",()=>{
  const mapping=mappingFixture(),entry=mapping.migrations[0],binding=sourceLineBinding(entry);
  const effect={kind:"dataTransformations",identity:"fixture.transform",fingerprint:"e".repeat(64),
    description:"Synthetic test-only transformation contract.",sourcePath:entry.path,
    contract:{operation:"UPDATE",sourceRelations:[{schema:"fixture",relation:"source"}],
      targetRelation:{schema:"fixture",relation:"target"},predicate:{sql:"id IS NOT NULL",sha256:"f".repeat(64)},...binding}};
  entry.effects.dataTransformations=[effect];entry.coverage.dataTransformations.disposition="effects";
  assert.doesNotThrow(()=>adapt(fixtureCsv(),mapping));
  for(const mutate of [
    x=>{x.contract.targetRelation={schema:"fixture"};},
    x=>{x.contract.sourceRelations=[{schema:"fixture",relation:"bad-name;drop"}];},
    x=>{x.contract.sourceStatementSha256="not-a-digest";},
    x=>{x.sourcePath="supabase/migrations/not-in-inventory.sql";},
  ]){const changed=structuredClone(mapping);mutate(changed.migrations[0].effects.dataTransformations[0]);assert.throws(()=>adapt(fixtureCsv(),changed));}
});

test("backfill contracts preserve unavailable measurement without asserting row counts",()=>{
  const mapping=mappingFixture(),entry=mapping.migrations[0],binding=sourceLineBinding(entry);
  entry.effects.backfills=[{kind:"backfills",identity:"fixture.backfill",fingerprint:"b".repeat(64),
    description:"Synthetic test-only backfill candidate.",sourcePath:entry.path,
    contract:{targetRelation:{schema:"fixture",relation:"target"},predicate:{sql:"processed_at IS NULL",sha256:"c".repeat(64)},
      measurement:{status:"not_measured",reason:"No independent execution measurement is supplied by this source fixture."},...binding}}];
  entry.coverage.backfills.disposition="effects";
  assert.equal(adapt(fixtureCsv(),mapping).candidate.status,"UNSIGNED_NOT_ACCEPTED");
  const malformed=structuredClone(mapping);
  malformed.migrations[0].effects.backfills[0].contract.measurement={status:"independently_measured",rowCount:-1,
    querySha256:"e".repeat(64),evidenceDigest:"f".repeat(64),capturedAt:"2026-11-26T00:00:00.000Z",
    executionId:"made-up",sourceBlobSha1:entry.blobSha1};
  assert.throws(()=>adapt(fixtureCsv(),malformed));
});

test("dependency contracts require a pinned distinct prerequisite migration",()=>{
  const mapping=mappingFixture(),entry=mapping.migrations[1],dependency=inventory.migrations[0],binding=sourceLineBinding(entry);
  entry.effects.dependencies=[{kind:"dependencies",identity:"fixture.dependency",fingerprint:"a".repeat(64),
    description:"Synthetic test-only dependency edge.",sourcePath:entry.path,
    contract:{dependencyType:"foreign_key",fromRelation:{schema:"fixture",relation:"child"},
      toRelation:{schema:"fixture",relation:"parent"},dependsOnMigrationPath:dependency.path,...binding}}];
  entry.coverage.dependencies.disposition="effects";
  assert.doesNotThrow(()=>adapt(fixtureCsv(),mapping));
  const invalid=structuredClone(mapping);
  invalid.migrations[1].effects.dependencies[0].contract.dependsOnMigrationPath=entry.path;
  assert.throws(()=>adapt(fixtureCsv(),invalid));
});

test("precondition and postcondition contracts require explicit predicates and verification state",()=>{
  for(const category of ["preconditions","postconditions"]){
    const mapping=mappingFixture(),entry=mapping.migrations[0],binding=sourceLineBinding(entry);
    entry.effects[category]=[{kind:category,identity:"fixture."+category,fingerprint:"c".repeat(64),
      description:"Synthetic test-only condition contract.",sourcePath:entry.path,
      contract:{predicateSql:"SELECT count(*) = 0 FROM fixture.target WHERE invalid",
        predicateSha256:"d".repeat(64),expectedOutcome:"true",
        verification:{status:"not_verified",reason:"Source text alone cannot establish the execution outcome."},...binding}}];
    entry.coverage[category].disposition="effects";
    assert.doesNotThrow(()=>adapt(fixtureCsv(),mapping));
    const invalid=structuredClone(mapping);
    invalid.migrations[0].effects[category][0].contract.expectedOutcome="unknown";
    assert.throws(()=>adapt(fixtureCsv(),invalid));
  }
});
