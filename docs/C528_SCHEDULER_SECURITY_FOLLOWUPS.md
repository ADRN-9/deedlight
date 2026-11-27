# C528 — Scheduler security-review follow-ups

**Repository:** `ADRN-9/deedlight`  
**PR:** [#24](https://github.com/ADRN-9/deedlight/pull/24) — OPEN / UNMERGED  
**Branch:** `feat/production-evidence-collector-e1-e2`  
**Report status:** implementation committed; exact-head CI not yet observable  
**Production:** **NO-GO**

## Changes

C528 preserves migration 039 unchanged (`39eba637aa9f93fa77855f82f3fcc27b580b25da`) and extends its existing tests and verifier.

1. **Weekly stale-token adversarial regression** — `scripts/test-delivery-kind-claims.sql` seeds an expired Weekly claim, obtains a fresh claim token, expires that lease in the disposable PostgreSQL fixture, reclaims the same row with a second fresh token, then calls `authorize_delivery_job` using the first token. The test requires SQLSTATE `42501`; if the stale token authorizes, the explicit test exception fails the suite. It does not depend on email/provider IO.
2. **Caller-controlled time rejection** — `scripts/verify-delivery-kind-claims.mjs` verifies both claim RPC signatures accept only `p_limit integer`, reject timestamp parameters, and contain PostgreSQL `clock_timestamp()` lease/scheduling decisions. It rejects lease-expiry or scheduled-time predicates using transaction-start `now()`.
3. **Coordinated rollback guidance** — `docs/C525_SCHEDULER_CLAIM_ISOLATION.md` now explains that migration 039 revokes the legacy unrestricted RPC, so deploying old application code alone is not a rollback: it would call a revoked function and fail. It explicitly prohibits restoring legacy grants and requires scheduler hold/global kill switch, compatible application/database versions, and separately reviewed forward-safe database handling.

No migration 039 content, Daily/Weekly isolation predicates, or service-role-only permissions were changed. The legacy unrestricted claim RPC was not restored or regranted. Existing verifier and PostgreSQL test wiring in `.github/workflows/pr-validation.yml` and `scripts/test-delivery-migration-order.sh` already invoke these checks; no separate workflow wiring change was necessary.

## Commit trail

All commits are on the existing PR #24 branch; no branch retargeting was attempted.

- `a7c207b6211b7de49aa508e869060696676d9d4b` — add Weekly stale-reclaim regression (initial draft).
- `68c9303bbc012666eb30d1268acec381bcad3e78` — extend claim security verifier.
- `04c6ee4a7607b81fe411b15a592ce141253722cb` — document coordinated rollback.
- `b1a9d6c4ffffe944b735facb4f83c196c9d1282d` — correct verifier regex escaping.
- `7bda22df6d9b9f116857b69aefaa82d7b87bc86c` — correct SQL output formatting.
- `481606a9acbe7fbda6559c4ef3211a65931148e2` — replace UUID max aggregate in test fixture.
- `1d521e4ec9b74870e645a50242ec32cf72f51602` — correct Weekly reclaim fixture structure.
- `44d8dff3419ea2cb82480936bd4acacdd54fa929` — compare the first freshly issued Weekly token against the second reclaim token.
- - `88282621e7855e53555c7fed450759c612c14f04` — strengthen clock checks per function.
- `b49c93003fc41804e1e942a079483601f477d7d5` — correct per-function lease verifier regexes.
- **Current PR HEAD before this report refresh:** `b49c93003fc41804e1e942a079483601f477d7d5`.

Migration 039 was independently re-fetched at this HEAD and its blob SHA remains the original value. Its 18 `clock_timestamp()` occurrences were checked against the static-verifier threshold; no lease-expiry predicate using `now()` was found. The SQL Editor aggregate still contains migration 039 verbatim.

## Validation status and blockers

- Source-level inspection confirms the Weekly test captures the first new token, forces that lease to expire, invokes the Weekly claim function again, and asserts the first token is rejected by `authorize_delivery_job`.
- Source-level inspection confirms the verifier extracts each claim function body separately and requires wall-clock checks for expiry, due-job eligibility, and five-minute lease assignment; transaction-start `now()` is rejected.
- The existing CI workflow is already wired to run `node scripts/verify-delivery-kind-claims.mjs` in `validate` and `scripts/test-delivery-kind-claims.sql` through the PostgreSQL migration-order job.
- **No exact-head workflow run ID or successful test result is available yet.** GitHub's commit-workflow-run lookup and combined-status lookup returned empty results for the current PR head when checked; both lookups returned empty results. No workflow run ID is available to report. This agent does not have a repository shell/runner, so it cannot truthfully claim local execution of Node or PostgreSQL tests. Exact-head CI remains a release blocker pending an observable workflow run.

## Unchanged external blockers

PR #23 remains the unresolved stacked dependency. No attempt was made to merge it or retarget PR #24. PR #24 remains open and unmerged. Independent PR #25 security approval, Production migration-history reconciliation, actual Production scheduler cycles, kill-switch exercise, safe re-enablement and curated Weekly operation remain outstanding.

No Production migrations, Cron activation, delivery configuration changes, provider requests or emails were performed. **Production remains NO-GO.**
