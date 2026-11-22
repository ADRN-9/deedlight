#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly MIGRATIONS="$ROOT/supabase/migrations"
readonly S6="$MIGRATIONS/202607260007_sprint6_daily_deedlight.sql"
readonly S7="$MIGRATIONS/202607260007_sprint7_pwa_daily_engagement.sql"
readonly S8="$MIGRATIONS/202607270008_sprint8_short_video_studio.sql"
readonly M12="$MIGRATIONS/202608110012_sprint10_1_daily_deed_completion.sql"
readonly M13="$MIGRATIONS/202608110013_sprint10_2_saved_lights_gentle_rhythm.sql"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

assert_ci_context() {
  [[ "${GITHUB_ACTIONS:-}" == "true" ]] || die "This destructive migration fixture is restricted to GitHub Actions."
  [[ "${GITHUB_REPOSITORY:-}" == "ADRN-9/deedlight" ]] || die "Unexpected GitHub repository for migration fixture."
  [[ "${GITHUB_JOB:-}" == "delivery_migration_order_database_behavior" ]] || die "Unexpected GitHub job for migration fixture."
  case "${GITHUB_EVENT_NAME:-}" in
    push|pull_request) ;;
    *) die "Unsupported GitHub event for migration fixture." ;;
  esac
  [[ "${DELIVERY_ENABLED:-}" == "false" ]] || die "Delivery must remain disabled during migration fixture execution."
}

validate_libpq_environment() {
  local name
  while IFS= read -r name; do
    case "$name" in
      PGHOST)
        [[ "${!name}" == "127.0.0.1" ]] || die "Refusing PostgreSQL target: PGHOST must be exactly 127.0.0.1."
        ;;
      PGPORT)
        [[ "${!name}" == "5432" ]] || die "Refusing PostgreSQL target: PGPORT must be exactly 5432."
        ;;
      PGUSER)
        [[ "${!name}" == "postgres" ]] || die "Refusing PostgreSQL target: PGUSER must be exactly postgres."
        ;;
      PGPASSWORD)
        [[ "${!name}" == "postgres" ]] || die "Refusing PostgreSQL target: unexpected PGPASSWORD value."
        ;;
      PG*)
        die "Refusing unsupported libpq connection override: $name."
        ;;
    esac
  done < <(compgen -e | LC_ALL=C sort)
}

assert_no_privileged_configuration() {
  local name
  for name in \
    CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID \
    DATABASE_URL RESEND_API_KEY RESEND_WEBHOOK_SECRET DELIVERY_FROM_EMAIL \
    SUPABASE_ACCESS_TOKEN SUPABASE_DB_PASSWORD SUPABASE_DB_URL \
    SUPABASE_PROJECT_REF SUPABASE_SERVICE_ROLE_KEY; do
    [[ -z "${!name:-}" ]] || die "Refusing privileged configuration in migration fixture: $name."
  done
}

assert_ci_context
validate_libpq_environment
assert_no_privileged_configuration

# Strip accepted environment defaults; every database command supplies its target explicitly.
unset PGHOST PGPORT PGUSER PGPASSWORD
readonly DB_HOST="127.0.0.1"
readonly DB_PORT="5432"
readonly DB_USER="postgres"
readonly CONTROL_DB="deedlight_migration_order_test"
export PGPASSWORD="postgres"

