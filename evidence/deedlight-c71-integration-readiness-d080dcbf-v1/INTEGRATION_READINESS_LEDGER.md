# DeedLight Cycle 71 — Integration Readiness Ledger

Assignment: DL-C71-INTEGRATION-OWNERSHIP-AND-EVIDENCE-RECOVERY-D01  
Task: d080dcbf9c064ec1a02c2013e070a734  
Date: 2026-11-14. Read-only application-source recovery and verification; **no integration or Production authority inferred**.

## 0. Administrative baseline (preserved; not incremented)

Coordinator-provided: completed 70, attempts 75, failed 5, target 1,051, remaining 981. These are not independently audited GitHub counters; do not update them from this ledger.

## 1. Authoritative repository baseline and recovered Cycle 70

- Repository: https://github.com/ADRN-9/deedlight
- `main` verified at `ce82b3fdf1a73510de70e3729a487d4ae00e66e3` (unchanged during read-only investigation).
- Cycle 70 combined CI candidate: `60301d44176186b33a812a972016751629fd792f`, branch `evidence/deedlight-c70-combined-ci-36c53dad-v1`. GitHub compare to main: **ahead 3, behind 0**, exactly three source paths: `scripts/test-gentle-delivery-transport.sql` (+46/-13), `package.json` (+3/-3), `package-lock.json` (+1324/-1948). No migration or webhook function changes in the candidate.
- Interrupted task `8106d405aed14e0ebc0c936d4bcc7c1a` **produced evidence**, so interruption did not mean no work: commit `f5e1de915d9d106579b9a5d39cada2634fc94d64`, branch `evidence/deedlight-c70-ci-expiry-8106d405-v1`, adds original SQL, a relative-clock patch, Python surrogate fixtures, logs and SHA256SUMS. Recovered work overlaps the replacement SQL fixture; **do not apply a second copy**.
- Rotated Developer Cycle 70 completion technical checkpoint: `ed6400effc8849b1660d0b5a60bcc33bf067cc27`, file `evidence/c70-dependency-candidate-36c53dad/C70-TECHNICAL-CHECKPOINT.md`, GHSA inventory same directory. Historical replacement identifier `DL-C70-ROTATED-DEVELOPER-CI-IMPLEMENTATION-D01`.

## 2. Exact-head CI evidence — CLOSED—VERIFIED, scoped to C70

- GitHub Actions https://github.com/ADRN-9/deedlight/actions/runs/43619104996
- GitHub API: run status **completed**, conclusion **success**, head `60301d44176186b33a812a972016751629fd792f`, attempt 1, 2026-11-14.
- Jobs, all conclusions `success`:
  - `132521953776` `validate`: npm ci, diff integrity, Sprint 12.1 and 12.2 security assertions, delivery reliability and gentle transport checks, auth pgcrypto assertions, JavaScript transport behavior, npm audit high/critical, `npx tsc --noEmit`, `npm run build`, `npx opennextjs-cloudflare build`. No skipped required validation steps in the job.
  - `132521954078` `gentle_delivery_transport_database_behavior`: PostgreSQL **16.16** from actual job service logs; output `{"transport_started_jobs":1,"gentle_delivery_transport_db":"pass"}`.
  - `132521954090` `delivery_reliability_database_behavior`: PostgreSQL 16.16; ledger reliability and terminal transitions PASS.
  - `132521954167` `auth_pgcrypto_database_behavior`: PostgreSQL 16.16; pgcrypto schema qualification PASS.
  - `132521954318` `sprint12_2_database_behavior`: PostgreSQL 16.16; job PASS.
