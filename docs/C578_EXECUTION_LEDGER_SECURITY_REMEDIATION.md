# DeedLight C578 — Execution-ledger crash and snapshot identity remediation

**Status:** Latest documentation-inclusive PR #34 HEAD `3cc944d5ea57856af8f28343331ff3f53ea015f3` passed PR Validation run #2257 / `46056007501` with 13/13 jobs successful. The dedicated PostgreSQL 16 integration job passed and its actual decoded job log was inspected for every crash/snapshot evidence marker. Production remains NO-GO.

## 1. Baseline independently verified

- Repository: `ADRN-9/deedlight`.
- Starting PR #33 is OPEN and unmerged.
- Starting PR #33 head: `7246312a93524e0bbde10f5d27acbe36db3e5a62`.
- PR #33 base: C576 `74af17632cdf27d032058d6782d96f569ef92fca`.
- C578 branch: `feat/c578-ledger-crash-snapshot-remediation`, created from the exact PR #33 head.
- PR #34: OPEN, unmerged; base `feat/c577-durable-execution-ledger`, exact base SHA `7246312a93524e0bbde10f5d27acbe36db3e5a62`.
- PR #34 implementation head: `f3e046b464e6fc004a1b0619e8daa83d410dbaa1`.
- C577 changes remain in the parent PR; C578 is stacked on its feature branch and does not merge or modify PR #33.

## 2. Confirmed C577 crash-harness false positive

Inspected the actual PostgreSQL 16 Actions job log for C577 run #2226 / `46051047114`, job ID `140682372638`, rather than relying on the green job conclusion.

The log shows PostgreSQL rejected the crash SQL before `pg_sleep(30)`:

- Timestamp: `2026-11-27 18:40:14.136 UTC`.
- PostgreSQL reported `ERROR: invalid input syntax for type json`.
- Context showed the JSON had arrived as `{path:supabase/migrations/test-crash.sql,sha256:...}`, with JSON key/value quotes stripped by shell double-quote processing.
- The server log's statement confirms the crash transaction never reached the intended marker/sleep state.
- The old harness used a fixed `sleep 0.5`, killed a PID without proving the backend state, and treated any nonzero `wait` status as expected termination. The already-failed client therefore satisfied the weak nonzero check.
- The fixture printed a PASS line before the crash shell harness ran. The overall shell job's later PASS line did not prove that a process crash occurred, nor that effects and marker rolled back.

**Correction to C577 evidence:** run #2226 did pass its CI job, but its crash-recovery subtest was defective and did not establish real crash rollback. C577's previous crash-recovery PASS classification is withdrawn. The C578 harness below is the new test; until its actual PostgreSQL logs are inspected on a successful exact HEAD, crash recovery is NOT ESTABLISHED.

## 3. Crash-recovery harness correction

Updated `scripts/test-migration-execution-ledger-postgres16.sh`.

- Crash SQL is written with a single-quoted `<<'SQL'` heredoc. JSON literals reach PostgreSQL without shell interpolation.
- The client is launched directly as `psql` with a dedicated `PGAPPNAME=deedlight_c578_crash_test`.
- The harness verifies the exact client PID resolves to `psql`.
- A separate PostgreSQL connection polls `pg_stat_activity` for the named backend in `active` state, waiting on `PgSleep`, with a non-null `backend_xid` and query text matching `pg_sleep(30)`.
- This state is reached only after the earlier INSERT and `record_effect_commit_marker` statements have returned inside the same still-open transaction.
- The harness records the actual PostgreSQL backend PID and client PID, then sends SIGKILL to the identified client.
- It requires the client's exact wait status to be 137 (SIGKILL), not merely any nonzero status.
- It waits for the identified PostgreSQL backend PID to disappear.
- It compares migration-effect counts before and after the crash.
- It separately asserts the execution's commit-marker row count is zero.
- It asserts the separately committed reservation still exists in `running` state and the approval remains consumed.
- It runs stale recovery and requires the execution to become `unknown`.
- It attempts replay using the consumed approval and requires the expected approval-scope rejection.

The script emits explicit evidence lines:
- `C578_CRASH_BACKEND_READY`
- `C578_CRASH_CLIENT_SIGKILL`
- `C578_CRASH_ROLLBACK`
- `C578_CRASH_RECOVERY`
- `C578_CRASH_REPLAY_REJECTED`

These are test assertions and have all been observed in the actual C578 PostgreSQL 16 job log for run #2247; source inspection alone was not used as the PASS basis.

## 4. Immutable snapshot query identity and bundle digest

