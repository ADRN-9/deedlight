const HEX_256 = /^[a-f0-9]{64}$/;
const HEX_160 = /^[a-f0-9]{40}$/;
const RELATION = /^[A-Za-z_][A-Za-z0-9_$]*$/;
const exact = (value, keys) => value && typeof value === "object" && !Array.isArray(value)
  && Object.keys(value).sort().join(",") === [...keys].sort().join(",");
const relation = value => exact(value, ["schema", "relation"])
  && RELATION.test(value.schema) && RELATION.test(value.relation);
const timestamp = value => typeof value === "string"
  && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(value)
  && Number.isFinite(Date.parse(value));

export function validateCategoryEffectContract(category, effect, inventoryPaths, { requireEvidence = true } = {}) {
  if (!["dataTransformations", "backfills", "dependencies", "preconditions", "postconditions"].includes(category)) return null;
  const contract = effect && effect.contract;
  if (!contract || typeof contract !== "object" || Array.isArray(contract)) return category + " effect is missing its category-specific contract";
  if (category === "dataTransformations") {
    if (!exact(contract, ["operation", "sourceRelations", "targetRelation", "predicate", "sourceStatementSha256"])
      || !["INSERT_SELECT", "UPDATE", "DELETE", "UPSERT", "MERGE"].includes(contract.operation)
      || !Array.isArray(contract.sourceRelations) || !contract.sourceRelations.every(relation)
      || !relation(contract.targetRelation) || !HEX_256.test(contract.sourceStatementSha256 || "")) {
      return "transformation contract is malformed or lacks source/target relation binding";
    }
    if (contract.predicate !== null && (!exact(contract.predicate, ["sql", "sha256"])
      || typeof contract.predicate.sql !== "string" || !contract.predicate.sql.trim()
      || !HEX_256.test(contract.predicate.sha256 || ""))) return "transformation predicate is malformed or unbound";
    return null;
  }
  if (category === "backfills") {
    if (!exact(contract, ["targetRelation", "predicate", "measurement", "sourceStatementSha256"])
      || !relation(contract.targetRelation) || !exact(contract.predicate, ["sql", "sha256"])
      || typeof contract.predicate.sql !== "string" || !contract.predicate.sql.trim()
      || !HEX_256.test(contract.predicate.sha256 || "") || !HEX_256.test(contract.sourceStatementSha256 || "")) {
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
      || !HEX_160.test(measurement.sourceBlobSha1 || "") || !inventoryPaths.has(effect.sourcePath)) {
      return "backfill requires an independently evidenced non-negative measurement bound to the exact migration source";
    }
    return null;
  }
  if (category === "dependencies") {
    if (!exact(contract, ["dependencyType", "fromRelation", "toRelation", "dependsOnMigrationPath", "sourceStatementSha256"])
      || !["foreign_key", "view_source", "routine_call", "data_order"].includes(contract.dependencyType)
      || !relation(contract.fromRelation) || !relation(contract.toRelation)
      || typeof contract.dependsOnMigrationPath !== "string" || !inventoryPaths.has(contract.dependsOnMigrationPath)
      || contract.dependsOnMigrationPath === effect.sourcePath
      || !HEX_256.test(contract.sourceStatementSha256 || "")) {
      return "dependency contract must bind a typed relation edge to a distinct pinned prerequisite migration";
    }
    return null;
  }
  if (category === "preconditions" || category === "postconditions") {
    if (!exact(contract, ["predicateSql", "predicateSha256", "expectedOutcome", "verification"])
      || typeof contract.predicateSql !== "string" || !contract.predicateSql.trim()
      || !HEX_256.test(contract.predicateSha256 || "")
      || !["true", "false", "zero_rows", "nonzero_rows"].includes(contract.expectedOutcome)) {
      return category + " contract must bind a predicate and explicit expected outcome";
    }
    const verification = contract.verification;
    if (exact(verification, ["status", "reason"]) && verification.status === "not_verified"
      && typeof verification.reason === "string" && verification.reason.trim().length >= 20) {
      return requireEvidence ? category + " is source-declared but has no independently verified execution outcome" : null;
    }
    if (!exact(verification, ["status", "evidenceDigest", "querySha256", "capturedAt", "executionId"])
      || verification.status !== "independently_verified" || !HEX_256.test(verification.evidenceDigest || "")
      || !HEX_256.test(verification.querySha256 || "") || !timestamp(verification.capturedAt)
      || typeof verification.executionId !== "string" || !verification.executionId.trim()) {
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
