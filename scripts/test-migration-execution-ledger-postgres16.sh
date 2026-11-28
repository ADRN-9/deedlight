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
clean_psql --file scripts/fixtures/test-migration-execution-ledger-c585.sql
clean_psql --file scripts/fixtures/test-migration-execution-ledger-c600.sql

# Exercise a real interrupted migration transaction with a deterministic backend handshake.
# The SQL file is a single-quoted heredoc: JSON reaches PostgreSQL unchanged.
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
before_crash_effects="$(clean_psql --tuples-only --no-align --command \
  "SELECT count(*) FROM deedlight_execution_ledger.test_effects")"

cat >"$tmp_dir/crash.sql" <<'SQL'
BEGIN;
SET LOCAL ROLE deedlight_ledger_runner;
INSERT INTO deedlight_execution_ledger.test_effects(effect_value)
VALUES ('uncommitted crash effect');
SELECT deedlight_execution_ledger.record_effect_commit_marker(
  'c5700000-0000-4000-8000-000000000027',
  '{"path":"supabase/migrations/test-crash.sql","sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}'::jsonb
);
SELECT pg_catalog.pg_sleep(5);
COMMIT;
SQL

PGAPPNAME=deedlight_c578_crash_test \
PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=deedlight_ledger_test \
PGPASSWORD=postgres PGSSLMODE=disable \
psql --no-psqlrc --set ON_ERROR_STOP=1 --file "$tmp_dir/crash.sql" \
  >"$tmp_dir/crash-client.log" 2>&1 &
crash_client_pid=$!

client_command="$(ps -p "$crash_client_pid" -o comm= | tr -d '[:space:]')"
if [[ "$client_command" != "psql" ]]; then
  echo "FAIL: expected psql client PID, got PID=$crash_client_pid command=$client_command" >&2
  cat "$tmp_dir/crash-client.log"
  exit 1
fi

# Wait for the marker statement to have returned and the backend to enter PgSleep.
# Because statements run sequentially in one transaction, this proves both the
# effect INSERT and marker INSERT have executed but neither has committed.
backend_row=""
for attempt in $(seq 1 200); do
  backend_row="$(clean_psql --tuples-only --no-align --field-separator '|' --command "
    SELECT pid::text || '|' || state || '|' || coalesce(wait_event,'') || '|' ||
      coalesce(backend_xid::text,'')
    FROM pg_catalog.pg_stat_activity
    WHERE application_name = 'deedlight_c578_crash_test'
      AND datname = current_database()
      AND state = 'active'
      AND wait_event = 'PgSleep'
      AND backend_xid IS NOT NULL
      AND query LIKE '%pg_sleep(5)%'
  ")"
  [[ -n "$backend_row" ]] && break
  if ! kill -0 "$crash_client_pid" 2>/dev/null; then
    echo "FAIL: psql client exited before the marker/backend handshake" >&2
    cat "$tmp_dir/crash-client.log"
    exit 1
  fi
  sleep 0.1
done
if [[ -z "$backend_row" ]]; then
  echo "FAIL: timed out waiting for marker execution and backend PgSleep state" >&2
  cat "$tmp_dir/crash-client.log"
  exit 1
fi
IFS='|' read -r crash_backend_pid crash_backend_state crash_wait_event crash_backend_xid <<<"$backend_row"
[[ "$crash_backend_state" == "active" && "$crash_wait_event" == "PgSleep" && -n "$crash_backend_xid" ]]
printf 'C578_CRASH_BACKEND_READY backend_pid=%s state=%s wait_event=%s xid=%s client_pid=%s client=%s\n' \
  "$crash_backend_pid" "$crash_backend_state" "$crash_wait_event" "$crash_backend_xid" \
  "$crash_client_pid" "$client_command"

# Terminate only the identified psql client. Its server backend must then disappear.
kill -KILL "$crash_client_pid"
if wait "$crash_client_pid"; then
  crash_status=0
else
  crash_status=$?
fi
if [[ "$crash_status" -ne 137 ]]; then
  echo "FAIL: expected SIGKILL wait status 137, got $crash_status" >&2
  cat "$tmp_dir/crash-client.log"
  exit 1
fi
printf 'C578_CRASH_CLIENT_SIGKILL status=%s backend_pid=%s\n' "$crash_status" "$crash_backend_pid"

# PostgreSQL may not notice a disconnected client until the current statement returns.
# The client is already dead; allow the bounded PgSleep statement to finish, then
# require the server backend to observe EOF and roll back the open transaction.
backend_gone=false
for attempt in $(seq 1 250); do
  backend_present="$(clean_psql --tuples-only --no-align --command \
    "SELECT count(*) FROM pg_catalog.pg_stat_activity WHERE pid = $crash_backend_pid")"
  if [[ "$backend_present" == "0" ]]; then
    backend_gone=true
    break
  fi
  sleep 0.1
done
[[ "$backend_gone" == "true" ]] || {
  echo "FAIL: PostgreSQL backend $crash_backend_pid remained after client SIGKILL and bounded statement completion" >&2
  exit 1
}
printf 'C578_CRASH_BACKEND_EXITED backend_pid=%s\n' "$crash_backend_pid"

after_crash_effects="$(clean_psql --tuples-only --no-align --command \
  "SELECT count(*) FROM deedlight_execution_ledger.test_effects")"
crash_marker_count="$(clean_psql --tuples-only --no-align --command \
  "SELECT count(*) FROM deedlight_execution_ledger.execution_commit_markers WHERE execution_id = 'c5700000-0000-4000-8000-000000000027'")"
