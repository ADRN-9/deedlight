import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  buildAggregate,
  gitBlobSha1,
  verifyAggregate,
  verifyMigrationInventory,
} from "./verify-migration-inventory-aggregate.mjs";

const sourceManifest = JSON.parse(readFileSync(new URL("../supabase/migration-inventory.json", import.meta.url), "utf8"));
const compatibilityBytes = readFileSync(new URL("../supabase/bootstrap/migration_038_admin_compatibility.sql", import.meta.url));
const seedFixture = Buffer.from([
  "insert into public.themes (slug) values ('fixture') on conflict (slug) do update set slug = excluded.slug;",
  "insert into public.daily_posts (slug) values ('fixture') on conflict (slug) do update set slug = excluded.slug;",
  "insert into public.badges (slug) values ('fixture') on conflict (slug) do update set slug = excluded.slug;",
  "",
].join("\n"));

function fixture() {
  const root = mkdtempSync(path.join(os.tmpdir(), "deedlight-migration-"));
  mkdirSync(path.join(root, "supabase/migrations"), { recursive: true });
  mkdirSync(path.join(root, "supabase/bootstrap"), { recursive: true });
  writeFileSync(path.join(root, "supabase/bootstrap/migration_038_admin_compatibility.sql"), compatibilityBytes);
  const migrations = sourceManifest.migrations.map((item) => {
    const bytes = Buffer.from(`-- fixture source: ${path.basename(item.path)}\nselect '${path.basename(item.path)}';\n`);
    writeFileSync(path.join(root, item.path), bytes);
    return { ...item, blobSha1: gitBlobSha1(bytes), byteLength: bytes.length };
  });
  writeFileSync(path.join(root, "supabase/seed.sql"), seedFixture);
  const manifest = {
    ...sourceManifest,
    migrations,
    bootstrapSeed: {
      ...sourceManifest.bootstrapSeed,
      blobSha1: gitBlobSha1(seedFixture),
      byteLength: seedFixture.length,
    },
  };
  const manifestBytes = Buffer.from(JSON.stringify(manifest, null, 2) + "\n");
  writeFileSync(path.join(root, "supabase/migration-inventory.json"), manifestBytes);
  const inventoryBlobSha1 = gitBlobSha1(manifestBytes);
  const aggregate = buildAggregate(root, manifest, inventoryBlobSha1);
  writeFileSync(path.join(root, "supabase/run_in_sql_editor_all.sql"), aggregate);
  return { root, manifest, aggregate, inventoryBlobSha1, cleanup: () => rmSync(root, { recursive: true, force: true }) };
}

function expectInventoryFailure(f, pattern) {
  assert.throws(() => verifyMigrationInventory(f.root, f.manifest, f.inventoryBlobSha1), pattern);
}

function expectAggregateFailure(f, pattern) {
  assert.throws(() => verifyAggregate(f.root, f.manifest, "supabase/run_in_sql_editor_all.sql", f.inventoryBlobSha1), pattern);
}

test("accepts exact 40-file inventory and preserves both distinct 007 sources", () => {
  const f = fixture();
  try {
    const result = verifyMigrationInventory(f.root, f.manifest, f.inventoryBlobSha1);
    assert.deepEqual(result, { migrationCount: 40, uniqueVersionCount: 39, seedUpsertCount: 3 });
    const a = f.aggregate.toString("utf8");
    for (const name of sourceManifest.intentionalDuplicateVersionGroups["202607260007"]) {
      const item = f.manifest.migrations.find((entry) => path.basename(entry.path) === name);
      const bytes = readFileSync(path.join(f.root, item.path));
      assert.equal(f.aggregate.indexOf(bytes), f.aggregate.lastIndexOf(bytes));
    }
    assert.match(a, /202607260007_sprint6_daily_deedlight\.sql/);
    assert.match(a, /202607260007_sprint7_pwa_daily_engagement\.sql/);
    assert.equal((a.match(/BEGIN BOOTSTRAP SEED/g) ?? []).length, 1);
  } finally { f.cleanup(); }
});


test("rejects a substituted inventory manifest even when its JSON remains valid",()=>{
  const f=fixture();
  try {
    const changed={...f.manifest,bootstrapSeed:{...f.manifest.bootstrapSeed,expectedUpsertCount:2}};
    writeFileSync(path.join(f.root,"supabase/migration-inventory.json"),JSON.stringify(changed,null,2)+"\n");
    assert.throws(()=>verifyMigrationInventory(f.root,f.manifest,f.inventoryBlobSha1),/inventory manifest Git blob SHA-1/);
  } finally { f.cleanup(); }
});

