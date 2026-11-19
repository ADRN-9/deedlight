import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { inflateRawSync } from "node:zlib";
import {
  closeSync,
  constants,
  fsyncSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, resolve, sep } from "node:path";

export const MAX_ARCHIVE_BYTES = 64 * 1024 * 1024;
const MAX_ENTRIES = 256;
const MAX_ENTRY_BYTES = 16 * 1024 * 1024;
const MAX_TOTAL_UNCOMPRESSED = 64 * 1024 * 1024;
const MAX_NAME_BYTES = 1024;
const MAX_EXTRA_BYTES = 4096;
const MAX_TOTAL_METADATA_BYTES = 1024 * 1024;
const DATA_DESCRIPTOR_SIGNATURE = 0x08074b50;
const CP437_HIGH =
  "ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»" +
  "░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀" +
  "αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ";
const utf8 = new TextDecoder("utf-8", { fatal: true });

export class ArtifactIntegrityError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "ArtifactIntegrityError";
    this.code = code;
  }
}

function reject(condition, code, message) {
  if (!condition) throw new ArtifactIntegrityError(code, message);
}

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
  reject(actual.length === expected.length, "ZIP_MEMBER_SET_MISMATCH", label + " count mismatch");
  const left = [...actual].sort();
  const right = [...expected].sort();
  reject(left.every((value, index) => value === right[index]),
    "ZIP_MEMBER_SET_MISMATCH", label + " mismatch");
}

function safeMemberName(name) {
  reject(typeof name === "string" && name.length > 0 && !name.includes("\0"),
    "ZIP_FILENAME_NOT_CANONICAL", "Empty or NUL ZIP member name");
  reject(!name.startsWith("/") && !name.startsWith("\\") && !/^[a-zA-Z]:/.test(name),
    "ZIP_FILENAME_NOT_CANONICAL", "Absolute ZIP member path rejected");
  reject(!name.includes("\\"), "ZIP_FILENAME_NOT_CANONICAL", "Backslash ZIP path rejected");
  reject(!name.endsWith("/"), "ZIP_FILENAME_NOT_CANONICAL", "Directory ZIP members are not permitted");
  const segments = name.split("/");
  reject(segments.every((part) => part.length > 0 && part !== "." && part !== ".."),
    "ZIP_FILENAME_NOT_CANONICAL", "Non-canonical ZIP member path rejected");
  reject(!segments.some((part) => part.includes(":")),
    "ZIP_FILENAME_NOT_CANONICAL", "Colon in ZIP member path rejected");
  return name;
}

function decodeZipName(bytes, flags) {
  if ((flags & 0x0800) !== 0) {
    try {
      return utf8.decode(bytes);
    } catch {
      throw new ArtifactIntegrityError("ZIP_FILENAME_INVALID_UTF8", "EFS filename is not valid UTF-8");
    }
  }
  let value = "";
  for (const byte of bytes) {
    value += byte < 0x80 ? String.fromCharCode(byte) : CP437_HIGH[byte - 0x80];
  }
  return value;
}

function validateFlags(flags, method) {
  const allowed = method === 0 ? 0x0808 : 0x080e;
  reject((flags & ~allowed) === 0, "ZIP_FLAGS_UNSUPPORTED",
    "Unsupported general-purpose ZIP flags for compression method " + method);
}

