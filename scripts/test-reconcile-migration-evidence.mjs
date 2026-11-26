import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { analyzeMigrationEvidence, canonicalJson, evidencePayload, mappingDigest } from "./reconcile-migration-evidence.mjs";

const repoRoot = process.cwd();
const sourceManifest = JSON.parse(readFileSync(path.join(repoRoot, "supabase/migration-inventory.json"), "utf8"));
const sourceInventoryBytes = readFileSync(path.join(repoRoot, "supabase/migration-inventory.json"));
const catalogKinds = ["schemas", "tables", "sequences", "columns", "constraints", "indexes", "triggers", "policies", "routines", "privileges", "ownership", "dataTransformations", "backfills", "dependencies", "preconditions", "postconditions"];
const categories = ["schema", "privileges", "ownership", "routines", "dataTransformations", "backfills", "dependencies", "preconditions", "postconditions"];
const hash = (value) => createHash("sha256").update(value).digest("hex");
const keys = Object.fromEntries(["evidence-approver", "mapping-approver", "collector"].map((role) => [role, generateKeyPairSync("ed25519")]));
const signerIds = { "evidence-approver": "fixture-evidence-authority", "mapping-approver": "fixture-mapping-authority", collector: "fixture-collector-authority" };
const fixtureTime = (offsetMs = 0) => new Date(Date.now() + offsetMs).toISOString();
const FIXTURE_CAPTURED_AT = fixtureTime(-30 * 60 * 1000);
const FIXTURE_APPROVED_AT = fixtureTime(-29 * 60 * 1000);
const FIXTURE_EXPIRES_AT = fixtureTime(6 * 60 * 60 * 1000);
const FIXTURE_EXECUTION_STARTED_AT = fixtureTime(-40 * 60 * 1000);
const FIXTURE_EXECUTION_COMPLETED_AT = fixtureTime(-35 * 60 * 1000);
const FIXTURE_HISTORY_EXECUTED_AT = fixtureTime(-90 * 60 * 1000);

