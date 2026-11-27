#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import {
  canonicalJson, CSV_QUOTED_EMPTY, INVENTORY_GIT_BLOB_SHA1, PROJECT_REF, RECEIPT_SCHEMA_GIT_BLOB_SHA1,
  RECEIPT_SCHEMA_SHA256, SQL_GIT_BLOB_SHA1, SQL_PATH, SQL_PROJECTIONS, SQL_SHA256,
  sha256, validateSqlOutput, verifyReceiptAndEvidence,
} from "./collect-production-migration-evidence.mjs";
import { gitBlobSha1, validateInventory } from "./verify-migration-inventory-aggregate.mjs";

const CATALOG_KINDS = ["schemas","tables","sequences","columns","constraints","indexes","triggers","policies","routines","privileges","ownership"];
const CATEGORIES = ["schema","privileges","ownership","routines","dataTransformations","backfills","dependencies","preconditions","postconditions"];
const SCHEMA_EFFECT_KINDS = new Set(["tables","columns","constraints","indexes","triggers","policies"]);
const ACL_IDS = ["relation_acl_v1","schema_acl_v1","routine_acl_v1","sequence_acl_v1","default_privileges_v1"];
const EMPTY_PROJECTION_ALLOWLIST = new Set(["relation_acl_v1","routine_acl_v1","role_memberships_v1","rls_policies_v1","constraints_v1","indexes_v1","triggers_v1","sequences_v1","sequence_acl_v1","default_privileges_v1","extensions_v1","migration_history_v1"]);
const REQUIRED_ACCESS_SUMMARY = ["DATABASE_CONNECT","SYSTEM_CATALOG_SELECT","MIGRATION_HISTORY_SCHEMA_USAGE","MIGRATION_HISTORY_SELECT"];
const RELATION_PRIVILEGES = new Set(["SELECT","INSERT","UPDATE","DELETE","TRUNCATE","REFERENCES","TRIGGER"]);
const SEQUENCE_PRIVILEGES = new Set(["USAGE","SELECT","UPDATE"]);
const SCHEMA_PRIVILEGES = new Set(["USAGE","CREATE"]);
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
    result.get(active).push(row.map((cell,index)=>cell===CSV_QUOTED_EMPTY && !(active==="migration_history_v1"&&index===1)?"":cell));
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
  for (const projection of SQL_PROJECTIONS) {
    const rows=p.get(projection.id);
    if (!Array.isArray(rows)) fail("PROJECTION_MISSING:"+projection.id);
    if (!rows.length && !EMPTY_PROJECTION_ALLOWLIST.has(projection.id)) fail("PROJECTION_EMPTY_NOT_ALLOWED:"+projection.id);
    if (rows.some(row=>!Array.isArray(row)||row.length!==projection.columns.length||row.some(cell=>typeof cell!=="string"))) fail("PROJECTION_ROW_SHAPE_INVALID:"+projection.id);
  }
  const unique=(id,key,code)=>{const seen=new Set();for(const row of p.get(id)){const value=key(row);if(seen.has(value))fail(code);seen.add(value);}};
  for (const row of p.get("relations_v1")) {
    if (!nonempty(row,[0,1,2,3,4,7,8,9]) || !["r","p","v","m","f"].includes(row[2])
      || !["p","u","t"].includes(row[4]) || !/^[1-9][0-9]*$/.test(row[7])
      || !bool(row[5]) || !bool(row[6]) || !bool(row[10])) fail("RELATIONS_PROJECTION_ROW_INVALID");
  }
  unique("relations_v1",r=>r[0]+"\0"+r[1]+"\0"+r[7],"RELATIONS_PROJECTION_DUPLICATED");
  for (const row of p.get("routines_v1")) {
    if (!nonempty(row,[0,1,2,5,6,9]) || !["f","p","a","w"].includes(row[2])
      || (row[2] !== "p" && !row[4]) || !bool(row[7]) || !bool(row[8]) || !["i","s","v"].includes(row[9])) fail("ROUTINES_PROJECTION_ROW_INVALID");
    let settings;try{settings=JSON.parse(row[10]);}catch{fail("ROUTINE_SETTINGS_INVALID");}
    if(!Array.isArray(settings)||settings.some(item=>!exact(item,["name","value"])||typeof item.name!=="string"||!item.name||typeof item.value!=="string"))fail("ROUTINE_SETTINGS_INVALID");
  }
  unique("routines_v1",r=>r[0]+"\0"+r[1]+"\0"+r[3],"ROUTINES_PROJECTION_DUPLICATED");
  const aclSpecs={
    relation_acl_v1:{grantee:4,grantor:5,privilege:6,grantable:7,allowed:RELATION_PRIVILEGES},
    schema_acl_v1:{grantee:2,grantor:3,privilege:4,grantable:5,allowed:SCHEMA_PRIVILEGES},
    routine_acl_v1:{grantee:3,grantor:4,privilege:5,grantable:6,allowed:new Set(["EXECUTE"])},
    sequence_acl_v1:{grantee:3,grantor:4,privilege:5,grantable:6,allowed:SEQUENCE_PRIVILEGES},
  };
  for(const [id,spec] of Object.entries(aclSpecs)){
    for(const row of p.get(id)){
      if(!bool(row[spec.grantable])||!nonempty(row,[spec.grantee,spec.grantor,spec.privilege])||!spec.allowed.has(row[spec.privilege]))fail("ACL_PROJECTION_ROW_INVALID:"+id);
      if(id==="relation_acl_v1"&&(!["relation","column"].includes(row[0])||!nonempty(row,[1,2])||(row[0]==="relation"&&row[3]!=="")||(row[0]==="column"&&!row[3])))fail("RELATION_ACL_ROW_INVALID");
      if(id==="schema_acl_v1"&&!nonempty(row,[0,1]))fail("SCHEMA_ACL_ROW_INVALID");
      if(id==="routine_acl_v1"&&!nonempty(row,[0,1]))fail("ROUTINE_ACL_ROW_INVALID");
      if(id==="sequence_acl_v1"&&!nonempty(row,[0,1,2]))fail("SEQUENCE_ACL_ROW_INVALID");
    }
    unique(id,r=>r.join("\0"),"ACL_PROJECTION_DUPLICATED:"+id);
  }
  for (const row of p.get("default_privileges_v1")) {
    const allowed=row[2]==="r"?RELATION_PRIVILEGES:row[2]==="S"?SEQUENCE_PRIVILEGES:row[2]==="f"?new Set(["EXECUTE"]):null;
    if(!nonempty(row,[0,1,2,3,4,5])||!allowed||!allowed.has(row[5])||!bool(row[6]))fail("DEFAULT_PRIVILEGES_ROW_INVALID");
  }
  unique("default_privileges_v1",r=>r.join("\0"),"DEFAULT_PRIVILEGES_DUPLICATED");
  const roles=p.get("roles_v1"),roleNames=new Set();
  for (const row of roles) {
    if (!nonempty(row,[0,8]) || row.slice(1,8).some((v) => !bool(v)) || !/^-?(0|[1-9][0-9]*)$/.test(row[8])
      || (row[9] !== "" && row[9] !== "infinity" && row[9] !== "-infinity" && !/^\d{4}-\d{2}-\d{2}(?:T| )\d{2}:\d{2}:\d{2}/.test(row[9]))) fail("ROLES_PROJECTION_ROW_INVALID");
    if(roleNames.has(row[0]))fail("ROLE_IDENTITY_DUPLICATED");roleNames.add(row[0]);
  }
  const memberships=new Set();
  for (const row of p.get("role_memberships_v1")) {
    if (!nonempty(row,[0,1,2]) || row.slice(3,6).some((v) => !bool(v))) fail("ROLE_MEMBERSHIPS_ROW_INVALID");
    const id=row.slice(0,3).join("\0");if(memberships.has(id))fail("ROLE_MEMBERSHIP_DUPLICATED");memberships.add(id);
  }
  for (const row of p.get("rls_policies_v1")) {
    if (!nonempty(row,[0,1,2,3,4,5]) || !["PERMISSIVE","RESTRICTIVE"].includes(row[3])
      || !/^\{.*\}$/.test(row[4]) || !["ALL","SELECT","INSERT","UPDATE","DELETE"].includes(row[5])) fail("RLS_POLICY_ROW_INVALID");
  }
  unique("rls_policies_v1",r=>r.slice(0,3).join("\0"),"RLS_POLICY_DUPLICATED");
  for (const row of p.get("constraints_v1")) if (!nonempty(row,[0,1,2,3,7]) || !["c","f","p","u","t","x"].includes(row[3]) || row.slice(4,7).some((v) => !bool(v))) fail("CONSTRAINT_ROW_INVALID");
  unique("constraints_v1",r=>r.slice(0,3).join("\0"),"CONSTRAINT_DUPLICATED");
  for (const row of p.get("indexes_v1")) if (!nonempty(row,[0,1,2,11]) || row.slice(3,11).some((v) => !bool(v))) fail("INDEX_ROW_INVALID");
  unique("indexes_v1",r=>r.slice(0,3).join("\0"),"INDEX_DUPLICATED");
  for (const row of p.get("triggers_v1")) if (!nonempty(row,[0,1,2,3,5]) || !["O","D","R","A"].includes(row[3]) || !bool(row[4])) fail("TRIGGER_ROW_INVALID");
  unique("triggers_v1",r=>r.slice(0,3).join("\0"),"TRIGGER_DUPLICATED");
  for (const row of p.get("sequences_v1")) {
    if (!nonempty(row,[0,1,2,3,4,5,6,7,8]) || row.slice(4,9).some((v) => !/^-?(0|[1-9][0-9]*)$/.test(v)) || !bool(row[9])
      || ([row[10],row[11],row[12]].some(Boolean)&&![row[10],row[11],row[12]].every(Boolean))) fail("SEQUENCE_ROW_INVALID");
  }
  unique("sequences_v1",r=>r[0]+"\0"+r[1],"SEQUENCE_DUPLICATED");
  for (const row of p.get("extensions_v1")) if (!nonempty(row,[0,1,2,3])) fail("EXTENSION_ROW_INVALID");
  unique("extensions_v1",r=>r[0],"EXTENSION_DUPLICATED");
  const identity=projectionObjects(p,"identity_v1");
  if(identity.length!==1)fail("IDENTITY_PROJECTION_CARDINALITY_INVALID");
  const sessionRoleName=identity[0].session_role;
  const effectiveRoleName=identity[0].current_role;
  if(sessionRoleName!=="deedlight_catalog_auditor")fail("COLLECTOR_ROLE_IDENTITY_MISMATCH");
  const collectorRoleNames=new Set([sessionRoleName,effectiveRoleName]);
  for(const roleName of collectorRoleNames){
    const collectorRoles=roles.filter(row=>row[0]===roleName);
    if(collectorRoles.length!==1)fail("COLLECTOR_ROLE_MISSING_OR_DUPLICATED");
    const role=collectorRoles[0];
    if(role[2]!=="f"||role[3]!=="f"||role[4]!=="f"||role[5]!=="f"||role[6]!=="f"||role[7]!=="f")fail("COLLECTOR_ROLE_PRIVILEGE_INVALID");
    if(roleName===sessionRoleName&&role[1]!=="t")fail("COLLECTOR_ROLE_PRIVILEGE_INVALID");
  }
  if(p.get("role_memberships_v1").some(row=>collectorRoleNames.has(row[1])))fail("COLLECTOR_ROLE_MEMBERSHIP_PRESENT");
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
function rawProjections(p){return SQL_PROJECTIONS.map(x=>({id:x.id,columns:[...x.columns],rows:p.get(x.id).map(row=>row.map(cell=>cell===CSV_QUOTED_EMPTY?"":cell))}));}
function authorityCandidate(p,identity,catalogObjects,receipt){
  const roleName=identity.current_role;
  const defaultAcl=projectionObjects(p,"default_privileges_v1");
  if(defaultAcl.some(row=>row[3]===roleName||row[3]==="PUBLIC"))fail("PRIVILEGE_DEFAULT_SCOPE_INVALID");
  const role=projectionObjects(p,"roles_v1").find(row=>row[0]===roleName);
  if(!role||identity.session_role!==roleName)fail("COLLECTOR_ROLE_IDENTITY_MISMATCH");
  const memberships=projectionObjects(p,"role_memberships_v1");
  if(memberships.length)fail("COLLECTOR_ROLE_MEMBERSHIP_PRESENT");
  const schemas=catalogObjects.filter(x=>x.kind==="schemas").map(x=>x.identity).sort();
  const schemaAcl=projectionObjects(p,"schema_acl_v1");
  const schemaPrivileges=schemas.map(schema=>{
    const rows=schemaAcl.filter(row=>row[0]===schema&&(row[2]===roleName||row[2]==="PUBLIC"));
    if(rows.some(row=>row[5]!=="f"))fail("PRIVILEGE_SCHEMA_GRANT_OPTION_INVALID");
    const privileges=[...new Set(rows.map(row=>row[4]))].sort();
    const expected=schema==="supabase_migrations"?["USAGE"]:[];
    if(canonicalJson(privileges)!==canonicalJson(expected))fail("PRIVILEGE_SCHEMA_SCOPE_INVALID:"+schema);
    return {schema,scope:schema==="supabase_migrations"?"migration_history":"application_data",privileges};
  });
  if(!schemas.includes("supabase_migrations"))fail("PRIVILEGE_MIGRATION_SCHEMA_MISSING");
  const relationAcl=projectionObjects(p,"relation_acl_v1"),routineAcl=projectionObjects(p,"routine_acl_v1"),sequenceAcl=projectionObjects(p,"sequence_acl_v1");
  const tables=catalogObjects.filter(x=>x.kind==="tables");
  const sequences=catalogObjects.filter(x=>x.kind==="sequences");
  const routines=catalogObjects.filter(x=>x.kind==="routines");
  const objectPrivileges=[];
  for(const item of [...tables,...sequences,...routines]){
    let rows=[];
    if(item.kind==="tables")rows=relationAcl.filter(r=>r[0]==="relation"&&r[1]+"."+r[2]===item.identity&&(r[4]===roleName||r[4]==="PUBLIC"));
    if(item.kind==="sequences")rows=sequenceAcl.filter(r=>r[0]+"."+r[1]===item.identity&&(r[3]===roleName||r[3]==="PUBLIC"));
    if(item.kind==="routines"){
      const source=projectionObjects(p,"routines_v1").find(r=>r[0]+"."+r[1]+"("+r[3]+")"===item.identity);
      rows=source?routineAcl.filter(r=>r[0]===source[0]&&r[1]===source[1]&&r[2]===source[3]&&(r[3]===roleName||r[3]==="PUBLIC")):[];
    }
    if(rows.some(r=>r.at(-1)!=="f"))fail("PRIVILEGE_OBJECT_GRANT_OPTION_INVALID:"+item.identity);
    const privilegeIndex=item.kind==="tables"?6:5;
    const privileges=[...new Set(rows.map(r=>r[privilegeIndex]))].sort();
    const history=item.kind==="tables"&&item.identity==="supabase_migrations.schema_migrations";
    const expected=history?["SELECT"]:[];
    if(canonicalJson(privileges)!==canonicalJson(expected))fail("PRIVILEGE_OBJECT_SCOPE_INVALID:"+item.identity);
    objectPrivileges.push({kind:item.kind,identity:item.identity,scope:history?"migration_history":"application_data",privileges});
  }
  const columns=catalogObjects.filter(x=>x.kind==="columns");
  const columnPrivileges=[];
  for(const item of columns){
    const source=projectionObjects(p,"relations_v1").find(r=>r[0]+"."+r[1]+"."+r[8]===item.identity);
    if(!source)fail("PRIVILEGE_COLUMN_IDENTITY_INVALID:"+item.identity);
    const history=source[0]==="supabase_migrations"&&source[1]==="schema_migrations";
    const table=objectPrivileges.find(x=>x.kind==="tables"&&x.identity===source[0]+"."+source[1]);
    const rows=relationAcl.filter(r=>r[0]==="column"&&r[1]===source[0]&&r[2]===source[1]&&r[3]===source[8]&&(r[4]===roleName||r[4]==="PUBLIC"));
    if(rows.some(r=>r[7]!=="f"))fail("PRIVILEGE_COLUMN_GRANT_OPTION_INVALID:"+item.identity);
    const privileges=[...new Set([...(table?.privileges??[]),...rows.map(r=>r[6])])].sort();
    const expected=history?["SELECT"]:[];
    if(canonicalJson(privileges)!==canonicalJson(expected))fail("PRIVILEGE_COLUMN_SCOPE_INVALID:"+item.identity);
    columnPrivileges.push({identity:item.identity,scope:history?"migration_history":"application_data",privileges});
  }
  const databaseRows=projectionObjects(p,"database_acl_v1");
  const currentDatabase=databaseRows.filter(row=>row[3]===identity.database_name);
  if(currentDatabase.length!==1)fail("PRIVILEGE_CURRENT_DATABASE_MISSING");
  const databaseEdges=JSON.parse(currentDatabase[0][10]);
  const effectiveDatabaseEdges=databaseEdges.filter(edge=>edge.grantee_name===roleName||edge.grantee_name==="PUBLIC");
  if(effectiveDatabaseEdges.some(edge=>edge.is_grantable))fail("PRIVILEGE_DATABASE_GRANT_OPTION_INVALID");
  const databasePrivileges=[...new Set(effectiveDatabaseEdges.map(edge=>edge.privilege_type))].sort();
  if(canonicalJson(databasePrivileges)!==canonicalJson(["CONNECT"]))fail("PRIVILEGE_DATABASE_SCOPE_INVALID");
  const ownedSchemas=[...new Set(schemaAcl.filter(row=>row[1]===roleName).map(row=>row[0]))].sort();
  const ownedRelations=projectionObjects(p,"relations_v1").some(row=>row[3]===roleName);
  const ownedRoutines=projectionObjects(p,"routines_v1").some(row=>row[6]===roleName);
  const ownedSequences=projectionObjects(p,"sequences_v1").some(row=>row[2]===roleName);
  if(ownedSchemas.length||ownedRelations||ownedRoutines||ownedSequences)fail("COLLECTOR_OWNS_APPLICATION_OBJECTS");
  const databaseAclV1=databaseRows.map(row=>({
    acl_expansion_source:row[9],allows_connections:row[4]==="t",database_count:Number(row[1]),database_name:row[3],database_oid:Number(row[2]),
    datacl_was_null:row[8]==="t",expanded_acl_edges:JSON.parse(row[10]).map(edge=>({...edge,grantee_oid:Number(edge.grantee_oid),grantor_oid:Number(edge.grantor_oid)})),
    is_template:row[5]==="t",owner_name:row[7],owner_oid:Number(row[6]),
  }));
  return {status:"UNAUTHENTICATED_CANDIDATE",declaredContract:"catalog_only_v1",authenticated:false,
    privilegeContractVersion:"catalog_only_v1",requiredAccessSummary:[...REQUIRED_ACCESS_SUMMARY],
    databaseRole:roleName,isSuperuser:role[2]==="t",canCreateDatabase:role[3]==="t",canCreateRole:role[4]==="t",
    isReplication:role[5]==="t",bypassRls:role[6]==="t",ownsObjects:false,
    databasePrivileges,catalogPrivileges:["SELECT"],schemaPrivileges,objectPrivileges,columnPrivileges,
    roleMemberships:memberships,ownedSchemas,proofQueryBundleSha256:receipt.source.sqlBundleSha256,databaseAclV1,
    effectiveRole:identity.current_role,sessionRole:identity.session_role,roles:projectionObjects(p,"roles_v1"),
    privilegeProjections:Object.fromEntries(ACL_IDS.map(id=>[id,projectionObjects(p,id)])),databaseAcl:projectionObjects(p,"database_acl_v1")};
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
  const identityRows=projectionObjects(p,"identity_v1");
  if(identityRows.length!==1)fail("IDENTITY_PROJECTION_CARDINALITY_INVALID");
  const identityRow=identityRows[0];
  if(identityRow.expected_project_ref!==PROJECT_REF||receipt?.projectRef!==PROJECT_REF)fail("PROVENANCE_PROJECT_IDENTITY_MISMATCH");
  if(typeof receipt?.endpoint?.database!=="string"||!receipt.endpoint.database.trim()
    ||identityRow.database_name!==receipt.endpoint.database)fail("PROVENANCE_DATABASE_IDENTITY_MISMATCH");
  if(!hex(receipt?.source?.repositoryCommitSha,40)||identityRow.repository_sha!==receipt.source.repositoryCommitSha)fail("PROVENANCE_REPOSITORY_IDENTITY_MISMATCH");
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
  const catalogObjects=buildCatalog(p);
  const environment=receipt.endpoint.database==="postgres"?"production":"test";
  const evidence={schemaVersion:2,
    provenance:{environment,projectRef:PROJECT_REF,capturedAt,collectorIdentity:receipt.execution.collectorId,queryBundleSha256:receipt.source.sqlBundleSha256},
    history:{complete:true,rows:validation.migrationHistoryRows},
    catalog:{complete:false,completeKinds:[...CATALOG_KINDS],objects:catalogObjects}};
  if(normalizedMapping)evidence.mapping=normalizedMapping;
  return {schemaVersion:1,status:"UNSIGNED_NOT_ACCEPTED",acceptance:"NOT_ACCEPTED",adapter:"deedlight-collector-analyzer-adapter-v1",
    receipt,databaseCaptureTimestamp,evidence,databaseAuthorityCandidate:authorityCandidate(p,identityRow,catalogObjects,receipt),
    unmappedCatalogEvidence:{extensions_v1:{status:"PRESERVED_NOT_NORMALIZED",rows:projectionObjects(p,"extensions_v1")}},projections:rawProjections(p),
    integrity:{receiptCanonicalSha256:sha256(Buffer.from(canonicalJson(receipt),"utf8")),
      receiptSchemaGitBlobSha1:RECEIPT_SCHEMA_GIT_BLOB_SHA1,receiptSchemaSha256:RECEIPT_SCHEMA_SHA256,
      migrationInventoryGitBlobSha1:INVENTORY_GIT_BLOB_SHA1,repositoryCommitSha:receipt.source.repositoryCommitSha,sqlBundlePath:SQL_PATH,sqlBundleGitBlobSha1:SQL_GIT_BLOB_SHA1,
      sqlBundleSha256:SQL_SHA256,csvSha256:receipt.evidence.sha256,canonicalResultSha256:receipt.execution.canonicalResultSha256,
      normalizedEvidenceSha256:sha256(Buffer.from(canonicalJson(evidence),"utf8"))},
    signing:{state:"NOT_SIGNED",authenticated:false},
    blockers:["Collector receipt is explicitly unsigned and cannot authenticate evidence.",
      "Catalog projections do not attest data transformations, backfills, dependencies, preconditions or postconditions.",
      "extensions_v1 is preserved but the analyzer catalog schema has no extensions kind; it remains explicitly unmapped.",
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
