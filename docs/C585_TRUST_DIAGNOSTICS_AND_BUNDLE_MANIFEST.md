# DeedLight C585 — Trust diagnostics and query-bundle integrity remediation

**Status:** Implementation changes are committed on a branch created from candidate `eb6b1ca392563bce388819d1a5462932e340cbeb`. Exact-head PostgreSQL 16 CI is pending; no C585 test PASS is claimed yet. PR #33 and PR #34 remain OPEN and unmerged. Production remains NO-GO.

## Scope and preserved boundaries

- Repository: `ADRN-9/deedlight`.
- Branch: `feat/c585-trust-diagnostics-bundle-manifest`.
- Base candidate: `eb6b1ca392563bce388819d1a5462932e340cbeb`.
- Only disposable PostgreSQL fixture, fixture tests, shell CI harness and this report are changed.
- No `supabase/migrations` source or migration inventory is changed.
- Preserve C575/C576 contracts and `catalog_only_v1`.
- Hash equality is identity consistency only, not independent proof of source execution.
- No Production database, migration history, trust root or credential is touched.

## Implemented changes

### Structured trust-failure outcomes

The fixture introduces a fail-closed diagnostic helper with stable SQLSTATE values and machine-readable DETAIL JSON:

| SQLSTATE | Category |
|---|---|
| D1001 | missing_trust |
| D1002 | invalid_source_identity |
| D1003 | missing_execution_evidence |
| D1004 | snapshot_substitution |
| D1005 | replay |
| D1006 | incomplete_preconditions |
| D1007 | failed_postconditions |
| D1008 | ambiguous_execution_outcome |

Applied to observer authority, registered-query absence, SQL digest substitution, reservation replay and source mismatch, marker source mismatch, finalization evidence requirements and terminal finalization postconditions. Running stale executions are recorded as `unknown` with explicit `ambiguous_execution_outcome` / D1008 metadata. A runner-controlled marker remains transaction-coupled evidence, not independent proof of source execution.

### Immutable query-bundle manifest

- Adds `query_bundle_manifests` with immutable JSON membership, declared member count and canonical SHA-256.
- Canonical digest is computed from sorted `queryId:querySha256` members separated by LF, independent of caller-supplied digest.
- Duplicate or malformed members fail closed.
- Query registry rows reference the manifest by composite bundle ID/digest.
- Capture recomputes the exact registered SQL digest, recomputes the canonical manifest digest, validates member count and proves the requested query/digest is a member.
- Bundle manifest and query registry UPDATE/DELETE are rejected by append-only triggers.

### Adversarial regression coverage

Added `scripts/fixtures/test-migration-execution-ledger-c585.sql` and wired it into the PostgreSQL 16 CI harness. Coverage includes:
- Canonical manifest digest and membership.
- SQL digest substitution rejection.
- Bundle digest substitution rejected by composite FK.
- Manifest and query-registry UPDATE/DELETE rejection.
- Snapshot UPDATE/DELETE rejection.
- Source identity substitution at marker and reservation boundaries.
- Missing pre-snapshot and missing post-snapshot finalization rejection with distinct diagnostic details.
- Terminal finalization postcondition rejection.

The C578 snapshot-mismatch test now expects structured SQLSTATE D1004 rather than the former generic error text.

### Deterministic replay contention

The former fixed-delay race is replaced with a PostgreSQL lock-holder and two named waiters. The harness identifies the holder backend, starts both waiters, and polls `pg_blocking_pids()` until both are proven blocked by that holder. Only then does it cancel the holder transaction, releasing both waiters. It requires exactly one reservation winner and emits explicit blocking/one-winner evidence.

## Validation status

- Branch created from requested candidate: PASS.
- Source edits and fixture test wiring: IMPLEMENTED.
- PostgreSQL 16 runtime tests: PENDING.
- Exact-head PR-triggered CI: PENDING.
- Actual PostgreSQL log inspection: PENDING.
- Production readiness: NOT ESTABLISHED; NO-GO.

The CI run must demonstrate D1002 source-identity rejection at reservation and marker operations, D1004 SQL digest substitution, D1006 missing pre/post, D1007 failed postcondition, manifest immutability, and `C585_REPLAY_WAITERS_BLOCKED` with both waiters listed as blocked by the identified holder PID before release. Any SQL bootstrap failure or missing evidence marker is a failure, not a pass.

## Remaining risks and blockers

