# PR #22 — Cycle 373 PostgreSQL ownership-audit test hardening

**Repository:** `ADRN-9/deedlight`  
**PR:** [#22](https://github.com/ADRN-9/deedlight/pull/22)  
**Branch:** `security/private-daily-journey-admin-isolation-c408`  
**Cycle 373 baseline:** `9948510fd98300b3b4bdab48b4c9f785fa361b0f`

## Existing executable test suite retained

The branch already contained the Cycle 372 disposable PostgreSQL 16 harness at the start of this work. Rather than maintain duplicate suites, Cycle 373 retained and strengthened `scripts/test-security-definer-ownership-audit.mjs` and its existing dedicated `security_definer_ownership_audit_database_behavior` workflow job.

The harness extracts the actual fenced Query 8A and Query 8B SQL from `docs/PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md`, verifies all 18 exact signatures, and executes those query bodies against the dedicated disposable PostgreSQL 16 database. The existing suite covers:

- SECURITY DEFINER status, exact catalog identity, and synthetic owner assignment across all 18 signatures.
- Explicit ACL versus default `proacl IS NULL` behavior, including PUBLIC EXECUTE removal.
- All owner role attributes and a missing-membership owner.
- Missing function, non-SECURITY-DEFINER, and missing owner-role lookup negative cases.
- Direct and transitive membership paths, per-edge INHERIT/SET options, and effective MEMBER/USAGE/SET privileges.
- An intentionally unexpected BYPASSRLS membership that remains visible for review.

## Cycle 373 hardening

The synthetic function definitions now explicitly set `search_path = pg_catalog`. The test asserts the exact `function_settings_search_path` returned by Query 8A for every signature.

The owner-role assertions now check expected fixture attributes rather than merely checking that catalog fields are non-NULL: no fixture owner is superuser, CREATEROLE, CREATEDB, LOGIN, REPLICATION, or BYPASSRLS. The expected INHERIT role attribute is also asserted for the NOINHERIT fixture owner versus the INHERIT owners.
The membership suite also mutates a direct membership's INHERIT and SET options and checks the effective MEMBER/USAGE/SET results. It performs real PostgreSQL `SET ROLE` operations while SET is granted and asserts PostgreSQL rejects `SET ROLE` while the edge's SET option is false. It then revokes the parent membership and verifies that both the direct edge and recursive child path disappear before restoring the edge and proving both paths return.

The original lexical verifier tests remain intact. The existing Cycle 372 PostgreSQL 16 job is retained as the single executable ownership-audit CI job; the duplicate Cycle 373 harness/job drafted during initial implementation was removed to avoid competing fixtures and redundant CI work.

## Missing-owner catalog limitation

A valid `pg_proc.proowner` reference depends on its owning role. PostgreSQL prevents ordinary deletion of a role that still owns a function. No invalid system-catalog state is fabricated. The suite tests the fail-closed `MISSING_OWNER_ROLE` branch by changing only the owner-role LEFT JOIN in a disposable query variant to `ON false`, then asserting every expected function is reported as unresolved. This tests defensive query behavior, not a real Production owner state.

## Safety and Production boundary

All identities are synthetic and confined to the disposable CI database. No Production owner name or expected mapping is inferred. No Production database operation, deployment, migration, provider request, or delivery action was performed. Migrations 036–038 and historical migration 007 remain unchanged.

The PostgreSQL behavior run does not establish Production ownership, migration application status, acceptable Production memberships, DBA approval, or independent security acceptance. Production remains NO-GO.

## Cycle 374 handoff

1. Verify the final exact branch HEAD and inspect the PostgreSQL 16 job logs.
2. Confirm the search-path and owner-attribute assertions pass on the final HEAD.
3. Retain the separate lexical verifier coverage and inspect any SQL/runtime failure without weakening the actual audit queries.
4. Keep the Production DBA owner-map and independent security review gates open.
5. Keep PR #22 OPEN / DRAFT / UNMERGED; do not merge, deploy, or alter Production ownership.


## Cycle 374 validation extension

The executable suite now tests PostgreSQL's actual session role-switch behavior, not only the Query 8B `pg_has_role(..., 'SET')` result: a permitted `SET ROLE` succeeds, the same operation fails with permission denied when the membership's SET option is false, and it succeeds again after the option is restored. These checks execute in isolated psql sessions as the synthetic owner role after switching away from the superuser session identity.

## Validation finding and correction

The first Cycle 374 exact-head PostgreSQL 16 run (workflow 45482525878) exposed a real fixture syntax defect before any catalog assertions: the PL/pgSQL function body used a single-dollar delimiter instead of PostgreSQL's required paired `$$` delimiter. The job failed at the first synthetic function creation; this was not a query or Production finding.

The fixture was corrected to use paired `$$` delimiters. The failed run is retained as evidence and is not represented as a pass. A fresh exact-head CI run is required to validate the correction and the subsequent assertions.
