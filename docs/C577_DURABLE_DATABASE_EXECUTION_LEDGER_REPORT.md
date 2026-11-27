# DeedLight C577 — Durable Database Execution Ledger and Atomic Replay Prevention

**Status:** Disposable PostgreSQL 16 ledger implementation and integration harness added. Production deployment, migration-runner integration, verifier trust, and Production acceptance are NOT ESTABLISHED. This is not a Production migration.

## 1. Baseline and scope

Repository: `ADRN-9/deedlight`.

Verified immediately before C577:
- PR #29: OPEN, unmerged; head `2133cee1439287399740bf9794bbb0b4e793105c`.
- PR #30: OPEN, unmerged; head `0c551b48315249bcd64872ec35952ee8853ba524`.
- PR #31 / C575: OPEN, unmerged; head `64f0daab2f8a5c75ef19431e1e888dcea04713ca`.
- PR #32 / C576: OPEN, unmerged; head `74af17632cdf27d032058d6782d96f569ef92fca`.
- All four PRs were mergeable at baseline.
- C576 exact-head CI run `46047799457`, run #2192, completed SUCCESS, 12/12 jobs.

C577 starts from the exact C576 head. It adds files only under `scripts/fixtures`, `scripts`, CI workflow and documentation. It does not add a file under `supabase/migrations`.

## 2. Database-local identity and uniqueness

The disposable fixture creates schema `deedlight_execution_ledger`.

Database identity is derived inside PostgreSQL from:
- `pg_control_system().system_identifier`
- `pg_database.oid` for `current_database()`
- `current_database()`
- `server_version_num`

No caller-supplied database identity is accepted by reservation, snapshot, finalization, recovery or verification functions. Every operation reloads the installed identity and compares it to the live server/database values; mismatch fails closed.

The approval and execution tables enforce database-scoped uniqueness:
- `(system_identifier, database_oid, record_id)`
- `(system_identifier, database_oid, execution_id)`

Execution rows retain the database name and immutable source identity. A second disposable database in the same PostgreSQL cluster can use the same UUID pair because its database OID is different. A copied physical cluster retains the PostgreSQL system identifier and database OIDs; the system identifier is therefore not a deployment/environment trust root. Production must additionally pin project/environment identity through separately governed deployment authority.

## 3. Authorities and privileges

The fixture defines five distinct NOLOGIN roles:
- `deedlight_ledger_approver`
- `deedlight_ledger_runner`
- `deedlight_ledger_observer`
- `deedlight_ledger_verifier`
- `deedlight_ledger_recovery`

Each operation checks the active PostgreSQL role inside a SECURITY DEFINER function with a fixed search path. Operational roles receive function execution grants only; they cannot read or write ledger tables directly. The observer can invoke only the server-side snapshot function and has no direct read or write privilege on the ledger or disposable effect table.

Approvals are append-only except for a single atomic `consumed_at` transition. The verifier can append a verification event only after a terminal outcome. That event does not change execution state, authorize migration history, or establish semantic acceptance.

The CI bootstrap grants these roles to the disposable PostgreSQL `postgres` superuser solely so tests can use `SET ROLE`. Production must provision separate non-overlapping login identities and must not grant all roles to one login or superuser. The CI role arrangement is not a Production trust model.

## 4. Reservation, execution and finalization transaction boundaries

The required protocol is:

1. An authorized approver inserts a single-use approval bound to exact record ID, execution ID and source identity.
2. A runner calls `reserve_execution`. The function locks the approval row `FOR UPDATE`, verifies the full scope and unconsumed state, inserts the reserved ledger row, and consumes the approval in the same transaction. Unique indexes and the row lock arbitrate concurrent attempts.
3. The runner commits reservation in its own short transaction.
4. A separate observer connection calls `capture_snapshot(..., 'pre', ...)`. The observer can only see a committed reservation. The SQL query comes from an owner-installed allowlist; callers cannot supply SQL or observation values.
5. The runner commits `start_execution` separately. It requires the pre-snapshot.
6. The migration runs in its own transaction. It must not share the reservation/finalization transaction. As the final ledger operation inside that same transaction, the runner calls `record_effect_commit_marker`, binding the active execution and exact stored source-identity JSON. The marker row and migration effects therefore commit or roll back together.
7. A separate observer connection can capture the post-snapshot only after the marker is visible in a committed transaction while the ledger remains RUNNING. The function checks the marker's database, execution, runner and source binding; callers cannot submit snapshot rows or arbitrary SQL.
8. The runner finalizes in a separate transaction. Finalization requires the committed effect marker and both independently collected snapshots, plus a supported explicit outcome.

