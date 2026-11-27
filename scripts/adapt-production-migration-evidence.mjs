#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import {
  canonicalJson, INVENTORY_GIT_BLOB_SHA1, PROJECT_REF, RECEIPT_SCHEMA_GIT_BLOB_SHA1,
  RECEIPT_SCHEMA_SHA256, SQL_GIT_BLOB_SHA1, SQL_PATH, SQL_PROJECTIONS, SQL_SHA256,
  sha256, validateSqlOutput, verifyReceiptAndEvidence,
} from "./collect-production-migration-evidence.mjs";
import { gitBlobSha1, validateInventory } from "./verify-migration-inventory-aggregate.mjs";

const CATALOG_KINDS = ["schemas","tables","sequences","columns","constraints","indexes","triggers","policies","routines","privileges","ownership"];
const CATEGORIES = ["schema","privileges","ownership","routines","dataTransformations","backfills","dependencies","preconditions","postconditions"];
const SCHEMA_EFFECT_KINDS = new Set(["tables","columns","constraints","indexes","triggers","policies"]);
const ACL_IDS = ["relation_acl_v1","schema_acl_v1","routine_acl_v1","sequence_acl_v1","default_privileges_v1"];
const exact = (v, keys) => v && typeof v === "object" && !Array.isArray(v)
  && Object.keys(v).sort().join("\0") === [...keys].sort().join("\0");