test("rejects a missing migration file", () => {
  const f = fixture();
  try {
    rmSync(path.join(f.root, f.manifest.migrations[2].path));
    expectInventoryFailure(f, /missing migrations/);
  } finally { f.cleanup(); }
});

test("rejects changed Git blob hashes and byte lengths", () => {
  const f = fixture();
  try {
    const target = f.manifest.migrations[3];
    writeFileSync(path.join(f.root, target.path), "select 'tampered';\n");
    expectInventoryFailure(f, /modified migrations/);
  } finally { f.cleanup(); }
});

test("detects renamed migration by matching its pinned blob", () => {
  const f = fixture();
  try {
    const target = f.manifest.migrations[4];
    renameSync(path.join(f.root, target.path), path.join(f.root, "supabase/migrations/renamed-migration.sql"));
    assert.throws(() => verifyMigrationInventory(f.root, f.manifest, f.inventoryBlobSha1), /renamed migrations/);
  } finally { f.cleanup(); }
});

test("rejects unexpected additional SQL files", () => {
  const f = fixture();
  try {
    writeFileSync(path.join(f.root, "supabase/migrations/209901010001_unapproved.sql"), "select 1;\n");
    expectInventoryFailure(f, /unexpected migrations/);
  } finally { f.cleanup(); }
});

for (const version of ["202611240037", "202611240038", "202611260039"]) {
  test(`rejects modified migration ${version}`, () => {
    const f = fixture();
    try {
      const target = f.manifest.migrations.find((item) => item.version === version);
      writeFileSync(path.join(f.root, target.path), "select 'changed protected migration';\n");
      expectInventoryFailure(f, /modified migrations/);
    } finally { f.cleanup(); }
  });
}

test("rejects truncated inventory JSON and incomplete inventory arrays", () => {
  const f = fixture();
  try {
    writeFileSync(path.join(f.root, "supabase/migration-inventory.json"), '{"schemaVersion":1,"migrations":[');
    assert.throws(() => JSON.parse(readFileSync(path.join(f.root, "supabase/migration-inventory.json"), "utf8")));
    assert.throws(() => verifyMigrationInventory(f.root, { ...f.manifest, migrations: f.manifest.migrations.slice(0, 39) }, f.inventoryBlobSha1), /truncated/);
  } finally { f.cleanup(); }
});

test("rejects a missing bootstrap seed upsert", () => {
  const f = fixture();
  try {
    writeFileSync(path.join(f.root, "supabase/seed.sql"), seedFixture.toString("utf8").replace(/insert into public.badges[\s\S]*?;\n/, ""));
    expectInventoryFailure(f, /bootstrap seed bytes differ/);
  } finally { f.cleanup(); }
});

test("rejects duplicated bootstrap seed data", () => {
  const f = fixture();
  try {
    writeFileSync(path.join(f.root, "supabase/seed.sql"), Buffer.concat([seedFixture, seedFixture]));
    expectInventoryFailure(f, /bootstrap seed bytes differ/);
  } finally { f.cleanup(); }
});

test("verifies committed aggregate byte-for-byte", () => {
  const f = fixture();
  try {
    const result = verifyAggregate(f.root, f.manifest, "supabase/run_in_sql_editor_all.sql", f.inventoryBlobSha1);
    assert.equal(result.aggregateBytes, f.aggregate.length);
    assert.match(result.aggregateSha256, /^[a-f0-9]{64}$/);
  } finally { f.cleanup(); }
});

test("rejects a missing aggregate migration body", () => {
  const f = fixture();
  try {
    const item = f.manifest.migrations[2];
    const body = readFileSync(path.join(f.root, item.path));
    const offset = f.aggregate.indexOf(body);
    const changed = Buffer.concat([f.aggregate.subarray(0, offset), f.aggregate.subarray(offset + body.length)]);
    writeFileSync(path.join(f.root, "supabase/run_in_sql_editor_all.sql"), changed);
    expectAggregateFailure(f, /SQL aggregate differs/);
  } finally { f.cleanup(); }
});

test("rejects duplicated aggregate migration bodies", () => {
  const f = fixture();
  try {
    const body = readFileSync(path.join(f.root, f.manifest.migrations[2].path));
    const offset = f.aggregate.indexOf(Buffer.from("-- END MIGRATION SQL"));
    const changed = Buffer.concat([f.aggregate.subarray(0, offset), body, f.aggregate.subarray(offset)]);
    writeFileSync(path.join(f.root, "supabase/run_in_sql_editor_all.sql"), changed);
    expectAggregateFailure(f, /SQL aggregate differs/);
  } finally { f.cleanup(); }
});

