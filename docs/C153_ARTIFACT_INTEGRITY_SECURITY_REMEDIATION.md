# DeedLight C155 — C153 artifact-integrity remediation follow-up

## Status and provenance

Repository: `ADRN-9/deedlight`

Dedicated branch: `work/deedlight-c153-artifact-integrity-security-20261118`

Verified base commit: `d492b473c43415c4ddcef1361b4a9331e822475c`

Verified base tree: `3a69a108f06c2a073d14d1e9ffe90c37830c1df1`

Preserved C146 implementation commit: `9f4a87c98fbb12e0c285aa4430a21aca9957c6fb`

Preserved C146 implementation tree: `b3daae4a945d3b47a3329120c891cd055320400a`

The branch is created directly from the verified C146 baseline. The C146 implementation commit `9f4a87c98fbb12e0c285aa4430a21aca9957c6fb` has verified tree `b3daae4a945d3b47a3329120c891cd055320400a`; the C153 starting head `e4afcddcf7db07b17ecb1f5e8520817e499e6308` has verified tree `82c42985b48803d86ea8ae6cf458278602c1c8de`. The base commit `d492b473c43415c4ddcef1361b4a9331e822475c` has verified tree `3a69a108f06c2a073d14d1e9ffe90c37830c1df1`. The existing C146 branch, implementation commit, main branch, PR #10 and PR #11 are not modified.

The corrected historical C149 specification and the independent C152 review artifact were not available in the repository branches, commits, issues or pull requests at the time this work was prepared. This document is a new C153 remediation specification. It is not a recovered C149 document and does not claim historical C149 acceptance.

## Acceptance principles

Each semantic negative fixture must:
- Begin with an otherwise structurally valid archive.
- Change only the metadata or bytes required to represent its target defect.
- Recalculate the GitHub artifact digest and byte-size metadata after archive mutation, so the parser—not the outer integrity check—must reject it.
- Assert the exact stable `ArtifactIntegrityError.code`.
- Retain positive fixtures for supported Stored, Deflate, descriptor, filename and extra-field cases.

The parser is intentionally narrow. It accepts Stored and Deflate only, disallows archive and member comments, disallows multi-disk and ZIP64 archives, permits only the validated Extended Timestamp extra field (`0x5455`), and requires the exact expected member set.

## Eighteen semantic negative cases

| # | Isolated defect | Required stable rejection code | Fixture isolation |
|---:|---|---|---|
| 1 | Stored method sets Deflate-only compression option bits | `ZIP_FLAGS_UNSUPPORTED` | Stored member uses an otherwise permitted EFS/descriptor combination plus only the invalid method-specific option |
| 2 | Local and central general-purpose flags differ | `ZIP_FLAGS_LOCAL_CENTRAL_MISMATCH` | Both flag values are individually permitted for Deflate; only local/central equality is broken |
| 3 | EFS is set but filename bytes are malformed UTF-8 | `ZIP_FILENAME_INVALID_UTF8` | Only the filename byte sequence is invalid; artifact digest and byte size are resealed |
| 4 | Filename contains a non-canonical traversal path | `ZIP_FILENAME_NOT_CANONICAL` | One otherwise regular member name changes to a traversal path |
| 5 | Central directory contains an unsupported extra-field ID | `ZIP_EXTRA_FIELD_UNSUPPORTED` | One well-formed extra field uses an unapproved ID |
| 6 | Local extra-field length exceeds its available payload | `ZIP_EXTRA_FIELD_MALFORMED` | One local extra-field header declares a payload longer than its containing field |
| 7 | Member-level ZIP64 uses sentinel local/central sizes and offsets, matching 64-bit local/central extra values, and a 64-bit descriptor | `ZIP64_EXTRA_NOT_SUPPORTED` | A structurally valid ZIP64 member fixture uses version 4.5, 32-bit sentinels, corresponding 64-bit sizes/offset and a signed ZIP64 descriptor; only ZIP64 support is outside policy |
| 8 | Archive-level ZIP64 EOCD and locator are present | `ZIP64_NOT_SUPPORTED` | A valid ZIP64 EOCD record and locator carry the true entry count, central size and offset; the legacy EOCD uses the required sentinel fields |
| 9 | Deflate stream leaves trailing compressed bytes unconsumed | `ZIP_DEFLATE_TRAILING_DATA` | One byte is appended to the compressed member and included in all size/digest metadata |
| 10 | Deflate stream is truncated | `ZIP_DEFLATE_INVALID` | One final compressed byte is removed and all outer size/digest metadata is resealed |
| 11 | Local-record area contains an unreferenced gap | `ZIP_LOCAL_RECORD_LAYOUT` | A byte is inserted between otherwise contiguous local records and following offsets are updated |
| 12 | Central-directory area contains unreferenced bytes | `ZIP_CENTRAL_DIRECTORY_LAYOUT` | A byte is inserted into the central-directory extent and EOCD size is updated |
| 13 | Data descriptor CRC disagrees with the central directory | `ZIP_DATA_DESCRIPTOR_MISMATCH` | Only the descriptor CRC is changed; member bytes and central CRC remain valid |
| 14 | EFS UTF-8 member name begins with a BOM | `ZIP_FILENAME_BOM_NOT_ALLOWED` | Valid UTF-8 BOM bytes are present identically in local and central filenames; archive digest and size are resealed |
| 15 | Local CRC differs from the central CRC | `ZIP_LOCAL_CENTRAL_MISMATCH` | Only the local CRC field changes; all member bytes and central metadata remain valid |
| 16 | Local compressed size differs from the central compressed size | `ZIP_LOCAL_CENTRAL_MISMATCH` | Only the local compressed-size field changes |
| 17 | Local uncompressed size differs from the central uncompressed size | `ZIP_LOCAL_CENTRAL_MISMATCH` | Only the local uncompressed-size field changes |
| 18 | Local and central modification timestamps disagree | `ZIP_EXTRA_FIELD_TIMESTAMP_MISMATCH` | Both valid 0x5455 fields contain an mtime; only the local timestamp differs |

