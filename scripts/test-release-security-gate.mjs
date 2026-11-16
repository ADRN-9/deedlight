import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { cpSync, mkdtempSync, readFileSync, renameSync, rmSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";

const original = resolve("release-downloaded");
const baseline = JSON.parse(process.env.NEEDS_JSON ?? "{}");
const expectedSha = process.env.EXPECTED_SHA;
const expectedTree = process.env.EXPECTED_TREE;

function runTamper(name, alter) {
  const root = mkdtempSync(join(tmpdir(), "c105-security-gate-"));
  const evidence = join(root, "evidence");
  try {
    cpSync(original, evidence, { recursive: true });
    const needs = JSON.parse(JSON.stringify(baseline));
    alter({ needs, evidence });
    const run = spawnSync(process.execPath,
      ["scripts/verify-release-security-gate.mjs"], {
        cwd: process.cwd(),
        encoding: "utf8",
        env: {
          ...process.env,
          EVIDENCE_ROOT: evidence,
          NEEDS_JSON: JSON.stringify(needs),
          EXPECTED_SHA: expectedSha,
          EXPECTED_TREE: expectedTree,
        },
      });
    assert.notEqual(run.status, 0, name + " must fail closed; stderr " + run.stderr.slice(0, 250));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

for (const disposition of ["failure", "skipped", "cancelled", "neutral"]) {
  test("required job " + disposition + " fails the final gate", () => {
    runTamper(disposition, ({ needs }) => {
      needs.release_privacy_pg16.result = disposition;
    });
  });
}

test("missing mandatory job fails the final gate", () => {
  runTamper("missing job", ({ needs }) => {
    delete needs.release_action_privacy;
  });
});

test("mismatched source commit fails the final gate", () => {
  runTamper("mismatched SHA", ({ evidence }) => {
    writeFileSync(join(evidence, "release-evidence-release_webhook_http", "commit.txt"),
      "0000000000000000000000000000000000000000\n");
  });
});

test("mismatched tree fails the final gate", () => {
  runTamper("mismatched tree", ({ evidence }) => {
    writeFileSync(join(evidence, "release-evidence-release_provider_pg16", "tree.txt"),
      "0000000000000000000000000000000000000000\n");
  });
});

test("missing expected privacy artifact fails the final gate", () => {
  runTamper("missing privacy evidence", ({ evidence }) => {
    unlinkSync(join(evidence, "release-evidence-release_privacy_pg16", "privacy.log"));
  });
});

test("missing required attestation fails the final gate", () => {
  runTamper("missing PASS attestation", ({ evidence }) => {
    unlinkSync(join(evidence, "release-evidence-validate", "result.txt"));
  });
});

test("skipped assertion inventory fails the final gate", () => {
  runTamper("missing inventory", ({ evidence }) => {
    writeFileSync(join(evidence, "release-evidence-release_action_privacy", "inventory.txt"),
      "INCOMPLETE 18/19\n");
  });
});
