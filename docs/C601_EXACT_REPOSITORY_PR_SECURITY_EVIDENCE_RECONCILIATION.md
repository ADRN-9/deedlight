# C601 — Exact repository, PR and security evidence reconciliation

**Assessment date:** 2026-11-27 (America/Los_Angeles)  
**Repository:** `ADRN-9/deedlight`  
**Default branch:** `main`  
**Register:** [C601_REPOSITORY_PR_SECURITY_EVIDENCE_REGISTER.json](evidence/C601_REPOSITORY_PR_SECURITY_EVIDENCE_REGISTER.json)

## Executive disposition

The repository and current PR state were retrieved directly from GitHub. Existing C600 work was found and preserved; no duplicate C600 branch or commits were created. PR #36, #37 and #38 remain open and unmerged. No Production resources, credentials, signing keys, migration history or scheduler configuration were modified.

**C601 baseline result:** repository/PR identity, ancestry, migration-preservation comparisons and exact-head CI evidence are reconciled. Formal approval evidence and the original C599 review artifact remain missing. Production external trust is not established.

## 1. Repository and relevant refs

| Ref | Exact HEAD |
|---|---|
| `main` (default) | `d83813ba29831498846d9fa915ae210769c94e48` |
| `feat/c585-trust-diagnostics-bundle-manifest` | `ba906e7c06e1efc52dc7185c9125277e08400220` |
| `feat/c593-ledger-live-identity-manifest-trust` | `f26a7dfea5c8d1342a31952363476127d97b0607` |
| `docs/production-external-trust-binding-architecture` | `5da7cde1f1d02a47bde1575c20a32e091d051ab3` |
| `docs/c600-external-trust-findings-remediation` | `0d81fa5bd3892d3ec063c41a4275b9a60c14b30c` |

Repository ID is `1308367373`. Default branch protection is disabled; the relevant C585, C593, C598 and C600 branches also report `protected=false`. The repository rulesets endpoint returned an empty list. CI success therefore does not imply a required-review gate.

No C599 or C601 branch was present at the time of inventory. C600's branch and PR #38 were present and recovered.

## 2. PR and ancestry reconciliation

