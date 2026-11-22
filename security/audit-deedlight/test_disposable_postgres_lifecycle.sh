#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/disposable_postgres.sh"
deedlight_fixture_require_run_scope
deedlight_fixture_verify_docker_service
deedlight_fixture_verify_service

TMP="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/deedlight-fixture-lifecycle.XXXXXX")"
CHILD_PIDS=()
cleanup_test() {
  local rc=$? pid
  trap - EXIT INT TERM HUP
  for pid in "${CHILD_PIDS[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  for pid in "${CHILD_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
  rm -rf "$TMP"
  exit "$rc"
}
trap cleanup_test EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_state() {
  local db="$1" marker="$2" expected="$3" actual
  actual="$(deedlight_fixture_database_state "$db" "$marker")" || fail "Could not inspect $db"
  [[ "$actual" == "$expected" ]] || fail "Expected $db state $expected, received $actual"
}

wait_for_ready() {
  local ready="$1" pid="$2" attempt
  for ((attempt=0; attempt<200; attempt++)); do
    [[ -s "$ready" ]] && return 0
    kill -0 "$pid" 2>/dev/null || fail "Lifecycle child $pid exited before creating its database"
    sleep 0.05
  done
  fail "Timed out waiting for lifecycle child $pid"
}

spawn_waiting_fixture() {
  local case_name="$1" ready="$2" fifo="$3" output_root="$4"
  local pid="$BASHPID" nonce output
  nonce="$(deedlight_fixture_nonce)"
  export DEEDLIGHT_FIXTURE_DB_NAME
  export DEEDLIGHT_FIXTURE_DB_MARKER
  DEEDLIGHT_FIXTURE_DB_NAME="$(deedlight_fixture_database_name "$case_name" "$pid" "$nonce")"
  DEEDLIGHT_FIXTURE_DB_MARKER="$(deedlight_fixture_database_marker "$case_name" "$pid" "$nonce")"
  deedlight_fixture_install_cleanup_traps
  deedlight_fixture_create_database "$DEEDLIGHT_FIXTURE_DB_NAME" "$DEEDLIGHT_FIXTURE_DB_MARKER"
  output="$(deedlight_fixture_output_path "$output_root" "$case_name" "$pid" "$nonce")"
  mkdir "$output"
  printf '%s\t%s\t%s\n' "$DEEDLIGHT_FIXTURE_DB_NAME" "$DEEDLIGHT_FIXTURE_DB_MARKER" "$output" > "$ready"
  IFS= read -r _ < "$fifo"
}

spawn_failure_fixture() {
  local case_name="$1" ready="$2" fifo="$3" pid="$BASHPID" nonce
  nonce="$(deedlight_fixture_nonce)"
  export DEEDLIGHT_FIXTURE_DB_NAME
  export DEEDLIGHT_FIXTURE_DB_MARKER
  DEEDLIGHT_FIXTURE_DB_NAME="$(deedlight_fixture_database_name "$case_name" "$pid" "$nonce")"
  DEEDLIGHT_FIXTURE_DB_MARKER="$(deedlight_fixture_database_marker "$case_name" "$pid" "$nonce")"
  deedlight_fixture_install_cleanup_traps
  deedlight_fixture_create_database "$DEEDLIGHT_FIXTURE_DB_NAME" "$DEEDLIGHT_FIXTURE_DB_MARKER"
  printf '%s\t%s\n' "$DEEDLIGHT_FIXTURE_DB_NAME" "$DEEDLIGHT_FIXTURE_DB_MARKER" > "$ready"
  IFS= read -r _ < "$fifo"
  exit 23
}

mkdir -p "$TMP/output"
mkfifo "$TMP/release-a" "$TMP/release-b" "$TMP/release-failure"

# Same PID with different nonces must still produce distinct resources.
SAME_PID="$BASHPID"
SAME_NONCE_A="00000001"
SAME_NONCE_B="00000002"
SAME_DB_A="$(deedlight_fixture_database_name A "$SAME_PID" "$SAME_NONCE_A")"
SAME_DB_B="$(deedlight_fixture_database_name A "$SAME_PID" "$SAME_NONCE_B")"
SAME_OUT_A="$(deedlight_fixture_output_path "$TMP/output" A "$SAME_PID" "$SAME_NONCE_A")"
SAME_OUT_B="$(deedlight_fixture_output_path "$TMP/output" A "$SAME_PID" "$SAME_NONCE_B")"
[[ "$SAME_DB_A" != "$SAME_DB_B" && "$SAME_OUT_A" != "$SAME_OUT_B" ]] || fail "Reused process IDs collided without a fresh nonce"

spawn_waiting_fixture A "$TMP/ready-a" "$TMP/release-a" "$TMP/output" &
PID_A=$!
CHILD_PIDS+=("$PID_A")
spawn_waiting_fixture A "$TMP/ready-b" "$TMP/release-b" "$TMP/output" &
PID_B=$!
CHILD_PIDS+=("$PID_B")
wait_for_ready "$TMP/ready-a" "$PID_A"
wait_for_ready "$TMP/ready-b" "$PID_B"

IFS=$'\t' read -r DB_A MARKER_A OUTPUT_A < "$TMP/ready-a"
IFS=$'\t' read -r DB_B MARKER_B OUTPUT_B < "$TMP/ready-b"
[[ "$DB_A" != "$DB_B" ]] || fail "Parallel same-case invocations shared a database name"
[[ "$OUTPUT_A" != "$OUTPUT_B" ]] || fail "Parallel same-case invocations shared an output directory"
assert_state "$DB_A" "$MARKER_A" owned
assert_state "$DB_B" "$MARKER_B" owned

printf 'release\n' > "$TMP/release-a"
if wait "$PID_A"; then STATUS_A=0; else STATUS_A=$?; fi
CHILD_PIDS=("$PID_B")
[[ "$STATUS_A" -eq 0 ]] || fail "Successful fixture child returned $STATUS_A"
assert_state "$DB_A" "$MARKER_A" ""
assert_state "$DB_B" "$MARKER_B" owned

kill -TERM "$PID_B"
if wait "$PID_B"; then STATUS_B=0; else STATUS_B=$?; fi
CHILD_PIDS=()
[[ "$STATUS_B" -eq 143 ]] || fail "TERM fixture child returned $STATUS_B instead of 143"
assert_state "$DB_B" "$MARKER_B" ""

spawn_failure_fixture C "$TMP/ready-failure" "$TMP/release-failure" &
PID_FAILURE=$!
CHILD_PIDS+=("$PID_FAILURE")
wait_for_ready "$TMP/ready-failure" "$PID_FAILURE"
IFS=$'\t' read -r DB_FAILURE MARKER_FAILURE < "$TMP/ready-failure"
assert_state "$DB_FAILURE" "$MARKER_FAILURE" owned
printf 'release\n' > "$TMP/release-failure"
if wait "$PID_FAILURE"; then STATUS_FAILURE=0; else STATUS_FAILURE=$?; fi
CHILD_PIDS=()
[[ "$STATUS_FAILURE" -eq 23 ]] || fail "Failing fixture child returned $STATUS_FAILURE instead of 23"
assert_state "$DB_FAILURE" "$MARKER_FAILURE" ""

ORPHAN_PID="$BASHPID"
ORPHAN_NONCE="$(deedlight_fixture_nonce)"
ORPHAN_DB="$(deedlight_fixture_database_name D "$ORPHAN_PID" "$ORPHAN_NONCE")"
ORPHAN_MARKER="$(deedlight_fixture_database_marker D "$ORPHAN_PID" "$ORPHAN_NONCE")"
deedlight_fixture_create_database "$ORPHAN_DB" "$ORPHAN_MARKER"
deedlight_fixture_cleanup_run
assert_state "$ORPHAN_DB" "$ORPHAN_MARKER" ""

UNMARKED_PID="$BASHPID"
UNMARKED_NONCE="$(deedlight_fixture_nonce)"
UNMARKED_DB="$(deedlight_fixture_database_name D "$UNMARKED_PID" "$UNMARKED_NONCE")"
UNMARKED_MARKER="$(deedlight_fixture_database_marker D "$UNMARKED_PID" "$UNMARKED_NONCE")"
createdb --host 127.0.0.1 --port 5432 --username postgres "$UNMARKED_DB"
assert_state "$UNMARKED_DB" "$UNMARKED_MARKER" unmarked
deedlight_fixture_cleanup_run
assert_state "$UNMARKED_DB" "$UNMARKED_MARKER" ""

FOREIGN_PID="$BASHPID"
FOREIGN_NONCE="$(deedlight_fixture_nonce)"
FOREIGN_DB="$(deedlight_fixture_database_name E "$FOREIGN_PID" "$FOREIGN_NONCE")"
EXPECTED_MARKER="$(deedlight_fixture_database_marker E "$FOREIGN_PID" "$FOREIGN_NONCE")"
FOREIGN_MARKER="foreign-fixture-marker:${GITHUB_RUN_ID}:${GITHUB_RUN_ATTEMPT}:${FOREIGN_PID}:${FOREIGN_NONCE}"
deedlight_fixture_create_database "$FOREIGN_DB" "$FOREIGN_MARKER"
if deedlight_fixture_drop_owned_database "$FOREIGN_DB" "$EXPECTED_MARKER"; then
  fail "Cleanup accepted a mismatched database ownership marker"
fi
assert_state "$FOREIGN_DB" "$FOREIGN_MARKER" owned
if deedlight_fixture_cleanup_run; then
  fail "Run-scoped sweep accepted a mismatched database marker"
fi
assert_state "$FOREIGN_DB" "$FOREIGN_MARKER" owned
dropdb --force --if-exists --host 127.0.0.1 --port 5432 --username postgres "$FOREIGN_DB"
assert_state "$FOREIGN_DB" "$FOREIGN_MARKER" ""

# A failed dropdb must fail closed without losing the database's ownership evidence.
DROP_FAILURE_PID="$BASHPID"
DROP_FAILURE_NONCE="$(deedlight_fixture_nonce)"
DROP_FAILURE_DB="$(deedlight_fixture_database_name F "$DROP_FAILURE_PID" "$DROP_FAILURE_NONCE")"
DROP_FAILURE_MARKER="$(deedlight_fixture_database_marker F "$DROP_FAILURE_PID" "$DROP_FAILURE_NONCE")"
deedlight_fixture_create_database "$DROP_FAILURE_DB" "$DROP_FAILURE_MARKER"
REAL_DROPDB="$(command -v dropdb)"
[[ -x "$REAL_DROPDB" ]] || fail "Could not resolve the real dropdb executable"
mkdir -p "$TMP/failing-bin"
cat > "$TMP/failing-bin/dropdb" <<'SH'
#!/usr/bin/env bash
printf 'invoked\n' > "$DEEDLIGHT_DROPDB_FAILURE_MARKER"
echo "Injected dropdb failure for disposable cleanup" >&2
exit 42
SH
chmod 0755 "$TMP/failing-bin/dropdb"
export DEEDLIGHT_DROPDB_FAILURE_MARKER="$TMP/dropdb-failure-invoked"
SAVED_PATH="$PATH"
PATH="$TMP/failing-bin:$PATH"
hash -r
if deedlight_fixture_cleanup_run; then
  PATH="$SAVED_PATH"
  hash -r
  fail "Run cleanup succeeded even though injected dropdb returned nonzero"
else
  DROP_FAILURE_STATUS=$?
fi
PATH="$SAVED_PATH"
hash -r
[[ "$DROP_FAILURE_STATUS" -ne 0 ]] || fail "Injected dropdb failure was not propagated"
[[ -s "$DEEDLIGHT_DROPDB_FAILURE_MARKER" ]] || fail "Injected dropdb executable was not invoked"
[[ "$(command -v dropdb)" == "$REAL_DROPDB" ]] || fail "Real dropdb was not restored after failure injection"
assert_state "$DROP_FAILURE_DB" "$DROP_FAILURE_MARKER" owned
echo "Injected dropdb failure: cleanup returned nonzero and ownership marker remained intact: PASS"

# Restore the real executable and prove a normal retry removes the same database.
deedlight_fixture_cleanup_run || fail "Cleanup retry with the real dropdb executable failed"
assert_state "$DROP_FAILURE_DB" "$DROP_FAILURE_MARKER" ""
echo "Cleanup retry with the real dropdb executable: PASS"
deedlight_fixture_assert_no_run_databases
echo "Remaining run-scoped disposable PostgreSQL databases: 0"
echo "C260 cleanup-failure recovery regression: PASS"
echo "C249 disposable PostgreSQL lifecycle, ownership, parallel isolation and cleanup regression: PASS"
