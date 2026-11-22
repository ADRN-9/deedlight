#!/usr/bin/env bash
# Creates and deletes a dedicated local synthetic PostgreSQL database. Never run on Production.
set -euo pipefail
set +x
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${DEEDLIGHT_SOURCE_REPO:-}"
SHA="c983e2ed8b93c935139c935343261570ecea6978"
CASE="${1:-}"
if [[ ! "$CASE" =~ ^(A|B|C|D|E|F|G|H|I|J|K|L)$ ]]; then
  echo 'Specify one fixture case A-L' >&2; exit 2
fi
if [[ "${DEEDLIGHT_DISPOSABLE_ACK:-}" != 'I_ACCEPT_DISPOSABLE_DATABASE_DELETION' ]]; then
  echo 'Missing explicit synthetic database deletion acknowledgement' >&2; exit 2
fi
if [[ -z "$SRC" ]] || [[ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)" != "$SHA" ]]; then
  echo "Fixture source must be the exact reviewed commit $SHA" >&2; exit 2
fi
# GitHub-hosted disposable postgres:16.16 service only. Localhost tunnels are not proof.
if [[ "${GITHUB_ACTIONS:-}" != true || "${GITHUB_REPOSITORY:-}" != ADRN-9/deedlight
   || "${GITHUB_REF:-}" != refs/heads/security/deedlight-audit-fixtures-c18
   || "${DEEDLIGHT_AUDIT_CI_ONLY:-}" != true ]]; then
  echo 'Fixtures require the approved GitHub Actions disposable workflow' >&2
  exit 2
fi
source "$ROOT/disposable_postgres.sh"
deedlight_fixture_require_run_scope
for binary in git psql createdb dropdb python3; do
  command -v "$binary" >/dev/null || { echo "Missing $binary" >&2; exit 2; }
done
deedlight_fixture_verify_docker_service
deedlight_fixture_verify_service

PSQL=(psql -X -At -v ON_ERROR_STOP=1 --host 127.0.0.1 --port 5432 --username postgres)
FIXTURE_PID="$BASHPID"
FIXTURE_NONCE="$(deedlight_fixture_nonce)"
DB="$(deedlight_fixture_database_name "$CASE" "$FIXTURE_PID" "$FIXTURE_NONCE")"
DB_MARKER="$(deedlight_fixture_database_marker "$CASE" "$FIXTURE_PID" "$FIXTURE_NONCE")"
OUT_ROOT="${DEEDLIGHT_AUDIT_OUTPUT_DIR:-$ROOT/results}"
OUT="$(deedlight_fixture_output_path "$OUT_ROOT" "$CASE" "$FIXTURE_PID" "$FIXTURE_NONCE")"
mkdir -p "$OUT_ROOT"
mkdir "$OUT"
export DEEDLIGHT_FIXTURE_DB_NAME="$DB"
export DEEDLIGHT_FIXTURE_DB_MARKER="$DB_MARKER"
deedlight_fixture_install_cleanup_traps
deedlight_fixture_create_database "$DB" "$DB_MARKER"
printf 'Disposable database: %s\nFixture output: %s\n' "$DB" "$OUT"
psql_db() { "${PSQL[@]}" --dbname "$DB" "$@"; }
psql_db --file "$SRC/scripts/test-gentle-delivery-transport.sql" >"$OUT/fixture-setup.log"
# Synthetic fixture adapter only: source auth fixture predates migration 022's columns.
psql_db >"$OUT/fixture-adapter.log" <<'SQL'
create schema if not exists extensions;
alter extension pgcrypto set schema extensions;
alter table auth.users add column raw_user_meta_data jsonb not null default '{}'::jsonb;
alter table public.profiles add column username text;
alter table public.profiles add column display_name text;
alter table public.profiles enable row level security;
alter table public.daily_reminder_preferences enable row level security;
alter table public.newsletter_preferences enable row level security;
alter table public.weekly_goodness_features enable row level security;
SQL
psql_db --file "$SRC/supabase/migrations/202609240022_auth_pgcrypto_schema_qualification.sql" >"$OUT/m022.log"
if [[ "$CASE" != B ]]; then
  psql_db --file "$SRC/supabase/migrations/202611120023_delivery_consent_linearization.sql" >"$OUT/m023.log"
fi
if [[ "$CASE" != B && "$CASE" != C ]]; then
  psql_db --file "$SRC/supabase/migrations/202611120024_delivery_identity_lease_capacity.sql" >"$OUT/m024.log"
fi
case "$CASE" in
  D)
    psql_db >"$OUT/mutation.log" <<'SQL'
