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


function stripJsonComments(source) {
  let output = "";
  let inString = false;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;

  for (let index = 0; index < source.length; index += 1) {
    const char = source[index];
    const next = source[index + 1];

    if (lineComment) {
      if (char === "\n" || char === "\r") {
        lineComment = false;
        output += char;
      } else {
        output += " ";
      }
      continue;
    }

    if (blockComment) {
      if (char === "*" && next === "/") {
        blockComment = false;
        output += "  ";
        index += 1;
      } else {
        output += char === "\n" || char === "\r" ? char : " ";
      }
      continue;
    }

    if (inString) {
      output += char;
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }

    if (char === '"') {
      inString = true;
      output += char;
    } else if (char === "/" && next === "/") {
      lineComment = true;
      output += "  ";
      index += 1;
    } else if (char === "/" && next === "*") {
      blockComment = true;
      output += "  ";
      index += 1;
    } else {
      output += char;
    }
  }

  if (blockComment) {
    throw new Error("Supabase JSONC configuration contains an unterminated comment.");
  }
  return output;
}

function stripJsonTrailingCommas(source) {
  let output = "";
  let inString = false;
  let escaped = false;

  for (let index = 0; index < source.length; index += 1) {
    const char = source[index];
    if (inString) {
      output += char;
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }

    if (char === '"') {
      inString = true;
      output += char;
      continue;
    }

    if (char === ",") {
      let next = index + 1;
      while (next < source.length && /\s/u.test(source[next])) next += 1;
      if (source[next] === "}" || source[next] === "]") continue;
    }
    output += char;
  }
  return output;
}

function readExperimentalStackJson(source) {
  let document;
  try {
    const clean = stripJsonTrailingCommas(stripJsonComments(source));
    document = JSON.parse(clean);
  } catch (error) {
    throw new Error("Supabase project configuration is unreadable: " + error.message);
  }

  if (!document || typeof document !== "object" || Array.isArray(document)) {
    throw new Error("Supabase project configuration must be an object.");
  }
  const experimental = document.experimental;
  if (experimental === undefined) return false;
  if (!experimental || typeof experimental !== "object" || Array.isArray(experimental)) {
    throw new Error("Supabase experimental configuration is malformed.");
  }
  if (experimental.stack === undefined) return false;
  if (typeof experimental.stack !== "boolean") {
    throw new Error("Supabase experimental.stack must be a literal boolean; dynamic stack selection is unsupported.");
  }
  return experimental.stack;
}

function findUnescapedTomlTriple(line, quote, start) {
  for (let index = start; index <= line.length - quote.length; index += 1) {
    if (!line.startsWith(quote, index)) continue;
    if (quote === "'''") return index;
    let backslashes = 0;
    for (let cursor = index - 1; cursor >= 0 && line[cursor] === "\\"; cursor -= 1) {
      backslashes += 1;
    }
    if (backslashes % 2 === 0) return index;
  }
  return -1;
}

function stripTomlComment(line, state) {
  let quote;
  let escaped = false;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if (state.multiline !== undefined) {
      const close = findUnescapedTomlTriple(line, state.multiline, index);
      if (close === -1) return "";
      state.multiline = undefined;
      return "";
    }
    if (quote !== undefined) {
      if (escaped) {
        escaped = false;
      } else if (quote === '"' && char === "\\") {
        escaped = true;
      } else if (char === quote) {
        quote = undefined;
      }
    } else if ((char === '"' && line.startsWith('"""', index)) ||
               (char === "'" && line.startsWith("'''", index))) {
      const triple = char.repeat(3);
      if (findUnescapedTomlTriple(line, triple, index + 3) === -1) {
        state.multiline = triple;
      }
      return line.slice(0, index);
    } else if (char === '"' || char === "'") {
      quote = char;
    } else if (char === "#") {
      return line.slice(0, index);
    }
  }
  return line;
}

function parseTomlStackBoolean(value) {
  const normalized = value.trim();
  if (normalized === "true") return true;
  if (normalized === "false") return false;
  throw new Error("Supabase experimental.stack must be a literal TOML boolean; dynamic stack selection is unsupported.");
}

