# C593 — Execution ledger identity and manifest trust hardening

**Repository:** `ADRN-9/deedlight`  
**Starting candidate:** `ba906e7c06e1efc52dc7185c9125277e08400220`  
**Branch:** `feat/c593-ledger-live-identity-manifest-trust`  
**Status at implementation handoff:** Source and adversarial tests committed; PostgreSQL 16 CI pending. No Production mutation or trust-root change.

## Scope

This remediation changes only the disposable execution-ledger fixture, its PostgreSQL 16 adversarial test, and the C577/C578/C585/C593 engineering reports. It does not change any historical migration source or the migration inventory.

### Live database identity at every privileged RPC

The fixture's `current_database_identity()` verifier now compares the immutable installation anchor with live server-derived values:
- PostgreSQL system identifier from `pg_control_system()`;
- current database OID from `pg_database`;
- current database name;
- server version number.

The verifier fails with structured D1001 / `live_database_identity_mismatch` (or `database_identity_anchor_missing`) when the anchor is absent or differs. The check is the first operation in each privileged SECURITY DEFINER RPC, before role authorization, writes, or dynamic query execution:
`approve_execution`, `reserve_execution`, `record_effect_commit_marker`, `capture_snapshot`, `start_execution`, `heartbeat_execution`, `finalize_execution`, `recover_stale_executions`, and `record_verification`.

This is database-local identity validation. It does not independently prove source execution or a Production deployment's physical identity.

### Logical restore and clone limitations

The tests simulate an identity-anchor substitution by bypassing only the fixture's append-only trigger inside a rollback-protected disposable PostgreSQL transaction. They exercise:
- a mismatched persisted system identifier;
- a mismatched persisted database OID, modeling restoration into another database on the same cluster;
- fail-closed behavior for `reserve_execution`, `record_effect_commit_marker`, `finalize_execution`, and `recover_stale_executions`;
- absence of approval consumption, execution creation, marker writes, or status changes after identity failure.

A logical restore into a new database/cluster is rejected when the new live OID or cluster system identifier differs from the copied anchor. A logical restore into the same database identity cannot be distinguished by these local fields alone.

**Physical clone warning:** PostgreSQL's system identifier is copied by physical cloning. A clone may also retain database OIDs, names, and server version. Therefore system identifiers alone do not prevent a physical clone from appearing identical. This fixture does not claim to solve physical cloning.

### Separately governed Production environment trust binding

Production acceptance requires an out-of-database, separately governed environment binding:
1. A control-plane authority outside the database backup/restore boundary identifies the provider account/project and the unique live database deployment resource (not merely the PostgreSQL system identifier).
2. The live workload obtains a short-lived, signed attestation from provider workload identity. The attestation binds the unique resource identity, DeedLight Production environment ID, database endpoint identity, deployment generation, expiry, and a fresh challenge/nonce.
3. A separately administered verifier checks the signature, audience, expiry, resource identity, deployment generation, and nonce freshness/replay status before any privileged ledger RPC proceeds.
4. The verifier trust root and nonce/replay authority are administered outside the cloned database and are not supplied by a caller-controlled SQL parameter or user-settable GUC.
5. Missing, stale, replayed, unverifiable, or clone-mismatched attestations fail closed with a structured trust failure. No fallback to PostgreSQL system identifier alone is allowed.

The Production control-plane binding, provider identity source, signing/verifier key custody, nonce service, DB-side enforcement integration, and operational role separation require explicit Security and DBA ownership and review. They are **not implemented or provisioned by C593**. No credential or Production trust root was changed.

### Manifest canonicalization and trust

Canonical manifest ordering now sorts UTF-8 query identifiers by their byte representation, rather than locale-dependent text collation. The digest input remains sorted `queryId:querySha256` records separated by LF and SHA-256 encoded as lowercase hex.

The test suite adds:
- a fixed independent SHA-256 vector;
- permutation-invariance coverage;
- duplicate-member rejection;
- a forged stored-manifest digest rejection;
- a validly digested manifest whose query registry entry is not a member;
- direct source-identity UPDATE attempts against approval, execution, and commit-marker evidence.

### D1008 persisted-diagnostic semantics

