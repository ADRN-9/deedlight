# DeedLight C575 — Backfill execution evidence model

**Disposition:** Evidence record model and fail-closed structural verifier implemented. No Production execution record accepted. No Production mutation performed.

## 1. Independent starting-point verification

Repository: `ADRN-9/deedlight`.

- PR #29: OPEN, UNMERGED. Head `2133cee1439287399740bf9794bbb0b4e793105c`; base `0e5bf38f1fdd67300825ecdf29555aa1ff3674b7`.
- PR #30: OPEN, UNMERGED. Head `0c551b48315249bcd64872ec35952ee8853ba524`; base `98cb712a890b8809ac309727264927e9b4d7cc36`.
- C573 architecture commit: `98cb712a890b8809ac309727264927e9b4d7cc36`.
- C574 commit: `56d6ceeb19bc7fe70044c2f60a6f73b180eb5ce3`.
- PR #30 head is one commit ahead of C574 commit, zero behind; C574 ancestry is preserved.
- PR #29 is untouched.

C574 final PR Validation run **46044093603**, run #2154, completed **SUCCESS** with all 12 jobs successful. This includes C574 source map verification, C574 literal regressions, analyzer adversarial tests, evidence collector and adapter tests, package integrity tests, PostgreSQL database behavior jobs, TypeScript, Next.js build, Cloudflare package and dependency audit. This evidence applies to the C574/PR #30 head `0c551b48315249bcd64872ec35952ee8853ba524`, not to C575.

## 2. C574 evidence preservation

At C575 start, the C574 map and migration inventory were fetched again:

- Inventory blob: `4e63f31368d446e905f4f44565be73337c7188fb`.
- Inventory entries: 40.
- Unique versions: 39.
- C574 map entries: 40.
- Distinct Migration 007 entries: 2.
- Migration 039 retained.
- C574 map blob: `bec7bb2e0be7ced406a48b0c3e406210c9eae797`.
- SQL NULL, quoted-empty and literal backslash-N distinctions retained.
- `catalog_only_v1` unchanged.
- All five non-catalog lifecycle domains remain UNKNOWN and NOT_ACCEPTED.

No migration inventory, migration source, historical migration order, or C574 mapping file is changed by C575.

## 3. Existing implementation gap established by source inspection

The existing category-specific backfill measurement contract in `scripts/migration-effect-contracts.mjs` requires a row count, query digest, evidence digest, timestamp, execution ID and source blob SHA-1. It does not bind an execution record to a database identity/environment, pre-execution state, post-execution state, actual database execution observation, independent verifier identity/version, independent authorization, or a durable replay registry.

The analyzer's `validateIndependentEffectEvidence` compares normalized measurement rows to the signed mapping, but its backfill evidence row has the same limited fields. The analyzer already keeps all non-catalog categories behind semantic-verification blockers, so no backfill category can establish semantic acceptance through this limited record alone. C575 does not weaken or bypass that boundary.

The collector-to-analyzer adapter emits empty `backfillMeasurements` and has explicit blockers explaining that catalog projections do not attest backfills. The current read-only collector is not an execution audit collector and cannot retrospectively prove historical execution.

## 4. C575 implementation

### New artifacts

- `scripts/backfill-execution-evidence.mjs` — exact-field structural validator, source/database binding, digest checks, Ed25519 verifier and approver artifact verification, time ordering, separation of duties, audit-observation consistency, replay-collision checks and explicit NOT_ACCEPTED blockers.
- `schemas/backfill-execution-evidence-v1.schema.json` — strict JSON Schema record envelope.
- `scripts/test-backfill-execution-evidence.mjs` — 18 Node adversarial regression cases.
- `package.json` — `test:backfill-execution-evidence` command.
- `.github/workflows/pr-validation.yml` — executes the C575 adversarial suite.

### Record fields bound by the model

