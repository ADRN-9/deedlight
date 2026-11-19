import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const path = process.argv[2];
assert.ok(path, "Usage: node scripts/verify-dependency-audit.mjs <npm-audit.json>");
const report = JSON.parse(readFileSync(path, "utf8"));
const counts = report.metadata?.vulnerabilities;
assert.ok(counts && ["critical", "high", "moderate", "low", "info", "total"]
  .every((key) => Number.isSafeInteger(counts[key]) && counts[key] >= 0),
"npm audit did not return complete vulnerability counts");
assert.equal(counts.critical, 0, "Critical dependency advisories remain");
assert.equal(counts.high, 0, "High dependency advisories remain");
console.log(
  "DEPENDENCY_AUDIT_PASS high=0 critical=0 " +
  "moderate=" + counts.moderate + " low=" + counts.low +
  " info=" + counts.info + " total=" + counts.total
);