The separate-session visibility requirements are important: an uncommitted reservation cannot be observed by the observer; a post-snapshot cannot be collected until the running state and same-transaction effect marker are committed; finalization cannot precede the committed post-snapshot. If the migration transaction rolls back, its effect marker rolls back too, so a post-snapshot and finalization are refused. A caller that wraps the reservation in a transaction and rolls it back leaves no reservation or consumed approval. The runner protocol must commit reservation before any migration effects.

The SQL fixture contains a single preinstalled observation query for a disposable effect table. It proves server-side snapshot mechanics and phase binding; it is not a general production semantic query catalogue. Production query bundles need reviewed, versioned, migration-specific SQL and independent provenance.

## 5. Crash and terminal-state semantics

State transitions:
- `reserved -> running`
- `reserved -> interrupted` when a stale reservation was never started
- `running -> succeeded | failed | partial` after required snapshots
- `running -> unknown` when a running process becomes stale or disappears

`interrupted`, `unknown`, `succeeded`, `failed`, and `partial` are terminal. The trigger rejects terminal updates and ledger evidence deletes. Source identity, record/execution IDs, approval identity, database identity and reservation timestamp cannot be changed. Heartbeats are permitted only as monotonic `running -> running` updates by the owning runner.

An ambiguous execution becomes `unknown`, never inferred successful or safely replayable. A reserved-but-not-started crash becomes `interrupted`. Both remain permanently protected by unique keys and consumed approval state. A post-crash recovery snapshot is not equivalent to a successful post-execution snapshot and does not upgrade unknown state.

The execution runner must treat database connectivity loss after reservation as an ambiguous state. It must not retry the migration under a new ID without independent reconciliation and a new human-approved plan.

## 6. Disposable PostgreSQL integration coverage

Files:
- `scripts/fixtures/migration-execution-ledger-v1.sql`
- `scripts/fixtures/test-migration-execution-ledger-v1.sql`
- `scripts/test-migration-execution-ledger-postgres16.sh`
- New CI job `migration_execution_ledger_postgres16` in `.github/workflows/pr-validation.yml`.

The CI job uses a PostgreSQL 16 service, a pinned Docker service address, fixed localhost connection settings, an exact disposable database name and an explicit disposable-fixture authorization marker. It fails closed if Supabase credentials, provider keys or Production database variables are present.

Adversarial/integration scenarios:
1. Live database identity is compared with server-derived PostgreSQL facts.
2. Reservation transaction rollback leaves no ledger row and does not consume the approval.
3. Normal successful lifecycle requires independently captured pre/post snapshots.
4. Snapshot rows reflect the before/after effect state and retain observer identity.
5. Runner heartbeat works without permitting other same-state mutations.
6. Partial outcome remains partial.
7. Completed execution replay is rejected.
8. Duplicate execution ID is rejected at approval uniqueness.
9. Duplicate record ID is rejected at approval uniqueness.
10. Stale reserved execution becomes interrupted.
11. Replay after interrupted outcome is rejected.
12. Stale running execution becomes unknown.
13. Runner and approver roles cannot invoke verifier authority.
14. Terminal outcome mutation is rejected.
15. Runner cannot directly read ledger tables.
16. Observer cannot directly mutate effect or ledger tables.
17. A forged caller-supplied database identity argument has no matching API and fails.
18. An actual disposable PostgreSQL client is SIGKILLed during an open effect transaction; the uncommitted effect rolls back while the separately committed RUNNING ledger entry survives and is recovered to unknown.
19. Two simultaneous independent sessions contend for the same approval; exactly one reservation may commit.
20. The same record/execution UUID pair can be reserved in a second disposable database in the same cluster, demonstrating database scoping.
21. The post-snapshot API rejects an execution with no committed effect marker.