function artifact(kind, role, claims, overrides = {}) {
  const now = FIXTURE_APPROVED_AT;
  const unsigned = {
    schemaVersion: 1,
    kind,
    signerId: signerIds[role],
    keyId: role + "-key-1",
    approvalId: role + "-approval-1",
    issuedAt: now,
    expiresAt: FIXTURE_EXPIRES_AT,
    claims,
    ...overrides,
  };
  return {
    ...unsigned,
    signature: sign(null, Buffer.from(canonicalJson(unsigned)), keys[role].privateKey).toString("base64"),
  };
}
function fixture() {
  const rootDir = mkdtempSync(path.join(os.tmpdir(), "deedlight-reconcile-repo-"));
  const trustDir = mkdtempSync(path.join(os.tmpdir(), "deedlight-reconcile-trust-"));
  mkdirSync(path.join(rootDir, "supabase/migrations"), { recursive: true });
  writeFileSync(path.join(rootDir, "supabase/migration-inventory.json"), sourceInventoryBytes);
  for (const item of sourceManifest.migrations) copyFileSync(path.join(repoRoot, item.path), path.join(rootDir, item.path));

  const migrationEffects = sourceManifest.migrations.map((item, index) => {
    const schemaEffect = {
      kind: index % 2 ? "columns" : "tables",
      identity: "fixture.schema." + index,
      fingerprint: hash("schema:" + index),
      description: "Exact schema definition and structural attributes",
    };
    const dataEffect = {
      kind: "backfills",
      identity: "fixture.backfill." + index,
      fingerprint: hash("backfill:" + index),
      description: "Backfill transformation and postcondition evidence",
    };
    const effects = {
      schema: [schemaEffect],
      privileges: [],
      ownership: [],
      routines: [],
      dataTransformations: [{
        kind: "dataTransformations",
        identity: "fixture.transform." + index,
        fingerprint: hash("transform:" + index),
        description: "Data transformation with exact source and result invariants",
      }],
      backfills: [dataEffect],
      dependencies: [],
      preconditions: [],
      postconditions: [],
    };
    const lineCount = readFileSync(path.join(repoRoot, item.path), "utf8").split(String.fromCharCode(10)).length;
    const coverage = Object.fromEntries(categories.map((category) => [category, {
      disposition: effects[category].length ? "effects" : "none",
      rationale: effects[category].length
        ? "Synthetic fixture maps a representative " + category + " effect to the pinned migration source range."
        : "Synthetic fixture explicitly records no " + category + " effect in the pinned migration source range.",
      sourceRanges: [{ startLine: 1, endLine: lineCount }],
    }]));
    return { path: item.path, blobSha1: item.blobSha1, effects, coverage };
  });
  const mapping = { schemaVersion: 1, migrations: migrationEffects };
  const expected = migrationEffects.flatMap((entry) => categories.flatMap((category) => entry.effects[category]));
  const catalog = [
    ...expected.map((effect) => ({ kind: effect.kind, identity: effect.identity, fingerprint: effect.fingerprint })),
    { kind: "schemas", identity: "public", fingerprint: hash("schema:public") },
    { kind: "tables", identity: "public.profiles", fingerprint: hash("table:public.profiles") },
  ];
  const historyRows = [];
  const byVersion = new Map();
  for (const item of sourceManifest.migrations) {
    if (!byVersion.has(item.version)) byVersion.set(item.version, item);
  }
  for (const [version, item] of byVersion) {
    historyRows.push({
      version,
      name: path.basename(item.path).replace(/^\d{12}_/, "").replace(/\.sql$/, ""),
      sourceBlobSha1: item.blobSha1,
      executedAt: FIXTURE_HISTORY_EXECUTED_AT,
      executedBy: "supabase_migration_runner",
      executionId: "fixture-execution-" + version,
    });
  }
  const evidence = {
    schemaVersion: 2,
    provenance: {
      environment: "production",
      projectRef: "xaipiovflxomcbfwtwmu",
      capturedAt: FIXTURE_CAPTURED_AT,
      collectorIdentity: "fixture-read-only-exporter",
      queryBundleSha256: hash("reviewed-read-only-query-bundle"),
    },
    history: { complete: true, rows: historyRows },
    catalog: { complete: true, completeKinds: [...catalogKinds], objects: catalog },
    mapping,
  };
  const trustRoots = {
    schemaVersion: 1,
    revokedApprovalIds: [],
    keys: Object.entries(keys).map(([role, pair]) => ({
      keyId: role + "-key-1",
      signerId: signerIds[role],
      role,
      algorithm: "Ed25519",
      status: "active",
      publicKeyPem: pair.publicKey.export({ type: "spki", format: "pem" }).toString(),
      notBefore: "2026-01-01T00:00:00.000Z",
      notAfter: "2027-01-01T00:00:00.000Z",
      revokedAt: null,
    })),
  };
  const f = {
    rootDir,
    trustDir,
    evidence,
    mapping,
    trustRoots,
    cleanup() {
      rmSync(rootDir, { recursive: true, force: true });
      rmSync(trustDir, { recursive: true, force: true });
    },
    reapprove(mutateDatabaseAuthority, mutateExecutionEvidence) {
      const mapHash = mappingDigest(mapping);
      const common = {
        projectRef: "xaipiovflxomcbfwtwmu",
        queryBundleSha256: evidence.provenance.queryBundleSha256,
        collectorIdentity: evidence.provenance.collectorIdentity,
        capturedAt: evidence.provenance.capturedAt,
      };
      const databaseAuthority = {
        databaseRole: "deedlight_readonly_auditor",
        isSuperuser: false,
        canCreateRole: false,
        canCreateDatabase: false,
        bypassRls: false,
        isReplication: false,
        ownsObjects: false,
        effectivePrivileges: ["CONNECT", "USAGE", "SELECT"],
        databasePrivilegesComplete: true,
        databasePrivileges: ["CONNECT"],
        databaseAclV1: [{
          database_count: 1,
          database_oid: 100,
          database_name: "deedlight_fixture",
          allows_connections: true,
          is_template: false,
          owner_oid: 10,
          owner_name: "postgres",
          datacl_was_null: false,
          acl_expansion_source: "explicit",
          expanded_acl_edges: [{
            grantee_oid: 10,
            grantee_name: "postgres",
            grantor_oid: 10,
            grantor_name: "postgres",
            privilege_type: "CONNECT",
            is_grantable: true,
          }],
        }],
        schemaPrivilegesComplete: true,
        schemaPrivileges: evidence.catalog.objects.filter((entry) => entry.kind === "schemas")
          .map((entry) => ({ schema: entry.identity, privileges: ["USAGE"] })),
        objectPrivilegesComplete: true,
        objectPrivileges: evidence.catalog.objects.filter((entry) => ["tables", "sequences", "routines"].includes(entry.kind))
          .map((entry) => ({
            kind: entry.kind,
            identity: entry.identity,
            privileges: entry.kind === "routines" ? [] : ["SELECT"],
          })),
        catalogPrivilegesComplete: true,
        catalogPrivileges: ["SELECT"],
        roleMemberships: [],
        ownedSchemas: [],
        proofQueryBundleSha256: evidence.provenance.queryBundleSha256,
      };
      if (mutateDatabaseAuthority) mutateDatabaseAuthority(databaseAuthority);
      const executionId = "fixture-collector-query-execution";
      const executionEvidence = {
        projectRef: common.projectRef,
        collectorIdentity: common.collectorIdentity,
        capturedAt: common.capturedAt,
        queryBundleSha256: common.queryBundleSha256,
        executionId,
        startedAt: FIXTURE_EXECUTION_STARTED_AT,
        completedAt: FIXTURE_EXECUTION_COMPLETED_AT,
        completed: true,
        readOnlyTransaction: true,
        statementCount: 4,
        resultDigest: hash(Buffer.from(canonicalJson({
          history: evidence.history,
          catalog: evidence.catalog,
          databaseAuthority,
        }))),
      };
      if (mutateExecutionEvidence) mutateExecutionEvidence(executionEvidence);
      evidence.collectorAuthority = {
        schemaVersion: 1,
        projectRef: common.projectRef,
        collectorIdentity: common.collectorIdentity,
        capturedAt: common.capturedAt,
        queryBundleSha256: common.queryBundleSha256,
        executionId,
        completed: true,
        readOnlyTransaction: true,
        databaseAuthority,
        executionEvidence,
      };
      const evidenceDigest = hash(evidencePayload(evidence));
      const authorityEvidenceDigest = hash(Buffer.from(canonicalJson(evidence.collectorAuthority)));
      f.approvals = {
        evidenceApproval: artifact("production-evidence-approval", "evidence-approver", {
          ...common,
          evidenceDigest,
          mappingDigest: mapHash,
        }),
        mappingApproval: artifact("migration-mapping-approval", "mapping-approver", {
          projectRef: "xaipiovflxomcbfwtwmu",
          mappingDigest: mapHash,
          inventoryBlobSha1: "95d514a0bd97ff448c9507252eb1f5e69a507442",
          migrationCount: 39,
          versionCount: 38,
        }),
        collectorAttestation: artifact("read-only-collector-attestation", "collector", {
          ...common,
          evidenceDigest,
          authorityEvidenceDigest,
          executionId,
          databaseAuthority,
        }),
      };
      return f.approvals;
    },
    analyze(overrides = {}) {
      const inputs = f.writeCurrentInputs();
      const script = path.join(repoRoot, "scripts/reconcile-migration-evidence.mjs");
      const args = [
        "--evidence=" + inputs.evidencePath,
        "--approvals=" + inputs.approvalsPath,
        "--trust-roots=" + inputs.rootsPath,
        "--mode=accept",
      ];
      const trustedTrustRootsSha256 = overrides.trustedTrustRootsSha256 || inputs.rootsDigest;
      const result = spawnSync(process.execPath, [script, ...args], {
        cwd: rootDir,
        encoding: "utf8",
        env: { ...process.env, DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256: trustedTrustRootsSha256 },
      });
      assert.ok(result.stdout, result.stderr || "analyzer CLI did not produce a report");
      return JSON.parse(result.stdout);
    },
    writeCurrentInputs() {
      const evidencePath = path.join(trustDir, "evidence.json");
      const approvalsPath = path.join(trustDir, "approvals.json");
      const rootsPath = path.join(trustDir, "trust-roots.json");
      writeFileSync(evidencePath, JSON.stringify(evidence));
      writeFileSync(approvalsPath, JSON.stringify(f.approvals));
      writeFileSync(rootsPath, JSON.stringify(trustRoots));
      return { evidencePath, approvalsPath, rootsPath, rootsDigest: hash(Buffer.from(canonicalJson(trustRoots))) };
    },
    writeCliInputs() {
      f.reapprove();
      return f.writeCurrentInputs();
    },
  };
  f.reapprove();
  return f;
}

