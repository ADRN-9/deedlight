import { createHash } from "node:crypto";
const HEX_256 = /^[a-f0-9]{64}$/;
const HEX_160 = /^[a-f0-9]{40}$/;
const RELATION = /^[A-Za-z_][A-Za-z0-9_$]*$/;
const exact = (value, keys) => value && typeof value === "object" && !Array.isArray(value)
  && Object.keys(value).sort().join(",") === [...keys].sort().join(",");
const relation = value => exact(value, ["schema", "relation"])
  && RELATION.test(value.schema) && RELATION.test(value.relation);
const timestamp = value => typeof value === "string"
  && /^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$/.test(value)
  && Number.isFinite(Date.parse(value)) && new Date(Date.parse(value)).toISOString() === value;

export function validateCategoryEffectContract(category, effect, inventoryPaths, { requireEvidence = true, sourceText = null } = {}) {
  if (!["dataTransformations", "backfills", "dependencies", "preconditions", "postconditions"].includes(category)) return null;
  const contract = effect && effect.contract;
  if (!contract || typeof contract !== "object" || Array.isArray(contract)) return category + " effect is missing its category-specific contract";
  if (!sourceText || typeof sourceText !== "string") return category + " effect cannot be source-bound without the pinned SQL bytes";
  const range = contract.sourceRange;
  if (!exact(range, ["startLine", "endLine"]) || !Number.isSafeInteger(range.startLine) || !Number.isSafeInteger(range.endLine)
    || range.startLine < 1 || range.endLine < range.startLine) return category + " effect has an invalid source range";
  const sourceLines = sourceText.split(/\r?\n/);
  if (range.endLine > sourceLines.length) return category + " effect source range exceeds pinned SQL line count";
  const sourceStatement = sourceLines.slice(range.startLine - 1, range.endLine).join("\n");
  const sourceDigest = createHash("sha256").update(sourceStatement, "utf8").digest("hex");
  const digestText = value => createHash("sha256").update(value, "utf8").digest("hex");
  if (sourceDigest !== contract.sourceStatementSha256) return category + " effect source-statement fingerprint does not match the pinned SQL range";
  if (category === "dataTransformations") {
    if (!exact(contract, ["operation", "sourceRelations", "targetRelation", "predicate", "sourceRange", "sourceStatementSha256"])
      || !["INSERT_SELECT", "UPDATE", "DELETE", "UPSERT", "MERGE"].includes(contract.operation)
      || !Array.isArray(contract.sourceRelations) || !contract.sourceRelations.every(relation)
      || !relation(contract.targetRelation) || !HEX_256.test(contract.sourceStatementSha256 || "")) {
      return "transformation contract is malformed or lacks source/target relation binding";
    }
    if (contract.predicate !== null && (!exact(contract.predicate, ["sql", "sha256"])
      || typeof contract.predicate.sql !== "string" || !contract.predicate.sql.trim()
      || !HEX_256.test(contract.predicate.sha256 || "") || digestText(contract.predicate.sql) !== contract.predicate.sha256)) return "transformation predicate is malformed or unbound";
    return null;
  }
  if (category === "backfills") {
    if (!exact(contract, ["targetRelation", "predicate", "measurement", "sourceRange", "sourceStatementSha256"])
      || !relation(contract.targetRelation) || !exact(contract.predicate, ["sql", "sha256"])
      || typeof contract.predicate.sql !== "string" || !contract.predicate.sql.trim()
      || !HEX_256.test(contract.predicate.sha256 || "") || digestText(contract.predicate.sql) !== contract.predicate.sha256 || !HEX_256.test(contract.sourceStatementSha256 || "")) {
      return "backfill contract must bind target, predicate and source statement";
    }
    const measurement = contract.measurement;
    if (exact(measurement, ["status", "reason"]) && measurement.status === "not_measured"
      && typeof measurement.reason === "string" && measurement.reason.trim().length >= 20) {
      return requireEvidence ? "backfill measurement is unavailable; source SQL cannot establish affected-row counts" : null;
    }
    if (!exact(measurement, ["status", "rowCount", "querySha256", "evidenceDigest", "capturedAt", "executionId", "sourceBlobSha1"])
      || measurement.status !== "independently_measured" || !Number.isSafeInteger(measurement.rowCount) || measurement.rowCount < 0
      || !HEX_256.test(measurement.querySha256 || "") || !HEX_256.test(measurement.evidenceDigest || "")
      || !timestamp(measurement.capturedAt) || typeof measurement.executionId !== "string" || !measurement.executionId.trim()
      || !HEX_160.test(measurement.sourceBlobSha1 || "") || measurement.sourceBlobSha1 !== inventoryPaths.get(effect.sourcePath)) {
      return "backfill requires an independently evidenced non-negative measurement bound to the exact migration source";
    }
    return null;
  }
  if (category === "dependencies") {
    if (!exact(contract, ["dependencyType", "fromRelation", "toRelation", "dependsOnMigrationPath", "dependsOnMigrationBlobSha1", "sourceRange", "sourceStatementSha256"])
      || !["foreign_key", "view_source", "routine_call", "data_order"].includes(contract.dependencyType)
      || !relation(contract.fromRelation) || !relation(contract.toRelation)
      || typeof contract.dependsOnMigrationPath !== "string" || !inventoryPaths.has(contract.dependsOnMigrationPath)
      || contract.dependsOnMigrationPath === effect.sourcePath
      || contract.dependsOnMigrationBlobSha1 !== inventoryPaths.get(contract.dependsOnMigrationPath)
      || !HEX_256.test(contract.sourceStatementSha256 || "")) {
      return "dependency contract must bind a typed relation edge to a distinct pinned prerequisite migration";
    }
    return null;
  }
  if (category === "preconditions" || category === "postconditions") {
    if (!exact(contract, ["predicateSql", "predicateSha256", "expectedOutcome", "verification", "sourceRange", "sourceStatementSha256"])
      || typeof contract.predicateSql !== "string" || !contract.predicateSql.trim()
      || !HEX_256.test(contract.predicateSha256 || "") || digestText(contract.predicateSql) !== contract.predicateSha256
      || !["true", "false", "zero_rows", "nonzero_rows"].includes(contract.expectedOutcome)) {
      return category + " contract must bind a predicate and explicit expected outcome";
    }
    const verification = contract.verification;
    if (exact(verification, ["status", "reason"]) && verification.status === "not_verified"
      && typeof verification.reason === "string" && verification.reason.trim().length >= 20) {
      return requireEvidence ? category + " is source-declared but has no independently verified execution outcome" : null;
    }
    if (!exact(verification, ["status", "evidenceDigest", "querySha256", "capturedAt", "executionId", "sourceBlobSha1"])
      || verification.status !== "independently_verified" || !HEX_256.test(verification.evidenceDigest || "")
      || !HEX_256.test(verification.querySha256 || "") || !timestamp(verification.capturedAt)
      || typeof verification.executionId !== "string" || !verification.executionId.trim()
      || verification.sourceBlobSha1 !== inventoryPaths.get(effect.sourcePath)) {
      return category + " requires an independently evidenced predicate outcome";
    }
    return null;
  }
  return "unsupported effect category";
}

export function categoryEffectKeys(category) {
  return ["dataTransformations", "backfills", "dependencies", "preconditions", "postconditions"].includes(category)
    ? ["contract", "description", "fingerprint", "identity", "kind", "sourcePath"]
    : ["description", "fingerprint", "identity", "kind"];
}
