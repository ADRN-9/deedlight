# PR #22 — Cycle 362 provider security review

**Repository:** `ADRN-9/deedlight`  
**Review baseline:** `1aef18898307c555c41695b1e80702d6e15164ef`  
**Review branch:** `security/private-daily-journey-admin-isolation-c408`  
**Disposition:** P1 concurrency hardening implemented in this branch; P0 owner attestation and P2 migration application status remain blocked on authoritative Production evidence.

## P0 — SECURITY DEFINER owner attestation: BLOCKED

Migration 038's preflight currently attests function source hashes, `prosecdef`, `proconfig`, and EXECUTE privileges. It does **not** inspect `pg_proc.proowner` or compare the owner against an expected role. The static verifier likewise has no owner-attestation assertion or owner-drift behavior fixture.

The expected owner cannot safely be inferred from the migration source:

- Migration `202607210002_rls_policies.sql` creates `public.is_admin()` as `SECURITY DEFINER`, but does not set an explicit function owner.
- Migration 037 creates the provider-integrity lifecycle, suppression, private helper, and administrator functions as `SECURITY DEFINER`. It revokes/grants EXECUTE and renames some functions, but does not establish an explicit owner with `ALTER FUNCTION ... OWNER TO`.
- Migration 038 replaces provider wrappers and creates additional administrator page/detail RPCs as `SECURITY DEFINER`, but does not set explicit owners.
- PostgreSQL's default function owner is the role that executes the relevant `CREATE FUNCTION` statement. That role is not established by these source files and can differ between CI, SQL Editor, and Production execution.

The existing Production read-only audit packet, `docs/PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md`, includes a catalog query returning `pg_get_userbyid(pg_proc.proowner)`. However, the packet is explicitly **PREPARED ONLY**; no authorized Production catalog query was executed. The companion reconciliation document records Production migration/effect classifications as UNKNOWN and states that Production read-only access is unavailable. A disposable CI database's owner is not an authoritative Production ownership baseline.

**Do not hardcode `postgres`, `supabase_admin`, the migration runner, `current_user`, or any other guessed role.** No owner check was added to migration 038 because doing so without the reviewed expected identity would either encode an unsupported assumption or make the migration's authorization contract misleading.

### Required evidence to close P0

A Production owner/DBA must provide approved, read-only catalog evidence for the exact target project, including the owner name and role attributes for every in-scope SECURITY DEFINER identity signature. The evidence must be reviewed and recorded in the access-controlled Production evidence location; raw catalog output and credentials must not be copied into this public PR.

The scope includes:

- `public.is_admin()`;
- lifecycle RPC overloads, `record_delivery_provider_event(...)`, and `record_delivery_provider_suppression_event(...)`;
- migration-037 private integrity/lifecycle/suppression helpers;
- migration-037 administrator list/evidence/history/resolve RPCs;
- migration-038 administrator conflict-page, detail, evidence-page, and history-page RPCs.

After the Production owner contract is independently established, add explicit expected-owner checks using `pg_proc.proowner` and `pg_roles` (or `pg_get_userbyid`), reject NULL/missing/unexpected roles, and add both a positive fixture and a negative owner-drift fixture. The negative fixture must prove the preflight aborts atomically: capture function definitions/owners/ACLs and relevant schema objects before inducing drift, execute the preflight inside a rollback-safe test transaction, and assert no function or schema mutation survives the failed preflight.

**P0 status: NOT COMPLETE.** The owner-identity prerequisite is a real blocker, not a reason to infer an owner from CI.

## P1 — bounded concurrency suite: IMPLEMENTED, CI VALIDATION PENDING

The provider concurrency harness now:

- bounds every PostgreSQL invocation with GNU `timeout` (25 seconds), TERM/KILL escalation, and a five-second connection timeout;
- tracks every background child and routes scenario waits through `wait_bounded` (32-second deadline);
- bounds marker polling (100 × 50 ms);
- installs a 14-minute suite watchdog in a dedicated process group;
- cleans up tracked child process groups on EXIT, INT, or TERM;
- includes self-tests using TERM-resistant children to prove timeout escalation and bounded-wait cleanup;
- introduces a controlled event-ID advisory-lock conflict using PostgreSQL `lock_timeout`, asserting SQLSTATE `55P03` (`lock_not_available`);
- verifies the timed-out RPC did not persist an event or mutate database state.

The controlled conflict holds only the same event-ID advisory lock that the production RPC acquires first. It does not create an inverted production lock hierarchy or modify production RPCs.

The static verifier now asserts the timeout, wait, cleanup, self-test, and SQLSTATE safeguards.

**P1 status: IMPLEMENTED IN SOURCE; not yet validated by a new exact-head CI run.** No local shell execution or database run is claimed.

## P2 — migration 038 application status: UNKNOWN; DO NOT REWRITE

No authoritative Production migration-history query, catalog audit, SQL Editor execution record, or deployment evidence available in the inspected project sources establishes whether migration 038 has been applied. The existing read-only audit/reconciliation material is prepared-only and records prior Production migration classifications as UNKNOWN; it predates this PR's migrations 037 and 038 and cannot establish their current Production status.

Therefore migration 038 must not be rewritten in place and no corrective migration should be invented yet. First obtain authoritative read-only migration history and schema-effect evidence from the Production owner. If 038 is proven unapplied, retain its forward-only strategy and correct the candidate before any authorized application. If proven applied, use a reviewed forward corrective migration. If status remains unknown, preserve the historical migration unchanged.

Preserve migrations 036 and 037, both historical migration 007 variants, and the existing SQL Editor aggregate. No Production migration, deployment, or resource was executed or modified for this review.

## Execution status

| Item | Status |
|---|---|
| PR #22 state and starting HEAD inspected | PASS |
| Existing `is_admin()` source-attestation commit inspected | PASS; no duplicate |
| P0 expected Production owner established | BLOCKED |
| P0 positive/negative owner fixtures | NOT IMPLEMENTED; prerequisite unavailable |
| P1 deadlines, bounded waits, process tracking and cleanup | IMPLEMENTED IN SOURCE |
| P1 lock-timeout SQLSTATE and unchanged-state regression | IMPLEMENTED IN SOURCE |
| P1 suite-hang and wait-hang self-tests | IMPLEMENTED IN SOURCE |
| P1 exact-head CI | PENDING |
| P2 migration 038 Production status | UNKNOWN |
| Production operations | NOT PERFORMED |
| PR merge/approval | NOT PERFORMED |
