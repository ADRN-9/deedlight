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
