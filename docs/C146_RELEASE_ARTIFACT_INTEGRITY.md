# DeedLight C146 — Release artifact integrity verification

## Source ownership and starting candidate

Repository: `ADRN-9/deedlight`

The C145 candidate was independently rechecked before creating C146:
- C145 branch: `work/deedlight-c145-dependency-transport-20261118`
- C145 commit: `2c9bcece2b82f755578a1bce0f97adee18fdb391`
- C145 tree: `03959ab264f033f78dc806a83b3733b4f5033831`
- C145 workflow: `44455869666`, attempt 1, successful
- C145 workflow identity: `PR Validation`, `.github/workflows/pr-validation.yml`
- C145 artifact repository ID: `1308367373`

The C145 branch still pointed at the reported SHA. C144 remained at `aaa9722b8ed72577bfe5c77d6e69a4b4e12cad12`. PR #10 and PR #11 remained open, draft and unmerged. No PR was merged or retargeted.

C146 was created as a new isolated branch from that verified C145 SHA. The C145 and C144 branches were not modified.

## Independent C145 artifact-byte baseline

All 12 artifacts from workflow run `44455869666` were retrieved through GitHub's artifact download endpoint. Their GitHub API metadata included artifact ID, exact name, byte size, SHA-256 digest, workflow-run ID, repository ID, head repository ID, head branch and head SHA.

For every downloaded archive:
- Actual byte count matched `size_in_bytes`.
- Independently calculated SHA-256 matched the API `digest`.
- ZIP CRC validation passed.
- Member names were unique and canonical.
- No absolute paths, traversal components, backslashes, symlinks, directories or special file modes were found.

The 11 producer archives plus the separately uploaded release-gate manifest were all checked. The output manifest artifact is not part of its own input set.

## Implementation

C146 adds:
- `scripts/lib/release-artifact-integrity.mjs`
- `scripts/test-release-artifact-integrity.mjs`

It updates:
- `.github/workflows/pr-validation.yml`
- `scripts/verify-release-security-gate.mjs`
- `scripts/test-release-security-gate.mjs`

### Verification rules

The canonical release gate now:
1. Retrieves the authoritative current-attempt GitHub run, jobs and artifact registry using an `actions: read` token.
2. Requires the canonical repository and workflow identity.
3. Requires the exact current run ID, attempt, source SHA, source tree and branch.
4. Requires the exact producer artifact names, unique positive GitHub artifact IDs, complete metadata and non-expired artifacts.
5. Binds each artifact to the workflow run, repository ID, head repository ID, branch and source commit.
6. Downloads each raw ZIP using its GitHub artifact ID.
7. Independently calculates SHA-256 and compares it with GitHub's `sha256:` digest and byte-size metadata.
8. Validates ZIP central-directory and local-header consistency, data descriptors, compression method, CRC, decompressed size and archive bounds.
9. Rejects ZIP64, encryption, duplicate entries, malformed names, absolute paths, traversal, backslashes, symlinks, special files, directory entries, unsupported compression, oversized members and unexpected members.
10. Requires the exact allowlisted member set for each producer job.
11. Safely extracts only verified file bytes, then compares extracted names and contents against the verified ZIP.
12. Continues the existing receipt, job, privacy, provider, consent and release-evidence checks.

The raw ZIP archives are downloaded and validated before any extraction. The workflow no longer relies on `actions/download-artifact` to establish the trust boundary.

The release manifest records the artifact ID, expected name, authoritative digest, independently calculated SHA-256, byte size, member names and an explicit `archive_verified: true` assertion.

Missing metadata, unavailable token, download failure, digest mismatch, invalid archive, unsafe member or mismatched identity stops the release gate.

## Exact-head CI acceptance

