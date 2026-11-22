#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly TARGET_SCRIPT="$ROOT/scripts/test-duplicate-migration-007.sh"
readonly TMP="$(mktemp -d)"
readonly TEST_BIN="$TMP/bin"
readonly CALL_LOG="$TMP/command-calls.log"
readonly SYSTEM_PATH="${PATH:-/usr/bin:/bin}"
readonly TEST_PATH="$TEST_BIN:$SYSTEM_PATH"
readonly TEST_CONTAINER_ID="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$TEST_BIN" "$TMP/home"

for command_name in docker psql dropdb createdb supabase; do
  cat > "$TEST_BIN/$command_name" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\t%s\n' "${0##*/}" "$*" >> "${DEEDLIGHT_SAFETY_CALL_LOG:?}"
case "${0##*/}" in
  docker)
    [[ "$#" -eq 6 && "$1" == "inspect" && "$2" == "--type" && "$3" == "container" && "$4" == "--format" ]] || exit 96
    [[ "$5" == '{{.Id}}|{{.Config.Image}}|{{.State.Running}}|{{len .NetworkSettings.Networks}}|{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ]] || exit 96
    [[ "$6" == "${POSTGRES_SERVICE_CONTAINER_ID:-}" ]] || exit 96
    printf '%s\n' "${DEEDLIGHT_TEST_DOCKER_INSPECT_OUTPUT:?}"
    exit 0
    ;;
  psql)
    printf '%s\n' "${DEEDLIGHT_TEST_PSQL_RESPONSE:-172.18.0.2|5432|deedlight_migration_order_test|postgres|160016|16.16}"
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
run_rejected_override PGHOST "localhost" hostname_alias
run_rejected_override PGHOSTADDR "203.0.113.44" remote_hostaddr
run_rejected_override PGSERVICE "production" service_name
run_rejected_override PGSERVICEFILE "$TMP/production.pg_service.conf" service_file
run_rejected_override PGDATABASE "production" database_override
run_rejected_override PGPORT "6543" remote_port
run_rejected_override PGOPTIONS "-c application_name=production" options_override
run_rejected_override PGTARGETSESSIONATTRS "read-write" target_session_override
run_rejected_override PGPASSFILE "$TMP/production.pgpass" password_file_override
run_rejected_override PGSSLMODE "require" ssl_mode_override

run_rejected_docker_metadata() {
  local metadata="$1" label="$2" log="$TMP/$2.log" status=0
  local -a calls
  : > "$CALL_LOG"
  env -i \
    "PATH=$TEST_PATH" "HOME=$TMP/home" \
    GITHUB_ACTIONS=true \
    GITHUB_REPOSITORY=ADRN-9/deedlight \
    GITHUB_JOB=delivery_migration_order_database_behavior \
    GITHUB_EVENT_NAME=pull_request \
    DELIVERY_ENABLED=false \
    "POSTGRES_SERVICE_CONTAINER_ID=$TEST_CONTAINER_ID" \
    "DEEDLIGHT_TEST_DOCKER_INSPECT_OUTPUT=$metadata" \
    "DEEDLIGHT_SAFETY_CALL_LOG=$CALL_LOG" \
    bash "$TARGET_SCRIPT" > "$log" 2>&1 || status=$?

  [[ "$status" -ne 0 ]] || fail "Unsafe Docker metadata was accepted ($label)."
  mapfile -t calls < <(cut -f1 "$CALL_LOG")
  [[ "${#calls[@]}" -eq 1 && "${calls[0]}" == "docker" ]] || {
    cat "$CALL_LOG" >&2
    fail "Invalid Docker metadata reached PostgreSQL or another command ($label)."
  }
  grep -Fq "Refusing PostgreSQL target" "$log" || {
    cat "$log" >&2
    fail "Invalid Docker metadata was not rejected fail-closed ($label)."
  }
  printf 'Docker service metadata rejected before PostgreSQL preflight (%s): PASS\n' "$label"
}

run_rejected_missing_container_id() {
  local log="$TMP/missing-container-id.log" status=0
  : > "$CALL_LOG"
  env -i \
    "PATH=$TEST_PATH" "HOME=$TMP/home" \
    GITHUB_ACTIONS=true \
    GITHUB_REPOSITORY=ADRN-9/deedlight \
    GITHUB_JOB=delivery_migration_order_database_behavior \
    GITHUB_EVENT_NAME=pull_request \
    DELIVERY_ENABLED=false \
    "DEEDLIGHT_SAFETY_CALL_LOG=$CALL_LOG" \
    bash "$TARGET_SCRIPT" > "$log" 2>&1 || status=$?
  [[ "$status" -ne 0 && ! -s "$CALL_LOG" ]] || fail "Missing service-container ID was not rejected before Docker inspection."
  grep -Fq "missing or malformed GitHub Actions service container ID" "$log" || {
    cat "$log" >&2
    fail "Missing service-container ID rejection was not explicit."
  }
  printf 'Missing PostgreSQL service-container ID rejected before Docker inspection: PASS\n'
}

run_rejected_backend_address() {
  local log="$TMP/backend-address-mismatch.log" status=0
  local -a calls
  : > "$CALL_LOG"
  env -i \
    "PATH=$TEST_PATH" "HOME=$TMP/home" \
    GITHUB_ACTIONS=true \
    GITHUB_REPOSITORY=ADRN-9/deedlight \
    GITHUB_JOB=delivery_migration_order_database_behavior \
    GITHUB_EVENT_NAME=pull_request \
    DELIVERY_ENABLED=false \
    "POSTGRES_SERVICE_CONTAINER_ID=$TEST_CONTAINER_ID" \
    "DEEDLIGHT_TEST_DOCKER_INSPECT_OUTPUT=$TEST_CONTAINER_ID|postgres:16.16|true|1|172.18.0.9" \
    "DEEDLIGHT_TEST_PSQL_RESPONSE=172.18.0.2|5432|deedlight_migration_order_test|postgres|160016|16.16" \
    "DEEDLIGHT_SAFETY_CALL_LOG=$CALL_LOG" \
    bash "$TARGET_SCRIPT" > "$log" 2>&1 || status=$?

  [[ "$status" -ne 0 ]] || fail "Unexpected PostgreSQL backend address was accepted."
  grep -Fq "backend address does not match Docker service container address (172.18.0.9)" "$log" || {
    cat "$log" >&2
    fail "Unexpected backend address did not produce the expected fail-closed error."
  }
  mapfile -t calls < <(cut -f1 "$CALL_LOG")
  [[ "${#calls[@]}" -eq 2 && "${calls[0]}" == "docker" && "${calls[1]}" == "psql" ]] || {
    cat "$CALL_LOG" >&2
    fail "Backend-address mismatch did not stop after Docker metadata and read-only PostgreSQL identity checks."
  }
  if grep -Eq : > "$CALL_LOG"
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
  "POSTGRES_SERVICE_CONTAINER_ID=$TEST_CONTAINER_ID" \
  "DEEDLIGHT_TEST_DOCKER_INSPECT_OUTPUT=$TEST_CONTAINER_ID|postgres:16.16|true|1|172.18.0.2" \
  "DEEDLIGHT_SAFETY_CALL_LOG=$CALL_LOG" \
  bash "$TARGET_SCRIPT" > "$TMP/local-allowlist.log" 2>&1 || local_status=$?

[[ "$local_status" -eq 97 ]] || {
  cat "$TMP/local-allowlist.log" >&2
  fail "Local CI target did not reach the fake createdb boundary (status=$local_status)."
}
grep -Fq "Verified isolated PostgreSQL target: client=127.0.0.1:5432/deedlight_migration_order_test user=postgres docker_service_addr=172.18.0.2 server_addr=172.18.0.2" "$TMP/local-allowlist.log" || {
  cat "$TMP/local-allowlist.log" >&2
  fail "Exact local CI target was not accepted by the Docker-bound read-only preflight."
}
grep -Fq "server_version_num=160016" "$TMP/local-allowlist.log" || fail "Numeric PostgreSQL version evidence was not logged."
grep -q '^docker' "$CALL_LOG" || fail "The local target preflight did not inspect the expected Docker service container."
grep -q '^psql' "$CALL_LOG" || fail "The local target preflight did not call the fake psql command."
grep -q '^createdb' "$CALL_LOG" || fail "The exact local target did not reach the fake createdb boundary."
grep -Fq -- "--host 127.0.0.1 --port 5432 --username postgres --dbname deedlight_migration_order_test" "$CALL_LOG" || fail "The local preflight did not use explicit loopback connection arguments."

printf 'Exact local CI target accepted; fake createdb prevented any database mutation: PASS\n'
printf 'Duplicate-007 remote-target safety regressions: PASS\n'
^(dropdb|createdb|supabase)\\t' "$CALL_LOG"; then
    cat "$CALL_LOG" >&2
    fail "Backend-address mismatch reached a destructive database or CLI command."
  fi
  printf 'Unexpected backend address rejected after mocked Docker and PostgreSQL identity checks: PASS\n'
}

run_rejected_missing_container_id
run_rejected_docker_metadata "$TEST_CONTAINER_ID|postgres:16.15|true|1|172.18.0.2" wrong_image
run_rejected_docker_metadata "$TEST_CONTAINER_ID|postgres:16.16|false|1|172.18.0.2" stopped_container
run_rejected_docker_metadata "$TEST_CONTAINER_ID|postgres:16.16|true|2|172.18.0.2" ambiguous_networks
run_rejected_docker_metadata "$TEST_CONTAINER_ID|postgres:16.16|true|1|" missing_network_address
run_rejected_docker_metadata "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff|postgres:16.16|true|1|172.18.0.2" unexpected_container_id
run_rejected_docker_metadata "$TEST_CONTAINER_ID|postgres:16.16|true|1|300.18.0.2" malformed_network_address
run_rejected_backend_address

# The documented local CI values pass the environment guard. Fake commands prevent database mutation.
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
grep -q '^psql' "$CALL_LOG" || fail "The local target preflight did not call the fake psql command."
grep -q '^createdb' "$CALL_LOG" || fail "The exact local target did not reach the fake createdb boundary."
grep -Fq -- "--host 127.0.0.1 --port 5432 --username postgres --dbname deedlight_migration_order_test" "$CALL_LOG" || fail "The local preflight did not use explicit loopback connection arguments."

printf 'Exact local CI target accepted; fake createdb prevented any database mutation: PASS\n'
printf 'Duplicate-007 remote-target safety regressions: PASS\n'
