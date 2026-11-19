import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { deflateRawSync } from "node:zlib";
import {
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  rmSync,
  statSync,
  symlinkSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  ArtifactIntegrityError,
  MAX_ARCHIVE_BYTES,
  crc32,
  downloadArtifactArchive,
  extractVerifiedArtifactFiles,
  verifyArtifactArchive,
  verifyExtractedArtifactDirectory,
} from "./lib/release-artifact-integrity.mjs";

const runId = 123456789;
const repository = "ADRN-9/deedlight";
const repositoryId = 1308367373;
const headSha = "2c9bcece2b82f755578a1bce0f97adee18fdb391";
const headBranch = "work/deedlight-c145-dependency-transport-20261118";
const artifactName = "release-evidence-validate-run-" + runId + "-attempt-1";
const expectedMembers = ["commit.txt", "receipt.json", "result.txt", "tree.txt"];

function extraField(id, payload) {
  const header = Buffer.alloc(4);
  header.writeUInt16LE(id, 0);
  header.writeUInt16LE(payload.length, 2);
  return Buffer.concat([header, payload]);
}

function makeZip(entries, options = {}) {
  const localParts = [];
  const centralParts = [];
  const offsets = [];
  let localOffset = 0;
  let centralLength = 0;

  const u64 = (value) => {
    const bytes = Buffer.alloc(8);
    bytes.writeBigUInt64LE(BigInt(value), 0);
    return bytes;
  };

  for (const value of entries) {
    const entry = typeof value === "string" ? { name: value } : value;
    const nameBytes = entry.nameBytes ?? Buffer.from(entry.name, "utf8");
    const plain = Buffer.from(entry.data ?? (entry.name + "\n"), "utf8");
    const method = entry.method ?? 8;
    let compressed = entry.compressedOverride
      ? Buffer.from(entry.compressedOverride)
      : method === 8 ? deflateRawSync(plain) : Buffer.from(plain);
    if (entry.compressedSuffix) compressed = Buffer.concat([compressed, entry.compressedSuffix]);
    const actualCrc = crc32(plain);
    const centralCrc = entry.centralCrc ?? actualCrc;
    const flags = entry.flags ?? 0x0808;
    const localFlags = entry.localFlags ?? flags;
    const descriptor = (flags & 8) !== 0;
    const zip64 = entry.zip64 === true;
    const versionNeeded = entry.versionNeeded ?? (zip64 ? 45 : (method === 8 ? 20 : 10));
    const localZip64Extra = zip64 && !descriptor
      ? extraField(0x0001, Buffer.concat([u64(plain.length), u64(compressed.length)]))
      : Buffer.alloc(0);
    const centralZip64Extra = zip64
      ? extraField(0x0001, Buffer.concat([
        u64(plain.length), u64(compressed.length), u64(localOffset),
      ]))
      : Buffer.alloc(0);
    const localExtra = Buffer.concat([localZip64Extra, entry.extraLocal ?? Buffer.alloc(0)]);
    const centralExtra = Buffer.concat([centralZip64Extra, entry.extraCentral ?? Buffer.alloc(0)]);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(versionNeeded, 4);
    local.writeUInt16LE(localFlags, 6);
    local.writeUInt16LE(method, 8);
    local.writeUInt32LE(entry.localDosTimestamp ?? entry.dosTimestamp ?? 0, 10);
    local.writeUInt32LE(entry.localCrc ?? (descriptor ? 0 : actualCrc), 14);
    local.writeUInt32LE(zip64 && !descriptor ? 0xffffffff : (entry.localCompressedSize ?? (descriptor ? 0 : compressed.length)), 18);
    local.writeUInt32LE(zip64 && !descriptor ? 0xffffffff : (entry.localUncompressedSize ?? (descriptor ? 0 : plain.length)), 22);
    local.writeUInt16LE(nameBytes.length, 26);
    local.writeUInt16LE(localExtra.length, 28);

    const localRecord = [local, nameBytes, localExtra, compressed];
    const dataEnd = localOffset + local.length + nameBytes.length + localExtra.length + compressed.length;
    if (descriptor) {
      const descriptorParts = [];
      if (entry.descriptorSignature !== false) {
        const signature = Buffer.alloc(4);
        signature.writeUInt32LE(0x08074b50, 0);
        descriptorParts.push(signature);
      }
      const descriptorBytes = Buffer.alloc(zip64 ? 20 : 12);
      descriptorBytes.writeUInt32LE(entry.descriptorCrc ?? actualCrc, 0);
      if (zip64) {
        descriptorBytes.writeBigUInt64LE(BigInt(compressed.length), 4);
        descriptorBytes.writeBigUInt64LE(BigInt(plain.length), 12);
      } else {
        descriptorBytes.writeUInt32LE(compressed.length, 4);
        descriptorBytes.writeUInt32LE(plain.length, 8);
      }
      descriptorParts.push(descriptorBytes);
      localRecord.push(...descriptorParts);
    }
    const localRecordLength = localRecord.reduce((sum, part) => sum + part.length, 0);
    localParts.push(...localRecord);
    if (entry.gapAfter) localParts.push(entry.gapAfter);
    offsets.push({
      localOffset,
      centralOffset: centralLength,
      dataEnd,
    });
    localOffset += localRecordLength + (entry.gapAfter?.length ?? 0);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE((3 << 8) | (zip64 ? 45 : 20), 4);
    central.writeUInt16LE(versionNeeded, 6);
    central.writeUInt16LE(flags, 8);
    central.writeUInt16LE(method, 10);
    central.writeUInt32LE(entry.centralDosTimestamp ?? entry.dosTimestamp ?? 0, 12);
    central.writeUInt32LE(centralCrc, 16);
    central.writeUInt32LE(zip64 ? 0xffffffff : (entry.centralCompressedSize ?? compressed.length), 20);
    central.writeUInt32LE(zip64 ? 0xffffffff : (entry.centralUncompressedSize ?? plain.length), 24);
    central.writeUInt16LE(nameBytes.length, 28);
    central.writeUInt16LE(centralExtra.length, 30);
    central.writeUInt32LE(((entry.mode ?? 0o100644) << 16) >>> 0, 38);
    central.writeUInt32LE(zip64 ? 0xffffffff : offsets.at(-1).localOffset, 42);
    centralParts.push(central, nameBytes, centralExtra);
    centralLength += central.length + nameBytes.length + centralExtra.length;
  }

  const centralOffset = localOffset;
  const central = Buffer.concat(centralParts);
  const centralGap = options.centralGap ?? Buffer.alloc(0);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(0, 4);
  end.writeUInt16LE(0, 6);
  if (options.zip64Eocd) {
    const zip64EocdOffset = centralOffset + central.length;
    const zip64Eocd = Buffer.alloc(56);
    zip64Eocd.writeUInt32LE(0x06064b50, 0);
    zip64Eocd.writeBigUInt64LE(44n, 4);
    zip64Eocd.writeUInt16LE((3 << 8) | 45, 12);
    zip64Eocd.writeUInt16LE(45, 14);
    zip64Eocd.writeUInt32LE(0, 16);
    zip64Eocd.writeUInt32LE(0, 20);
    zip64Eocd.writeBigUInt64LE(BigInt(entries.length), 24);
    zip64Eocd.writeBigUInt64LE(BigInt(entries.length), 32);
    zip64Eocd.writeBigUInt64LE(BigInt(central.length), 40);
    zip64Eocd.writeBigUInt64LE(BigInt(centralOffset), 48);

    const locator = Buffer.alloc(20);
    locator.writeUInt32LE(0x07064b50, 0);
    locator.writeUInt32LE(0, 4);
    locator.writeBigUInt64LE(BigInt(zip64EocdOffset), 8);
    locator.writeUInt32LE(1, 16);

    end.writeUInt16LE(0xffff, 8);
    end.writeUInt16LE(0xffff, 10);
    end.writeUInt32LE(0xffffffff, 12);
    end.writeUInt32LE(0xffffffff, 16);
    return {
      bytes: Buffer.concat([...localParts, central, zip64Eocd, locator, end]),
      offsets,
      centralOffset,
      zip64EocdOffset,
    };
  }

  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(central.length + centralGap.length, 12);
  end.writeUInt32LE(centralOffset, 16);
  return {
    bytes: Buffer.concat([...localParts, central, centralGap, end]),
    offsets,
    centralOffset,
    zip64EocdOffset: null,
  };
}
function fixture(entries = expectedMembers.map((name) => ({ name })), options = {}) {
  const zip = makeZip(entries, options);
  const bytes = zip.bytes;
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
  return {
    bytes,
    artifact,
    expected,
    offsets: zip.offsets,
    centralOffset: zip.centralOffset,
    zip64EocdOffset: zip.zip64EocdOffset,
    expectedMembers: entries.map((entry) => typeof entry === "string" ? entry : entry.name),
  };
}

