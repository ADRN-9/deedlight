# PR #22 — Cycle 372 SECURITY DEFINER ownership query behavior

**Starting HEAD:** `9948510fd98300b3b4bdab48b4c9f785fa361b0f`  
**Scope:** `ADRN-9/deedlight`, PR #22 only  
**Production access:** NOT USED

## Implementation

The new `scripts/test-security-definer-ownership-audit.mjs` extracts the actual fenced Query 8A and Query 8B SQL from `docs/PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md`. It verifies the exact 18-signature inventory and executes those SQL statements against the dedicated PostgreSQL 16 CI service database `deedlight_ownership_audit_test`.

Synthetic fixture roles and functions are created only in that disposable database. The fixture assigns 16 functions to `deedlight_audit_owner_a`, one to an owner with no memberships, and one to `deedlight_audit_owner_b`. These identities are test data, not Production expectations.

Coverage includes:

- Exact function signature resolution and catalog identity.
- SECURITY DEFINER status and owner identity/role attributes.
- Default NULL `proacl` behavior versus an explicit ACL after revoking PUBLIC EXECUTE.
- Missing function and non-SECURITY-DEFINER status.
- Missing-owner-role fail-closed branch.
- Direct and transitive memberships, cycle-safe paths, per-edge INHERIT/SET options and effective MEMBER/USAGE/SET results.
- Visibility of an intentionally unexpected BYPASSRLS membership.
- An owner with no memberships correctly producing no Query 8B rows.

PostgreSQL dependencies prevent dropping a role that still owns a function. Therefore the missing-owner-role branch is tested by forcing the Query 8A owner-role LEFT JOIN to miss in a disposable query variant; it does not claim that a real Production owner is missing.

## CI integration

A dedicated `security_definer_ownership_audit_database_behavior` job uses `postgres:16`, a separate database, loopback-only connection assertions, and no Production credentials. The existing lexical verifier and all four negative source fixtures remain in place. The lexical verifier now asserts that this executable behavior suite remains wired into CI.

## Security and migration boundary

- No Production database access, query execution, or mutation occurred.
- No Production owner mapping or role membership is inferred or approved.
- Migration 038 is not changed.
- Historical migrations 007 and migrations 036–038 are not changed.
- No deployment or merge is authorized by this work.
- CI behavior proves only the synthetic PostgreSQL fixture. It is not Production ownership attestation.

## Cycle 373 handoff

1. Inspect exact new HEAD and the dedicated PostgreSQL 16 job logs.
2. Fix any SQL/runtime or assertion defects revealed by CI, without weakening Query 8A/8B or the existing four lexical negative fixtures.
3. Verify all nine workflow jobs on the exact new HEAD, including TypeScript, Next build and Cloudflare packaging.
4. Keep the DBA dependency open: run the unmodified SELECT-only Query 8A/8B on the exact Production project only after an authorized read-only identity is provided; preserve raw evidence in restricted storage and obtain explicit owner-map approval plus independent review.
5. Keep PR #22 OPEN and DRAFT. Do not merge, deploy, alter Production ownership or rewrite migration 038.

## Final Cycle 372 execution evidence

The exact-head push workflow completed successfully:

- **Workflow run:** [45478435965](https://github.com/ADRN-9/deedlight/actions/runs/45478035937)
- **Validated HEAD:** `83184756ff3fd7826790959ce94e634cfdf4be8c`
- **Conclusion:** SUCCESS — all nine jobs passed.
- **Ownership audit job:** `security_definer_ownership_audit_database_behavior` — PASS on PostgreSQL 16.16.
- Its logs explicitly report Query 8A identity/owner/ACL assertions, missing-function/missing-owner/non-definer branches, Query 8B membership/INHERIT/SET/effective-privilege assertions, and final disposable PostgreSQL PASS.

Two early exact-head iterations exposed test-harness issues (a SQL statement terminator in the derived query wrapper and fixture assertions that assumed result order). A subsequent run also exposed PostgreSQL's canonical `timestamp with time zone` display. Those test-only issues were corrected; the final exact-head run above passed. The actual Query 8A/8B source was not modified.

**Final Cycle 372 status:** IMPLEMENTED AND EXACT-HEAD CI-VALIDATED. The evidence remains limited to the synthetic disposable PostgreSQL fixture. Production owner attestation remains BLOCKED and Production remains NO-GO.