test("verifies signed approvals and collector authority; duplicate 007 remains explicitly ambiguous", () => {
  const f = fixture();
  try {
    const report = f.analyze();
    assert.equal(report.trustVerified, true);
    assert.equal(report.sourceInventory.migrationCount, 39);
    assert.equal(report.sourceInventory.uniqueVersionCount, 38);
    const duplicate = report.classifications.filter((item) => item.version === "202607260007");
    assert.equal(duplicate.length, 2);
    assert.ok(duplicate.every((item) => item.status === "Schema represented but history ambiguous"));
    assert.ok(duplicate.every((item) => item.exactExecutionEstablished === false));
    assert.equal(report.counts["Applied and verified"], 37);
    assert.equal(report.acceptance, "NOT_ACCEPTED");
    assert.equal(report.mutationPerformed, false);
  } finally { f.cleanup(); }
});

test("signed artifacts with missing claims or unsigned extra approval references fail closed", () => {
  for (const mutate of [
    (f) => { f.approvals.evidenceApproval = artifact("production-evidence-approval", "evidence-approver", undefined); },
    (f) => { f.approvals.mappingApproval = artifact("migration-mapping-approval", "mapping-approver", undefined); },
    (f) => { f.approvals.collectorAttestation = artifact("read-only-collector-attestation", "collector", undefined); },
    (f) => { f.approvals.evidenceApproval.untrustedApprovalReference = "arbitrary-reference"; },
  ]) {
    const f = fixture();
    try {
      mutate(f);
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.equal(report.acceptance, "NOT_ACCEPTED");
      assert.ok(report.trustProblems.some((reason) => reason.includes("missing claims") || reason.includes("unsupported envelope")));
    } finally { f.cleanup(); }
  }
});

test("unsigned approval envelope is rejected before signature verification", () => {
  const f = fixture();
  try {
    delete f.approvals.evidenceApproval.signature;
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.equal(report.acceptance, "NOT_ACCEPTED");
    assert.ok(report.trustProblems.some((reason) => reason.includes("missing claims or an unsupported envelope")));
  } finally { f.cleanup(); }
});

test("forged approval signature fails cryptographic verification", () => {
  const f = fixture();
  try {
    f.approvals.evidenceApproval.signature = Buffer.alloc(64).toString("base64");
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.equal(report.acceptance, "NOT_ACCEPTED");
    assert.ok(report.trustProblems.some((reason) => reason.includes("signature verification failed")));
  } finally { f.cleanup(); }
});

test("expired approval, revoked signer key and revoked approval ID fail closed", () => {
  const changes = [
    (f) => {
      const claims = f.approvals.evidenceApproval.claims;
      f.approvals.evidenceApproval = artifact("production-evidence-approval", "evidence-approver", claims, { expiresAt: fixtureTime(-60 * 1000) });
    },
    (f) => { f.trustRoots.keys.find((key) => key.role === "evidence-approver").revokedAt = fixtureTime(-60 * 1000); },
    (f) => { f.trustRoots.revokedApprovalIds.push(f.approvals.evidenceApproval.approvalId); },
    (f) => { f.approvals.evidenceApproval.signerId = "untrusted-signer"; },
  ];
  for (const change of changes) {
    const f = fixture();
    try {
      change(f);
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.equal(report.acceptance, "NOT_ACCEPTED");
    } finally { f.cleanup(); }
  }
});

test("approval claims are bound to exact project, evidence, mapping, query, collector and capture timestamp", () => {
  const f = fixture();
  try {
    const claims = f.approvals.evidenceApproval.claims;
    f.approvals.evidenceApproval = artifact("production-evidence-approval", "evidence-approver", { ...claims, collectorIdentity: "forged-collector" });
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("signed evidence approval does not bind the exact evidence")));
  } finally { f.cleanup(); }
});

test("mapping digest alteration after signed mapping approval fails closed", () => {
  const f = fixture();
  try {
    f.mapping.migrations[0].effects.backfills[0].description = "altered backfill";
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("signed evidence approval")));
    assert.ok(report.trustProblems.some((reason) => reason.includes("signed mapping approval")));
  } finally { f.cleanup(); }
});

test("plausible mapping with missing effect domains cannot be approved into Applied", () => {
  const f = fixture();
  try {
    delete f.mapping.migrations[0].effects.preconditions;
    f.reapprove();
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("omits, or adds unsupported, effect domains")));
  } finally { f.cleanup(); }
});

