# DeedLight C578 — Execution-ledger crash and snapshot identity remediation

**Status:** Changes implemented on a stacked branch. Exact-head PostgreSQL 16 CI and PR-triggered validation are pending. No C578 test has yet been run in this session. Production remains NO-GO.

## 1. Baseline independently verified

- Repository: `ADRN-9/deedlight`.
- Starting PR #33 is OPEN and unmerged.
- Starting PR #33 head: `7246312a93524e0bbde10f5d27acbe36db3e5a62`.
- PR #33 base: C576 `74af17632cdf27d032058d6782d96f569ef92fca`.
- C578 branch: `feat/c578-ledger-crash-snapshot-remediation`, created from the exact PR #33 head.
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

These are test assertions to be proven by actual C578 PostgreSQL logs; source inspection alone is not a PASS.

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
- Crash harness source correction: IMPLEMENTED; runtime NOT ESTABLISHED.
- Snapshot query and bundle identity enforcement: IMPLEMENTED; runtime NOT ESTABLISHED.
- Crash rollback, marker rollback, reservation survival, UNKNOWN recovery and replay rejection: NOT ESTABLISHED pending C578 PostgreSQL run and actual log inspection.
- Matching-query successful lifecycle: IMPLEMENTED; runtime NOT ESTABLISHED.
- Mismatched-query rejection: IMPLEMENTED; runtime NOT ESTABLISHED.
- C575/C576 regression suite on C578 head: NOT ESTABLISHED.
- Exact C578 HEAD and PR-triggered CI: PENDING.
- PR #33: OPEN, unmerged.
- C578 remediation PR: not yet opened at time of this report.

No local PostgreSQL execution is claimed. The browser relay is not used to run commands. GitHub Actions is the intended validation machine.

## 9. Handover and safety disposition

After pushing the final C578 branch changes, inspect the dedicated PostgreSQL job's actual decoded log. A green workflow conclusion is insufficient. Require all five `C578_CRASH_*` evidence lines, the exact wait status 137, no PostgreSQL JSON syntax error, unchanged effects count, zero marker rows, surviving committed reservation, `unknown` recovery and rejected replay. Inspect the snapshot mismatch rejection and matching-query success evidence too.

If any of these conditions are absent, classify the corresponding test as FAIL or NOT ESTABLISHED and fix it before considering the remediation complete.

**Production remains NO-GO.** No merge, Production migration, migration-history reconciliation, trust-root provisioning, credential operation, or Production activation is authorized or performed.
