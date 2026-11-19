# DeedLight C146 — Release artifact integrity verification

## Source ownership and starting candidate

Repository: \`ADRN-9/deedlight\`

The C145 candidate was independently rechecked before creating C146:
- C145 branch: \`work/deedlight-c145-dependency-transport-20261118\`
- C145 commit: \`2c9bcece2b82f755578a1bce0f97adee18fdb391\`
- C145 tree: \`03959ab264f033f78dc806a83b3733b4f5033831\`
- C145 workflow: \`44455869666\`, attempt 1, successful
- C145 workflow identity: \`PR Validation\`, \`.github/workflows/pr-validation.yml\`
- C145 artifact repository ID: \`1308367373\`

The C145 branch still pointed at the reported SHA. C144 remained at \`aaa9722b8ed72577bfe5c77d6e69a4b4e12cad12\`. PR #10 and PR #11 remained open, draft and unmerged. No PR was merged or retargeted.

C146 was created as a new isolated branch from that verified C145 SHA. The C145 and C144 branches were not modified.

## Independent C145 artifact-byte baseline

All 12 artifacts from workflow run \`44455869666\` were retrieved through GitHub's artifact download endpoint. Their GitHub API metadata included artifact ID, exact name, byte size, SHA-256 digest, workflow-run ID, repository ID, head repository ID, head branch and head SHA.

For every downloaded archive:
- Actual byte count matched \`size_in_bytes\`.
- Independently calculated SHA-256 matched the API \`digest\`.
- ZIP CRC validation passed.
- Member names were unique and canonical.
- No absolute paths, traversal components, backslashes, symlinks, directories or special file modes were found.

The 11 producer archives plus the separately uploaded release-gate manifest were all checked. The output manifest artifact is not part of its own input set.

## Implementation

C146 adds:
- \`scripts/lib/release-artifact-integrity.mjs\`
- \`scripts/test-release-artifact-integrity.mjs\`

It updates:
- \`.github/workflows/pr-validation.yml\`
- \`scripts/verify-release-security-gate.mjs\`
- \`scripts/test-release-security-gate.mjs\`

### Verification rules

The canonical release gate now:
1. Retrieves the authoritative current-attempt GitHub run, jobs and artifact registry using an \`actions: read\` token.
2. Requires the canonical repository and workflow identity.
3. Requires the exact current run ID, attempt, source SHA, source tree and branch.
4. Requires the exact producer artifact names, unique positive GitHub artifact IDs, complete metadata and non-expired artifacts.
5. Binds each artifact to the workflow run, repository ID, head repository ID, branch and source commit.
6. Downloads each raw ZIP using its GitHub artifact ID.
7. Independently calculates SHA-256 and compares it with GitHub's \`sha256:\` digest and byte-size metadata.
8. Validates ZIP central-directory and local-header consistency, data descriptors, compression method, CRC, decompressed size and archive bounds.
9. Rejects ZIP64, encryption, duplicate entries, malformed names, absolute paths, traversal, backslashes, symlinks, special files, directory entries, unsupported compression, oversized members and unexpected members.
10. Requires the exact allowlisted member set for each producer job.
11. Safely extracts only verified file bytes, then compares extracted names and contents against the verified ZIP.
12. Continues the existing receipt, job, privacy, provider, consent and release-evidence checks.

The raw ZIP archives are downloaded and validated before any extraction. The workflow no longer relies on \`actions/download-artifact\` to establish the trust boundary.

The release manifest records the artifact ID, expected name, authoritative digest, independently calculated SHA-256, byte size, member names and an explicit \`archive_verified: true\` assertion.

Missing metadata, unavailable token, download failure, digest mismatch, invalid archive, unsafe member or mismatched identity stops the release gate.

## Exact-head CI acceptance

Successful implementation workflow:
- Run: \`44458082686\`
- Attempt: 1
- Commit: \`4efedc4be2a6928a12c9dfde327481669a0a213f\`
- Tree: \`e7874b94f822e6994370ea716845f8ed130e17db\`
- Branch: \`work/deedlight-c146-artifact-integrity-20261119\`

All 12 jobs succeeded, including the release security gate.

The gate reported:

\`RELEASE_SECURITY_GATE_PASS 11/11 current-attempt GitHub jobs and artifacts; 64/64 SQL, 19/19 application, provider/webhook/race contracts verified; run=44458082686 attempt=1\`

Automated integrity and release-gate tests: **65 passed, 0 failed**.

The exact-head run also preserved:
- C103 privacy evidence: 64/64 PostgreSQL assertions and 19/19 application privacy tests.
- C144 migration 034 compatibility and duplicate-prefix checks.
- C145 dependency audit and delivery-transport assertions.
- TypeScript, Next.js production build and Cloudflare packaging checks.

The first C146 CI attempt, run \`44457715631\`, correctly failed because three negative-test fixtures passed member-name strings to a ZIP fixture builder that expected objects. The fixture builder was corrected to normalize both forms. The subsequent exact-head run above passed all tests. The first run is not counted as acceptance.

## C146 actual artifact IDs and independently calculated SHA-256

All 12 artifacts from successful run \`44458082686\` were independently downloaded after the run. Local SHA-256 calculations matched GitHub's authoritative artifact metadata for all 12, and independent ZIP CRC/member-safety inspection passed.

| Artifact / job | GitHub artifact ID | Bytes | SHA-256 |
|---|---:|---:|---|
| validate | 14497664483 | 2,046 | \`ac27f7ac3687f06aa3d1d1dcdedd1312663a87f42123f184c94c55129c860053\` |
| sprint12_2_database_behavior | 14499020893 | 809 | \`4b4f161945a6a17f0005095670903221df253b2f501c432a5c8079b54476ff6a\` |
| delivery_reliability_database_behavior | 14498214119 | 815 | \`65610924424e8012eb8506f144d01efc92609603d80072a875e74cb92c222321\` |
| gentle_delivery_transport_database_behavior | 14499140350 | 819 | \`94effa503a7151867b89e8659b13e9265598112f93a0b3d0a46a89d0b5cc7965\` |
| auth_pgcrypto_database_behavior | 14497833889 | 812 | \`d4810ab2daab5d01768c3e661bef5c1b7e33a3aa25bfb73ca46df4428ef9e5e6\` |
| delivery_migration_order_database_behavior | 14499030800 | 816 | \`b73989022e348724214507c7f7f80c0ff6da88916fd7c616defc687458e472da\` |
| release_privacy_pg16 | 14499065855 | 5,879 | \`f26dd320a3ba33e3880ce4f8ea100022f8f240f52b50d87fccf8b6a0b3e9d4f4\` |
| release_action_privacy | 14498767830 | 1,892 | \`564540980c8c6712399ec5eb61d82bedb0f850d1bd9aa8bdbad04ceece987ef4\` |
| release_provider_pg16 | 14499020865 | 6,076 | \`f59b3d7b7124848f65d621c8289458eed76d343b00a65b8d4fb7f8ca3c6112ff\` |
| release_consent_races | 14498946498 | 5,186 | \`ee00814affa39e8c32615bb47b888fab780df9dde44ab0c0c44c99a81a8496eb\` |
| release_webhook_http | 14498437641 | 5,750 | \`94023cc4954555e01d828719a4d7da568d0eae0133a3623323c3546968d42fb2\` |
| release-security-gate-manifest (output) | 14498194341 | 4,153 | \`210adb76ebdc8550697845da0f7af1e9e0fa91436aabcbed7ce19489f06fbe92\` |

The output manifest artifact contains \`release-security-gate-manifest.json\` with 11 verified producer artifact records, the exact source SHA/tree, member lists and independently calculated archive hashes. Its own artifact ZIP was separately downloaded and checked against its GitHub digest.

## Nine moderate dependency advisories

C146 did not change \`package.json\` or \`package-lock.json\`. The C145 audit artifact was reviewed against the actual lockfile.

Locked versions:
- \`@opennextjs/cloudflare@1.20.17\`
- \`glob@13.0.7\`
- \`minimatch@10.2.5\`
- \`@typescript-eslint/*@8.65.0\`
- \`typescript-eslint@8.65.0\`

The nine moderate findings comprise six TypeScript ESLint package advisories, the direct OpenNext advisory, and the transitive glob and minimatch advisories.

Compatible remediation opportunities:
- The six \`@typescript-eslint\` advisories report \`fixAvailable: true\`. Their affected range ends at 8.72.2, while the lock currently resolves the v8 family at 8.65.0. A lockstep update within major v8 to a patched release (8.72.3 or later, after registry confirmation) is the compatible first remediation candidate. Validate peer ranges, ESLint, TypeScript, Next build and Cloudflare package before retaining it.
- \`glob@13.0.7\` is pulled by OpenNext's \`glob ^13.0.6\` range. GHSA-3g3m-2fjr-6pw4 affects glob versions through 14.0.1. The npm audit's suggested OpenNext remediation is \`@opennextjs/cloudflare@0.3.0\`, a major downgrade from the locked 1.20.17 line. That is not a safe compatible upgrade.
- \`minimatch@10.2.5\` is pulled through both glob and TypeScript ESLint's \`typescript-estree\`, whose dependency ranges are \`^10.2.2\`. GHSA-g3hv-75wg-m249 affects versions below 11.0.1. Forcing minimatch 11 through overrides would cross current parent semver ranges and needs a dedicated compatibility experiment.

Do not downgrade OpenNext or force major transitive overrides merely to lower the advisory count. Prefer compatible TypeScript ESLint updates now, and coordinate the glob/minimatch fixes with upstream dependency-range updates or a separately tested override proposal.

## Changed-file inventory

- \`.github/workflows/pr-validation.yml\` — use the raw-archive verifier inside the canonical release gate; remove pre-validation extraction.
- \`scripts/lib/release-artifact-integrity.mjs\` — GitHub artifact download, metadata binding, SHA-256, ZIP validation and safe extraction.
- \`scripts/test-release-artifact-integrity.mjs\` — positive and negative archive/metadata/extraction tests.
- \`scripts/verify-release-security-gate.mjs\` — enforce raw archive verification, exact archive members and manifest evidence.
- \`scripts/test-release-security-gate.mjs\` — exercise artifact ID, digest, run, repository, workflow and source mismatches against the real gate.

No historical migration file, dependency manifest, lockfile, C103 privacy assertion or C145 delivery implementation was changed.

## Blockers and release disposition

C146 did not perform Production operations:
- No Production deployment.
- No Production Supabase migration or \`supabase db push\`.
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