verify_postgres_target() {
  local observed server_addr server_port database username server_version_num server_version
  if ! observed="$(psql -X -A -t -F '|' -v ON_ERROR_STOP=1 \
    --host "$DB_HOST" --port "$DB_PORT" --username "$DB_USER" --dbname "$CONTROL_DB" \
    --command "select coalesce(inet_server_addr()::text, ''), inet_server_port(), current_database(), current_user, current_setting('server_version_num'), current_setting('server_version')")"; then
    die "Could not verify the isolated PostgreSQL service before database operations."
  fi

  IFS='|' read -r server_addr server_port database username server_version_num server_version <<< "$observed"
  [[ -n "$server_addr" ]] || die "Refusing PostgreSQL target: the server did not report a TCP address."
  [[ "$server_port" == "$DB_PORT" ]] || die "Refusing PostgreSQL target: server port is not 5432."
  [[ "$database" == "$CONTROL_DB" ]] || die "Refusing PostgreSQL target: unexpected control database."
  [[ "$username" == "$DB_USER" ]] || die "Refusing PostgreSQL target: unexpected database user."
  [[ "$server_version_num" == "160016" ]] || die "Expected PostgreSQL 16.16 (server_version_num=160016), got ${server_version_num:-unknown}."

  printf 'Verified isolated PostgreSQL client target: %s:%s/%s as %s; server_addr=%s server_port=%s; PostgreSQL %s (server_version_num=%s)\n' \
    "$DB_HOST" "$DB_PORT" "$database" "$username" "$server_addr" "$server_port" "$server_version" "$server_version_num"
}

# This read-only identity/version check runs before temp setup, cleanup traps, or any DROP/CREATE.
verify_postgres_target

readonly TMP="$(mktemp -d)"
readonly DB_S6_S7="deedlight_007_s6_s7"
readonly DB_S7_S6="deedlight_007_s7_s6"
readonly DB_DEPS="deedlight_007_dependencies"
readonly DB_013_FIRST="deedlight_007_013_before_012"

cleanup() {
  local exit_code=$?
  local cleanup_failed=0
  trap - EXIT
  for db in "$DB_S6_S7" "$DB_S7_S6" "$DB_DEPS" "$DB_013_FIRST"; do
    if ! dropdb --if-exists --host "$DB_HOST" --port "$DB_PORT" --username "$DB_USER" "$db" >/dev/null; then
      printf 'ERROR: cleanup could not drop isolated fixture database %s\n' "$db" >&2
      cleanup_failed=1
    fi
  done
  rm -rf "$TMP"
  if (( cleanup_failed == 1 && exit_code == 0 )); then
    exit_code=1
  fi
  exit "$exit_code"
}
trap cleanup EXIT

psql_db() {
  local db="$1"
  shift
  psql -X -v ON_ERROR_STOP=1 --host "$DB_HOST" --port "$DB_PORT" --username "$DB_USER" --dbname "$db" "$@"
}

db_url() {
  printf 'postgresql://%s:%s@%s:%s/%s' "$DB_USER" "$PGPASSWORD" "$DB_HOST" "$DB_PORT" "$1"
}

reset_db() {
  local db="$1"
  dropdb --if-exists --host "$DB_HOST" --port "$DB_PORT" --username "$DB_USER" "$db" >/dev/null 2>&1 || true
  createdb --host "$DB_HOST" --port "$DB_PORT" --username "$DB_USER" "$db"
  psql_db "$db" <<'SQL'
create extension if not exists pgcrypto;
do $roles$
declare role_name text;
begin
  foreach role_name in array array['anon','authenticated','service_role'] loop
    if not exists (select 1 from pg_roles where rolname=role_name) then
      execute format('create role %I nologin', role_name);
    end if;
  end loop;
end;
$roles$;
create schema auth;
create table auth.users (id uuid primary key);
create or replace function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;
create table public.profiles (
  user_id uuid primary key,
  role text not null default 'member',
  is_suspended boolean not null default false
);
create table public.offerings (id uuid primary key default gen_random_uuid());
create or replace function public.is_admin()
returns boolean language sql security definer set search_path=public as $$ select false $$;
SQL
}

write_cli_project() {
  local project="$1" order="$2"
  mkdir -p "$project/supabase/migrations"
  cat > "$project/supabase/config.toml" <<'TOML'
project_id = "deedlight-duplicate-migration-regression"
[api]
enabled = false
[db]
[db.migrations]
enabled = true
[db.seed]
enabled = false
TOML
  if [[ "$order" == "s6-s7" ]]; then
    cp "$S6" "$project/supabase/migrations/202607260007_sprint6_daily_deedlight.sql"
    cp "$S7" "$project/supabase/migrations/202607260007_sprint7_pwa_daily_engagement.sql"
  else
    # Temporary test names reverse the same-version tie without renaming historical migrations.
    cp "$S7" "$project/supabase/migrations/202607260007_a_sprint7_pwa_daily_engagement.sql"
    cp "$S6" "$project/supabase/migrations/202607260007_z_sprint6_daily_deedlight.sql"
  fi
}