function reseal(value) {
  value.artifact.size_in_bytes = value.bytes.length;
  value.artifact.digest = "sha256:" + createHash("sha256").update(value.bytes).digest("hex");
  return value;
}

function verify(value) {
  return verifyArtifactArchive({
    bytes: value.bytes,
    artifact: value.artifact,
    expected: value.expected,
    expectedMembers: value.expectedMembers,
  });
}

function expectCode(callback, code) {
  assert.throws(callback, (error) =>
    error instanceof ArtifactIntegrityError && error.code === code,
  "Expected stable rejection code " + code);
}

function replaceFirst(entries, replacement) {
  const next = entries.map((entry) => ({ ...(typeof entry === "string" ? { name: entry } : entry) }));
  next[0] = { ...next[0], ...replacement };
  return next;
}

function boundedMemberName(index, length = 1024) {
  const prefix = "f" + String(index).padStart(3, "0") + "/";
  return prefix + "a".repeat(length - prefix.length);
}

test("positive control requires matching four-byte DOS modification timestamps", () => {
  const dosTimestamp = 0x58221883;
  const value = fixture(expectedMembers.map((name) => ({ name, dosTimestamp })));
  for (const offset of value.offsets) {
    const local = offset.localOffset;
    const central = value.centralOffset + offset.centralOffset;
    assert.equal(value.bytes.readUInt32LE(local + 10), dosTimestamp);
    assert.equal(value.bytes.readUInt32LE(central + 12), dosTimestamp);
  }
  assert.equal(verify(value).files.size, expectedMembers.length);
});