test("rejects reversed aggregate migration order", () => {
  const f = fixture();
  try {
    const first = readFileSync(path.join(f.root, f.manifest.migrations[0].path));
    const second = readFileSync(path.join(f.root, f.manifest.migrations[1].path));
    const start = f.aggregate.indexOf(first);
    const secondStart = f.aggregate.indexOf(second, start + first.length);
    const changed = Buffer.concat([
      f.aggregate.subarray(0, start),
      second,
      first,
      f.aggregate.subarray(secondStart + second.length),
    ]);
    writeFileSync(path.join(f.root, "supabase/run_in_sql_editor_all.sql"), changed);
    expectAggregateFailure(f, /SQL aggregate differs/);
  } finally { f.cleanup(); }
});

test("rejects truncated migration source bytes", () => {
  const f = fixture();
  try {
    const target = f.manifest.migrations[5];
    const bytes = readFileSync(path.join(f.root, target.path));
    writeFileSync(path.join(f.root, target.path), bytes.subarray(0, bytes.length - 3));
    expectInventoryFailure(f, /modified migrations/);
  } finally { f.cleanup(); }
});

test("rejects unexpected SQL appended to the aggregate", () => {
  const f = fixture();
  try {
    const changed = Buffer.concat([f.aggregate, Buffer.from("\ndrop table public.profiles;\n")]);
    writeFileSync(path.join(f.root, "supabase/run_in_sql_editor_all.sql"), changed);
    expectAggregateFailure(f, /SQL aggregate differs/);
  } finally { f.cleanup(); }
});

test("rejects duplicate seed content in the aggregate", () => {
  const f = fixture();
  try {
    const seedOffset = f.aggregate.indexOf(seedFixture);
    const changed = Buffer.concat([
      f.aggregate.subarray(0, seedOffset + seedFixture.length),
      seedFixture,
      f.aggregate.subarray(seedOffset + seedFixture.length),
    ]);
    writeFileSync(path.join(f.root, "supabase/run_in_sql_editor_all.sql"), changed);
    expectAggregateFailure(f, /SQL aggregate differs/);
  } finally { f.cleanup(); }
});

test("places the pinned compatibility step after 037 and before immutable 038", () => {
  const f = fixture();
  try {
    const aggregate = f.aggregate.toString("utf8");
    const compatibilityStart = aggregate.indexOf("-- BEGIN MIGRATION 038 ADMIN COMPATIBILITY");
    const migration037Start = aggregate.indexOf("-- fixture source: 202611240037_delivery_provider_integrity_conflict_evidence.sql");
    const migration038Start = aggregate.indexOf("-- fixture source: 202611240038_delivery_provider_integrity_lock_order_pagination.sql");
    assert.ok(migration037Start >= 0 && compatibilityStart > migration037Start && migration038Start > compatibilityStart);
    assert.ok(aggregate.includes(compatibilityBytes.toString("utf8")));
    assert.equal(aggregate.split(compatibilityBytes.toString("utf8")).length - 1, 1);
    assert.match(aggregate, /COMPATIBILITY supabase\/bootstrap\/migration_038_admin_compatibility\.sql blob=[a-f0-9]{40}/);
  } finally { f.cleanup(); }
});

test("rejects a modified Migration 038 compatibility artifact", () => {
  const f = fixture();
  try {
    writeFileSync(path.join(f.root, "supabase/bootstrap/migration_038_admin_compatibility.sql"), Buffer.concat([compatibilityBytes, Buffer.from("\\n-- unreviewed")]));
    assert.throws(() => buildAggregate(f.root, f.manifest, f.inventoryBlobSha1), /compatibility artifact Git blob SHA-1 differs/);
  } finally { f.cleanup(); }
});

test("compatibility artifact keeps fail-closed suspension and exact-source guards", () => {
  const source = compatibilityBytes.toString("utf8");
  assert.match(source, /profiles\.is_suspended to remain NOT NULL/);
  assert.match(source, /4fb49052b2e525d8b355123d430df7e536a4da5207fd6ef3d21f3b2d770e98e0/);
  assert.match(source, /85e6838cf8feec05bcfe9e9051e5192bc8f0d42f7a53cb6c0450067d70bba74b/);
  assert.match(source, /security definer/i);
  assert.match(source, /is_suspended = false/);
});
