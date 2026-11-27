#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:?PGHOST must be set}"
: "${PGDATABASE:?PGDATABASE must be set}"
: "${PGUSER:?PGUSER must be set}"
: "${DEEDLIGHT_EXPECTED_SERVER_ADDR:?CI must pin the disposable PostgreSQL service address}"
: "${DEEDLIGHT_DISPOSABLE_FIXTURE_AUTHORIZATION:?disposable fixture authorization marker required}"

[[ "$PGHOST" == "127.0.0.1" ]]
[[ "$PGPORT" == "5432" ]]
[[ "$PGDATABASE" == "deedlight_ledger_test" ]]
[[ "$PGUSER" == "postgres" ]]
[[ "$DEEDLIGHT_DISPOSABLE_FIXTURE_AUTHORIZATION" == "deedlight-postgres16-ci-disposable-v1" ]]
[[ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]
[[ -z "${SUPABASE_DB_PASSWORD:-}" ]]
[[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]
[[ -z "${RESEND_API_KEY:-}" ]]

clean_psql() {
  env -i PATH="$PATH" HOME="${HOME:-/tmp}" PGPASSWORD=postgres \
    PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=deedlight_ledger_test \
    PGSSLMODE=disable psql --no-psqlrc --set ON_ERROR_STOP=1 "$@"
}

actual_addr="$(clean_psql --tuples-only --no-align --command \
  "SELECT pg_catalog.host(pg_catalog.inet_server_addr())")"
[[ "$actual_addr" == "$DEEDLIGHT_EXPECTED_SERVER_ADDR" ]] || {
  echo "FAIL: PostgreSQL server address does not match pinned disposable service" >&2
  exit 1
}

clean_psql --file scripts/fixtures/migration-execution-ledger-v1.sql
clean_psql --file scripts/fixtures/test-migration-execution-ledger-v1.sql

# Kill a live PostgreSQL client while its migration-effect transaction is open.
# The database rolls back the uncommitted effect; the separately committed ledger
# reservation survives and is conservatively recovered as UNKNOWN.
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
before_crash_effects="$(clean_psql --tuples-only --no-align --command \
  "SELECT count(*) FROM deedlight_execution_ledger.test_effects")"
set +e
env -i PATH="$PATH" HOME="${HOME:-/tmp}" PGPASSWORD=postgres \
  PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=deedlight_ledger_test \
  PGSSLMODE=disable psql --no-psqlrc --set ON_ERROR_STOP=1 --command "
    BEGIN;
    SET LOCAL ROLE deedlight_ledger_runner;
    INSERT INTO deedlight_execution_ledger.test_effects(effect_value) VALUES ('uncommitted crash effect');
    SELECT pg_catalog.pg_sleep(30);
    COMMIT;
  " >"$tmp_dir/crash.log" 2>&1 &
crash_pid=$!
sleep 0.5
kill -9 "$crash_pid" 2>/dev/null
wait "$crash_pid"
crash_status=$?
set -e
if [[ "$crash_status" -eq 0 ]]; then
  echo "FAIL: migration client did not terminate during the open transaction" >&2
  exit 1
fi
sleep 0.25
clean_psql --command "
  SET ROLE deedlight_ledger_recovery;
  SELECT deedlight_execution_ledger.recover_stale_executions(interval '1 microsecond');
  RESET ROLE;
"
after_crash_effects="$(clean_psql --tuples-only --no-align --command \
  "SELECT count(*) FROM deedlight_execution_ledger.test_effects")"
crash_outcome="$(clean_psql --tuples-only --no-align --command \
  "SELECT status FROM deedlight_execution_ledger.executions WHERE execution_id = 'c5700000-0000-4000-8000-000000000027'")"
[[ "$after_crash_effects" == "$before_crash_effects" ]]
[[ "$crash_outcome" == "unknown" ]]

# Two independent sessions race for one approved execution. Row locking and the
# one-time approval consumption must permit exactly one reservation.
clean_psql --command "
  SET ROLE deedlight_ledger_approver;
  SELECT deedlight_execution_ledger.approve_execution(
    'c5770000-0000-4000-8000-000000000001',
    'c5770000-0000-4000-8000-000000000011',
    'c5770000-0000-4000-8000-000000000021',
    '{\"path\":\"supabase/migrations/concurrent-test.sql\",\"sha256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"}'::jsonb
  );
  RESET ROLE;
"

race_sql="
  BEGIN;
  SELECT pg_catalog.pg_sleep(0.25);
  SET LOCAL ROLE deedlight_ledger_runner;
  SELECT deedlight_execution_ledger.reserve_execution(
    'c5770000-0000-4000-8000-000000000001',
    'c5770000-0000-4000-8000-000000000011',
    'c5770000-0000-4000-8000-000000000021',
    '{\"path\":\"supabase/migrations/concurrent-test.sql\",\"sha256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"}'::jsonb
  );
  COMMIT;
"

set +e
clean_psql --command "$race_sql" >"$tmp_dir/race-a.log" 2>&1 &
pid_a=$!
clean_psql --command "$race_sql" >"$tmp_dir/race-b.log" 2>&1 &
pid_b=$!
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e

successes=0
[[ "$status_a" -eq 0 ]] && successes=$((successes + 1))
[[ "$status_b" -eq 0 ]] && successes=$((successes + 1))
if [[ "$successes" -ne 1 ]]; then
  cat "$tmp_dir/race-a.log" "$tmp_dir/race-b.log"
  echo "FAIL: concurrent duplicate reservation did not produce exactly one winner" >&2
  exit 1
fi

clean_psql --command "
  DO \$assert\$
  BEGIN
    IF (SELECT count(*) FROM deedlight_execution_ledger.executions
        WHERE execution_id = 'c5770000-0000-4000-8000-000000000021') <> 1 THEN
      RAISE EXCEPTION 'concurrent reservation produced an incorrect ledger cardinality';
    END IF;
  END
  \$assert\$;
  SET ROLE deedlight_ledger_recovery;
  SELECT deedlight_execution_ledger.recover_stale_executions(interval '1 microsecond');
  RESET ROLE;
"

echo "C577 disposable PostgreSQL 16 execution ledger and concurrent replay tests: PASS"