test("valid Deflate archive and current-run metadata pass", () => {
  const value = fixture();
  const result = verify(value);
  assert.equal(result.artifact_id, 77);
  assert.equal(result.artifact_sha256, value.artifact.digest.slice(7));
  assert.deepEqual(result.archive_members, [...expectedMembers].sort());
  assert.equal(result.files.get("commit.txt").toString(), "commit.txt\n");
});

test("positive controls accept Stored records and signed/unsigned Deflate descriptors", () => {
  const entries = expectedMembers.map((name, index) => index === 0
    ? { name, method: 0, flags: 0x0800 }
    : { name, method: 8, flags: 0x0808, descriptorSignature: index !== 2 });
  const result = verify(fixture(entries));
  assert.equal(result.files.get("commit.txt").toString(), "commit.txt\n");
  assert.equal(result.files.size, expectedMembers.length);
});

test("positive controls accept Stored data descriptors with signed and unsigned forms", () => {
  for (const descriptorSignature of [true, false]) {
    const entries = expectedMembers.map((name, index) => index === 0
      ? { name, method: 0, flags: 0x0808, descriptorSignature }
      : { name, method: 8, flags: 0x0808 });
    const value = fixture(entries);
    const result = verify(value);
    assert.equal(result.files.get("commit.txt").toString(), "commit.txt\n");
    assert.equal(result.files.size, expectedMembers.length);

    for (let index = 0; index < entries.length; index++) {
      const local = value.offsets[index].localOffset;
      const central = value.centralOffset + value.offsets[index].centralOffset;
      const nameLength = value.bytes.readUInt16LE(local + 26);
      const extraLength = value.bytes.readUInt16LE(local + 28);
      const centralCrc = value.bytes.readUInt32LE(central + 16);
      const compressedSize = value.bytes.readUInt32LE(central + 20);
      const uncompressedSize = value.bytes.readUInt32LE(central + 24);
      const dataEnd = local + 30 + nameLength + extraLength + compressedSize;
      const signed = entries[index].descriptorSignature !== false;
      const descriptor = dataEnd + (signed ? 4 : 0);
      if (signed) assert.equal(value.bytes.readUInt32LE(dataEnd), 0x08074b50);
      assert.equal(value.bytes.readUInt32LE(descriptor), centralCrc);
      assert.equal(value.bytes.readUInt32LE(descriptor + 4), compressedSize);
      assert.equal(value.bytes.readUInt32LE(descriptor + 8), uncompressedSize);
      assert.equal(descriptor + 12,
        index + 1 < entries.length ? value.offsets[index + 1].localOffset : value.centralOffset);
      if (index === 0) assert.equal(compressedSize, uncompressedSize);
    }
  }
});

test("positive control accepts descriptor-bit local headers with matching populated CRC and sizes", () => {
  const name = "commit.txt";
  const plain = Buffer.from(name + "\n");
  const size = plain.length;
  const entries = expectedMembers.map((member, index) => index === 0
    ? {
      name: member,
      method: 0,
      flags: 0x0808,
      localCrc: crc32(plain),
      localCompressedSize: size,
      localUncompressedSize: size,
    }
    : { name: member, method: 8, flags: 0x0808 });
  const result = verify(fixture(entries));
  assert.equal(result.files.get(name).toString(), "commit.txt\n");
});

test("positive controls decode CP437 names without EFS and UTF-8 names with EFS", () => {
  const cp437Name = "café.txt";
  const cp437 = fixture([{
    name: cp437Name,
    nameBytes: Buffer.from([0x63, 0x61, 0x66, 0x82, 0x2e, 0x74, 0x78, 0x74]),
    flags: 0,
  }]);
  assert.equal(verify(cp437).archive_members[0], cp437Name);
  const utf8Value = fixture([{ name: cp437Name, flags: 0x0800 }]);
  assert.equal(verify(utf8Value).archive_members[0], cp437Name);
});

test("positive control accepts a well-formed extended timestamp extra field", () => {
  const timestamp = Buffer.alloc(5);
  timestamp[0] = 1;
  timestamp.writeUInt32LE(1700000000, 1);
  const field = extraField(0x5455, timestamp);
  const entries = expectedMembers.map((name, index) => index === 0
    ? { name, extraLocal: field, extraCentral: field }
    : { name });
  assert.equal(verify(fixture(entries)).files.size, expectedMembers.length);
});

