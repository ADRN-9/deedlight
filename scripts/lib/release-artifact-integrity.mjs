import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { inflateRawSync } from "node:zlib";
import { lstatSync, readFileSync, readdirSync, mkdirSync, writeFileSync, existsSync } from "node:fs";
import { join, resolve, sep } from "node:path";

export const MAX_ARCHIVE_BYTES = 64 * 1024 * 1024;
const MAX_ENTRIES = 256;
const MAX_ENTRY_BYTES = 16 * 1024 * 1024;
const MAX_TOTAL_UNCOMPRESSED = 64 * 1024 * 1024;
const utf8 = new TextDecoder("utf-8", { fatal: true });

const crcTable = Uint32Array.from({ length: 256 }, (_, value) => {
  let crc = value;
  for (let bit = 0; bit < 8; bit++) crc = (crc & 1) ? (0xedb88320 ^ (crc >>> 1)) : (crc >>> 1);
  return crc >>> 0;
});

export function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function exactSet(actual, expected, label) {
  assert.equal(actual.length, expected.length, label + " count mismatch");
  assert.deepEqual([...actual].sort(), [...expected].sort(), label + " mismatch");
}

function safeMemberName(name) {
  assert.ok(name.length > 0 && !name.includes("\0"), "Empty or NUL ZIP member name");
  assert.ok(!name.startsWith("/") && !name.startsWith("\\") && !/^[a-zA-Z]:/.test(name),
    "Absolute ZIP member path rejected");
  assert.ok(!name.includes("\\"), "Backslash ZIP path rejected");
  assert.ok(!name.endsWith("/"), "Directory ZIP members are not permitted");
  const segments = name.split("/");
  assert.ok(segments.every((part) => part.length > 0 && part !== "." && part !== ".."),
    "Non-canonical ZIP member path rejected");
  assert.ok(!segments.some((part) => part.includes(":")), "Colon in ZIP member path rejected");
  return name;
}

function parseExtraFields(bytes, start, length) {
  let offset = start;
  const end = start + length;
  assert.ok(end <= bytes.length, "Truncated ZIP extra fields");
  while (offset < end) {
    assert.ok(offset + 4 <= end, "Malformed ZIP extra field header");
    const id = bytes.readUInt16LE(offset);
    const size = bytes.readUInt16LE(offset + 2);
    offset += 4;
    assert.ok(offset + size <= end, "Truncated ZIP extra field");
    assert.notEqual(id, 0x0001, "ZIP64 archives are not accepted");
    offset += size;
  }
  assert.equal(offset, end, "Malformed ZIP extra field length");
}

function findEndOfCentralDirectory(bytes) {
  const minimum = Math.max(0, bytes.length - 22 - 0xffff);
  for (let offset = bytes.length - 22; offset >= minimum; offset--) {
    if (bytes.readUInt32LE(offset) !== 0x06054b50) continue;
    const commentLength = bytes.readUInt16LE(offset + 20);
    if (offset + 22 + commentLength === bytes.length) return offset;
  }
  throw new Error("ZIP end-of-central-directory record missing or malformed");
}