- Supporting run https://github.com/ADRN-9/deedlight/actions/runs/43618358786: four PostgreSQL jobs PASS, `validate` FAIL due old dependency audit; TypeScript/Next/Cloudflare SKIPPED in that failed run. Do not conflate with the combined PASS.
- Supporting dependency run https://github.com/ADRN-9/deedlight/actions/runs/43618537821: independent npm installation, audit, security, TypeScript, Next and Cloudflare candidate evaluation PASS. Exact extracted package/lock/audit evidence published in `evidence/deedlight-c70-dependency-eval-36c53dad-v1`; evidence commit `d95191661c13074389183a22c38fbc6977bc3327`; temporary publishing workflow later removed.
- Historical failed run https://github.com/ADRN-9/deedlight/actions/runs/43606668445: at SQL line 96, `authorize_delivery_job` rejected a claim leased at 2026-10-26 while the database clock was 2026-11-14. That was correct fail-closed Production authorization behavior, not a reason to change authorization. Old dependency audit: 21 affected entries (12 moderate, 7 high, 2 critical).

### C70 SQL fixture and security scope

- Exact corrected fixture Git blob `e92c138cedef5ad7d4b2411e7c00cab7f225c5e8`.
- Uses one database transaction, UTC ISO week derived from `now()`, same `v_now` for enqueue and claim, explicitly checks live lease and idempotent start.
- Explicit stale token `00000000-0000-0000-0000-000000000000`: both authorization and transport must throw 42501. Correct token still succeeds. Deliberately expire claim: both authorization and transport must throw 42501. Repeated weekly enqueue must insert zero duplicate logical deliveries.
- Existing current consent is checked through `authorize_delivery_job` for this old migration path; the C70 change did not alter Production authorization logic. **It is not evidence that the later 025–028 event/recipient lifecycle works**.
- This fixture tests the legacy two-argument transport contract in baseline 021; PR #10 migration 024 ultimately retires that RPC. Reconcile tests **without reinstating** retired overloads.

### Dependency integrity and residual risk

- Candidate `package.json` Git blob `effbcf99326244521f87e485138a34d93691dd56`, SHA-256 `082d3a01bb0714e0ca2b4181bfe65697487c9a5f828dc08dc408876067278658`.
- Candidate `package-lock.json` Git blob `ba71390562f7eb32b88f5627a851c74494e58727`, SHA-256 `6dc03950cd14fa7a9cbe11769d7a19c2ecb06040507d8bd107e635786ad619a0`.
- Independently parsed lockfile v3: **754 packages**, root manifest equals lockfile root dependencies and devDependencies; resolved `next@16.4.6`, `zod@4.6.7`, `wrangler@4.162.0`, `@opennextjs/cloudflare@1.20.17`, `miniflare@5.20261113.0-beta`, `undici@7.30.1`, `sharp@0.35.5`, `body-parser@2.4.0`, `proxy-addr@2.0.8`, `source-map-js@1.2.2`, and integrity fields present. No npm overrides in C70 manifest.
- Real exact-head audit `npm audit --audit-level=high` PASS, but output is **9 moderate, 0 high, 0 critical**. Nine are affected entries, not nine distinct GHSA IDs:
  - `glob` and dependent `@opennextjs/cloudflare`: GHSA-3g3m-2fjr-6pw4 (post-timeout filesystem traversal after AbortSignal cancellation).
  - `minimatch` and dependent `@typescript-eslint/typescript-estree`, `@typescript-eslint/parser`, `typescript-eslint`, `@typescript-eslint/type-utils`, `@typescript-eslint/eslint-plugin`, `@typescript-eslint/utils`: GHSA-g3hv-75wg-m249 (globparts amplification denial-of-service).
- **OPEN:** test a compatible upstream fix when available. If not possible, record an explicit scoped moderate-risk decision covering CI/build-time untrusted pattern/file inputs and whether vulnerable packages are bundled at runtime. No blind `npm audit fix --force`, suppression or unsupported downgrade of OpenNext.
- Root manifest still has mutable `latest` specifiers in other dependencies; lockfile makes current npm ci repeatable, not future regenerated-lockfile behavior.

## 3. Security provenance, independently checked source identities

`f4bffa2d24f5241012b99f673eaaa39ac1dc2907` is the **authentic archival evidence** for isolated SQL migrations 025–028. Four GitHub-retrieved files were independently SHA-256 recalculated; all match:

