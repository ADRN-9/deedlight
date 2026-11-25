#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:=127.0.0.1}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${PGPASSWORD:=postgres}"
: "${PGDATABASE:=deedlight_migration_order_test}"
export PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE

tmp_dir="$(mktemp -d)"
lock_pid=""
cleanup() {
  if [[ -n "${lock_pid}" ]]; then
    wait "${lock_pid}" 2>/dev/null || true
  fi
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

psql -X -v ON_ERROR_STOP=1 --file scripts/test-production-migration-readonly-audit-postgres16-fixture.sql

run_audit() {
  local role="$1"
  local project_ref="${2:-xaipiovflxomcbfwtwmu}"
  local repository_sha="${3:-0123456789abcdef0123456789abcdef01234567}"
  psql -X -v ON_ERROR_STOP=1 <<SQL
SET ROLE ${role};
SET deedlight.expected_project_ref = '${project_ref}';
SET deedlight.repository_sha = '${repository_sha}';
\i scripts/production-migration-readonly-audit.sql
SELECT 'AUDIT_TRANSACTION_ROLLED_BACK' AS audit_rollback_check
WHERE current_setting('transaction_read_only') = 'off';
SQL
}

expect_failure() {
  local name="$1"
  local role="$2"
  local expected="$3"
  local project_ref="${4:-xaipiovflxomcbfwtwmu}"
  local repository_sha="${5:-0123456789abcdef0123456789abcdef01234567}"
  if run_audit "${role}" "${project_ref}" "${repository_sha}" >"${tmp_dir}/${name}.log" 2>&1; then
    echo "FAIL: ${name} unexpectedly succeeded" >&2
    exit 1
  fi
  if ! grep -Fq "${expected}" "${tmp_dir}/${name}.log"; then
    cat "${tmp_dir}/${name}.log" >&2
    echo "FAIL: ${name} did not fail for the expected reason" >&2
    exit 1
  fi
  echo "PASS: ${name}"
}

run_audit deedlight_audit_approved >"${tmp_dir}/approved.log"
grep -Fq "audit_fixture_sequence" "${tmp_dir}/approved.log"
grep -Fq "AUDIT_TRANSACTION_ROLLED_BACK" "${tmp_dir}/approved.log"
echo "PASS: approved collector completes full PostgreSQL 16 audit and rolls back"

expect_failure privileged_predefined_role deedlight_audit_bad_membership "Collector role has role membership"
expect_failure missing_migration_history_select deedlight_audit_missing_history "Collector must have SELECT-only access"
expect_failure missing_catalog_select deedlight_audit_missing_catalog "Required catalog SELECT access unavailable"
expect_failure application_table_select deedlight_audit_app_table "prohibited SELECT access to application relation"
expect_failure application_column_select deedlight_audit_app_column "prohibited column-level SELECT access"
expect_failure application_sequence_usage deedlight_audit_app_sequence "prohibited USAGE access to application sequence"
expect_failure invalid_project_metadata deedlight_audit_approved "Missing or unexpected DeedLight Production project reference" "wrong-project"
expect_failure invalid_repository_metadata deedlight_audit_approved "Exact repository SHA is required" "xaipiovflxomcbfwtwmu" "not-a-git-sha"

# Lock the history table so the actual audit query is interrupted by its 5s lock timeout.
psql -X -v ON_ERROR_STOP=1 -c "BEGIN; LOCK TABLE supabase_migrations.schema_migrations IN ACCESS EXCLUSIVE MODE; SELECT pg_sleep(8); COMMIT;" >"${tmp_dir}/locker.log" 2>&1 &
lock_pid="$!"
sleep 1
expect_failure interrupted_history_read deedlight_audit_approved "lock timeout"
wait "${lock_pid}"
lock_pid=""

# Simulate a client disconnect while the same read-only transaction envelope is open.
set +e
PGAPPNAME=deedlight_audit_interrupted timeout 2s psql -X -v ON_ERROR_STOP=1 \
  -c "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY; SELECT pg_sleep(20); ROLLBACK;" \
  >"${tmp_dir}/interrupted.log" 2>&1
interrupt_status=$?
set -e
test "${interrupt_status}" -eq 124
sleep 1
remaining="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM pg_catalog.pg_stat_activity WHERE application_name = 'deedlight_audit_interrupted'")"
test "${remaining}" = "0"
echo "PASS: interrupted read-only client disconnect leaves no active transaction"

echo "PASS: all PostgreSQL 16 production-migration-audit fixtures"
