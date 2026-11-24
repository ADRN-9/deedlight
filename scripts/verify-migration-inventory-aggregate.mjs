import { createHash } from "node:crypto";
import {
  lstatSync,
  readFileSync,
  readdirSync,
  realpathSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";

const INVENTORY_RELATIVE = "supabase/migration-inventory.json";
const AGGREGATE_RELATIVE = "supabase/run_in_sql_editor_all.sql";
const SEED_RELATIVE = "supabase/seed.sql";
const COMPATIBILITY_RELATIVE = "supabase/bootstrap/migration_038_admin_compatibility.sql";
const EXPECTED_COMPATIBILITY_BLOB_SHA1 = "67f950183e9b2111ee6b6837813f7115ec336e2e";
const EXPECTED_INVENTORY_BLOB_SHA1 = "95d514a0bd97ff448c9507252eb1f5e69a507442";
const EXPECTED_DUPLICATES = {
  "202607260007": [
    "202607260007_sprint6_daily_deedlight.sql",
    "202607260007_sprint7_pwa_daily_engagement.sql",
  ],
};

export function gitBlobSha1(bytes) {
  const data = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes);
  return createHash("sha1")
    .update(Buffer.concat([Buffer.from(`blob ${data.length}\0`), data]))
    .digest("hex");
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function safeFile(rootDir, relativePath, label) {
  const absolute = path.resolve(rootDir, relativePath);
  const root = path.resolve(rootDir);
  assert(absolute.startsWith(root + path.sep), `${label}: path escapes repository root`);
  const stat = lstatSync(absolute);
  assert(stat.isFile() && !stat.isSymbolicLink(), `${label}: expected a regular non-symlink file`);
  assert(realpathSync(absolute).startsWith(realpathSync(root) + path.sep), `${label}: resolved path escapes repository root`);
  return readFileSync(absolute);
}

export function validateInventory(manifest) {
  assert(manifest && typeof manifest === "object" && !Array.isArray(manifest), "inventory must be a JSON object");
  assert(manifest.schemaVersion === 1, "unsupported inventory schema version");
  assert(manifest.expectedMigrationCount === 39, "inventory expectedMigrationCount must be 39");
  assert(manifest.expectedUniqueVersionCount === 38, "inventory expectedUniqueVersionCount must be 38");
  assert(Array.isArray(manifest.migrations) && manifest.migrations.length === 39, "inventory is truncated or has an unexpected migration count");
  assert(JSON.stringify(manifest.intentionalDuplicateVersionGroups) === JSON.stringify(EXPECTED_DUPLICATES), "intentional duplicate-version group differs from the approved 007 pair");
  const seenPaths = new Set();
  const versions = new Map();
  let previousPath = "";
  for (const item of manifest.migrations) {
    assert(item && typeof item === "object", "invalid migration inventory entry");
    assert(typeof item.path === "string" && /^supabase\/migrations\/\d{12}_[a-z0-9_]+\.sql$/.test(item.path), "invalid migration path in inventory");
    assert(!seenPaths.has(item.path), `duplicate migration inventory path: ${item.path}`);
    assert(item.path > previousPath, "migration inventory must be in deterministic filename order");
    previousPath = item.path;
    seenPaths.add(item.path);
    const filename = path.basename(item.path);
    const version = filename.slice(0, 12);
    assert(item.version === version, `version prefix mismatch for ${filename}`);
    assert(/^[a-f0-9]{40}$/.test(item.blobSha1), `invalid Git blob SHA-1 for ${filename}`);
    assert(Number.isSafeInteger(item.byteLength) && item.byteLength >= 0, `invalid byte length for ${filename}`);
    const group = versions.get(version) ?? [];
    group.push(filename);
    versions.set(version, group);
  }
  assert(versions.size === 38, "inventory does not contain exactly 38 unique version prefixes");
  for (const [version, names] of versions) {
    const approved = EXPECTED_DUPLICATES[version];
    assert(names.length === (approved ? 2 : 1), `unexpected duplicate migration version ${version}`);
    if (approved) assert(JSON.stringify(names) === JSON.stringify(approved), `duplicate migration version ${version} has substituted filenames`);
  }
  assert(manifest.bootstrapSeed?.path === SEED_RELATIVE, "bootstrap seed path is not approved");
  assert(/^[a-f0-9]{40}$/.test(manifest.bootstrapSeed.blobSha1), "invalid bootstrap seed Git blob SHA-1");
  assert(Number.isSafeInteger(manifest.bootstrapSeed.byteLength) && manifest.bootstrapSeed.byteLength > 0, "invalid bootstrap seed byte length");
  assert(manifest.bootstrapSeed.expectedUpsertCount === 3, "bootstrap seed must declare exactly three upserts");
  return true;
}

export function verifyMigrationInventory(rootDir, manifest, expectedInventoryBlobSha1 = EXPECTED_INVENTORY_BLOB_SHA1) {
  validateInventory(manifest);
  const inventoryBytes = readFileSync(path.join(rootDir, INVENTORY_RELATIVE));
  assert(gitBlobSha1(inventoryBytes) === expectedInventoryBlobSha1, "migration inventory manifest Git blob SHA-1 differs from its pinned value");
  const migrationDir = path.join(rootDir, "supabase/migrations");
  const actualEntries = readdirSync(migrationDir, { withFileTypes: true });
  const actualSql = [];
  for (const entry of actualEntries) {
    if (entry.isSymbolicLink()) throw new Error(`migration directory contains symlink: ${entry.name}`);
    if (entry.isFile() && entry.name.endsWith(".sql")) actualSql.push(entry.name);
  }
  actualSql.sort();
  const expectedNames = manifest.migrations.map((item) => path.basename(item.path));
  const expectedSet = new Set(expectedNames);
  const actualSet = new Set(actualSql);
  const missing = expectedNames.filter((name) => !actualSet.has(name));
  const unexpected = actualSql.filter((name) => !expectedSet.has(name));
  const hashes = new Map();
  for (const name of actualSql) {
    const bytes = safeFile(rootDir, `supabase/migrations/${name}`, name);
    hashes.set(name, gitBlobSha1(bytes));
  }
  const renamed = [];
  for (const missingName of missing) {
    const expected = manifest.migrations.find((item) => path.basename(item.path) === missingName);
    const substitute = unexpected.find((name) => hashes.get(name) === expected.blobSha1);
    if (substitute) renamed.push(`${missingName} -> ${substitute}`);
  }
  const modified = [];
  for (const item of manifest.migrations) {
    const name = path.basename(item.path);
    if (!actualSet.has(name)) continue;
    const bytes = safeFile(rootDir, item.path, name);
    const actualHash = gitBlobSha1(bytes);
    if (actualHash !== item.blobSha1 || bytes.length !== item.byteLength) {
      modified.push(`${name} expected=${item.blobSha1}/${item.byteLength} actual=${actualHash}/${bytes.length}`);
    }
  }
  const seed = safeFile(rootDir, SEED_RELATIVE, "bootstrap seed");
  const compatibility = safeFile(rootDir, COMPATIBILITY_RELATIVE, "Migration 038 compatibility artifact");
  assert(gitBlobSha1(compatibility) === EXPECTED_COMPATIBILITY_BLOB_SHA1, "Migration 038 compatibility artifact Git blob SHA-1 differs from its pinned value");
  const seedHash = gitBlobSha1(seed);
  const seedText = seed.toString("utf8");
  const upsertCount = (seedText.match(/\binsert\s+into\b/gi) ?? []).length;
  const conflictCount = (seedText.match(/\bon\s+conflict\b/gi) ?? []).length;
  const seedProblems = [];
  if (seedHash !== manifest.bootstrapSeed.blobSha1 || seed.length !== manifest.bootstrapSeed.byteLength) {
    seedProblems.push("bootstrap seed bytes differ from the pinned Git blob");
  }
  if (upsertCount !== manifest.bootstrapSeed.expectedUpsertCount || conflictCount !== manifest.bootstrapSeed.expectedUpsertCount) {
    seedProblems.push(`expected 3 upserts with conflict handling; found ${upsertCount} INSERT and ${conflictCount} ON CONFLICT clauses`);
  }
  const problems = [];
  if (missing.length) problems.push(`missing migrations: ${missing.join(", ")}`);
  if (unexpected.length) problems.push(`unexpected migrations: ${unexpected.join(", ")}`);
  if (renamed.length) problems.push(`renamed migrations: ${renamed.join(", ")}`);
  if (modified.length) problems.push(`modified migrations: ${modified.join("; ")}`);
  if (seedProblems.length) problems.push(...seedProblems);
  if (actualSql.length !== 39) problems.push(`actual migration file count is ${actualSql.length}, expected 39`);
  if (problems.length) throw new Error(problems.join("\n"));
  return { migrationCount: actualSql.length, uniqueVersionCount: 38, seedUpsertCount: upsertCount };
}

export function buildAggregate(rootDir, manifest, expectedInventoryBlobSha1 = EXPECTED_INVENTORY_BLOB_SHA1) {
  verifyMigrationInventory(rootDir, manifest, expectedInventoryBlobSha1);
  const inventoryBytes = readFileSync(path.join(rootDir, INVENTORY_RELATIVE));
  const lines = [
    "-- DeedLight SQL Editor aggregate v1",
    "-- Deterministically generated from immutable Git-blob-pinned migration sources and the maintained bootstrap seed.",
    `-- Inventory Git blob SHA-1: ${gitBlobSha1(inventoryBytes)}`,
    "-- BEGIN SOURCE PROVENANCE",
  ];
  for (const item of manifest.migrations) {
    lines.push(`-- SOURCE ${item.version} ${path.basename(item.path)} blob=${item.blobSha1} bytes=${item.byteLength}`);
  }
  const compatibility = safeFile(rootDir, COMPATIBILITY_RELATIVE, "Migration 038 compatibility artifact");
  lines.push(
    `-- BOOTSTRAP SEED ${SEED_RELATIVE} blob=${manifest.bootstrapSeed.blobSha1} bytes=${manifest.bootstrapSeed.byteLength} upserts=3`,
    `-- COMPATIBILITY ${COMPATIBILITY_RELATIVE} blob=${EXPECTED_COMPATIBILITY_BLOB_SHA1} bytes=${compatibility.length} placement=after-202611240037-before-202611240038`,
    "-- END SOURCE PROVENANCE",
    "-- BEGIN MIGRATION SQL",
  );
  const chunks = [Buffer.from(lines.join("\n") + "\n")];
  const seed = safeFile(rootDir, SEED_RELATIVE, "bootstrap seed");
  for (let index = 0; index < manifest.migrations.length; index += 1) {
    const item = manifest.migrations[index];
    chunks.push(safeFile(rootDir, item.path, path.basename(item.path)));
    if (item.version === "202611240037") {
      chunks.push(Buffer.from("\\n-- BEGIN MIGRATION 038 ADMIN COMPATIBILITY\\n"));
      chunks.push(compatibility);
      chunks.push(Buffer.from("\\n-- END MIGRATION 038 ADMIN COMPATIBILITY\\n"));
    }
    if (index === 1) {
      chunks.push(Buffer.from("\n-- BEGIN BOOTSTRAP SEED (three idempotent upserts)\n"));
      chunks.push(seed);
      chunks.push(Buffer.from("\n-- END BOOTSTRAP SEED\n"));
    }
  }
  chunks.push(Buffer.from("\n-- END MIGRATION SQL\n"));
  return Buffer.concat(chunks);
}

export function verifyAggregate(rootDir, manifest, aggregatePath = AGGREGATE_RELATIVE, expectedInventoryBlobSha1 = EXPECTED_INVENTORY_BLOB_SHA1) {
  const expected = buildAggregate(rootDir, manifest, expectedInventoryBlobSha1);
  const actual = safeFile(rootDir, aggregatePath, "committed SQL aggregate");
  if (!actual.equals(expected)) {
    let offset = 0;
    while (offset < actual.length && offset < expected.length && actual[offset] === expected[offset]) offset += 1;
    throw new Error(`SQL aggregate differs from deterministic generation at byte ${offset}; committed=${actual.length} bytes expected=${expected.length} bytes`);
  }
  return { aggregateBytes: actual.length, aggregateSha256: sha256(actual) };
}

function main() {
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length === 1 && args[0] !== "--write")) {
    throw new Error("usage: node scripts/verify-migration-inventory-aggregate.mjs [--write]");
  }
  const rootDir = process.cwd();
  const manifest = JSON.parse(readFileSync(path.join(rootDir, INVENTORY_RELATIVE), "utf8"));
  const inventory = verifyMigrationInventory(rootDir, manifest);
  if (args[0] === "--write") {
    const generated = buildAggregate(rootDir, manifest);
    writeFileSync(path.join(rootDir, AGGREGATE_RELATIVE), generated);
    process.stdout.write(`Generated ${AGGREGATE_RELATIVE}: ${generated.length} bytes\n`);
    return;
  }
  const aggregate = verifyAggregate(rootDir, manifest);
  process.stdout.write(`Migration inventory PASS: ${inventory.migrationCount} files, ${inventory.uniqueVersionCount} unique versions, duplicate 007 pair preserved\n`);
  process.stdout.write(`Bootstrap seed PASS: ${inventory.seedUpsertCount} upserts\n`);
  process.stdout.write(`SQL aggregate PASS: ${aggregate.aggregateBytes} bytes SHA-256 ${aggregate.aggregateSha256}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname)) {
  main();
}