function parseZip(bytes, expectedMembers) {
  assert.ok(Buffer.isBuffer(bytes), "ZIP archive must be a Buffer");
  assert.ok(bytes.length >= 22 && bytes.length <= MAX_ARCHIVE_BYTES, "ZIP archive size outside safe bounds");
  const eocd = findEndOfCentralDirectory(bytes);
  const disk = bytes.readUInt16LE(eocd + 4);
  const centralDisk = bytes.readUInt16LE(eocd + 6);
  const entriesOnDisk = bytes.readUInt16LE(eocd + 8);
  const entryCount = bytes.readUInt16LE(eocd + 10);
  const centralSize = bytes.readUInt32LE(eocd + 12);
  const centralOffset = bytes.readUInt32LE(eocd + 16);
  assert.equal(disk, 0, "Multi-disk ZIP is not accepted");
  assert.equal(centralDisk, 0, "Multi-disk ZIP central directory is not accepted");
  assert.equal(entriesOnDisk, entryCount, "Split ZIP directory is not accepted");
  assert.ok(entryCount > 0 && entryCount <= MAX_ENTRIES, "ZIP entry count outside safe bounds");
  assert.notEqual(entryCount, 0xffff, "ZIP64 entry count is not accepted");
  assert.notEqual(centralSize, 0xffffffff, "ZIP64 central directory is not accepted");
  assert.notEqual(centralOffset, 0xffffffff, "ZIP64 central offset is not accepted");
  assert.equal(centralOffset + centralSize, eocd, "ZIP central directory bounds mismatch");

  const entries = [];
  const files = new Map();
  const localRanges = [];
  const localOffsets = new Set();
  let cursor = centralOffset;
  let totalUncompressed = 0;

  for (let index = 0; index < entryCount; index++) {
    assert.ok(cursor + 46 <= eocd && bytes.readUInt32LE(cursor) === 0x02014b50,
      "Malformed ZIP central directory entry");
    const flags = bytes.readUInt16LE(cursor + 8);
    const method = bytes.readUInt16LE(cursor + 10);
    const expectedCrc = bytes.readUInt32LE(cursor + 16);
    const compressedSize = bytes.readUInt32LE(cursor + 20);
    const uncompressedSize = bytes.readUInt32LE(cursor + 24);
    const nameLength = bytes.readUInt16LE(cursor + 28);
    const extraLength = bytes.readUInt16LE(cursor + 30);
    const commentLength = bytes.readUInt16LE(cursor + 32);
    const startDisk = bytes.readUInt16LE(cursor + 34);
    const externalAttributes = bytes.readUInt32LE(cursor + 38);
    const localOffset = bytes.readUInt32LE(cursor + 42);
    const end = cursor + 46 + nameLength + extraLength + commentLength;
    assert.ok(end <= eocd, "Truncated ZIP central directory entry");
    assert.equal(startDisk, 0, "Split ZIP member is not accepted");
    assert.ok((flags & 0x2041) === 0, "Encrypted ZIP members are not accepted");
    assert.ok((flags & 0x2000) === 0, "Masked ZIP headers are not accepted");
    assert.ok(method === 0 || method === 8, "Unsupported ZIP compression method");
    assert.notEqual(compressedSize, 0xffffffff, "ZIP64 member size is not accepted");
    assert.notEqual(uncompressedSize, 0xffffffff, "ZIP64 member size is not accepted");
    assert.ok(compressedSize <= MAX_ARCHIVE_BYTES && uncompressedSize <= MAX_ENTRY_BYTES,
      "ZIP member size outside safe bounds");
    totalUncompressed += uncompressedSize;
    assert.ok(totalUncompressed <= MAX_TOTAL_UNCOMPRESSED, "ZIP expansion exceeds safe bounds");

    const nameBytes = bytes.subarray(cursor + 46, cursor + 46 + nameLength);
    const name = safeMemberName(utf8.decode(nameBytes));
    assert.ok(!files.has(name), "Duplicate ZIP member: " + name);
    parseExtraFields(bytes, cursor + 46 + nameLength, extraLength);

    const unixMode = (externalAttributes >>> 16) & 0xffff;
    const fileType = unixMode & 0o170000;
    assert.ok(fileType === 0 || fileType === 0o100000, "Non-regular ZIP member rejected");
    assert.equal(externalAttributes & 0x10, 0, "Directory ZIP member rejected");
    assert.ok(!localOffsets.has(localOffset), "Duplicate ZIP local-header offset");
    localOffsets.add(localOffset);
    assert.ok(localOffset + 30 <= centralOffset && bytes.readUInt32LE(localOffset) === 0x04034b50,
      "Malformed ZIP local file header");

    const localFlags = bytes.readUInt16LE(localOffset + 6);
    const localMethod = bytes.readUInt16LE(localOffset + 8);
    const localCrc = bytes.readUInt32LE(localOffset + 14);
    const localCompressedSize = bytes.readUInt32LE(localOffset + 18);
    const localUncompressedSize = bytes.readUInt32LE(localOffset + 22);
    const localNameLength = bytes.readUInt16LE(localOffset + 26);
    const localExtraLength = bytes.readUInt16LE(localOffset + 28);
    const localNameStart = localOffset + 30;
    const localNameEnd = localNameStart + localNameLength;
    const dataStart = localNameEnd + localExtraLength;
    const dataEnd = dataStart + compressedSize;
    assert.ok(dataStart <= centralOffset && dataEnd <= centralOffset,
      "ZIP member data overlaps central directory");
    assert.equal(localFlags, flags, "ZIP local and central flags differ");
    assert.equal(localMethod, method, "ZIP local and central compression differs");
    assert.deepEqual(bytes.subarray(localNameStart, localNameEnd), nameBytes,
      "ZIP local and central names differ");
    parseExtraFields(bytes, localNameEnd, localExtraLength);
    if ((flags & 0x0008) === 0) {
      assert.equal(localCrc, expectedCrc, "ZIP local CRC differs");
      assert.equal(localCompressedSize, compressedSize, "ZIP local compressed size differs");
      assert.equal(localUncompressedSize, uncompressedSize, "ZIP local uncompressed size differs");
    } else {
      assert.ok(localCrc === 0 || localCrc === expectedCrc, "ZIP descriptor CRC header mismatch");
      assert.ok(localCompressedSize === 0 || localCompressedSize === compressedSize,
        "ZIP descriptor compressed size header mismatch");
      assert.ok(localUncompressedSize === 0 || localUncompressedSize === uncompressedSize,
        "ZIP descriptor uncompressed size header mismatch");
    }

    const compressed = bytes.subarray(dataStart, dataEnd);
    let plain;
    if (method === 0) {
      plain = Buffer.from(compressed);
    } else {
      plain = inflateRawSync(compressed, { maxOutputLength: Math.max(1, uncompressedSize + 1) });
    }
    assert.equal(plain.length, uncompressedSize, "ZIP uncompressed size mismatch");
    assert.equal(crc32(plain), expectedCrc, "ZIP member CRC mismatch");

    let localEnd = dataEnd;
    if ((flags & 0x0008) !== 0) {
      const signedStart = localEnd + 4;
      const signedMatches = signedStart + 12 <= centralOffset
        && bytes.readUInt32LE(localEnd) === 0x08074b50
        && bytes.readUInt32LE(signedStart) === expectedCrc
        && bytes.readUInt32LE(signedStart + 4) === compressedSize
        && bytes.readUInt32LE(signedStart + 8) === uncompressedSize;
      const descriptorStart = signedMatches ? signedStart : localEnd;
      assert.ok(descriptorStart + 12 <= centralOffset, "Truncated ZIP data descriptor");
      assert.equal(bytes.readUInt32LE(descriptorStart), expectedCrc, "ZIP data descriptor CRC mismatch");
      assert.equal(bytes.readUInt32LE(descriptorStart + 4), compressedSize,
        "ZIP data descriptor compressed size mismatch");
      assert.equal(bytes.readUInt32LE(descriptorStart + 8), uncompressedSize,
        "ZIP data descriptor uncompressed size mismatch");
      localEnd = descriptorStart + 12;
    }
    localRanges.push({ start: localOffset, end: localEnd, name });
    files.set(name, plain);
    entries.push(name);
    cursor = end;
  }

  assert.equal(cursor, centralOffset + centralSize, "Unexpected bytes in ZIP central directory");
  localRanges.sort((a, b) => a.start - b.start);
  for (let index = 1; index < localRanges.length; index++) {
    assert.ok(localRanges[index - 1].end <= localRanges[index].start,
      "Overlapping ZIP local entries");
  }
  exactSet(entries, expectedMembers, "ZIP archive members");
  return files;
}