test("positive controls accept local mtime, atime and ctime with a matching central mtime", () => {
  const localTime = Buffer.alloc(13);
  localTime[0] = 0x07;
  localTime.writeUInt32LE(1700000000, 1);
  localTime.writeUInt32LE(1700000001, 5);
  localTime.writeUInt32LE(1700000002, 9);
  const centralTime = Buffer.alloc(5);
  centralTime[0] = 0x01;
  centralTime.writeUInt32LE(1700000000, 1);
  const entries = expectedMembers.map((name, index) => index === 0
    ? { name, extraLocal: extraField(0x5455, localTime), extraCentral: extraField(0x5455, centralTime) }
    : { name });
  assert.equal(verify(fixture(entries)).files.size, expectedMembers.length);
});

test("positive control accepts local atime/ctime without a local mtime", () => {
  const localTime = Buffer.alloc(9);
  localTime[0] = 0x06;
  localTime.writeUInt32LE(1700000001, 1);
  localTime.writeUInt32LE(1700000002, 5);
  const centralTime = Buffer.alloc(5);
  centralTime[0] = 0x01;
  centralTime.writeUInt32LE(1700000000, 1);
  const entries = expectedMembers.map((name, index) => index === 0
    ? { name, extraLocal: extraField(0x5455, localTime), extraCentral: extraField(0x5455, centralTime) }
    : { name });
  assert.equal(verify(fixture(entries)).files.size, expectedMembers.length);
});

