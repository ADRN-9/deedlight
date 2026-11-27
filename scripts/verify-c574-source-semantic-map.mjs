import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = process.cwd();
const inventoryPath = path.join(root, "supabase/migration-inventory.json");
const mapPath = path.join(root, "docs/c574-migration-source-semantic-map.json");
const inventoryBytes = readFileSync(inventoryPath);
const inventory = JSON.parse(inventoryBytes.toString("utf8"));
const mapping = JSON.parse(readFileSync(mapPath, "utf8"));

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function gitBlobSha1(bytes) {
  const body = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes);
  return createHash("sha1")
    .update(Buffer.concat([Buffer.from(`blob ${body.length}\0`), body]))
    .digest("hex");
}

const requiredDomains = [
  "dataTransformations",
  "backfills",
  "dependencies",
  "preconditions",
  "postconditions",
];

export function verifyC574SourceMap({ rootDir = root, inventory: sourceInventory = inventory, map = mapping } = {}) {
  assert(map.schemaVersion === 1, "unsupported C574 mapping schema");
  assert(map.project === "DeedLight", "mapping project mismatch");
  assert(map.status === "SOURCE_OBSERVATIONS_ONLY_NOT_SEMANTIC_VERIFICATION", "mapping must remain source-observations-only");
  assert(map.authorizationBoundary?.catalogContract === "catalog_only_v1", "catalog_only_v1 boundary changed");
  assert(map.authorizationBoundary?.changed === false, "C574 must not change catalog authorization");
  assert(map.authorizationBoundary?.nonCatalogLifecycleDomainsAccepted === false, "non-catalog acceptance must remain disabled");
  assert(map.inventory?.gitBlobSha1 === gitBlobSha1(readFileSync(path.join(rootDir, "supabase/migration-inventory.json"))), "inventory Git blob SHA-1 mismatch");
  assert(sourceInventory.expectedMigrationCount === 40, "expected 40 inventory entries");
  assert(Array.isArray(sourceInventory.migrations) && sourceInventory.migrations.length === 40, "inventory entry count mismatch");
  assert(new Set(sourceInventory.migrations.map(x => x.version)).size === 39, "expected 39 unique versions");
  assert(Array.isArray(map.entries) && map.entries.length === 40, "mapping must cover exactly 40 entries");

  const inventoryByPath = new Map(sourceInventory.migrations.map(item => [item.path, item]));
  const mappedPaths = new Set();
  const mappedSources = new Set();

  for (const entry of map.entries) {
    const source = entry.source;
    assert(source && typeof source.path === "string", "mapping source path missing");
    assert(!mappedPaths.has(source.path), `duplicate mapping path: ${source.path}`);
    mappedPaths.add(source.path);
    const expected = inventoryByPath.get(source.path);
    assert(expected, `mapping path is not in pinned inventory: ${source.path}`);
    assert(source.version === expected.version, `migration version mismatch: ${source.path}`);
    assert(source.gitBlobSha1 === expected.blobSha1, `source Git blob mismatch: ${source.path}`);
    assert(source.byteLength === expected.byteLength, `source byte length mismatch: ${source.path}`);
    assert(source.sourceIdentityKey === `${source.path}@${source.gitBlobSha1}`, `source identity key mismatch: ${source.path}`);
    assert(!mappedSources.has(source.sourceIdentityKey), `duplicate source identity: ${source.sourceIdentityKey}`);
    mappedSources.add(source.sourceIdentityKey);

    const bytes = readFileSync(path.join(rootDir, source.path));
    assert(bytes.length === source.byteLength, `working-tree byte length mismatch: ${source.path}`);
    assert(gitBlobSha1(bytes) === source.gitBlobSha1, `working-tree source blob mismatch: ${source.path}`);
    assert(Array.isArray(entry.sourceConstructsObserved) && entry.sourceConstructsObserved.length > 0, `source construct observations missing: ${source.path}`);
    assert(Array.isArray(entry.qualifiedReferenceTokens), `qualified token list missing: ${source.path}`);
    assert(entry.referenceInterpretation.includes("No AST"), `qualified tokens misrepresented as semantic identities: ${source.path}`);
    assert(entry.executionOrder?.historicalExecutionOrder === "UNKNOWN", `historical execution order must remain UNKNOWN: ${source.path}`);
    assert(entry.executionOrder?.basis === "INVENTORY_FILENAME_ORDER_ONLY", `execution ordering basis mismatch: ${source.path}`);
    assert(Array.isArray(entry.executionOrder.independentlyJustifiedEdges) && entry.executionOrder.independentlyJustifiedEdges.length === 0, `unjustified execution edge present: ${source.path}`);
    assert(Array.isArray(entry.dependencyCandidates) && entry.dependencyCandidates.length === 0, `unverified dependency edge present: ${source.path}`);
    assert(entry.semanticAcceptance === "NOT_ACCEPTED", `semantic acceptance must remain blocked: ${source.path}`);
    for (const domain of requiredDomains) {
      assert(entry.lifecycleDomains?.[domain]?.status === "UNKNOWN", `lifecycle domain must remain UNKNOWN: ${source.path} / ${domain}`);
      assert(entry.lifecycleDomains[domain].reasonCode === "POSTGRES_SEMANTIC_RESOLVER_NOT_IMPLEMENTED", `unexpected lifecycle reason: ${source.path} / ${domain}`);
    }
    for (const token of entry.qualifiedReferenceTokens) {
      assert(/^(public|auth|storage|extensions|pg_catalog|information_schema)\.[A-Za-z_][A-Za-z0-9_$]*$/.test(token.token), `invalid qualified reference token: ${source.path}`);
      assert(token.identityStatus === "UNRESOLVED_LEXICAL_REFERENCE", `reference token must remain unresolved: ${source.path}`);
      assert(token.semanticResolution === "NOT_PERFORMED", `semantic resolution must not be claimed: ${source.path}`);
    }
  }

  assert(mappedPaths.size === 40, "mapping path coverage incomplete");
  for (const item of sourceInventory.migrations) assert(mappedPaths.has(item.path), `inventory entry unmapped: ${item.path}`);

  const duplicate007 = map.entries.filter(x => x.source.version === "202607260007");
  assert(duplicate007.length === 2, "both distinct Migration 007 sources must be preserved");
  assert(new Set(duplicate007.map(x => x.source.gitBlobSha1)).size === 2, "Migration 007 source identities collapsed");
  assert(new Set(duplicate007.map(x => x.source.path)).size === 2, "Migration 007 paths collapsed");
  assert(map.entries.some(x => x.source.path.endsWith("202611260039_delivery_kind_scoped_claims.sql")), "Migration 039 missing");
  assert(map.literalDistinctions?.sourceBytesPreservedByGitBlobIdentity === true, "literal source bytes preservation missing");
  assert(map.literalDistinctions?.sqlNullKeywordDistinctFromQuotedEmptyString === true, "SQL NULL / empty-string distinction missing");
  assert(map.literalDistinctions?.quotedBackslashNDistinctFromSqlNull === true, "quoted backslash-N distinction missing");
  assert(map.literalDistinctions?.normalizationPerformed === false, "source normalization is forbidden");
  return {
    status: "PASS",
    migrationCount: mappedPaths.size,
    uniqueVersionCount: new Set(sourceInventory.migrations.map(x => x.version)).size,
    qualifiedReferenceTokenCount: map.entries.reduce((n, x) => n + x.qualifiedReferenceTokens.length, 0),
    lifecycleDomainCount: requiredDomains.length,
    semanticAcceptance: "NOT_ACCEPTED",
    catalogAuthorization: "catalog_only_v1",
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.stdout.write(JSON.stringify(verifyC574SourceMap(), null, 2) + "\n");
}