const hex = (v, n) => typeof v === "string" && new RegExp("^[a-f0-9]{" + n + "}$").test(v);
function fail(code) { const error = new Error(code); error.code = code; throw error; }
function parseProjections(validation) {
  const result = new Map(SQL_PROJECTIONS.map((p) => [p.id, []]));
  const headers = new Map(SQL_PROJECTIONS.map((p) => [p.columns.join("\0"), p.id]));
  let active = null;
  for (const row of validation.rows) {
    const id = headers.get(row.join("\0"));
    if (id) { active = id; continue; }
    if (row.length === 1 && row[0] === "collector_transaction_closed") break;
    if (!active) fail("PROJECTION_DATA_WITHOUT_HEADER");
    result.get(active).push(row);
  }
  if (result.size !== 19) fail("PROJECTION_SET_INCOMPLETE");
  return result;
}
function projectionObjects(projections, id) {
  const p = SQL_PROJECTIONS.find((item) => item.id === id);
  if (!p) fail("PROJECTION_IDENTITY_UNKNOWN");
  return projections.get(id).map((row) => Object.fromEntries(p.columns.map((column, i) => [column, row[i]])));
}
const bool = (value) => value === "t" || value === "f";
const nonempty = (row, indexes) => indexes.every((i) => typeof row[i] === "string" && row[i].length > 0);
function validateProjectionRows(p) {
  for (const row of p.get("relations_v1")) {
    if (!nonempty(row,[0,1,2,3,4,7]) || !/^[1-9][0-9]*$/.test(row[7]) || !bool(row[5]) || !bool(row[6]) || !bool(row[10])
        || (row[8] !== "" && !row[9])) fail("RELATIONS_PROJECTION_ROW_INVALID");
  }
  for (const row of p.get("routines_v1")) {
    if (!nonempty(row,[0,1,2,5,6,9]) || (row[2] !== "p" && !row[4]) || !bool(row[7]) || !bool(row[8]) || !["i","s","v"].includes(row[9])) fail("ROUTINES_PROJECTION_ROW_INVALID");
  }
  for (const id of ACL_IDS) for (const row of p.get(id)) {
    if (!bool(row.at(-1)) || !row.some((cell) => cell !== "")) fail("ACL_PROJECTION_ROW_INVALID");
    if (id === "relation_acl_v1" && !nonempty(row,[0,1,2,4,5,6])) fail("RELATION_ACL_ROW_INVALID");
    if (id === "schema_acl_v1" && !nonempty(row,[0,1,2,3,4])) fail("SCHEMA_ACL_ROW_INVALID");
    if (id === "routine_acl_v1" && !nonempty(row,[0,1,3,4,5])) fail("ROUTINE_ACL_ROW_INVALID");
    if (id === "sequence_acl_v1" && !nonempty(row,[0,1,2,3,4,5])) fail("SEQUENCE_ACL_ROW_INVALID");
    if (id === "default_privileges_v1" && !nonempty(row,[0,2,3,4,5])) fail("DEFAULT_PRIVILEGES_ROW_INVALID");
  }
  for (const row of p.get("roles_v1")) {
    if (!nonempty(row,[0,8]) || row.slice(1,8).some((v) => !bool(v)) || !/^-?(0|[1-9][0-9]*)$/.test(row[8])
        || (row[9] !== "" && row[9] !== "infinity" && !/^\d{4}-\d{2}-\d{2}T/.test(row[9]))) fail("ROLES_PROJECTION_ROW_INVALID");
  }
  for (const row of p.get("role_memberships_v1")) if (!nonempty(row,[0,1,2]) || row.slice(3,6).some((v) => !bool(v))) fail("ROLE_MEMBERSHIPS_ROW_INVALID");
  for (const row of p.get("rls_policies_v1")) {
    if (!nonempty(row,[0,1,2,3,4,5]) || !["PERMISSIVE","RESTRICTIVE"].includes(row[3]) || !["ALL","SELECT","INSERT","UPDATE","DELETE"].includes(row[5])) fail("RLS_POLICY_ROW_INVALID");
  }
  for (const row of p.get("constraints_v1")) if (!nonempty(row,[0,1,2,3,7]) || row.slice(4,7).some((v) => !bool(v))) fail("CONSTRAINT_ROW_INVALID");
  for (const row of p.get("indexes_v1")) if (!nonempty(row,[0,1,2,11]) || row.slice(3,11).some((v) => !bool(v))) fail("INDEX_ROW_INVALID");
  for (const row of p.get("triggers_v1")) if (!nonempty(row,[0,1,2,3,5]) || !["O","D","R","A"].includes(row[3]) || !bool(row[4])) fail("TRIGGER_ROW_INVALID");
  for (const row of p.get("sequences_v1")) {
    if (!nonempty(row,[0,1,2,3,4,5,6,7,8]) || row.slice(4,9).some((v) => !/^-?(0|[1-9][0-9]*)$/.test(v)) || !bool(row[9])) fail("SEQUENCE_ROW_INVALID");
  }
  for (const row of p.get("extensions_v1")) if (!nonempty(row,[0,1,2,3])) fail("EXTENSION_ROW_INVALID");
}
function buildCatalog(p) {
  const objects=[],seen=new Set();
  const add=(kind,identity,value)=>{
    if(typeof identity!=="string"||!identity.trim())fail("CATALOG_IDENTITY_INVALID");
    const key=kind+"\0"+identity;if(seen.has(key))fail("CATALOG_IDENTITY_DUPLICATED");seen.add(key);
    objects.push({kind,identity,fingerprint:sha256(Buffer.from(canonicalJson(value),"utf8"))});
  };
  const relations=projectionObjects(p,"relations_v1"),routines=projectionObjects(p,"routines_v1");
  const sequences=projectionObjects(p,"sequences_v1"),schemaAcl=projectionObjects(p,"schema_acl_v1");
  const schemaValues=new Map(),includeSchema=(name,row)=>{const rows=schemaValues.get(name)??[];rows.push(row);schemaValues.set(name,rows);};
  for(const row of [...relations,...routines,...sequences,...schemaAcl])includeSchema(row.schema_name,row);
  for(const [name,rows] of [...schemaValues].sort(([a],[b])=>a.localeCompare(b))){
    rows.sort((a,b)=>canonicalJson(a).localeCompare(canonicalJson(b)));add("schemas",name,rows);
  }
  const relationGroups=new Map(),relationOwners=new Map();
  for(const row of relations){
    const identity=row.schema_name+"."+row.relation_name,group=relationGroups.get(identity)??[];
    group.push(row);relationGroups.set(identity,group);
    if(row.column_name)add("columns",identity+"."+row.column_name,row);
    if(row.owner_name)relationOwners.set(identity,{owner:row.owner_name,relationKind:row.relation_kind});
  }
  for(const [identity,rows] of [...relationGroups].sort(([a],[b])=>a.localeCompare(b))){
    rows.sort((a,b)=>Number(a.ordinal_position)-Number(b.ordinal_position));add("tables",identity,rows);
  }
  for(const [identity,owner] of [...relationOwners].sort(([a],[b])=>a.localeCompare(b)))add("ownership",identity,owner);
  for(const row of routines){
    const identity=row.schema_name+"."+row.routine_name+"("+row.identity_arguments+")";
    add("routines",identity,row);if(row.owner_name)add("ownership",identity,{owner:row.owner_name});
  }
  for(const row of sequences){
    const identity=row.schema_name+"."+row.sequence_name;
    add("sequences",identity,row);if(row.owner_name)add("ownership",identity,{owner:row.owner_name});
  }
  const schemaOwners=new Map();for(const row of schemaAcl)if(row.owner_name)schemaOwners.set(row.schema_name,{owner:row.owner_name});
  for(const [schema,owner] of [...schemaOwners].sort(([a],[b])=>a.localeCompare(b)))add("ownership","schema:"+schema,owner);
  const simple=[
    ["constraints_v1","constraints",r=>r.schema_name+"."+r.table_name+"."+r.constraint_name],
    ["indexes_v1","indexes",r=>r.schema_name+"."+r.table_name+"."+r.index_name],
    ["triggers_v1","triggers",r=>r.schema_name+"."+r.table_name+"."+r.trigger_name],
    ["rls_policies_v1","policies",r=>r.schemaname+"."+r.tablename+"."+r.policyname],
  ];
  for(const [id,kind,identity] of simple)for(const row of projectionObjects(p,id))add(kind,identity(row),row);
  for(const id of ACL_IDS)for(const row of projectionObjects(p,id))add("privileges",id+":"+Object.values(row).join("\u001f"),row);
  for(const row of projectionObjects(p,"database_acl_v1")){
    const db="database:"+row.database_name;add("ownership",db,{owner:row.owner_name,ownerOid:row.owner_oid});
    for(const edge of JSON.parse(row.expanded_acl_edges)){
      const id=db+":"+edge.grantee_oid+":"+edge.grantor_oid+":"+edge.privilege_type+":"+Number(edge.is_grantable);
      add("privileges",id,{database:row.database_name,...edge});
    }
  }
  return objects;
}
function validateMapping(mapping,inventory){
  if(mapping===undefined||mapping===null)return null;
  if(!exact(mapping,["schemaVersion","migrations"])||mapping.schemaVersion!==1||!Array.isArray(mapping.migrations)||mapping.migrations.length!==40)fail("MIGRATION_MAPPING_INCOMPLETE");
  const byPath=new Map();
  for(const entry of mapping.migrations){
    if(!exact(entry,["path","blobSha1","coverage","effects"])||typeof entry.path!=="string"||byPath.has(entry.path)||!hex(entry.blobSha1,40))fail("MIGRATION_MAPPING_ENTRY_INVALID");
    if(!exact(entry.effects,CATEGORIES)||!exact(entry.coverage,CATEGORIES))fail("MIGRATION_MAPPING_CATEGORIES_INVALID");
    let count=0;
    const seenEffects=new Set();
    for(const category of CATEGORIES){
      const effects=entry.effects[category],review=entry.coverage[category];
      if(!Array.isArray(effects)||!exact(review,["disposition","rationale","sourceRanges"])||review.disposition!==(effects.length?"effects":"none")
        ||typeof review.rationale!=="string"||review.rationale.trim().length<20||!Array.isArray(review.sourceRanges)||!review.sourceRanges.length
        ||review.sourceRanges.some((range)=>!exact(range,["startLine","endLine"])||!Number.isSafeInteger(range.startLine)||!Number.isSafeInteger(range.endLine)||range.startLine<1||range.endLine<range.startLine))fail("MIGRATION_MAPPING_COVERAGE_INVALID");
      for(const effect of effects){
        const allowedKinds=category==="schema"?SCHEMA_EFFECT_KINDS:category==="routines"?new Set(["routines"]):new Set([category]);
        if(!exact(effect,["description","fingerprint","identity","kind"])||typeof effect.identity!=="string"||!effect.identity.trim()
          ||!allowedKinds.has(effect.kind)||!hex(effect.fingerprint,64)||typeof effect.description!=="string"||!effect.description.trim())fail("MIGRATION_MAPPING_EFFECT_INVALID");
        const effectIdentity=effect.kind+"\\0"+effect.identity;
        if(seenEffects.has(effectIdentity))fail("MIGRATION_MAPPING_EFFECT_DUPLICATED");
        seenEffects.add(effectIdentity);
        count++;
      }
    }
    if(!count)fail("MIGRATION_MAPPING_EMPTY");byPath.set(entry.path,entry);
  }
  for(const item of inventory.migrations){const entry=byPath.get(item.path);if(!entry||entry.blobSha1!==item.blobSha1)fail("MIGRATION_MAPPING_SOURCE_MISMATCH");}
  if(byPath.size!==40)fail("MIGRATION_MAPPING_PATH_SET_INVALID");return mapping;
}
function rawProjections(p){return SQL_PROJECTIONS.map(x=>({id:x.id,columns:[...x.columns],rows:p.get(x.id).map(row=>[...row])}));}
function authorityCandidate(p){
  const identity=projectionObjects(p,"identity_v1");if(identity.length!==1)fail("IDENTITY_PROJECTION_CARDINALITY_INVALID");
  return {status:"UNAUTHENTICATED_CANDIDATE",declaredContract:"catalog_only_v1",authenticated:false,
    effectiveRole:identity[0].current_role,sessionRole:identity[0].session_role,
    roles:projectionObjects(p,"roles_v1"),roleMemberships:projectionObjects(p,"role_memberships_v1"),
    privilegeProjections:Object.fromEntries(ACL_IDS.map(id=>[id,projectionObjects(p,id)])),
    databaseAcl:projectionObjects(p,"database_acl_v1").map(row=>({...row,expanded_acl_edges:JSON.parse(row.expanded_acl_edges)}))};
}
export function adaptCollectorEvidence({receipt,csv,inventoryBytes,schemaBytes,mapping}){
  if(!Buffer.isBuffer(csv)||!Buffer.isBuffer(inventoryBytes)||!Buffer.isBuffer(schemaBytes))fail("ADAPTER_INPUT_BYTES_REQUIRED");
  let inventory;try{inventory=JSON.parse(inventoryBytes.toString("utf8"));}catch{fail("MIGRATION_INVENTORY_JSON_INVALID");}
  try{validateInventory(inventory);}catch{fail("MIGRATION_INVENTORY_INVALID");}
  if(gitBlobSha1(inventoryBytes)!==INVENTORY_GIT_BLOB_SHA1||receipt?.source?.migrationInventoryGitBlobSha1!==INVENTORY_GIT_BLOB_SHA1)fail("MIGRATION_INVENTORY_FINGERPRINT_MISMATCH");
  const actualSchemaBlob=gitBlobSha1(schemaBytes),actualSchemaSha256=sha256(schemaBytes);
  if(actualSchemaBlob!==RECEIPT_SCHEMA_GIT_BLOB_SHA1)fail("RECEIPT_SCHEMA_GIT_BLOB_SHA1_MISMATCH:"+actualSchemaBlob);
  if(actualSchemaSha256!==RECEIPT_SCHEMA_SHA256)fail("RECEIPT_SCHEMA_RAW_SHA256_MISMATCH:"+actualSchemaSha256);
  if(receipt?.source?.receiptSchemaGitBlobSha1!==RECEIPT_SCHEMA_GIT_BLOB_SHA1)fail("RECEIPT_SCHEMA_RECEIPT_BLOB_SHA1_MISMATCH:"+String(receipt?.source?.receiptSchemaGitBlobSha1));
  if(receipt?.source?.receiptSchemaSha256!==RECEIPT_SCHEMA_SHA256)fail("RECEIPT_SCHEMA_RECEIPT_SHA256_MISMATCH:"+String(receipt?.source?.receiptSchemaSha256));
  verifyReceiptAndEvidence(receipt,csv);
  const validation=validateSqlOutput(csv),p=parseProjections(validation);validateProjectionRows(p);
  const identityRow=projectionObjects(p,"identity_v1")[0];
  const databaseCaptureTimestamp=identityRow.captured_at_utc;
  if(typeof databaseCaptureTimestamp!=="string"||!/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$/.test(databaseCaptureTimestamp))fail("COLLECTOR_CAPTURE_TIMESTAMP_INVALID");
  const capturedAt=receipt.execution.completedAt;
  const structure=p.get("migration_history_structure_v1");
  const structureByName=new Map(structure.map(row=>[row[1],row]));
  const structureValid=structure.length===3&&structureByName.size===3
    &&["version","name","statements"].every(name=>structureByName.has(name))
    &&new Set(structure.map(row=>row[0])).size===3
    &&structure.every(row=>["1","2","3"].includes(row[0])&&bool(row[3]))
    &&structureByName.get("version")[2]==="text"&&structureByName.get("version")[3]==="t"
    &&structureByName.get("name")[2]==="text"&&structureByName.get("name")[3]==="f"
    &&structureByName.get("statements")[2]==="text[]"&&structureByName.get("statements")[3]==="f";
  if(!structureValid)fail("MIGRATION_HISTORY_STRUCTURE_INCOMPLETE");
  if(validation.migrationHistoryRows.length!==receipt.execution.migrationHistoryRowCount)fail("MIGRATION_HISTORY_CARDINALITY_MISMATCH");
  const normalizedMapping=validateMapping(mapping,inventory);
  const evidence={schemaVersion:2,
    provenance:{environment:"production",projectRef:PROJECT_REF,capturedAt,collectorIdentity:receipt.execution.collectorId,queryBundleSha256:receipt.source.sqlBundleSha256},
    history:{complete:true,rows:validation.migrationHistoryRows},
    catalog:{complete:false,completeKinds:[...CATALOG_KINDS],objects:buildCatalog(p)}};
  if(normalizedMapping)evidence.mapping=normalizedMapping;
  return {schemaVersion:1,status:"UNSIGNED_NOT_ACCEPTED",acceptance:"NOT_ACCEPTED",adapter:"deedlight-collector-analyzer-adapter-v1",
    receipt,databaseCaptureTimestamp,evidence,databaseAuthorityCandidate:authorityCandidate(p),projections:rawProjections(p),
    integrity:{receiptCanonicalSha256:sha256(Buffer.from(canonicalJson(receipt),"utf8")),
      receiptSchemaGitBlobSha1:RECEIPT_SCHEMA_GIT_BLOB_SHA1,receiptSchemaSha256:RECEIPT_SCHEMA_SHA256,
      migrationInventoryGitBlobSha1:INVENTORY_GIT_BLOB_SHA1,repositoryCommitSha:receipt.source.repositoryCommitSha,sqlBundlePath:SQL_PATH,sqlBundleGitBlobSha1:SQL_GIT_BLOB_SHA1,
      sqlBundleSha256:SQL_SHA256,csvSha256:receipt.evidence.sha256,canonicalResultSha256:receipt.execution.canonicalResultSha256,
      normalizedEvidenceSha256:sha256(Buffer.from(canonicalJson(evidence),"utf8"))},
    signing:{state:"NOT_SIGNED",authenticated:false},
    blockers:["Collector receipt is explicitly unsigned and cannot authenticate evidence.",
      "Catalog projections do not attest data transformations, backfills, dependencies, preconditions or postconditions.",
      "Collector output does not contain independently authenticated collectorAuthority execution evidence.",
      ...(normalizedMapping?[]:["A complete independently reviewed 40-entry migration mapping was not supplied."]),
      "Independent evidence, mapping and collector approvals and provisioned trust roots are required."]};
}
function main(){
  const args=process.argv.slice(2),arg=name=>{const i=args.indexOf(name);return i>=0&&args[i+1]&&!args[i+1].startsWith("--")?args[i+1]:null;};
  if(args.includes("--help")){process.stdout.write("usage: node scripts/adapt-production-migration-evidence.mjs --receipt receipt.json --csv evidence.csv [--mapping reviewed-mapping.json] --output candidate.json\n");return;}
  const receiptPath=arg("--receipt"),csvPath=arg("--csv"),outputPath=arg("--output"),mappingPath=arg("--mapping");
  if(!receiptPath||!csvPath||!outputPath||args.some(x=>x.startsWith("--")&&!["--receipt","--csv","--mapping","--output"].includes(x)))fail("ADAPTER_ARGUMENTS_INVALID");
  const receipt=JSON.parse(readFileSync(receiptPath,"utf8")),csv=readFileSync(csvPath);
  const inventoryBytes=readFileSync(path.resolve("supabase/migration-inventory.json"));
  const schemaBytes=readFileSync(path.resolve("schemas/production-migration-collection-receipt-v1.schema.json"));
  const mapping=mappingPath?JSON.parse(readFileSync(mappingPath,"utf8")):undefined;
  const candidate=adaptCollectorEvidence({receipt,csv,inventoryBytes,schemaBytes,mapping});
  writeFileSync(outputPath,JSON.stringify(candidate,null,2)+"\n",{flag:"wx",mode:0o600});
  process.stdout.write("UNSIGNED_NOT_ACCEPTED: normalized candidate written; analyzer acceptance is prohibited.\n");
}
if(process.argv[1]&&path.resolve(process.argv[1])===path.resolve(new URL(import.meta.url).pathname))main();
