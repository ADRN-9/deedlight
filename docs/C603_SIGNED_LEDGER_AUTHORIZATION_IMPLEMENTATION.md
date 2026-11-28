# C603 — Signed authorization boundary implementation record

**Repository:** ADRN-9/deedlight  
**Baseline:** C602 PR #40 head `4942b57570efab56807cd04ce73a96ceedece8ff`  
**Implementation PR:** #41 (draft)  
**Scope:** disposable PostgreSQL execution-ledger fixture and adversarial tests only.

## Implementation shape

The original nine ledger bodies are retained as owner-only `*_impl` functions. Their unwrapped public signatures are renamed and lose runtime actor EXECUTE. Nine new wrapper signatures require an additional JSONB authorization envelope.

Actor identity now derives from `session_user`, not the mutable `current_setting('role')` value. The five actor principals are separate LOGIN / NOINHERIT / NOSUPERUSER roles with no membership between them. The shared postgres test login's membership in all five is revoked by the C603 overlay after legacy C578/C585/C600 tests have completed.

All SECURITY DEFINER implementation and wrapper functions are reassigned to `deedlight_ledger_owner`, a NOLOGIN / NOSUPERUSER owner. The owner receives only schema/table/sequence access needed by the fixture and inherited `pg_monitor` access for the existing live database identity check. Its temporary schema CREATE privilege is revoked after function ownership transfer. Runtime actors do not receive direct ledger table privileges.

## Signed envelope contract (version 1)

The wrapper verifies exactly 15 fields:

- `version`, `operation`, `actor`, `principal`, `executionId`;
- `databaseResource` (live system identifier, database OID/name, server version);
- `generation`, `audience`, `nonce`, `issuedAt`, `expiresAt`;
- `request`, `requestDigest`, `keyId`, `signature`.

The request digest is SHA-256 over the PostgreSQL JSONB canonical text representation. The signature is HMAC-SHA-256 over the canonical JSONB envelope with `signature` removed. Key lookup binds actor, principal, key ID, generation and audience. The signed request binds the exact operation and typed parameters, execution ID, and source identity. Recovery additionally binds a digest and count of the exact stale target set. Expiry is bounded to two minutes with 15 seconds of future clock skew. A unique actor/nonce row rejects replay.

The nonce insert and business operation execute in the same PostgreSQL statement transaction: a later business-logic exception rolls back the nonce insert as well as the operation. Invalid envelopes fail before the nonce insert. The C603 tests compare complete JSON row projections for approvals, executions, snapshots, commit markers, verification events and authorization nonces before/after rejected requests.

## Actor / RPC grants

| Actor | Allowed wrappers |
|---|---|
| Approver | approve_execution |
| Runner | reserve_execution, record_effect_commit_marker, start_execution, heartbeat_execution, finalize_execution |
| Observer | capture_snapshot |
| Recovery | recover_stale_executions |
| Verifier | record_verification |

All other wrapper grants are absent. Original unwrapped signatures are absent under their former names; renamed implementations are owner-only.

## Executable test coverage added

- Positive signed lifecycle traverses all nine wrappers and all five actor classes.
- Catalog-derived five actor × nine RPC EXECUTE matrix.
- Five actor × nine direct invocation matrix: allowed RPC without envelope fails with D1001; all other RPCs fail at EXECUTE with 42501.
- Cross-role membership assertions and a runner-level attempted Approver-to-Runner `SET ROLE` denial.
- Invalid signature, wrong actor, request/source substitution and nonce replay rejection.
- Zero protected table and nonce side effects on all rejected cases.
- Existing C578/C585/C593/C595/C600 fixture tests remain before the C603 overlay in the PostgreSQL 16 runner.

## Explicit limitations / production handoff

This is not Production remediation proof. The runner simulates each authenticated principal using superuser `SET SESSION AUTHORIZATION`; it does not prove actual external login authentication or Production connection-pool isolation. HMAC is symmetric: the external signer and database verifier share key material. Deterministic keys in the overlay are disposable CI-only values and must never be reused. No Production key provisioning, rotation/revocation, signing service, live principal mapping, generation authority, privilege change, trust-root change, infrastructure change or forward Production migration is performed.

Production adoption requires Security/DBA review of key custody and signer/database trust separation (including whether an asymmetric signature verifier is required), generation rotation, independent login provisioning, catalog parity, live deployment migration design, and external gateway integration. C603 deliberately leaves those human-controlled trust dependencies unresolved.

## Preservation and rollback

- No historical migration SQL or migration inventory file is changed.
- No C575/C576 historical contract is rewritten.
- PRs #36–#40 remain untouched and unmerged.
- The new fixture overlay runs only after the existing disposable historical test suite.
- Rollback: revert PR #41; no Production rollback or data operation is necessary.