Updated `scripts/fixtures/migration-execution-ledger-v1.sql`.

Observation-query registry rows now bind:
- `query_id`
- SHA-256 digest of the exact registered SQL text (`query_sha256`)
- SHA-256 digest of the canonical query bundle (`query_bundle_digest`)

The bundle digest is calculated from the sorted registered query IDs and their exact SQL digests. The registry remains append-only under the existing trigger. Snapshot rows persist the query ID, query digest and bundle digest, with a composite foreign key back to the registered immutable identity.

The snapshot payload also includes `querySha256` and `queryBundleDigest`.

Finalization now requires:
- A committed same-transaction effect marker.
- A pre-snapshot and a post-snapshot for the same execution.
- Identical query IDs.
- Identical exact SQL digests.
- Identical query-bundle digests.

It fails closed when the pre/post observation identity differs.

## 5. Snapshot regression coverage

Updated `scripts/fixtures/test-migration-execution-ledger-v1.sql`.

- Existing successful lifecycle captures pre/post using the same registered query and asserts matching query ID, query digest and bundle digest.
- The fixture registers multiple queries across two distinct immutable query bundles.
- A new adversarial execution captures its pre-snapshot using `test_effects_v1` and its post-snapshot using `test_effects_v2`.
- The two query identities and bundle digests are asserted to differ.
- Finalization must raise the exact matching-query-identity rejection.
- The SQL fixture no longer prints a generic C577 PASS that could be mistaken for completion of the later crash-recovery shell test. It reports only SQL setup completion.

## 6. Preserved security boundaries

- The runner-controlled effect marker remains a transaction-coupled witness, **not independent proof that migration source executed**.
- No signature, hash or marker is treated as proof of execution or semantic acceptance.
- No C575/C576 verifier or acceptance contract is changed.
- No `catalog_only_v1` or migration-inventory change is made.
- No Production migration, Production database, migration history, trust root or credential is modified.
- PR #33 remains open and unmerged.

## 7. Outstanding Production trust findings

The following findings remain OPEN and are not resolved by disposable PostgreSQL tests:

| Finding | Classification | Disposition |
|---|---|---|
| F-01 | Trust-failure diagnostic issue | OPEN; inherited issue retained |
| F-02 | Production trust boundary | OPEN; no Production evidence supplied by C578 |
| F-04 | Production trust boundary | OPEN; no Production evidence supplied by C578 |
| F-05 | Production trust boundary | OPEN; no Production evidence supplied by C578 |

The exact underlying scope and acceptance criteria for F-02, F-04 and F-05 were not established from the starting PR's accessible artifacts during this task. They are therefore explicitly retained as unresolved findings rather than assigned invented definitions or marked resolved.

Disposable PostgreSQL CI can establish fixture behavior only. It cannot establish Production identity binding, independent DBA/verifier authority, trust-root governance, real migration-runner integration, or Production semantic acceptance.

## 8. Validation and delivery status

- Branch created from exact PR #33 head: PASS.
- Crash harness source correction: PASS in PostgreSQL 16 integration run #2247.
- Snapshot query and bundle identity enforcement: PASS in PostgreSQL 16 integration run #2247.
- Crash rollback, marker rollback, reservation survival, UNKNOWN recovery and replay rejection: PASS; all explicit C578 evidence markers are present in the actual job log.
- Matching-query successful lifecycle: PASS in PostgreSQL 16 integration run #2247.
- Mismatched-query rejection across two registered queries and two distinct bundles: PASS in PostgreSQL 16 integration run #2247.
- C575/C576 inherited regression suite: PASS in exact-head PR Validation.
- Exact C578 HEAD and PR-triggered CI: PASS, 13/13 jobs.
- PR #33: OPEN, unmerged.
- PR #34: OPEN, unmerged; mergeable at last check.

No local PostgreSQL execution is claimed. GitHub Actions was the validation machine.

## 9. Documentation-inclusive exact-head verification

The current PR #34 head `02642d9894ba291ae45c34d32881f0a261cd7ab9`, which includes this handover's CI evidence, passed PR Validation run #2249 / `46055268836` with 13/13 jobs successful. The dedicated PostgreSQL job ID `140696115895` also passed and its actual decoded log repeated all required `C578_CRASH_*` and snapshot identity evidence. PR #34 remains OPEN/unmerged and PR #33 remains OPEN/unmerged.

## 10. Exact-head CI and PostgreSQL log evidence

PR #34 is stacked on PR #33 and remains OPEN/unmerged.

