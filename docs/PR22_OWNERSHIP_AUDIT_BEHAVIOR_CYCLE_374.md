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

The executable suite now tests PostgreSQL's actual session role-switch behavior, not only the Query 8B `pg_has_role(..., 'SET')` result: a permitted `SET ROLE` succeeds, the same operation fails with permission denied when the membership's SET option is false, and it succeeds again after the option is restored. These checks execute in isolated psql sessions authenticated as a synthetic non-superuser LOGIN role, then switch to the synthetic function owner.

## Validation finding and correction

The first two Cycle 374 PostgreSQL 16 runs (workflows 45482525878 and 45482683052) exposed a fixture syntax defect before any catalog assertions: the PL/pgSQL function body used a single-dollar delimiter instead of PostgreSQL's required paired `$$` delimiter. The job failed at the first synthetic function creation; this was not a query or Production finding.

The fixture was corrected to use paired `$` delimiters. Both failed runs are retained as evidence and are not represented as passes. A later run also exposed that a superuser session could SET ROLE despite a false membership SET option (workflow 45482926573); the test was corrected to use a non-superuser synthetic LOGIN. The final run validates both corrections.

## SET ROLE fixture correction

The first attempted SET ROLE negative assertion ran through the PostgreSQL superuser connection. PostgreSQL superusers can bypass ordinary membership SET restrictions, so that test correctly did not fail. The test now creates a disposable LOGIN role with a non-superuser session, grants it SET access to the synthetic function owner, and tests the owner's membership to the target role from that login session. The SET-enabled path must succeed; after the owner-to-target SET option is disabled, the same path must fail with permission denied. The fixture login and memberships are removed during cleanup.


## Final exact-head CI evidence