const semanticCases = [
  {
    name: "Stored method rejects Deflate-only option flags",
    code: "ZIP_FLAGS_UNSUPPORTED",
    entries: () => replaceFirst(expectedMembers, { method: 0, flags: 0x080a }),
  },
  {
    name: "local and central general-purpose flags must match",
    code: "ZIP_FLAGS_LOCAL_CENTRAL_MISMATCH",
    entries: () => replaceFirst(expectedMembers, { flags: 0x0808, localFlags: 0x080a }),
  },
  {
    name: "EFS names must contain valid UTF-8",
    code: "ZIP_FILENAME_INVALID_UTF8",
    entries: () => replaceFirst(expectedMembers, { nameBytes: Buffer.from([0xc3, 0x28]) }),
  },
  {
    name: "non-canonical member paths are rejected",
    code: "ZIP_FILENAME_NOT_CANONICAL",
    entries: () => replaceFirst(expectedMembers, { name: "../commit.txt" }),
  },
  {
    name: "unsupported extra-field identifiers are rejected",
    code: "ZIP_EXTRA_FIELD_UNSUPPORTED",
    entries: () => replaceFirst(expectedMembers, { extraCentral: extraField(0xbeef, Buffer.from([1])) }),
  },
  {
    name: "malformed extra-field lengths are rejected",
    code: "ZIP_EXTRA_FIELD_MALFORMED",
    entries: () => replaceFirst(expectedMembers, {
      extraLocal: Buffer.from([0x55, 0x54, 0x05, 0x00, 0x01]),
    }),
  },
  {
    name: "valid ZIP64 member local/central extras and descriptor variants are rejected",
    code: "ZIP64_EXTRA_NOT_SUPPORTED",
    variants: [
      {
        entries: () => [{ name: "commit.txt", flags: 0x0800, zip64: true }],
        descriptor: false,
      },
      {
        entries: () => [{ name: "commit.txt", flags: 0x0808, zip64: true, descriptorSignature: true }],
        descriptor: true,
      },
    ],
    assertStructure: (value, variant) => {
      const local = value.offsets[0].localOffset;
      const localNameLength = value.bytes.readUInt16LE(local + 26);
      const localExtraLength = value.bytes.readUInt16LE(local + 28);
      const localExtra = local + 30 + localNameLength;
      if (variant.descriptor) {
        assert.equal(value.bytes.readUInt32LE(local + 18), 0);
        assert.equal(value.bytes.readUInt32LE(local + 22), 0);
        assert.equal(localExtraLength, 0);
      } else {
        assert.equal(value.bytes.readUInt32LE(local + 18), 0xffffffff);
        assert.equal(value.bytes.readUInt32LE(local + 22), 0xffffffff);
        assert.equal(value.bytes.readUInt16LE(localExtra), 0x0001);
        assert.equal(value.bytes.readUInt16LE(localExtra + 2), 16);
        assert.equal(value.bytes.readBigUInt64LE(localExtra + 4), BigInt(Buffer.byteLength("commit.txt\n")));
      }
      const central = value.centralOffset;
      const centralNameLength = value.bytes.readUInt16LE(central + 28);
      const centralExtra = central + 46 + centralNameLength;
      assert.equal(value.bytes.readUInt32LE(central + 20), 0xffffffff);
      assert.equal(value.bytes.readUInt32LE(central + 24), 0xffffffff);
      assert.equal(value.bytes.readUInt32LE(central + 42), 0xffffffff);
      assert.equal(value.bytes.readUInt16LE(centralExtra), 0x0001);
      assert.equal(value.bytes.readUInt16LE(centralExtra + 2), 24);
      assert.equal(value.bytes.readBigUInt64LE(centralExtra + 4), BigInt(Buffer.byteLength("commit.txt\n")));
      const compressedSize = Number(value.bytes.readBigUInt64LE(centralExtra + 12));
      assert.equal(value.bytes.readBigUInt64LE(centralExtra + 20), BigInt(local));
      if (variant.descriptor) {
        const dataStart = local + 30 + localNameLength + localExtraLength;
        const dataEnd = dataStart + compressedSize;
        assert.equal(value.bytes.readUInt32LE(dataEnd), 0x08074b50);
        assert.equal(value.bytes.readUInt32LE(dataEnd + 4), crc32(Buffer.from("commit.txt\n")));
        assert.equal(value.bytes.readBigUInt64LE(dataEnd + 8), BigInt(compressedSize));
        assert.equal(value.bytes.readBigUInt64LE(dataEnd + 16), BigInt(Buffer.byteLength("commit.txt\n")));
      } else {
        assert.equal(local + 30 + localNameLength + localExtraLength + compressedSize,
          value.centralOffset);
      }
      assert.ok(value.bytes.subarray(local + 30, local + 30 + localNameLength)
        .equals(value.bytes.subarray(central + 46, central + 46 + centralNameLength)));
    },
  },
  {
    name: "valid ZIP64 EOCD and locator structures are rejected",
    code: "ZIP64_NOT_SUPPORTED",
    entries: () => [{ name: "commit.txt", flags: 0x0800 }],
    options: { zip64Eocd: true },
    assertStructure: (value) => {
      const eocd = value.bytes.length - 22;
      const locator = eocd - 20;
      const zip64Eocd = Number(value.bytes.readBigUInt64LE(locator + 8));
      assert.equal(value.bytes.readUInt32LE(eocd), 0x06054b50);
      assert.equal(value.bytes.readUInt16LE(eocd + 8), 0xffff);
      assert.equal(value.bytes.readUInt16LE(eocd + 10), 0xffff);
      assert.equal(value.bytes.readUInt32LE(eocd + 12), 0xffffffff);
      assert.equal(value.bytes.readUInt32LE(eocd + 16), 0xffffffff);
      assert.equal(value.bytes.readUInt32LE(locator), 0x07064b50);
      assert.equal(value.bytes.readUInt32LE(locator + 4), 0);
      assert.equal(value.bytes.readUInt32LE(locator + 16), 1);
      assert.equal(value.bytes.readUInt32LE(zip64Eocd), 0x06064b50);
      assert.equal(value.bytes.readBigUInt64LE(zip64Eocd + 4), 44n);
      assert.equal(value.bytes.readBigUInt64LE(zip64Eocd + 24), 1n);
      assert.equal(value.bytes.readBigUInt64LE(zip64Eocd + 32), 1n);
      assert.equal(value.bytes.readBigUInt64LE(zip64Eocd + 40), BigInt(zip64Eocd - value.centralOffset));
      assert.equal(value.bytes.readBigUInt64LE(zip64Eocd + 48), BigInt(value.centralOffset));
      assert.equal(value.zip64EocdOffset, zip64Eocd);
    },
  },
  {
    name: "Deflate streams cannot leave unconsumed trailing bytes",
    code: "ZIP_DEFLATE_TRAILING_DATA",
    entries: () => replaceFirst(expectedMembers, { compressedSuffix: Buffer.from([0]) }),
  },
  {
    name: "truncated Deflate streams are rejected",
    code: "ZIP_DEFLATE_INVALID",
    entries: () => {
      const plain = Buffer.from("commit.txt\n");
      return replaceFirst(expectedMembers, {
        compressedOverride: deflateRawSync(plain).subarray(0, -1),
      });
    },
  },
  {
    name: "unreferenced gaps between local records are rejected",
    code: "ZIP_LOCAL_RECORD_LAYOUT",
    entries: () => replaceFirst(expectedMembers, { gapAfter: Buffer.from([0]) }),
  },
  {
    name: "unreferenced bytes inside the central directory are rejected",
    code: "ZIP_CENTRAL_DIRECTORY_LAYOUT",
    options: { centralGap: Buffer.from([0]) },
  },
  {
    name: "data descriptor values must match the central directory",
    code: "ZIP_DATA_DESCRIPTOR_MISMATCH",
    entries: () => replaceFirst(expectedMembers, { descriptorCrc: 0 }),
  },
  {
    name: "EFS UTF-8 BOM-prefixed member names are preserved and rejected",
    code: "ZIP_FILENAME_BOM_NOT_ALLOWED",
    entries: () => [{
      name: "commit.txt",
      nameBytes: Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from("commit.txt")]),
      flags: 0x0800,
    }],
    assertStructure: (value) => {
      const local = value.offsets[0].localOffset;
      const central = value.centralOffset;
      const localNameLength = value.bytes.readUInt16LE(local + 26);
      const centralNameLength = value.bytes.readUInt16LE(central + 28);
      assert.deepEqual(value.bytes.subarray(local + 30, local + 30 + localNameLength),
        Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from("commit.txt")]));
      assert.ok(value.bytes.subarray(local + 30, local + 30 + localNameLength)
        .equals(value.bytes.subarray(central + 46, central + 46 + centralNameLength)));
    },
  },
  {
    name: "local CRC mismatch is rejected independently",
    code: "ZIP_LOCAL_CENTRAL_MISMATCH",
    entries: () => replaceFirst(expectedMembers, { flags: 0x0800, localCrc: 0x12345678 }),
  },
  {
    name: "local compressed-size mismatch is rejected independently",
    code: "ZIP_LOCAL_CENTRAL_MISMATCH",
    entries: () => replaceFirst(expectedMembers, { flags: 0x0800, localCompressedSize: 0x1234 }),
  },
  {
    name: "local uncompressed-size mismatch is rejected independently",
    code: "ZIP_LOCAL_CENTRAL_MISMATCH",
    entries: () => replaceFirst(expectedMembers, { flags: 0x0800, localUncompressedSize: 0x1234 }),
  },
  {
    name: "descriptor-bit local CRC placeholder mismatch is rejected independently",
    code: "ZIP_LOCAL_CENTRAL_MISMATCH",
    entries: () => replaceFirst(expectedMembers, { flags: 0x0808, localCrc: 0x12345678 }),
  },
  {
    name: "descriptor-bit local compressed-size placeholder mismatch is rejected independently",
    code: "ZIP_LOCAL_CENTRAL_MISMATCH",
    entries: () => replaceFirst(expectedMembers, { flags: 0x0808, localCompressedSize: 0x1234 }),
  },
  {
    name: "descriptor-bit local uncompressed-size placeholder mismatch is rejected independently",
    code: "ZIP_LOCAL_CENTRAL_MISMATCH",
    entries: () => replaceFirst(expectedMembers, { flags: 0x0808, localUncompressedSize: 0x1234 }),
  },
  {
    name: "local DOS modification timestamp must match central timestamp exactly",
    code: "ZIP_DOS_TIMESTAMP_MISMATCH",
    entries: () => replaceFirst(expectedMembers, {
      dosTimestamp: 0x58221883,
      localDosTimestamp: 0x58221884,
    }),
    assertStructure: (value) => {
      const local = value.offsets[0].localOffset;
      const central = value.centralOffset + value.offsets[0].centralOffset;
      assert.equal(value.bytes.readUInt32LE(central + 12), 0x58221883);
      assert.equal(value.bytes.readUInt32LE(local + 10), 0x58221884);
    },
  },
  {
    name: "local and central modification timestamps must agree when both are present",
    code: "ZIP_EXTRA_FIELD_TIMESTAMP_MISMATCH",
    entries: () => {
      const localTime = Buffer.alloc(5);
      localTime[0] = 1;
      localTime.writeUInt32LE(1700000000, 1);
      const centralTime = Buffer.alloc(5);
      centralTime[0] = 1;
      centralTime.writeUInt32LE(1700000001, 1);
      return replaceFirst(expectedMembers, {
        extraLocal: extraField(0x5455, localTime),
        extraCentral: extraField(0x5455, centralTime),
      });
    },
  },
];

