# DeedLight — metadata-only delivery schema audit

**Scope:** independently reviewable catalog-only inspection of the reviewed delivery-security code at source commit `c983e2ed8b93c935139c935343261570ecea6978` (PR #10). This audit tooling lives on its own branch and **does not approve, merge, deploy, or run** any Production change.

The audit SQL is `audited/00_preflight.sql` and `audited/01_catalog_audit.sql`. The source's original Cycle 14 six-file package is retained unchanged in `original/`. `audit_corrections.diff` explains the Cycle 16 accuracy corrections. `SECURITY_REVIEW.md` and `fixture_execution_matrix.md` state independent review, privacy boundaries and expected results. `MANIFEST.sha256` records the exact file-level bytes. The active workflow is `.github/workflows/deedlight-audit-fixtures.yml`; `proposed_ci.yml` mirrors that workflow for review.

## Scope and interpretation

- Audit SELECTs only read `pg_catalog` metadata, using a `READ ONLY` transaction and `ROLLBACK`. **No customer, ledger, migration-history, provider or credential rows are selected.**
- Checks inspect current schema, RLS enablement, constraint and policy inventory, `SECURITY DEFINER`, stored-function MD5 bodies, effective privileges, final three-argument transport RPC and absence of the legacy two-argument RPC.
- MD5 detects accidental source drift; it is **not** a malicious-change authenticity guarantee. Policy expressions and historical migration execution are **UNKNOWN** without separately approved evidence.
- A correctly installed 024 replaces some intermediate 023 functions and removes the old transport overload. Therefore `migration_023:pre_024_exact_function_contract=UNKNOWN` is expected after 024; final contracts are tested independently.
- Catalog metadata cannot prove Supabase project identity. Target `xaipiovflxomcbfwtwmu` requires independent operator attestation and explicit catalog-only authorization before *any* Production inspection. `migration_history:recorded_versions=UNKNOWN` because history rows are deliberately not queried.
- Browser role EXECUTE grants, unsafe search paths, missing RLS and drift must produce `FAILED`; inaccessible metadata is `BLOCKED`. Never turn an unexpected PostgreSQL error into an expected negative test.

## Reproduce disposable fixtures — PostgreSQL 16 only

Use the separate GitHub Actions workflow in `.github/workflows/deedlight-audit-fixtures.yml`. It starts a fresh `postgres:16` service, refuses Production configuration, checks out the exact reviewed DeedLight commit, runs offline checks and ten synthetic PostgreSQL scenarios.

**Runner safety restriction (Cycle 20):** mutating fixtures run only in the dedicated GitHub Actions job, with the exact DeedLight repository and audit branch identity, an explicit disposable acknowledgment, a single local Docker `postgres:16` service container publishing port 5432, and no unexpected libpq connection overrides. An SSH tunnel, a bare localhost port, or a manual Postgres instance is **not sufficient**. For independent reproduction, use the workflow in an approved audit branch; do not bypass its guards.

```bash
python3 security/audit-deedlight/original/check_package_static.py
python3 security/audit-deedlight/audited/check_package_static.py
python3 -m unittest discover -s security/audit-deedlight/tests -v
# Within the dedicated approved CI job only:
# for case in A B C D E F G H I J; do bash security/audit-deedlight/run_disposable_fixture.sh "$case"; done
```

The checker validates every evidence record against `audited/audit_record.schema.json`, requires all 82 pinned deterministic invariants in `invariant_inventory.json`, rejects duplicate or malformed/truncated output, and permits only documented UNKNOWN policy-row additions. Every intentionally FAILED security exception in fixtures B/C is explicitly enumerated in `fixture_expectations.json`. The full-schema fixture A cannot pass with an unexpectedly missing, FAILED or BLOCKED record.

**Preference setter assurance:** `function:public.set_daily_reminder_preference(...)` verifies metadata and effective authorization only; `function_source:public.set_daily_reminder_preference(...)` is explicitly `UNKNOWN`. SECURITY DEFINER and search_path alone do not verify source/behavioral correspondence.

`run_disposable_fixture.sh` performs **DDL/DML and database deletion only against its isolated synthetic database**. Never run that script against a connected or ambiguous Production target. This is test-only code; the SQL audit itself remains read-only.

## Review and release STOP gates

Independent Reviewer must confirm workflow run ID, exact audit branch commit, PostgreSQL version, all ten fixture results and sanitized logs. Unexpected SQL errors, missing JSON records, missing constraints or permission checks, unreviewed SQL edits, different source SHA, wrong project identity, or any uncertain target must STOP. The project has an outstanding Cycle 12 authorization-provenance discrepancy and an earlier HOLD accounting discrepancy; neither is closed by this test package.

The production migration history is historically unreconciled. No Production `supabase db push`, history repair, privileged connection, Worker deploy, Cron activation, outbound delivery, PR #10 merge or issue closure is authorized by this audit tooling.
