# Migration 038 compatibility security remediation — Cycle 394

**Repository:** ADRN-9/deedlight  
**PR:** #22 — OPEN / DRAFT / UNMERGED  
**Base:** PR #10 head `6a3660bbe2fd6beb2ddada43d5e77ff5ac9f3793`  
**Starting candidate:** `9fea779d4748a46e36fb98644b14d9e18319c0bc`

## Scope and safety

This remediation changes only the disposable-testable Migration 038 compatibility bridge, its deterministic aggregate pin/output, and the existing PostgreSQL 16 aggregate test. It does not modify any numbered migration, Production database, migration history, deployment, or PR target.

The Production function-owner identity is intentionally not hardcoded. The bridge resolves the existing owner OID and role name and verifies that both remain identical after replacement. This proves preservation, not authorization. Production acceptance remains BLOCKED until the authorized DBA supplies complete Query 8A/8B evidence for the exact Production project and the DBA/security owners approve the per-signature owner mapping, role attributes, and permitted membership graph. A disposable PostgreSQL role is not evidence of Production ownership.

## Ownership enforcement boundary

The bridge rejects an unresolved owner before changing the function. It captures the exact existing owner OID and role name in transaction-local settings, then compares both after replacement. A canonical no-op also passes through the same owner and security-context checks.

The owner-preservation behavior is exercised in PostgreSQL 16 by an event-trigger fixture that changes the function owner after CREATE OR REPLACE. The bridge must fail its postflight owner comparison, and the surrounding transaction must restore the original owner, function body, ACL, and proconfig. The synthetic owner exists only in the disposable test database.

This does not assert that the existing Production owner is approved. Query 8A/8B and the protected approval workflow remain the authority for that decision.

## ACL contract

Historical Sprint 6 migration `202607260007_sprint6_daily_deedlight.sql` explicitly grants EXECUTE on `public.is_admin()` to `anon` and `authenticated`. The migration does not issue an explicit PUBLIC revoke or a service_role grant. PostgreSQL's effective default function ACL may therefore include PUBLIC EXECUTE depending on the creator's default ACL.

The bridge enforces the following without normalizing or revoking existing privileges:

- Effective ACL is expanded using `COALESCE(proacl, acldefault('f', proowner))`, so NULL `proacl` is not mistaken for no privileges.
- Explicit EXECUTE for `anon` and `authenticated` is required, matching the historical migration.
- PUBLIC EXECUTE is accepted only if it is already present in the effective ACL; it is neither added nor removed.
- No other explicit grantee, non-EXECUTE privilege, grant option, or non-owner grantor is accepted.
- If PUBLIC EXECUTE is absent, all non-superuser roles are checked with `has_function_privilege`; unexpected effective EXECUTE through role membership fails closed. Superusers are excluded from this membership-derived test because their catalog privilege bypass is not an ACL grant.
- Owner-scoped global and public-schema function default ACL entries are captured and compared before/after. Default ACLs do not retroactively grant privileges on this existing function; the effective function ACL remains the authority for this object.
- The canonical, ordered ACL snapshot and default-ACL snapshot must be identical after replacement. The bridge does not issue GRANT or REVOKE.

The ACL contract deliberately preserves the existing PUBLIC state rather than assuming that all environments share the same PostgreSQL default ACL configuration. Production acceptance still requires review of the live Query 8A/8B and default-ACL evidence, including any environment-specific role memberships.

## Idempotency and fingerprints

Only two source fingerprints are accepted:

- Exact historical Sprint 6 source: `4fb49052b2e525d8b355123d430df7e536a4da5207fd6ef3d21f3b2d770e98e0`.
- Exact canonical Migration 038 source: `85e6838cf8feec05bcfe9e9051e5192bc8f0d42f7a53cb6c0450067d70bba74b`.

The historical source is replaced using a dynamically assembled DDL statement whose function body preserves the exact canonical source bytes. The canonical fingerprint takes a verified no-op path. Unknown definitions, altered SECURITY DEFINER state, changed search_path, missing suspension NOT NULL, NULL suspension values, ACL drift, owner drift, and effective inherited-grant drift fail closed.

## PostgreSQL 16 regression coverage

The existing aggregate job now additionally covers:

1. Unexpected direct EXECUTE grant to a synthetic role is rejected.
2. Unexpected inherited EXECUTE via membership in `authenticated` is rejected when PUBLIC EXECUTE is absent.
3. Canonical Migration 038 re-execution succeeds without changing source, owner, ACL, or configuration.
4. A test-only `ddl_command_end` event trigger raises after CREATE OR REPLACE; the failed transaction must restore the original function body, owner, ACL, and configuration.
5. A separate test-only event trigger changes the owner after replacement; postflight must reject the owner drift and rollback the change and replacement.
6. A valid historical replacement preserves the exact pre-existing owner identity.

Both event triggers and their functions are created and removed only by `scripts/test-migration-aggregate-postgres.sh` in the disposable PostgreSQL service. No failure switch or test trigger is present in Production SQL.

The aggregate continues to execute all 39 historical migration files, seed, compatibility bridge, and Migration 038. Existing authorization, suspension, fingerprint, and aggregate inventory checks remain in place.

## Protected historical files

The two Migration 007 files and Migrations 036–038 must remain byte-identical. This remediation does not edit any of those files.

## Production acceptance dependencies — BLOCKED

- Authorized read-only access to DeedLight Production project `xaipiovflxomcbfwtwmu`.
- Complete, immutable Query 8A output for all 18 SECURITY DEFINER signatures.
- Complete Query 8B direct/transitive owner-membership graph, including INHERIT/SET edges and effective MEMBER/USAGE/SET values.
- DBA/security approval of the exact per-signature owner map, role attributes, and allowed membership paths.
- Production ACL/default-ACL review and approval for `public.is_admin()`, including PUBLIC, direct grants, grantors, inherited privileges, and any service-role expectations.

No Production SQL, ownership mutation, ACL mutation, migration-history repair, deployment, merge, or PR retargeting is authorized or performed by this remediation.
