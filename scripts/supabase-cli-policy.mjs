import fs from "node:fs";
import path from "node:path";

export const PROJECT_REF_PATTERN = /^[a-z]{20}$/;

const PROJECT_POLICY_KEYS = [
  "schemaVersion",
  "productionProjectRef",
  "approvedNonProductionProjectRefs",
];

export function parseProjectPolicy(source) {
  let value;
  try {
    value = JSON.parse(source);
  } catch {
    throw new Error("Supabase project policy is not valid JSON.");
  }

  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Supabase project policy must be a JSON object.");
  }

  const keys = Object.keys(value).sort();
  if (keys.join(",") !== [...PROJECT_POLICY_KEYS].sort().join(",")) {
    throw new Error("Supabase project policy has missing or unexpected fields.");
  }

  if (value.schemaVersion !== 1) {
    throw new Error("Unsupported Supabase project policy schema version.");
  }

  if (!PROJECT_REF_PATTERN.test(value.productionProjectRef)) {
    throw new Error("Production Supabase project reference is malformed.");
  }

  if (!Array.isArray(value.approvedNonProductionProjectRefs)) {
    throw new Error("Non-Production project allowlist must be an array.");
  }

  const refs = value.approvedNonProductionProjectRefs;
  if (refs.some((ref) => typeof ref !== "string" || !PROJECT_REF_PATTERN.test(ref))) {
    throw new Error("Non-Production project allowlist contains a malformed reference.");
  }

  if (new Set(refs).size !== refs.length) {
    throw new Error("Non-Production project allowlist contains duplicate references.");
  }

  if (refs.includes(value.productionProjectRef)) {
    throw new Error("Production project reference must never appear in the allowlist.");
  }

  return Object.freeze({
    schemaVersion: value.schemaVersion,
    productionProjectRef: value.productionProjectRef,
    approvedNonProductionProjectRefs: Object.freeze([...refs]),
  });
}

export function loadProjectPolicy(root, fileSystem = fs) {
  const file = path.join(root, "config", "supabase-projects.json");
  let source;
  try {
    source = fileSystem.readFileSync(file, "utf8");
  } catch {
    throw new Error("Supabase project allowlist is missing or unreadable.");
  }
  return parseProjectPolicy(source);
}