crash_reservation_status="$(clean_psql --tuples-only --no-align --command \
  "SELECT status FROM deedlight_execution_ledger.executions WHERE execution_id = 'c5700000-0000-4000-8000-000000000027'")"
crash_approval_consumed="$(clean_psql --tuples-only --no-align --command \
  "SELECT (consumed_at IS NOT NULL)::text FROM deedlight_execution_ledger.approvals WHERE approval_id = 'c5700000-0000-4000-8000-000000000007'")"

[[ "$after_crash_effects" == "$before_crash_effects" ]] || {
  echo "FAIL: uncommitted migration effects survived client crash (before=$before_crash_effects after=$after_crash_effects)" >&2
  exit 1
}
[[ "$crash_marker_count" == "0" ]] || {
  echo "FAIL: same-transaction commit marker survived rollback (count=$crash_marker_count)" >&2
  exit 1
}
[[ "$crash_reservation_status" == "running" ]] || {
  echo "FAIL: separately committed reservation did not survive as running (status=$crash_reservation_status)" >&2
  exit 1
}
[[ "$crash_approval_consumed" == "true" ]] || {
  echo "FAIL: separately committed approval consumption did not survive" >&2
  exit 1
}
printf 'C578_CRASH_ROLLBACK effects_before=%s effects_after=%s marker_rows=%s reservation=%s approval_consumed=%s\n' \
  "$before_crash_effects" "$after_crash_effects" "$crash_marker_count" \
  "$crash_reservation_status" "$crash_approval_consumed"

clean_psql --command "
  SET ROLE deedlight_ledger_recovery;
  SELECT deedlight_execution_ledger.recover_stale_executions(interval '1 microsecond');
  RESET ROLE;
"
crash_outcome="$(clean_psql --tuples-only --no-align --command \
  "SELECT status FROM deedlight_execution_ledger.executions WHERE execution_id = 'c5700000-0000-4000-8000-000000000027'")"
[[ "$crash_outcome" == "unknown" ]] || {
  echo "FAIL: interrupted running execution did not recover to unknown (status=$crash_outcome)" >&2
  exit 1
}
printf 'C578_CRASH_RECOVERY execution_id=c5700000-0000-4000-8000-000000000027 status=%s\n' "$crash_outcome"
crash_diagnostic="$(clean_psql --tuples-only --no-align --command \
  "SELECT (outcome_detail->>'category') || '|' || (outcome_detail->>'diagnosticCode') FROM deedlight_execution_ledger.executions WHERE execution_id = 'c5700000-0000-4000-8000-000000000027'")"
[[ "$crash_diagnostic" == "ambiguous_execution_outcome|D1008" ]] || {
  echo "FAIL: interrupted execution lacks explicit ambiguous-outcome diagnostic ($crash_diagnostic)" >&2
  exit 1
}
printf 'C585_AMBIGUOUS_OUTCOME_D1008 execution_id=c5700000-0000-4000-8000-000000000027\n'

# The consumed approval and terminal UNKNOWN reservation must reject replay.
clean_psql <<'SQL'
SET ROLE deedlight_ledger_runner;
DO $assert$
DECLARE v_detail text;
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.reserve_execution(
      'c5700000-0000-4000-8000-000000000007',
      'c5700000-0000-4000-8000-000000000017',
      'c5700000-0000-4000-8000-000000000027',
      '{"path":"supabase/migrations/test-crash.sql","sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}'::jsonb
    );
    RAISE EXCEPTION 'unknown execution replay unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE 'D1005' THEN
    GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
    IF v_detail NOT LIKE '%approval_missing_or_consumed%' THEN RAISE; END IF;
  END;
END
$assert$;
RESET ROLE;
SQL
echo "C578_CRASH_REPLAY_REJECTED execution_id=c5700000-0000-4000-8000-000000000027"

# Deterministically serialize two waiters behind a known approval-row lock holder.
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

app_psql() {
  local app_name="$1"
  shift
  env -i PATH="$PATH" HOME="${HOME:-/tmp}" PGPASSWORD=postgres \
    PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=deedlight_ledger_test \
    PGSSLMODE=disable PGAPPNAME="$app_name" \
    psql --no-psqlrc --set ON_ERROR_STOP=1 "$@"
}

holder_sql="
  BEGIN;
  SELECT 1 FROM deedlight_execution_ledger.approvals
    WHERE approval_id='c5770000-0000-4000-8000-000000000001' FOR UPDATE;
  SELECT pg_catalog.pg_sleep(60);
  COMMIT;
"
app_psql deedlight_c585_lock_holder --command "$holder_sql" >"$tmp_dir/holder.log" 2>&1 &
holder_client_pid=$!

holder_backend_pid=""
for attempt in $(seq 1 200); do
  holder_backend_pid="$(clean_psql --tuples-only --no-align --command "
    SELECT pid FROM pg_catalog.pg_stat_activity
    WHERE application_name='deedlight_c585_lock_holder'
      AND state='active' AND wait_event='PgSleep'
      AND query LIKE '%pg_sleep(60)%'
  ")"
  [[ -n "$holder_backend_pid" ]] && break
  kill -0 "$holder_client_pid" 2>/dev/null || {
    cat "$tmp_dir/holder.log"
    echo "FAIL: deterministic lock holder exited before acquiring the approval lock" >&2
    exit 1
  }
  sleep 0.1