- Final tested commit: `b5441c0c197ed40415c48453b6fc633154a80fa0`.
- Workflow: [45483125584](https://github.com/ADRN-9/deedlight/actions/runs/45483125584).
- Overall conclusion: SUCCESS.
- All nine jobs completed successfully, including `security_definer_ownership_audit_database_behavior` and the general `validate` job.
- PostgreSQL 16 job log confirms Query 8A exact signatures/ownership/SECURITY DEFINER/role attributes/ACLs PASS; missing-function, missing-owner-role lookup and non-definer negative cases PASS; Query 8B direct/transitive memberships, INHERIT, SET, effective privileges and unexpected membership PASS; membership option mutation, revoke and restoration PASS; final disposable PostgreSQL 16 behavior PASS.
- General validation job confirms existing security assertions, ESLint, TypeScript, Next.js production build and Cloudflare packaging build PASS.
- The workflow checked out exactly the final tested commit. No Production secrets were supplied to the ownership job.

## Cycle 375 handoff

1. Preserve PR #22 as OPEN / DRAFT / UNMERGED and retain its current branch ancestry.
2. Keep Production NO-GO until an authorized DBA supplies read-only Query 8A/8B evidence and approves the 18 per-signature owner mapping and acceptable membership paths.
3. Have independent security review verify that CI evidence is correctly scoped to synthetic fixtures and does not substitute for Production ownership evidence.
4. Do not alter migrations 036–038 or historical migration 007 without a separately authorized scope.
5. Do not deploy, merge, or perform Production ownership changes as part of this handoff.


# Cycle 376 — ownership audit completeness and fail-closed privilege fixtures

**Starting HEAD:** `110de2cc3ba27b5e3328f045f26a49880b77d9c7`

## F375-02 — effective function EXECUTE privileges

The PostgreSQL 16 behavior suite now creates disposable `anon`, `authenticated`, and `service_role` identities and evaluates PostgreSQL's effective `has_function_privilege(role, signature, 'EXECUTE')` result. The default-ACL fixture preserves `proacl IS NULL` and confirms PUBLIC-derived EXECUTE for all three identities. The explicit-ACL fixture revokes PUBLIC, grants EXECUTE only to the synthetic `service_role`, and proves anon/authenticated are denied while service_role is allowed. These are synthetic ACL behavior fixtures, not claims about the live Production ACLs.

## F375-03 — privileged function-owner fail-closed scenarios

The suite creates one disposable owner role for each dangerous attribute: SUPERUSER, CREATEROLE, CREATEDB, REPLICATION, and BYPASSRLS. It transfers one synthetic SECURITY DEFINER function to each role in turn, verifies Query 8A reports the corresponding catalog attribute, and invokes an explicit safe-owner assertion that must throw for every unauthorized configuration. The function is returned to its benign fixture owner before subsequent checks. No privileged role identity is an expected Production owner.

## F375-04 — actual transitive SET ROLE behavior

In addition to the existing direct SET ROLE positive/negative checks, a synthetic non-superuser login now executes the complete owner → parent → transitive-role chain. The full transitive chain succeeds when each edge has SET enabled. Disabling SET on the parent → transitive-role edge causes the same nested command to fail with PostgreSQL's permission-denied error; restoring SET permits it again. Query 8B's recursive path and effective SET result are checked alongside the actual session operations.

## Preserved coverage and boundaries

- Query 8A and Query 8B remain extracted from the exact documented SQL fences and are executed against disposable PostgreSQL 16.
- The exact 18-signature inventory, explicit/default ACL metadata checks, search_path assertions, direct/recursive membership checks, missing-function/missing-owner/non-definer negative branches, and existing role-option/revoke/restoration tests remain.
- The four lexical negative fixtures in `scripts/verify-delivery-provider-webhooks.mjs` remain unchanged.
- Provider-integrity, provider-concurrency, privacy authorization, consent and delivery reliability workflow jobs remain unchanged.
- Migration 038 is not changed. It has no DBA-approved expected-owner baseline, and adding a guessed or synthetic Production owner expectation would be unsafe.

## Production ownership approval and future implementation plan

Ownership attestation remains unresolved until the authorized Production DBA supplies read-only Query 8A/8B results for the verified Production project and explicitly approves every one of the 18 function owners and acceptable direct/transitive membership paths. Independent security review must accept that evidence and the policy for privileged owner attributes.

Only after those approvals should a separate implementation proposal define the expected-owner contract, its source of authority, how it is reviewed/versioned, and how drift is tested. The contract must not derive values from CI fixture owners, migration-runner identities, a developer's database session, or guessed role names. A subsequent migration/verifier should fail closed on missing or changed approved ownership only after that contract has been formally approved. No baseline is introduced in this cycle.

## Cycle 376 execution evidence

- Initial branch/PR inspection confirmed PR #22 was OPEN / DRAFT / UNMERGED at starting HEAD `110de2cc3ba27b5e3328f045f26a49880b77d9c7`.
- Changes are limited to the PostgreSQL ownership behavior test and this evidence document.
- Exact-head workflow evidence will be added after the new commit's complete CI run finishes; earlier workflow evidence is not substituted for it.

## Cycle 377 handoff

1. Inspect exact-head PostgreSQL 16 job output for the new EXECUTE, privileged-owner, and transitive SET ROLE assertions.
2. Confirm all other jobs pass, including provider integrity/concurrency, privacy, consent and delivery reliability.
3. Keep the four lexical negative fixtures and 18-signature Query 8A/8B inventory unchanged.
4. Obtain authoritative Production DBA Query 8A/8B evidence and explicit owner/membership approval before proposing any expected-owner enforcement.
5. Keep PR #22 OPEN / DRAFT / UNMERGED. Production remains NO-GO; no migrations, deployments, merges, credentials or Production changes are authorized by this handoff.


### Cycle 376 CI execution evidence

- Tested commit: `bd0bc119de3367cf963536c02b62af44100d4c30`.
- Exact-head workflow: [PR Validation run 45485733922](https://github.com/ADRN-9/deedlight/actions/runs/45485733922) — completed SUCCESS with all 9 jobs successful.
- The dedicated `security_definer_ownership_audit_database_behavior` job executed Query 8A/8B against disposable PostgreSQL 16 and logged PASS for the exact 18 signatures, SECURITY DEFINER/owner/role attributes, explicit/default ACLs and effective EXECUTE privileges; missing function/owner/non-definer branches; recursive membership and effective SET; option mutation, revocation and restoration; and final suite completion.
- The same run passed `validate`, provider webhook behavior and concurrency, provider migration ordering, privacy authorization, delivery reliability, consent/transport concurrency, Sprint 12.2 and auth pgcrypto behavior.
- `validate` passed existing security assertions, ESLint, TypeScript, Next.js production build with non-Production configuration, and Cloudflare packaging with non-Production configuration.
- A preceding attempt (run 45485532106) failed at the fixture SQL batch boundary because the generated SQL used a literal backslash-n separator. The separator was corrected to a real newline; the successful exact-head run above validates the correction. The failed attempt is not counted as a pass.

The evidence document update itself will receive its own exact-head CI run; the run above is evidence for commit `bd0bc119...`, not for any later documentation-only commit.


### PR #22 description synchronization

The PR description was refreshed after Cycle 376 to identify the current branch/head, base, ancestry, complete 29-path diff inventory, and the successful PostgreSQL 16/CI evidence for commit `bd0bc119de3367cf963536c02b62af44100d4c30`. The documentation-only synchronization commit that contains this note is separately subject to exact-head CI; do not conflate the prior tested code commit with a later head.
