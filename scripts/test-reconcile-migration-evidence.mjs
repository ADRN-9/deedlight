import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { analyzeMigrationEvidence, evidencePayload } from "./reconcile-migration-evidence.mjs";
import { gitBlobSha1 } from "./verify-migration-inventory-aggregate.mjs";

const repoRoot = process.cwd();
const sourceManifest = JSON.parse(readFileSync(path.join(repoRoot, "supabase/migration-inventory.json"), "utf8"));
const kinds = ["tables", "columns", "constraints", "indexes", "triggers", "policies", "routines"];
const hash = (value) => createHash("sha256").update(value).digest("hex");

function fixture() {
  const rootDir = mkdtempSync(path.join(os.tmpdir(), "deedlight-reconcile-"));
  mkdirSync(path.join(rootDir, "supabase/migrations"), { recursive: true });
  const manifestBytes = Buffer.from(JSON.stringify(sourceManifest, null, 2) + "\n");
  writeFileSync(path.join(rootDir, "supabase/migration-inventory.json"), manifestBytes);
  for (const item of sourceManifest.migrations) {
    copyFileSync(path.join(repoRoot, item.path), path.join(rootDir, item.path));
  }
  const migrationEffects = sourceManifest.migrations.map((item, index) => ({
    path: item.path,
    blobSha1: item.blobSha1,
    expectedObjects: [0, 1].map((part) => ({
      kind: kinds[(index + part) % kinds.length],
      identity: "fixture." + index + "." + part,
      fingerprint: hash("expected:" + index + ":" + part),
    })),
  }));
  const objects = migrationEffects.flatMap((effect) => effect.expectedObjects);
  const versions = [...new Set(sourceManifest.migrations.map((item) => item.version))];
  const evidence = {
    schemaVersion: 1,
    provenance: {
      environment: "production",
      projectRef: "xaipiovflxomcbfwtwmu",
      capturedAt: "2026-11-25T00:00:00.000Z",
      readOnly: true,
      collector: "fixture-read-only-exporter",
      queryBundleSha256: hash("reviewed-query-bundle"),
      approvalReference: "DBA-APPROVAL-FIXTURE-001",
      payloadSha256: "",
    },
    history: { complete: true, rows: versions.map((version) => ({ version })) },
    catalog: { complete: true, completeKinds: [...kinds], objects },
    mapping: { reviewer: "fixture-reviewer", reviewedSha256: hash("reviewed-effect-mapping") },
    migrationEffects,
  };
  evidence.provenance.payloadSha256 = hash(evidencePayload(evidence));
  return {
    rootDir,
    manifest: sourceManifest,
    evidence,
    trustedEvidenceSha256: evidence.provenance.payloadSha256,
    cleanup: () => rmSync(rootDir, { recursive: true, force: true }),
    analyze(overrides = {}) {
      return analyzeMigrationEvidence({
        rootDir,
        manifest: sourceManifest,
        evidence,
        trustedEvidenceSha256: evidence.provenance.payloadSha256,
        expectedInventoryBlobSha1: gitBlobSha1(manifestBytes),
        now: Date.parse("2026-11-25T01:00:00.000Z"),
        ...overrides,
      });
    },
    reseal() {
      evidence.provenance.payloadSha256 = hash(evidencePayload(evidence));
    },
  };
}

test("classifies all 39 migration sources and never treats one duplicate-007 history row as proof of both bodies", () => {
  const f = fixture();
  try {
    const report = f.analyze();
    assert.equal(report.sourceInventory.migrationCount, 39);
    assert.equal(report.sourceInventory.uniqueVersionCount, 38);
    assert.equal(report.classifications.length, 39);
    const duplicate = report.classifications.filter((item) => item.version === "202607260007");
    assert.equal(duplicate.length, 2);
    assert.ok(duplicate.every((item) => item.status === "Schema represented but history ambiguous"));
    assert.ok(duplicate.every((item) => item.reasons.some((reason) => reason.includes("one history row cannot attest both"))));
    assert.equal(report.counts["Applied and verified"], 37);
    assert.equal(report.productionEvidenceUsed, true);
    assert.equal(report.mutationPerformed, false);
  } finally { f.cleanup(); }
});

test("missing or incomplete evidence fails closed to Unknown for every migration", () => {
  const f = fixture();
  try {
    f.evidence.catalog.complete = false;
    f.reseal();
    const report = f.analyze();
    assert.equal(report.productionEvidenceUsed, false);
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.evidenceProblems.some((reason) => reason.includes("catalog export is incomplete")));
  } finally { f.cleanup(); }
});

