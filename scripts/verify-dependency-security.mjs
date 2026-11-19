import { readFileSync } from "node:fs";

const packageJson = JSON.parse(readFileSync("package.json", "utf8"));
const lock = JSON.parse(readFileSync("package-lock.json", "utf8"));
const packages = lock.packages ?? {};

function versionParts(value, name) {
  const match = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/.exec(value ?? "");
  if (!match) throw new Error(`Invalid stable ${name} version in lockfile: ${value}`);
  return match.slice(1).map(Number);
}

function compareVersions(left, right) {
  const a = versionParts(left, "package");
  const b = versionParts(right, "minimum");
  for (let i = 0; i < 3; i += 1) {
    if (a[i] !== b[i]) return a[i] - b[i];
  }
  return 0;
}

function requireAtLeast(path, minimum) {
  const installed = packages[path]?.version;
  if (!installed || compareVersions(installed, minimum) < 0) {
    throw new Error(`${path} must resolve to >=${minimum}; found ${installed ?? "missing"}`);
  }
}

const vulnerable = [];
for (const [path, entry] of Object.entries(packages)) {
  const name = path.slice(path.lastIndexOf("node_modules/") + "node_modules/".length);
  const version = entry.version;
  if (!version) continue;

  if (name === "glob" && compareVersions(version, "9.0.0") >= 0 && compareVersions(version, "14.0.2") < 0) {
    vulnerable.push(`${path}@${version} (GHSA-3g3m-2fjr-6pw4)`);
  }
  if (name === "minimatch" && compareVersions(version, "7.0.0") >= 0 && compareVersions(version, "11.0.1") < 0) {
    vulnerable.push(`${path}@${version} (GHSA-g3hv-75wg-m249)`);
  }
}

if (vulnerable.length) {
  throw new Error(`Vulnerable dependency paths remain:\n${vulnerable.join("\n")}`);
}

requireAtLeast("node_modules/glob", "14.0.2");
requireAtLeast("node_modules/minimatch", "11.0.1");
requireAtLeast("node_modules/typescript-eslint", "8.73.0");
requireAtLeast("node_modules/@typescript-eslint/typescript-estree", "8.73.0");

const globVersion = packages["node_modules/glob"].version;
const scopedGlobOverride = packageJson.overrides?.["@opennextjs/cloudflare"]?.glob;
if (scopedGlobOverride !== globVersion) {
  throw new Error(`OpenNext glob override must match the resolved glob version (${globVersion}); found ${scopedGlobOverride ?? "missing"}`);
}

const directTsEslint = packageJson.devDependencies?.["typescript-eslint"];
const lockedTsEslint = packages[""].devDependencies?.["typescript-eslint"];
if (!directTsEslint || directTsEslint !== lockedTsEslint) {
  throw new Error("typescript-eslint must be a direct, lockfile-synchronized development dependency");
}

const estreeMinimatchRange = packages["node_modules/@typescript-eslint/typescript-estree"].dependencies?.minimatch;
if (estreeMinimatchRange !== "^11.0.1") {
  throw new Error(`typescript-estree must declare patched minimatch ^11.0.1; found ${estreeMinimatchRange ?? "missing"}`);
}

console.log("Dependency security resolution PASS");
console.log(`glob@${globVersion}; minimatch@${packages["node_modules/minimatch"].version}; typescript-eslint@${packages["node_modules/typescript-eslint"].version}`);
console.log("No affected glob or minimatch versions exist in package-lock.json");