assert_cli_order() {
  local order="$1" db="$2" expected_state="$3" first_name="$4"
  local project="$TMP/$order" log="$TMP/$order.log" status=0
  reset_db "$db"
  write_cli_project "$project" "$order"

  if (cd "$project" && supabase db push --db-url "$(db_url "$db")" --yes) >"$log" 2>&1; then
    echo "ERROR: duplicate-version db push unexpectedly succeeded ($order)." >&2
    cat "$log" >&2
    exit 1
  else
    status=$?
  fi
  if ! grep -Fq "SQLSTATE $expected_state" "$log"; then
    echo "ERROR: expected SQLSTATE $expected_state from Supabase CLI ($order)." >&2
    cat "$log" >&2
    exit 1
  fi

  local recorded_name
  recorded_name="$(psql_db "$db" -Atqc "select name from supabase_migrations.schema_migrations where version='202607260007'")"
  [[ "$recorded_name" == "$first_name" ]]
  [[ "$(psql_db "$db" -Atqc "select count(*) from supabase_migrations.schema_migrations where version='202607260007'")" == "1" ]]

  if [[ "$order" == "s6-s7" ]]; then
    grep -Fq "Applying migration 202607260007_sprint6_daily_deedlight.sql" "$log"
    grep -Fq "Applying migration 202607260007_sprint7_pwa_daily_engagement.sql" "$log"
    grep -Fq "INSERT INTO supabase_migrations.schema_migrations" "$log"
    psql_db "$db" <<'SQL'
do $assert$
declare
  cols text[] := array['id','user_id','daily_post_id','daily_light_id','reflection_text','did_today_deed','mood_label','is_private','reflection','intention','created_at','updated_at'];
  policies text[] := array['daily_reflections_select_own_or_admin','daily_reflections_insert_own','daily_reflections_update_own','daily_reflections_delete_admin','daily reflections select own or admin','daily reflections insert own','daily reflections update own or admin'];
  missing text;
begin
  if to_regclass('public.daily_posts') is null or to_regclass('public.daily_lights') is null then
    raise exception 'Expected both Daily Post and Daily Light tables after Sprint 7 commit';
  end if;
  select c into missing from unnest(cols) as x(c)
  where not exists (select 1 from information_schema.columns where table_schema='public' and table_name='daily_reflections' and column_name=c) limit 1;
  if missing is not null then raise exception 'Missing reflection column: %', missing; end if;
  if (select count(*) from pg_constraint where conrelid='public.daily_reflections'::regclass and contype='u' and conname in ('daily_reflections_unique_user_post','daily_reflections_daily_light_user_unique')) <> 2 then
    raise exception 'Missing Sprint 6/7 reflection unique constraints';
  end if;
  if (select count(*) from pg_indexes where schemaname='public' and tablename='daily_reflections' and indexname in ('daily_reflections_post_idx','daily_reflections_user_idx')) <> 2 then
    raise exception 'Missing Sprint 6 reflection indexes';
  end if;
  if (select count(*) from pg_trigger where tgrelid in ('public.daily_reflections'::regclass,'public.daily_posts'::regclass) and not tgisinternal and tgname in ('set_daily_reflections_updated_at','set_daily_posts_updated_at')) <> 2 then
    raise exception 'Missing Sprint 6 update triggers';
  end if;
  select c into missing from unnest(policies) as x(c)
  where not exists (select 1 from pg_policies where schemaname='public' and tablename='daily_reflections' and policyname=c) limit 1;
  if missing is not null then raise exception 'Missing reflection policy: %', missing; end if;
  if (select count(*) from pg_policies where schemaname='public' and tablename='daily_reflections') <> 7 then
    raise exception 'Expected all seven Sprint 6/7 reflection policies';
  end if;
  if (select is_nullable from information_schema.columns where table_schema='public' and table_name='daily_reflections' and column_name='daily_post_id') <> 'NO'
    or (select is_nullable from information_schema.columns where table_schema='public' and table_name='daily_reflections' and column_name='user_id') <> 'NO' then
    raise exception 'Sprint 6 daily_post_id/user_id NOT NULL contracts not present';
  end if;
end;
$assert$;
SQL
  else
    grep -Fq "Applying migration 202607260007_a_sprint7_pwa_daily_engagement.sql" "$log"
    grep -Fq "Applying migration 202607260007_z_sprint6_daily_deedlight.sql" "$log"
    grep -Fq "daily_reflections_post_idx" "$log"
    grep -Fq "daily_post_id" "$log"
    psql_db "$db" <<'SQL'
do $assert$
declare
  cols text[] := array['id','user_id','daily_light_id','reflection','intention','created_at','updated_at'];
  policies text[] := array['daily reflections select own or admin','daily reflections insert own','daily reflections update own or admin'];
  missing text;
begin
  if to_regclass('public.daily_posts') is not null or to_regprocedure('public.set_updated_at()') is not null then
    raise exception 'Failed Sprint 6 left Daily Post/function DDL behind';
  end if;
  if position('SELECT FALSE' in upper(pg_get_functiondef('public.is_admin()'::regprocedure))) = 0 then
    raise exception 'Failed Sprint 6 did not roll back is_admin() replacement';
  end if;
  select c into missing from unnest(cols) as x(c)
  where not exists (select 1 from information_schema.columns where table_schema='public' and table_name='daily_reflections' and column_name=c) limit 1;
  if missing is not null then raise exception 'Missing Sprint 7 reflection column after rollback: %', missing; end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='daily_reflections' and column_name in ('daily_post_id','reflection_text','did_today_deed','mood_label','is_private')) then
    raise exception 'Failed Sprint 6 left partial reflection columns';
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.daily_reflections'::regclass and conname='daily_reflections_daily_light_user_unique' and contype='u') then
    raise exception 'Sprint 7 unique reflection constraint missing';
  end if;
  if exists (select 1 from pg_constraint where conrelid='public.daily_reflections'::regclass and conname='daily_reflections_unique_user_post')
    or exists (select 1 from pg_indexes where schemaname='public' and tablename='daily_reflections' and indexname in ('daily_reflections_post_idx','daily_reflections_user_idx'))
    or exists (select 1 from pg_trigger where tgrelid='public.daily_reflections'::regclass and not tgisinternal and tgname='set_daily_reflections_updated_at') then
    raise exception 'Failed Sprint 6 left a constraint, index, or trigger';
  end if;
  select c into missing from unnest(policies) as x(c)
  where not exists (select 1 from pg_policies where schemaname='public' and tablename='daily_reflections' and policyname=c) limit 1;
  if missing is not null then raise exception 'Missing Sprint 7 reflection policy: %', missing; end if;
  if (select count(*) from pg_policies where schemaname='public' and tablename='daily_reflections') <> 3 then
    raise exception 'Expected only three Sprint 7 reflection policies after rollback';
  end if;
  if (select is_nullable from information_schema.columns where table_schema='public' and table_name='daily_reflections' and column_name='user_id') <> 'YES'
    or (select is_nullable from information_schema.columns where table_schema='public' and table_name='daily_reflections' and column_name='daily_light_id') <> 'YES' then
    raise exception 'Sprint 7 nullable identity/source columns changed unexpectedly';
  end if;