D1008 has two related but distinct representations:
- As a PostgreSQL exception SQLSTATE, it is used only when a function raises an `ambiguous_execution_outcome` exception.
- In stale-running recovery, the recovery RPC persists `status='unknown'` and `outcome_detail.category='ambiguous_execution_outcome'` plus `outcome_detail.diagnosticCode='D1008'`. The recovery call itself returns a recovered-row count; the persisted code is not evidence that the recovery RPC raised SQLSTATE D1008.

The persisted diagnostic is durable audit context for an ambiguous outcome. It does not prove whether the external migration effects committed.

## Preservation checks

At the starting candidate:
- `supabase/migration-inventory.json` blob SHA: `4e63f31368d446e905f4f44565be73337c7188fb`.
- Inventory declares 40 migration source files and 39 unique versions.
- No `supabase/migrations/**` path, migration inventory, C575 schema/validator contract, C576 pre/postcondition contract, or `catalog_only_v1` artifact is edited by this branch.

The branch edits only:
- `scripts/fixtures/migration-execution-ledger-v1.sql`;
- `scripts/fixtures/test-migration-execution-ledger-c585.sql`;
- `docs/C577_DURABLE_DATABASE_EXECUTION_LEDGER_REPORT.md`;
- `docs/C578_EXECUTION_LEDGER_SECURITY_REMEDIATION.md`;
- `docs/C585_TRUST_DIAGNOSTICS_AND_BUNDLE_MANIFEST.md`;
- this report.

## Validation requirements and status

**Implemented:** per-RPC live identity checks; explicit bytewise manifest ordering; independent digest vector; forged digest and nonmember adversarial cases; source-identity immutability checks; persisted D1008 semantics; Production physical-clone trust-binding contract.

**Not yet executed at handoff:** PostgreSQL 16 integration tests, actual PostgreSQL log inspection, all applicable security assertions, and exact-head CI. The branch has no local repository shell execution in this task. GitHub Actions is the required validation machine.

The exact-head CI must prove the C593 evidence markers and preserve all inherited C575/C576, C577, C578, C585, migration inventory, and other database/security jobs. A green overall job without the C593 markers in actual PostgreSQL logs is insufficient.

## Historical workflow evidence reconciliation

The following are historical results on their respective exact branch heads, not C593 validation:
- C577 exact branch head `7246312a93524e0bbde10f5d27acbe36db3e5a62`: push run #2229 / `46051417528`, 13/13 jobs successful. Its earlier #2226 PostgreSQL run is not valid crash-recovery evidence; the C577 report withdraws that subtest's PASS.
- C578 exact branch head `eb6b1ca392563bce388819d1a5462932e340cbeb`: push run #2258 / `46056320456`, 13/13 jobs successful. PostgreSQL job `140699564456` actual log contains backend handshake, client SIGKILL 137, backend exit, effect/marker rollback, UNKNOWN recovery and replay rejection. PR merge-context run #2259 / `46056326657` also succeeded.
- C585 exact branch head `ba906e7c06e1efc52dc7185c9125277e08400220`: push run #2326 / `46071479293`, 13/13 jobs successful. PostgreSQL job `140749181289` actual log contains C585 manifest, trust-diagnostic, crash recovery, D1008 and deterministic replay markers. PR merge-context run #2327 / `46071487615` also succeeded; PostgreSQL job `140749207151` passed.

Earlier C585 runs #2285, #2303, #2319 and subsequent corrections remain historically accurate failed attempts; the later #2326/#2327 runs validate the C585 final candidate. None of those runs validates C593 changes.

## Production disposition and human-controlled dependencies

**Production remains NO-GO.** This branch is fixture and evidence hardening only.

Human-controlled dependencies:
- Security architecture approval of the out-of-database physical-clone binding and trust-root custody.
- DBA/provider confirmation of the authoritative unique deployment resource identity and provider workload-identity mechanism.
- Security/operations ownership of the external nonce and replay service.
- Review of how every Production privileged RPC obtains and validates fresh attestation without a caller-controlled bypass.
- Independent review of the implementation and final CI evidence.

No PR merge, Production migration, migration-history reconciliation, credential rotation, trust-root provisioning, or scheduler activation is performed or authorized here.