The test fixture builder recalculates archive SHA-256 and byte-size metadata after each semantic mutation. These tests therefore do not pass merely because the archive digest or outer size is wrong.

## Positive controls

The test suite also requires:
- A valid Stored member without a descriptor.
- Valid Deflate members with signed and unsigned data descriptors.
- Valid Stored members with signed and unsigned data descriptors.
- A structurally valid ZIP64 member fixture with matching local/central ZIP64 extra values and a 64-bit descriptor, rejected specifically because ZIP64 is unsupported.
- A structurally valid ZIP64 EOCD/locator fixture, rejected specifically because ZIP64 is unsupported.
- CP437 filename decoding when EFS is clear.
- Strict UTF-8 filename decoding when EFS is set.
- A valid Extended Timestamp extra field in local and central records.
- Valid nested extraction of an expected member set.

## ZIP parser requirements

### Flags and filename interpretation

- Stored allowlist: descriptor bit 3 and EFS bit 11 only.
- Deflate allowlist: compression-option bits 1–2, descriptor bit 3 and EFS bit 11 only.
- Local and central flags, method and version-needed values must agree.
- EFS filenames are decoded using fatal UTF-8 with BOM preservation; U+FEFF is explicitly rejected as a non-canonical member-name character.
- Filenames without EFS are decoded as CP437, not silently treated as UTF-8.
- Canonical member paths reject NUL, absolute paths, drive prefixes, backslashes, empty path components, dot segments, colon segments and directory entries.

### Extra fields and ZIP64

- ZIP64 sentinels and ZIP64 extra field ID `0x0001` are rejected.
- Only Extended Timestamp ID `0x5455` is supported.
- Timestamp flag bits and exact payload length are checked. Central-directory timestamps may contain only the modification-time field; local headers may also include access and creation times. If both local and central 0x5455 fields include modification time, their Unix timestamps must match. A timestamp present in only one header is accepted; local access/creation timestamps have no central counterpart.
- Unknown, duplicate or malformed extra fields fail closed.
- Entry count, member name/extra sizes, aggregate metadata, per-member decompressed size, total decompressed size and archive size are bounded.

### Record and compression consistency

- Central-directory bounds must terminate exactly at EOCD.
- EOCD and per-member comments are rejected.
- Archive prefixes, local-record gaps, overlaps, duplicate local offsets and trailing unreferenced local bytes are rejected.
- Local and central filenames, flags, method, version, CRC and sizes are checked. CRC, compressed-size and uncompressed-size mismatches are tested independently.
- Data descriptors are validated in signed and unsigned form.
- Stored compressed and uncompressed sizes must match.
- Deflate uses zlib's `info` result and requires `engine.bytesWritten` to equal the complete compressed member length. This rejects a valid Deflate stream followed by ignored bytes.
- CRC-32 and exact decompressed byte count remain mandatory.