for (const item of semanticCases) {
  test("C161 semantic negative: " + item.name, () => {
    const variants = item.variants ?? [item];
    for (const variant of variants) {
      const value = fixture(variant.entries ? variant.entries()
        : (item.entries ? item.entries() : undefined), variant.options ?? item.options);
      if (item.assertStructure) item.assertStructure(value, variant);
      if (item.mutate) item.mutate(value);
      reseal(value);
      expectCode(() => verify(value), item.code);
    }
  });
}

test("entry-count and aggregate metadata upper boundaries remain within policy", () => {
  const localTime = Buffer.alloc(13);
  localTime[0] = 0x07;
  localTime.writeUInt32LE(1700000000, 1);
  localTime.writeUInt32LE(1700000001, 5);
  localTime.writeUInt32LE(1700000002, 9);
  const centralTime = Buffer.alloc(5);
  centralTime[0] = 0x01;
  centralTime.writeUInt32LE(1700000000, 1);
  const localExtra = extraField(0x5455, localTime);
  const centralExtra = extraField(0x5455, centralTime);
  const entries = Array.from({ length: 256 }, (_, index) => ({
    name: boundedMemberName(index),
    flags: 0x0800,
    extraLocal: localExtra,
    extraCentral: centralExtra,
  }));
  const maximumMetadata = 256 * (1024 + localExtra.length + 1024 + centralExtra.length);
  assert.equal(maximumMetadata, 530944);
  assert.ok(maximumMetadata < 1024 * 1024);
  assert.equal(verify(fixture(entries)).files.size, 256);
});

