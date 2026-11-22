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

Rollback is a normal fast-forward revert of the C249 commit on the existing PR #11 branch. It restores the previous runner/workflow/docs but does not touch database contents outside the ephemeral CI service. No force push or merge is required or authorized.

Production remains NO-GO.
