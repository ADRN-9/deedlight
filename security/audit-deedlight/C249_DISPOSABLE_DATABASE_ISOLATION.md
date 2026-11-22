# C249 — disposable PostgreSQL isolation and cleanup remediation

**Repository:** `ADRN-9/deedlight`  
**PR:** #11 — open, draft and unmerged  
**Branch:** `security/deedlight-audit-fixtures-c18`  
**Baseline HEAD:** `468f7f7e0941d11a52ec3a36478d0148f7557cd8`  
**Baseline tree:** `18af61c02089caeb39aa1a6c2b192db73eb09dfb`  
**Production:** NO-GO; no Production connection or mutation.

## Evidence recovery and original problem boundary

The live PR #11 branch, its commit history, workflow, runner, PR comments and prior exact-head run were inspected. No C249-labelled commit, issue, PR comment or historical failure record exists in the recovered repository evidence. Therefore this remediation does not invent a prior incident or claim that a particular CI run exposed these defects.

The concrete source-level weaknesses in the baseline `run_disposable_fixture.sh` were:

- Database names used only fixture case and `BASHPID`; they were not scoped to a workflow run and retry attempt.
- Output paths defaulted to `results/CASE`, so concurrent same-case invocations in one workspace could overwrite each other's logs.
- Cleanup relied only on an EXIT trap. INT, TERM and HUP were not explicitly handled.
- A boolean was set only after `createdb` returned. A signal between successful database creation and setting the flag could leave an untracked database.
- Cleanup dropped by name without checking database owner or a per-invocation marker.
- Plain `dropdb` could fail while fixture sessions remained connected.
- No final assertion proved that the workflow left zero databases from its own run.

The workflow already declared PostgreSQL as a GitHub Actions job-level service. That is a meaningful existing boundary: separate jobs have separate service containers. C249 preserves it and does not introduce shared database infrastructure. The missing safeguards were inside the job's shared service and workspace, especially for concurrent fixture processes and abnormal exits.

## Remediation

1. Pin the service image and assert the actual server version as `postgres:16.16`. The prior exact-head PostgreSQL service logs show runtime version 16.16.
2. Name each database `deedlight_audit20_RUN_ID_RUN_ATTEMPT_CASE_PID_NONCE`, with PostgreSQL's 63-byte identifier limit checked before use.
3. Pass a comment marker containing the run, attempt, case, PID and fresh nonce as the `createdb` description. If interrupted before the description is recorded, an unmarked database is eligible only when its owner is `postgres` and its complete database name exactly matches that marker identity.
4. Create a unique result directory using the same invocation identity.
5. Install EXIT, INT, TERM and HUP traps before creating the database. The former post-create boolean race is removed.
6. Before deletion, verify the database is owned by `postgres` and has the exact expected comment marker. For the interrupted-create window, an unmarked database is eligible only when its full run/attempt/case/PID/nonce name matches the expected marker identity. Unknown or mismatched resources fail closed and are not dropped.
7. Use PostgreSQL 16 `dropdb --force` only after ownership verification, then query the catalog again to prove the database is absent.
8. Add an `if: always()` run-scoped cleanup sweep. It enumerates only database names in the current run/attempt namespace, verifies each exact marker or exact unmarked-create identity, drops only those resources, and asserts that no run-owned database remains.
9. Retain job-scoped service-container teardown as the final cleanup boundary when a runner is killed or lost before shell cleanup can run.

## Executable regression coverage

`test_disposable_postgres_lifecycle.sh` runs against the isolated PostgreSQL 16.16 service before the twelve catalog fixtures. It proves:

- Two concurrent invocations of the same fixture case receive different database names and result directories; deterministic same-PID/different-nonce assertions also cover process-ID reuse.
- Cleaning one invocation does not destroy the sibling database.
- Normal process exit removes its database.
- A deliberate nonzero process exit removes its database while preserving exit status.
- TERM interruption invokes cleanup and returns the expected signal exit status.
- The final sweep removes an otherwise orphaned database from the current run.
- A mismatched owner marker is rejected; the helper does not drop the database.
- The final run-scoped database count is zero, including a database created without a comment to simulate interruption during `createdb`.

The regular runner now uses the same lifecycle helper. The active workflow and `proposed_ci.yml` remain byte-for-byte mirrors. The audit manifest is refreshed to cover the helper, regression test, updated runner/workflow and C249 documentation.

## Cleanup and cancellation limitations

Shell traps cannot execute after SIGKILL, VM loss, or abrupt runner destruction. The workflow therefore uses both per-process traps and a final `always()` cleanup step for ordinary failures/cancellations, while GitHub Actions' job-scoped service container destruction bounds any remaining resources after a hard runner loss. This does not support a shared or persistent self-hosted PostgreSQL server; the runner continues to refuse any environment other than the verified job-scoped disposable service.

The exact GitHub Actions cancellation path is not force-cancelled as part of the test run. TERM handling is exercised directly, the always-step is configured for cancellation/failure, and service teardown remains the platform fallback. This limitation is explicit rather than overstating cancellation-test coverage.

## Scope and rollback

Only PR #11 audit-fixture tooling and its documentation are changed. No migration, application runtime, dependency graph, C165 advisory work, PR #17, PR #18, Production resource, secret, deployment, Cron or outbound delivery is modified.

C249 is appended as four commits. If rollback is required, use ordinary `git revert` in reverse order: `83599a6c4fbc2dc288e737d1e867b5fb463d21ef`, `03b44f3672aa30fe1595c61b320ea46e6e913707`, `c70d812edd3053f6ae78de42d94517c74554a6ae`, then `2d6ce1aba773ef034304ce4eee8b719cf91e0d1a`. This restores the pre-C249 runner/workflow/docs while preserving all prior PR #11 history. No force push or merge is required or authorized.

Production remains NO-GO.


## Validated implementation evidence

**Implementation code head:** `83599a6c4fbc2dc288e737d1e867b5fb463d21ef`  
**Implementation tree:** `45ceb47b2576dd0df7c1b04548b325829e44c006`

- [Disposable PostgreSQL 16.16 audit run #44](https://github.com/ADRN-9/deedlight/actions/runs/44985347442) — PASS, 1/1 job; job `137094597361`.
- [Push PR Validation #809](https://github.com/ADRN-9/deedlight/actions/runs/44985347425) — PASS, 5/5 jobs.
- [PR Validation #810](https://github.com/ADRN-9/deedlight/actions/runs/44985349229) — PASS, 5/5 jobs.
- The audit job verified the SHA-256 manifest, passed Bash/parser and Python assurance tests, passed the lifecycle regression, passed all twelve fixtures A–L, completed the run-scoped cleanup assertion, archived sanitized evidence, and stopped its PostgreSQL service container.
- Sanitized artifact: `deedlight-catalog-audit-pg16`, ID `14738474877`, 44,066 bytes; expires 2026-12-06.
- The lifecycle test log contains `C249 disposable PostgreSQL lifecycle, ownership, parallel isolation and cleanup regression: PASS`.

Two earlier exact-head audit attempts were diagnostic failures and are retained in GitHub Actions history: run `44984901933` exposed a too-strict server-version string comparison; run `44985192012` exposed psql variable interpolation being incorrectly used with `-c`. The runner now checks `server_version_num=160016` and feeds variable-bearing SQL through stdin. The final run above passes.