test("mapping requires source-linked review disposition for every effect domain", () => {
  for (const mutate of [
    (f) => { delete f.mapping.migrations[0].coverage.privileges; },
    (f) => { f.mapping.migrations[0].coverage.privileges.rationale = ""; },
    (f) => { f.mapping.migrations[0].coverage.schema.sourceRanges = []; },
    (f) => { f.mapping.migrations[0].coverage.privileges.disposition = "effects"; },
  ]) {
    const f = fixture();
    try {
      mutate(f);
      f.reapprove();
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.equal(report.acceptance, "NOT_ACCEPTED");
      assert.ok(report.trustProblems.some((reason) => reason.includes("reviewed coverage disposition") || reason.includes("source-linked coverage review")));
    } finally { f.cleanup(); }
  }
});

test("collector authority must be present and cryptographically bound to the exact query execution and evidence", () => {
  for (const mutate of [
    (f) => { delete f.evidence.collectorAuthority; },
    (f) => { f.evidence.collectorAuthority.databaseAuthority.canCreateRole = true; },
    (f) => { f.evidence.collectorAuthority.executionId = "substituted-execution"; },
    (f) => { f.approvals.collectorAttestation.claims.authorityEvidenceDigest = hash("unrelated"); },
  ]) {
    const f = fixture();
    try {
      mutate(f);
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.equal(report.acceptance, "NOT_ACCEPTED");
      assert.ok(report.trustProblems.some((reason) => reason.includes("collector") || reason.includes("privilege-query")));
    } finally { f.cleanup(); }
  }
});

test("one Ed25519 public key cannot impersonate multiple independent approval authorities", () => {
  const f = fixture();
  try {
    f.trustRoots.keys[1].publicKeyPem = f.trustRoots.keys[0].publicKeyPem;
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("reuses one public key")));
  } finally { f.cleanup(); }
});

test("mapping must account for schema, privileges, ownership, routines, data, dependencies and lifecycle assertions", () => {
  const f = fixture();
  try {
    for (const category of categories) assert.ok(Array.isArray(f.mapping.migrations[0].effects[category]));
    f.mapping.migrations[0].effects.ownership.push({
      kind: "ownership", identity: "fixture.owner", fingerprint: hash("owner"),
      description: "Owner role and grants",
    });
    f.mapping.migrations[0].coverage.ownership.disposition = "effects";
    f.mapping.migrations[0].coverage.ownership.rationale = "Synthetic fixture explicitly maps ownership effects to the pinned migration source range.";
    f.reapprove();
    const report = f.analyze();
    assert.equal(report.trustVerified, true);
    assert.equal(report.classifications[0].status, "Partial or drifted");
    assert.equal(report.acceptance, "NOT_ACCEPTED");
  } finally { f.cleanup(); }
});

test("write-capable collector, inherited roles or unproven read-only privilege flags fail closed", () => {
  for (const mutate of [
    (f) => {
      const claims = f.approvals.collectorAttestation.claims;
      f.approvals.collectorAttestation = artifact("read-only-collector-attestation", "collector", {
        ...claims, databaseAuthority: { ...claims.databaseAuthority, canCreateRole: true },
      });
    },
    (f) => {
      const claims = f.approvals.collectorAttestation.claims;
      f.approvals.collectorAttestation = artifact("read-only-collector-attestation", "collector", {
        ...claims, databaseAuthority: { ...claims.databaseAuthority, roleMemberships: ["service_role"] },
      });
    },
    (f) => {
      const claims = f.approvals.collectorAttestation.claims;
      f.approvals.collectorAttestation = artifact("read-only-collector-attestation", "collector", {
        ...claims, databaseAuthority: { ...claims.databaseAuthority, effectivePrivileges: ["CONNECT", "USAGE", "SELECT", "UPDATE"] },
      });
    },
    (f) => {
      const claims = f.approvals.collectorAttestation.claims;
      f.approvals.collectorAttestation = artifact("read-only-collector-attestation", "collector", {
        ...claims, databaseAuthority: { ...claims.databaseAuthority, bypassRls: undefined },
      });
    },
    (f) => {
      const claims = f.approvals.collectorAttestation.claims;
      f.approvals.collectorAttestation = artifact("read-only-collector-attestation", "collector", {
        ...claims, databaseAuthority: {
          ...claims.databaseAuthority,
          objectPrivileges: [{ identity: "public.profiles", privileges: ["SELECT", "UPDATE"] }],
        },
      });
    },
    (f) => {
      const claims = f.approvals.collectorAttestation.claims;
      f.approvals.collectorAttestation = artifact("read-only-collector-attestation", "collector", {
        ...claims, databaseAuthority: {
          ...claims.databaseAuthority,
          schemaPrivileges: [{ schema: "public", privileges: ["USAGE", "CREATE"] }],
        },
      });
    },
    (f) => {
      const claims = f.approvals.collectorAttestation.claims;
      f.approvals.collectorAttestation = artifact("read-only-collector-attestation", "collector", {
        ...claims, databaseAuthority: { ...claims.databaseAuthority, objectPrivilegesComplete: false },
      });
    },
  ]) {
    const f = fixture();
    try {
      mutate(f);
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.equal(report.acceptance, "NOT_ACCEPTED");
    } finally { f.cleanup(); }
  }
});

test("self-declared completeness booleans do not replace signed catalog identity evidence", () => {
  const f = fixture();
  try {
    f.evidence.history.complete = false;
    f.evidence.catalog.complete = false;
    f.reapprove((db) => {
      db.databasePrivilegesComplete = false;
      db.schemaPrivilegesComplete = false;
      db.objectPrivilegesComplete = false;
      db.catalogPrivilegesComplete = false;
    });
    const report = f.analyze();
    assert.equal(report.trustVerified, true);
    assert.equal(report.acceptance, "NOT_ACCEPTED");
    assert.equal(report.counts.Unknown, 0);
  } finally { f.cleanup(); }
});

test("catalog completeness dimensions reject omissions, duplicates and unsupported kinds", () => {
  for (const mutate of [
    (f) => { f.evidence.catalog.completeKinds.pop(); },
    (f) => { f.evidence.catalog.completeKinds.push(f.evidence.catalog.completeKinds[0]); },
    (f) => { f.evidence.catalog.completeKinds[0] = "unreviewed_catalog_kind"; },
  ]) {
    const f = fixture();
    try {
      mutate(f);
      f.reapprove();
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.ok(report.trustProblems.some((reason) => reason.includes("catalog completeness dimensions")));
    } finally { f.cleanup(); }
  }
});