function parseProjectIdFromDotEnv(source, file) {
  let result;

  for (const line of source.split(/\r?\n/u)) {
    if (/^\s*#/.test(line) || /^\s*$/.test(line)) continue;

    const keyPrefix = /^\s*(?:export\s+)?SUPABASE_PROJECT_ID(?:\s|=|$)/u;
    if (!keyPrefix.test(line)) continue;

    const assignment = line.match(/^\s*(?:export\s+)?SUPABASE_PROJECT_ID\s*=\s*(.*?)\s*$/u);
    if (!assignment) {
      throw new Error(`Malformed SUPABASE_PROJECT_ID assignment in ${file}.`);
    }

    let value = assignment[1].trim();
    if (value.startsWith('"')) {
      if (!value.endsWith('"') || value.length < 2) {
        throw new Error(`Malformed SUPABASE_PROJECT_ID assignment in ${file}.`);
      }
      try {
        value = JSON.parse(value);
      } catch {
        throw new Error(`Malformed SUPABASE_PROJECT_ID assignment in ${file}.`);
      }
    } else if (value.startsWith("'")) {
      if (!value.endsWith("'") || value.length < 2) {
        throw new Error(`Malformed SUPABASE_PROJECT_ID assignment in ${file}.`);
      }
      value = value.slice(1, -1);
    } else {
      value = value.replace(/\s+#.*$/u, "").trim();
    }

    if (typeof value !== "string" || value.includes("$")) {
      throw new Error(`Unsupported SUPABASE_PROJECT_ID value in ${file}.`);
    }

    if (result !== undefined && result !== value) {
      throw new Error(`Conflicting SUPABASE_PROJECT_ID assignments in ${file}.`);
    }
    result = value;
  }

  return result;
}

export function readEffectiveProjectId(root, env, fileSystem = fs) {
  if (Object.hasOwn(env, "SUPABASE_PROJECT_ID")) {
    return env.SUPABASE_PROJECT_ID;
  }

  const configuredEnv = env.SUPABASE_ENV;
  const envName = configuredEnv === undefined || configuredEnv === ""
    ? "development"
    : configuredEnv;

  if (!/^[A-Za-z0-9_-]+$/u.test(envName)) {
    throw new Error("SUPABASE_ENV contains an invalid environment name.");
  }

  const names = [
    `.env.${envName}.local`,
    ...(envName === "test" ? [] : [".env.local"]),
    `.env.${envName}`,
    ".env",
  ];

  for (const directory of [path.join(root, "supabase"), root]) {
    for (const name of names) {
      const file = path.join(directory, name);
      let source;
      try {
        source = fileSystem.readFileSync(file, "utf8");
      } catch (error) {
        if (error?.code === "ENOENT" || error?.code === "ENOTDIR") continue;
        throw new Error(`Unable to read Supabase project environment file: ${path.relative(root, file)}.`);
      }

      const projectId = parseProjectIdFromDotEnv(source, path.relative(root, file));
      if (projectId !== undefined) return projectId;
    }
  }

  return undefined;
}

export function resolveApprovedProjectRef({ root, env, policy, fileSystem = fs }) {
  const target = env.SUPABASE_PROJECT_REF;

  if (typeof target !== "string" || !PROJECT_REF_PATTERN.test(target)) {
    throw new Error("Set SUPABASE_PROJECT_REF to an explicitly approved 20-letter project reference.");
  }

  if (target === policy.productionProjectRef) {
    throw new Error("Production Supabase project is explicitly forbidden for this command.");
  }

  if (policy.approvedNonProductionProjectRefs.length === 0) {
    throw new Error("No approved Non-Production Supabase project references are configured.");
  }

  if (!policy.approvedNonProductionProjectRefs.includes(target)) {
    throw new Error("Supabase project reference is not in the approved Non-Production allowlist.");
  }

  const projectId = readEffectiveProjectId(root, env, fileSystem);
  if (projectId !== undefined) {
    if (typeof projectId !== "string" || !PROJECT_REF_PATTERN.test(projectId)) {
      throw new Error("SUPABASE_PROJECT_ID is malformed.");
    }
    if (projectId !== target) {
      throw new Error("SUPABASE_PROJECT_ID does not match the approved SUPABASE_PROJECT_REF.");
    }
  }

  return target;
}

export function readLinkedProjectRef(root, fileSystem = fs) {
  const file = path.join(root, "supabase", ".temp", "project-ref");
  let source;
  try {
    source = fileSystem.readFileSync(file, "utf8");
  } catch (error) {
    if (error?.code === "ENOENT" || error?.code === "ENOTDIR") return undefined;
    throw new Error("Unable to read the linked Supabase project identity.");
  }

  const ref = source.trim();
  if (!PROJECT_REF_PATTERN.test(ref)) {
    throw new Error("Linked Supabase project identity is malformed.");
  }
  return ref;
}

export function assertLinkedProject(root, target, { required = true, fileSystem = fs } = {}) {
  const linked = readLinkedProjectRef(root, fileSystem);
  if (linked === undefined) {
    if (required) {
      throw new Error("Supabase project is not linked. Run npm run supabase:link with an approved target first.");
    }
    return undefined;
  }

  if (linked !== target) {
    throw new Error("Linked Supabase project does not match the approved target.");
  }
  return linked;
}

export function assertNoForwardedArgs(args, mode) {
  if (!Array.isArray(args) || args.length > 0) {
    throw new Error(`supabase:${mode} accepts no forwarded arguments; target overrides are forbidden.`);
  }
}

export function assertResolvedTarget(stderr, expectedRef) {
  const lines = String(stderr).split(/\r?\n/u).filter((line) => /^Target:\s/u.test(line));
  if (lines.length !== 1) {
    throw new Error("Supabase CLI did not report exactly one resolved Target; refusing the migration.");
  }

  const refs = lines[0].match(/[a-z]{20}/gu) ?? [];
  if (refs.length !== 1 || refs[0] !== expectedRef) {
    throw new Error("Supabase CLI resolved a target different from the approved project reference.");
  }
}

export function parseCliVersionConfig(source) {
  let value;
  try {
    value = JSON.parse(source);
  } catch {
    throw new Error("Supabase CLI version configuration is not valid JSON.");
  }

  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    Object.keys(value).length !== 1 ||
    typeof value.version !== "string" ||
    !/^\d+\.\d+\.\d+$/u.test(value.version)
  ) {
    throw new Error("Supabase CLI version configuration is malformed.");
  }

  return value.version;
}

export function loadCliVersion(root, fileSystem = fs) {
  const file = path.join(root, "config", "supabase-cli.json");
  let source;
  try {
    source = fileSystem.readFileSync(file, "utf8");
  } catch {
    throw new Error("Pinned Supabase CLI version configuration is missing or unreadable.");
  }
  return parseCliVersionConfig(source);
}
