import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { verifyC574SourceMap } from "./verify-c574-source-semantic-map.mjs";

const mapping = JSON.parse(readFileSync("docs/c574-migration-source-semantic-map.json", "utf8"));

function classifyFixtureLexeme(value) {
  if (value === "NULL") return "SQL_NULL_KEYWORD";
  if (value === "'" + String.fromCharCode(92) + "N'") return "QUOTED_BACKSLASH_N_STRING";
  if (value === "''") return "QUOTED_EMPTY_STRING";
  if (/^'.*'$/.test(value)) return "QUOTED_STRING";
  return "OTHER";
}

test("C574 mapping covers all 40 exact inventory source identities", () => {
  const result = verifyC574SourceMap();
  assert.equal(result.status, "PASS");
  assert.equal(result.migrationCount, 40);
  assert.equal(result.uniqueVersionCount, 39);
  assert.equal(result.lifecycleDomainCount, 5);
  assert.equal(result.semanticAcceptance, "NOT_ACCEPTED");
});

test("both Migration 007 source files remain separate source identities", () => {
  const pair = mapping.entries.filter(x => x.source.version === "202607260007");
  assert.equal(pair.length, 2);
  assert.notEqual(pair[0].source.path, pair[1].source.path);
  assert.notEqual(pair[0].source.gitBlobSha1, pair[1].source.gitBlobSha1);
});

test("Migration 039 remains pinned", () => {
  assert.ok(mapping.entries.some(x => x.source.path.endsWith("202611260039_delivery_kind_scoped_claims.sql")));
});

test("all five non-catalog lifecycle domains remain UNKNOWN for every migration", () => {
  for (const entry of mapping.entries) {
    for (const domain of ["dataTransformations", "backfills", "dependencies", "preconditions", "postconditions"]) {
      assert.equal(entry.lifecycleDomains[domain].status, "UNKNOWN");
      assert.equal(entry.semanticAcceptance, "NOT_ACCEPTED");
    }
  }
});

test("lexical reference tokens never masquerade as resolved PostgreSQL identities", () => {
  for (const entry of mapping.entries) {
    for (const reference of entry.qualifiedReferenceTokens) {
      assert.equal(reference.identityStatus, "UNRESOLVED_LEXICAL_REFERENCE");
      assert.equal(reference.semanticResolution, "NOT_PERFORMED");
    }
  }
});

test("inventory filename ordering is not represented as historical execution order", () => {
  for (const entry of mapping.entries) {
    assert.equal(entry.executionOrder.basis, "INVENTORY_FILENAME_ORDER_ONLY");
    assert.equal(entry.executionOrder.historicalExecutionOrder, "UNKNOWN");
    assert.deepEqual(entry.executionOrder.independentlyJustifiedEdges, []);
    assert.deepEqual(entry.dependencyCandidates, []);
  }
});

test("SQL NULL, quoted backslash-N and quoted empty string remain distinct lexemes", () => {
  const tokens = ["NULL", "'" + String.fromCharCode(92) + "N'", "''"];
  assert.deepEqual(tokens.map(classifyFixtureLexeme), [
    "SQL_NULL_KEYWORD",
    "QUOTED_BACKSLASH_N_STRING",
    "QUOTED_EMPTY_STRING",
  ]);
  assert.equal(new Set(tokens).size, 3);
});

test("the artifact pins source bytes without claiming a parser or execution", () => {
  assert.equal(mapping.sourceReviewMethod.includes("No PostgreSQL parser"), true);
  assert.equal(mapping.executionPolicy.includes("No migration execution"), true);
  assert.equal(mapping.authorizationBoundary.catalogContract, "catalog_only_v1");
  assert.equal(mapping.authorizationBoundary.changed, false);
});