| Proposed migration | Git blob SHA-1 | SHA-256 verified | Defines / changes |
|---|---|---|---|
| `202611130025_delivery_kind_claim_isolation.sql` | `3d57ad3762f78b15f13ce9fb8182353465f83ae3` | `93f990990b2112e1ee4f049e5d9b9495ffd4d17e43159a9bf6146953d1ae9fc9` | kind-scoped `claim_delivery_jobs(text,timestamptz,integer)`; revokes/drops unscoped claim |
| `202611130026_resend_webhook_lifecycle.sql` | `6751f3bf721f5b6e4823e71c622fdb6c8faea274` | `d1f2812f343c799e42583f57265bc967cbeab98ca5400d4206e5bddc559be137` | `delivery_provider_submissions`, `delivery_provider_events`, `delivery_recipient_suppressions`, initial webhook recorder, recipient-bound mark-sent |
| `202611130027_recipient_suppression_serialization.sql` | `12bdd42cdb551ded6de1b994a5b5096ce54341aa` | `3d30d188b867ab45e70befb5bbc2f69c5c94e594d29efb5d2758ecc7c7e1b81e` | `delivery_provider_pending_events`, `delivery_recipient_state`, redefined webhook and mark-sent, suppressed transport wrapper; revokes old 024 transport |
| `202611130028_database_authoritative_recipient_binding.sql` | `afdfc36df889dadade8c0b63ebec43fdb49e8cbb` | `d0e85b338a6b96fea5fcc8121369cd2dc20faab0cc8183ee01139a0015c0d391` | private keyring and maintenance lock, `delivery_transport_intents`, `delivery_provider_identity_conflicts`, identity-bound transport/mark-sent/webhook; revokes older wrappers |

- Source directory: https://github.com/ADRN-9/deedlight/tree/f4bffa2d24f5241012b99f673eaaa39ac1dc2907/evidence/deedlight-c68-authentic-migrations-01f441aa
- These filenames are **proposed migration numbers**, not proof they were applied or committed to a shared application branch. They are absent from checked PR #10 and main trees; PR #10 carries only 023 and 024. Do not blindly repair Supabase CLI migration history.

Cycle 61 globally keyed event-registry proposal:
- Evidence commit `80fed7f0b3e07c3c9ee0cf0fdb0675559a54b9bd`, file `evidence/cycle61-provider-event-registry/ORIGINAL_C61_PACKAGE.zip.base64.txt`, Git blob `67cb2502a93dc2369e0c60930f6c8e0b95729cb1`.
- Independently decoded the encoded ZIP and recalculated original binary SHA-256: **PASS**, `7e574ba3f8c455f30f5c18c1487fda45dcf5af1d4ae5f15f8ea4745724ea0630`, 35,836 bytes. ZIP directory has 17 entries, including `patch/PROPOSED_POST_028_provider_event_registry.sql` and `tests/postgres_fixture.sql`.
- C69 evidence reports registry SQL source SHA-256 `ed0dc53204c91b6171bc12de40929df6f54bae24e78716f0072d69593e008672`; individual uncompressed registry SQL body was not independently hashed in this Cycle 71 access path. **Registry PostgreSQL execution NOT TESTED** here.
- The registry must be the one global event identity authority across processed/pending/quarantine and must be reconciled with historical IDs before enablement. Legacy paths currently bypass its exclusivity; registry remains disabled.

Cycle 69 containment:
- Evidence commit `55fcb8f7beb4fff62a9e252455ff8f53590cbfe5`, file `patch/ADD_C69_REVIEW_ONLY_HARD_STOP.patch` in `evidence/deedlight-c69-authentic-wrapper-9b6ab5c6-v1/`.
- Independently SHA-256 checked patch: **PASS** `622f86d35114e34ad3fe65a90bf888c2a04c1cedf516e82939212082977e8864`; Git blob `57a3606dffb2f19f94922eff41e75f1bd17c2897`.
- Proposed embedded hard-stop SQL historical SHA-256 `75f63539dcc2d9cd840ab681cdcaf49dc3f97f16b2ca549f5d6d8af8eaa5dd09`, not separately recalculated from ZIP in Cycle 71.
- Protection is **stop-only**: 42501 deny-body replacements for eight legacy transport, mark-sent and webhook RPC signatures, revoke browser/service EXECUTE, ENABLE ALWAYS event-table write/TRUNCATE vetoes on processed, pending, conflict tables, registry stays disabled.
- Cycle 69 local surrogate tests reportedly passed (28 PASS / 1 SKIP; legacy suites previously passed); **authentic PostgreSQL 16 NOT TESTED**. No working authenticated webhook intake or suppressed send restoration. **DO NOT** treat as deployable completion.