- Production trust roots, independent verifier trust and semantic execution proof remain outside disposable fixture scope.
- F-01/F-02/F-04/F-05 remain unresolved until separately evidenced.
- The fixture uses owner-level test seeding for negative cases; this does not establish Production operational-role integration.
- A successful disposable PostgreSQL run does not establish Production readiness.
- No merge, Production migration, migration-history reconciliation, delivery activation or privileged credential operation is authorized or performed.


## CI failure and correction record

Initial PR-triggered run #2285 / `46063685445` failed in PostgreSQL 16 fixture bootstrap. I inspected the actual service-container log: PostgreSQL 16.16 reported that `pg_catalog.jsonb_object_length(jsonb)` does not exist while compiling `valid_source_identity`. This was a real failure; no C585 runtime assertions were reached and no PASS is claimed from that run.

Corrected the key-count checks to use `count(*) FROM pg_catalog.jsonb_object_keys(...)` in commit `a0e92bbeb18acec1d7d6fd15561e037ad1dcd56f`. Follow-up review also hardened path traversal checks and aligned the replay assertion with SQLSTATE D1005. Latest source HEAD is `cffd28989908442abd4b328d64fe1e891760c688`.

The available GitHub workflow-run lookup has not returned a PR-triggered run for the latest commits. Therefore exact-head CI and actual PostgreSQL log verification remain PENDING. The failed #2285 run is not counted as validation success. Do not merge while this gate remains pending.


## Latest handover status

Latest implementation/test-harness commit: `f0c586335e956fa834f17e9fd4bb71144423e2f9`. This adds an explicit assertion that stale RUNNING recovery records `ambiguous_execution_outcome|D1008`.

PR #35 is OPEN and mergeable; PR #33 and PR #34 remain OPEN and UNMERGED. The migration inventory remains 40 entries with the same blob SHA `4e63f31368d446e905f4f44565be73337c7188fb`. The PR changes exactly five files and contains no `supabase/migrations` or migration-inventory changes.

The only available PR-triggered validation run is the initial run #2285 / `46063685445`, which failed during PostgreSQL 16 fixture bootstrap before C585 assertions. After that failure, the JSON key-count defect was corrected, source-path validation hardened, structured replay SQLSTATE handling updated, and ambiguous-outcome recovery assertion added. Run #2303 / `46064227579` was triggered for PR #35 and failed in PostgreSQL 16 job `140727421732` during manifest fixture bootstrap. The actual log identifies a PostgreSQL operator-precedence error in canonical digest concatenation: `value->>'queryId' || ':' || value->>'querySha256'` was parsed as applying `->>` to a text expression. No C585 adversarial assertions ran in that attempt. Corrected by parenthesizing both JSON extraction expressions in commit `fca24cabd488fe26a429b26cb4306e5e225354af`. This correction is an implementation change only; it has not yet been runtime-validated. Exact-head CI and actual PostgreSQL log inspection for the corrected head remain **PENDING / NOT ESTABLISHED**. Do not treat run #2285, run #2301 / `46064185132` (cancelled), or run #2303 as validation success.

## Follow-up after run #2303

A second instance of the same PostgreSQL operator-precedence hazard was found in the shell harness query that reads the D1008 recovery diagnostic. The concatenated JSON text extractions are now individually parenthesized in commit `0a5c218989b76b4b7b14fab9d31111f3f9f85ae0`. This prevents the evidence assertion itself from failing before it can verify `ambiguous_execution_outcome|D1008`. The corrected SQL and harness now require a fresh PR-triggered exact-head CI run; no result is claimed until PostgreSQL 16 logs are inspected.

A further static review found the missing-observer-trust negative test was invoking `capture_snapshot` as the runner role, which does not have EXECUTE on that function and would therefore fail at the privilege boundary before reaching the intended D1001 trust diagnostic. The fixture now creates a dedicated disposable `deedlight_ledger_untrusted` role, grants only the function/schema access needed to exercise the trust check, and verifies D1001 without widening runner privileges. Implemented in commit `58b8e03645aa8a5047f302f7d27b4523836c6112`. A new exact-head CI run is required; no runtime result is claimed for this correction.

The D1001 and D1002 adversarial cases are now run under separate fixture roles: the dedicated untrusted role reaches only `capture_snapshot` to assert missing observer authority, then the test resets role and runs malformed source identity under the authorized runner role. This avoids a privilege-denial false positive in the D1002 test. Implemented in `485ebbb3788b2aa1e6d17f87e955a5f23e0e191c`. Exact-head PostgreSQL 16 validation remains required.