done
[[ -n "$holder_backend_pid" ]] || {
  echo "FAIL: timed out waiting for lock holder backend" >&2
  exit 1
}

waiter_sql="
  SET ROLE deedlight_ledger_runner;
  SELECT deedlight_execution_ledger.reserve_execution(
    'c5770000-0000-4000-8000-000000000001',
    'c5770000-0000-4000-8000-000000000011',
    'c5770000-0000-4000-8000-000000000021',
    '{\"path\":\"supabase/migrations/concurrent-test.sql\",\"sha256\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"}'::jsonb
  );
  RESET ROLE;
"
app_psql deedlight_c585_waiter_a --command "$waiter_sql" >"$tmp_dir/race-a.log" 2>&1 &
pid_a=$!
app_psql deedlight_c585_waiter_b --command "$waiter_sql" >"$tmp_dir/race-b.log" 2>&1 &
pid_b=$!

both_blocked=false
for attempt in $(seq 1 200); do
  blocked="$(clean_psql --tuples-only --no-align --command "
    WITH RECURSIVE waiters AS (
      SELECT pid FROM pg_catalog.pg_stat_activity
      WHERE application_name IN ('deedlight_c585_waiter_a','deedlight_c585_waiter_b')
        AND wait_event_type='Lock'
    ), blocker_chain(waiter_pid, blocker_pid, path, depth) AS (
      SELECT waiter.pid, blocker.pid, ARRAY[waiter.pid, blocker.pid], 1
      FROM waiters waiter
      CROSS JOIN LATERAL unnest(pg_catalog.pg_blocking_pids(waiter.pid)) AS blocker(pid)
      UNION ALL
      SELECT chain.waiter_pid, blocker.pid, chain.path || blocker.pid, chain.depth + 1
      FROM blocker_chain chain
      CROSS JOIN LATERAL unnest(pg_catalog.pg_blocking_pids(chain.blocker_pid)) AS blocker(pid)
      WHERE NOT blocker.pid = ANY(chain.path) AND chain.depth < 16
    )
    SELECT count(DISTINCT waiter.pid)
    FROM waiters waiter
    WHERE EXISTS (
      SELECT 1 FROM blocker_chain chain
      WHERE chain.waiter_pid=waiter.pid AND $holder_backend_pid = ANY(chain.path)
    )
  ")"
  if [[ "$blocked" == "2" ]]; then
    both_blocked=true
    break
  fi
  sleep 0.1
done
[[ "$both_blocked" == "true" ]] || {
  echo "FAIL: both replay waiters were not observed in the holder's lock chain (holder PID $holder_backend_pid; observed=$blocked)" >&2
  clean_psql --command "
    SELECT pid, application_name, state, wait_event_type, wait_event,
           pg_catalog.pg_blocking_pids(pid) AS blocking_pids, left(query,240) AS query
    FROM pg_catalog.pg_stat_activity
    WHERE application_name IN ('deedlight_c585_lock_holder','deedlight_c585_waiter_a','deedlight_c585_waiter_b')
    ORDER BY application_name
  " >&2
  cat "$tmp_dir/race-a.log" "$tmp_dir/race-b.log"
  exit 1
}
printf 'C585_REPLAY_WAITERS_BLOCKED holder_pid=%s waiters=2 blocker_proven_by=pg_blocking_pids\n' "$holder_backend_pid"

# Cancel the holder only after PostgreSQL proves both waiters are blocked by it.
cancelled="$(clean_psql --tuples-only --no-align --command "SELECT pg_catalog.pg_cancel_backend($holder_backend_pid)")"
[[ "$cancelled" == "t" ]] || {
  echo "FAIL: PostgreSQL did not cancel the deterministic lock holder" >&2
  exit 1
}
set +e
wait "$holder_client_pid"; holder_status=$?
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
[[ "$holder_status" -eq 1 ]] || {
  echo "FAIL: expected cancelled holder psql status 1, got $holder_status" >&2
  cat "$tmp_dir/holder.log"
  exit 1
}

successes=0
[[ "$status_a" -eq 0 ]] && successes=$((successes + 1))
[[ "$status_b" -eq 0 ]] && successes=$((successes + 1))
if [[ "$successes" -ne 1 ]]; then
  cat "$tmp_dir/race-a.log" "$tmp_dir/race-b.log"
  echo "FAIL: deterministic concurrent replay did not produce exactly one winner" >&2
  exit 1
fi
printf 'C585_REPLAY_ONE_WINNER status_a=%s status_b=%s holder_cancel_status=%s\n' "$status_a" "$status_b" "$holder_status"

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

# The same UUIDs may be reserved independently in another database in the same cluster.
# system_identifier is shared, while database_oid is server-derived and distinct.
clean_psql --command "CREATE DATABASE deedlight_ledger_scope_test"
env -i PATH="$PATH" HOME="${HOME:-/tmp}" PGPASSWORD=postgres \
  PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=deedlight_ledger_scope_test \
  PGSSLMODE=disable psql --no-psqlrc --set ON_ERROR_STOP=1 \
  --file scripts/fixtures/migration-execution-ledger-v1.sql