test("self-reported payload digest is not trusted without independent DBA-approved digest", () => {
  const f = fixture();
  try {
    const report = f.analyze({ trustedEvidenceSha256: undefined });
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.evidenceProblems.some((reason) => reason.includes("independently approved evidence digest")));
  } finally { f.cleanup(); }
});

test("stale evidence is rejected even when its payload digest is valid", () => {
  const f = fixture();
  try {
    const report = f.analyze({ now: Date.parse("2026-11-27T00:00:00.000Z") });
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.evidenceProblems.some((reason) => reason.includes("stale")));
  } finally { f.cleanup(); }
});

test("tampered export after approval is rejected by the evidence digest", () => {
  const f = fixture();
  try {
    f.evidence.catalog.objects[0].fingerprint = hash("tampered");
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
    assert.ok(report.evidenceProblems.some((reason) => reason.includes("digest mismatch")));
  } finally { f.cleanup(); }
});

test("source fingerprint alteration is Unknown and cannot be inferred as applied", () => {
  const f = fixture();
  try {
    const item = f.manifest.migrations[4];
    writeFileSync(path.join(f.rootDir, item.path), "select 'tampered';\n");
    const report = f.analyze();
    const result = report.classifications.find((entry) => entry.path === item.path);
    assert.equal(result.status, "Unknown");
    assert.match(result.reasons.join(" "), /source fingerprint/);
  } finally { f.cleanup(); }
});

test("complete absence with no history is Verified unapplied", () => {
  const f = fixture();
  try {
    const item = f.manifest.migrations.find((entry) => entry.version === "202607260004");
    const effect = f.evidence.migrationEffects.find((entry) => entry.path === item.path);
    const keys = new Set(effect.expectedObjects.map((object) => object.kind + "\0" + object.identity));
    f.evidence.catalog.objects = f.evidence.catalog.objects.filter((object) => !keys.has(object.kind + "\0" + object.identity));
    f.evidence.history.rows = f.evidence.history.rows.filter((row) => row.version !== item.version);
    f.reseal();
    const report = f.analyze();
    assert.equal(report.classifications.find((entry) => entry.path === item.path).status, "Verified unapplied");
  } finally { f.cleanup(); }
});

test("history row with missing effects is Partial or drifted, not applied", () => {
  const f = fixture();
  try {
    const item = f.manifest.migrations.find((entry) => entry.version === "202607260004");
    const effect = f.evidence.migrationEffects.find((entry) => entry.path === item.path);
    const key = effect.expectedObjects[0];
    f.evidence.catalog.objects = f.evidence.catalog.objects.filter((object) => !(object.kind === key.kind && object.identity === key.identity));
    f.reseal();
    const report = f.analyze();
    assert.equal(report.classifications.find((entry) => entry.path === item.path).status, "Partial or drifted");
  } finally { f.cleanup(); }
});

test("conflicting catalog fingerprint is Partial or drifted", () => {
  const f = fixture();
  try {
    const target = f.evidence.catalog.objects[0];
    target.fingerprint = hash("different-live-definition");
    f.reseal();
    const report = f.analyze();
    const item = f.manifest.migrations.find((entry) => entry.path === f.evidence.migrationEffects[0].path);
    assert.equal(report.classifications.find((entry) => entry.path === item.path).status, "Partial or drifted");
  } finally { f.cleanup(); }
});

test("duplicate catalog identities fail closed as Unknown", () => {
  const f = fixture();
  try {
    f.evidence.catalog.objects.push({ ...f.evidence.catalog.objects[0] });
    f.reseal();
    const report = f.analyze();
    assert.equal(report.classifications[0].status, "Unknown");
  } finally { f.cleanup(); }
});

test("missing migration-effect mapping fails closed", () => {
  const f = fixture();
  try {
    f.evidence.migrationEffects.pop();
    f.reseal();
    const report = f.analyze();
    assert.equal(report.counts.Unknown, 39);
  } finally { f.cleanup(); }
});

test("wrong project, write-capable collector or incomplete catalog dimensions fail closed", () => {
  for (const change of [
    (e) => { e.provenance.projectRef = "another-project"; },
    (e) => { e.provenance.readOnly = false; },
    (e) => { e.catalog.completeKinds = e.catalog.completeKinds.filter((kind) => kind !== "routines"); },
  ]) {
    const f = fixture();
    try {
      change(f.evidence);
      f.reseal();
      const report = f.analyze();
      assert.equal(report.counts.Unknown, 39);
    } finally { f.cleanup(); }
  }
});