function parseExtraFields(bytes, start, length, location) {
  let offset = start;
  const end = start + length;
  const seen = new Set();
  reject(end <= bytes.length, "ZIP_EXTRA_FIELD_MALFORMED", "Truncated ZIP extra fields");
  while (offset < end) {
    reject(offset + 4 <= end, "ZIP_EXTRA_FIELD_MALFORMED", "Malformed ZIP extra field header");
    const id = bytes.readUInt16LE(offset);
    const size = bytes.readUInt16LE(offset + 2);
    offset += 4;
    reject(offset + size <= end, "ZIP_EXTRA_FIELD_MALFORMED", "Truncated ZIP extra field");
    reject(id !== 0x0001, "ZIP64_EXTRA_NOT_SUPPORTED", "ZIP64 extra fields are not accepted");
    reject(id === 0x5455, "ZIP_EXTRA_FIELD_UNSUPPORTED",
      "Unsupported ZIP extra field 0x" + id.toString(16));
    reject(!seen.has(id), "ZIP_EXTRA_FIELD_MALFORMED", "Duplicate ZIP extended timestamp field");
    seen.add(id);
    reject(size >= 1, "ZIP_EXTRA_FIELD_MALFORMED", "Extended timestamp field is empty");
    const flags = bytes[offset];
    const allowedTimestampFlags = location === "central" ? 0x01 : 0x07;
    reject((flags & ~allowedTimestampFlags) === 0, "ZIP_EXTRA_FIELD_MALFORMED",
      "Extended timestamp field has unsupported flags for " + location + " header");
    const timestampCount = Number(flags & 1) + Number(flags & 2) + Number(flags & 4);
    reject(size === 1 + timestampCount * 4, "ZIP_EXTRA_FIELD_MALFORMED",
      "Extended timestamp field length does not match its flags");
    offset += size;
  }
  reject(offset === end, "ZIP_EXTRA_FIELD_MALFORMED", "Malformed ZIP extra field length");
}

function findEndOfCentralDirectory(bytes) {
  const minimum = Math.max(0, bytes.length - 22 - 0xffff);
  for (let offset = bytes.length - 22; offset >= minimum; offset--) {
    if (bytes.readUInt32LE(offset) !== 0x06054b50) continue;
    const commentLength = bytes.readUInt16LE(offset + 20);
    if (offset + 22 + commentLength === bytes.length) return offset;
  }
  throw new ArtifactIntegrityError("ZIP_EOCD_INVALID",
    "ZIP end-of-central-directory record missing or malformed");
}