env -i PATH="$PATH" HOME="${HOME:-/tmp}" PGPASSWORD=postgres \
  PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=deedlight_ledger_scope_test \
  PGSSLMODE=disable psql --no-psqlrc --set ON_ERROR_STOP=1 --command "
    SET ROLE deedlight_ledger_approver;
    SELECT deedlight_execution_ledger.approve_execution(
      'c5700000-0000-4000-8000-000000000101',
      'c5700000-0000-4000-8000-000000000011',
      'c5700000-0000-4000-8000-000000000021',
      '{\"path\":\"supabase/migrations/test.sql\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}'::jsonb
    );
    RESET ROLE;
    SET ROLE deedlight_ledger_runner;
    SELECT deedlight_execution_ledger.reserve_execution(
      'c5700000-0000-4000-8000-000000000101',
      'c5700000-0000-4000-8000-000000000011',
      'c5700000-0000-4000-8000-000000000021',
      '{\"path\":\"supabase/migrations/test.sql\",\"sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}'::jsonb
    );
    RESET ROLE;
  "

echo "C578 disposable PostgreSQL 16 execution-ledger remediation tests: PASS"


# C603 signed gateway boundary is applied only after all historical fixture tests
# and crash/replay harnesses have completed. This is a disposable CI-only overlay.
clean_psql --file scripts/fixtures/migration-execution-ledger-c603-authorization.sql
clean_psql --file scripts/fixtures/test-migration-execution-ledger-c603-authorization.sql
clean_psql --file scripts/fixtures/test-c608-recovery-authorization.sql