The crash test checks that the uncommitted effect is absent after client termination and that the ledger remains UNKNOWN. The race test checks exactly one committed row. The tests do not use Production.

## 7. Integrity and trust limitations

This ledger supplies database-enforced uniqueness, role-gated transitions, immutable terminal records and independently captured snapshots. It does not make a superuser untrusted: a database superuser can change schema, disable triggers, change role grants or replace functions. Production requires independent DBA controls, audit retention and alerting.

Snapshot SHA-256 values are integrity checks over the server-generated JSON snapshot. They are not signatures, and they do not prove the migration executed. The effect marker is a runner-controlled commit witness, not independent proof that the source file ran: a compromised or dishonest runner could call it without executing the migration. The ledger records a database-observed lifecycle and state; it does not prove source code was safe or that all semantic effects were correct.

The current `record_verification` operation is an append-only role-gated event. Its caller-supplied verdict/evidence is not a cryptographic attestation. No verifier trust root is provisioned, and no C576 acceptance bypass is introduced.

Approver/verifier role separation in CI is a role boundary only. Production must separately govern login membership, keys, verifier deployment, source approvals, DBA privileges and emergency access. No shared superuser should possess routine approver, runner, observer and verifier duties.

## 8. C568–C576 and historical preservation

C577 does not edit:
- `supabase/migration-inventory.json`
- Either of the two Migration 007 SQL sources.
- Migration 039.
- Any historical migration SQL source.
- C568–C576 verifier or test files.

C576's exact-head run is predecessor evidence; C577's own CI must pass on its final exact head. The inherited C568–C576 regression suites remain in the same PR workflow. The 40-entry inventory, duplicate-version mapping, `catalog_only_v1` and SQL NULL distinctions are not altered by this fixture.

## 9. Remaining work and human-controlled dependencies

Not delivered in C577:
- Production migration-runner integration and a separately committed reservation protocol in the actual runner.
- Production schema migration / deployment plan; this fixture is not a Production migration.
- Project/environment trust-root provisioning and physical-clone identity binding.
- Separate Production approver, runner, observer, verifier and recovery login identities.
- Cryptographic verifier attestation and source/approval signature validation.
- Versioned reviewed Production observation query bundles for actual migration-specific semantics.
- Production DBA audit controls, retention, alerting and emergency-access review.
- F-01 trust-failure diagnostic remediation.
- Analyzer integration that consumes ledger evidence without treating it as semantic acceptance.

No Production migration execution, migration-history reconciliation, trust-root provisioning, credential exposure, PR merge or Production activation occurred.

## 10. Final classification

| Area | Classification |
|---|---|
| C576 baseline and predecessor CI | PASS |
| Disposable ledger schema and server-derived DB identity | IMPLEMENTED; CI pending |
| Database-scoped unique record/execution IDs | IMPLEMENTED; CI pending |
| Atomic reservation and single-use approval consumption | IMPLEMENTED; CI pending |
| Terminal-state immutability and crash-state recovery | IMPLEMENTED; CI pending |
| Independent server-side pre/post snapshots | IMPLEMENTED for allowlisted disposable fixture query |
| Separate role-gated approver/runner/observer/verifier/recovery operations | IMPLEMENTED; Production identity governance NOT ESTABLISHED |
| Transaction rollback and concurrency race evidence | NOT ESTABLISHED until exact-head CI completes |
| Same-transaction effect marker rollback coupling | NOT ESTABLISHED until exact-head CI completes |
| Actual process kill and crash-recovery evidence | NOT ESTABLISHED until exact-head CI completes |
| Production migration-runner integration | BLOCKED |
| Production observation query bundles | BLOCKED |
| Production verifier trust root | BLOCKED |
| Production DBA trust and retention controls | NOT ESTABLISHED |
| F-01 | OPEN |
| Production readiness | NO-GO |

**Safety disposition:** no Production schema change, migration execution, migration-history reconciliation, credential or trust-root provisioning, PR merge or activation.