| Required fact | Record field / check |
|---|---|
| Exact migration source identity | Path, version, Git blob SHA-1, raw source SHA-256, source line range, statement SHA-256 |
| Unique execution identity | UUID execution ID, record UUID, attempt, transaction ID |
| Database/environment identity | Project ref, environment, database name, server identity, server version; compared with independently pinned caller context |
| Execution time | Strict UTC start/completion timestamps |
| Pre-execution state | Independent query digest, observer identity, observed rows and row digest |
| Actual execution outcome | Execution outcome and a separately observed database audit row bound to source, execution, database, transaction and command |
| Post-execution state | Independent query digest, observer identity, observed rows and row digest |
| Verification | Ed25519 verifier artifact, verifier identity/version, outcome and exact evidence digests |
| Independent authorization | Ed25519 approver artifact bound to exact source, execution, database and environment; approval must predate execution |
| Provenance/integrity | Collector identity/version, capture time, raw evidence bundle digest and canonical signed payload |
| Replay check | Database-scoped registry collision check for execution and record IDs |

The validator compares exact source bytes to the pinned inventory entry and checks the source statement digest for the selected line range. A migration version alone cannot identify a source file; the two Migration 007 sources remain separate.

Pre/post observations preserve JSON null, empty strings and literal backslash-N as distinct values.

### Acceptance behavior

The validator returns `structuralValidation: PASS` only when the supplied fixture/record passes its shape, source, database, chronology, digest, trust-signature and collision checks. It always returns `acceptance: NOT_ACCEPTED`.

It always reports the remaining hard blockers:

1. `DURABLE_ATOMIC_REPLAY_REGISTRY_NOT_IMPLEMENTED`
2. `MIGRATION_RECONCILIATION_ANALYZER_INTEGRATION_NOT_IMPLEMENTED`
3. `PRODUCTION_TRUST_ROOTS_NOT_PROVISIONED`

The test suite generates ephemeral Ed25519 keys for test fixtures only. No Production trust roots are provisioned. The process-level trust-root digest is captured at module load; caller-supplied trust roots must match it. A signature authenticates an attestation; it does not replace raw execution/audit rows and pre/post database observations.

The replay registry parameter is a collision-detection interface for the model, not a durable atomic uniqueness guarantee. A future acceptance integration must reserve the execution ID and record ID transactionally in a trusted database-scoped ledger and fail on replay/concurrency races.

## 5. Adversarial regression coverage

18 test cases include:

1. Structurally complete evidence remains NOT_ACCEPTED.
2. Missing execution identity.
3. Altered source bytes.
4. Wrong database/environment identity.
5. Missing pre-execution state.
6. Failed execution.
7. Partial execution.
8. Missing post-execution evidence.
9. Contradictory/tampered post-state observation.
10. Replay of an existing execution ID.
11. Missing verifier authority.
12. Invalid verifier signature.
13. Missing independent authorization.
14. Authorization issued after execution began.
15. Missing execution audit evidence.
16. SQL NULL / quoted-empty / literal backslash-N distinction.
17. Migration 007 cross-source substitution.
18. Missing authoritative replay registry.

The test fixture uses a pinned Migration 005 source range containing the source UPDATE statement as a synthetic test case. This is not a claim that this record describes an actual historical or Production execution.

## 6. Exact implementation limitations

The current implementation is deliberately a record contract and verifier, not a full acceptance pipeline.

- No database-side execution ledger exists to generate or atomically reserve unique execution IDs.
- The current Production collector only performs read-only catalog/history collection; it does not capture per-migration execution audit rows or pre/post backfill snapshots.
- There is no authenticated Production verifier or backfill approver trust root.
- The current reconciliation analyzer does not ingest this new record format.
- No PostgreSQL backfill was run by C575; source inspection and CI fixtures cannot prove historical execution.
- No actual Production pre-state, post-state, affected-row count, execution timestamp, or execution outcome was observed.
- A signed verifier declaration cannot prove correctness if the verifier's evidence collection method, authority and raw evidence provenance are not independently trusted.
- The test-supplied database pin and replay registry are fixtures, not Production identity or durable registry evidence.

