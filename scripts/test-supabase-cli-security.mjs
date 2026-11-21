import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  assertLegacyProjectStateMode,
  assertLinkedProject,
  assertResolvedTarget,
  loadProjectPolicy,
  parseProjectPolicy,
  resolveApprovedProjectRef,
} from "./supabase-cli-policy.mjs";
import { createHostedCliEnvironment, executeSupabaseMode, runSupabase } from "./supabase-cli.mjs";

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

function writeStackLink(root, projectRef, activeBranchRef) {
  const file = path.join(root, "supabase", ".link.json");
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify({
    project: { ref: projectRef },
    active_branch: { ref: activeBranchRef },
    fetchedAt: "2026-11-21T00:00:00.000Z",
  }));
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


function writeInteractiveFakeSupabase(root) {
  const bin = path.join(root, "bin");
  fs.mkdirSync(bin, { recursive: true });
  const executable = path.join(bin, "supabase");
  fs.writeFileSync(executable, "#!/usr/bin/env node\nconst fs = require('node:fs');\nconst args = process.argv.slice(2);\nif (args[0] === '--version') { process.stdout.write('3.2.0\\n'); process.exit(0); }\nif (args[0] === 'db' && args[1] === 'push' && args.includes('--dry-run')) {\n  process.stderr.write('Target: project ' + process.env.SUPABASE_PROJECT_ID + '\\n');\n  process.exit(0);\n}\nif (args[0] === 'db' && args[1] === 'push') {\n  if (!process.stdin.isTTY || !process.stdout.isTTY) {\n    process.stderr.write('Refusing hosted migration without an interactive TTY.\\n');\n    process.exit(1);\n  }\n  process.stdout.write('Proceed with hosted migration? [y/N] ');\n  let answer = '';\n  process.stdin.setEncoding('utf8');\n  process.stdin.on('data', (chunk) => {\n    answer += chunk;\n    if (!answer.includes('\\n')) return;\n    if (answer.trim().toLowerCase() !== 'y') { process.exitCode = 1; process.stdin.pause(); return; }\n    fs.writeFileSync(process.env.DEEDLIGHT_MUTATION_MARKER, 'confirmed\\n');\n    process.stdout.write('\\nConfirmation accepted.\\n', () => process.exit(0));\n  });\n  process.stdin.resume();\n  return;\n}\nprocess.stderr.write('Unexpected fake Supabase CLI invocation.\\n');\nprocess.exit(90);\n");
  fs.chmodSync(executable, 0o755);
  return bin;
}

const PYTHON_PTY_RUNNER = "import errno, os, pty, select, signal, sys, time\n\npid, master = pty.fork()\nif pid == 0:\n    os.execvpe(sys.argv[1], [sys.argv[1], sys.argv[2], 'push-non-production'], os.environ.copy())\n\noutput = bytearray()\nsent = False\nstatus = None\ndeadline = time.monotonic() + 10\n\nwhile True:\n    if status is None and time.monotonic() > deadline:\n        os.kill(pid, signal.SIGKILL)\n        _, status = os.waitpid(pid, 0)\n        break\n\n    readable, _, _ = select.select([master], [], [], 0.1)\n    if readable:\n        try:\n            chunk = os.read(master, 4096)\n        except OSError as error:\n            if error.errno == errno.EIO:\n                break\n            raise\n        if chunk:\n            output.extend(chunk)\n            if not sent and b'Proceed with hosted migration? [y/N]' in output:\n                os.write(master, b'y\\n')\n                sent = True\n\n    if status is None:\n        waited, child_status = os.waitpid(pid, os.WNOHANG)\n        if waited == pid:\n            status = child_status\n    elif not readable:\n        break\n\nif status is None:\n    _, status = os.waitpid(pid, 0)\nos.close(master)\nsys.stdout.write(output.decode('utf-8', 'replace'))\nif not sent:\n    sys.stderr.write('PTY prompt was not visible or interactive.\\n')\n    sys.exit(23)\nif os.WIFEXITED(status):\n    sys.exit(os.WEXITSTATUS(status))\nsys.exit(128 + os.WTERMSIG(status))\n"