end;
$assert$;
SQL
  fi

  echo "Supabase CLI $cli_version order=$order exit=$status SQLSTATE=$expected_state"
  grep -E -A3 -B2 "SQLSTATE $expected_state|At statement:|daily_reflections_post_idx|schema_migrations" "$log" | tail -n 24 || true
}

seed_legacy_tables() {
  local db="$1"
  psql_db "$db" <<'SQL'
create table public.daily_deed_completions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  daily_post_id uuid not null references public.daily_posts(id) on delete cascade,
  status text not null default 'completed' check (status in ('try','completed')),
  created_at timestamptz not null default now(),
  unique (user_id,daily_post_id,status)
);
create table public.saved_lights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  offering_id uuid references public.offerings(id) on delete cascade,
  daily_post_id uuid references public.daily_posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint saved_lights_check check ((offering_id is not null) <> (daily_post_id is not null))
);
SQL
}

assert_dependency_state() {
  local db="$1"
  psql_db "$db" <<'SQL'
do $assert$
declare
  missing text;
  reflection_cols text[] := array['id','user_id','daily_post_id','daily_light_id','reflection_text','did_today_deed','mood_label','is_private','reflection','intention','created_at','updated_at'];
  reflection_policies text[] := array['daily_reflections_select_own_or_admin','daily_reflections_insert_own','daily_reflections_update_own','daily_reflections_delete_admin','daily reflections select own or admin','daily reflections insert own','daily reflections update own or admin'];
  video_cols text[] := array['video_status','video_platform','video_hashtags','video_notes','video_asset_url','tiktok_url','instagram_url','short_video_public','video_posted_at'];
begin
  select c into missing from unnest(reflection_cols) as x(c)
  where not exists (select 1 from information_schema.columns where table_schema='public' and table_name='daily_reflections' and column_name=c) limit 1;
  if missing is not null then raise exception 'Dependency replay missing reflection column %', missing; end if;
  if (select count(*) from pg_constraint where conrelid='public.daily_reflections'::regclass and conname in ('daily_reflections_unique_user_post','daily_reflections_daily_light_user_unique','daily_reflections_has_daily_source')) <> 3 then
    raise exception 'Dependency replay missing reflection constraints';
  end if;
  if (select is_nullable from information_schema.columns where table_schema='public' and table_name='daily_reflections' and column_name='daily_post_id') <> 'YES' then
    raise exception 'Migration 012 did not make reflection daily_post_id nullable';
  end if;
  if (select count(*) from pg_indexes where schemaname='public' and tablename='daily_reflections' and indexname in ('daily_reflections_post_idx','daily_reflections_user_idx')) <> 2 then
    raise exception 'Dependency replay missing Sprint 6 reflection indexes';
  end if;
  if (select count(*) from pg_trigger where tgrelid='public.daily_reflections'::regclass and not tgisinternal and tgname='set_daily_reflections_updated_at') <> 1 then
    raise exception 'Dependency replay missing reflection update trigger';
  end if;
  select c into missing from unnest(reflection_policies) as x(c)
  where not exists (select 1 from pg_policies where schemaname='public' and tablename='daily_reflections' and policyname=c) limit 1;
  if missing is not null then raise exception 'Dependency replay missing reflection policy %', missing; end if;
  if (select count(*) from pg_policies where schemaname='public' and tablename='daily_reflections') <> 7 then
    raise exception 'Dependency replay expected seven reflection policies';
  end if;
  if (select count(*) from information_schema.columns where table_schema='public' and table_name='daily_lights' and column_name=any(video_cols)) <> cardinality(video_cols) then
    raise exception 'Migration 008 missing video-planning columns';
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.daily_lights'::regclass and conname='daily_lights_video_status_check')
    or (select count(*) from pg_indexes where schemaname='public' and tablename='daily_lights' and indexname in ('daily_lights_video_status_idx','daily_lights_video_public_idx','daily_lights_video_posted_at_idx')) <> 3 then
    raise exception 'Migration 008 missing video constraint/indexes';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='daily_deed_completions' and column_name='daily_light_id')
    or not exists (select 1 from pg_constraint where conrelid='public.daily_deed_completions'::regclass and conname='daily_deed_completions_has_source')
    or (select is_nullable from information_schema.columns where table_schema='public' and table_name='daily_deed_completions' and column_name='daily_post_id') <> 'YES' then
    raise exception 'Migration 012 missing completion source contract';
  end if;
  if (select count(*) from pg_indexes where schemaname='public' and tablename='daily_deed_completions' and indexname in ('daily_deed_completions_user_light_unique','daily_deed_completions_light_created_idx','daily_deed_completions_user_created_idx')) <> 3
    or (select count(*) from pg_policies where schemaname='public' and tablename='daily_deed_completions' and policyname in ('daily_deed_completions_select_own','daily_deed_completions_insert_own_published','daily_deed_completions_delete_own')) <> 3
    or to_regclass('public.daily_deed_completion_counts') is null then
    raise exception 'Migration 012 missing completion indexes/policies/count view';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='saved_lights' and column_name='daily_light_id')
    or not exists (select 1 from pg_constraint where conrelid='public.saved_lights'::regclass and conname='saved_lights_exactly_one_source')
    or (select count(*) from pg_indexes where schemaname='public' and tablename='saved_lights' and indexname in ('saved_lights_unique_daily_light','saved_lights_user_created_idx')) <> 2
    or (select count(*) from pg_policies where schemaname='public' and tablename='saved_lights' and policyname in ('saved_lights_select_own','saved_lights_insert_own_published_daily_light','saved_lights_delete_own')) <> 3
    or has_table_privilege('authenticated','public.saved_lights','UPDATE') then
    raise exception 'Migration 013 missing saved-light contract or retained UPDATE privilege';
  end if;