test("collector schema and object privilege identity sets must exactly match catalog inventory", () => {
  const mutations = [
    (db) => { db.schemaPrivileges = []; },
    (db) => { db.schemaPrivileges.push({ schema: "private_extra", privileges: ["USAGE"] }); },
    (db) => { db.schemaPrivileges.push({ ...db.schemaPrivileges[0] }); },
    (db) => { db.objectPrivileges = db.objectPrivileges.slice(1); },
    (db) => { db.objectPrivileges[0].kind = db.objectPrivileges[0].kind === "tables" ? "sequences" : "tables"; },
    (db) => { db.objectPrivileges.push({ kind: "tables", identity: "public.unexpected", privileges: ["SELECT"] }); },
    (db) => { db.objectPrivileges.push({ ...db.objectPrivileges[0] }); },
  ];
  for (const mutate of mutations) {
    const f = fixture();
    try {
      f.reapprove(mutate);
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.equal(report.acceptance, "NOT_ACCEPTED");
      assert.ok(report.trustProblems.some((reason) => reason.includes("privilege identities do not exactly match")));
    } finally { f.cleanup(); }
  }
});

test("complete database_acl_v1 projection is mandatory and included in the signed result digest", () => {
  const missing = fixture();
  try {
    delete missing.evidence.collectorAuthority;
    missing.reapprove((databaseAuthority) => { delete databaseAuthority.databaseAclV1; });
    const report = missing.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("complete database_acl_v1 projection is missing")));
  } finally { missing.cleanup(); }

  const malformed = fixture();
  try {
    malformed.reapprove((databaseAuthority) => {
      databaseAuthority.databaseAclV1[0].expanded_acl_edges[0].grantee_name = "PUBLIC";
    });
    const report = malformed.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("malformed ACL edge")));
  } finally { malformed.cleanup(); }

  const duplicated = fixture();
  try {
    duplicated.reapprove((databaseAuthority) => {
      databaseAuthority.databaseAclV1[0].expanded_acl_edges.push({
        ...databaseAuthority.databaseAclV1[0].expanded_acl_edges[0],
      });
    });
    const report = duplicated.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("repeats an ACL edge")));
  } finally { duplicated.cleanup(); }

  const tampered = fixture();
  try {
    tampered.reapprove();
    tampered.evidence.collectorAuthority.databaseAuthority.databaseAclV1[0].database_name = "tampered";
    const report = tampered.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("execution receipt")
      || reason.includes("signed collector authority differs")
      || reason.includes("signed evidence approval does not bind the exact evidence")));
  } finally { tampered.cleanup(); }

  const truncated = fixture();
  try {
    truncated.reapprove((databaseAuthority) => {
      databaseAuthority.databaseAclV1.push({
        ...databaseAuthority.databaseAclV1[0],
        database_oid: 101,
        database_name: "omitted_database",
      });
    });
    const report = truncated.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("incomplete, malformed or unordered database row")));
  } finally { truncated.cleanup(); }
});

test("collector execution receipt binds project, collector, query digest, capture and result", () => {
  for (const mutate of [
    (e) => { e.queryBundleSha256 = hash("wrong-query"); },
    (e) => { e.projectRef = "other-project"; },
    (e) => { e.collectorIdentity = "other-collector"; },
    (e) => { e.completedAt = fixtureTime(-20 * 60 * 1000); },
    (e) => { e.resultDigest = hash("wrong-result"); },
    (e) => { e.statementCount = 0; },
  ]) {
    const f = fixture();
    try {
      f.reapprove(undefined, mutate);
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.equal(report.acceptance, "NOT_ACCEPTED");
      assert.ok(report.trustProblems.some((reason) => reason.includes("execution receipt")));
    } finally { f.cleanup(); }
  }
});

test("migration execution timestamps cannot be later than capture or current time", () => {
  for (const executedAt of [fixtureTime(-29 * 60 * 1000), fixtureTime(60 * 1000)]) {
    const f = fixture();
    try {
      f.evidence.history.rows[0].executedAt = executedAt;
      f.reapprove();
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.ok(report.trustProblems.some((reason) => reason.includes("executedAt <= evidence capturedAt <= current time")));
    } finally { f.cleanup(); }
  }
});

test("malformed collector execution receipts fail closed", () => {
  for (const mutate of [
    (receipt) => { delete receipt.resultDigest; },
    (receipt) => { receipt.statementCount = "4"; },
    (receipt) => { receipt.startedAt = "not-a-timestamp"; },
    (receipt) => { receipt.completedAt = fixtureTime(-20 * 60 * 1000); },
  ]) {
    const f = fixture();
    try {
      f.reapprove(undefined, mutate);
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.equal(report.acceptance, "NOT_ACCEPTED");
      assert.ok(report.trustProblems.some((reason) => reason.includes("execution receipt")));
    } finally { f.cleanup(); }
  }
});

test("collector attestation must bind the exact project and query bundle", () => {
  const f = fixture();
  try {
    const claims = f.approvals.collectorAttestation.claims;
    f.approvals.collectorAttestation = artifact("read-only-collector-attestation", "collector", {
      ...claims, queryBundleSha256: hash("other-query"),
    });
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("collector attestation does not bind exact queryBundleSha256")));
  } finally { f.cleanup(); }
});

