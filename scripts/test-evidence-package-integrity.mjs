import test from "node:test";
import assert from "node:assert/strict";
import { canonicalJson, validateSqlOutput, sha256, SQL_PROJECTIONS } from "./collect-production-migration-evidence.mjs";
import { createEvidencePackageManifest, verifyEvidencePackageManifest } from "./evidence-package-integrity.mjs";

function fixture() {
  const rows = [];
  for (const projection of SQL_PROJECTIONS) {
    rows.push(projection.columns);
    if (projection.id === "identity_v1") {
      rows.push(["xaipiovflxomcbfwtwmu", "c".repeat(40), "deedlight_migration_order_test",
        "deedlight_catalog_auditor", "deedlight_catalog_auditor", "16.2", "127.0.0.1", "5432",
        "2026-01-01T00:00:00.000Z", "on"]);
    } else if (projection.id === "migration_history_v1") {
      rows.push(["202611240037", "migration_037_fixture", "1"]);
      rows.push(["202611240038", "", ""]);
    } else if (projection.id === "database_acl_v1") {
      rows.push(["database_acl_v1", "2", "1", "db_one", "t", "f", "10", "postgres", "t", "built_in_default", "[]"]);
      rows.push(["database_acl_v1", "2", "2", "db_two", "t", "t", "10", "postgres", "f", "explicit", "[]"]);
    }
  }
  rows.push(["collector_transaction_closed"], ["t"]);
  const evidenceBytes = Buffer.from(rows.map((row) => row.join(",")).join("\r\n") + "\r\n");
  const validation = validateSqlOutput(evidenceBytes);
  const digest = sha256(evidenceBytes);
  const receipt = {
    schemaVersion: 1,
    kind: "deedlight-production-migration-collection",
    status: "UNSIGNED_NOT_ACCEPTED",
    projectRef: "xaipiovflxomcbfwtwmu",
    endpoint: {
      hostname: "db.xaipiovflxomcbfwtwmu.supabase.co", port: 5432, database: "postgres",
      tlsMode: "verify-full", tlsVerified: true, tlsHostnameVerified: true, tlsChainVerified: true,
      projectIdentityMethod: "independently-pinned-profile-and-project-specific-TLS-hostname",
      tlsRootCertificateSha256: "a".repeat(64), independentlyPinnedProfileSha256: "b".repeat(64),
    },
    source: {
      repositoryCommitSha: "c".repeat(40), migrationInventoryGitBlobSha1: "4e63f31368d446e905f4f44565be73337c7188fb",
      sqlBundlePath: "scripts/production-migration-readonly-audit.sql",
      sqlBundleGitBlobSha1: "8f8c38ba0c2a463ee25c6dae1dc1b15e24e3819f",
      sqlBundleSha256: "afda6bcfc9f7abc7765b8dfb54bf02d1cdb0d8062da2a9f953336b638d13af7d",
    },
    execution: {
      collectorId: "deedlight-readonly-collector-v1", authenticatedPrincipal: "deedlight_catalog_auditor",
      expectedEffectivePrincipal: "deedlight_catalog_auditor", transactionIsolation: "repeatable read",
      readOnly: true, transactionRollbackVerified: true, startedAt: "2026-01-01T00:00:00Z",
      completedAt: "2026-01-01T00:01:00Z", outputFormat: "PostgreSQL psql CSV",
      canonicalization: "UTF-8 canonical JSON with ordered records and sorted object keys",
      resultRecordCount: validation.resultRows.length, databaseAclV1RowCount: validation.databaseAclRows,
      migrationHistoryRowCount: validation.migrationHistoryRows.length,
      canonicalResultSha256: sha256(Buffer.from(canonicalJson(validation.resultRows))), evidenceFileSha256: digest,
    },
    evidence: { file: "evidence.csv", mediaType: "text/csv", byteLength: evidenceBytes.length, sha256: digest },
    signing: { state: "NOT_SIGNED", keyId: null, signature: null,
      acceptance: "PROHIBITED_PENDING_INDEPENDENT_SIGNING_AND_VERIFICATION" },
  };
  return { receipt, evidenceBytes };
}

test("package manifest binds exact receipt and raw evidence bytes", () => {
  const f = fixture();
  const manifest = createEvidencePackageManifest(f);
  const receiptBytes = Buffer.from(canonicalJson(f.receipt) + "\n");
  assert.equal(verifyEvidencePackageManifest({ manifest, receiptBytes, evidenceBytes: f.evidenceBytes }), true);
  assert.equal(manifest.status, "UNSIGNED_INTEGRITY_ONLY_NOT_ACCEPTED");
});

test("tampered evidence and receipt bytes fail package verification", () => {
  const f = fixture();
  const manifest = createEvidencePackageManifest(f);
  const receiptBytes = Buffer.from(canonicalJson(f.receipt) + "\n");
  const changedEvidence = Buffer.from(f.evidenceBytes);
  changedEvidence[0] ^= 1;
  assert.throws(() => verifyEvidencePackageManifest({ manifest, receiptBytes, evidenceBytes: changedEvidence }), /PACKAGE_FILE_INTEGRITY_MISMATCH/);
  const changedReceipt = Buffer.from(receiptBytes);
  changedReceipt[0] ^= 1;
  assert.throws(() => verifyEvidencePackageManifest({ manifest, receiptBytes: changedReceipt, evidenceBytes: f.evidenceBytes }), /PACKAGE_FILE_INTEGRITY_MISMATCH/);
});

test("manifest path swaps, extra files and status promotion fail closed", () => {
  const f = fixture();
  const manifest = createEvidencePackageManifest(f);
  const receiptBytes = Buffer.from(canonicalJson(f.receipt) + "\n");
  for (const mutate of [
    (m) => { m.files.reverse(); },
    (m) => { m.files.push({ path: "extra.txt", byteLength: 0, sha256: "0".repeat(64) }); },
    (m) => { m.status = "ACCEPTED"; },
    (m) => { m.files[0].path = "../evidence.csv"; },
  ]) {
    const altered = structuredClone(manifest);
    mutate(altered);
    assert.throws(() => verifyEvidencePackageManifest({ manifest: altered, receiptBytes, evidenceBytes: f.evidenceBytes }));
  }
});

test("manifest digest detects modification of an entry even when file bytes remain intact", () => {
  const f = fixture();
  const manifest = createEvidencePackageManifest(f);
  const altered = structuredClone(manifest);
  altered.files[0].byteLength += 1;
  assert.throws(() => verifyEvidencePackageManifest({
    manifest: altered,
    receiptBytes: Buffer.from(canonicalJson(f.receipt) + "\n"),
    evidenceBytes: f.evidenceBytes,
  }), /PACKAGE_FILE_INTEGRITY_MISMATCH/);
});