test("hosted child environment sanitization removes inherited SUPABASE_YES", () => {
  const sanitized = createHostedCliEnvironment({
    SUPABASE_YES: "true",
    SUPABASE_EXPERIMENTAL_STACK: "1",
    SUPABASE_WORKDIR: "/tmp/other-project",
    SUPABASE_ACCESS_TOKEN: "retained-token",
    NODE_ENV: "test",
  }, APPROVED);

  assert.equal(Object.hasOwn(sanitized, "SUPABASE_YES"), false);
  assert.equal(Object.hasOwn(sanitized, "SUPABASE_EXPERIMENTAL_STACK"), false);
  assert.equal(Object.hasOwn(sanitized, "SUPABASE_WORKDIR"), false);
  assert.equal(sanitized.SUPABASE_PROJECT_ID, APPROVED);
  assert.equal(sanitized.SUPABASE_ACCESS_TOKEN, "retained-token");
  assert.equal(sanitized.NODE_ENV, "test");
});

test("hosted confirmation prompt is visible and answerable through a real PTY", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, APPROVED);
    const marker = path.join(root, "mutation-confirmed");
    const bin = writeInteractiveFakeSupabase(root);
    const childEnv = {
      ...process.env,
      PATH: bin + path.delimiter + (process.env.PATH ?? ""),
      SUPABASE_PROJECT_REF: APPROVED,
      SUPABASE_PROJECT_ID: APPROVED,
      DEEDLIGHT_MUTATION_MARKER: marker,
    };
    delete childEnv.SUPABASE_YES;

    const wrapperPath = path.join(process.cwd(), "scripts", "supabase-cli.mjs");
    const result = spawnSync("python3", [
      "-c",
      PYTHON_PTY_RUNNER,
      process.execPath,
      wrapperPath,
    ], {
      cwd: root,
      env: childEnv,
      encoding: "utf8",
      timeout: 15_000,
    });

    assert.equal(result.error, undefined, result.error?.message);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.ok(result.stdout.includes("Proceed with hosted migration? [y/N]"), result.stdout);
    assert.ok(result.stdout.includes("Confirmation accepted"), result.stdout);
    assert.equal(fs.readFileSync(marker, "utf8"), "confirmed\n");
  });
});

test("non-TTY hosted migration fails closed before the mutation shim executes", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, APPROVED);
    const marker = path.join(root, "must-not-mutate");
    const bin = writeInteractiveFakeSupabase(root);
    const childEnv = {
      ...process.env,
      PATH: bin + path.delimiter + (process.env.PATH ?? ""),
      SUPABASE_PROJECT_REF: APPROVED,
      SUPABASE_PROJECT_ID: APPROVED,
      DEEDLIGHT_MUTATION_MARKER: marker,
    };
    delete childEnv.SUPABASE_YES;

    const wrapperPath = path.join(process.cwd(), "scripts", "supabase-cli.mjs");
    const result = spawnSync(process.execPath, [wrapperPath, "push-non-production"], {
      cwd: root,
      env: childEnv,
      encoding: "utf8",
      timeout: 10_000,
    });

    assert.equal(result.error, undefined, result.error?.message);
    assert.notEqual(result.status, 0, result.stdout);
    assert.ok(result.stderr.includes("Refusing hosted migration without an interactive TTY"), result.stderr);
    assert.equal(fs.existsSync(marker), false);
  });
});


test("legacy linked identity remains supported when stack mode is absent", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, APPROVED);
    assert.equal(assertLegacyProjectStateMode(root, env()), "legacy");
    assert.equal(assertLinkedProject(root, APPROVED), APPROVED);
  });
});

test("stack-mode .link.json identity is rejected even when its active branch matches", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, APPROVED);
    writeStackLink(root, OTHER, APPROVED);
    assert.throws(
      () => assertLegacyProjectStateMode(root, env()),
      /stack-mode link identity/u,
    );
  });
});

test("stack configuration without .link.json rejects stale legacy project references", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, APPROVED);
    fs.mkdirSync(path.join(root, "supabase"), { recursive: true });
    fs.writeFileSync(
      path.join(root, "supabase", "config.toml"),
      "[experimental]\nstack = true\n",
    );
    const calls = [];
    assert.throws(
      () => executeSupabaseMode({
        mode: "push-non-production",
        cwd: root,
        env: env(),
        runCli: (args) => {
          calls.push(args);
          return { status: 0, stdout: VERSION + "\n", stderr: "" };
        },
        io: quietIo,
      }),
      /stack mode is enabled/u,
    );
    assert.deepEqual(calls, []);
  });
});