| PR | Current state | Exact head | Base | Review records |
|---|---|---|---|---|
| [#36 C593](https://github.com/ADRN-9/deedlight/pull/36) | Open, non-draft, mergeable, `clean` | `f26a7dfea5c8d1342a31952363476127d97b0607` | C585 `ba906e7c06e1efc52dc7185c9125277e08400220` | 0 reviews, 0 inline comments, 0 conversation comments |
| [#37 C598](https://github.com/ADRN-9/deedlight/pull/37) | Open, draft, mergeable, `unstable` | `5da7cde1f1d02a47bde1575c20a32e091d051ab3` | C593 `f26a7dfea5c8d1342a31952363476127d97b0607` | 0 reviews, 0 inline comments, 0 conversation comments |
| [#38 C600](https://github.com/ADRN-9/deedlight/pull/38) | Open, draft, mergeable, `clean` | `0d81fa5bd3892d3ec063c41a4275b9a60c14b30c` | C598 `5da7cde1f1d02a47bde1575c20a32e091d051ab3` | 0 reviews, 0 inline comments, 0 conversation comments |

Ancestry is confirmed by first-parent commit records: PR #36 starts at the C585 head; PR #37's sole commit has PR #36 HEAD as parent; PR #38's first commit has PR #37 HEAD as parent. These are a dependent stack, not three independent merge candidates.

PR #36's `mergeable_state=clean` is not a security approval. It targets the C585 branch, not `main`. The C593 report records that a C596 independent review recommended merge, but GitHub's current review API has no submitted approval record. This historical prose is not a formal GitHub approval. No reviewers are requested on #36 or #37, and their base branches are unprotected. PR #37 remains draft and unstable. C600's PR #38 is also draft and has no review records.

C598 and C600 documents list outstanding Security, Infrastructure, DBA/Database Security and Product/Operations approvals. C600 specifically records Security, Infrastructure, DBA and Operations as outstanding. Do not infer those approvals from CI.

## 3. C599 review artifact and F-01…F-08 reconciliation

The original C599 review artifact was not found in:
- PR #37 review submissions, inline comments or conversation comments;
- repository branches or the current open/closed PR inventory;
- the C593/C598/C600 document inventory;
- repository issue search for C599.

Therefore, the original independent review is **NOT LOCATED**. The eight F-01…F-08 labels in the C600 assignment and C600 remediation document are used as the current working checklist. This is not proof that the original C599 report has been fully recovered.

| Finding | Classification | Evidence and remaining gap |
|---|---|---|
| F-01 Gateway authorization | **PARTIAL** | C600 tests direct legacy RPC denial for an untrusted NOLOGIN role across all nine functions, with full protected ledger row equality. It does not test calls by a privileged gateway actor lacking a signed envelope. Gateway and DB-side signed wrappers are not implemented. |
| F-02 Actor separation | **NOT ESTABLISHED** | Five-way role separation is described in C600, but Production principals, grants and identity mapping are not implemented or adversarially proven. |
| F-03 Live resource identity | **PARTIAL** | C593 checks live PostgreSQL system identifier, database OID/name and server version at all nine privileged RPCs. These are database-local values; physical clones can preserve them. Provider-signed resource and endpoint identity is still design-only. |
| F-04 Verifier compromise | **NOT ESTABLISHED** | Dual independent authorization and containment are specified, not deployed or tested. |
| F-05 Generation fencing | **NOT ESTABLISHED** | Linearizable generation transitions and dispatch leases are specified; no fencing service or race test exists. |
| F-06 Workload/artifact provenance | **NOT ESTABLISHED** | Fresh provider workload evidence and verified artifact provenance are specified, not implemented. |
| F-07 Canonical request/receipt | **NOT ESTABLISHED** | Typed deterministic request encoding and signed consume receipts are proposed; no wrappers or validation tests exist. |
| F-08 Nonce rollback/audit outage | **NOT ESTABLISHED** | Consensus nonce state, independent witness and durable audit outbox are specified, not implemented. |

Physical-clone protection remains **NOT ESTABLISHED**. A disposable PostgreSQL role test is not evidence of provider identity or Production authorization.

## 4. Exact-head GitHub Actions evidence

Workflow ID `365241434`, **PR Validation**. The following branch-push and PR runs all tested the exact current head SHA reported by the corresponding PR and completed 13/13 jobs successfully.

| PR | Event | Run ID / number | Tested SHA | PostgreSQL 16 job |
|---|---|---|---|---|
| #36 | push | `46082355732` / #2353 | `f26a7dfea5c8d1342a31952363476127d97b0607` | `140783977729` |
| #36 | pull_request | `46082361933` / #2354 | same | `140783998725` |
| #37 | push | `46084795810` / #2356 | `5da7cde1f1d02a47bde1575c20a32e091d051ab3` | `140791739624` |
| #37 | pull_request | `46084820756` / #2357 | same | `140791819943` |
| #38 | push | `46086776651` / #2367 | `0d81fa5bd3892d3ec063c41a4275b9a60c14b30c` | `140798079632` |
| #38 | pull_request | `46086781316` / #2368 | same | `140798094143` |

The actual decoded PostgreSQL 16 job logs were fetched and inspected:
- PR #36 branch and PR jobs contain C593 canonical digest, C595 locale and valid-manifest nonmember, forged manifest digest, source identity immutability, live database identity fail-closed, C578 crash recovery and C585 replay-waiter/one-winner evidence.
- PR #37 branch and PR jobs contain the inherited C593/C595 identity and manifest markers plus C578/C585 runtime evidence. PR #37 itself adds only the C598 architecture document.
- PR #38 branch and PR jobs contain `C600_NINE_RPC_UNAUTHORIZED_DIRECT_CALLS_DENIED_ZERO_SIDE_EFFECTS`, plus inherited C593/C595/C578/C585 markers.

The PostgreSQL logs contain expected negative-test events, including killed crash-test client process, lock-holder cancellation and replay rejection. The harness completed successfully; these events are not treated as unexpected job failures.

Exact run pages:
- [PR #36 branch run](https://github.com/ADRN-9/deedlight/actions/runs/46082355732) · [PR run](https://github.com/ADRN-9/deedlight/actions/runs/46082361933)
- [PR #37 branch run](https://github.com/ADRN-9/deedlight/actions/runs/46084795810) · [PR run](https://github.com/ADRN-9/deedlight/actions/runs/46084820756)
- [PR #38 branch run](https://github.com/ADRN-9/deedlight/actions/runs/46086776651) · [PR run](https://github.com/ADRN-9/deedlight/actions/runs/46086781316)

Earlier successful C595/C593 candidate runs on SHA `5a075ee...` and earlier C600 attempts that failed or were cancelled are historical evidence only. They are not used as substitutes for the exact-head runs listed above.

## 5. Migration inventory and preservation

The C585 base, C593 PR #36 head, C598 PR #37 head and C600 PR #38 head each contain 40 migration SQL files. Their shared `supabase/migration-inventory.json` blob SHA is:

`4e63f31368d446e905f4f44565be73337c7188fb`

The inventory declares 40 migration source files and 39 unique versions, including one intentional duplicate-version group. Git tree comparisons were performed by path and blob SHA:
- C585 base → C593 head: zero migration file changes.
- C593 head → C598 head: zero migration file changes.
- C598 head → C600 head: zero migration file changes.

PR #36's changed-file list contains fixture SQL and reports, not historical migration files. PR #37 is documentation-only. PR #38 changes one documentation file, one disposable SQL fixture and the PostgreSQL test harness; no migration file or migration inventory is changed.

C593's report also records preservation of C575 schema/validator, C576 pre/postcondition contracts and `catalog_only_v1`. These contracts do not appear in the changed-file lists for #36/#37/#38.

**Important baseline distinction:** the default `main` branch currently has 23 migration SQL files and no `supabase/migration-inventory.json`. The 40-file inventory is inherited on the C585→C593→C598→C600 feature branch stack. It has not been merged into `main` by these PRs and must not be described as the main-branch or Production migration inventory. No migration-history reconciliation is proven by this C601 review.

## 6. Approval and Production blockers

Outstanding:
1. Attach the original C599 report, if available, and reconcile its exact wording and severity to F-01…F-08.
2. Obtain Security approval of dual-authority design, trust roots, canonical request contract and residual risk.
3. Obtain Infrastructure approval of provider workload identity, resource/endpoint identity, failover and independent trust-service deployment.
4. Obtain DBA approval of the exact nine-RPC catalog/grant inventory, role mapping, wrapper enforcement and DB-side signature verification.
5. Obtain Operations approval of fencing/drain SLO, nonce/audit outage behavior, restore and disable/re-enable runbooks.
6. Implement and adversarially test gateway signed-wrapper enforcement and actor separation before treating F-01/F-02 as closed.
7. Implement and test provider resource identity, independent verifier/policy/nonce authorities, artifact provenance, generation fencing, canonical receipt validation, anti-rollback and audit fail-closed behavior before Production trust claims.

No Production resources, credentials, signing keys, database privileges, migration history or scheduler settings were changed. No Production physical-clone protection is claimed.

## 7. Recommended C602 handoff

**C602 — Close F-01 privileged-gateway bypass and prove the database authorization boundary.**

This is the narrowest security prerequisite after C601. C600's executable test proves that an ordinary untrusted PostgreSQL role cannot execute the nine legacy RPCs. It does not yet prove that a privileged gateway actor cannot invoke those legacy functions without a valid signed envelope.

C602 should:
1. Recover/attach original C599 review; if unavailable, explicitly accept the eight assigned F-01…F-08 statements as the working specification.
2. Inventory exact signatures, owners, SECURITY DEFINER settings, grants, memberships and alternate invocation paths for all nine RPCs on disposable PostgreSQL 16.
3. Implement versioned authorization wrappers with database-side signature and claim validation; revoke direct legacy RPC EXECUTE from all runtime actor roles.
4. Enforce distinct approver, runner, observer, recovery and verifier principals with fail-closed authenticated principal mapping.
5. Attempt every legacy RPC directly as anon, authenticated, application and each gateway actor with absent, invalid, expired, replayed and mismatched authorization.
6. Assert complete protected row hashes/counts and zero external dispatch side effects for every negative case.
7. Run fresh exact-head branch and PR CI, inspect PostgreSQL logs, preserve all 40 inherited migration blobs and C575/C576 contracts, and obtain Security/DBA approval for the disposable enforcement design.

C602 must not provision Production credentials, modify Production roles, claim physical-clone protection, or merge PR #36/#37. The external provider trust architecture remains a later implementation track after the database authorization boundary is demonstrated.

## 8. Evidence register

The adjacent JSON file is the machine-readable evidence source of record for this assessment. It includes exact refs, PR states, workflow/run/job IDs, PostgreSQL marker strings, migration blob comparisons, F-01…F-08 classifications, approval dependencies and C602 acceptance criteria.


## 9. C601 documentation-branch exact-head CI reconciliation

The C601 documentation branch itself was validated after the evidence report and register were committed. This is a documentation-only PR and its CI is not evidence for the C593/C598 security implementation.

Exact C601 HEAD: `da89faceed290483ac567a34a6e2e059e9bca462` (PR #39, draft, open, unmerged; base `main` at `d83813ba29831498846d9fa915ae210769c94e48`). The branch is three commits ahead of main and changes only the two C601 evidence files.

Workflow ID `365241434`:
- Branch push run #2372 / `46094938414`: **FAIL, 2/5 jobs successful**. Jobs: `delivery_reliability_database_behavior` #`140824044022` PASS; `auth_pgcrypto_database_behavior` #`140824044241` PASS; `gentle_delivery_transport_database_behavior` #`140824044183` FAIL; `validate` #`140824044206` FAIL; `sprint12_2_database_behavior` #`140824044255` FAIL.
- PR run #2373 / `46094954115`: **FAIL, 3/5 jobs successful**. Jobs: `sprint12_2_database_behavior` #`140824077432` PASS; `auth_pgcrypto_database_behavior` #`140824077549` PASS; `delivery_reliability_database_behavior` #`140824077607` PASS; `validate` #`140824077637` FAIL; `gentle_delivery_transport_database_behavior` #`140824077647` FAIL.

Decoded failure logs were fetched and inspected:
1. Both `validate` jobs fail the high/critical dependency audit. The log reports 21 vulnerabilities (12 moderate, 7 high, 2 critical), including the three advisories already called out in the run summary: `GHSA-6pq8-jhm2-2vcw`, `GHSA-3wwx-pv8p-q78v`, and `GHSA-xjj6-f33q-929c`. The audit output includes `qs` and `undici` findings. No dependency or lockfile changes were made in C601.
2. Both `gentle_delivery_transport_database_behavior` jobs fail at `authorize_delivery_job` with `Delivery claim is not authorized`. The unchanged main-branch fixture `scripts/test-gentle-delivery-transport.sql` creates and claims the fixed `2026-10-26` delivery, while the database requires `claim_expires_at > now()`; the fixture's claim is expired on the 2026-11-28 run date. The PR log shows the exact fixed timestamps and SQL location (line 96).
3. Branch run #2372 additionally fails `sprint12_2_database_behavior` because repeated `postgres:16` Docker image-layer downloads from Docker Hub/CloudFront terminate with TCP `connection reset by peer`. The corresponding PR run succeeds, so this is recorded as an infrastructure/transient runner failure, not a source regression.

These are baseline `main` validation blockers exposed by the C601 documentation PR; they do not establish a failure in the C601 evidence content. They remain FAIL for the exact C601 head and must not be represented as passing. The C601 branch contains no code, dependency, migration or Production changes. The workflow ran only five jobs and did not run `migration_execution_ledger_postgres16`; no C601 ledger-regression claim is made from these runs.