do $$
declare v_def text;
begin
  select pg_get_functiondef('public.begin_delivery_transport(uuid,uuid,text)'::regprocedure) into v_def;
  if position('p_expected_email is null' in v_def) = 0 then
    raise exception 'Missing exact mutation anchor; refuse incomplete drift fixture';
  end if;
  execute replace(v_def,'p_expected_email is null','p_expected_email is not null');
end $$;
SQL
    ;;
  E) psql_db -c 'grant execute on function public.begin_delivery_transport(uuid,uuid,text) to anon;' >"$OUT/mutation.log" ;;
  F) psql_db -c 'alter table public.delivery_ledger disable row level security;' >"$OUT/mutation.log" ;;
  G) psql_db -c 'alter function public.begin_delivery_transport(uuid,uuid,text) set search_path = public;' >"$OUT/mutation.log" ;;
  H) psql_db -c 'revoke select on pg_catalog.pg_proc from public;' >"$OUT/mutation.log" ;;
  I)
    psql_db >"$OUT/mutation.log" <<'SQL'
create schema supabase_migrations;
create table supabase_migrations.schema_migrations (version text primary key);
insert into supabase_migrations.schema_migrations(version) values ('202609230019');
SQL
    ;;
  J)
    psql_db >"$OUT/mutation.log" <<'SQL'
create function public.begin_delivery_transport(uuid,uuid)
returns timestamptz language sql as $$ select null::timestamptz $$;
SQL
    ;;
  K)
    psql_db >"$OUT/mutation.log" <<'SQL'
create schema if not exists supabase_migrations;
create table supabase_migrations.schema_migrations (version bigint primary key);
insert into supabase_migrations.schema_migrations(version) values (202609230019);
SQL
    ;;
  L)
    psql_db >"$OUT/mutation.log" <<'SQL'
create schema if not exists supabase_migrations;
create table supabase_migrations.schema_migrations (
  version text not null,
  name text,
  primary key (version, name)
);
insert into supabase_migrations.schema_migrations(version, name)
values ('202609230019', 'synthetic');
SQL
    ;;

esac
if [[ "$CASE" == H ]]; then
  if psql_db -c 'set role anon' --file "$ROOT/audited/00_preflight.sql" >"$OUT/preflight.txt" 2>"$OUT/preflight.stderr"; then
    if [[ -s "$OUT/preflight.stderr" ]]; then echo 'Unexpected preflight stderr' >&2; exit 1; fi
    python3 "$ROOT/assert_fixture_result.py" H --preflight "$OUT/preflight.txt"
  else
    python3 "$ROOT/assert_fixture_result.py" H --preflight-error --preflight-stderr "$OUT/preflight.stderr"
  fi
  echo "Fixture H: metadata restricted and audit blocked"
  exit 0
fi
psql_db --file "$ROOT/audited/00_preflight.sql" >"$OUT/preflight.txt" 2>"$OUT/preflight.stderr"
if [[ -s "$OUT/preflight.stderr" ]]; then echo 'Unexpected preflight stderr' >&2; exit 1; fi
psql_db --file "$ROOT/audited/01_catalog_audit.sql" >"$OUT/audit.txt" 2>"$OUT/audit.stderr"
if [[ -s "$OUT/audit.stderr" ]]; then echo 'Unexpected audit SQL stderr' >&2; exit 1; fi
python3 "$ROOT/assert_fixture_result.py" "$CASE" --preflight "$OUT/preflight.txt" --audit "$OUT/audit.txt"
echo "Fixture $CASE: verified expected statuses from synthetic PostgreSQL"
