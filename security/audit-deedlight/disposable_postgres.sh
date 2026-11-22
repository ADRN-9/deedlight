#!/usr/bin/env bash
# Shared lifecycle primitives for the disposable DeedLight audit PostgreSQL service.

deedlight_fixture_require_run_scope() {
  if [[ "${GITHUB_ACTIONS:-}" != "true" ||
        "${GITHUB_REPOSITORY:-}" != "ADRN-9/deedlight" ||
        "${GITHUB_REF:-}" != "refs/heads/security/deedlight-audit-fixtures-c18" ||
        "${DEEDLIGHT_AUDIT_CI_ONLY:-}" != "true" ||
        "${DEEDLIGHT_DISPOSABLE_ACK:-}" != "I_ACCEPT_DISPOSABLE_DATABASE_DELETION" ]]; then
    echo "Refusing fixture operation outside the approved GitHub Actions branch workflow" >&2
    return 1
  fi
  if [[ ! "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ ||
        ! "${GITHUB_RUN_ATTEMPT:-}" =~ ^[0-9]+$ ]]; then
    echo "Missing valid GitHub workflow run identity" >&2
    return 1
  fi
}

deedlight_fixture_verify_docker_service() {
  local container_id
  command -v docker >/dev/null || { echo "Docker is required to prove disposable service identity" >&2; return 1; }
  command -v grep >/dev/null || { echo "grep is required to prove disposable service port mapping" >&2; return 1; }
  local -a containers=()
  mapfile -t containers < <(docker ps --filter ancestor=postgres:16.16 --format '{{.ID}}')
  if [[ "${#containers[@]}" -ne 1 ]]; then
    echo "Exactly one running postgres:16.16 service container is required" >&2
    return 1
  fi
  container_id="${containers[0]}"
  if ! docker port "$container_id" 5432/tcp | grep -Eq '(^|:)5432$'; then
    echo "Disposable PostgreSQL service is not publishing the expected local port" >&2
    return 1
  fi
}

deedlight_fixture_psql() {
  psql -X -At -v ON_ERROR_STOP=1 --host 127.0.0.1 --port 5432 --username postgres "$@"
}

deedlight_fixture_verify_service() {
  local envname identity
  for envname in PGHOSTADDR PGSERVICE PGSERVICEFILE PGSYSCONFDIR PGPASSFILE PGOPTIONS PGDATABASE \
    PGSSLMODE PGSSLCERT PGSSLKEY PGSSLROOTCERT PGSSLCRL PGREQUIRESSL PGGSSENCMODE \
    PGTARGETSESSIONATTRS PGCONNECT_TIMEOUT PGCHANNELBINDING PGAPPNAME; do
    if [[ -n "${!envname:-}" ]]; then
      echo "Refusing libpq connection override $envname" >&2
      return 1
    fi
  done
  for envname in DATABASE_URL SUPABASE_URL SUPABASE_PROJECT_REF SUPABASE_SERVICE_ROLE_KEY \
    SUPABASE_DB_PASSWORD SUPABASE_ACCESS_TOKEN RESEND_API_KEY CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID; do
    if [[ -n "${!envname:-}" ]]; then
      echo "Refusing Production configuration variable $envname" >&2
      return 1
    fi
  done
  if [[ "${DELIVERY_ENABLED:-}" != "false" ]]; then
    echo "Outbound delivery must remain disabled during disposable fixture work" >&2
    return 1
  fi
  if [[ "${PGHOST:-}" != "127.0.0.1" || "${PGPORT:-}" != "5432" ||
        "${PGUSER:-}" != "postgres" || "${PGPASSWORD:-}" != "postgres" ]]; then
    echo "Disposable PostgreSQL connection identity mismatch" >&2
    return 1
  fi
  identity="$(deedlight_fixture_psql --dbname postgres --command \
    "SELECT current_database() || '|' || current_user || '|' || current_setting('server_version');")" || return 1
  if [[ "$identity" != "postgres|postgres|16.16" ]]; then
    echo "Expected the dedicated PostgreSQL 16.16 service; received a different database identity" >&2
    return 1
  fi
}