function parseZip(bytes, expectedMembers) {
  reject(Buffer.isBuffer(bytes), "ZIP_INPUT_INVALID", "ZIP archive must be a Buffer");
  reject(bytes.length >= 22 && bytes.length <= MAX_ARCHIVE_BYTES,
    "ZIP_RESOURCE_LIMIT", "ZIP archive size outside safe bounds");
  reject(Array.isArray(expectedMembers) && expectedMembers.length > 0,
    "ZIP_EXPECTED_MEMBERS_INVALID", "Expected ZIP member list is required");

  const eocd = findEndOfCentralDirectory(bytes);
  const disk = bytes.readUInt16LE(eocd + 4);
  const centralDisk = bytes.readUInt16LE(eocd + 6);
  const entriesOnDisk = bytes.readUInt16LE(eocd + 8);
  const entryCount = bytes.readUInt16LE(eocd + 10);
  const centralSize = bytes.readUInt32LE(eocd + 12);
  const centralOffset = bytes.readUInt32LE(eocd + 16);
  const commentLength = bytes.readUInt16LE(eocd + 20);
  reject(commentLength === 0, "ZIP_CENTRAL_DIRECTORY_LAYOUT",
    "ZIP archive comments are not accepted");
  reject(disk === 0 && centralDisk === 0 && entriesOnDisk === entryCount,
    "ZIP_MULTIDISK_NOT_SUPPORTED", "Multi-disk ZIP is not accepted");
  reject(entryCount > 0 && entryCount <= MAX_ENTRIES,
    "ZIP_RESOURCE_LIMIT", "ZIP entry count outside safe bounds");
  reject(entryCount !== 0xffff && centralSize !== 0xffffffff && centralOffset !== 0xffffffff,
    "ZIP64_NOT_SUPPORTED", "ZIP64 archive metadata is not accepted");
  reject(centralOffset + centralSize === eocd && centralOffset > 0,
    "ZIP_CENTRAL_DIRECTORY_LAYOUT", "ZIP central directory bounds mismatch");

  const entries = [];
  const files = new Map();
  const localRanges = [];
  const localOffsets = new Set();
  let cursor = centralOffset;
  let totalUncompressed = 0;
  let totalMetadata = 0;

  for (let index = 0; index < entryCount; index++) {
    reject(cursor + 46 <= eocd && bytes.readUInt32LE(cursor) === 0x02014b50,
      "ZIP_CENTRAL_DIRECTORY_LAYOUT", "Malformed ZIP central directory entry");
    const madeBy = bytes.readUInt16LE(cursor + 4);
    const versionNeeded = bytes.readUInt16LE(cursor + 6);
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

    reject(end <= eocd, "ZIP_CENTRAL_DIRECTORY_LAYOUT", "Truncated ZIP central directory entry");
    reject(commentLength === 0, "ZIP_CENTRAL_DIRECTORY_LAYOUT",
      "ZIP per-member comments are not accepted");
    reject(startDisk === 0, "ZIP_MULTIDISK_NOT_SUPPORTED", "Split ZIP member is not accepted");
    reject(method === 0 || method === 8, "ZIP_METHOD_UNSUPPORTED", "Unsupported ZIP compression method");
    validateFlags(flags, method);
    reject(versionNeeded >= (method === 8 ? 20 : 10) && versionNeeded <= 20,
      "ZIP_VERSION_UNSUPPORTED", "Unsupported ZIP version-needed value");
    reject(compressedSize !== 0xffffffff && uncompressedSize !== 0xffffffff
      && localOffset !== 0xffffffff,
    "ZIP64_NOT_SUPPORTED", "ZIP64 member metadata is not accepted");
    reject(nameLength > 0 && nameLength <= MAX_NAME_BYTES && extraLength <= MAX_EXTRA_BYTES,
      "ZIP_RESOURCE_LIMIT", "ZIP member metadata outside safe bounds");
    totalMetadata += nameLength + extraLength;
    reject(totalMetadata <= MAX_TOTAL_METADATA_BYTES,
      "ZIP_RESOURCE_LIMIT", "ZIP aggregate metadata exceeds safe bounds");
    reject(compressedSize <= MAX_ARCHIVE_BYTES && uncompressedSize <= MAX_ENTRY_BYTES,
      "ZIP_RESOURCE_LIMIT", "ZIP member size outside safe bounds");
    totalUncompressed += uncompressedSize;
    reject(totalUncompressed <= MAX_TOTAL_UNCOMPRESSED,
      "ZIP_RESOURCE_LIMIT", "ZIP expansion exceeds safe bounds");
    const nameBytes = bytes.subarray(cursor + 46, cursor + 46 + nameLength);
    const name = safeMemberName(decodeZipName(nameBytes, flags));
    reject(!files.has(name), "ZIP_DUPLICATE_MEMBER", "Duplicate ZIP member: " + name);
    parseExtraFields(bytes, cursor + 46 + nameLength, extraLength, "central");

    const operatingSystem = madeBy >>> 8;
    const unixMode = (externalAttributes >>> 16) & 0xffff;
    const fileType = unixMode & 0o170000;
    if (operatingSystem === 3) {
      reject(fileType === 0 || fileType === 0o100000,
        "ZIP_FILE_TYPE_UNSUPPORTED", "Non-regular ZIP member rejected");
    }
    reject((externalAttributes & 0x10) === 0,
      "ZIP_FILE_TYPE_UNSUPPORTED", "Directory ZIP member rejected");
    reject(!localOffsets.has(localOffset), "ZIP_LOCAL_RECORD_LAYOUT",
      "Duplicate ZIP local-header offset");
    localOffsets.add(localOffset);
    reject(localOffset + 30 <= centralOffset && bytes.readUInt32LE(localOffset) === 0x04034b50,
      "ZIP_LOCAL_RECORD_LAYOUT", "Malformed ZIP local file header");

    const localVersionNeeded = bytes.readUInt16LE(localOffset + 4);
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

    reject(localVersionNeeded === versionNeeded && localMethod === method,
      "ZIP_LOCAL_CENTRAL_MISMATCH", "ZIP local and central version/method differ");
    reject(localFlags === flags, "ZIP_FLAGS_LOCAL_CENTRAL_MISMATCH",
      "ZIP local and central flags differ");
    validateFlags(localFlags, localMethod);
    reject(localNameLength === nameLength && localExtraLength <= MAX_EXTRA_BYTES
      && dataStart <= centralOffset && dataEnd <= centralOffset,
    "ZIP_LOCAL_RECORD_LAYOUT", "ZIP local member bounds are invalid");
    reject(bytes.subarray(localNameStart, localNameEnd).equals(nameBytes),
      "ZIP_LOCAL_CENTRAL_MISMATCH", "ZIP local and central names differ");
    totalMetadata += localNameLength + localExtraLength;
    reject(totalMetadata <= MAX_TOTAL_METADATA_BYTES,
      "ZIP_RESOURCE_LIMIT", "ZIP aggregate metadata exceeds safe bounds");
    parseExtraFields(bytes, localNameEnd, localExtraLength, "local");

    const hasDescriptor = (flags & 0x0008) !== 0;
    if (!hasDescriptor) {
      reject(localCrc === expectedCrc && localCompressedSize === compressedSize
        && localUncompressedSize === uncompressedSize,
      "ZIP_LOCAL_CENTRAL_MISMATCH", "ZIP local CRC/sizes differ from central directory");
    } else {
      reject((localCrc === 0 || localCrc === expectedCrc)
        && (localCompressedSize === 0 || localCompressedSize === compressedSize)
        && (localUncompressedSize === 0 || localUncompressedSize === uncompressedSize),
      "ZIP_LOCAL_CENTRAL_MISMATCH", "ZIP descriptor local-header placeholders are inconsistent");
    }

    const compressed = bytes.subarray(dataStart, dataEnd);
    let plain;
    if (method === 0) {
      reject(compressedSize === uncompressedSize, "ZIP_STORED_SIZE_MISMATCH",
        "Stored ZIP member compressed and uncompressed sizes differ");
      plain = Buffer.from(compressed);
    } else {
      let inflated;
      try {
        inflated = inflateRawSync(compressed, {
          maxOutputLength: Math.max(1, uncompressedSize + 1),
          info: true,
        });
      } catch {
        throw new ArtifactIntegrityError("ZIP_DEFLATE_INVALID", "Deflate stream is truncated or invalid");
      }
      reject(inflated.engine.bytesWritten === compressed.length,
        "ZIP_DEFLATE_TRAILING_DATA", "Deflate stream did not consume the complete compressed member");
      plain = inflated.buffer;
    }
    reject(plain.length === uncompressedSize, "ZIP_UNCOMPRESSED_SIZE_MISMATCH",
      "ZIP uncompressed size mismatch");
    reject(crc32(plain) === expectedCrc, "ZIP_CRC_MISMATCH", "ZIP member CRC mismatch");

    let localEnd = dataEnd;
    if (hasDescriptor) {
      const hasSignature = bytes.readUInt32LE(dataEnd) === DATA_DESCRIPTOR_SIGNATURE
        && dataEnd + 16 <= centralOffset
        && bytes.readUInt32LE(dataEnd + 4) === expectedCrc
        && bytes.readUInt32LE(dataEnd + 8) === compressedSize
        && bytes.readUInt32LE(dataEnd + 12) === uncompressedSize;
      const descriptorStart = hasSignature ? dataEnd + 4 : dataEnd;
      reject(descriptorStart + 12 <= centralOffset, "ZIP_DATA_DESCRIPTOR_MISMATCH",
        "Truncated ZIP data descriptor");
      reject(bytes.readUInt32LE(descriptorStart) === expectedCrc
        && bytes.readUInt32LE(descriptorStart + 4) === compressedSize
        && bytes.readUInt32LE(descriptorStart + 8) === uncompressedSize,
      "ZIP_DATA_DESCRIPTOR_MISMATCH", "ZIP data descriptor differs from central directory");
      localEnd = descriptorStart + 12;
    }

    localRanges.push({ start: localOffset, end: localEnd, name });
    files.set(name, plain);
    entries.push(name);
    cursor = end;
  }

  reject(cursor === centralOffset + centralSize, "ZIP_CENTRAL_DIRECTORY_LAYOUT",
    "Unexpected bytes in ZIP central directory");
  localRanges.sort((a, b) => a.start - b.start);
  reject(localRanges.length > 0 && localRanges[0].start === 0,
    "ZIP_LOCAL_RECORD_LAYOUT", "ZIP archive prefix before first local record is not accepted");
  for (let index = 1; index < localRanges.length; index++) {
    reject(localRanges[index - 1].end === localRanges[index].start,
      "ZIP_LOCAL_RECORD_LAYOUT", "ZIP local records contain an unreferenced gap or overlap");
  }
  reject(localRanges.at(-1).end === centralOffset,
    "ZIP_LOCAL_RECORD_LAYOUT", "ZIP local records do not end at the central directory");
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

const APPROVED_REDIRECT_HOSTS = new Set([
  "api.github.com",
  "github.com",
  "release-assets.githubusercontent.com",
  "objects.githubusercontent.com",
  "pipelines.actions.githubusercontent.com",
]);

function validateRedirectUrl(location, currentUrl) {
  let destination;
  try {
    destination = new URL(location, currentUrl);
  } catch {
    throw new ArtifactIntegrityError("ARTIFACT_REDIRECT_INVALID", "Artifact redirect URL is invalid");
  }
  const hostAllowed = APPROVED_REDIRECT_HOSTS.has(destination.hostname)
    || /^productionresultssa[0-9]+\.blob\.core\.windows\.net$/.test(destination.hostname);
  reject(destination.protocol === "https:" && hostAllowed
    && destination.username === "" && destination.password === ""
    && (destination.port === "" || destination.port === "443")
    && destination.hash === "",
  "ARTIFACT_REDIRECT_HOST_REJECTED", "Artifact redirect destination is not approved");
  return destination;
}

async function cancelResponse(response) {
  try {
    await response.body?.cancel();
  } catch {
    // Redirect bodies are never consumed.
  }
}

export async function downloadArtifactArchive({
  repository,
  artifactId,
  token,
  signal: callerSignal,
  timeoutMs = 30000,
  maxBytes = MAX_ARCHIVE_BYTES,
}) {
  assert.equal(repository, "ADRN-9/deedlight", "Unexpected artifact repository");
  assert.ok(Number.isSafeInteger(artifactId) && artifactId > 0, "Invalid artifact ID");
  assert.ok(typeof token === "string" && token.length > 0, "GitHub actions:read token missing");
  reject(Number.isInteger(timeoutMs) && timeoutMs >= 1000 && timeoutMs <= 120000,
    "ARTIFACT_DOWNLOAD_TIMEOUT_INVALID", "Artifact download deadline is outside safe bounds");
  reject(Number.isSafeInteger(maxBytes) && maxBytes > 0 && maxBytes <= MAX_ARCHIVE_BYTES,
    "ARTIFACT_DOWNLOAD_LIMIT_INVALID", "Artifact download limit is outside safe bounds");
  if (callerSignal !== undefined) {
    reject(callerSignal instanceof AbortSignal, "ARTIFACT_DOWNLOAD_SIGNAL_INVALID",
      "Artifact download cancellation signal is invalid");
  }

  const timeoutSignal = AbortSignal.timeout(timeoutMs);
  const signal = callerSignal ? AbortSignal.any([callerSignal, timeoutSignal]) : timeoutSignal;
  let currentUrl = new URL("https://api.github.com/repos/" + repository
    + "/actions/artifacts/" + artifactId + "/zip");

  for (let redirectCount = 0; redirectCount <= 5; redirectCount++) {
    if (signal.aborted) {
      throw new ArtifactIntegrityError("ARTIFACT_DOWNLOAD_ABORTED", "Artifact download was cancelled or timed out");
    }
    const headers = redirectCount === 0
      ? {
          authorization: "Bearer " + token,
          accept: "application/vnd.github+json",
          "x-github-api-version": "2022-11-28",
          "user-agent": "deedlight-release-artifact-verifier",
        }
      : { "user-agent": "deedlight-release-artifact-verifier" };
    let response;
    try {
      response = await fetch(currentUrl, {
        method: "GET",
        redirect: "manual",
        headers,
        signal,
      });
    } catch {
      if (signal.aborted) {
        throw new ArtifactIntegrityError("ARTIFACT_DOWNLOAD_ABORTED",
          "Artifact download was cancelled or timed out");
      }
      throw new ArtifactIntegrityError("ARTIFACT_DOWNLOAD_REQUEST_FAILED",
        "GitHub artifact download request failed");
    }
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get("location");
      await cancelResponse(response);
      reject(typeof location === "string" && location.length > 0,
        "ARTIFACT_REDIRECT_INVALID", "Artifact redirect did not include a destination");
      reject(redirectCount < 5, "ARTIFACT_REDIRECT_LIMIT",
        "Artifact download exceeded the redirect limit");
      currentUrl = validateRedirectUrl(location, currentUrl);
      continue;
    }
    if (response.status !== 200) {
      await cancelResponse(response);
      throw new ArtifactIntegrityError("ARTIFACT_DOWNLOAD_HTTP_ERROR",
        "GitHub artifact download failed with HTTP " + response.status);
    }
    if (response.url && new URL(response.url).href !== currentUrl.href) {
      await cancelResponse(response);
      throw new ArtifactIntegrityError("ARTIFACT_REDIRECT_AUTOFOLLOW_REJECTED",
        "Artifact transport followed an uncontrolled redirect");
    }
    const contentType = response.headers.get("content-type") ?? "";
    if (/text\/html/i.test(contentType)) {
      await cancelResponse(response);
      throw new ArtifactIntegrityError("ARTIFACT_DOWNLOAD_CONTENT_TYPE",
        "GitHub returned an HTML artifact response");
    }
    const lengthHeader = response.headers.get("content-length");
    if (lengthHeader !== null) {
      const length = Number(lengthHeader);
      if (!Number.isSafeInteger(length) || length <= 0 || length > maxBytes) {
        await cancelResponse(response);
        throw new ArtifactIntegrityError("ARTIFACT_DOWNLOAD_LENGTH_INVALID",
          "Artifact download content length outside safe bounds");
      }
    }
    reject(response.body, "ARTIFACT_DOWNLOAD_BODY_MISSING", "GitHub artifact response body missing");
    const reader = response.body.getReader();
    const chunks = [];
    let total = 0;
    let completed = false;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) {
          completed = true;
          break;
        }
        total += value.byteLength;
        reject(total <= maxBytes, "ARTIFACT_DOWNLOAD_SIZE_LIMIT",
          "GitHub artifact exceeds download size limit");
        chunks.push(Buffer.from(value));
      }
      reject(total > 0, "ARTIFACT_DOWNLOAD_EMPTY", "GitHub returned an empty artifact archive");
      return Buffer.concat(chunks, total);
    } catch (error) {
      if (!completed) {
        try {
          await reader.cancel(error);
        } catch {
          // Cancellation is best effort after a failed stream.
        }
      }
      if (error instanceof ArtifactIntegrityError) throw error;
      if (signal.aborted) {
        throw new ArtifactIntegrityError("ARTIFACT_DOWNLOAD_ABORTED",
          "Artifact download was cancelled or timed out");
      }
      throw new ArtifactIntegrityError("ARTIFACT_DOWNLOAD_STREAM_FAILED",
        "Artifact download stream failed");
    } finally {
      reader.releaseLock();
    }
  }
  throw new ArtifactIntegrityError("ARTIFACT_REDIRECT_LIMIT", "Artifact download exceeded the redirect limit");
}

