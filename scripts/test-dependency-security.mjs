import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";

const verifierPath = fileURLToPath(new URL("./verify-dependency-security.mjs", import.meta.url));

function runVerifier(t, overrides = {}) {
  const directory = mkdtempSync(join(tmpdir(), "deedlight-dependency-security-"));
  t.after(() => rmSync(directory, { recursive: true, force: true }));

  const versions = {
    glob: "14.0.2",
    minimatch: "11.0.9",
    typescriptEslint: "8.73.0",
    typescriptEstree: "8.73.0",
    ...overrides,
  };

  const packageJson = {
    devDependencies: { "typescript-eslint": versions.typescriptEslint },
    overrides: { "@opennextjs/cloudflare": { glob: versions.glob } },
  };
  const lock = {
    packages: {
      "": { devDependencies: { "typescript-eslint": versions.typescriptEslint } },
      "node_modules/glob": {
        version: versions.glob,
        dependencies: { minimatch: "^11.0.0" },
      },
      "node_modules/minimatch": { version: versions.minimatch },
      "node_modules/typescript-eslint": { version: versions.typescriptEslint },
      "node_modules/@typescript-eslint/typescript-estree": {
        version: versions.typescriptEstree,
        dependencies: { minimatch: "^11.0.1" },
      },
    },
  };

  writeFileSync(join(directory, "package.json"), JSON.stringify(packageJson));
  writeFileSync(join(directory, "package-lock.json"), JSON.stringify(lock));

  return spawnSync(process.execPath, [verifierPath], {
    cwd: directory,
    encoding: "utf8",
    timeout: 10_000,
  });
}

test("accepts patched stable dependency versions", (t) => {
  const result = runVerifier(t);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /Dependency security resolution PASS/);
});

const prereleaseCases = [
  ["glob", { glob: "14.0.2-beta.1" }],
  ["minimatch", { minimatch: "11.0.9-rc.1" }],
  ["typescript-eslint", { typescriptEslint: "8.73.0-alpha.1" }],
  ["typescript-estree", { typescriptEstree: "8.73.0-beta.1" }],
];

for (const [dependency, versions] of prereleaseCases) {
  test(`rejects prerelease ${dependency} versions as unpatched`, (t) => {
    const result = runVerifier(t, versions);
    assert.notEqual(result.status, 0, result.stdout);
    assert.match(
      result.stderr,
      /Invalid stable package version in lockfile:/,
    );
  });
}
