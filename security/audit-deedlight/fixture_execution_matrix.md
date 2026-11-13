# Disposable PostgreSQL test matrix — Cycle 20 revalidation

**Historical executable evidence:** Cycle 18's audited source passed all ten PostgreSQL 16.16 fixtures in [GitHub Actions run 43430078142](https://github.com/ADRN-9/deedlight/actions/runs/43430078142). **Cycle 20 changes:** a much stricter assertion consumer, 82-record inventory, additional negative tests, and a CI-only disposable service guard. These changed bytes require their **own exact-head CI run**; earlier execution is not proof of Cycle 20 success. Pinned delivery source SHA: `c983e2ed8b93c935139c935343261570ecea6978`.

| Case | Setup (synthetic database only) | Required audited invariant result | Stop interpretation |
|---|---|---|---|
| **A — expected 019–024** | Real DeedLight synthetic 019–021 fixture, isolated Auth adapter and 022, authentic 023→024 | Final 024 transport, Daily/Weekly, RPC grants, ledger uniqueness, RLS and missing legacy `VERIFIED`; historical 023 intermediate `UNKNOWN` | Overall release NOT proven: independent identity `BLOCKED`, history and policy semantics `UNKNOWN` |
| **B — 023 absent** | Through 022, omit both 023 and 024 | `migration_023:pre_024_exact_function_contract=FAILED`; 3-arg RPC `FAILED`; legacy absence `FAILED` | STOP; cannot apply 024 blindly |
| **C — 024 absent** | Through authentic 023, omit 024 | 023 prerequisite `VERIFIED`; 3-arg transport `FAILED`; legacy absence `FAILED`; post-024 Weekly hash `FAILED` | STOP; 024 still needed after independent approval |
| **D — function body drift** | Authentic 024; synthetically change expected-email condition without changing signature or grant | 3-arg transport function hash `FAILED`, ACL remains `VERIFIED` | STOP; MD5 drift check detected a *material* change (does not prove adversarial integrity) |
| **E — browser role grant** | Authentic 024; synthetically `GRANT EXECUTE` to `anon` on 3-arg transport | `rpc_acl:...=FAILED`, observed `anon=true` | STOP; browser RPC access unsafe |
| **F — missing ledger RLS** | Authentic 024; disable ledger RLS | `rls:public.delivery_ledger=FAILED`, observed `rls_enabled=false` | STOP; privacy boundary unsafe |
| **G — incorrect search path** | Authentic 024; synthetic `ALTER FUNCTION` to `search_path=public` | Transport function `FAILED`, `path_match=false` | STOP; definer function search-path contract broken |
| **H — insufficient catalog access** | Synthetic database only; remove `pg_proc` SELECT from `PUBLIC`, run preflight as `anon` | `metadata_access_preflight=BLOCKED` **or** an independently confirmed catalog permission error | STOP before catalog audit; any other SQL error is **FAILED**, not a false permission PASS |
| **I — migration history mismatch** | Authentic 024; create *synthetic* CLI-history table with only an incomplete 019 version | `migration_history:catalog_object=VERIFIED` but recorded versions and historical execution **UNKNOWN** | STOP reconciliation; catalog-only queries do not inspect the synthetic row and **cannot prove mismatch or history completeness** |
| **J — unexpected legacy RPC** | Authentic 024; create synthetic extra 2-arg transport overload | `legacy_rpc:...=FAILED` and `legacy_rpc:unexpected_transport_overloads=FAILED` | STOP; insecure path reintroduced and pre-024 attestation deliberately FAILED in the mixed overload state |

All scenario setup SQL is fixture-only and MUST NOT be applied to Production. Case H temporarily modifies `pg_catalog` ACLs **inside a disposable database only**; never run against any other database. Case I deliberately writes mock migration-history rows **only in the synthetic fixture**; the audit SQL itself never touches those rows.

## Guardrails and operator preflight

- The mutating runner is restricted to the dedicated GitHub Actions branch workflow and verifies a single local Docker `postgres:16` container actually publishing port 5432; it refuses local manual execution and libpq override variables. A compromised workflow can still defeat safeguards; do not repurpose the runner or use a tunneled/server-shared database.
- Prepare a clean Git checkout at the exact reviewed PR head. Verify source files by SHA before use. Do not borrow another project's credentials or fixture data.
- Ensure environment contains no `DATABASE_URL`, `SUPABASE_*` secrets or provider keys. Use only test-time `PGPASSWORD` for the disposable server. `PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres` are required.
- Read the scripts and explicitly acknowledge destructive temporary database setup; the runner uses `createdb` and `dropdb` on per-case synthetic databases.
- Use `psql -X -v ON_ERROR_STOP=1`. A SQL syntax error, missing fixture feature, unexpected connection error, or incomplete output is **not PASS**.
- Required evidence: exact audit archive checksum, source SHA, `select version()` string from the disposable fixture (not yet collected), all ten scenarios, preflight and audited JSON records, stderr success/failure reason redacted, tool versions, timestamps and independent reviewer sign-off.
- Do not promote an isolated fixture's results into statements about Production. The current expected Production project `xaipiovflxomcbfwtwmu` remains a separate, unauthorized inspection boundary.

## Replay

Run the approved GitHub Actions job only, with its disposable PostgreSQL 16 service and pinned delivery source checkout. For each case, `run_disposable_fixture.sh CASE` builds a new synthetic database, runs the `audited/` SQL, invokes `assert_fixture_result.py` with `fixture_expectations.json`, then drops that database. Results are saved under `results/CASE/` unless an output directory is supplied. A nonzero exit means the case did not validate; inspect only sanitized local fixture logs.

The JSON consumer unit tests only confirm that fixture-evidence verification rejects mismatched or absent invariants. They do **not** establish the SQL schema itself works against PostgreSQL.

## Cycle 20 new evidence-negative cases

The actual `assert_fixture_result.py` CLI is invoked by unit tests using synthetic transaction envelopes to reject: missing required invariant; duplicate invariant; unexpected FAILED or BLOCKED; malformed JSON, invalid JSON schema and extra fields; missing `ROLLBACK` or truncated invariant inventory; incorrect fixture classification; unexpected PostgreSQL ERROR/FATAL output; unapproved dynamic policy failure; and unjustified VERIFIED preference source. These are **offline parser tests**, distinct from the ten live PostgreSQL fixtures.