## 4. Branch and pull-request source inventory

| Item | Exact head | State | Meaning |
|---|---|---|---|
| Main | `ce82b3fdf1a73510de70e3729a487d4ae00e66e3` | current | base application, older 019–022 delivery |
| PR #10 | `c983e2ed8b93c935139c935343261570ecea6978` | **open draft, unmerged**; +17 commits from main | guarded consent, 023/024, identity lease, transport wrappers and security scripts; **shared app branch, not Production** |
| PR #11 | `aed588d771dc04fda5e5c18d8611239ac926a513` | **open draft, unmerged**; +26 commits from main | 24-file metadata-only audit fixture package and CI, **not** delivery security integration |
| Historical Cycle 22 | `4a403eee5fe4fc45e3decde988dc5e488cdf3b81` | +2 from PR #10 | combines audit package with PR #10, then adds branch-specific audit CI/shell changes; **not release-ready** |
| C70 CI | `60301d44176186b33a812a972016751629fd792f` | +3 from main | old-main fixture + audited npm manifest and lock, no 023–028 migration |
| C61/C68/C69 | evidence commits above | proposal-only | not shared code and not Production schema |

### Overlap and supersession to reconcile

1. PR #10 migration `202611120023_delivery_consent_linearization.sql` changes consent-to-transport serialization; `202611120024_delivery_identity_lease_capacity.sql` then supersedes its two-arg transport by `begin_delivery_transport(uuid,uuid,text)` and drops the two-arg version.
2. 025 drops `claim_delivery_jobs(timestamptz,integer)`, introduces `claim_delivery_jobs(text,timestamptz,integer)`. PR #10's `lib/delivery/supabase-runtime.ts` still calls claim without kind; this is a concrete mandatory application change.
3. 026 adds provider event/submission/suppression stores and recipient-bound sent webhook APIs; 027 changes webhook/pending-event and suppression locking; 028 replaces reachability with identity-bound transport/sent/recorder wrappers. PR #10's `supabase-runtime.ts` still calls basic `mark_delivery_sent` and base `begin_delivery_transport`. Future integrated gateway must explicitly use only the approved identity-bound APIs and deny legacy fallback.
4. C61 global registry must supersede isolated per-table uniqueness across 026 processed, 027 pending and 028 conflicts. A registry that merely coexists is bypassable. Historical IDs require exact reconcile with collisions quarantined.
5. C69 hard stop is intentionally not a restoration path; installing it disables all transport and webhook acceptance until separately reviewed functional cutover. Never restore insecure base RPC fallback.
6. Both PR #10 and C70 edit `package.json`, `package-lock.json` and `scripts/test-gentle-delivery-transport.sql`. PR #10 manifest already includes `next@16.4.6`, `zod@4.6.7`, migration guard npm scripts, OpenNext pin and selective dependency overrides; C70 instead pins `wrangler@4.162.0` and has no overrides. **Do not wholesale replace PR #10 manifest or lock**: regenerate, audit, validate and preserve migration guards.
7. PR #10's SQL fixture is already `now()`-relative, but it exercises legacy 021 before applying later 023/024 in its consent suite. Merge C70 stale/expired negative cases into the correct test phase. Do not revive the retired two-arg RPC after 024.
8. PR #11 audit scripts are pinned to earlier source/tree and CI branch names; transplant with reviewed ref/manifest updates, preserving existing PR #11 review context. The historical Cycle 22 branch has branch-only workflow edits, making it unsuitable as an unquestioned integration base.

## 5. Ownership and historical worker incidents — BLOCKED

