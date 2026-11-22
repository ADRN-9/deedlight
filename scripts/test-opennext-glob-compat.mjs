import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { runInNewContext } from "node:vm";
import { pathToFileURL } from "node:url";
import test from "node:test";

import { ContentUpdater } from "@opennextjs/aws/plugins/content-updater.js";
import { build } from "esbuild";

const require = createRequire(import.meta.url);
const packageJsonPath = require.resolve("@opennextjs/cloudflare/package.json");
const packageRoot = dirname(packageJsonPath);
const adapterPackage = JSON.parse(readFileSync(packageJsonPath, "utf8"));

const importAdapterModule = (relativePath) =>
  import(pathToFileURL(join(packageRoot, relativePath)).href);

const [{ getCacheAssets }, { normalizePath }, { inlineLoadManifest }] = await Promise.all([
  importAdapterModule("dist/cli/commands/populate-cache.js"),
  importAdapterModule("dist/cli/utils/normalize-path.js"),
  importAdapterModule("dist/cli/build/patches/plugins/load-manifest.js"),
]);

test("uses the pinned OpenNext release and tests its actual glob call sites", () => {
  assert.equal(adapterPackage.version, "1.20.18");

  const bundleServer = readFileSync(join(packageRoot, "dist/cli/build/bundle-server.js"), "utf8");
  const populateCache = readFileSync(join(packageRoot, "dist/cli/commands/populate-cache.js"), "utf8");
  const loadManifest = readFileSync(join(packageRoot, "dist/cli/build/patches/plugins/load-manifest.js"), "utf8");

  assert.match(bundleServer, /globSync\(["']\*\*\/\*\.nft\.json["']/);
  assert.match(populateCache, /globSync\(path\.join\(opts\.outputDir, ["']cache\/\*\*\/\*["']/);
  assert.match(loadManifest, /await glob\(/);
  assert.match(loadManifest, /windowsPathsNoEscape: true/);
  assert.match(loadManifest, /nodir: true/);
});

test("runs OpenNext's real cache-population discovery and path normalization", () => {
  const outputDir = mkdtempSync(join(tmpdir(), "deedlight-opennext-cache-"));
  try {
    const staticFile = join(outputDir, "cache", "static-build", "home", "index.cache");
    const fetchFile = join(outputDir, "cache", "__fetch", "fetch-build", "api", "v1", "profile.json");
    mkdirSync(dirname(staticFile), { recursive: true });
    mkdirSync(dirname(fetchFile), { recursive: true });
    mkdirSync(join(outputDir, "cache", "empty-directory"), { recursive: true });
    writeFileSync(staticFile, "static cache");
    writeFileSync(fetchFile, "fetch cache");

    const assets = getCacheAssets({ outputDir });
    assert.deepEqual(
      assets.map(({ isFetch, key, buildId }) => ({ isFetch, key, buildId })).sort((a, b) => a.key.localeCompare(b.key)),
      [
        { isFetch: true, key: "/api/v1/profile.json", buildId: "fetch-build" },
        { isFetch: false, key: "/home/index", buildId: "static-build" },
      ],
    );
    assert.equal(assets.find((asset) => asset.key === "/home/index").fullPath, staticFile);
    assert.equal(assets.find((asset) => asset.key === "/api/v1/profile.json").fullPath, fetchFile);
  } finally {
    rmSync(outputDir, { recursive: true, force: true });
  }
});

test("rejects malformed cache paths instead of silently staging them", () => {
  const outputDir = mkdtempSync(join(tmpdir(), "deedlight-opennext-invalid-cache-"));
  try {
    const invalidFile = join(outputDir, "cache", "__fetch", "missing-key");
    mkdirSync(dirname(invalidFile), { recursive: true });
    writeFileSync(invalidFile, "invalid");
    assert.throws(() => getCacheAssets({ outputDir }), /Invalid path for a Cache Asset file/);
  } finally {
    rmSync(outputDir, { recursive: true, force: true });
  }
});

test("normalizes Windows and POSIX paths through OpenNext's actual helper", () => {
  assert.equal(
    normalizePath("C:\\project\\.next\\server\\chunk.js"),
    "C:/project/.next/server/chunk.js",
  );
  assert.equal(normalizePath("/project/.next/server/chunk.js"), "/project/.next/server/chunk.js");
});

test("discovers only real manifests and client manifests through OpenNext's actual build plugin", async () => {
  const outputDir = mkdtempSync(join(tmpdir(), "deedlight-opennext-manifest-"));
  try {
    const appBuildOutputPath = join(outputDir, "app");
    const monorepoRoot = appBuildOutputPath;
    const baseDir = join(outputDir, "server-functions", "default");
    const dotNextDir = join(baseDir, ".next");
    const loaderPath = join(outputDir, "node_modules", "next", "dist", "server", "load-manifest.external.js");

    const writeManifest = (relativePath, value) => {
      const file = join(dotNextDir, relativePath);
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, JSON.stringify(value));
    };

    writeManifest("prerender-manifest.json", { version: 4, routes: { "/": { initialRevalidateSeconds: 60 } } });
    writeManifest("required-server-files.json", { version: 1, config: { output: "standalone" } });
    writeManifest("prefetch-hints.json", { hints: ["home"] });
    writeManifest("server/preview-props.json", { preview: true });
    writeManifest("not-a-matching-file.json", { shouldNotAppear: true });

    const clientManifestPath = join(dotNextDir, "server", "app", "page_client-reference-manifest.js");
    mkdirSync(dirname(clientManifestPath), { recursive: true });
    writeFileSync(
      clientManifestPath,
      'globalThis.__RSC_MANIFEST ??= {}; globalThis.__RSC_MANIFEST["/page"] = {"clientModules":{"fixture":{"id":1}}};',
    );

    // These directories match the glob suffixes but must never be treated as files.
    const manifestDirectory = join(dotNextDir, "server", "app", "route-manifest.json");
    mkdirSync(manifestDirectory, { recursive: true });
    writeFileSync(join(manifestDirectory, "inside.txt"), "not a manifest");
    const clientDirectory = join(dotNextDir, "server", "app", "fake_client-reference-manifest.js");
    mkdirSync(clientDirectory, { recursive: true });
    writeFileSync(join(clientDirectory, "inside.txt"), "not a client manifest");

    mkdirSync(dirname(loaderPath), { recursive: true });
    writeFileSync(
      loaderPath,
      `const _fs = require("node:fs");
function loadManifest(path) {
  const contents = (0, _fs.readFileSync)(path, "utf8");
  return path.endsWith("/BUILD_ID") ? contents : JSON.parse(contents);
}
function evalManifest(path, shouldCache = true, cache = new Map(), handleMissing = false) {
  if (shouldCache && cache.has(path)) return cache.get(path);
  if (handleMissing) return undefined;
  return require(path);
}`,
    );

    const buildOpts = {
      outputDir,
      appBuildOutputPath,
      monorepoRoot,
      nextVersion: "16.4.6",
    };
    const updater = new ContentUpdater(buildOpts);
    inlineLoadManifest(updater, buildOpts);

    const result = await build({
      entryPoints: [loaderPath],
      write: false,
      logLevel: "silent",
      plugins: [updater.plugin],
    });
    const patched = result.outputFiles[0]?.text;
    assert.ok(patched, "OpenNext's manifest plugin must produce patched loader code");
    assert.doesNotMatch(patched, /shouldNotAppear|not a manifest|not a client manifest/);
    assert.doesNotMatch(patched, /readFileSync/);

    const context = {
      require,
      process: { env: { NEXT_BUILD_ID: "deedlight-smoke-build" } },
      __RSC_MANIFEST: { "/page": { clientModules: { fixture: { id: 1 } } } },
    };
    const loader = runInNewContext(`\n${patched}\n;({ loadManifest, evalManifest })`, context);

    assert.deepEqual(JSON.parse(JSON.stringify(loader.loadManifest("/app/.next/prerender-manifest.json"))), {
      version: 4,
      routes: { "/": { initialRevalidateSeconds: 60 } },
    });
    assert.deepEqual(JSON.parse(JSON.stringify(loader.loadManifest("/app/.next/required-server-files.json"))), {
      version: 1,
      config: { output: "standalone" },
    });
    assert.deepEqual(JSON.parse(JSON.stringify(loader.loadManifest("/app/.next/prefetch-hints.json"))), { hints: ["home"] });
    assert.deepEqual(JSON.parse(JSON.stringify(loader.loadManifest("/app/.next/server/preview-props.json"))), { preview: true });
    assert.equal(loader.loadManifest("/app/.next/BUILD_ID"), "deedlight-smoke-build");
    assert.deepEqual(JSON.parse(JSON.stringify(loader.loadManifest("/app/.next/dynamic-css-manifest"))), {});
    assert.throws(() => loader.loadManifest("/app/.next/unknown-required-manifest.json"), /Unexpected loadManifest/);

    const clientResult = loader.evalManifest("/app/.next/server/app/page_client-reference-manifest.js");
    assert.deepEqual(JSON.parse(JSON.stringify(clientResult)), {
      __RSC_MANIFEST: { "/page": { clientModules: { fixture: { id: 1 } } } },
    });
  } finally {
    rmSync(outputDir, { recursive: true, force: true });
  }
});
