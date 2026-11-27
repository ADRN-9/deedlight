#!/usr/bin/env node
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { gitBlobSha1, validateInventory } from "./verify-migration-inventory-aggregate.mjs";

const root = process.cwd();
const inventory = JSON.parse(readFileSync(path.join(root, "supabase/migration-inventory.json"), "utf8"));
const observations = JSON.parse(readFileSync(path.join(root, "docs/c556-migration-source-observations.json"), "utf8"));
const categories = ["dataTransformations", "backfills", "dependencies", "preconditions", "postconditions"];
const exact = (value, keys) => value && typeof value === "object" && !Array.isArray(value)
  && Object.keys(value).sort().join(",") === [...keys].sort().join(",");
validateInventory(inventory);
assert.equal(gitBlobSha1(readFileSync(path.join(root, "supabase/migration-inventory.json"))),
  "4e63f31368d446e905f4f44565be73337c7188fb", "pinned 40-entry inventory changed");
assert.ok(exact(observations, ["schemaVersion", "inventoryBlobSha1", "inventoryCount", "analysisMethod", "executionEvidenceIncluded", "entries"]));
assert.equal(observations.schemaVersion, 1);
assert.equal(observations.inventoryBlobSha1, "4e63f31368d446e905f4f44565be73337c7188fb");
assert.equal(observations.inventoryCount, 40);
assert.equal(observations.analysisMethod, "conservative-source-line-observation-v1");
assert.equal(observations.executionEvidenceIncluded, false);
assert.equal(observations.entries.length, inventory.migrations.length);
const byPath = new Map();
for (const entry of observations.entries) {
  assert.ok(exact(entry, ["path", "blobSha1", "byteLength", "lineCount", "observations", "classifications"]));
  assert.equal(typeof entry.path, "string");
  assert.ok(!byPath.has(entry.path), "duplicate source observation path: " + entry.path);
  byPath.set(entry.path, entry);
}
assert.equal(byPath.size, 40);
for (const migration of inventory.migrations) {
  const entry = byPath.get(migration.path);
  assert.ok(entry, "source observation missing: " + migration.path);
  assert.equal(entry.blobSha1, migration.blobSha1, "source identity mismatch: " + migration.path);
  assert.equal(entry.byteLength, migration.byteLength, "source byte length mismatch: " + migration.path);
  const bytes = readFileSync(path.join(root, migration.path));
  assert.equal(bytes.length, migration.byteLength, "local source byte length mismatch: " + migration.path);
  assert.equal(gitBlobSha1(bytes), migration.blobSha1, "local source blob mismatch: " + migration.path);
  const lines = bytes.toString("utf8").split(/\r?\n/);
  assert.equal(entry.lineCount, lines.length, "source line count mismatch: " + migration.path);
  assert.ok(exact(entry.observations, ["transformations", "foreignKeyReferences", "guards"]));
  for (const [name, rows] of Object.entries(entry.observations)) {
    assert.ok(Array.isArray(rows), "observation list malformed: " + name);
    for (const row of rows) {
      assert.ok(Number.isSafeInteger(row.line) && row.line >= 1 && row.line <= lines.length,
        "observation line out of range: " + migration.path);
      assert.equal(row.sourceExcerpt, lines[row.line - 1].trim().slice(0, 200),
        "source excerpt does not match pinned source: " + migration.path + ":" + row.line);
    }
  }
  assert.ok(exact(entry.classifications, categories));
  const hasMutation = entry.observations.transformations.length > 0;
  const hasReference = entry.observations.foreignKeyReferences.length > 0;
  const hasGuard = entry.observations.guards.length > 0;
  for (const category of categories) {
    const classification = entry.classifications[category];
    assert.ok(exact(classification, ["disposition", "reason"]));
    assert.ok(["unsupported", "unknown"].includes(classification.disposition),
      "source scan must never assert effects/none: " + migration.path + ":" + category);
    assert.ok(typeof classification.reason === "string" && classification.reason.trim().length >= 20);
  }
  assert.equal(entry.classifications.dataTransformations.disposition, hasMutation ? "unsupported" : "unknown");
  assert.equal(entry.classifications.backfills.disposition, hasMutation ? "unsupported" : "unknown");
  assert.equal(entry.classifications.dependencies.disposition, hasReference ? "unsupported" : "unknown");
  assert.equal(entry.classifications.preconditions.disposition, hasGuard ? "unsupported" : "unknown");
  assert.equal(entry.classifications.postconditions.disposition, hasGuard ? "unsupported" : "unknown");
}
const paths = inventory.migrations.map((entry) => entry.path);
assert.ok(paths.includes("supabase/migrations/202607260007_sprint6_daily_deedlight.sql"));
assert.ok(paths.includes("supabase/migrations/202607260007_sprint7_pwa_daily_engagement.sql"));
assert.ok(paths.includes("supabase/migrations/202611260039_delivery_kind_scoped_claims.sql"));
assert.equal(inventory.migrations.filter((entry) => entry.version === "202607260007").length, 2);
process.stdout.write("C556 source observations PASS: 40/40 exact source blobs, excerpts and explicit unsupported/unknown classifications; no execution evidence asserted.\n");
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exitCode = 0;