Accordingly, no record is classified as accepted or as successful Production execution.

## 7. C572/C574 findings retained

- **F-01, incomplete trust-failure semantic diagnostics:** NOT RESOLVED by C575. Track separately; do not infer resolution from this validator's failure output.
- **PR-triggered merge-context validation:** C574 added stacked-branch PR triggers and the C574 run passed. C575 extends the same workflow with its own test. Exact C575 merge-context CI must complete before claiming this change verified.
- C574 semantic parsing/resolution remains NOT IMPLEMENTED.
- Existing unsigned evidence rejection is not changed.
- `catalog_only_v1` and the eleven catalog-only kinds are not changed.
- The five non-catalog lifecycle domains remain NOT_ACCEPTED.

## 8. Execution and verification status

**C575 GitHub writes:** New branch `feat/c575-backfill-execution-evidence` created from PR #30 head `0c551b48315249bcd64872ec35952ee8853ba524`, preserving C574 ancestry.

**Code changes:** Model, schema, test suite, package command and PR workflow step committed on the C575 branch.

**Local execution:** NOT EXECUTED. The session has GitHub repository tools but no local repository shell/Node runtime. No local test PASS is claimed.

**Executed CI:** GitHub Actions PR Validation run **46045915417** (run #2178) completed **SUCCESS** against exact C575 head `b0796ad1a7663683c1ed5927f8f723b3b92342e0`. All 12 jobs passed. In the `validate` job, the C575 Backfill execution evidence adversarial regressions (step 16) passed, along with C574 mapping verification, analyzer adversarial tests, collector/adapter/package-integrity tests, security assertions, TypeScript, Next.js build, Cloudflare package and dependency audit. All PostgreSQL 16 behavior jobs also completed successfully. This validates the code at that exact head; the documentation update containing this CI evidence requires a fresh PR run for its own final head.

## 9. Required follow-on work

1. Implement a narrowly scoped database-side execution/audit ledger with unique constraints for record and execution IDs, database identity, source identity and attempt; make reservation atomic.
2. Instrument the actual migration runner to emit execution identity, transaction outcome, timestamps and affected-row/audit evidence without exposing credentials.
3. Capture read-only pre/post database state snapshots with pinned query bundles and exact database identity.
4. Provision independent verifier and approver trust roots through the separately reviewed security process; never accept roots supplied by the evidence package itself.
5. Bind the new record format into the analyzer's backfill category; keep NOT_ACCEPTED until durable replay, trust and raw observation checks all pass.
6. Add PostgreSQL 16 disposable database tests for audit capture, transaction failure/partial execution, replay races, cross-database substitution and snapshot consistency.
7. Resolve F-01 separately and add trust-failure diagnostic completeness assertions.
8. Re-run exact-head CI, then independently review any Production execution evidence before considering migration-history reconciliation.

## 10. Final classification

| Area | Classification |
|---|---|
| Starting repository / PR / ancestry verification | PASS |
| C574 CI final run | PASS |
| C574 40-entry preservation | PASS |
| C575 evidence model and strict schema | IMPLEMENTED |
| C575 adversarial tests | IMPLEMENTED; CI NOT ESTABLISHED |
| C575 exact-head CI | NOT ESTABLISHED |
| Actual Production backfill execution evidence | NOT ESTABLISHED |
| Durable atomic replay prevention | BLOCKED |
| Production verifier/approver trust | BLOCKED |
| Analyzer integration | BLOCKED |
| F-01 | OPEN |
| Semantic verification | NOT ESTABLISHED |
| Production readiness | NOT ESTABLISHED |

**Safety:** No Production database mutation, migration-history reconciliation, trust-root provisioning, credential exposure, PR merge, or Production activation was performed.