function collectFiles(directory, prefix = "", result = new Map()) {
  const entries = readdirSync(directory).sort();
  for (const entry of entries) {
    const path = join(directory, entry);
    const info = lstatSync(path);
    const name = prefix ? prefix + "/" + entry : entry;
    reject(!info.isSymbolicLink(), "EXTRACTED_SYMLINK_REJECTED",
      "Symlink in extracted artifact: " + name);
    if (info.isDirectory()) {
      collectFiles(path, name, result);
    } else {
      reject(info.isFile(), "EXTRACTED_FILE_TYPE_REJECTED",
        "Non-regular extracted artifact member: " + name);
      result.set(name, readFileSync(path));
    }
  }
  return result;
}

export function verifyExtractedArtifactDirectory(directory, archiveFiles) {
  const rootInfo = lstatSync(directory);
  reject(rootInfo.isDirectory() && !rootInfo.isSymbolicLink(),
    "EXTRACTED_ROOT_UNSAFE", "Unsafe extracted artifact root");
  const extracted = collectFiles(directory);
  exactSet([...extracted.keys()], [...archiveFiles.keys()], "Extracted artifact member set");
  for (const [name, bytes] of archiveFiles) {
    reject(extracted.get(name).equals(bytes), "EXTRACTED_CONTENT_MISMATCH",
      "Extracted artifact bytes differ: " + name);
  }
  return [...extracted.keys()].sort();
}

