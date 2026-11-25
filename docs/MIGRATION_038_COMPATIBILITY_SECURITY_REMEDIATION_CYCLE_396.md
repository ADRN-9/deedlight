# Migration 038 compatibility authorization hardening — Cycle 396

**Repository:** ADRN-9/deedlight  
**PR:** #22 — must remain OPEN / DRAFT / UNMERGED  
**Candidate base:** `e858f48b325a36f2135d6262f501e5462eea6c17`  
**PR base:** `6a3660bbe2fd6beb2ddada43d5e77ff5ac9f3793`

## Defects addressed

### 1. Function-owner SET ROLE authorization

Both preflight and postflight enumerate non-superuser roles and reject any role for which PostgreSQL 16 reports `pg_has_role(member_oid, actual_function_owner_oid, 'SET')`. PostgreSQL evaluates the effective membership graph, including transitive membership and SET-only edges. The check uses the actual `pg_proc.proowner`; it does not assume a Production owner or a disposable owner is authoritative.

The preflight error is `rejected unauthorized SET ROLE membership to the is_admin() owner`. Postflight has a distinct error so a membership change injected after CREATE OR REPLACE cannot pass unnoticed.

### 2. service_role effective EXECUTE

The bridge now requires `has_function_privilege('service_role', public.is_admin(), 'EXECUTE')` in both preflight and postflight, matching immutable Migration 038's reviewed public execution contract. A direct service_role ACL entry is accepted when present. An existing PUBLIC/default-ACL grant or effective inherited membership may also supply the privilege; the bridge does not add, revoke, or normalize PUBLIC/default ACLs.

When PUBLIC is absent, the unexpected effective-privilege guard treats service_role as an explicitly allowed application role, while rejecting unrelated effective EXECUTE and SET ROLE paths into anon, authenticated, or service_role. Direct ACL grantor checks, owner ACL snapshots, default ACL snapshots, and exact postflight ACL equality remain enforced.

## PostgreSQL 16 regression fixtures

The aggregate PostgreSQL 16 test now includes:

- A non-superuser synthetic function owner.
- An unexpected role with `INHERIT FALSE, SET TRUE` membership to that owner. Preflight must reject it and preserve the function source, owner, ACL, and configuration.
- An event trigger that adds that SET-only membership after function replacement. Postflight must reject it; transaction rollback must restore the function and remove the injected membership.
- Missing service_role EXECUTE with PUBLIC absent. Preflight must reject it and preserve the function.
- A service_role effective privilege supplied through membership in anon while no direct service_role ACL exists. A test-only event trigger removes that membership after replacement; postflight must reject the lost effective privilege even though the function ACL snapshot is unchanged. Rollback restores the membership and effective execution.
- A successful PostgreSQL 16 fixture with PUBLIC EXECUTE revoked and explicit, owner-granted EXECUTE entries for anon, authenticated, and service_role. The bridge must complete without widening the ACL, and all three roles must retain effective EXECUTE.
- An event trigger that adds both direct and transitive SET-only membership paths to service_role after function replacement. Postflight must reject the new paths independently of PUBLIC EXECUTE state. The regression verifies both paths existed during the event-trigger transaction and that rollback restores function source, owner OID/name, ACL, configuration, and removes both membership paths.
- Existing direct/inherited privilege, fingerprint, canonical no-op, unknown fingerprint, suspension NOT NULL, SECURITY DEFINER/search_path, administrator authorization, and post-replacement atomic rollback tests.

All synthetic roles, memberships, and event triggers are confined to the disposable PostgreSQL 16 test database. No permanent failure switch or test-only Production SQL was added.

## Immutable migration and aggregate constraints

The two historical Migration 007 files and Migrations 036–038 remain byte-identical. The SQL Editor aggregate must retain one compatibility block at the existing placement immediately after Migration 037 and before Migration 038. Its compatibility artifact pin is regenerated from the exact bridge blob.

## Production boundary

Production remains **NO-GO**. This work proves authorization behavior in disposable PostgreSQL only. It does not approve the live function owner or any Production membership path. Independent DBA/security acceptance still requires complete authoritative Query 8A/8B output, exact Production owner identity and attributes, complete direct/transitive membership evidence including INHERIT/SET, and Production ACL/default-ACL approval.

No Production SQL, Production migration history, deployment, merge, or PR retargeting is authorized or performed.