test("entry count one above the configured limit is rejected", () => {
  const entries = Array.from({ length: 257 }, (_, index) => ({
    name: "member-" + String(index).padStart(3, "0") + ".txt",
    flags: 0x0800,
  }));
  expectCode(() => verify(fixture(entries)), "ZIP_RESOURCE_LIMIT");
});

test("individual decompressed size accepts the exact limit and rejects one byte over", () => {
  const maxEntryBytes = 16 * 1024 * 1024;
  const accepted = fixture([{
    name: "commit.txt",
    data: Buffer.alloc(maxEntryBytes, 0x61),
    flags: 0x0800,
  }]);
  assert.equal(verify(accepted).files.get("commit.txt").length, maxEntryBytes);

  const rejected = fixture([{
    name: "commit.txt",
    flags: 0x0800,
    localUncompressedSize: maxEntryBytes + 1,
    centralUncompressedSize: maxEntryBytes + 1,
  }]);
  expectCode(() => verify(rejected), "ZIP_RESOURCE_LIMIT");
});

test("aggregate decompressed size accepts 64 MiB and rejects one byte over", () => {
  const maxEntryBytes = 16 * 1024 * 1024;
  const data = Buffer.alloc(maxEntryBytes, 0x62);
  const acceptedEntries = Array.from({ length: 4 }, (_, index) => ({
    name: "member-" + index + ".txt",
    data,
    flags: 0x0800,
  }));
  const accepted = verify(fixture(acceptedEntries));
  assert.equal([...accepted.files.values()].reduce((sum, value) => sum + value.length, 0),
    64 * 1024 * 1024);

  const rejectedEntries = Array.from({ length: 5 }, (_, index) => {
    const claimedSize = index < 4 ? maxEntryBytes : 1;
    return {
      name: "member-" + index + ".txt",
      flags: 0x0800,
      localUncompressedSize: claimedSize,
      centralUncompressedSize: claimedSize,
    };
  });
  expectCode(() => verify(fixture(rejectedEntries)), "ZIP_RESOURCE_LIMIT");
});

test("archive size one byte above the configured maximum is rejected", () => {
  const value = fixture();
  value.bytes = Buffer.alloc(MAX_ARCHIVE_BYTES + 1);
  reseal(value);
  expectCode(() => verify(value), "ZIP_RESOURCE_LIMIT");
});

test("artifact metadata identity, digest and byte-size mismatches fail closed", () => {
  const value = fixture();
  value.expected.artifactId++;
  assert.throws(() => verify(value));
  const next = fixture();
  next.artifact.digest = "sha256:" + "0".repeat(64);
  assert.throws(() => verify(next));
  const sized = fixture();
  sized.artifact.size_in_bytes++;
  assert.throws(() => verify(sized));
});

test("extractor publishes verified files with private directory and file modes", () => {
  const archive = verify(fixture());
  const parent = mkdtempSync(join(tmpdir(), "deedlight-safe-extract-"));
  const destination = join(parent, "artifact");
  try {
    assert.deepEqual(
      extractVerifiedArtifactFiles(destination, archive.files),
      [...expectedMembers].sort(),
    );
    assert.deepEqual(
      verifyExtractedArtifactDirectory(destination, archive.files),
      [...expectedMembers].sort(),
    );
    assert.equal(statSync(destination).mode & 0o777, 0o700);
    assert.equal(statSync(join(destination, "commit.txt")).mode & 0o777, 0o600);
    assert.throws(() => extractVerifiedArtifactFiles(destination, archive.files),
      /Refusing to overwrite/);
  } finally {
    rmSync(parent, { recursive: true, force: true });
  }
});

test("extractor removes private staging output after a partial filesystem failure", () => {
  const parent = mkdtempSync(join(tmpdir(), "deedlight-extract-cleanup-"));
  const destination = join(parent, "artifact");
  try {
    const invalidTree = new Map([
      ["a", Buffer.from("file first")],
      ["a/b.txt", Buffer.from("nested after file")],
    ]);
    assert.throws(() => extractVerifiedArtifactFiles(destination, invalidTree),
      (error) => error instanceof ArtifactIntegrityError && error.code === "EXTRACTION_PARENT_UNSAFE");
    assert.equal(readdirSync(parent).length, 0);
    assert.throws(() => lstatSync(destination), { code: "ENOENT" });
  } finally {
    rmSync(parent, { recursive: true, force: true });
  }
});