- Exact tested HEAD: `f3e046b464e6fc004a1b0619e8daa83d410dbaa1`.
- PR Validation run #2247: `46054871375`, completed SUCCESS.
- All 13 workflow jobs completed SUCCESS, including `validate`, the inherited PostgreSQL behavior jobs and `migration_execution_ledger_postgres16`.
- Dedicated PostgreSQL job ID: `140694881378`, completed SUCCESS.

Actual decoded PostgreSQL job log evidence:
- `C578_SNAPSHOT_MATCHING_QUERY_PASS`
- `C578_SNAPSHOT_MISMATCH_REJECTED`
- `C578_CRASH_BACKEND_READY backend_pid=88 state=active wait_event=PgSleep xid=830 client_pid=2867 client=psql`
- `C578_CRASH_CLIENT_SIGKILL status=137 backend_pid=88`
- `C578_CRASH_BACKEND_EXITED backend_pid=88`
- `C578_CRASH_ROLLBACK effects_before=3 effects_after=3 marker_rows=0 reservation=running approval_consumed=true`
- `C578_CRASH_RECOVERY execution_id=c5700000-0000-4000-8000-000000000027 status=unknown`
- `C578_CRASH_REPLAY_REJECTED execution_id=c5700000-0000-4000-8000-000000000027`
- `C578 disposable PostgreSQL 16 execution-ledger remediation tests: PASS`

The PostgreSQL log contains one expected `approval is missing, consumed, or does not bind this execution scope` error from the replay-rejection assertion. It contains no malformed JSON error in the successful #2247 run. The earlier #2243 JSON-regex bootstrap failure and #2245 backend-wait timeout were corrected; neither is counted as a passing run.

The validate job passed migration inventory and aggregate checks, C575/C576 source/evidence regression tests, security assertions, TypeScript, Next.js production build, Cloudflare packaging and dependency advisory checks. All 13 jobs are green on the exact tested implementation HEAD.

A later documentation-only update changes the PR head; that later HEAD must receive a fresh exact-head CI run before this report's final text is considered validated.


## 11. Prior exact PR-head verification

The latest PR #34 HEAD `9fba2fbf43141771a2029c3bda4b9c683086c1fc` passed PR Validation run #2253 / `46055632225` with all 13/13 jobs successful. The dedicated PostgreSQL 16 job completed successfully and its actual decoded log again contained matching-query PASS, mismatched-query rejection, backend-ready handshake, SIGKILL status 137, backend exit, effect/marker rollback, reservation survival, UNKNOWN recovery and replay rejection. The current PR remains OPEN/unmerged; PR #33 remains OPEN/unmerged.

## 12. Final documentation-inclusive exact-head verification

The final PR #34 HEAD `3cc944d5ea57856af8f28343331ff3f53ea015f3` passed PR Validation run #2257 / `46056007501` with **13/13 jobs successful**. The dedicated PostgreSQL job ID `140698600689` passed; its actual decoded log repeated the matching-query success, mismatch rejection, backend/client identity, SIGKILL status 137, backend exit, effects and marker rollback, committed reservation survival, UNKNOWN recovery, and replay rejection evidence. The validation job and all inherited database behavior jobs also passed.

## 13. Handover and safety disposition

After pushing the final C578 branch changes, inspect the dedicated PostgreSQL job's actual decoded log. A green workflow conclusion is insufficient. Require all five `C578_CRASH_*` evidence lines, the exact wait status 137, no PostgreSQL JSON syntax error, unchanged effects count, zero marker rows, surviving committed reservation, `unknown` recovery and rejected replay. Inspect the snapshot mismatch rejection and matching-query success evidence too.

If any of these conditions are absent, classify the corresponding test as FAIL or NOT ESTABLISHED and fix it before considering the remediation complete.

**Production remains NO-GO.** No merge, Production migration, migration-history reconciliation, trust-root provisioning, credential operation, or Production activation is authorized or performed.


## C593 historical evidence reconciliation

The later C578 branch-head candidate is `eb6b1ca392563bce388819d1a5462932e340cbeb`, validated by push run #2258 / `46056320456` (13/13 jobs) and PR merge-context run #2259 / `46056326657` (13/13 jobs). PostgreSQL job `140699564456` actual decoded logs contain the matching/mismatched snapshot evidence and corrected crash handshake, SIGKILL status 137, backend exit, rollback of effects and marker, survival of the reservation/approval consumption, UNKNOWN recovery, and replay rejection. This supersedes earlier report snapshots that named an intermediate PR #34 head; it does not establish Production trust. These are historical predecessor results, not validation of C593.