run_c608_state_race() {
  local scenario="$1"
  local execution_id="$2"
  local mutation_sql="$3"
  local expected_status="$4"
  local authorization holder_app updater_app recovery_app
  local holder_client_pid holder_backend_pid updater_pid recovery_pid
  local updater_client_pid recovery_client_pid updater_status recovery_status
  local holder_status cancelled blocker_count final_state nonce_count

  authorization="$(clean_psql --tuples-only --no-align --command "
    SELECT c608_test.request(ARRAY['$execution_id']::uuid[],interval '1 minute')
  ")"
  [[ -n "$authorization" ]] || {
    echo "FAIL: could not sign C608 $scenario race target" >&2
    return 1
  }

  holder_app="deedlight_c608_"$scenario"_holder"
  updater_app="deedlight_c608_"$scenario"_update"
  recovery_app="deedlight_c608_"$scenario"_recovery"
  cat >"$tmp_dir/c608-$scenario-holder.sql" <<SQL
BEGIN;
SELECT 1 FROM deedlight_execution_ledger.executions
WHERE execution_id='$execution_id' FOR UPDATE;
SELECT pg_catalog.pg_sleep(30);
COMMIT;
SQL
  printf '%s\n' "BEGIN;" "$mutation_sql" "COMMIT;" >"$tmp_dir/c608-$scenario-update.sql"
  cat >"$tmp_dir/c608-$scenario-recovery.sql" <<'SQL'
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT deedlight_execution_ledger.recover_stale_executions(interval '1 minute', :'authorization'::jsonb);
RESET SESSION AUTHORIZATION;
SQL

  app_psql "$holder_app" --file "$tmp_dir/c608-$scenario-holder.sql" \
    >"$tmp_dir/c608-$scenario-holder.log" 2>&1 &
  holder_client_pid=$!
  holder_backend_pid=""
  for attempt in $(seq 1 200); do
    holder_backend_pid="$(clean_psql --tuples-only --no-align --command "
      SELECT pid FROM pg_catalog.pg_stat_activity
      WHERE application_name='$holder_app' AND state='active'
        AND wait_event='PgSleep' AND query LIKE '%pg_sleep(30)%'
    ")"
    [[ -n "$holder_backend_pid" ]] && break
    kill -0 "$holder_client_pid" 2>/dev/null || {
      cat "$tmp_dir/c608-$scenario-holder.log"
      echo "FAIL: C608 $scenario lock holder exited early" >&2
      return 1
    }
    sleep 0.05
  done
  [[ -n "$holder_backend_pid" ]] || {
    echo "FAIL: C608 $scenario lock holder timed out" >&2
    return 1
  }

  app_psql "$updater_app" --file "$tmp_dir/c608-$scenario-update.sql" \
    >"$tmp_dir/c608-$scenario-update.log" 2>&1 &
  updater_client_pid=$!
  updater_pid=""
  for attempt in $(seq 1 200); do
    updater_pid="$(clean_psql --tuples-only --no-align --command "
      SELECT pid FROM pg_catalog.pg_stat_activity
      WHERE application_name='$updater_app' AND state='active'
        AND wait_event_type='Lock'
        AND $holder_backend_pid = ANY(pg_catalog.pg_blocking_pids(pid))
    ")"
    [[ -n "$updater_pid" ]] && break
    kill -0 "$updater_client_pid" 2>/dev/null || {
      cat "$tmp_dir/c608-$scenario-update.log"
      echo "FAIL: C608 $scenario state change did not block behind the row lock" >&2
      return 1
    }
    sleep 0.05
  done
  [[ -n "$updater_pid" ]] || {
    echo "FAIL: C608 $scenario state-change lock wait was not observed" >&2
    return 1
  }

  app_psql "$recovery_app" --set "authorization=$authorization" \
    --file "$tmp_dir/c608-$scenario-recovery.sql" \
    >"$tmp_dir/c608-$scenario-recovery.log" 2>&1 &
  recovery_client_pid=$!
  recovery_pid=""
  blocker_count=0
  for attempt in $(seq 1 200); do
    recovery_pid="$(clean_psql --tuples-only --no-align --command "
      SELECT pid FROM pg_catalog.pg_stat_activity
      WHERE application_name='$recovery_app' AND state='active'
        AND wait_event_type='Lock'
    ")"
    if [[ -n "$recovery_pid" ]]; then
      blocker_count="$(clean_psql --tuples-only --no-align --command "
        WITH RECURSIVE blocker_chain(pid,path,depth) AS (
          SELECT blocker.pid,ARRAY[$recovery_pid,blocker.pid],1
          FROM unnest(pg_catalog.pg_blocking_pids($recovery_pid)) AS blocker(pid)
          UNION ALL
          SELECT blocker.pid,chain.path || blocker.pid,chain.depth+1
          FROM blocker_chain AS chain
          CROSS JOIN LATERAL unnest(pg_catalog.pg_blocking_pids(chain.pid)) AS blocker(pid)
          WHERE NOT blocker.pid=ANY(chain.path) AND chain.depth < 16
        )
        SELECT count(*) FROM blocker_chain WHERE pid=$updater_pid
      ")"
      [[ "$blocker_count" == "1" ]] && break
    fi
    kill -0 "$recovery_client_pid" 2>/dev/null || break
    sleep 0.05
  done
  [[ "$blocker_count" == "1" ]] || {
    echo "FAIL: C608 $scenario recovery was not serialized behind the authorized-state change" >&2
    clean_psql --command "
      SELECT pid,application_name,state,wait_event_type,wait_event,
        pg_catalog.pg_blocking_pids(pid),left(query,180)
      FROM pg_catalog.pg_stat_activity
      WHERE application_name IN ('$holder_app','$updater_app','$recovery_app')
    " >&2
    return 1
  }

  cancelled="$(clean_psql --tuples-only --no-align --command "SELECT pg_catalog.pg_cancel_backend($holder_backend_pid)")"
  [[ "$cancelled" == "t" ]] || {
    echo "FAIL: could not release C608 $scenario lock holder" >&2
    return 1
  }
  set +e
  wait "$holder_client_pid"; holder_status=$?
  wait "$updater_client_pid"; updater_status=$?
  wait "$recovery_client_pid"; recovery_status=$?
  set -e
  [[ "$holder_status" -ne 0 && "$updater_status" -eq 0 && "$recovery_status" -ne 0 ]] \
    && grep -q "canceling statement due to user request" "$tmp_dir/c608-$scenario-holder.log" || {
    echo "FAIL: C608 $scenario race statuses holder=$holder_status updater=$updater_status recovery=$recovery_status" >&2
    cat "$tmp_dir/c608-$scenario-holder.log" "$tmp_dir/c608-$scenario-update.log" "$tmp_dir/c608-$scenario-recovery.log"
    return 1
  }
  grep -q "DEEDLIGHT_TRUST_FAILURE:incomplete_preconditions" "$tmp_dir/c608-$scenario-recovery.log" || {
    echo "FAIL: C608 $scenario recovery did not reject the changed target" >&2
    cat "$tmp_dir/c608-$scenario-recovery.log"
    return 1
  }

  final_state="$(clean_psql --tuples-only --no-align --command "
    SELECT status || '|' || c603_row_version::text
    FROM deedlight_execution_ledger.executions WHERE execution_id='$execution_id'
  ")"
  [[ "$final_state" == "$expected_status|2" ]] || {
    echo "FAIL: C608 $scenario state after rejection is unexpected ($final_state)" >&2
    return 1
  }
  cat >"$tmp_dir/c608-$scenario-nonce.sql" <<'SQL'
SELECT count(*) FROM deedlight_execution_ledger.authorization_nonces
WHERE actor='deedlight_ledger_recovery'
  AND nonce=(:'authorization'::jsonb->>'nonce')::uuid;
SQL
  nonce_count="$(clean_psql --tuples-only --no-align --set "authorization=$authorization" \
    --file "$tmp_dir/c608-$scenario-nonce.sql")"
  [[ "$nonce_count" == "0" ]] || {
    echo "FAIL: rejected C608 $scenario request consumed its authorization nonce ($nonce_count)" >&2
    return 1
  }
  printf 'C608_%s_RACE_REJECTED_ZERO_MUTATION nonce_rolled_back=%s final=%s\n' \
    "$scenario" "$nonce_count" "$final_state"
}

run_c608_state_race "heartbeat" "c6080000-0000-4000-8000-000000000010" \
  "UPDATE deedlight_execution_ledger.executions SET heartbeat_at=pg_catalog.clock_timestamp() WHERE execution_id='c6080000-0000-4000-8000-000000000010';" \
  "running"
run_c608_state_race "finalize" "c6080000-0000-4000-8000-000000000011" \
  "UPDATE deedlight_execution_ledger.executions SET status='succeeded',completed_at=pg_catalog.clock_timestamp(),outcome_detail='{\"result\":\"finalized-after-recovery-authorization\"}'::jsonb WHERE execution_id='c6080000-0000-4000-8000-000000000011';" \
  "succeeded"

# Change the later authorized target while recovery is blocked on the earlier target.
later_target_auth="$(clean_psql --tuples-only --no-align --command "
  SELECT c608_test.request(ARRAY[
    'c6080000-0000-4000-8000-000000000021',
    'c6080000-0000-4000-8000-000000000022'
  ]::uuid[],interval '1 minute')
