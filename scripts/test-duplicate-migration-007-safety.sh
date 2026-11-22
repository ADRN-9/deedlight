#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly TARGET_SCRIPT="$ROOT/scripts/test-duplicate-migration-007.sh"
readonly TMP="$(mktemp -d)"
readonly TEST_BIN="$TMP/bin"
readonly CALL_LOG="$TMP/command-calls.log"
readonly SYSTEM_PATH="${PATH:-/usr/bin:/bin}"
readonly TEST_PATH="$TEST_BIN:$SYSTEM_PATH"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$TEST_BIN" "$TMP/home"

for command_name in psql dropdb createdb supabase; do
  cat > "$TEST_BIN/$command_name" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\t%s\n' "${0##*/}" "$*" >> "${DEEDLIGHT_SAFETY_CALL_LOG:?}"
case "${0##*/}" in
  psql)
    printf '172.18.0.2|5432|deedlight_migration_order_test|postgres|160016|16.16\n'
    exit 0
    ;;
  supabase)
    if [[ "${1:-}" == "--version" ]]; then
      printf 'supabase version 3.2.0\n'
      exit 0
    fi
    exit 98
    ;;
  createdb)
    exit 97
    ;;
  *)
    exit 0
    ;;
esac
SH
  chmod 0755 "$TEST_BIN/$command_name"
done

run_rejected_override() {
  local name="$1" value="$2" label="$3" log="$TMP/$3.log"
  : > "$CALL_LOG"
  if env -i \
    "PATH=$TEST_PATH" "HOME=$TMP/home" \
    GITHUB_ACTIONS=true \
    GITHUB_REPOSITORY=ADRN-9/deedlight \
    GITHUB_JOB=delivery_migration_order_database_behavior \
    GITHUB_EVENT_NAME=pull_request \
    DELIVERY_ENABLED=false \
    "DEEDLIGHT_SAFETY_CALL_LOG=$CALL_LOG" \
    "$name=$value" \
    bash "$TARGET_SCRIPT" > "$log" 2>&1; then
    fail "$name=$value was accepted."
  fi
  [[ ! -s "$CALL_LOG" ]] || {
    printf 'Unexpected PostgreSQL/CLI command calls for %s:\n' "$name" >&2
    cat "$CALL_LOG" >&2
    fail "$name was rejected only after a command executed."
  }
  grep -Fq "Refusing" "$log" || {
    cat "$log" >&2
    fail "$name rejection did not report a fail-closed guard."
  }
  printf 'Remote/overridden libpq setting %s rejected before psql/dropdb/createdb/supabase: PASS\n' "$name"
}

run_rejected_override PGHOST "203.0.113.44" remote_host
run_rejected_override PGHOSTADDR "203.0.113.44" remote_hostaddr
run_rejected_override PGSERVICE "production" service_name
run_rejected_override PGSERVICEFILE "$TMP/production.pg_service.conf" service_file
run_rejected_override PGDATABASE "production" database_override
run_rejected_override PGPORT "6543" remote_port
run_rejected_override PGOPTIONS "-c application_name=production" options_override
run_rejected_override PGTARGETSESSIONATTRS "read-write" target_session_override
run_rejected_override PGPASSFILE "$TMP/production.pgpass" password_file_override
run_rejected_override PGSSLMODE "require" ssl_mode_override

# The documented local CI values pass the environment guard. Fake commands ensure no database is created.
: > "$CALL_LOG"
local_status=0
env -i \
  "PATH=$TEST_PATH" "HOME=$TMP/home" \
  GITHUB_ACTIONS=true \
  GITHUB_REPOSITORY=ADRN-9/deedlight \
  GITHUB_JOB=delivery_migration_order_database_behavior \
  GITHUB_EVENT_NAME=pull_request \
  DELIVERY_ENABLED=false \
  PGHOST=127.0.0.1 \
  PGPORT=5432 \
  PGUSER=postgres \
  PGPASSWORD=postgres \
  "DEEDLIGHT_SAFETY_CALL_LOG=$CALL_LOG" \
  bash "$TARGET_SCRIPT" > "$TMP/local-allowlist.log" 2>&1 || local_status=$?

[[ "$local_status" -eq 97 ]] || {
  cat "$TMP/local-allowlist.log" >&2
  fail "Local CI target did not reach the fake createdb boundary (status=$local_status)."
}
grep -Fq "Verified isolated PostgreSQL client target: 127.0.0.1:5432/deedlight_migration_order_test" "$TMP/local-allowlist.log" || {
  cat "$TMP/local-allowlist.log" >&2
  fail "Exact local CI target was not accepted by the read-only preflight."
}
grep -Fq "server_version_num=160016" "$TMP/local-allowlist.log" || fail "Numeric PostgreSQL version evidence was not logged."
grep -q $'^psql\t' "$CALL_LOG" || fail "The local target preflight did not call the fake psql command."
grep -q 

printf 'Exact local CI target accepted; fake createdb prevented any database mutation: PASS\n'
printf 'Duplicate-007 remote-target safety regressions: PASS\n'
^createdb\t' "$CALL_LOG" || fail "The exact local target did not reach the fake createdb boundary."
grep -Fq -- "--host 127.0.0.1 --port 5432 --username postgres --dbname deedlight_migration_order_test" "$CALL_LOG" || fail "The local preflight did not use explicit loopback connection arguments."

printf 'Exact local CI target accepted; fake createdb prevented any database mutation: PASS\n'
printf 'Duplicate-007 remote-target safety regressions: PASS\n'