test("history names and exact source execution metadata are required for Applied and verified", () => {
  const f = fixture();
  try {
    const row = f.evidence.history.rows.find((entry) => entry.version === "202607260004");
    row.name = "wrong_migration_name";
    f.reapprove();
    const report = f.analyze();
    const result = report.classifications.find((entry) => entry.version === "202607260004");
    assert.equal(result.status, "Schema represented but history ambiguous");
    assert.equal(result.exactExecutionEstablished, false);
    assert.equal(result.schemaRepresented, true);
    assert.equal(result.historyRecorded, true);
    assert.equal(report.acceptance, "NOT_ACCEPTED");
  } finally { f.cleanup(); }
  const second = fixture();
  try {
    const row = second.evidence.history.rows.find((entry) => entry.version === "202607260004");
    delete row.sourceBlobSha1;
    second.reapprove();
    const report = second.analyze();
    const result = report.classifications.find((entry) => entry.version === "202607260004");
    assert.equal(result.status, "Schema represented but history ambiguous");
    assert.equal(result.exactExecutionEstablished, false);
  } finally { second.cleanup(); }
});

test("tampered evidence after signed approval fails closed", () => {
  const f = fixture();
  try {
    f.evidence.catalog.objects[0].fingerprint = hash("tampered");
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("signature verification failed") || reason.includes("does not bind the exact evidence")));
  } finally { f.cleanup(); }
});

test("altered source fingerprint is Unknown", () => {
  const f = fixture();
  try {
    const item = sourceManifest.migrations[4];
    writeFileSync(path.join(f.rootDir, item.path), "select 'tampered';\n");
    const report = f.analyze();
    assert.equal(report.classifications.find((entry) => entry.path === item.path).status, "Unknown");
  } finally { f.cleanup(); }
});

test("complete absence with no history is Verified unapplied", () => {
  const f = fixture();
  try {
    const item = sourceManifest.migrations.find((entry) => entry.version === "202607260004");
    const effect = f.mapping.migrations.find((entry) => entry.path === item.path);
    const keys = new Set(categories.flatMap((category) => effect.effects[category].map((object) => object.kind + "\0" + object.identity)));
    f.evidence.catalog.objects = f.evidence.catalog.objects.filter((object) => !keys.has(object.kind + "\0" + object.identity));
    f.evidence.history.rows = f.evidence.history.rows.filter((row) => row.version !== item.version);
    f.reapprove();
    const report = f.analyze();
    assert.equal(report.classifications.find((entry) => entry.path === item.path).status, "Verified unapplied");
  } finally { f.cleanup(); }
});

test("history with missing effects and conflicting catalog fingerprints is Partial or drifted", () => {
  const f = fixture();
  try {
    const item = sourceManifest.migrations.find((entry) => entry.version === "202607260004");
    const effect = f.mapping.migrations.find((entry) => entry.path === item.path).effects.schema[0];
    f.evidence.catalog.objects = f.evidence.catalog.objects.filter((object) => object.identity !== effect.identity);
    f.reapprove();
    const report = f.analyze();
    assert.equal(report.classifications.find((entry) => entry.path === item.path).status, "Partial or drifted");
  } finally { f.cleanup(); }
  const second = fixture();
  try {
    second.evidence.catalog.objects[0].fingerprint = hash("conflict");
    second.reapprove();
    const report = second.analyze();
    assert.equal(report.classifications[0].status, "Partial or drifted");
  } finally { second.cleanup(); }
});

test("duplicate catalog identities fail closed as Unknown", () => {
  const f = fixture();
  try {
    f.evidence.catalog.objects.push({ ...f.evidence.catalog.objects[0] });
    f.reapprove();
    const report = f.analyze();
    assert.equal(report.classifications[0].status, "Unknown");
  } finally { f.cleanup(); }
});

test("malformed history names and unrecognized versions fail closed", () => {
  const f = fixture();
  try {
    f.evidence.history.rows[0].version = "999999999999";
    f.reapprove();
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("unrecognized version")));
  } finally { f.cleanup(); }
});

test("acceptance mode returns nonzero for unresolved duplicate-007 ambiguity; report mode is explicitly not accepted", () => {
  const f = fixture();
  try {
    const inputs = f.writeCliInputs();
    const script = path.join(repoRoot, "scripts/reconcile-migration-evidence.mjs");
    const args = ["--evidence=" + inputs.evidencePath, "--approvals=" + inputs.approvalsPath, "--trust-roots=" + inputs.rootsPath];
    const env = { ...process.env, DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256: inputs.rootsDigest };
    const accepted = spawnSync(process.execPath, [script, ...args, "--mode=accept"], { cwd: f.rootDir, encoding: "utf8", env });
    assert.equal(accepted.status, 2, accepted.stderr);
    assert.match(accepted.stdout, /"acceptance": "NOT_ACCEPTED"/);
    const reportOnly = spawnSync(process.execPath, [script, ...args, "--mode=report"], { cwd: f.rootDir, encoding: "utf8", env });
    assert.equal(reportOnly.status, 0, reportOnly.stderr);
    assert.match(reportOnly.stdout, /"executionMode": "REPORT_ONLY"/);
    assert.match(reportOnly.stdout, /"acceptance": "REPORT_ONLY"/);
    assert.match(reportOnly.stdout, /"analysisAcceptance": "NOT_ACCEPTED"/);
    assert.match(reportOnly.stdout, /"reconciliationAccepted": false/);
  } finally { f.cleanup(); }
});

test("strict timestamp parser accepts canonical UTC millisecond timestamps", () => {
  const f = fixture();
  try {
    const report = f.analyze();
    assert.equal(report.trustVerified, true);
    assert.equal(report.counts.Unknown, 0);
    assert.equal(report.trustProblems.length, 0, report.trustProblems.join("; "));
  } finally { f.cleanup(); }
});

