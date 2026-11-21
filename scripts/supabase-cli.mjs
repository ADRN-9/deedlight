import { spawnSync } from "node:child_process";
import process from "node:process";
import path from "node:path";
import { pathToFileURL } from "node:url";
import {
  assertLinkedProject,
  assertNoForwardedArgs,
  assertResolvedTarget,
  loadCliVersion,
  loadProjectPolicy,
  resolveApprovedProjectRef,
} from "./supabase-cli-policy.mjs";

export function runSupabase(args, {
  cwd,
  env,
  interactive = false,
  spawnSyncImpl = spawnSync,
}) {
  const result = spawnSyncImpl("supabase", args, {
    cwd,
    env,
    encoding: "utf8",
    // Hosted mutation prompts require the child to inherit the caller's TTY.
    stdio: interactive ? "inherit" : ["inherit", "pipe", "pipe"],
  });

  if (result.error) {
    throw new Error(`Unable to execute the pinned Supabase CLI: ${result.error.message}`);
  }

  return {
    status: result.status ?? 1,
    stdout: typeof result.stdout === "string" ? result.stdout : "",
    stderr: typeof result.stderr === "string" ? result.stderr : "",
  };
}

function redactOutput(value, env) {
  let output = String(value);
  for (const name of [
    "SUPABASE_ACCESS_TOKEN",
    "SUPABASE_DB_PASSWORD",
    "SUPABASE_SERVICE_ROLE_KEY",
    "RESEND_API_KEY",
  ]) {
    const secret = env[name];
    if (typeof secret === "string" && secret.length > 0) {
      output = output.replaceAll(secret, "[REDACTED]");
    }
  }
  return output.replace(
    /\bpostgres(?:ql)?:\/\/[^@\s/]+@/giu,
    "postgresql://[REDACTED]@",
  );
}

function emitResult(result, env, io) {
  const stdout = redactOutput(result.stdout, env);
  const stderr = redactOutput(result.stderr, env);
  if (stdout) io.stdout(stdout);
  if (stderr) io.stderr(stderr);
}

function requireSuccess(result, label, env, io) {
  if (result.status === 0) return;
  emitResult(result, env, io);
  throw new Error(`${label} failed with exit code ${result.status}.`);
}

function requirePinnedCli(runCli, version, options) {
  const result = runCli(["--version"], options);
  if (result.status !== 0) {
    throw new Error("Unable to verify the installed Supabase CLI version.");
  }

  const matches = `${result.stdout}\n${result.stderr}`.match(/\b\d+\.\d+\.\d+\b/gu) ?? [];
  if (matches.length !== 1 || matches[0] !== version) {
    throw new Error(`Supabase CLI ${version} is required; installed CLI version did not match.`);
  }
}

function cliEnvironment(env, target) {
  const result = { ...env, SUPABASE_PROJECT_ID: target };
  // The wrapper never forwards shell-level confirmation bypasses to hosted commands.
  delete result.SUPABASE_YES;
  return result;
}

function assertNoHostedYesOverride(env) {
  if (Object.hasOwn(env, "SUPABASE_YES") || env.SUPABASE_YES !== undefined) {
    throw new Error(
      "SUPABASE_YES must be unset for hosted migrations; this wrapper requires interactive confirmation.",
    );
  }
}

export function executeSupabaseMode({
  mode,
  args = [],
  cwd = process.cwd(),
  env = process.env,
  runCli = runSupabase,
  io = {
    stdout: (value) => process.stdout.write(value),
    stderr: (value) => process.stderr.write(value),
  },
}) {
  const localModes = {
    "push-local": ["db", "push"],
    "reset-local": ["db", "reset"],
  };

  if (Object.hasOwn(localModes, mode)) {
    assertNoForwardedArgs(args, mode === "push-local" ? "push" : "reset");
    const version = loadCliVersion(cwd);
    requirePinnedCli(runCli, version, { cwd, env });
    const result = runCli(localModes[mode], { cwd, env });
    requireSuccess(result, `Local ${mode === "push-local" ? "database push" : "database reset"}`, env, io);
    emitResult(result, env, io);
    return;
  }

  if (mode !== "link" && mode !== "push-non-production") {
    throw new Error("Unknown Supabase CLI mode.");
  }

  assertNoForwardedArgs(args, mode === "link" ? "link" : "push:nonprod");
  if (mode === "push-non-production") {
    // Reject presence, not truthiness: even SUPABASE_YES=false is an unexpected caller override.
    assertNoHostedYesOverride(env);
  }

  const version = loadCliVersion(cwd);
  const policy = loadProjectPolicy(cwd);
  const target = resolveApprovedProjectRef({ root: cwd, env, policy });
  const targetEnv = cliEnvironment(env, target);

  if (mode === "link") {
    assertLinkedProject(cwd, target, { required: false });
    requirePinnedCli(runCli, version, { cwd, env });

    const result = runCli(["link", "--project-ref", target], {
      cwd,
      env: targetEnv,
    });
    requireSuccess(result, "Supabase project link", targetEnv, io);
    assertLinkedProject(cwd, target);
    emitResult(result, targetEnv, io);
    return;
  }

  assertLinkedProject(cwd, target);
  requirePinnedCli(runCli, version, { cwd, env });

  const dryRun = runCli(["db", "push", `--remote=${target}`, "--dry-run"], {
    cwd,
    env: targetEnv,
  });
  requireSuccess(dryRun, "Non-Production migration preflight", targetEnv, io);
  assertResolvedTarget(dryRun.stderr, target);

  // Re-read the allowlist and link immediately before the only mutating invocation.
  const currentPolicy = loadProjectPolicy(cwd);
  const currentTarget = resolveApprovedProjectRef({
    root: cwd,
    env,
    policy: currentPolicy,
  });
  if (currentTarget !== target) {
    throw new Error("Approved Supabase target changed during migration preflight.");
  }
  assertLinkedProject(cwd, target);

  // The captured dry-run verifies the exact target. Inherit stdio for the real push so the CLI
  // can display its confirmation prompt and the operator can answer it directly.
  const result = runCli(["db", "push", `--remote=${target}`], {
    cwd,
    env: targetEnv,
    interactive: true,
  });
  requireSuccess(result, "Non-Production migration push", targetEnv, io);
}

function main() {
  const [mode, ...args] = process.argv.slice(2);
  try {
    executeSupabaseMode({ mode, args });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown failure.";
    console.error(`Supabase CLI security guard: ${message}`);
    process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main();
}
