# PR #22 — Cycle 370 SQL ownership-audit verifier hardening

**Repository:** `ADRN-9/deedlight`  
**PR:** [#22](https://github.com/ADRN-9/deedlight/pull/22)  
**Branch:** `security/private-daily-journey-admin-isolation-c408`  
**Starting HEAD:** `864a685511e2e63a4fdc7e9aedd65138017fcd15`  
**Scope:** lexical/source-structural verification of the existing Query 8A and Query 8B fenced SQL blocks.  
**Production execution:** NOT PERFORMED.

## Changes

`scripts/verify-delivery-provider-webhooks.mjs` now extracts the actual fenced `sql` block beneath each exact Query 8A / Query 8B heading. Each section must contain exactly one fenced SQL block. Validation is performed against those extracted SQL strings, not against arbitrary prose elsewhere in the audit document.

The verifier preserves and checks exactly 18 function identity signatures in each query block. The signature inventory is unchanged.

### Query 8A structural requirements

The extracted SQL must include:

- Exact signature resolution through `pg_catalog.to_regprocedure`.
- A left join to `pg_catalog.pg_proc`, retaining missing signatures in the result.
- `proowner`, resolved owner name and a join to `pg_catalog.pg_roles`.
- Explicit missing-function, missing-owner-role and non-SECURITY-DEFINER statuses.
- SECURITY DEFINER metadata and exact `proconfig` search-path settings.
- Explicit `proacl` and the defaulted effective ACL using `acldefault`.
- Owner role attributes: superuser, INHERIT, CREATEROLE, CREATEDB, LOGIN, REPLICATION and BYPASSRLS.

### Query 8B structural requirements

The extracted SQL must include:

- The same exact 18-signature inventory.
- A `WITH RECURSIVE` membership walk with `UNION ALL`.
- Both direct and recursive `pg_auth_members` joins.
- A role-path cycle guard.
- Per-edge INHERIT and SET options.
- All three distinct `pg_has_role` effective checks: MEMBER, USAGE and SET.
- Privileged granted-role attributes, including superuser and BYPASSRLS.

### Negative regression fixtures

The verifier mutates copies of the extracted SQL and asserts that each weakened fixture is rejected:

1. Missing function-owner identity (`procedure.proowner` output).
2. Missing explicit function ACL evidence (`procedure.proacl` output).
3. Missing recursive membership traversal (`WITH RECURSIVE`).
4. Missing effective SET ROLE privilege evaluation (`pg_has_role(..., 'SET')`).

The original extracted blocks are validated before the negative fixtures. The fixtures do not edit the audit document, execute SQL, or alter a migration.

## Verification boundary

These checks are lexical/source-structural assertions. They prove that the audit packet currently contains the required SQL constructs and that removal of each required construct causes the verifier to fail. They do **not** parse SQL with PostgreSQL, prove query semantics, execute Query 8A/8B, establish catalog visibility, or verify Production owner identities.

Query 8A and Query 8B remain SELECT-only prepared audit queries. Their actual execution requires the approved Production DBA read-only identity and must be recorded in the restricted evidence location.

## Authoritative ownership approval check

The authorized DeedLight repository evidence inspected for this cycle includes:

- `docs/PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md` — Query 8A/8B and the Cycle 363 DBA collection/approval procedure.
- `docs/PR22_SECURITY_REVIEW_CYCLE_362.md` — explicit P0 ownership-attestation blocker and requirement for Production owner/DBA evidence.
- `docs/PR22_INDEPENDENT_REVIEWER_AVAILABILITY.md` — formal independent-review status.
- PR #22 metadata, conversation comments and submitted-review records.

No authoritative Production DBA evidence, Query 8A/8B result, approved per-signature owner mapping, or owner-role membership approval was found in these inspected project records. The formal submitted-review list is empty; PR conversation comments contain no owner-attestation evidence. This is a statement about the inspected authorized project evidence, not a claim that no such evidence could exist outside it.

**No owner names or mappings are inferred.** CI, SQL Editor source, migration-runner identity, and disposable PostgreSQL ownership are not Production authority.

## Required DBA dependency remains unchanged

The Production owner/DBA must independently verify project reference `xaipiovflxomcbfwtwmu`, provide the enforced read-only least-privilege audit identity, execute Query 8A and 8B on the exact Production project, preserve raw results in the restricted evidence location, and explicitly approve the expected owner mapping and acceptable role/membership paths for all 18 signatures. An independent database/security reviewer must review that owner contract before any expected-owner migration check or owner-drift fixture is implemented.

Until then:

- Ownership attestation remains BLOCKED.
- Do not guess or hardcode a Production owner.
- Do not weaken or rewrite migration 038 or any historical migration.
- Do not perform Production database operations or deployments.
- PR #22 remains OPEN and DRAFT; do not merge or approve it.

## Changed files in this cycle

- `scripts/verify-delivery-provider-webhooks.mjs` — extract and independently validate Query 8A/8B SQL fences; preserve exact 18-function inventory; add four negative fixtures.
- `docs/PR22_OWNERSHIP_AUDIT_VERIFIER_CYCLE_370.md` — this evidence and handover record.

Exact-head CI evidence is added after the branch-push workflow completes.