test("all timestamp-bearing evidence fields reject non-string and noncanonical values", () => {
  const invalidValues = [0, 1, null, false, true, [], {}, "not-a-timestamp",
    "2026-02-30T00:00:00.000Z", "2026-11-25T01:00:00Z",
    "2026-11-25T01:00:00.000+00:00"];
  const cases = [
    ["evidence capture", (f, value) => { f.evidence.provenance.capturedAt = value; f.reapprove(); },
      (report) => report.trustProblems.some((reason) => reason.includes("evidence capture timestamp"))],
    ["collector start", (f, value) => f.reapprove(undefined, (receipt) => { receipt.startedAt = value; }),
      (report) => report.trustProblems.some((reason) => reason.includes("collector execution startedAt"))],
    ["collector completion", (f, value) => f.reapprove(undefined, (receipt) => { receipt.completedAt = value; }),
      (report) => report.trustProblems.some((reason) => reason.includes("collector execution completedAt"))],
    ["history execution", (f, value) => { f.evidence.history.rows[0].executedAt = value; f.reapprove(); },
      (report) => report.trustProblems.some((reason) => reason.includes("history row lacks exact name or valid execution metadata"))],
    ["approval issuedAt", (f, value) => {
      const current = f.approvals.evidenceApproval;
      f.approvals.evidenceApproval = artifact(current.kind, "evidence-approver", current.claims, { issuedAt: value });
    }, (report) => report.trustProblems.some((reason) => reason.includes("approval issuedAt"))],
    ["approval expiresAt", (f, value) => {
      const current = f.approvals.evidenceApproval;
      f.approvals.evidenceApproval = artifact(current.kind, "evidence-approver", current.claims, { expiresAt: value });
    }, (report) => report.trustProblems.some((reason) => reason.includes("approval expiresAt"))],
    ["trust-root notBefore", (f, value) => { f.trustRoots.keys[0].notBefore = value; },
      (report) => report.trustProblems.some((reason) => reason.includes("trust-root notBefore"))],
    ["trust-root notAfter", (f, value) => { f.trustRoots.keys[0].notAfter = value; },
      (report) => report.trustProblems.some((reason) => reason.includes("trust-root notAfter"))],
  ];
  for (const [label, mutate, assertReason] of cases) {
    for (const value of invalidValues) {
      const f = fixture();
      try {
        mutate(f, value);
        const report = f.analyze();
        assert.equal(report.counts.Unknown, 39, label + " accepted " + JSON.stringify(value));
        assert.ok(assertReason(report), label + " did not report invalid timestamp " + JSON.stringify(value));
      } finally { f.cleanup(); }
    }
  }
});

test("collector completion after evidence capture fails closed", () => {
  const f = fixture();
  try {
    f.reapprove(undefined, (receipt) => { receipt.completedAt = fixtureTime(-20 * 60 * 1000); });
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("execution receipt")));
  } finally { f.cleanup(); }
});

test("evidence capture after the current time fails closed", () => {
  const f = fixture();
  try {
    f.evidence.provenance.capturedAt = new Date(Date.now() + 60_000).toISOString();
    f.reapprove();
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("future")));
  } finally { f.cleanup(); }
});

test("strict timestamp parsing rejects non-string and noncanonical execution timestamps", () => {
  for (const value of [0, 1, null, false, true, [], {}, "not-a-timestamp", "2026-02-30T00:00:00.000Z"]) {
    const f = fixture();
    try {
      f.reapprove(undefined, (receipt) => { receipt.startedAt = value; });
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.ok(report.trustProblems.some((reason) => reason.includes("collector execution startedAt")));
    } finally { f.cleanup(); }
  }
});

test("migration history execution timestamps reject coercible non-string values", () => {
  for (const value of [0, 1, null, false, [], {}]) {
    const f = fixture();
    try {
      f.evidence.history.rows[0].executedAt = value;
      f.reapprove();
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.ok(report.trustProblems.some((reason) => reason.includes("history row lacks exact name or valid execution metadata")));
    } finally { f.cleanup(); }
  }
});

test("approval and trust-root validity intervals require canonical timestamps and positive duration", () => {
  const approvalCases = [
    { issuedAt: 0 },
    { expiresAt: null },
    { issuedAt: "2026-02-30T00:00:00.000Z" },
    { issuedAt: fixtureTime(-28 * 60 * 1000), expiresAt: fixtureTime(-29 * 60 * 1000) },
  ];
  for (const overrides of approvalCases) {
    const f = fixture();
    try {
      const current = f.approvals.evidenceApproval;
      f.approvals.evidenceApproval = artifact(current.kind, "evidence-approver", current.claims, overrides);
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.ok(report.trustProblems.some((reason) => reason.includes("approval issuedAt")
        || reason.includes("approval expiresAt") || reason.includes("invalid validity interval")));
    } finally { f.cleanup(); }
  }

  const trustRootCases = [
    (key) => { key.notBefore = 0; },
    (key) => { key.notAfter = {}; },
    (key) => { key.notBefore = fixtureTime(-28 * 60 * 1000); key.notAfter = fixtureTime(-29 * 60 * 1000); },
  ];
  for (const mutate of trustRootCases) {
    const f = fixture();
    try {
      mutate(f.trustRoots.keys.find((key) => key.role === "evidence-approver"));
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.ok(report.trustProblems.some((reason) => reason.includes("trust-root notBefore")
        || reason.includes("trust-root notAfter") || reason.includes("outside its validity window")));
    } finally { f.cleanup(); }
  }
});

test("collector execution rejects reversed start and completion timestamps", () => {
  const f = fixture();
  try {
    f.reapprove(undefined, (receipt) => {
      receipt.startedAt = fixtureTime(-34 * 60 * 1000);
      receipt.completedAt = fixtureTime(-35 * 60 * 1000);
    });
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("execution receipt")));
  } finally { f.cleanup(); }
});

test("exported analyzer ignores caller-supplied trust-root digest", () => {
  const f = fixture();
  const previousDigest = process.env.DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256;
  try {
    delete process.env.DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256;
    const report = analyzeMigrationEvidence({
      rootDir: f.rootDir,
      manifest: sourceManifest,
      evidence: f.evidence,
      approvals: f.approvals,
      trustRoots: f.trustRoots,
      trustedTrustRootsSha256: hash(Buffer.from(canonicalJson(f.trustRoots))),
    });
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("independently provisioned trust-root digest")));
  } finally {
    if (previousDigest === undefined) delete process.env.DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256;
    else process.env.DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256 = previousDigest;
    f.cleanup();
  }
});