Final squashed implementation branch and exact-head workflow:
- Run: `44458533510`
- Attempt: 1
- Commit: `9f4a87c98fbb12e0c285aa4430a21aca9957c6fb`
- Tree: `b3daae4a945d3b47a3329120c891cd055320400a`
- Branch: `work/deedlight-c146-artifact-integrity-20261119`
- Parent: verified C145 commit `2c9bcece2b82f755578a1bce0f97adee18fdb391`

The earlier implementation validation run `44458082686` also passed. The branch history was consolidated into one feature commit, and the final report/branch head received its own exact-head validation in run `44458533510`.

All 12 jobs succeeded, including the release security gate.

The gate reported:

`RELEASE_SECURITY_GATE_PASS 11/11 current-attempt GitHub jobs and artifacts; 64/64 SQL, 19/19 application, provider/webhook/race contracts verified; run=44458082686 attempt=1`

Automated integrity and release-gate tests: **65 passed, 0 failed**.

The exact-head run also preserved:
- C103 privacy evidence: 64/64 PostgreSQL assertions and 19/19 application privacy tests.
- C144 migration 034 compatibility and duplicate-prefix checks.
- C145 dependency audit and delivery-transport assertions.
- TypeScript, Next.js production build and Cloudflare packaging checks.

The first C146 CI attempt, run `44457715631`, correctly failed because three negative-test fixtures passed member-name strings to a ZIP fixture builder that expected objects. The fixture builder was corrected to normalize both forms. The subsequent exact-head run above passed all tests. The first run is not counted as acceptance.

## C146 actual artifact IDs and independently calculated SHA-256

All 12 artifacts from successful run `44458533510` were independently downloaded after the run. Local SHA-256 calculations matched GitHub's authoritative artifact metadata for all 12, and independent ZIP CRC/member-safety inspection passed.