export function verifyArtifactArchive({ bytes, artifact, expected, expectedMembers }) {
  assert.ok(expected && Number.isSafeInteger(expected.artifactId) && expected.artifactId > 0,
    "Expected GitHub artifact ID is required");
  assert.equal(artifact?.id, expected.artifactId, "GitHub artifact ID mismatch");
  assert.equal(artifact?.name, expected.artifactName, "GitHub artifact name mismatch");
  assert.equal(artifact?.expired, false, "Expired GitHub artifact rejected");
  assert.ok(Number.isSafeInteger(artifact?.size_in_bytes) && artifact.size_in_bytes > 0,
    "GitHub artifact size metadata missing");
  assert.match(artifact?.digest ?? "", /^sha256:[a-f0-9]{64}$/,
    "GitHub artifact SHA-256 metadata missing");
  assert.equal(expected.repository, "ADRN-9/deedlight", "Unexpected expected repository");
  assert.ok(Number.isSafeInteger(expected.repositoryId) && expected.repositoryId > 0,
    "Expected repository ID missing");
  assert.ok(Number.isSafeInteger(expected.runId) && expected.runId > 0, "Expected run ID missing");
  assert.match(expected.headSha ?? "", /^[a-f0-9]{40}$/, "Expected source SHA missing");
  assert.ok(expected.headBranch, "Expected source branch missing");
  const workflowRun = artifact.workflow_run;
  assert.ok(workflowRun && typeof workflowRun === "object", "Artifact workflow provenance missing");
  assert.equal(workflowRun.id, expected.runId, "Artifact workflow run mismatch");
  assert.equal(workflowRun.repository_id, expected.repositoryId, "Artifact repository ID mismatch");
  assert.equal(workflowRun.head_repository_id, expected.repositoryId, "Artifact head repository ID mismatch");
  assert.equal(workflowRun.head_sha, expected.headSha, "Artifact source commit mismatch");
  assert.equal(workflowRun.head_branch, expected.headBranch, "Artifact source branch mismatch");

  assert.ok(Buffer.isBuffer(bytes), "Downloaded GitHub artifact bytes missing");
  assert.equal(bytes.length, artifact.size_in_bytes, "GitHub artifact byte length mismatch");
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  assert.equal("sha256:" + sha256, artifact.digest, "GitHub artifact SHA-256 mismatch");
  const files = parseZip(bytes, expectedMembers);
  return {
    artifact_id: artifact.id,
    artifact_name: artifact.name,
    artifact_digest: artifact.digest,
    artifact_sha256: sha256,
    artifact_size_bytes: bytes.length,
    archive_members: [...files.keys()].sort(),
    files,
  };
}

