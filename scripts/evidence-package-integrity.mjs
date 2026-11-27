import { createHash } from "node:crypto";
import { canonicalJson, verifyReceiptAndEvidence } from "./collect-production-migration-evidence.mjs";

const KIND = "deedlight-evidence-package-integrity";
const STATUS = "UNSIGNED_INTEGRITY_ONLY_NOT_ACCEPTED";
const FILES = ["evidence.csv", "receipt.json"];

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function exactKeys(value, keys) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === keys.length
    && keys.every((key) => Object.hasOwn(value, key));
}

function bytes(value, code) {
  if (!Buffer.isBuffer(value)) throw new Error(code);
  return value;
}

function manifestPayload(evidenceBytes, receiptBytes) {
  return {
    schemaVersion: 1,
    kind: KIND,
    status: STATUS,
    files: [
      { path: FILES[0], byteLength: evidenceBytes.length, sha256: sha256(evidenceBytes) },
      { path: FILES[1], byteLength: receiptBytes.length, sha256: sha256(receiptBytes) },
    ],
  };
}

export function createEvidencePackageManifest({ receipt, evidenceBytes }) {
  bytes(evidenceBytes, "EVIDENCE_BYTES_INVALID");
  verifyReceiptAndEvidence(receipt, evidenceBytes);
  const receiptBytes = Buffer.from(canonicalJson(receipt) + "\n", "utf8");
  const payload = manifestPayload(evidenceBytes, receiptBytes);
  return { ...payload, packageSha256: sha256(Buffer.from(canonicalJson(payload), "utf8")) };
}

export function verifyEvidencePackageManifest({ manifest, receiptBytes, evidenceBytes }) {
  bytes(receiptBytes, "RECEIPT_BYTES_INVALID");
  bytes(evidenceBytes, "EVIDENCE_BYTES_INVALID");
  if (!exactKeys(manifest, ["schemaVersion", "kind", "status", "files", "packageSha256"])
    || manifest.schemaVersion !== 1 || manifest.kind !== KIND || manifest.status !== STATUS
    || !Array.isArray(manifest.files) || manifest.files.length !== 2
    || !/^[a-f0-9]{64}$/.test(manifest.packageSha256)) {
    throw new Error("PACKAGE_MANIFEST_INVALID");
  }
  const [evidenceEntry, receiptEntry] = manifest.files;
  for (const [entry, expectedPath, content] of [
    [evidenceEntry, FILES[0], evidenceBytes],
    [receiptEntry, FILES[1], receiptBytes],
  ]) {
    if (!exactKeys(entry, ["path", "byteLength", "sha256"]) || entry.path !== expectedPath
      || !Number.isSafeInteger(entry.byteLength) || entry.byteLength !== content.length
      || typeof entry.sha256 !== "string" || !/^[a-f0-9]{64}$/.test(entry.sha256)
      || sha256(content) !== entry.sha256) {
      throw new Error("PACKAGE_FILE_INTEGRITY_MISMATCH");
    }
  }
  const payload = {
    schemaVersion: manifest.schemaVersion,
    kind: manifest.kind,
    status: manifest.status,
    files: manifest.files,
  };
  if (sha256(Buffer.from(canonicalJson(payload), "utf8")) !== manifest.packageSha256) {
    throw new Error("PACKAGE_MANIFEST_DIGEST_MISMATCH");
  }
  let receipt;
  try {
    const text = receiptBytes.toString("utf8");
    if (!Buffer.from(text, "utf8").equals(receiptBytes)) throw new Error("invalid UTF-8");
    receipt = JSON.parse(text);
    if (text !== canonicalJson(receipt) + "\n") throw new Error("noncanonical receipt");
  } catch {
    throw new Error("PACKAGE_RECEIPT_INVALID");
  }
  verifyReceiptAndEvidence(receipt, evidenceBytes);
  return true;
}