deedlight_fixture_nonce() {
  command -v python3 >/dev/null || { echo "python3 is required for invocation-unique fixture IDs" >&2; return 1; }
  python3 -c 'import secrets; print(secrets.token_hex(4))'
}

deedlight_fixture_database_name() {
  local case_name="${1,,}" pid="${2:-}" nonce="${3:-}" name
  [[ "$case_name" =~ ^[a-l]$ && "$pid" =~ ^[0-9]+$ && "$nonce" =~ ^[0-9a-f]{8}$ ]] || return 2
  name="deedlight_audit20_${GITHUB_RUN_ID}_${GITHUB_RUN_ATTEMPT}_${case_name}_${pid}_${nonce}"
  (( ${#name} <= 63 )) || { echo "Disposable database identifier exceeds PostgreSQL's limit" >&2; return 2; }
  printf '%s' "$name"
}

deedlight_fixture_database_marker() {
  local case_name="${1,,}" pid="${2:-}" nonce="${3:-}"
  [[ "$case_name" =~ ^[a-l]$ && "$pid" =~ ^[0-9]+$ && "$nonce" =~ ^[0-9a-f]{8}$ ]] || return 2
  printf 'deedlight-audit-fixture:%s:%s:%s:%s:%s' \
    "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" "$case_name" "$pid" "$nonce"
}

deedlight_fixture_output_path() {
  local root="$1" case_name="${2,,}" pid="${3:-}" nonce="${4:-}"
  [[ "$case_name" =~ ^[a-l]$ && "$pid" =~ ^[0-9]+$ && "$nonce" =~ ^[0-9a-f]{8}$ ]] || return 2
  printf '%s/%s_%s_%s_%s_%s' "${root%/}" "$case_name" "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" "$pid" "$nonce"
}

deedlight_fixture_create_database() {
  local db="$1" marker="$2"
  createdb --host 127.0.0.1 --port 5432 --username postgres "$db" "$marker"
}

deedlight_fixture_database_state() {
  local db="$1" marker="$2"
  deedlight_fixture_psql --dbname postgres --set=db="$db" --set=marker="$marker" --command="
SELECT CASE
  WHEN pg_catalog.pg_get_userbyid(datdba) <> 'postgres' THEN 'foreign'
  WHEN pg_catalog.shobj_description(oid, 'pg_database') = :'marker' THEN 'owned'
  WHEN pg_catalog.shobj_description(oid, 'pg_database') IS NULL
    OR pg_catalog.shobj_description(oid, 'pg_database') = '' THEN 'unmarked'
  ELSE 'foreign' END
FROM pg_catalog.pg_database
WHERE datname = :'db';
"
}

deedlight_fixture_identity_matches_name() {
  local db="$1" marker="$2" run_id attempt case_name pid nonce expected
  if [[ ! "$marker" =~ ^deedlight-audit-fixture:([0-9]+):([0-9]+):([a-l]):([0-9]+):([0-9a-f]{8})$ ]]; then
    return 1
  fi
  run_id="${BASH_REMATCH[1]}"
  attempt="${BASH_REMATCH[2]}"
  case_name="${BASH_REMATCH[3]}"
  pid="${BASH_REMATCH[4]}"
  nonce="${BASH_REMATCH[5]}"
  [[ "$run_id" == "$GITHUB_RUN_ID" && "$attempt" == "$GITHUB_RUN_ATTEMPT" ]] || return 1
  expected="deedlight_audit20_${run_id}_${attempt}_${case_name}_${pid}_${nonce}"
  [[ "$db" == "$expected" ]]
}

deedlight_fixture_drop_owned_database() {
  local db="$1" marker="$2" state
  state="$(deedlight_fixture_database_state "$db" "$marker")" || {
    echo "Could not verify disposable database ownership for $db" >&2
    return 1
  }
  case "$state" in
    "") return 0 ;;
    owned) ;;
    unmarked)
      if ! deedlight_fixture_identity_matches_name "$db" "$marker"; then
        echo "Refusing to drop an unmarked database without an exact run/attempt/name identity: $db" >&2
        return 1
      fi
      ;;
    *)
      echo "Refusing to drop database without this invocation's ownership marker: $db" >&2
      return 1
      ;;
  esac
  if ! dropdb --force --if-exists --host 127.0.0.1 --port 5432 --username postgres "$db"; then
    echo "Failed to force-drop owned disposable database $db" >&2
    return 1
  fi
  state="$(deedlight_fixture_database_state "$db" "$marker")" || return 1
  if [[ -n "$state" ]]; then
    echo "Disposable database remains after cleanup: $db" >&2
    return 1
  fi
}

