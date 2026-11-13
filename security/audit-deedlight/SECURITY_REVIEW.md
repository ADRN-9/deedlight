# DeedLight Cycle 16 — independent static security review memorandum

Scope: audited SQL in `audited/00_preflight.sql` and `audited/01_catalog_audit.sql` only. Candidate delivery source SHA: `c983e2ed8b93c935139c935343261570ecea6978`. **Static review is not PostgreSQL execution.**

## Exact SQL operations reviewed

- Both scripts start `BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY`, set a transaction-scoped statement timeout and end `ROLLBACK`. SQL execution must use `psql -X -v ON_ERROR_STOP=1` to stop on any failure.
- `00_preflight.sql` uses built-in JSON construction, transaction/version/database settings, `has_table_privilege`, and existence lookups for required schemas/roles; no queries on application tables.
- `01_catalog_audit.sql` reads only `pg_catalog.pg_namespace`, `pg_catalog.pg_class`, `pg_catalog.pg_attribute`, `pg_catalog.pg_constraint`, `pg_catalog.pg_policy`, `pg_catalog.pg_proc`, `pg_catalog.pg_language`, and CTE-derived rows. `pg_catalog.unnest` expands **constraint key metadata**, not table contents.
- Other built-ins used for metadata only include `to_regclass`, `to_regprocedure`, `to_regrole`, `to_regnamespace`, `format_type`, `pg_get_expr`, `pg_get_constraintdef`, `obj_description`, `has_function_privilege`, `has_table_privilege`, `has_schema_privilege`, `array_agg`, `md5`, `jsonb_build_object`, `current_database` and `current_setting`. **No application-defined function is invoked**: its definition is hashed through `pg_proc.prosrc`.
- No `FROM`/`JOIN` references to `public.*`, `auth.*` or `supabase_migrations.*` data tables. Those names occur as **string literals used for catalog lookup** only. No member, delivery-ledger or migration-history rows are read. No provider metadata, token, email, or user-generated content is selected.
- No DML/DDL, `COPY`, filesystem reads, SECURITY DEFINER creation/execution, role switching, secret lookup or external calls appear in these audit SQL files. **The separate disposable fixture runner intentionally uses DDL/DML solely in a throwaway synthetic database** and must never be run against Production.
- Returned strings contain expected function signatures, object names and fixed source SHA, with booleans, metadata counts, or MD5 digests. Raw function bodies, policy expressions, CHECK expressions and customer information are not emitted.

## Audit accuracy/limits

- All checks refer to **current** catalogs. Historical migration execution order cannot be established from object existence; `migration_history:recorded_versions` deliberately stays `UNKNOWN` because the audit never queries history rows.
- `migration_023:pre_024_exact_function_contract` is intentionally `UNKNOWN` after a healthy 024 install: 024 replaces Weekly and removes the old transport function. The current final functions are assessed separately against the reviewed 024 digest manifest.
- MD5 is an accidental-change indicator, **not adversarial authentication**. Raw `pg_proc.prosrc` is read within SQL to compute a digest, but it is not returned to the caller; database administrators can spoof it.
- Policy definitions and CHECK constraint expressions are hashed but not marked safe from digest presence. Policy inventory remains `UNKNOWN` until an independently reviewed, PostgreSQL-version-aware manifest is available. In addition, relation RLS enabled by itself is **not** sufficient evidence of correct policies.
- `has_function_privilege` reports effective EXECUTE grants, not a full end-to-end proof of network/database routing, `service_role` authenticity or RLS safety. The revised audit also inspects schema USAGE for service_role. Function validity and behavior still require separate tests.
- `metadata_access_preflight=VERIFIED` is only metadata readability; Production Supabase project identity must come from an **authorized independent attestation** and remains `BLOCKED` in SQL. Database name alone proves nothing.
- If permissions prevent reading required catalog objects, SQL must stop and report `BLOCKED`; **never** elevate the audit role. If expected object metadata is visibly absent, use `FAILED`, not `BLOCKED` (corrected for missing RPC and ledger).
- Using a connection tunneled to Production at localhost would undermine the fixture-runner host guard. Reviewers must **independently verify that the local server is disposable** and provide explicit fixture-destruction acknowledgment.

## Original-vs-audited corrections (proposed, PostgreSQL NOT RUN)

1. Missing recipient-bound RPC with available role metadata now produces `rpc_acl:...=FAILED` rather than `BLOCKED`.
2. Missing delivery ledger with available role metadata now produces `table_acl:...=FAILED` rather than `BLOCKED`.
3. Primary-key result contains an actual `matching_constraint_present` boolean instead of only the claimed column name.
4. Explicit `policy_inventory:*` records every expected public relation, including zero policy rows, without pretending to validate the policies.
5. Explicit `rpc_schema_usage:public` checks the effective service-role schema USAGE precondition.

These changes are locally available only, uncommitted, unreviewed and not PostgreSQL-tested. The original six-file artifact remains byte-for-byte unchanged in `original/`.