test("trust roots must match an independently provisioned digest", () => {
  const f = fixture();
  try {
    const report = f.analyze({ trustedTrustRootsSha256: "0".repeat(64) });
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("independently provisioned trust-root digest")));
  } finally { f.cleanup(); }
});

test("reused migration execution IDs cannot establish exact execution identity", () => {
  const f = fixture();
  try {
    f.evidence.history.rows[1].executionId = f.evidence.history.rows[0].executionId;
    f.reapprove();
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("reuses an execution ID")));
    assert.equal(report.acceptance, "NOT_ACCEPTED");
  } finally { f.cleanup(); }
});

test("history rows without exact names or execution metadata fail closed", () => {
  const f = fixture();
  try {
    delete f.evidence.history.rows[0].name;
    f.reapprove();
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
  } finally { f.cleanup(); }
});

test("CLI rejects trust roots stored inside the repository", () => {
  const f = fixture();
  try {
    const inputs = f.writeCliInputs();
    const script = path.join(repoRoot, "scripts/reconcile-migration-evidence.mjs");
    const args = [
      "--evidence=" + inputs.evidencePath,
      "--approvals=" + inputs.approvalsPath,
      "--trust-roots=" + path.join(repoRoot, "package.json"),
    ];
    const result = spawnSync(process.execPath, [script, ...args], {
      cwd: repoRoot,
      encoding: "utf8",
      env: { ...process.env, DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256: inputs.rootsDigest },
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /trust roots must be provisioned outside the repository/);
  } finally { f.cleanup(); }
});

test("mapping rejects unreviewed effect domains and extra effect fields", () => {
  for (const mutate of [
    (mapping) => { mapping.migrations[0].effects.unreviewedDomain = []; },
    (mapping) => { mapping.migrations[0].effects.schema[0].unreviewedFlag = true; },
  ]) {
    const f = fixture();
    try {
      mutate(f.mapping);
      f.reapprove();
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.ok(report.trustProblems.some((reason) => reason.includes("effect domains") || reason.includes("malformed or empty effects")));
    } finally { f.cleanup(); }
  }
});

test("evidence, mapping and collector approvals require distinct trusted signers", () => {
  const f = fixture();
  try {
    const approval = f.approvals.mappingApproval;
    const unsigned = { ...approval, signerId: f.approvals.evidenceApproval.signerId };
    delete unsigned.signature;
    f.approvals.mappingApproval = {
      ...unsigned,
      signature: sign(null, Buffer.from(canonicalJson(unsigned)), keys["mapping-approver"].privateKey).toString("base64"),
    };
    f.trustRoots.keys.find((key) => key.role === "mapping-approver").signerId = unsigned.signerId;
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("three distinct trusted signers")));
  } finally { f.cleanup(); }
});

test("evidence approval must be issued strictly after capture", () => {
  const cases = [
    { label: "earlier", issuedAt: fixtureTime(-31 * 60 * 1000), accepted: false },
    { label: "equal", issuedAt: FIXTURE_CAPTURED_AT, accepted: false },
    { label: "later", issuedAt: FIXTURE_APPROVED_AT, accepted: true },
  ];
  for (const scenario of cases) {
    const f = fixture();
    try {
      const current = f.approvals.evidenceApproval;
      f.approvals.evidenceApproval = artifact(current.kind, "evidence-approver", current.claims, {
        issuedAt: scenario.issuedAt,
      });
      const report = f.analyze();
      assert.equal(report.trustVerified, scenario.accepted, "evidence approval " + scenario.label + " capture");
      if (!scenario.accepted) {
        assert.ok(report.trustProblems.some((reason) => reason.includes("issued after the exact evidence capture")));
      }
    } finally { f.cleanup(); }
  }
});

test("collector approval must be issued strictly after capture", () => {
  const cases = [
    { label: "earlier", issuedAt: fixtureTime(-31 * 60 * 1000), accepted: false },
    { label: "equal", issuedAt: FIXTURE_CAPTURED_AT, accepted: false },
    { label: "later", issuedAt: FIXTURE_APPROVED_AT, accepted: true },
  ];
  for (const scenario of cases) {
    const f = fixture();
    try {
      const current = f.approvals.collectorAttestation;
      f.approvals.collectorAttestation = artifact(current.kind, "collector", current.claims, {
        issuedAt: scenario.issuedAt,
      });
      const report = f.analyze();
      assert.equal(report.trustVerified, scenario.accepted, "collector approval " + scenario.label + " capture");
      if (!scenario.accepted) {
        assert.ok(report.trustProblems.some((reason) => reason.includes("issued after the exact evidence capture")));
      }
    } finally { f.cleanup(); }
  }
});

test("evidence and collector approvals must be issued after capture", () => {
  const f = fixture();
  try {
    const claims = f.approvals.evidenceApproval.claims;
    f.approvals.evidenceApproval = artifact("production-evidence-approval", "evidence-approver", claims, {
      issuedAt: fixtureTime(-31 * 60 * 1000),
    });
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.trustProblems.some((reason) => reason.includes("issued after the exact evidence capture")));
  } finally { f.cleanup(); }
});

test("trust-root bundle rejects private signing material and unsupported key roles", () => {
  for (const mutate of [
    (f) => {
      f.trustRoots.keys[0].publicKeyPem = keys["evidence-approver"].privateKey.export({ type: "pkcs8", format: "pem" }).toString();
    },
    (f) => { f.trustRoots.keys[0].role = "production-admin"; },
  ]) {
    const f = fixture();
    try {
      mutate(f);
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
      assert.ok(report.trustProblems.some((reason) => reason.includes("unsupported key, role or private signing material")));
    } finally { f.cleanup(); }
  }
});