| Artifact / job | GitHub artifact ID | Bytes | SHA-256 |
|---|---:|---:|---|
| validate | 14498273513 | 2,045 | \`a40f5cf269e4a0da888e75af27e5105e4b8ed2b1dc1c962c635d8288f5fca2aa\` |
| sprint12_2_database_behavior | 14498753828 | 807 | \`f444e9a89faf170420b86c61d521536bee6f93ca8e51e759dc7c206ec4fa30bd\` |
| delivery_reliability_database_behavior | 14499175279 | 815 | \`4585929f1b2e3b939e19589d7213c9044e46874f7f2f428b07f8a6a0fb37d31d\` |
| gentle_delivery_transport_database_behavior | 14498338452 | 818 | \`09d446b61dd33057604b5fa79d0398ebce7b0467b90783fe6e1e4c806947416c\` |
| auth_pgcrypto_database_behavior | 14498463156 | 810 | \`8d9e496cbb62193264a080a8192cba7837f92e315ae7cf47a87ce212677bc235\` |
| delivery_migration_order_database_behavior | 14499225399 | 815 | \`3a134a272d3635748b35f81f6d6ee5a2f764d2ea7821253aaba3661b1b8327b2\` |
| release_privacy_pg16 | 14498064725 | 5,879 | \`e8919eb81bbd8b91b8842c9f4aba2f2c786f7a402940658cc78819fc2689c2a7\` |
| release_action_privacy | 14499101301 | 1,883 | \`05201a6fe5a6fe7006b5d995a26e8213c8aba84ccfb05615be9c29d7840b0002\` |
| release_provider_pg16 | 14498763649 | 6,077 | \`5d47dc09fdaa566bc87f5f67e976ceced9cd1e176371af0c6352df9b63632bb4\` |
| release_consent_races | 14498843618 | 5,184 | \`deee1f68fdf69bfb14db475bbcee672eb74a80e8b8567a5cc5b5f637b057533c\` |
| release_webhook_http | 14498853733 | 5,742 | \`208247a3cef3ae98733c0092ba72e732be68d1271beb9a57393653dc8cfc7338\` |
| release-security-gate-manifest (output) | 14498743839 | 4,146 | \`fe1393040aaf9d8f315ef139f3fbd01eea7a7fc81110016a3bf5d8d102ba044b\` |

The output manifest artifact contains `release-security-gate-manifest.json` with 11 verified producer artifact records, the exact source SHA/tree, member lists and independently calculated archive hashes. Its own artifact ZIP was separately downloaded and checked against its GitHub digest.

## Nine moderate dependency advisories

C146 did not change `package.json` or `package-lock.json`. The C145 audit artifact was reviewed against the actual lockfile.

Locked versions:
- `@opennextjs/cloudflare@1.20.17`
- `glob@13.0.7`
- `minimatch@10.2.5`
- `@typescript-eslint/*@8.65.0`
- `typescript-eslint@8.65.0`

The nine moderate findings comprise six TypeScript ESLint package advisories, the direct OpenNext advisory, and the transitive glob and minimatch advisories.

Compatible remediation opportunities:
- The six `@typescript-eslint` advisories report `fixAvailable: true`. Their affected range ends at 8.72.2, while the lock currently resolves the v8 family at 8.65.0. A lockstep update within major v8 to a patched release (8.72.3 or later, after registry confirmation) is the compatible first remediation candidate. Validate peer ranges, ESLint, TypeScript, Next build and Cloudflare package before retaining it.
- `glob@13.0.7` is pulled by OpenNext's `glob ^13.0.6` range. GHSA-3g3m-2fjr-6pw4 affects glob versions through 14.0.1. The npm audit's suggested OpenNext remediation is `@opennextjs/cloudflare@0.3.0`, a major downgrade from the locked 1.20.17 line. That is not a safe compatible upgrade.
- `minimatch@10.2.5` is pulled through both glob and TypeScript ESLint's `typescript-estree`, whose dependency ranges are `^10.2.2`. GHSA-g3hv-75wg-m249 affects versions below 11.0.1. Forcing minimatch 11 through overrides would cross current parent semver ranges and needs a dedicated compatibility experiment.

Do not downgrade OpenNext or force major transitive overrides merely to lower the advisory count. Prefer compatible TypeScript ESLint updates now, and coordinate the glob/minimatch fixes with upstream dependency-range updates or a separately tested override proposal.

## Changed-file inventory

- `.github/workflows/pr-validation.yml` — use the raw-archive verifier inside the canonical release gate; remove pre-validation extraction.
- `scripts/lib/release-artifact-integrity.mjs` — GitHub artifact download, metadata binding, SHA-256, ZIP validation and safe extraction.
- `scripts/test-release-artifact-integrity.mjs` — positive and negative archive/metadata/extraction tests.
- `scripts/verify-release-security-gate.mjs` — enforce raw archive verification, exact archive members and manifest evidence.
- `scripts/test-release-security-gate.mjs` — exercise artifact ID, digest, run, repository, workflow and source mismatches against the real gate.

No historical migration file, dependency manifest, lockfile, C103 privacy assertion or C145 delivery implementation was changed.

## Blockers and release disposition

C146 did not perform Production operations:
- No Production deployment.
- No Production Supabase migration or `supabase db push`.
- No scheduler activation.
- No real provider send.
- No Production credentials used.

Production blockers remain: migration-history reconciliation, actual Production schema/PostgREST verification, staged Daily Cron operation, multiple healthy daily cycles, Production kill-switch exercise and safe re-enablement, curated Weekly Cron behavior, authenticated Production regression checks and final Production smoke.

**Production remains NO-GO.** C146 establishes artifact integrity in CI; it does not satisfy the outstanding Production rollout gates.

## Recommended C147

1. Independently review the new artifact verifier, especially ZIP parsing, metadata binding, GitHub API download permissions and archive-size limits.
2. Upgrade the TypeScript ESLint v8 family to a patched compatible release and rerun the exact-head CI suite.
3. Investigate an upstream-compatible OpenNext/glob/minimatch remediation without breaking overrides or major downgrades.
4. Continue the separately controlled Production migration-history reconciliation and staged rollout evidence.

