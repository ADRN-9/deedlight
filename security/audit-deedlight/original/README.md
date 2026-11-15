# DeedLight Cycle 14 retry — catalog-only schema audit design

**Status:** DESIGN PREPARED; new SQL execution **NOT RUN**. This package is an offline audit design, not Production authorization. No GitHub source, PR, Supabase or Cloudflare state is changed.

- Repository: `ADRN-9/deedlight`
- Reviewed PR #10 source SHA: `c983e2ed8b93c935139c935343261570ecea6978`
- Main at inspection: `ce82b3fdf1a73510de70e3729a487d4ae00e66e3`
- Expected Production Supabase project reference: `xaipiovflxomcbfwtwmu`
- GitHub source references: `supabase/migrations/202609230019_sprint12_2_gentle_delivery_foundation.sql`, `202609230020_delivery_reliability_hardening.sql`, `202609230021_gentle_delivery_transport.sql`, `202609240022_auth_pgcrypto_schema_qualification.sql`, `202611120023_delivery_consent_linearization.sql`, `202611120024_delivery_identity_lease_capacity.sql`.

## Package contents

| File | Exact purpose |
|---|---|
| `00_preflight.sql` | PostgreSQL version/database name; catalog SELECT capability; required role and schema metadata. `BLOCKED` on missing prerequisites. It **does not** prove Supabase project identity. |
| `01_catalog_audit.sql` | Read-only, single-snapshot PostgreSQL catalogs: relations, columns and types, named constraints and unique logical key, RLS, sanitized policy/constraint fingerprints, exact function signatures/body hashes/definer/path/volatility/language, effective RPC/table grants, migration 023 prerequisite, migration 024 target, missing legacy transport, migration-history table *existence* and unknown contents. |
| `audit_record.schema.json` | Consumer schema: `VERIFIED`, `FAILED`, `BLOCKED`, `UNKNOWN`; source SHA; expected contract and sanitized actual metadata. |
| `fixture_test_plan.md` | Six disposable fixture scenarios and negative/STOP outcomes; no Production procedures. |

## Execution authorization and STOP boundary

**Current scope does not authorize execution against Production.** For a future operator-approved inspection, first independently verify the Supabase account/project using a trusted project-management resource, connection endpoint or mutually authenticated server record, not `current_database()` or the expected ref embedded in this package. Audit identity must be signed off separately.

Minimum capability for future inspection: metadata-only `CONNECT` to the approved database; `SELECT` on the required `pg_catalog` system catalogs; use of built-in `to_regclass`, `to_regprocedure`, `to_regrole`, `pg_get_expr`, `pg_get_constraintdef`, `has_function_privilege`, `has_table_privilege`, `md5`, and `format_type`. The query role **must not** require `service_role`, `BYPASSRLS`, ownership of customer tables, or `SELECT` on `public`/`auth` customer data. Visibility of `pg_proc.prosrc` is needed internally to compute hashes but **raw source is never returned**.

The operator should independently review the SQL and compare its SHA against the approved artifact. Execute `00_preflight.sql` first, inspect the single output record, and **STOP unless `status=VERIFIED`**. A `VERIFIED` metadata preflight is *not* authorization to continue; execute `01_catalog_audit.sql` only with separate permission and confirmed project identity. The `BLOCKED` identity row intentionally remains in the SQL output even in a correctly connected database, until the authorized operator attaches external identity attestation. If a query raises permission errors, STOP and record `BLOCKED`; **never retry with elevated credentials**. All queries run inside `BEGIN ... READ ONLY` and end with `ROLLBACK`, with bounded statement timeouts.

For disposable synthetic PostgreSQL **only**, and after a deliberate separate test grant, a reviewer can run:

```sh
psql -X -v ON_ERROR_STOP=1 -d synthetic_deedlight -f 00_preflight.sql
# Confirm preflight VERIFIED, inspect connection identity, then:
psql -X -v ON_ERROR_STOP=1 -d synthetic_deedlight -f 01_catalog_audit.sql
```