end;
$assert$;
SQL
}

echo "=== Supabase CLI duplicate-version behavior ==="
assert_cli_order "s6-s7" "$DB_S6_S7" "23505" "sprint6_daily_deedlight"
assert_cli_order "s7-s6" "$DB_S7_S6" "42703" "a_sprint7_pwa_daily_engagement"

echo "=== PostgreSQL 16 dependency replay: 007 -> 008 -> 012 -> 013 ==="
reset_db "$DB_DEPS"
psql_db "$DB_DEPS" --file "$S6" >"$TMP/deps-s6.log"
psql_db "$DB_DEPS" --file "$S7" >"$TMP/deps-s7.log"
seed_legacy_tables "$DB_DEPS"
psql_db "$DB_DEPS" --file "$S8" >"$TMP/deps-008.log"
psql_db "$DB_DEPS" --file "$M12" >"$TMP/deps-012.log"
psql_db "$DB_DEPS" --file "$M13" >"$TMP/deps-013.log"
assert_dependency_state "$DB_DEPS"
echo "PostgreSQL 16 dependency sequence 007(S6+S7) -> 008 -> 012 -> 013: PASS"

echo "=== SQL dependency distinction: 013 before 012 ==="
reset_db "$DB_013_FIRST"
psql_db "$DB_013_FIRST" --file "$S6" >"$TMP/013-first-s6.log"
psql_db "$DB_013_FIRST" --file "$S7" >"$TMP/013-first-s7.log"
seed_legacy_tables "$DB_013_FIRST"
psql_db "$DB_013_FIRST" --file "$S8" >"$TMP/013-first-008.log"
psql_db "$DB_013_FIRST" --file "$M13" >"$TMP/013-first-013.log"
psql_db "$DB_013_FIRST" -Atqc "select count(*)=1 from information_schema.columns where table_schema='public' and table_name='saved_lights' and column_name='daily_light_id'" | grep -qx t
psql_db "$DB_013_FIRST" -Atqc "select count(*)=0 from information_schema.columns where table_schema='public' and table_name='daily_deed_completions' and column_name='daily_light_id'" | grep -qx t
psql_db "$DB_013_FIRST" --file "$M12" >"$TMP/013-first-012.log"
assert_dependency_state "$DB_013_FIRST"
echo "Migration 013 SQL succeeds before 012; 012 later installs completion-source contract: PASS"

echo "Duplicate 007 order, CLI transaction boundaries, reflection contracts, and 008/012/013 dependencies: PASS"