function pathExists(path) {
  try {
    lstatSync(path);
    return true;
  } catch (error) {
    if (error?.code === "ENOENT") return false;
    throw error;
  }
}

export function extractVerifiedArtifactFiles(directory, archiveFiles) {
  const destination = resolve(directory);
  const parent = dirname(destination);
  const parentInfo = lstatSync(parent);
  reject(parentInfo.isDirectory() && !parentInfo.isSymbolicLink(),
    "EXTRACTION_PARENT_UNSAFE", "Extraction parent must be an existing real directory");
  const realParent = realpathSync(parent);
  const finalPath = join(realParent, basename(destination));
  reject(!pathExists(finalPath), "EXTRACTION_DESTINATION_EXISTS",
    "Refusing to overwrite an extracted artifact directory");
  reject(archiveFiles instanceof Map && archiveFiles.size > 0,
    "EXTRACTION_INPUT_INVALID", "Verified archive member map is required");

  let totalBytes = 0;
  for (const [name, bytes] of archiveFiles) {
    safeMemberName(name);
    reject(Buffer.isBuffer(bytes), "EXTRACTION_INPUT_INVALID",
      "Verified archive member bytes must be Buffers");
    totalBytes += bytes.length;
    reject(bytes.length <= MAX_ENTRY_BYTES && totalBytes <= MAX_TOTAL_UNCOMPRESSED,
      "ZIP_RESOURCE_LIMIT", "Extracted artifact exceeds safe size bounds");
  }

  const staging = mkdtempSync(join(realParent, ".deedlight-artifact-"));
  try {
    for (const [name, bytes] of archiveFiles) {
      const segments = name.split("/");
      const destinationPath = resolve(staging, ...segments);
      reject(destinationPath.startsWith(staging + sep),
        "ZIP_FILENAME_NOT_CANONICAL", "ZIP member escaped extraction root");
      let parentPath = staging;
      for (const segment of segments.slice(0, -1)) {
        parentPath = join(parentPath, segment);
        if (pathExists(parentPath)) {
          const info = lstatSync(parentPath);
          reject(info.isDirectory() && !info.isSymbolicLink(),
            "EXTRACTION_PARENT_UNSAFE", "Unsafe ZIP extraction parent directory");
        } else {
          mkdirSync(parentPath, { mode: 0o700 });
        }
      }
      const target = join(parentPath, segments.at(-1));
      const noFollow = constants.O_NOFOLLOW ?? 0;
      const fd = openSync(target,
        constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | noFollow,
        0o600);
      try {
        writeFileSync(fd, bytes);
        fsyncSync(fd);
      } finally {
        closeSync(fd);
      }
    }
    const verifiedNames = verifyExtractedArtifactDirectory(staging, archiveFiles);
    reject(!pathExists(finalPath), "EXTRACTION_DESTINATION_EXISTS",
      "Extraction destination appeared during verification");
    renameSync(staging, finalPath);
    return verifiedNames;
  } catch (error) {
    rmSync(staging, { recursive: true, force: true });
    throw error;
  }
}