## Downloader boundary

The artifact downloader:
- Uses manual redirects rather than automatic redirect following.
- Starts only from the fixed GitHub artifact API URL.
- Validates HTTPS, host, port, URL credentials and fragment for each redirect.
- Allows exact GitHub artifact hosts plus the constrained GitHub Actions blob-host pattern `productionresultssa[0-9]+.blob.core.windows.net`.
- Sends the bearer token only on the first request to `api.github.com`; no redirect request receives the token, even if it redirects back to GitHub.
- Limits redirects to five.
- Applies a whole-request deadline (30 seconds by default; configurable only within 1–120 seconds).
- Supports caller cancellation.
- Enforces a streamed byte ceiling before retaining each chunk.
- Cancels failed/oversized streams and releases the reader.
- Leaves SHA-256 and provider metadata verification in `verifyArtifactArchive`, before extraction.

The blob-host allowlist is intentionally narrow. If GitHub changes its artifact redirect host, the download fails closed until the host is reviewed and added explicitly.

## Extraction boundary

Extraction:
- Requires an existing, non-symlink parent directory.
- Creates a private sibling staging directory with mode `0700`.
- Validates every member name and byte buffer before writing.
- Creates nested directories only inside the private staging root.
- Creates files with `O_CREAT | O_EXCL` and `O_NOFOLLOW` when the platform exposes it, using mode `0600`.
- Flushes file contents, verifies the complete staged file set and bytes, then publishes with a same-filesystem directory rename.
- Refuses an existing final destination.
- Removes the staging tree on every caught failure.

### Filesystem race guarantees and limits

The private staging directory, exclusive file creation, no-follow flag where available, parent-path checks and same-filesystem rename prevent archive-controlled symlink traversal and reduce races with other users.

Node's portable filesystem API does not expose Linux `renameat2(RENAME_NOREPLACE)`. There remains a narrow same-UID/concurrent-writer race between the final destination check and directory rename; an empty destination directory could be replaced by POSIX rename semantics. The extraction parent must therefore be a trusted workspace directory that is not concurrently writable by an untrusted or competing process. This implementation does not claim protection against a malicious process running as the same OS user with write access to that parent.

## Verification plan

The canonical C146 release workflow already invokes:

```sh
node --test scripts/test-release-artifact-integrity.mjs scripts/test-release-security-gate.mjs
```

C153 adds parser semantic tests, downloader redirect/cancellation/deadline tests and extraction publication/cleanup tests to the existing artifact-integrity test file. The existing release-security-gate tests remain in place.

Required evidence:
1. All 18 semantic negative tests pass with their exact rejection codes.
2. Stored, Deflate, descriptor, CP437, UTF-8 and timestamp positive controls pass.
3. Existing artifact metadata and digest tests pass.
4. Downloader redirect allowlist, bearer isolation, timeout, cancellation and byte-limit tests pass.
5. Extraction safety, mode, cleanup and no-overwrite tests pass.
6. Exact-head PR Validation workflow passes, including the release security gate.
7. Workflow run head SHA equals the implementation commit SHA.

No Production deployment, migration execution, PR merge or Production credential use is in scope.

## Independent review scope

A reviewer should independently inspect:
- Deflate termination and exact compressed-byte accounting against adversarial streams.
- ZIP flag and version allowlists against the APPNOTE method semantics.
- UTF-8 BOM preservation and U+FEFF canonical-name rejection.
- Structurally valid ZIP64 member extra fields, 64-bit descriptors, ZIP64 EOCD and locator fixtures.
- Local CRC and size mismatch isolation, and timestamp consistency semantics.
- CP437/EFS decoding and path canonicalization.
- Extended Timestamp field validation and unsupported extra-field rejection.
- EOCD/central/local record arithmetic, descriptors, overlaps and gap rejection.
- Actual GitHub Actions artifact redirect hosts observed in a successful workflow.
- Bearer-token absence on every redirected request.
- Abort propagation, request deadline and stream cancellation.
- Extraction cleanup, O_EXCL/O_NOFOLLOW behavior, atomic rename and documented same-UID race limitation.
- Whether the exact member allowlists and all release-gate consumers remain compatible with actual GitHub-generated artifact ZIPs.

## Production disposition

C153 is a CI security remediation only. Production remains NO-GO pending the project's separate migration-history, scheduler, provider, kill-switch, authenticated regression and Production smoke gates.