deedlight_fixture_cleanup() {
  local original_status="${1:-0}"
  trap - EXIT INT TERM HUP
  if [[ -n "${DEEDLIGHT_FIXTURE_DB_NAME:-}" || -n "${DEEDLIGHT_FIXTURE_DB_MARKER:-}" ]]; then
    if [[ -z "${DEEDLIGHT_FIXTURE_DB_NAME:-}" || -z "${DEEDLIGHT_FIXTURE_DB_MARKER:-}" ]] ||
       ! deedlight_fixture_drop_owned_database "$DEEDLIGHT_FIXTURE_DB_NAME" "$DEEDLIGHT_FIXTURE_DB_MARKER"; then
      original_status=1
    fi
  fi
  exit "$original_status"
}

deedlight_fixture_install_cleanup_traps() {
  trap 'deedlight_fixture_cleanup "$?"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
}

deedlight_fixture_assert_no_run_databases() {
  local prefix count
  prefix="deedlight_audit20_${GITHUB_RUN_ID}_${GITHUB_RUN_ATTEMPT}_"
  count="$(deedlight_fixture_psql --dbname postgres --set=prefix="$prefix" --command="
SELECT count(*)::text
FROM pg_catalog.pg_database
WHERE pg_catalog.left(datname, pg_catalog.length(:'prefix')) = :'prefix';
")" || return 1
  if [[ "$count" != "0" ]]; then
    echo "Found $count disposable PostgreSQL database(s) left by this workflow run" >&2
    return 1
  fi
}

deedlight_fixture_cleanup_run() {
  local prefix rows db marker case_name pid expected
  deedlight_fixture_require_run_scope || return 1
  prefix="deedlight_audit20_${GITHUB_RUN_ID}_${GITHUB_RUN_ATTEMPT}_"
  rows="$(deedlight_fixture_psql --dbname postgres --field-separator=$'\t' --set=prefix="$prefix" --command="
SELECT datname, COALESCE(pg_catalog.shobj_description(oid, 'pg_database'), '')
FROM pg_catalog.pg_database
WHERE pg_catalog.left(datname, pg_catalog.length(:'prefix')) = :'prefix'
ORDER BY datname;
")" || return 1
  if [[ -n "$rows" ]]; then
    while IFS=$'\t' read -r db marker; do
      [[ -n "$db" ]] || continue
      if [[ "$db" =~ ^deedlight_audit20_${GITHUB_RUN_ID}_${GITHUB_RUN_ATTEMPT}_([a-l])_([0-9]+)_([0-9a-f]{8})$ ]]; then
        case_name="${BASH_REMATCH[1]}"
        pid="${BASH_REMATCH[2]}"
        nonce="${BASH_REMATCH[3]}"
        expected="$(deedlight_fixture_database_marker "$case_name" "$pid" "$nonce")" || return 1
        if [[ -n "$marker" && "$marker" != "$expected" ]]; then
          echo "Refusing run cleanup for an unowned database: $db" >&2
          return 1
        fi
        deedlight_fixture_drop_owned_database "$db" "$expected" || return 1
      else
        echo "Refusing run cleanup for an unexpected database name: $db" >&2
        return 1
      fi
    done <<< "$rows"
  fi
  deedlight_fixture_assert_no_run_databases
}
