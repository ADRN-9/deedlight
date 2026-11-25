#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:=127.0.0.1}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${PGPASSWORD:=postgres}"
: "${PGDATABASE:=deedlight_migration_order_test}"
export PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE

tmp_dir="${RUNNER_TEMP:-/tmp}/deedlight-migration-audit-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
rm -rf "${tmp_dir}"
mkdir -p "${tmp_dir}"
lock_pid=""
client_pid=""
cleanup() {
  local status=$?
  if [[ -n "${client_pid}" ]]; then
    kill -KILL "${client_pid}" 2>/dev/null || true
    wait "${client_pid}" 2>/dev/null || true
  fi
  if [[ -n "${lock_pid}" ]]; then
    wait "${lock_pid}" 2>/dev/null || true
  fi
  if [[ "${status}" -ne 0 ]]; then
    echo "::group::Disposable PostgreSQL 16 migration-audit diagnostics"
    echo "Failure status: ${status}"
    for log in "${tmp_dir}"/*.log; do
      [[ -f "${log}" ]] || continue
      echo "--- ${log} ---"
      cat "${log}"
    done
    echo "Diagnostic files retained at ${tmp_dir}"
    echo "::endgroup::"
  else
    rm -rf "${tmp_dir}"
  fi
}
trap cleanup EXIT

psql -X -v ON_ERROR_STOP=1 --file scripts/test-production-migration-readonly-audit-postgres16-fixture.sql

reset_history() {
  psql -X -v ON_ERROR_STOP=1 <<'SQL'
DROP TABLE IF EXISTS supabase_migrations.schema_migrations;
CREATE TABLE supabase_migrations.schema_migrations (
  version text NOT NULL PRIMARY KEY,
  statements text[],
  name text
);
INSERT INTO supabase_migrations.schema_migrations(version, statements, name)
VALUES ('202611240038', ARRAY['SELECT 1'], 'fixture_migration');
GRANT SELECT ON supabase_migrations.schema_migrations TO deedlight_catalog_auditor;
SQL
}

run_audit() {
  local session_role="${1:-deedlight_catalog_auditor}"
  local auth_context="${2:-deedlight_catalog_auditor}"
  local project_ref="${3:-xaipiovflxomcbfwtwmu}"
  local repository_sha="${4:-0123456789abcdef0123456789abcdef01234567}"
  local role_switch="${5:-__NONE__}"
  {
    printf 'SET SESSION AUTHORIZATION %s;\n' "${session_role}"
    if [[ "${auth_context}" != "__MISSING__" ]]; then
      printf "SET deedlight.authenticated_principal = '%s';\n" "${auth_context}"
    fi
    printf "SET deedlight.expected_project_ref = '%s';\n" "${project_ref}"
    printf "SET deedlight.repository_sha = '%s';\n" "${repository_sha}"
    if [[ "${role_switch}" != "__NONE__" ]]; then
      printf 'SET ROLE %s;\n' "${role_switch}"
    fi
    printf '\\i scripts/production-migration-readonly-audit.sql\n'
    printf "SELECT 'AUDIT_TRANSACTION_ROLLED_BACK' WHERE current_setting('transaction_read_only') = 'off';\n"
  } | psql -X -v ON_ERROR_STOP=1
}

expect_failure() {
  local name="$1"
  local expected="$2"
  shift 2
  if run_audit "$@" >"${tmp_dir}/${name}.log" 2>&1; then
    echo "FAIL: ${name} unexpectedly succeeded" >&2
    cat "${tmp_dir}/${name}.log" >&2
    exit 1
  fi
  if ! grep -Fq "${expected}" "${tmp_dir}/${name}.log"; then
    cat "${tmp_dir}/${name}.log" >&2
    echo "FAIL: ${name} did not fail for the expected reason" >&2
    exit 1
  fi
  echo "PASS: ${name}"
}

expect_history_failure() {
  local name="$1"
  local expected="$2"
  if run_audit >"${tmp_dir}/${name}.log" 2>&1; then
    echo "FAIL: ${name} unexpectedly succeeded" >&2
    cat "${tmp_dir}/${name}.log" >&2
    exit 1
  fi
  if ! grep -Fq "${expected}" "${tmp_dir}/${name}.log"; then
    cat "${tmp_dir}/${name}.log" >&2
    echo "FAIL: ${name} did not fail for the expected reason" >&2
    exit 1
  fi
  echo "PASS: ${name}"
}

run_audit >"${tmp_dir}/approved.log" 2>&1
grep -Fq "audit_fixture_sequence" "${tmp_dir}/approved.log"
grep -Fq "AUDIT_TRANSACTION_ROLLED_BACK" "${tmp_dir}/approved.log"
grep -Fq '"name": "search_path"' "${tmp_dir}/approved.log"
grep -Fq '"value": "pg_catalog"' "${tmp_dir}/approved.log"
echo "PASS: approved authenticated collector, allowlisted routine metadata and rollback"

# A SECURITY DEFINER owner changes current_user but preserves the authenticated login.
definer_result="$(
  psql -X -At -v ON_ERROR_STOP=1 <<'SQL'
SET SESSION AUTHORIZATION deedlight_catalog_auditor;
SET deedlight.authenticated_principal = 'deedlight_catalog_auditor';
SELECT public.audit_fixture_security_definer_identity();
SQL
)"
test "${definer_result}" = "deedlight_audit_definer_owner:deedlight_catalog_auditor"
echo "PASS: SECURITY DEFINER preserves and validates the authenticated principal"

if psql -X -v ON_ERROR_STOP=1 >"${tmp_dir}/privileged_security_definer.log" 2>&1 <<'SQL'
SET SESSION AUTHORIZATION deedlight_catalog_auditor;
SET deedlight.authenticated_principal = 'deedlight_catalog_auditor';
SELECT public.audit_fixture_privileged_definer_identity();
SQL
then
  echo "FAIL: privileged SECURITY DEFINER owner unexpectedly passed" >&2
  exit 1
fi
grep -Fq "Fixture SECURITY DEFINER role attributes or memberships rejected" "${tmp_dir}/privileged_security_definer.log"
echo "PASS: privileged SECURITY DEFINER effective role is rejected"

expect_failure missing_auth_context "Authenticated collector principal is missing" deedlight_catalog_auditor __MISSING__
expect_failure malformed_auth_context "Authenticated collector principal is missing" deedlight_catalog_auditor "deedlight_catalog_auditor,spoofed"
expect_failure spoofed_session_authorization "Authenticated collector principal is missing" deedlight_audit_spoofed_login deedlight_catalog_auditor
expect_failure privileged_login_set_role_impersonation "Authenticated collector principal is missing" deedlight_audit_privileged_login deedlight_catalog_auditor xaipiovflxomcbfwtwmu 0123456789abcdef0123456789abcdef01234567 deedlight_catalog_auditor

# Direct SET ROLE is rejected even when the target role itself has no elevated attributes.
GRANT deedlight_audit_switch_target TO deedlight_catalog_auditor;
expect_failure direct_role_switch "SET ROLE is prohibited" deedlight_catalog_auditor deedlight_catalog_auditor xaipiovflxomcbfwtwmu 0123456789abcdef0123456789abcdef01234567 deedlight_audit_switch_target
REVOKE deedlight_audit_switch_target FROM deedlight_catalog_auditor;

# Nested and predefined-role memberships are rejected for the authenticated principal.
GRANT deedlight_audit_nested_leaf TO deedlight_audit_nested_parent;
GRANT deedlight_audit_nested_parent TO deedlight_catalog_auditor;
expect_failure nested_role_membership "Authenticated or effective collector role has role membership" 
REVOKE deedlight_audit_nested_parent FROM deedlight_catalog_auditor;
REVOKE deedlight_audit_nested_leaf FROM deedlight_audit_nested_parent;

GRANT pg_read_all_data TO deedlight_catalog_auditor;
expect_failure pg_read_all_data_membership "Authenticated or effective collector role has role membership"
REVOKE pg_read_all_data FROM deedlight_catalog_auditor;

# Authentication/authorization revocation is a hard failure, never a stronger-role fallback.
ALTER ROLE deedlight_catalog_auditor NOLOGIN;
expect_failure revoked_login_authorization "Authenticated or effective role violates the least-privilege identity contract."
ALTER ROLE deedlight_catalog_auditor LOGIN;
REVOKE SELECT ON pg_catalog.pg_class FROM deedlight_catalog_auditor;
expect_failure revoked_catalog_authorization "Required catalog SELECT access unavailable"
GRANT SELECT ON pg_catalog.pg_class TO deedlight_catalog_auditor;
REVOKE SELECT ON supabase_migrations.schema_migrations FROM deedlight_catalog_auditor;
expect_failure revoked_history_authorization "Collector must have SELECT-only access to migration history"
GRANT SELECT ON supabase_migrations.schema_migrations TO deedlight_catalog_auditor;

expect_failure invalid_project_metadata "Missing or unexpected DeedLight Production project reference." deedlight_catalog_auditor deedlight_catalog_auditor wrong-project
expect_failure invalid_repository_metadata "Exact repository SHA is required" deedlight_catalog_auditor deedlight_catalog_auditor xaipiovflxomcbfwtwmu not-a-git-sha

# Effective table, column and sequence privileges are prohibited.
GRANT SELECT ON public.audit_fixture_private TO deedlight_catalog_auditor;
expect_failure application_table_select "prohibited SELECT access to application relation"
REVOKE SELECT ON public.audit_fixture_private FROM deedlight_catalog_auditor;
GRANT SELECT (private_value) ON public.audit_fixture_private TO deedlight_catalog_auditor;
expect_failure application_column_select "prohibited column-level SELECT access"
REVOKE SELECT (private_value) ON public.audit_fixture_private FROM deedlight_catalog_auditor;
GRANT USAGE ON SEQUENCE public.audit_fixture_sequence TO deedlight_catalog_auditor;
expect_failure application_sequence_usage "prohibited USAGE access to application sequence"
REVOKE USAGE ON SEQUENCE public.audit_fixture_sequence FROM deedlight_catalog_auditor;

# Unexpected routine GUCs and unsafe values fail before any routine setting is emitted.
CREATE FUNCTION public.audit_fixture_custom_guc()
RETURNS integer LANGUAGE sql
SET deedlight.secret = 'fixture-secret-value'
AS 'SELECT 1';
expect_failure routine_custom_guc "Unexpected or unsafe routine configuration"
if grep -Fq "fixture-secret-value" "${tmp_dir}/routine_custom_guc.log"; then
  echo "FAIL: custom GUC value leaked into diagnostic output" >&2
  exit 1
fi
DROP FUNCTION public.audit_fixture_custom_guc();

CREATE FUNCTION public.audit_fixture_bad_search_path()
RETURNS integer LANGUAGE sql
SET search_path = 'public, pg_temp, auth'
AS 'SELECT 1';
expect_failure unsafe_routine_search_path "Unexpected or unsafe routine configuration"
DROP FUNCTION public.audit_fixture_bad_search_path();

# Exact migration-history schema: column names/types/nullability, constraints, indexes and row metadata.
psql -X -v ON_ERROR_STOP=1 -c "ALTER TABLE supabase_migrations.schema_migrations ADD COLUMN unexpected text"
expect_history_failure extra_history_column "Unsupported migration-history schema"
reset_history

psql -X -v ON_ERROR_STOP=1 -c "ALTER TABLE supabase_migrations.schema_migrations ALTER COLUMN statements TYPE jsonb USING to_jsonb(statements)"
expect_history_failure wrong_history_statements_type "Unsupported migration-history schema"
reset_history

psql -X -v ON_ERROR_STOP=1 -c "ALTER TABLE supabase_migrations.schema_migrations ALTER COLUMN name TYPE varchar(100)"
expect_history_failure wrong_history_name_type "Unsupported migration-history schema"
reset_history

psql -X -v ON_ERROR_STOP=1 -c "ALTER TABLE supabase_migrations.schema_migrations ALTER COLUMN version TYPE varchar(100)"
expect_history_failure wrong_history_version_type "Unsupported migration-history schema"
reset_history

psql -X -v ON_ERROR_STOP=1 -c "ALTER TABLE supabase_migrations.schema_migrations ALTER COLUMN name SET NOT NULL"
expect_history_failure wrong_history_name_nullability "Unsupported migration-history schema"
reset_history

psql -X -v ON_ERROR_STOP=1 -c "ALTER TABLE supabase_migrations.schema_migrations ALTER COLUMN statements SET NOT NULL"
expect_history_failure wrong_history_statements_nullability "Unsupported migration-history schema"
reset_history

psql -X -v ON_ERROR_STOP=1 -c "ALTER TABLE supabase_migrations.schema_migrations DROP CONSTRAINT schema_migrations_pkey; ALTER TABLE supabase_migrations.schema_migrations ALTER COLUMN version DROP NOT NULL"
expect_history_failure wrong_history_version_nullability "Unsupported migration-history schema"
reset_history

psql -X -v ON_ERROR_STOP=1 -c "ALTER TABLE supabase_migrations.schema_migrations ALTER COLUMN name SET DEFAULT 'fixture_default'"
expect_history_failure unexpected_history_default "Unsupported migration-history schema"
reset_history

psql -X -v ON_ERROR_STOP=1 -c "ALTER TABLE supabase_migrations.schema_migrations ADD CONSTRAINT audit_fixture_extra_check CHECK (version <> '')"
expect_history_failure unexpected_history_constraint "Unsupported migration-history constraints"
reset_history

psql -X -v ON_ERROR_STOP=1 -c "ALTER TABLE supabase_migrations.schema_migrations DROP CONSTRAINT schema_migrations_pkey"
expect_history_failure missing_history_primary_key "Unsupported migration-history constraints"
reset_history

psql -X -v ON_ERROR_STOP=1 -c "CREATE INDEX audit_fixture_history_name_idx ON supabase_migrations.schema_migrations(name)"
expect_history_failure unexpected_history_index "Unsupported migration-history indexes"
reset_history

psql -X -v ON_ERROR_STOP=1 -c "UPDATE supabase_migrations.schema_migrations SET version = 'not-a-version'"
expect_history_failure invalid_history_version_metadata "invalid version or migration-name metadata"
reset_history

psql -X -v ON_ERROR_STOP=1 -c "UPDATE supabase_migrations.schema_migrations SET name = 'bad name'"
expect_history_failure invalid_history_name_metadata "invalid version or migration-name metadata"
reset_history

# Lock timeout is a separate interruption/recovery scenario.
psql -X -v ON_ERROR_STOP=1 -c "BEGIN; LOCK TABLE supabase_migrations.schema_migrations IN ACCESS EXCLUSIVE MODE; SELECT pg_sleep(8); COMMIT;" >"${tmp_dir}/lock-timeout-holder.log" 2>&1 &
lock_pid="$!"
sleep 1
expect_failure migration_history_lock_timeout "lock timeout"
wait "${lock_pid}"
lock_pid=""
run_audit >"${tmp_dir}/after-lock-timeout.log" 2>&1
grep -Fq "AUDIT_TRANSACTION_ROLLED_BACK" "${tmp_dir}/after-lock-timeout.log"
echo "PASS: lock-timeout transaction abort releases locks and subsequent audit succeeds"

# Terminate a live psql client while its transaction owns a lock and an uncommitted row.
PGAPPNAME=deedlight_audit_client_termination psql -X -v ON_ERROR_STOP=1 \
  -c "BEGIN; INSERT INTO public.audit_fixture_termination_marker VALUES (1); LOCK TABLE supabase_migrations.schema_migrations IN ACCESS EXCLUSIVE MODE; SELECT pg_sleep(60); COMMIT;" \
  >"${tmp_dir}/client-termination.log" 2>&1 &
client_pid="$!"
backend_pid=""
for attempt in {1..100}; do
  backend_pid="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT pid FROM pg_catalog.pg_stat_activity WHERE application_name = 'deedlight_audit_client_termination' AND state = 'active' AND query LIKE '%pg_sleep%' LIMIT 1")"
  if [[ -n "${backend_pid}" ]]; then break; fi
  sleep 0.1
done
if [[ -z "${backend_pid}" ]]; then
  cat "${tmp_dir}/client-termination.log" >&2
  echo "FAIL: client-termination backend never became active" >&2
  exit 1
fi
kill -KILL "${client_pid}"
set +e
wait "${client_pid}"
client_status=$?
set -e
client_pid=""
test "${client_status}" -ne 0

backend_remaining="1"
for attempt in {1..100}; do
  backend_remaining="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM pg_catalog.pg_stat_activity WHERE pid = ${backend_pid}")"
  if [[ "${backend_remaining}" = "0" ]]; then break; fi
  sleep 0.1
done
test "${backend_remaining}" = "0"
marker_count="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM public.audit_fixture_termination_marker")"
test "${marker_count}" = "0"
psql -X -v ON_ERROR_STOP=1 -c "BEGIN; LOCK TABLE supabase_migrations.schema_migrations IN ACCESS EXCLUSIVE MODE NOWAIT; ROLLBACK;" >"${tmp_dir}/client-lock-release.log" 2>&1
expect_failure no_stale_authentication_context "Authenticated collector principal is missing" deedlight_catalog_auditor __MISSING__
run_audit >"${tmp_dir}/after-client-termination.log" 2>&1
grep -Fq "AUDIT_TRANSACTION_ROLLED_BACK" "${tmp_dir}/after-client-termination.log"
echo "PASS: killed client backend terminated, transaction rolled back, lock released, auth context not inherited and collector recovered"

echo "PASS: all PostgreSQL 16 production-migration-audit fixtures"
