import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const expected = [
  "rejectOffering: distinct internal and member feedback, owner-safe render",
  "rejectOffering: internal-only note clears prior owner feedback",
  "rejectOffering: feedback-only transition never inherits an old internal note",
  "rejectOffering: empty fields clear both without implicit templates",
  "rejectOffering: rejects oversized private and public fields independently",
  "requestOfferingEdit: distinct internal and member feedback, owner-safe render",
  "requestOfferingEdit: internal-only note clears prior owner feedback",
  "requestOfferingEdit: feedback-only transition never inherits an old internal note",
  "requestOfferingEdit: empty fields clear both without implicit templates",
  "requestOfferingEdit: rejects oversized private and public fields independently",
  "hideOffering: distinct internal and member feedback, owner-safe render",
  "hideOffering: internal-only note clears prior owner feedback",
  "hideOffering: feedback-only transition never inherits an old internal note",
  "hideOffering: empty fields clear both without implicit templates",
  "hideOffering: rejects oversized private and public fields independently",
  "unauthorized member role claim cannot invoke any moderation action",
  "suspended database admin loses all moderation-action privileges",
  "admin detail forms present separately labeled and bound textarea fields",
  "member-facing projection excludes private staff fields and public view redacts anonymous identity"
];
const text = readFileSync(process.argv[2], "utf8");
const names = [...text.matchAll(/^ok\s+\d+\s+-\s+(.+)$/gm)].map((m) => m[1].trim());
assert.equal(names.length, 19, "All 19 application-action regressions must execute");
assert.deepEqual(names.sort(), [...expected].sort());
const summary = text.match(/^# tests (\d+)\n# suites (\d+)\n# pass (\d+)\n# fail (\d+)\n# cancelled (\d+)\n# skipped (\d+)\n# todo (\d+)$/m);
assert.ok(summary, "Missing complete TAP summary");
assert.deepEqual(summary.slice(1).map(Number), [19,0,19,0,0,0,0]);
console.log("RELEASE_ACTION_INVENTORY_PASS 19/19; none skipped, cancelled or failed");
