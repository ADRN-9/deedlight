import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, extname, join, relative, resolve } from "node:path";

const root = process.cwd();
const openNextDir = join(root, ".open-next");
const workerPath = join(openNextDir, "worker.js");
const serverBundlePath = join(openNextDir, "server-functions", "default", "handler.mjs");
const metafilePath = `${serverBundlePath}.meta.json`;
const assetsDir = join(openNextDir, "assets");
const nextServerDir = join(root, ".next", "server");

function walk(directory) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walk(path));
    else if (entry.isFile()) files.push(path);
  }
  return files;
}

function assertFile(path, label) {
  assert.ok(existsSync(path) && statSync(path).isFile(), `${label} must exist: ${relative(root, path)}`);
  assert.ok(statSync(path).size > 0, `${label} must not be empty: ${relative(root, path)}`);
}

assertFile(workerPath, "Generated Cloudflare Worker");
assertFile(serverBundlePath, "OpenNext server handler");
assertFile(metafilePath, "OpenNext esbuild metafile");
assert.ok(statSync(assetsDir).isDirectory(), "OpenNext static assets directory must exist");

const assetFiles = walk(assetsDir);
assert.ok(assetFiles.length > 0, "OpenNext static assets must contain files");

const nftFiles = walk(nextServerDir).filter((path) => path.endsWith(".nft.json"));
assert.ok(nftFiles.length > 0, "Next.js server output must contain NFT traces for OpenNext bundle discovery");

const metafile = JSON.parse(readFileSync(metafilePath, "utf8"));
assert.ok(metafile.inputs && Object.keys(metafile.inputs).length > 0, "OpenNext metafile must contain traced inputs");
assert.ok(metafile.outputs && Object.keys(metafile.outputs).length > 0, "OpenNext metafile must contain bundle outputs");

const sourceMapFiles = [];
const sourceMapReferences = [];
const inspectFiles = [workerPath, serverBundlePath, ...walk(openNextDir).filter((path) => /\.(?:js|mjs|cjs)$/.test(path))];

for (const file of new Set(inspectFiles)) {
  const source = readFileSync(file, "utf8");
  const references = [...source.matchAll(/(?:\\/\\/|\\/\\*)[#@]\\s*sourceMappingURL=([^\\s*]+)/g)];
  for (const match of references) {
    const value = match[1];
    if (value.startsWith("data:")) continue;
    const mapPath = resolve(dirname(file), value);
    assert.ok(existsSync(mapPath) && statSync(mapPath).isFile(), `source map reference must resolve: ${relative(root, file)} -> ${value}`);
    const map = JSON.parse(readFileSync(mapPath, "utf8"));
    assert.equal(map.version, 3, `source map must use version 3: ${relative(root, mapPath)}`);
    assert.ok(Array.isArray(map.sources), `source map must contain sources: ${relative(root, mapPath)}`);
    sourceMapFiles.push(relative(root, mapPath));
    sourceMapReferences.push({ file: relative(root, file), map: relative(root, mapPath) });
  }
}

const mapFiles = walk(openNextDir).filter((path) => extname(path) === ".map");
for (const path of mapFiles) {
  const map = JSON.parse(readFileSync(path, "utf8"));
  assert.equal(map.version, 3, `generated source map must use version 3: ${relative(root, path)}`);
  assert.ok(Array.isArray(map.sources), `generated source map must contain sources: ${relative(root, path)}`);
}

console.log(JSON.stringify({
  artifacts: {
    workerBytes: statSync(workerPath).size,
    serverHandlerBytes: statSync(serverBundlePath).size,
    assetFiles: assetFiles.length,
    nextNftTraces: nftFiles.length,
    bundleInputs: Object.keys(metafile.inputs).length,
    bundleOutputs: Object.keys(metafile.outputs).length,
  },
  sourceMaps: {
    files: [...new Set([...sourceMapFiles, ...mapFiles.map((path) => relative(root, path))])].sort(),
    references: sourceMapReferences,
  },
}, null, 2));
