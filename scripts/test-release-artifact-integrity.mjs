import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { deflateRawSync } from "node:zlib";
import { mkdtempSync, rmSync, writeFileSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  crc32,
  verifyArtifactArchive,
  verifyExtractedArtifactDirectory,
  extractVerifiedArtifactFiles,
} from "./lib/release-artifact-integrity.mjs";

const runId = 123456789;
const repository = "ADRN-9/deedlight";
const repositoryId = 1308367373;
const headSha = "2c9bcece2b82f755578a1bce0f97adee18fdb391";
const headBranch = "work/deedlight-c145-dependency-transport-20261118";
const artifactName = "release-evidence-validate-run-" + runId + "-attempt-1";
const expectedMembers = ["commit.txt", "receipt.json", "result.txt", "tree.txt"];

function makeZip(entries) {
  const localParts = [];
  const centralParts = [];
  let offset = 0;
  for (const value of entries) {
    const entry = typeof value === "string" ? { name: value } : value;
    const name = Buffer.from(entry.name, "utf8");
    const plain = Buffer.from(entry.data ?? "fixture\n", "utf8");
    const method = entry.method ?? 8;
    const compressed = method === 8 ? deflateRawSync(plain) : plain;
    const actualCrc = crc32(plain);
    const crc = entry.badCrc ? (actualCrc ^ 1) >>> 0 : actualCrc;
    const flags = entry.flags ?? 0x0808;
    const mode = entry.mode ?? 0o100644;
    const descriptor = (flags & 8) !== 0;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(flags, 6);
    local.writeUInt16LE(method, 8);
    local.writeUInt32LE(descriptor ? 0 : crc, 14);
    local.writeUInt32LE(descriptor ? 0 : compressed.length, 18);
    local.writeUInt32LE(descriptor ? 0 : plain.length, 22);
    local.writeUInt16LE(name.length, 26);
    const localPartsForEntry = [local, name, compressed];
    if (descriptor) {
      const dataDescriptor = Buffer.alloc(16);
      dataDescriptor.writeUInt32LE(0x08074b50, 0);
      dataDescriptor.writeUInt32LE(crc, 4);
      dataDescriptor.writeUInt32LE(compressed.length, 8);
      dataDescriptor.writeUInt32LE(plain.length, 12);
      localPartsForEntry.push(dataDescriptor);
    }
    localParts.push(...localPartsForEntry);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE((3 << 8) | 20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(flags, 8);
    central.writeUInt16LE(method, 10);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(compressed.length, 20);
    central.writeUInt32LE(plain.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt32LE((mode << 16) >>> 0, 38);
    central.writeUInt32LE(offset, 42);
    centralParts.push(central, name);
    offset += localPartsForEntry.reduce((sum, part) => sum + part.length, 0);
  }
  const centralOffset = offset;
  const central = Buffer.concat(centralParts);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(central.length, 12);
  end.writeUInt32LE(centralOffset, 16);
  return Buffer.concat([...localParts, central, end]);
}

function fixture(entries = expectedMembers.map((name) => ({ name, data: name + "\n" }))) {
  const bytes = makeZip(entries);
  const artifact = {
    id: 77,
    name: artifactName,
    expired: false,
    size_in_bytes: bytes.length,
    digest: "sha256:" + createHash("sha256").update(bytes).digest("hex"),
    workflow_run: {
      id: runId,
      repository_id: repositoryId,
      head_repository_id: repositoryId,
      head_sha: headSha,
      head_branch: headBranch,
    },
  };
  const expected = {
    artifactId: 77,
    artifactName,
    repository,
    repositoryId,
    runId,
    headSha,
    headBranch,
  };
  return { bytes, artifact, expected };
}

test("valid deflated ZIP and current-run metadata pass", () => {
  const value = fixture();
  const result = verifyArtifactArchive({ ...value, expectedMembers });
  assert.equal(result.artifact_id, 77);
  assert.equal(result.artifact_sha256, value.artifact.digest.slice(7));
  assert.deepEqual(result.archive_members, [...expectedMembers].sort());
  assert.equal(result.files.get("commit.txt").toString(), "commit.txt\n");
});

for (const [name, mutate] of [
  ["artifact ID mismatch", (v) => { v.expected.artifactId++; }],
  ["artifact name mismatch", (v) => { v.expected.artifactName += "-wrong"; }],
  ["wrong run ID", (v) => { v.artifact.workflow_run.id++; }],
  ["wrong repository ID", (v) => { v.artifact.workflow_run.repository_id++; }],
  ["wrong head repository ID", (v) => { v.artifact.workflow_run.head_repository_id++; }],
  ["wrong source commit", (v) => { v.artifact.workflow_run.head_sha = "0".repeat(40); }],
  ["wrong source branch", (v) => { v.artifact.workflow_run.head_branch += "-wrong"; }],
  ["expired artifact", (v) => { v.artifact.expired = true; }],
  ["missing digest", (v) => { delete v.artifact.digest; }],
  ["mismatched digest", (v) => { v.artifact.digest = "sha256:" + "0".repeat(64); }],
  ["mismatched byte size", (v) => { v.artifact.size_in_bytes++; }],
]) {
  test(name + " fails closed", () => {
    const value = fixture();
    mutate(value);
    assert.throws(() => verifyArtifactArchive({ ...value, expectedMembers }));
  });
}

for (const [name, entries] of [
  ["duplicate member", [...expectedMembers, "commit.txt"].map((name) => ({ name }))],
  ["path traversal", [...expectedMembers.slice(0, 3), { name: "../escape.txt" }]],
  ["absolute path", [...expectedMembers.slice(0, 3), { name: "/escape.txt" }]],
  ["backslash path", [...expectedMembers.slice(0, 3), { name: "..\\escape.txt" }]],
  ["unexpected member", [...expectedMembers, "unexpected.txt"].map((name) => ({ name }))],
  ["symbolic link", expectedMembers.map((name, index) => ({
    name, mode: index === 0 ? 0o120777 : 0o100644,
  }))],
  ["encrypted member", expectedMembers.map((name, index) => ({
    name, flags: index === 0 ? 0x0809 : 0x0808,
  }))],
  ["CRC mismatch", expectedMembers.map((name, index) => ({
    name, badCrc: index === 0,
  }))],
]) {
  test("unsafe or malformed archive: " + name, () => {
    const value = fixture(entries);
    assert.throws(() => verifyArtifactArchive({ ...value, expectedMembers }));
  });
}

test("truncated ZIP archive fails closed", () => {
  const value = fixture();
  value.bytes = value.bytes.subarray(0, value.bytes.length - 8);
  value.artifact.size_in_bytes = value.bytes.length;
  value.artifact.digest = "sha256:" + createHash("sha256").update(value.bytes).digest("hex");
  assert.throws(() => verifyArtifactArchive({ ...value, expectedMembers }));
});

test("extracted directory must exactly match verified ZIP member bytes", () => {
  const value = fixture();
  const archive = verifyArtifactArchive({ ...value, expectedMembers });
  const directory = mkdtempSync(join(tmpdir(), "deedlight-artifact-"));
  try {
    for (const [name, bytes] of archive.files) writeFileSync(join(directory, name), bytes);
    assert.equal(verifyExtractedArtifactDirectory(directory, archive.files).length, 4);
    writeFileSync(join(directory, "result.txt"), "tampered\n");
    assert.throws(() => verifyExtractedArtifactDirectory(directory, archive.files));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("extracted symlink fails closed", () => {
  const value = fixture();
  const archive = verifyArtifactArchive({ ...value, expectedMembers });
  const directory = mkdtempSync(join(tmpdir(), "deedlight-artifact-link-"));
  try {
    for (const [name, bytes] of archive.files) writeFileSync(join(directory, name), bytes);
    symlinkSync(join(directory, "commit.txt"), join(directory, "link.txt"));
    assert.throws(() => verifyExtractedArtifactDirectory(directory, archive.files));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("verified archive extracts nested members without path traversal", () => {
  const value = fixture([
    { name: "c76-kind-logs/result.txt", data: "PASS\n" },
    { name: "receipt.json", data: "{}\n" },
  ]);
  const archive = verifyArtifactArchive({
    ...value,
    expectedMembers: ["c76-kind-logs/result.txt", "receipt.json"],
  });
  const parent = mkdtempSync(join(tmpdir(), "deedlight-safe-extract-"));
  const destination = join(parent, "artifact");
  try {
    assert.deepEqual(
      extractVerifiedArtifactFiles(destination, archive.files),
      ["c76-kind-logs/result.txt", "receipt.json"],
    );
    assert.throws(() => extractVerifiedArtifactFiles(destination, archive.files));
  } finally {
    rmSync(parent, { recursive: true, force: true });
  }
});

test("safe extractor independently rejects traversal members", () => {
  const parent = mkdtempSync(join(tmpdir(), "deedlight-unsafe-extract-"));
  try {
    assert.throws(() => extractVerifiedArtifactFiles(join(parent, "artifact"),
      new Map([["../outside.txt", Buffer.from("unsafe")]])));
  } finally {
    rmSync(parent, { recursive: true, force: true });
  }
});
