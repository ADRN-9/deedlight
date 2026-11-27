# DeedLight C576 — Migration Preconditions and Postconditions

**Disposition:** Executable pre/postcondition verification added on a C575-stacked branch. It is a fail-closed verification model, not Production execution proof or a semantic-acceptance bypass. Actual database observations and Production readiness remain NOT ESTABLISHED.

## 1. Independently verified starting point

Repository: `ADRN-9/deedlight`.

| PR | Head | Base | Status |
|---|---|---|---|
| #29 | `2133cee1439287399740bf9794bbb0b4e793105c` | `0e5bf38f1fdd67300825ecdf29555aa1ff3674b7` | OPEN, unmerged |
| #30 | `0c551b48315249bcd64872ec35952ee8853ba524` | `98cb712a890b8809ac309727264927e9b4d7cc36` | OPEN, unmerged |
| #31 | `64f0daab2f8a5c75ef19431e1e888dcea04713ca` | `0c551b48315249bcd64872ec35952ee8853ba524` | OPEN, unmerged |

All three PRs were fetched independently. All are open and unmerged. PR #31 retains its intended stack on PR #30. The new C576 branch starts exactly at PR #31 head `64f0daab2f8a5c75ef19431e1e888dcea04713ca`.

C575 exact-head CI run **46046289879** (run #2180) was independently rechecked:
- Triggered for commit `64f0daab2f8a5c75ef19431e1e888dcea04713ca`.
- Overall conclusion: SUCCESS.
- 12/12 jobs successful.
- The C575 backfill evidence adversarial test step, analyzer adversarial tests, TypeScript, Next.js production build, Cloudflare packaging and PostgreSQL 16 behavior jobs all succeeded.

This CI evidence belongs to the C575 commit, not C576.

## 2. Historical evidence and preservation

At the C575 baseline:
- `supabase/migration-inventory.json` blob: `4e63f31368d446e905f4f44565be73337c7188fb`.
- 40 migration inventory entries.
- Both Migration 007 source files remain distinct:
  - `supabase/migrations/202607260007_sprint6_daily_deedlight.sql`
  - `supabase/migrations/202607260007_sprint7_pwa_daily_engagement.sql`
- Migration 039 remains present:
  `supabase/migrations/202611260039_delivery_kind_scoped_claims.sql`, blob `39eba637aa9f93fa77855f82f3fcc27b580b25da`.
- C574 map and inventory are inherited unchanged by C576.
- `catalog_only_v1` remains unchanged.
- SQL NULL, quoted-empty string and literal backslash-N remain distinct; C575 regression case remains in the shared test suite.
- No historical migration source or migration inventory entry is edited by C576.

## 3. C576 implementation

New branch: `feat/c576-migration-pre-postconditions`, based on C575 final commit.

Artifacts:
- `scripts/migration-pre-postcondition-verifier.mjs`: fail-closed condition contract and signed verification evaluator.
- `schemas/migration-pre-postcondition-contract-v1.schema.json`: strict contract schema.
- `scripts/test-backfill-execution-evidence.mjs`: expanded from 18 to 33 adversarial tests, retaining C575 cases and adding 15 C576 cases.
- `package.json`: `test:migration-pre-postconditions` command.
- `.github/workflows/pr-validation.yml`: separate C576 validation step.
- `docs/C576_MIGRATION_PRE_POSTCONDITIONS_REPORT.md`: this handover.

Implementation commit provenance:
- Verifier: `a23cf16c5a74e406f8c5c4b04cb2b2126bc5691a`.
- Verifier hardening: `6d8df597b0ddb8ea85adce08e3fe4c8d9b93a5ce`.
- Contract schema: `d793a35550b9e3b83329f4e5e30e62869f68c063`.
- Pre/post tests: `54d5494b3dfed25f08689be151fcd900f616c06d`.
- Tamper/authority tests: `6967a30235507c321f1b49006fd7027edbaae578`.
- Package command: `ff8eafaf47db85a73b14c7e05424869f875df52b`.
- CI workflow: `e5e23a6725fdd5ad2c1ebd22d9023d7d4b981a7e`.

## 4. Executable contract

A condition contract is bound to the exact C575 source identity and database identity. It requires:
- At least one explicit precondition.
- At least one explicit postcondition.
- Zero or more supported cross-state semantic relationships.
- Stable unique condition IDs.
- Explicit observation keys and expected values.

Each observation is read from a single independently observed state row, under a database identity already bound by the C575 evidence record. Supported predicates are deliberately narrow:
- `equals`
- `not_equals`

Supported cross-state relationship:
- `integer_delta_equals`

Unknown or unsupported relationship operators fail closed. This is not a generic SQL evaluator and does not infer arbitrary semantic correctness from a row count.

The condition verifier attestation binds:
- Contract digest and contract ID.
- Exact execution ID, source identity and database identity.
- Observed execution outcome.
- Exact pre- and post-state digests.
- Explicit per-condition results.
- Verifier identity and version.

The verifier signature must resolve to the independently pinned backfill-verifier role. The verifier must be distinct from the executor, approver and evidence collector, and the attestation must post-date the post-execution observation.

The C575 base record validation remains a prerequisite. A condition PASS cannot override a C575 source, audit, state-integrity, signature, trust or replay failure.

## 5. Adversarial coverage

33 tests are now in the shared test file: the original 18 C575 tests plus 15 C576 tests.

C576 additions cover:
1. Complete preconditions, postconditions and supported relationships.
2. Missing preconditions.
3. Incorrect initial state.
4. Failed migration execution.
5. Partial migration execution.
6. Unexpected postconditions.
7. Repeated execution identity.
8. Interrupted execution (missing completion timestamp).
9. Unsupported semantic relationship.
10. Forged observation with stale row digest.
11. Missing condition verifier authority.
12. Altered condition-verifier signature.
13. Verifier timestamp before post-state observation.
14. Altered observation with recomputed row digest but stale independent verification binding.
15. Unknown verifier key.

The C575 tests continue to cover missing execution identity, altered migration source, wrong database identity, missing initial/final state, failed/partial outcome, contradictory state, replay, invalid/missing verifier authority, missing authorization, Migration 007 source confusion and SQL NULL distinctions.

Test keys and database identities are ephemeral fixtures. The fixture's pre/post rows are synthetic. A test PASS proves the evaluator's behavior against supplied test evidence, not that a live database was observed.

## 6. Acceptance boundary

The C576 verifier returns:
- `verification: PASS` only when all explicit conditions, supported relationships, source/database binding, base C575 structural checks and the signed verifier attestation agree.
- `verification: FAIL` for missing, contradictory, unsupported or invalid evidence.
- `acceptance: NOT_ACCEPTED` in all cases.

Remaining inherited blockers:
1. `DURABLE_ATOMIC_REPLAY_REGISTRY_NOT_IMPLEMENTED`.
2. `MIGRATION_RECONCILIATION_ANALYZER_INTEGRATION_NOT_IMPLEMENTED`.
3. `PRODUCTION_TRUST_ROOTS_NOT_PROVISIONED`.

C576 adds an explicit Production database observation and verifier-authority blocker. It does not provision a trust root or grant semantic acceptance.

## 7. Durable replay registry and database execution ledger investigation

The C575 verifier's `replayRegistry` is a caller-supplied collision-check interface. A `status: VERIFIED` value and arrays of seen IDs are not a durable atomic uniqueness guarantee. They can race, be stale, be supplied by an untrusted caller or be scoped to the wrong database.

The current read-only evidence collector does not provide a migration-runner audit stream or durable per-backfill execution ledger. The C575 adapter intentionally does not infer backfill execution from catalog projections. No database ledger was created or changed in this cycle.

A safe future design needs a dedicated, database-local append-only execution ledger, implemented and tested first against disposable PostgreSQL:
- Database identity derived server-side from trusted DB facts (including current database, server identity/version and an independently pinned project/environment identity), never trusted solely from the submitted record.
- Unique constraints for database identity + execution ID, database identity + record ID, and the source identity + execution attempt/idempotency key as appropriate.
- An atomic reservation transaction before execution. Concurrent workers must contend on a database uniqueness constraint or locked ledger row; a preflight SELECT is not sufficient.
- A state machine such as RESERVED -> RUNNING -> SUCCEEDED / FAILED / PARTIAL / INTERRUPTED. Terminal states are immutable; expired RUNNING entries become UNKNOWN/INTERRUPTED, never assumed successful.
- Exact migration path, version, Git blob and SHA-256, command/statement digest, executor, attempt, transaction ID, timestamps and outcome recorded as immutable evidence.
- A separate transaction for reservation and finalization where required. A ledger row written only in the same transaction as the migration disappears when that migration transaction rolls back, erasing the failure evidence. The ledger design must account for that without pretending a rolled-back transaction committed.
- Read-only, separately authorized pre/post snapshot collection with query-bundle digests, transaction/snapshot identifiers, exact database identity, captured rows and integrity digests.
- An independently operated verifier signs only after checking raw observations and ledger state. The approver must be distinct and authorize exact source/database/execution scope before execution.
- Atomic acceptance/reservation of evidence record IDs and execution IDs in the trusted ledger, with replay and concurrent submission tests.
- No queue token, claim, digest, signed declaration, source inspection or caller-supplied status may substitute for database-observed outcome.

Required disposable PostgreSQL integration tests include concurrent duplicate reservation, duplicate record ID, cross-database replay, runner crash after reservation, runner crash during execution, rollback, partial/nontransactional effects, terminal-state immutability, tampered audit rows and snapshot inconsistency.

Human/security dependencies remain: trust-root design and provisioning, verifier/approver identity governance, DB privilege review, migration-runner changes, and approval of any Production rollout. None is authorized or performed by C576.

## 8. Outstanding findings and stacked CI

- **F-01 trust-failure diagnostic completeness:** OPEN / NOT RESOLVED. C576 does not claim otherwise.
- **C575 durable replay registry and DB execution ledger:** BLOCKED / NOT IMPLEMENTED.
- **Stacked-branch CI:** the PR workflow includes `feat/**` base branches, and C575's PR #31 had a successful PR-triggered run on its stacked base. C576's PR-targeted CI must still complete to prove the new stack. Do not classify the concern as fully closed until the exact C576 head has a successful run.
- Existing unsigned-evidence rejection, `catalog_only_v1`, and C574 mapping acceptance boundaries are not weakened.

## 9. Verification status

No local Node runtime was available in this session; no local test execution is claimed. CI is the validation machine.

C576 exact-head PR CI is pending until GitHub Actions reports a completed successful run for the final C576 HEAD. C575's 12/12 run is predecessor evidence only.

No Production database mutation, migration-history change, trust-root provisioning, credential exposure, PR merge or Production activation occurred.

## 10. Final classification

| Area | Classification |
|---|---|
| PR #29/#30/#31 starting-point verification | PASS |
| C575 exact-head CI run 46046289879 | PASS |
| 40-entry inventory / two Migration 007 sources / Migration 039 preservation | PASS |
| C576 verifier and strict contract schema | IMPLEMENTED |
| C576 adversarial regression coverage | IMPLEMENTED; exact-head CI pending |
| Actual independent Production pre/post observations | NOT ESTABLISHED |
| Live migration execution outcome evidence | NOT ESTABLISHED |
| Durable atomic replay prevention | BLOCKED |
| Database-side execution ledger | BLOCKED |
| Production verifier/approver trust roots | BLOCKED |
| Analyzer integration | BLOCKED |
| F-01 | OPEN |
| Stacked C576 PR CI | NOT ESTABLISHED |
| Semantic verification | NOT ESTABLISHED |
| Production readiness | NO-GO |

**Final safety disposition:** no Production mutation or activation, no migration-history reconciliation, no credential or trust-root provisioning, and no PR merge.