test("stack mode is detected in JSON and commented JSONC project configuration", () => {
  for (const [name, content] of [
    ["config.json", '{"experimental":{"stack":true}}'],
    ["config.jsonc", '{\n  // opt in\n  "experimental": { "stack": true, },\n}\n'],
  ]) {
    withRoot((root) => {
      writeConfig(root);
      fs.mkdirSync(path.join(root, "supabase"), { recursive: true });
      fs.writeFileSync(path.join(root, "supabase", name), content);
      assert.throws(
        () => assertLegacyProjectStateMode(root, env()),
        /stack mode is enabled/u,
      );
    });
  }
});

test("literal experimental.stack=false remains a valid legacy configuration", () => {
  for (const [name, content] of [
    ["config.toml", "[experimental]\nstack = false\n"],
    ["config.json", '{"experimental":{"stack":false}}'],
    ["config.jsonc", '{ "experimental": { "stack": false, }, }'],
  ]) {
    withRoot((root) => {
      writeConfig(root);
      fs.mkdirSync(path.join(root, "supabase"), { recursive: true });
      fs.writeFileSync(path.join(root, "supabase", name), content);
      assert.equal(assertLegacyProjectStateMode(root, env()), "legacy");
    });
  }
});

test("nested TOML inline tables enable stack mode", () => {
  withRoot((root) => {
    writeConfig(root);
    fs.mkdirSync(path.join(root, "supabase"), { recursive: true });
    fs.writeFileSync(
      path.join(root, "supabase", "config.toml"),
      "experimental = { stack = true }\n",
    );
    assert.throws(
      () => assertLegacyProjectStateMode(root, env()),
      /stack mode is enabled/u,
    );
  });
});

test("escaped quoted TOML keys are decoded before stack-mode inspection", () => {
  withRoot((root) => {
    writeConfig(root);
    fs.mkdirSync(path.join(root, "supabase"), { recursive: true });
    fs.writeFileSync(
      path.join(root, "supabase", "config.toml"),
      '[experimental]\n"sta\\u0063k" = true\n',
    );
    assert.throws(
      () => assertLegacyProjectStateMode(root, env()),
      /stack mode is enabled/u,
    );
  });
});

test("competing Supabase config files follow CLI JSON then JSONC then TOML precedence", () => {
  withRoot((root) => {
    writeConfig(root);
    const directory = path.join(root, "supabase");
    fs.mkdirSync(directory, { recursive: true });
    const json = path.join(directory, "config.json");
    const jsonc = path.join(directory, "config.jsonc");
    const toml = path.join(directory, "config.toml");

    fs.writeFileSync(json, '{"experimental":{"stack":false}}');
    fs.writeFileSync(jsonc, '{"experimental":{"stack":true}}');
    fs.writeFileSync(toml, "this is deliberately malformed TOML = [\n");
    assert.equal(assertLegacyProjectStateMode(root, env()), "legacy");

    fs.unlinkSync(json);
    fs.writeFileSync(jsonc, '{"experimental":{"stack":false}}');
    fs.writeFileSync(toml, "experimental = { stack = true }\n");
    assert.equal(assertLegacyProjectStateMode(root, env()), "legacy");

    fs.unlinkSync(jsonc);
    assert.throws(
      () => assertLegacyProjectStateMode(root, env()),
      /stack mode is enabled/u,
    );
  });
});

test("malformed selected TOML configuration fails closed", () => {
  withRoot((root) => {
    writeConfig(root);
    fs.mkdirSync(path.join(root, "supabase"), { recursive: true });
    fs.writeFileSync(
      path.join(root, "supabase", "config.toml"),
      "[experimental\nstack = true\n",
    );
    assert.throws(
      () => assertLegacyProjectStateMode(root, env()),
      /configuration is unreadable/u,
    );
  });
});

test("dynamic experimental.stack JSON and JSONC values fail closed", () => {
  for (const name of ["config.json", "config.jsonc"]) {
    withRoot((root) => {
      writeConfig(root);
      fs.mkdirSync(path.join(root, "supabase"), { recursive: true });
      fs.writeFileSync(
        path.join(root, "supabase", name),
        '{"experimental":{"stack":"env(SUPABASE_EXPERIMENTAL_STACK)"}}',
      );
      assert.throws(
        () => assertLegacyProjectStateMode(root, env()),
        /literal boolean/u,
      );
    });
  }
});