- Current designated Developer conversation (per coordinator-provided assignment, **not a GitHub ownership lease**): https://chatgpt.com/c/6af891dd-5c30-83ea-b35b-09af058a0fb3
- Previous context-exhausted Developer conversation: https://chatgpt.com/c/6af65a98-1d14-83ea-a9d6-c2bdfd2a317d
- Historical tasks `0159431db94e4027be73df92a95b1151` and `f57a50fc0c0b40f5a725a30449dd9c13`: coordinator reports recovered completion markers, but no authoritative exclusive-write fencing or terminal lease record is accessible in this assignment. **UNKNOWN** whether a competing writer retains rights.
- Interrupted C70 task `8106d405aed14e0ebc0c936d4bcc7c1a`: **evidence recovered and independently verified**, but its original browser-session terminal state cannot be deduced from Git commits.
- Interrupted Reviewer task `24efa58f2e554120aedb6a0f25f76ba8`: browser-observer heartbeat loss; **terminal/review result UNKNOWN**, not completed, not independently rerun.
- GitHub branch inactivity and successful CI **do not establish exclusive source ownership**.

**Required authoritative coordinator escalation:** retrieve task/session registry with last heartbeat, completion/termination and active leases for the two historical writers, interrupted C70 writer and Reviewer; revoke/fence every uncertain competing shared-source writer and prove their write capability was invalidated; issue one explicit exclusive integration-writing lease to the designated Developer, naming repo, exact integration start SHA, branch namespace, fencing epoch/lease ID, issue time and expiration, and coordinator approval. Separately resolve the Reviewer's terminal state by authoritative browser evidence without duplicate Reviewer assignment. Until the fenced lease is recorded: **BLOCKED — NO SHARED-SOURCE WRITES**.

## 6. Single recommended integration baseline

**Recommendation: Start a new, uniquely named integration branch from PR #10 exact commit `c983e2ed8b93c935139c935343261570ecea6978`, only after exclusive-writer clearance.** Do not start from main (loses consent fixes), Cycle 70 (does not include 023/024), PR #11 (audit-only) or Cycle 22 (temporary CI/branch constraints). Preserve open PR #10/#11 review history without merging them.

Proposed ordering after exclusive ownership and approved disposable environment:

1. Verify PR #10 source and tests at its exact head; retain migration project identity guards, migration order checks, SQL aggregate consistency and 023/024 consent/identity invariants.
2. Bring in only reviewed, byte-identical PR #11 audit tooling, then update branch-pinned fixture runner/CI and hashes in a dedicated diff. Use its metadata preflight against a synthetic disposable 019–024 schema; do not treat historical migration history as current Production.
3. Reconcile C70 relative-clock and stale/expired negatives into PR #10's fixture phases. Regenerate `package-lock.json` using target `next@16.4.6`, `zod@4.6.7`, `wrangler@4.162.0` and compatible OpenNext; preserve PR #10 migration guards. Compare any existing PR #10 npm overrides against actual high/critical audit; remove/rework only with demonstrated compatible resolutions and build tests.
4. Introduce authentic 025, 026, 027, 028 **in that dependency order**, with exact preflight, privileged signature, ACL, RLS and migration-number checks. Update scheduler and gateway to kind-scoped claims and recipient-identity-bound transport/mark-sent. No legacy fallback, no public email or identifiers.
5. Reconcile the C61 **global** provider event identity registry with 026/027/028 table state; keep event acceptance disabled through historical duplicate/conflict discovery. Apply C69 containment only as a reviewed **stop-only** overlay if necessary to prevent legacy bypass. Do not interpret containment as functional restored webhook delivery.
6. Separately implement authenticated Resend webhook ingress with raw-body signature/timestamp/replay checks, documented provider event classifications, durable recipient-specific bounce/complaint suppression, atomic event acceptance across processed/pending/conflict, HMAC-key rotation with current+legacy fingerprint reconciliation, suppressed-send authorization under locks, and fail-closed uncertain outcomes. Restore only the reviewed narrow privileged path after acceptance tests.
7. Re-run all tests and obtain independent Reviewer acceptance at **one exact integrated commit**; no Production activity.

## 7. Mandatory executable gates for Cycle 72 and later

