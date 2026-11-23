import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const manifest = JSON.parse(await readFile(new URL("../package.json", import.meta.url), "utf8"));
const lock = JSON.parse(await readFile(new URL("../package-lock.json", import.meta.url), "utf8"));
const packages = lock.packages;

assert.equal(
  manifest.overrides?.["@opennextjs/cloudflare"]?.glob,
  "14.0.6",
  "OpenNext must retain its scoped patched glob override"
);
assert.equal(
  manifest.overrides?.["typescript-eslint"],
  "8.73.0",
  "eslint-config-next's TypeScript ESLint chain must remain on the patched release"
);

for (const name of ["@opennextjs/cloudflare", "eslint-config-next"]) {
  assert.ok(manifest.devDependencies?.[name], `${name} must remain a direct development dependency`);
  assert.equal(manifest.dependencies?.[name], undefined, `${name} must not enter production dependencies`);
}

const expectedVersions = {
  "node_modules/glob": "14.0.6",
  "node_modules/typescript-eslint": "8.73.0",
  "node_modules/@typescript-eslint/eslint-plugin": "8.73.0",
  "node_modules/@typescript-eslint/parser": "8.73.0",
  "node_modules/@typescript-eslint/type-utils": "8.73.0",
  "node_modules/@typescript-eslint/typescript-estree": "8.73.0",
  "node_modules/@typescript-eslint/utils": "8.73.0"
};

for (const [path, version] of Object.entries(expectedVersions)) {
  assert.equal(packages[path]?.version, version, `${path} must resolve to ${version}`);
}

const affectedNodes = [
  "node_modules/@opennextjs/cloudflare",
  "node_modules/glob",
  "node_modules/minimatch",
  "node_modules/typescript-eslint",
  "node_modules/@typescript-eslint/typescript-estree",
  "node_modules/@typescript-eslint/parser",
  "node_modules/@typescript-eslint/type-utils",
  "node_modules/@typescript-eslint/eslint-plugin",
  "node_modules/@typescript-eslint/utils"
];

for (const path of affectedNodes) {
  assert.equal(packages[path]?.dev, true, `${path} must remain development-only`);
}

function isAffectedGlob(version) {
  const [major, minor, patch] = version.split(".").map(Number);
  return major >= 9 && (major < 14 || (major === 14 && minor === 0 && patch <= 1));
}

function isAffectedMinimatch(version) {
  const [major, minor, patch] = version.split(".").map(Number);
  return major >= 7 && (major < 11 || (major === 11 && minor === 0 && patch < 1));
}

const vulnerableGlob = Object.entries(packages)
  .filter(([path]) => path === "node_modules/glob" || path.endsWith("/node_modules/glob"))
  .filter(([, pkg]) => isAffectedGlob(pkg.version));
assert.deepEqual(vulnerableGlob, [], "No affected glob versions may remain in the lockfile");

const vulnerableMinimatch = Object.entries(packages)
  .filter(([path]) => path === "node_modules/minimatch" || path.endsWith("/node_modules/minimatch"))
  .filter(([, pkg]) => isAffectedMinimatch(pkg.version));
assert.deepEqual(vulnerableMinimatch, [], "No affected minimatch versions may remain in the lockfile");

assert.equal(
  packages["node_modules/glob"]?.dependencies?.minimatch,
  "^11.0.5",
  "The scoped glob override must resolve the patched minimatch line"
);
assert.equal(
  packages["node_modules/@typescript-eslint/typescript-estree"]?.dependencies?.minimatch,
  "^11.0.1",
  "The TypeScript ESLint parser chain must use the patched minimatch line"
);

console.log("Dependency remediation assertions passed.");
