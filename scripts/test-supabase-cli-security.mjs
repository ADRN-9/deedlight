import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  assertLinkedProject,
  assertResolvedTarget,
  loadProjectPolicy,
  parseProjectPolicy,
  resolveApprovedProjectRef,
} from "./supabase-cli-policy.mjs";
import { executeSupabaseMode, runSupabase } from "./supabase-cli.mjs";

const APPROVED = "aaaaaaaaaaaaaaaaaaaa";
const OTHER = "bbbbbbbbbbbbbbbbbbbb";
const PRODUCTION = "zzzzzzzzzzzzzzzzzzzz";
const VERSION = "3.2.0";

function withRoot(run) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "deedlight-cli-"));
  try {
    run(root);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

function writeConfig(root, refs = [APPROVED]) {
  fs.mkdirSync(path.join(root, "config"), { recursive: true });
  fs.writeFileSync(path.join(root, "config", "supabase-cli.json"), JSON.stringify({ version: VERSION }));
  fs.writeFileSync(
    path.join(root, "config", "supabase-projects.json"),
    JSON.stringify({
      schemaVersion: 1,
      productionProjectRef: PRODUCTION,
      approvedNonProductionProjectRefs: refs,
    }),
  );
}

function writeLink(root, ref) {
  const file = path.join(root, "supabase", ".temp", "project-ref");
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${ref}\n`);
}

function env(overrides = {}) {
  return { SUPABASE_PROJECT_REF: APPROVED, ...overrides };
}

function fakeCli(root, resolved = APPROVED) {
  const calls = [];
  const runCli = (args, options) => {
    calls.push({ args: [...args], env: options.env, interactive: options.interactive ?? false });
    if (args[0] === "--version") return { status: 0, stdout: `${VERSION}\n`, stderr: "" };
    if (args[0] === "link") {
      writeLink(root, resolved);
      return { status: 0, stdout: "linked\n", stderr: "" };
    }
    if (args[0] === "db" && args[1] === "push") {
      return {
        status: 0,
        stdout: args.includes("--dry-run") ? "DRY RUN\n" : "pushed\n",
        stderr: `Target: project ${resolved}\n`,
      };
    }
    if (args[0] === "db" && args[1] === "reset") {
      return { status: 0, stdout: "local reset\n", stderr: "" };
    }
    throw new Error(`Unexpected CLI args: ${args.join(" ")}`);
  };
  return { calls, runCli };
}

const quietIo = { stdout() {}, stderr() {} };

test("project policy schema is strict and Production cannot be allowlisted", () => {
  const source = JSON.stringify({
    schemaVersion: 1,
    productionProjectRef: PRODUCTION,
    approvedNonProductionProjectRefs: [APPROVED],
  });
  assert.deepEqual([...parseProjectPolicy(source).approvedNonProductionProjectRefs], [APPROVED]);
  assert.throws(() => parseProjectPolicy("{"), /not valid JSON/u);
  assert.throws(() => parseProjectPolicy(JSON.stringify({ schemaVersion: 1 })), /missing or unexpected/u);
  assert.throws(
    () => parseProjectPolicy(JSON.stringify({
      schemaVersion: 1,
      productionProjectRef: PRODUCTION,
      approvedNonProductionProjectRefs: [PRODUCTION],
    })),
    /must never appear/u,
  );
  assert.throws(
    () => parseProjectPolicy(JSON.stringify({
      schemaVersion: 1,
      productionProjectRef: PRODUCTION,
      approvedNonProductionProjectRefs: [APPROVED, APPROVED],
    })),
    /duplicate/u,
  );
  assert.throws(
    () => parseProjectPolicy(JSON.stringify({
      schemaVersion: 1,
      productionProjectRef: PRODUCTION,
      approvedNonProductionProjectRefs: "invalid",
    })),
    /must be an array/u,
  );
});

test("missing and empty allowlists fail closed", () => {
  withRoot((root) => {
    assert.throws(() => loadProjectPolicy(root), /missing or unreadable/u);
    writeConfig(root, []);
    assert.throws(
      () => resolveApprovedProjectRef({ root, env: env(), policy: loadProjectPolicy(root) }),
      /No approved Non-Production/u,
    );
  });
});

test("only an exact approved non-Production ref is accepted", () => {
  withRoot((root) => {
    writeConfig(root);
    const policy = loadProjectPolicy(root);
    assert.equal(resolveApprovedProjectRef({ root, env: env(), policy }), APPROVED);
    assert.throws(
      () => resolveApprovedProjectRef({ root, env: env({ SUPABASE_PROJECT_REF: OTHER }), policy }),
      /not in the approved/u,
    );
    assert.throws(
      () => resolveApprovedProjectRef({ root, env: env({ SUPABASE_PROJECT_REF: PRODUCTION }), policy }),
      /explicitly forbidden/u,
    );
    assert.throws(
      () => resolveApprovedProjectRef({ root, env: env({ SUPABASE_PROJECT_REF: "invalid" }), policy }),
      /20-letter/u,
    );
  });
});

test("mismatched shell and dotenv SUPABASE_PROJECT_ID values are rejected", () => {
  withRoot((root) => {
    writeConfig(root);
    const policy = loadProjectPolicy(root);
    assert.throws(
      () => resolveApprovedProjectRef({
        root,
        env: env({ SUPABASE_PROJECT_ID: OTHER }),
        policy,
      }),
      /does not match/u,
    );

    const supabaseDir = path.join(root, "supabase");
    fs.mkdirSync(supabaseDir, { recursive: true });
    fs.writeFileSync(path.join(supabaseDir, ".env.local"), `SUPABASE_PROJECT_ID="${OTHER}"\n`);
    assert.throws(
      () => resolveApprovedProjectRef({ root, env: env(), policy }),
      /does not match/u,
    );
  });
});

test("linked project identity must exist and match the approved ref", () => {
  withRoot((root) => {
    assert.throws(() => assertLinkedProject(root, APPROVED), /not linked/u);
    writeLink(root, OTHER);
    assert.throws(() => assertLinkedProject(root, APPROVED), /does not match/u);
    writeLink(root, APPROVED);
    assert.equal(assertLinkedProject(root, APPROVED), APPROVED);
  });
});

test("resolved CLI Target must report exactly the approved project ref", () => {
  assert.doesNotThrow(() => assertResolvedTarget(`Target: project ${APPROVED}\n`, APPROVED));
  assert.throws(() => assertResolvedTarget(`Target: project ${OTHER}\n`, APPROVED), /different/u);
  assert.throws(() => assertResolvedTarget("No target\n", APPROVED), /did not report/u);
  assert.throws(
    () => assertResolvedTarget(`Target: ${APPROVED} ${OTHER}\n`, APPROVED),
    /different/u,
  );
});

test("generic supabase:reset is local-only and rejects remote and --yes arguments", () => {
  withRoot((root) => {
    writeConfig(root);
    const { calls, runCli } = fakeCli(root);
    executeSupabaseMode({ mode: "reset-local", cwd: root, env: { SUPABASE_YES: "true" }, runCli, io: quietIo });
    assert.deepEqual(calls.map((call) => call.args), [["--version"], ["db", "reset"]]);
    assert.equal(calls[1].env.SUPABASE_YES, "true");

    for (const args of [
      ["--remote"],
      [`--remote=${PRODUCTION}`],
      ["--project-ref", PRODUCTION],
      ["--db-url", "postgresql://example"],
      ["--yes"],
      ["--yes", "--remote"],
      ["--remote", "--yes"],
    ]) {
      const rejectedCalls = [];
      assert.throws(
        () => executeSupabaseMode({
          mode: "reset-local",
          args,
          cwd: root,
          env: {},
          runCli: (cliArgs) => {
            rejectedCalls.push(cliArgs);
            return { status: 0, stdout: `${VERSION}\n`, stderr: "" };
          },
          io: quietIo,
        }),
        /forwarded arguments/u,
      );
      assert.deepEqual(rejectedCalls, []);
    }
  });
});

test("generic supabase:push invokes only local db push", () => {
  withRoot((root) => {
    writeConfig(root);
    const { calls, runCli } = fakeCli(root);
    executeSupabaseMode({ mode: "push-local", cwd: root, env: {}, runCli, io: quietIo });
    assert.deepEqual(calls.map((call) => call.args), [["--version"], ["db", "push"]]);
  });
});

test("non-Production link uses only an approved ref and verifies linked identity", () => {
  withRoot((root) => {
    writeConfig(root);
    const { calls, runCli } = fakeCli(root);
    executeSupabaseMode({ mode: "link", cwd: root, env: env(), runCli, io: quietIo });
    assert.deepEqual(calls.map((call) => call.args), [
      ["--version"],
      ["link", "--project-ref", APPROVED],
    ]);
    assert.equal(calls[1].env.SUPABASE_PROJECT_ID, APPROVED);
    assert.equal(assertLinkedProject(root, APPROVED), APPROVED);
  });
});

test("non-Production link refuses a different existing linked identity", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, OTHER);
    const calls = [];
    assert.throws(
      () => executeSupabaseMode({
        mode: "link",
        cwd: root,
        env: env(),
        runCli: (args) => {
          calls.push(args);
          return { status: 0, stdout: `${VERSION}\n`, stderr: "" };
        },
        io: quietIo,
      }),
      /does not match/u,
    );
    assert.deepEqual(calls, []);
  });
});

test("non-Production push preflights and then uses explicit CLI v3 --remote=<ref>", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, APPROVED);
    const { calls, runCli } = fakeCli(root);
    executeSupabaseMode({
      mode: "push-non-production",
      cwd: root,
      env: env(),
      runCli,
      io: quietIo,
    });
    assert.deepEqual(calls.map((call) => call.args), [
      ["--version"],
      ["db", "push", `--remote=${APPROVED}`, "--dry-run"],
      ["db", "push", `--remote=${APPROVED}`],
    ]);
    assert.ok(calls.every((call) => !call.args.includes("--yes")));
    assert.equal(calls[1].env.SUPABASE_PROJECT_ID, APPROVED);
  });
});

test("wrong resolved target blocks the mutating remote push", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, APPROVED);
    const { calls, runCli } = fakeCli(root, OTHER);
    assert.throws(
      () => executeSupabaseMode({
        mode: "push-non-production",
        cwd: root,
        env: env(),
        runCli,
        io: quietIo,
      }),
      /different/u,
    );
    assert.equal(calls.filter((call) => call.args[0] === "db").length, 1);
    assert.ok(calls[1].args.includes("--dry-run"));
  });
});

test("remote push rejects forwarded target overrides and mismatched linked refs", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, OTHER);
    const calls = [];
    assert.throws(
      () => executeSupabaseMode({
        mode: "push-non-production",
        args: ["--remote", `--remote=${PRODUCTION}`, "--yes"],
        cwd: root,
        env: env(),
        runCli: (args) => {
          calls.push(args);
          return { status: 0, stdout: `${VERSION}\n`, stderr: "" };
        },
        io: quietIo,
      }),
      /forwarded arguments/u,
    );
    assert.deepEqual(calls, []);

    assert.throws(
      () => executeSupabaseMode({
        mode: "push-non-production",
        cwd: root,
        env: env(),
        runCli: (args) => {
          calls.push(args);
          return { status: 0, stdout: `${VERSION}\n`, stderr: "" };
        },
        io: quietIo,
      }),
      /does not match/u,
    );
    assert.deepEqual(calls, []);
  });
});

test("repository scripts, empty authoritative allowlist and CI pin are consistent", () => {
  const packageJson = JSON.parse(fs.readFileSync(path.join(process.cwd(), "package.json"), "utf8"));
  const cliConfig = JSON.parse(fs.readFileSync(path.join(process.cwd(), "config", "supabase-cli.json"), "utf8"));
  const projectPolicy = JSON.parse(fs.readFileSync(path.join(process.cwd(), "config", "supabase-projects.json"), "utf8"));
  const workflow = fs.readFileSync(path.join(process.cwd(), ".github", "workflows", "pr-validation.yml"), "utf8");

  assert.equal(projectPolicy.productionProjectRef, "xaipiovflxomcbfwtwmu");
  assert.deepEqual(projectPolicy.approvedNonProductionProjectRefs, []);
  assert.equal(packageJson.scripts["supabase:link"], "node scripts/supabase-cli.mjs link");
  assert.equal(packageJson.scripts["supabase:push"], "node scripts/supabase-cli.mjs push-local");
  assert.equal(packageJson.scripts["supabase:push:nonprod"], "node scripts/supabase-cli.mjs push-non-production");
  assert.equal(packageJson.scripts["supabase:reset"], "node scripts/supabase-cli.mjs reset-local");
  assert.match(workflow, /supabase\/setup-cli@[0-9a-f]{40}/u);
  assert.match(workflow, new RegExp(`version:\\s+${cliConfig.version.replaceAll(".", "\\.")}`, "u"));
});


test("SUPABASE_YES=true fails closed before any hosted CLI invocation", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, APPROVED);
    for (const value of ["true", "false", ""]) {
      const calls = [];
      assert.throws(
        () => executeSupabaseMode({
          mode: "push-non-production",
          cwd: root,
          env: env({ SUPABASE_YES: value }),
          runCli: (args, options) => {
            calls.push({ args, options });
            return { status: 0, stdout: `${VERSION}\\n`, stderr: "" };
          },
          io: quietIo,
        }),
        /SUPABASE_YES must be unset/u,
      );
      assert.deepEqual(calls, []);
    }
  });
});

test("missing hosted target policy fails before invoking the Supabase CLI", () => {
  withRoot((root) => {
    fs.mkdirSync(path.join(root, "config"), { recursive: true });
    fs.writeFileSync(
      path.join(root, "config", "supabase-cli.json"),
      JSON.stringify({ version: VERSION }),
    );
    const calls = [];
    assert.throws(
      () => executeSupabaseMode({
        mode: "push-non-production",
        cwd: root,
        env: env(),
        runCli: (args) => {
          calls.push(args);
          return { status: 0, stdout: `${VERSION}\\n`, stderr: "" };
        },
        io: quietIo,
      }),
      /allowlist is missing/u,
    );
    assert.deepEqual(calls, []);
  });
});

test("hosted migration inherits interactive stdio and never forwards SUPABASE_YES", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, APPROVED);
    const { calls, runCli } = fakeCli(root);
    executeSupabaseMode({
      mode: "push-non-production",
      cwd: root,
      env: env(),
      runCli,
      io: quietIo,
    });

    assert.equal(calls[1].interactive, false);
    assert.equal(calls[2].interactive, true);
    assert.equal(Object.hasOwn(calls[1].env, "SUPABASE_YES"), false);
    assert.equal(Object.hasOwn(calls[2].env, "SUPABASE_YES"), false);
  });
});

test("interactive Supabase execution inherits all stdio while preflight captures output", () => {
  const observed = [];
  const spawnSyncImpl = (_command, _args, options) => {
    observed.push(options);
    return { status: 0, stdout: null, stderr: null };
  };

  runSupabase(["db", "push"], {
    cwd: process.cwd(),
    env: {},
    interactive: false,
    spawnSyncImpl,
  });
  runSupabase(["db", "push"], {
    cwd: process.cwd(),
    env: {},
    interactive: true,
    spawnSyncImpl,
  });

  assert.deepEqual(observed[0].stdio, ["inherit", "pipe", "pipe"]);
  assert.equal(observed[1].stdio, "inherit");
});

test("a CLI version mismatch prevents database commands", () => {
  withRoot((root) => {
    writeConfig(root);
    const calls = [];
    assert.throws(
      () => executeSupabaseMode({
        mode: "reset-local",
        cwd: root,
        env: {},
        runCli: (args) => {
          calls.push(args);
          return { status: 0, stdout: "3.1.9\n", stderr: "" };
        },
        io: quietIo,
      }),
      /3\.2\.0 is required/u,
    );
    assert.deepEqual(calls, [["--version"]]);
  });
});