")"
[[ -n "$later_target_auth" ]] || {
  echo "FAIL: could not sign C610 two-target recovery request" >&2
  exit 1
}
cat >"$tmp_dir/c610-later-holder.sql" <<'SQL'
BEGIN;
SELECT 1 FROM deedlight_execution_ledger.executions
WHERE execution_id='c6080000-0000-4000-8000-000000000021' FOR UPDATE;
SELECT pg_catalog.pg_sleep(30);
COMMIT;
SQL
cat >"$tmp_dir/c610-later-recovery.sql" <<'SQL'
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT deedlight_execution_ledger.recover_stale_executions(interval '1 minute', :'authorization'::jsonb);
RESET SESSION AUTHORIZATION;
SQL
cat >"$tmp_dir/c610-later-update.sql" <<'SQL'
UPDATE deedlight_execution_ledger.executions
SET status='running',runner_identity='c610-race-runner',
    started_at=pg_catalog.clock_timestamp()
WHERE execution_id='c6080000-0000-4000-8000-000000000022';
SQL
cat >"$tmp_dir/c610-later-snapshots.sql" <<'SQL'
SELECT c608_test.assert_execution_snapshot(
  'c6080000-0000-4000-8000-000000000021','running',
  (:'authorization'::jsonb->'request'->'targets'->0->>'expectedHeartbeatAt')::timestamptz,
  :'authorization'::jsonb->'request'->'targets'->0->'expectedSourceIdentity',
  (:'authorization'::jsonb->'request'->'targets'->0->>'expectedRowVersion')::bigint
);
SELECT c608_test.assert_execution_snapshot(
  'c6080000-0000-4000-8000-000000000022','running',
  (:'authorization'::jsonb->'request'->'targets'->1->>'expectedHeartbeatAt')::timestamptz,
  :'authorization'::jsonb->'request'->'targets'->1->'expectedSourceIdentity',
  (:'authorization'::jsonb->'request'->'targets'->1->>'expectedRowVersion')::bigint+1
);
SQL
app_psql deedlight_c610_later_holder --file "$tmp_dir/c610-later-holder.sql" \
  >"$tmp_dir/c610-later-holder.log" 2>&1 &
c610_holder_client_pid=$!
c610_holder_backend_pid=""
for attempt in $(seq 1 200); do
  c610_holder_backend_pid="$(clean_psql --tuples-only --no-align --command "
    SELECT pid FROM pg_catalog.pg_stat_activity
    WHERE application_name='deedlight_c610_later_holder' AND state='active'
      AND wait_event='PgSleep' AND query LIKE '%pg_sleep(30)%'
  ")"
  [[ -n "$c610_holder_backend_pid" ]] && break
  kill -0 "$c610_holder_client_pid" 2>/dev/null || {
    cat "$tmp_dir/c610-later-holder.log"
    echo "FAIL: C610 earlier-target lock holder exited early" >&2
    exit 1
  }
  sleep 0.05
done
[[ -n "$c610_holder_backend_pid" ]] || {
  echo "FAIL: C610 timed out waiting for earlier-target lock holder" >&2
  exit 1
}

app_psql deedlight_c610_later_recovery --set "authorization=$later_target_auth" \
  --file "$tmp_dir/c610-later-recovery.sql" \
  >"$tmp_dir/c610-later-recovery.log" 2>&1 &
c610_recovery_client_pid=$!
c610_recovery_backend_pid=""
for attempt in $(seq 1 200); do
  c610_recovery_backend_pid="$(clean_psql --tuples-only --no-align --command "
    SELECT pid FROM pg_catalog.pg_stat_activity
    WHERE application_name='deedlight_c610_later_recovery' AND state='active'
      AND wait_event_type='Lock'
      AND $c610_holder_backend_pid = ANY(pg_catalog.pg_blocking_pids(pid))
  ")"
  [[ -n "$c610_recovery_backend_pid" ]] && break
  kill -0 "$c610_recovery_client_pid" 2>/dev/null || {
    cat "$tmp_dir/c610-later-recovery.log"
    echo "FAIL: C610 recovery did not wait on the earlier authorized target" >&2
    exit 1
  }
  sleep 0.05
done
[[ -n "$c610_recovery_backend_pid" ]] || {
  echo "FAIL: C610 recovery wait on earlier target was not observed" >&2
  exit 1
}

app_psql deedlight_c610_later_update --file "$tmp_dir/c610-later-update.sql" \
  >"$tmp_dir/c610-later-update.log" 2>&1 || {
  cat "$tmp_dir/c610-later-update.log"
  echo "FAIL: C610 later-target concurrent update did not complete" >&2
  exit 1
}
cancelled="$(clean_psql --tuples-only --no-align --command "SELECT pg_catalog.pg_cancel_backend($c610_holder_backend_pid)")"
[[ "$cancelled" == "t" ]] || {
  echo "FAIL: could not release C610 earlier-target lock holder" >&2
  exit 1
}
set +e
wait "$c610_holder_client_pid"; c610_holder_status=$?
wait "$c610_recovery_client_pid"; c610_recovery_status=$?
set -e
[[ "$c610_holder_status" -ne 0 && "$c610_recovery_status" -ne 0 ]] \
  && grep -q "canceling statement due to user request" "$tmp_dir/c610-later-holder.log" || {
  echo "FAIL: C610 later-target race statuses holder=$c610_holder_status recovery=$c610_recovery_status" >&2
  cat "$tmp_dir/c610-later-holder.log" "$tmp_dir/c610-later-recovery.log"
  exit 1
}
grep -q "DEEDLIGHT_TRUST_FAILURE:incomplete_preconditions" "$tmp_dir/c610-later-recovery.log" || {
  echo "FAIL: C610 recovery did not reject the later target changed while first was locked" >&2
  cat "$tmp_dir/c610-later-recovery.log"
  exit 1
}
clean_psql --set "authorization=$later_target_auth" \
  --file "$tmp_dir/c610-later-snapshots.sql"
