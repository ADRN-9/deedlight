#!/usr/bin/env bash
# Creates and deletes a dedicated local synthetic PostgreSQL database. Never run on Production.
set -euo pipefail
set +x
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${DEEDLIGHT_SOURCE_REPO:-}"
SHA="c983e2ed8b93c935139c935343261570ecea6978"
CASE="${1:-}"
if [[ ! "$CASE" =~ ^(A|B|C|D|E|F|G|H|I|J)$ ]]; then
  echo 'Specify one fixture case A-J' >&2; exit 2
fi
if [[ "${DEEDLIGHT_DISPOSABLE_ACK:-}" != 'I_ACCEPT_DISPOSABLE_DATABASE_DELETION' ]]; then
  echo 'Missing explicit synthetic database deletion acknowledgement' >&2; exit 2
fi
if [[ -z "$SRC" ]] || [[ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)" != "$SHA" ]]; then
  echo "Fixture source must be the exact reviewed commit $SHA" >&2; exit 2
fi
if [[ "${PGHOST:-127.0.0.1}" != 127.0.0.1 || "${PGPORT:-5432}" != 5432 || "${PGUSER:-postgres}" != postgres ]]; then
  echo 'Fixture host/port/user mismatch' >&2; exit 2
fi
for envname in DATABASE_URL SUPABASE_URL SUPABASE_PROJECT_REF SUPABASE_SERVICE_ROLE_KEY SUPABASE_DB_PASSWORD SUPABASE_ACCESS_TOKEN RESEND_API_KEY; do
  if [[ -n "${!envname:-}" ]]; then echo "Refusing $envname in fixture environment" >&2; exit 2; fi
done
for binary in git psql createdb dropdb python3; do
  command -v "$binary" >/dev/null || { echo "Missing $binary" >&2; exit 2; }
done
PSQL=(psql -X -At -v ON_ERROR_STOP=1 --host 127.0.0.1 --port 5432 --username postgres)
DB="deedlight_audit18_${CASE,,}_$BASHPID"
OUT="${DEEDLIGHT_AUDIT_OUTPUT_DIR:-$ROOT/results/$CASE}"
mkdir -p "$OUT"
DB_CREATED=false
cleanup() {
  if [[ "$DB_CREATED" == true ]]; then
    dropdb --if-exists --host 127.0.0.1 --port 5432 --username postgres "$DB" >/dev/null 2>&1 ||
      echo "WARNING: disposable cleanup failed for $DB" >&2
  fi
}
trap cleanup EXIT
createdb --host 127.0.0.1 --port 5432 --username postgres "$DB"
DB_CREATED=true
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
esac
if [[ "$CASE" == H ]]; then
  if psql_db -c 'set role anon' --file "$ROOT/audited/00_preflight.sql" >"$OUT/preflight.txt" 2>"$OUT/preflight.stderr"; then
    python3 "$ROOT/assert_fixture_result.py" H --preflight "$OUT/preflight.txt"
  else
    if ! grep -Eiq 'permission denied|insufficient privilege|not permitted' "$OUT/preflight.stderr"; then
      echo 'Unexpected SQL error, not a safe metadata-permission denial' >&2; exit 1
    fi
    python3 "$ROOT/assert_fixture_result.py" H --preflight-error
  fi
  echo "Fixture H: metadata restricted and audit blocked"
  exit 0
fi
psql_db --file "$ROOT/audited/00_preflight.sql" >"$OUT/preflight.txt"
psql_db --file "$ROOT/audited/01_catalog_audit.sql" >"$OUT/audit.txt"
python3 "$ROOT/assert_fixture_result.py" "$CASE" --preflight "$OUT/preflight.txt" --audit "$OUT/audit.txt"
echo "Fixture $CASE: verified expected statuses from synthetic PostgreSQL"