test("authorization policy changes after dry-run block hosted mutation", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, APPROVED);
    const policyPath = path.join(root, "config", "supabase-projects.json");
    const { runCli: fakeRunCli } = fakeCli(root);
    let mutationCalls = 0;

    assert.throws(
      () => executeSupabaseMode({
        mode: "push-non-production",
        cwd: root,
        env: env(),
        runCli: (args, options) => {
          if (args[0] === "db" && args.includes("--dry-run")) {
            fs.writeFileSync(policyPath, JSON.stringify({
              schemaVersion: 1,
              productionProjectRef: PRODUCTION,
              approvedNonProductionProjectRefs: [OTHER],
            }));
          } else if (args[0] === "db" && args[1] === "push") {
            mutationCalls += 1;
          }
          return fakeRunCli(args, options);
        },
        io: quietIo,
      }),
      /not in the approved/u,
    );
    assert.equal(mutationCalls, 0);
  });
});

test("linked identity changes after dry-run block hosted mutation", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, APPROVED);
    const { runCli: fakeRunCli } = fakeCli(root);
    let mutationCalls = 0;

    assert.throws(
      () => executeSupabaseMode({
        mode: "push-non-production",
        cwd: root,
        env: env(),
        runCli: (args, options) => {
          if (args[0] === "db" && args.includes("--dry-run")) {
            writeLink(root, OTHER);
          } else if (args[0] === "db" && args[1] === "push") {
            mutationCalls += 1;
          }
          return fakeRunCli(args, options);
        },
        io: quietIo,
      }),
      /does not match/u,
    );
    assert.equal(mutationCalls, 0);
  });
});

test("dynamic experimental.stack environment references fail closed", () => {
  withRoot((root) => {
    writeConfig(root);
    fs.mkdirSync(path.join(root, "supabase"), { recursive: true });
    fs.writeFileSync(
      path.join(root, "supabase", "config.toml"),
      "[experimental]\nstack = 'env(SUPABASE_EXPERIMENTAL_STACK)'\n",
    );
    assert.throws(
      () => assertLegacyProjectStateMode(root, env()),
      /literal TOML boolean/u,
    );
  });
});

test("SUPABASE_EXPERIMENTAL_STACK cannot switch identity modes through the environment", () => {
  withRoot((root) => {
    writeConfig(root);
    fs.mkdirSync(path.join(root, "supabase"), { recursive: true });
    fs.writeFileSync(
      path.join(root, "supabase", "config.toml"),
      "[experimental]\nstack = true\n",
    );
    for (const value of ["1", "0", "", "invalid"]) {
      assert.throws(
        () => assertLegacyProjectStateMode(root, env({ SUPABASE_EXPERIMENTAL_STACK: value })),
        /SUPABASE_EXPERIMENTAL_STACK must be unset/u,
      );
    }
  });
});

test("SUPABASE_WORKDIR cannot redirect hosted project identity", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, APPROVED);
    assert.throws(
      () => assertLegacyProjectStateMode(root, env({ SUPABASE_WORKDIR: "/tmp/other-project" })),
      /SUPABASE_WORKDIR must be unset/u,
    );
  });
});


test("TOML multiline strings cannot hide a later stack-mode declaration", () => {
  withRoot((root) => {
    writeConfig(root);
    fs.mkdirSync(path.join(root, "supabase"), { recursive: true });
    fs.writeFileSync(
      path.join(root, "supabase", "config.toml"),
      'description = """\n[experimental]\nstack = false\n"""\n[experimental]\nstack = true\n',
    );
    assert.throws(
      () => assertLegacyProjectStateMode(root, env()),
      /stack mode is enabled/u,
    );
  });
});

test("stack mode with no stack or legacy link identity is rejected", () => {
  withRoot((root) => {
    writeConfig(root);
    fs.mkdirSync(path.join(root, "supabase"), { recursive: true });
    fs.writeFileSync(
      path.join(root, "supabase", "config.toml"),
      "[experimental]\nstack = true\n",
    );
    assert.throws(
      () => assertLegacyProjectStateMode(root, env()),
      /stack mode is enabled/u,
    );
  });
});

test("hosted link rejects environment-based identity-mode switching before CLI execution", () => {
  withRoot((root) => {
    writeConfig(root);
    writeLink(root, APPROVED);
    const calls = [];
    assert.throws(
      () => executeSupabaseMode({
        mode: "link",
        cwd: root,
        env: env({ SUPABASE_EXPERIMENTAL_STACK: "1" }),
        runCli: (args) => {
          calls.push(args);
          return { status: 0, stdout: VERSION + "\n", stderr: "" };
        },
        io: quietIo,
      }),
      /SUPABASE_EXPERIMENTAL_STACK must be unset/u,
    );
    assert.deepEqual(calls, []);
  });
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
