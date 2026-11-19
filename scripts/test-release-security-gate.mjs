import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  cpSync, mkdtempSync, readFileSync, readdirSync,
  rmSync, unlinkSync, writeFileSync, renameSync, mkdirSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";

const rootEvidence = resolve("release-downloaded");
const rootPlatform = resolve("release-platform");
const rootArchives = resolve("release-archives");
const baselineNeeds = JSON.parse(process.env.NEEDS_JSON ?? "{}");
const runId = process.env.EXPECTED_RUN_ID;
const runAttempt = process.env.EXPECTED_RUN_ATTEMPT;
const sha = process.env.EXPECTED_SHA;
const tree = process.env.EXPECTED_TREE;
const prefix = (job, attempt = runAttempt) =>
  "release-evidence-" + job + "-run-" + runId + "-attempt-" + attempt;
const privacyName = prefix("release_privacy_pg16");
const actionName = prefix("release_action_privacy");
const providerName = prefix("release_provider_pg16");
const racesName = prefix("release_consent_races");
const webhookName = prefix("release_webhook_http");
const allJobs = Object.keys(baselineNeeds);

function readJson(path) { return JSON.parse(readFileSync(path, "utf8")); }
function writeJson(path, data) { writeFileSync(path, JSON.stringify(data, null, 2) + "\n"); }
function expectGate(description, mutate = () => {}, mustPass = false) {
  const work = mkdtempSync(join(tmpdir(), "deedlight-c107-gate-"));
  try {
    const evidence = join(work, "evidence");
    const platform = join(work, "platform");
    const archives = join(work, "archives");
    cpSync(rootEvidence, evidence, { recursive: true });
    cpSync(rootPlatform, platform, { recursive: true });
    cpSync(rootArchives, archives, { recursive: true });
    const needs = structuredClone(baselineNeeds);
    const context = {
      evidence, platform, needs,
      vars: {
        ...process.env,
        EVIDENCE_ROOT: evidence,
        PLATFORM_METADATA_DIR: platform,
        ARCHIVE_ROOT: archives,
        GH_TOKEN: "",
        NEEDS_JSON: JSON.stringify(needs),
      },
      receipt(job) { return join(evidence, prefix(job), "receipt.json"); },
      artifact(job, file) { return join(evidence, prefix(job), file); },
      artifactZip(job) {
        const metadata = readJson(join(platform, "artifacts.json"));
        const item = metadata.artifacts.find((x) => x.name === prefix(job));
        assert.ok(item, "Missing artifact metadata for test job " + job);
        return join(archives, String(item.id) + ".zip");
      },
      artifactMetadata() { return join(platform, "artifacts.json"); },
      jobsMetadata() { return join(platform, "jobs.json"); },
      attemptMetadata() { return join(platform, "attempt.json"); },
    };
    mutate(context);
    context.vars.NEEDS_JSON = JSON.stringify(needs);
    const p = spawnSync(process.execPath, [
      "scripts/verify-release-security-gate.mjs"
    ], { cwd: process.cwd(), encoding: "utf8", env: context.vars });
    if (mustPass) {
      assert.equal(p.status, 0,
        description + " positive control must pass: " + p.stderr.slice(0, 800));
      assert.match(p.stdout, /RELEASE_SECURITY_GATE_PASS 11\/11/);
    } else {
      assert.notEqual(p.status, 0,
        description + " must fail closed (instead got " + p.stdout.slice(0, 250) + ")");
    }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}
function editReceipt(ctx, job, updater) {
  const p = ctx.receipt(job);
  const receipt = readJson(p);
  updater(receipt);
  writeJson(p, receipt);
}
function editPlatform(ctx, file, updater) {
  const p = join(ctx.platform, file);
  const data = readJson(p);
  updater(data);
  writeJson(p, data);
}

test("positive current-attempt control verifies all real downloaded evidence", () => {
  expectGate("current-attempt complete proof", () => {}, true);
});

for (const state of ["failure", "skipped", "cancelled", "neutral"]) {
  test("required job " + state + " fails the final gate", () => {
    expectGate("required state " + state, ({ needs }) => {
      needs.release_privacy_pg16.result = state;
    });
  });
}
test("missing mandatory job fails the final gate", () => {
  expectGate("missing job", ({ needs }) => { delete needs.release_action_privacy; });
});
test("mismatched source commit fails the final gate", () => {
  expectGate("wrong source SHA", (ctx) => {
    writeFileSync(ctx.artifact("release_webhook_http", "commit.txt"), "0".repeat(40) + "\n");
  });
});
test("mismatched tree fails the final gate", () => {
  expectGate("wrong Git tree", (ctx) => {
    writeFileSync(ctx.artifact("release_provider_pg16", "tree.txt"), "0".repeat(40) + "\n");
  });
});
test("missing expected privacy evidence file fails the final gate", () => {
  expectGate("missing privacy log", (ctx) => {
    unlinkSync(ctx.artifact("release_privacy_pg16", "privacy.log"));
  });
});
test("missing required PASS attestation fails the final gate", () => {
  expectGate("missing PASS", (ctx) => {
    unlinkSync(ctx.artifact("validate", "result.txt"));
  });
});
test("skipped assertion inventory fails the final gate", () => {
  expectGate("incomplete inventory", (ctx) => {
    writeFileSync(ctx.artifact("release_action_privacy", "inventory.txt"), "INCOMPLETE 18/19\n");
  });
});

test("wrong workflow-run receipt fails", () => {
  expectGate("wrong run ID", (ctx) => {
    editReceipt(ctx, "release_privacy_pg16", x => { x.run_id = String(Number(runId) + 1); });
  });
});
test("wrong workflow-attempt receipt fails", () => {
  expectGate("wrong attempt", (ctx) => {
    editReceipt(ctx, "release_action_privacy", x => { x.run_attempt += 1; });
  });
});
test("missing run identity fails", () => {
  expectGate("missing run", (ctx) => {
    editReceipt(ctx, "release_provider_pg16", x => { delete x.run_id; });
  });
});
test("missing attempt identity fails", () => {
  expectGate("missing attempt", (ctx) => {
    editReceipt(ctx, "release_provider_pg16", x => { delete x.run_attempt; });
  });
});
test("malformed or duplicate provenance fields fail", () => {
  expectGate("duplicate fields", (ctx) => {
    const p = ctx.receipt("release_privacy_pg16");
    const content = readFileSync(p, "utf8");
    writeFileSync(p, content.replace('"run_id":', '"run_id": "999",\n  "run_id":'));
  });
});
test("mixed-attempt artifact collection fails", () => {
  expectGate("mixed attempts", (ctx) => {
    editReceipt(ctx, "release_consent_races", x => { x.run_attempt += 1; });
    editPlatform(ctx, "artifacts.json", x => {
      const item = x.artifacts.find(a => a.name === racesName);
      item.name = prefix("release_consent_races", String(Number(runAttempt) + 1));
    });
  });
});
test("internally consistent but externally inconsistent attempt fails", () => {
  expectGate("forged attempt 99 using attempt-1 artifacts", (ctx) => {
    ctx.vars.EXPECTED_RUN_ATTEMPT = "99";
    for (const job of allJobs) {
      const p = ctx.receipt(job);
      const x = readJson(p);
      x.run_attempt = 99;
      x.artifact_name = prefix(job, "99");
      writeJson(p, x);
      renameSync(join(ctx.evidence, prefix(job)), join(ctx.evidence, prefix(job, "99")));
    }
    editPlatform(ctx, "artifacts.json", x => {
      for (const item of x.artifacts) item.name = item.name.replace(
        "-attempt-" + runAttempt, "-attempt-99");
    });
    // The GitHub attempt and job API metadata still says attempt 1.
  });
});
test("unexpected release-evidence artifact fails", () => {
  expectGate("extra platform artifact", (ctx) => {
    editPlatform(ctx, "artifacts.json", x => {
      const extra = structuredClone(x.artifacts[0]);
      extra.id += 99999;
      extra.name = "release-evidence-unexpected-run-" + runId + "-attempt-" + runAttempt;
      x.artifacts.push(extra);
      x.total_count++;
    });
  });
});
test("duplicate artifact identity fails", () => {
  expectGate("duplicate API identity", (ctx) => {
    editPlatform(ctx, "artifacts.json", x => {
      x.artifacts.push(structuredClone(x.artifacts[0]));
      x.total_count++;
    });
  });
});
test("renamed mandatory artifact fails", () => {
  expectGate("renamed artifact", (ctx) => {
    editPlatform(ctx, "artifacts.json", x => {
      const item = x.artifacts.find(a => a.name === privacyName);
      item.name = privacyName + "-renamed";
    });
  });
});
test("missing mandatory artifact fails", () => {
  expectGate("missing metadata identity", (ctx) => {
    editPlatform(ctx, "artifacts.json", x => {
      x.artifacts = x.artifacts.filter(a => a.name !== actionName);
      x.total_count--;
    });
  });
});
test("unexpected nested evidence root fails", () => {
  expectGate("unexpected nested directory", (ctx) => {
    mkdirSync(join(ctx.evidence, "release-evidence-substitute"), { recursive: true });
  });
});
test("empty consent-race evidence fails", () => {
  expectGate("empty c77 race file", (ctx) => {
    writeFileSync(ctx.artifact("release_consent_races",
      "c77-race-logs/assertions.log"), " ");
  });
});
test("nonempty but incomplete consent-race evidence fails", () => {
  expectGate("incomplete c76 pass record", (ctx) => {
    writeFileSync(ctx.artifact("release_consent_races",
      "c76-kind-logs/kind-and-lease-regressions.log"), "DO\n(1 row)\n");
  });
});
test("missing required provider security marker fails", () => {
  expectGate("missing c77 pass marker", (ctx) => {
    writeFileSync(ctx.artifact("release_provider_pg16", "c77-post033.log"),
      "BEGIN\nCOMMIT\n");
  });
});
test("wrong GitHub-platform job attempt fails even with consistent receipts", () => {
  expectGate("platform attempt mismatch", (ctx) => {
    editPlatform(ctx, "jobs.json", x => {
      x.jobs.find(j => j.name === "release_privacy_pg16").run_attempt = 99;
    });
  });
});
test("wrong trusted artifact run identity fails", () => {
  expectGate("platform artifact workflow run mismatch", (ctx) => {
    editPlatform(ctx, "artifacts.json", x => {
      x.artifacts.find(a => a.name === providerName).workflow_run.id = Number(runId) + 1;
    });
  });
});

test("wrong canonical workflow name fails", () => {
  expectGate("wrong workflow name", (ctx) => {
    editPlatform(ctx, "attempt.json", x => { x.name = "Other Workflow"; });
  });
});
test("wrong canonical workflow path fails", () => {
  expectGate("wrong workflow path", (ctx) => {
    editPlatform(ctx, "attempt.json", x => { x.path = ".github/workflows/other.yml"; });
  });
});
test("wrong workflow head repository fails", () => {
  expectGate("wrong workflow head repository", (ctx) => {
    editPlatform(ctx, "attempt.json", x => { x.head_repository.full_name = "fork/deedlight"; });
  });
});

test("artifact SHA-256 metadata mismatch fails", () => {
  expectGate("artifact digest mismatch", (ctx) => {
    editPlatform(ctx, "artifacts.json", x => {
      x.artifacts.find(a => a.name === providerName).digest = "sha256:" + "0".repeat(64);
    });
  });
});
test("artifact byte tampering fails before release PASS", () => {
  expectGate("tampered raw ZIP bytes", (ctx) => {
    const path = ctx.artifactZip("release_provider_pg16");
    const bytes = readFileSync(path);
    bytes[bytes.length - 1] ^= 1;
    writeFileSync(path, bytes);
  });
});
test("artifact ID without its corresponding downloaded archive fails", () => {
  expectGate("wrong artifact ID", (ctx) => {
    editPlatform(ctx, "artifacts.json", x => {
      x.artifacts.find(a => a.name === providerName).id += 900000;
    });
  });
});
test("duplicate GitHub artifact IDs fail", () => {
  expectGate("duplicate artifact IDs", (ctx) => {
    editPlatform(ctx, "artifacts.json", x => {
      x.artifacts.find(a => a.name === providerName).id =
        x.artifacts.find(a => a.name === privacyName).id;
    });
  });
});
test("artifact from another repository fails", () => {
  expectGate("wrong artifact repository ID", (ctx) => {
    editPlatform(ctx, "artifacts.json", x => {
      x.artifacts.find(a => a.name === providerName).workflow_run.repository_id += 1;
    });
  });
});
test("artifact from a fork fails", () => {
  expectGate("wrong artifact head repository ID", (ctx) => {
    editPlatform(ctx, "artifacts.json", x => {
      x.artifacts.find(a => a.name === providerName).workflow_run.head_repository_id += 1;
    });
  });
});
test("artifact from a different source commit fails", () => {
  expectGate("wrong artifact source SHA", (ctx) => {
    editPlatform(ctx, "artifacts.json", x => {
      x.artifacts.find(a => a.name === providerName).workflow_run.head_sha = "0".repeat(40);
    });
  });
});
test("artifact from a different source branch fails", () => {
  expectGate("wrong artifact source branch", (ctx) => {
    editPlatform(ctx, "artifacts.json", x => {
      x.artifacts.find(a => a.name === providerName).workflow_run.head_branch += "-other";
    });
  });
});
test("prior-attempt leftover artifacts fail without overwrite", () => {
  expectGate("stale previous-attempt artifact", (ctx) => {
    editPlatform(ctx, "artifacts.json", x => {
      const old = structuredClone(x.artifacts[0]);
      old.id += 999999;
      old.name = old.name.replace("-attempt-" + runAttempt, "-attempt-0");
      x.artifacts.push(old);
      x.total_count++;
    });
  });
});