test("extractor refuses a pre-existing symlink destination without following it", () => {
  const parent = mkdtempSync(join(tmpdir(), "deedlight-extract-link-"));
  const outside = join(parent, "outside");
  const destination = join(parent, "artifact");
  try {
    mkdirSync(outside);
    symlinkSync(outside, destination);
    expectCode(() => extractVerifiedArtifactFiles(destination,
      new Map([["file.txt", Buffer.from("safe")]])), "EXTRACTION_DESTINATION_EXISTS");
    assert.equal(readdirSync(outside).length, 0);
  } finally {
    rmSync(parent, { recursive: true, force: true });
  }
});

const originalFetch = globalThis.fetch;

test("downloader follows approved redirects without forwarding bearer credentials", async () => {
  const calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push({
      url: String(url),
      authorization: new Headers(options.headers).get("authorization"),
      redirect: options.redirect,
    });
    if (calls.length === 1) {
      return new Response(null, {
        status: 302,
        headers: { location: "https://productionresultssa0.blob.core.windows.net/container/archive.zip" },
      });
    }
    return new Response(Buffer.from("zip"), {
      status: 200,
      headers: { "content-type": "application/zip", "content-length": "3" },
    });
  };
  try {
    const bytes = await downloadArtifactArchive({
      repository,
      artifactId: 77,
      token: "test-token",
      maxBytes: 8,
    });
    assert.equal(bytes.toString(), "zip");
    assert.equal(calls.length, 2);
    assert.equal(calls[0].authorization, "Bearer test-token");
    assert.equal(calls[1].authorization, null);
    assert.ok(calls.every((call) => call.redirect === "manual"));
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("downloader cancels a rejected response body before failing", async () => {
  let cancelled = false;
  globalThis.fetch = async () => new Response(new ReadableStream({
    start(controller) {
      controller.enqueue(new Uint8Array([1]));
    },
    cancel() {
      cancelled = true;
    },
  }), {
    status: 200,
    headers: { "content-type": "text/html" },
  });
  try {
    await assert.rejects(downloadArtifactArchive({
      repository,
      artifactId: 77,
      token: "test-token",
    }), (error) => error instanceof ArtifactIntegrityError
      && error.code === "ARTIFACT_DOWNLOAD_CONTENT_TYPE");
    assert.equal(cancelled, true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("downloader rejects unapproved redirect hosts before making a second request", async () => {
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    return new Response(null, {
      status: 302,
      headers: { location: "https://attacker.example/collect" },
    });
  };
  try {
    await assert.rejects(downloadArtifactArchive({
      repository,
      artifactId: 77,
      token: "test-token",
      maxBytes: 8,
    }), (error) => error instanceof ArtifactIntegrityError
      && error.code === "ARTIFACT_REDIRECT_HOST_REJECTED");
    assert.equal(calls, 1);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("downloader cancels a stream immediately when the byte limit is exceeded", async () => {
  let cancelled = false;
  globalThis.fetch = async () => new Response(new ReadableStream({
    start(controller) {
      controller.enqueue(new Uint8Array([1, 2, 3, 4]));
    },
    cancel() {
      cancelled = true;
    },
  }));
  try {
    await assert.rejects(downloadArtifactArchive({
      repository,
      artifactId: 77,
      token: "test-token",
      maxBytes: 3,
    }), (error) => error instanceof ArtifactIntegrityError
      && error.code === "ARTIFACT_DOWNLOAD_SIZE_LIMIT");
    assert.equal(cancelled, true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("downloader propagates caller cancellation", async () => {
  const controller = new AbortController();
  controller.abort();
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    throw new Error("fetch should not start");
  };
  try {
    await assert.rejects(downloadArtifactArchive({
      repository,
      artifactId: 77,
      token: "test-token",
      signal: controller.signal,
    }), (error) => error instanceof ArtifactIntegrityError
      && error.code === "ARTIFACT_DOWNLOAD_ABORTED");
    assert.equal(calls, 0);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("downloader aborts an in-flight request at its configured deadline", async () => {
  let requestSignal;
  globalThis.fetch = async (_url, options) => new Promise((_resolve, reject) => {
    requestSignal = options.signal;
    options.signal.addEventListener("abort", () => reject(options.signal.reason), { once: true });
  });
  try {
    await assert.rejects(downloadArtifactArchive({
      repository,
      artifactId: 77,
      token: "test-token",
      timeoutMs: 1000,
    }), (error) => error instanceof ArtifactIntegrityError
      && error.code === "ARTIFACT_DOWNLOAD_ABORTED");
    assert.equal(requestSignal.aborted, true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("downloader rejects redirects that contain embedded credentials", async () => {
  globalThis.fetch = async () => new Response(null, {
    status: 302,
    headers: { location: "https://user:pass@productionresultssa0.blob.core.windows.net/archive.zip" },
  });
  try {
    await assert.rejects(downloadArtifactArchive({
      repository,
      artifactId: 77,
      token: "test-token",
    }), (error) => error instanceof ArtifactIntegrityError
      && error.code === "ARTIFACT_REDIRECT_HOST_REJECTED");
  } finally {
    globalThis.fetch = originalFetch;
  }
});