export async function downloadArtifactArchive({ repository, artifactId, token }) {
  assert.equal(repository, "ADRN-9/deedlight", "Unexpected artifact repository");
  assert.ok(Number.isSafeInteger(artifactId) && artifactId > 0, "Invalid artifact ID");
  assert.ok(typeof token === "string" && token.length > 0, "GitHub actions:read token missing");
  const url = "https://api.github.com/repos/" + repository + "/actions/artifacts/" + artifactId + "/zip";
  const response = await fetch(url, {
    method: "GET",
    redirect: "follow",
    headers: {
      authorization: "Bearer " + token,
      accept: "application/vnd.github+json",
      "x-github-api-version": "2022-11-28",
      "user-agent": "deedlight-release-artifact-verifier",
    },
  });
  assert.equal(response.ok, true, "GitHub artifact download failed with HTTP " + response.status);
  assert.ok(response.url.startsWith("https://"), "Artifact download did not remain HTTPS");
  const contentType = response.headers.get("content-type") ?? "";
  assert.ok(!/text\/html/i.test(contentType), "GitHub returned an HTML artifact response");
  const lengthHeader = response.headers.get("content-length");
  if (lengthHeader !== null) {
    const length = Number(lengthHeader);
    assert.ok(Number.isSafeInteger(length) && length > 0 && length <= MAX_ARCHIVE_BYTES,
      "Artifact download content length outside safe bounds");
  }
  assert.ok(response.body, "GitHub artifact response body missing");
  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    assert.ok(total <= MAX_ARCHIVE_BYTES, "GitHub artifact exceeds download size limit");
    chunks.push(Buffer.from(value));
  }
  assert.ok(total > 0, "GitHub returned an empty artifact archive");
  return Buffer.concat(chunks, total);
}

function collectFiles(directory, prefix = "", result = new Map()) {
  const entries = readdirSync(directory).sort();
  for (const entry of entries) {
    const path = join(directory, entry);
    const info = lstatSync(path);
    const name = prefix ? prefix + "/" + entry : entry;
    assert.equal(info.isSymbolicLink(), false, "Symlink in extracted artifact: " + name);
    if (info.isDirectory()) {
      collectFiles(path, name, result);
    } else {
      assert.equal(info.isFile(), true, "Non-regular extracted artifact member: " + name);
      result.set(name, readFileSync(path));
    }
  }
  return result;
}

export function verifyExtractedArtifactDirectory(directory, archiveFiles) {
  const extracted = collectFiles(directory);
  exactSet([...extracted.keys()], [...archiveFiles.keys()], "Extracted artifact member set");
  for (const [name, bytes] of archiveFiles) {
    assert.deepEqual(extracted.get(name), bytes, "Extracted artifact bytes differ: " + name);
  }
  return [...extracted.keys()].sort();
}

export function extractVerifiedArtifactFiles(directory, archiveFiles) {
  const root = resolve(directory);
  assert.equal(existsSync(root), false, "Refusing to overwrite an extracted artifact directory");
  mkdirSync(root);
  assert.ok(lstatSync(root).isDirectory() && !lstatSync(root).isSymbolicLink(),
    "Unsafe extracted artifact root");
  for (const [name, bytes] of archiveFiles) {
    safeMemberName(name);
    const segments = name.split("/");
    const destination = resolve(root, ...segments);
    assert.ok(destination.startsWith(root + sep), "ZIP member escaped extraction root");
    let parent = root;
    for (const segment of segments.slice(0, -1)) {
      parent = join(parent, segment);
      if (existsSync(parent)) {
        const info = lstatSync(parent);
        assert.ok(info.isDirectory() && !info.isSymbolicLink(),
          "Unsafe ZIP extraction parent directory");
      } else {
        mkdirSync(parent);
      }
    }
    const target = join(parent, segments.at(-1));
    assert.equal(existsSync(target), false, "Duplicate ZIP extraction target");
    writeFileSync(target, bytes, { flag: "wx", mode: 0o600 });
  }
  return verifyExtractedArtifactDirectory(root, archiveFiles);
}