later_nonce_count="$(clean_psql --tuples-only --no-align --command "
  SELECT count(*) FROM deedlight_execution_ledger.authorization_nonces
  WHERE actor='deedlight_ledger_recovery'
    AND nonce=('$later_target_auth'::jsonb->>'nonce')::uuid
")"
[[ "$later_nonce_count" == "0" ]] || {
  echo "FAIL: C610 later-target rejection consumed its authorization nonce ($later_nonce_count)" >&2
  exit 1
}
echo "C610_LATER_TARGET_FINALIZED_WHILE_EARLIER_LOCKED_REJECTED_ZERO_RECOVERY_MUTATION nonce_rolled_back=$later_nonce_count"

# Two independently signed overlapping recovery requests wait on the same row.
# Releasing a deterministic lock holder must produce one winner and one fail-closed loser.
overlap_auth_a="$(clean_psql --tuples-only --no-align --command "
  SELECT c608_test.request(ARRAY['c6080000-0000-4000-8000-000000000009']::uuid[],interval '1 minute')
")"
overlap_auth_b="$(clean_psql --tuples-only --no-align --command "
  SELECT c608_test.request(ARRAY['c6080000-0000-4000-8000-000000000009']::uuid[],interval '1 minute')
")"
[[ -n "$overlap_auth_a" && -n "$overlap_auth_b" && "$overlap_auth_a" != "$overlap_auth_b" ]] || {
  echo "FAIL: could not create two distinct signed overlapping recovery requests" >&2
  exit 1
}

holder_sql="
  BEGIN;
  SELECT 1 FROM deedlight_execution_ledger.executions
    WHERE execution_id='c6080000-0000-4000-8000-000000000009' FOR UPDATE;
  SELECT pg_catalog.pg_sleep(30);
  COMMIT;
"
app_psql deedlight_c608_lock_holder --command "$holder_sql" >"$tmp_dir/c608-holder.log" 2>&1 &
c608_holder_client_pid=$!
c608_holder_backend_pid=""
for attempt in $(seq 1 200); do
  c608_holder_backend_pid="$(clean_psql --tuples-only --no-align --command "
    SELECT pid FROM pg_catalog.pg_stat_activity
    WHERE application_name='deedlight_c608_lock_holder'
      AND state='active' AND wait_event='PgSleep'
      AND query LIKE '%pg_sleep(30)%'
  ")"
  [[ -n "$c608_holder_backend_pid" ]] && break
  kill -0 "$c608_holder_client_pid" 2>/dev/null || {
    cat "$tmp_dir/c608-holder.log"
    echo "FAIL: C608 deterministic row-lock holder exited early" >&2
    exit 1
  }
  sleep 0.05
done
[[ -n "$c608_holder_backend_pid" ]] || {
  echo "FAIL: C608 timed out waiting for row-lock holder" >&2
  exit 1
}

cat >"$tmp_dir/c608-recovery-a.sql" <<'SQL'
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT deedlight_execution_ledger.recover_stale_executions(interval '1 minute', :'authorization'::jsonb);
RESET SESSION AUTHORIZATION;
SQL
cat >"$tmp_dir/c608-recovery-b.sql" <<'SQL'
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT deedlight_execution_ledger.recover_stale_executions(interval '1 minute', :'authorization'::jsonb);
RESET SESSION AUTHORIZATION;
SQL
app_psql deedlight_c608_recovery_a --set "authorization=$overlap_auth_a" \
  --file "$tmp_dir/c608-recovery-a.sql" >"$tmp_dir/c608-recovery-a.log" 2>&1 &
c608_pid_a=$!
app_psql deedlight_c608_recovery_b --set "authorization=$overlap_auth_b" \
  --file "$tmp_dir/c608-recovery-b.sql" >"$tmp_dir/c608-recovery-b.log" 2>&1 &
c608_pid_b=$!

both_recovery_waiters_blocked=false
for attempt in $(seq 1 200); do
  blocked_count="$(clean_psql --tuples-only --no-align --command "
    WITH RECURSIVE waiters AS (
      SELECT pid FROM pg_catalog.pg_stat_activity
      WHERE application_name IN ('deedlight_c608_recovery_a','deedlight_c608_recovery_b')
        AND wait_event_type='Lock'
    ), blocker_chain(waiter_pid,blocker_pid,path,depth) AS (
      SELECT waiter.pid,blocker.pid,ARRAY[waiter.pid,blocker.pid],1
      FROM waiters AS waiter
      CROSS JOIN LATERAL unnest(pg_catalog.pg_blocking_pids(waiter.pid)) AS blocker(pid)
      UNION ALL
      SELECT chain.waiter_pid,blocker.pid,chain.path || blocker.pid,chain.depth+1
      FROM blocker_chain AS chain
      CROSS JOIN LATERAL unnest(pg_catalog.pg_blocking_pids(chain.blocker_pid)) AS blocker(pid)
      WHERE NOT blocker.pid=ANY(chain.path) AND chain.depth < 16
    )
    SELECT count(DISTINCT waiter.pid)
    FROM waiters AS waiter
    WHERE EXISTS (
      SELECT 1 FROM blocker_chain AS chain
      WHERE chain.waiter_pid=waiter.pid
        AND chain.blocker_pid=$c608_holder_backend_pid
    )
  ")"
  if [[ "$blocked_count" == "2" ]]; then
    both_recovery_waiters_blocked=true
    break
  fi
  kill -0 "$c608_pid_a" 2>/dev/null || break
  kill -0 "$c608_pid_b" 2>/dev/null || break
  sleep 0.05