function readExperimentalStackToml(source) {
  let section = "";
  let found = false;
  let enabled = false;
  const tomlState = { multiline: undefined };

  for (const rawLine of source.split(/\r?\n/u)) {
    const line = stripTomlComment(rawLine, tomlState).trim();
    if (line === "") continue;

    const table = line.match(/^\[\s*([^\]]+)\s*\]$/u);
    if (table) {
      section = table[1].trim().replace(/^["']|["']$/gu, "");
      continue;
    }

    const assignment = line.match(/^((?:"[^"]+"|'[^']+'|[A-Za-z0-9_-]+)(?:\s*\.\s*(?:"[^"]+"|'[^']+'|[A-Za-z0-9_-]+))*)\s*=\s*(.*?)\s*$/u);
    if (!assignment) continue;

    const keyPath = assignment[1]
      .split(/\s*\.\s*/u)
      .map((part) => part.replace(/^["']|["']$/gu, ""));
    const value = assignment[2];
    const isStackKey =
      (section === "" && keyPath.length === 2 && keyPath[0] === "experimental" && keyPath[1] === "stack") ||
      (section === "experimental" && keyPath.length === 1 && keyPath[0] === "stack");

    if (isStackKey) {
      if (found) throw new Error("Supabase experimental.stack is defined more than once.");
      found = true;
      enabled = parseTomlStackBoolean(value);
      continue;
    }

    if (section === "" && keyPath.length === 1 && keyPath[0] === "experimental") {
      if (value.startsWith("{")) {
        const inlineStack = value.match(/(?:^|[{,]\s*)(?:"stack"|'stack'|stack)\s*=\s*([^,}]+)(?=\s*[,}])/u);
        if (inlineStack) {
          if (found) throw new Error("Supabase experimental.stack is defined more than once.");
          found = true;
          enabled = parseTomlStackBoolean(inlineStack[1]);
        } else if (!value.endsWith("}")) {
          throw new Error("Supabase inline experimental configuration is incomplete.");
        }
      } else {
        throw new Error("Supabase experimental configuration uses an unsupported value.");
      }
    }
  }

  return enabled;
}

/**
 * The wrapper supports only Supabase CLI's legacy project-state identity.
 * CLI 3.2.0 switches to supabase/.link.json when experimental stack mode is selected.
 */
export function assertLegacyProjectStateMode(root, env, fileSystem = fs) {
  if (Object.hasOwn(env, "SUPABASE_EXPERIMENTAL_STACK")) {
    throw new Error("SUPABASE_EXPERIMENTAL_STACK must be unset; hosted wrappers support legacy project identity only.");
  }
  if (Object.hasOwn(env, "SUPABASE_WORKDIR")) {
    throw new Error("SUPABASE_WORKDIR must be unset; hosted wrappers bind identity to the current repository.");
  }

  const stackLink = path.join(root, "supabase", ".link.json");
  try {
    fileSystem.lstatSync(stackLink);
    throw new Error("Experimental stack-mode link identity (supabase/.link.json) is unsupported by hosted wrappers.");
  } catch (error) {
    if (error?.code !== "ENOENT") {
      if (error instanceof Error && error.message.includes("stack-mode link identity")) throw error;
      if (error?.code === "ENOTDIR") {
        throw new Error("Unable to inspect Supabase stack-mode link identity.");
      }
      if (error?.code !== undefined) {
        throw new Error("Unable to inspect Supabase stack-mode link identity.");
      }
      throw error;
    }
  }

  const supabaseDir = path.join(root, "supabase");
  const configPaths = [
    path.join(supabaseDir, "config.json"),
    path.join(supabaseDir, "config.jsonc"),
    path.join(supabaseDir, "config.toml"),
  ];
  const configFile = configPaths.find((file) => fileSystem.existsSync(file));
  if (configFile === undefined) return "legacy";

  let source;
  try {
    source = fileSystem.readFileSync(configFile, "utf8");
  } catch {
    throw new Error("Unable to read Supabase project configuration for hosted identity verification.");
  }

  const stackEnabled = configFile.endsWith(".toml")
    ? readExperimentalStackToml(source)
    : readExperimentalStackJson(source);

  if (stackEnabled) {
    throw new Error("Supabase experimental stack mode is enabled; hosted wrappers require legacy supabase/.temp/project-ref identity.");
  }
  return "legacy";
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