- New disposable PostgreSQL **16** exact source 019–024 -> 025–028 -> disabled reconciled event registry; verify migration dependencies, signatures, object uniqueness, safe rollback, no untracked side effects, ACL/RLS and `SECURITY DEFINER` search path.
- True expired lease, exact expiry boundary, stale/reclaimed tokens, retry limit 5, retry/ambiguous provider horizon, crash recovery, stable external idempotency keys, logical unique queue, unauthorized browser RPC and direct table write negatives.
- Scheduler: Daily claims never consume Weekly queue and vice versa, both in SQL and the actual application gateway; test all allowed/unsupported kinds and malformed input.
- Current consent at final send: daily opt-in/timezone/key, weekly opt-in/confirmed email/curation, suspension, revocation after enqueue and after claim, mismatched recipient, provider suppression across key rotation; concurrent revocation must serialize with transport.
- Webhooks: invalid signatures, stale timestamps, replayed signed webhook, event ID collision across all legacy tables, pending-before-provider-ID, mismatched recipient and provider-message correlation, permanent bounce/complaint/`email.suppressed`, concurrent accept/promote/rotate/write, fail-closed malformed events. Verify revoked legacy RPC access even through definer-owned wrappers.
- Kill switch `DELIVERY_ENABLED=false` must stop outbound transport; test in isolated setup; Production proof stays a later separate gate.
- PR #10 consent concurrency/migration guards and PR #11 audit fixture matrix must pass alongside standard 5 PR Validation jobs, TypeScript, Next.js build, OpenNext/Cloudflare package and unsuppressed `npm audit --audit-level=high`.
- Human-only approvals: exclusive ownership/fencing, independently approved synthetic PostgreSQL setup, independent security Reviewer signoff, key rotation/provisioning, Production schema/migration history reconciliation, provider endpoint/secret operations and staged Production rollout. **Production NOT TESTED**.
- After all technical gates pass, only explicitly authorized rollout can prove multiple Daily cycles, real provider bounce/complaint delivery behavior, Production kill switch and safe re-enable, Weekly after Daily, authenticated regression and final Production smoke.

## 8. Cycle 71 disposition and Cycle 72 request

- **CLOSED—VERIFIED:** C70 overlap recovered; exact-head run 43619104996 SUCCESS; PG16.16 four DB jobs; matching artifact/lockfile hashes; authentic 025–028 SHA256; C61 ZIP SHA256; C69 review patch SHA256; PR #10/#11/C22/main relative ancestry.
- **OPEN:** nine moderate dependency exposures (two root advisories), functional webhook, event registry reconciliation, suppression and key-rotation design, remaining migrations, exact integrated security and CI evidence.
- **BLOCKED:** authoritative exclusive writer lease and uncertain Reviewer terminal state; Production migration-history reconciliation.
- **NOT TESTED:** authentic 025–028 + C61 + C69 PostgreSQL behavior as an integrated graph; Production services, provider, scheduler and kill switch.
- **Release disposition: MERGE NO-GO / PRODUCTION NO-GO.** PR #10/#11 remain draft. No Production mutation, email, Cron, deployment, release tag or Issue #6 closure.

**Specific Cycle 72 instruction:** Once the coordinator independently fences competing writers and issues one exact recorded exclusive lease, assign the Developer a bounded integration task starting from **`c983e2ed8b93c935139c935343261570ecea6978`**, with initial scope restricted to PR #11 audit + Cycle 70 compatibility/dependency reconciliation and precise 025–028 migration staging in a fresh branch. Require a disposable PG16 exact-head test and Reviewer security checkpoint before any merge. If ownership remains uncertain, Cycle 72 must instead resolve session leases and retain this ledger without shared-source changes.

Provenance notes: Direct authenticated GitHub connector reads, GitHub job log excerpts and independently computed SHA-256 checks; no application source was modified and no validation workflow was manually dispatched in Cycle 71. The evidence-only branch push can auto-trigger regular PR Validation on old `main` dependencies; that workflow is not a validation of C71 application integration. This ledger itself is an **evidence-only** GitHub branch file.