No production host, auth token, password, personal information or account identifier other than the **public project reference** should appear in the recorded evidence. Set terminal/log capture policies to prevent leaking a connection string. Do not save database URLs with embedded credentials.

## Expected output semantics

Each result has `source_sha`, `invariant`, `status`, `expected`, `actual` (JSON-compatible object). Status means:

- `VERIFIED`: the stated *individual* invariant is confirmed by catalog metadata; **does not mean the deployment as a whole is safe**.
- `FAILED`: required current target metadata is absent, materially mismatched or privileged access differs from the reviewed contract. An expected pre-migration schema may fail post-024 checks without implying the database is broken; do not run migrations without review.
- `BLOCKED`: required inspection privilege, verified Production identity, or authorization is missing. No escalation or workaround is permitted.
- `UNKNOWN`: current catalogs cannot prove the historical assertion, or a canonical policy/constraint-definition digest has not been independently reviewed. Never convert to `VERIFIED` through guesswork.

**Important distinctions:**

1. A verified relation/column/function signature is not evidence that a particular numbered SQL migration was historically applied; live objects can predate Supabase CLI history.
2. PostgreSQL catalogs expose the *schema* of `supabase_migrations.schema_migrations` but not its recorded version rows. This catalog-only package intentionally **does not read that table**. A separately approved read-only metadata-table query may be needed to reconcile version rows; this is outside this package.
3. Migration 024 legitimately **replaces** migration 023's Weekly function body and **drops** the 023-era two-argument transport. Hence `migration_023:pre_024_exact_function_contract` is `UNKNOWN` *after* a valid 024 upgrade, while post-024 function hashes can be individually `VERIFIED`. This is intentional, not a contradiction.
4. The function body fingerprints use built-in PostgreSQL `md5(pg_proc.prosrc)` for exact source drift detection, including modifications with unchanged comments. MD5 is **not collision-resistant** and cannot prove authenticity against a malicious database administrator. Independently verify the repository commit, connection identity, privilege boundary and canonical migration execution provenance.
5. A policy or CHECK constraint appears as an **UNKNOWN** definition fingerprint until compared against a version-specific independently reviewed manifest. The package deliberately does not mark arbitrary policy text as safe solely because RLS is enabled. Never expose the raw policy expression in generalized logs.
6. `public.set_daily_reminder_preference` is member-facing and intentionally grants `authenticated` rather than `service_role` only; it is checked separately. `public.handle_new_user` is a trigger function and is checked for body/config but not erroneously classified as a service-only RPC.
7. The 019–022 source contracts and migrations 023/024 are checked against the exact PR HEAD above. The audit does not attest to a future changed HEAD without a regenerated and independently reviewed manifest.

## Independent approval and reconciliation requirements

1. Level 1/Level 2 must explicitly reconcile the **Cycle 12 delegation-provenance dispute**. A project running flag or completed-cycle counter is not a privileged operation authorization.
2. The operator must separately authorize and scope **Production database access**, and must provide a trusted external proof that the endpoint is for `xaipiovflxomcbfwtwmu`.
3. A designated security reviewer must evaluate policy/check fingerprints against a freshly built synthetic fixture on the same PostgreSQL major as Production. Check role-effective permissions and function hashes in that fixture before using this report to decide migration ordering.
4. The migration history and schema must be reconciled **object by object**. Do not blindly mark history applied, run Production `supabase db push`, grant browser roles, restore the insecure legacy transport, or activate Cron.
5. PR #10 remains a draft until independent exact-head review, current CI, branch/approval governance and separate merge authorization are satisfied. Release Issue #6 remains open.

## Pre-existing CI evidence versus new audit validation

At the unchanged candidate head, GitHub runs `43356210249` and `43356199103` report six successful jobs apiece, including PostgreSQL migration-order, transport, reliability, Sprint 12.2 and Auth tests, plus application validation. This **does not validate these new audit queries**. No PostgreSQL executable or disposable PostgreSQL service was available in the audit-design environment; query execution and all six audit-fixture scenarios below are **NOT RUN**.