done
[[ "$both_recovery_waiters_blocked" == "true" ]] || {
  echo "FAIL: C608 overlapping recovery requests were not both blocked by the same row lock" >&2
  clean_psql --command "
    SELECT pid,application_name,state,wait_event_type,wait_event,
      pg_catalog.pg_blocking_pids(pid),left(query,200)
    FROM pg_catalog.pg_stat_activity
    WHERE application_name IN ('deedlight_c608_lock_holder',
      'deedlight_c608_recovery_a','deedlight_c608_recovery_b')
  " >&2
  cat "$tmp_dir/c608-recovery-a.log" "$tmp_dir/c608-recovery-b.log"
  exit 1
}
printf 'C608_OVERLAPPING_RECOVERY_WAITERS_BLOCKED holder_pid=%s waiters=2\n' "$c608_holder_backend_pid"

cancelled="$(clean_psql --tuples-only --no-align --command "SELECT pg_catalog.pg_cancel_backend($c608_holder_backend_pid)")"
[[ "$cancelled" == "t" ]] || {
  echo "FAIL: could not release C608 deterministic lock holder" >&2
  exit 1
}
set +e
wait "$c608_holder_client_pid"; c608_holder_status=$?
wait "$c608_pid_a"; c608_status_a=$?
wait "$c608_pid_b"; c608_status_b=$?
set -e
[[ "$c608_holder_status" -eq 1 ]] || {
  echo "FAIL: C608 lock holder was not cancelled as expected (status=$c608_holder_status)" >&2
  cat "$tmp_dir/c608-holder.log"
  exit 1
}
c608_successes=0
[[ "$c608_status_a" -eq 0 ]] && c608_successes=$((c608_successes + 1))
[[ "$c608_status_b" -eq 0 ]] && c608_successes=$((c608_successes + 1))
[[ "$c608_successes" -eq 1 ]] || {
  echo "FAIL: overlapping recovery did not produce exactly one winner (a=$c608_status_a b=$c608_status_b)" >&2
  cat "$tmp_dir/c608-recovery-a.log" "$tmp_dir/c608-recovery-b.log"
  exit 1
}
grep -q "DEEDLIGHT_TRUST_FAILURE:incomplete_preconditions" "$tmp_dir/c608-recovery-a.log" "$tmp_dir/c608-recovery-b.log" || {
  echo "FAIL: losing C608 recovery request did not fail with the expected trust boundary" >&2
  cat "$tmp_dir/c608-recovery-a.log" "$tmp_dir/c608-recovery-b.log"
  exit 1
}
c608_final_status="$(clean_psql --tuples-only --no-align --command "
  SELECT status FROM deedlight_execution_ledger.executions
  WHERE execution_id='c6080000-0000-4000-8000-000000000009'
")"
[[ "$c608_final_status" == "unknown" ]] || {
  echo "FAIL: overlapping recovery final state is not terminal UNKNOWN ($c608_final_status)" >&2
  exit 1
}
cat >"$tmp_dir/c608-nonce-count.sql" <<'SQL'
SELECT count(*) FROM deedlight_execution_ledger.authorization_nonces
WHERE actor='deedlight_ledger_recovery'
  AND nonce IN ((:'auth_a'::jsonb->>'nonce')::uuid,(:'auth_b'::jsonb->>'nonce')::uuid);
SQL
c608_nonce_winners="$(clean_psql --tuples-only --no-align \
  --set "auth_a=$overlap_auth_a" --set "auth_b=$overlap_auth_b" \
  --file "$tmp_dir/c608-nonce-count.sql")"
[[ "$c608_nonce_winners" == "1" ]] || {
  echo "FAIL: overlapping recovery did not commit exactly one authorization nonce ($c608_nonce_winners)" >&2
  exit 1
}
printf 'C608_OVERLAPPING_RECOVERY_ONE_WINNER status_a=%s status_b=%s nonce_winners=%s final_status=%s\n' \
  "$c608_status_a" "$c608_status_b" "$c608_nonce_winners" "$c608_final_status"
clean_psql --command "DROP SCHEMA c608_test CASCADE; DROP SCHEMA c603_test CASCADE;"
echo "C608_RECOVERY_AUTHORIZATION_CONCURRENCY_PASS"

# Prove a non-superuser actor cannot switch to another actor role.
if clean_psql --command "SET SESSION AUTHORIZATION deedlight_ledger_approver; SET ROLE deedlight_ledger_runner" \
  >"$tmp_dir/c603-set-role.log" 2>&1; then
  echo "FAIL: Approver unexpectedly assumed Runner role" >&2
  cat "$tmp_dir/c603-set-role.log" >&2
  exit 1
fi
grep -qi "permission denied to set role" "$tmp_dir/c603-set-role.log" || {
  echo "FAIL: SET ROLE failed for an unexpected reason" >&2
  cat "$tmp_dir/c603-set-role.log" >&2
  exit 1
}
echo "C603_CROSS_ROLE_SET_ROLE_DENIED_PASS"
