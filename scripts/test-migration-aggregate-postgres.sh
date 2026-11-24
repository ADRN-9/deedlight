#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:?PGHOST must target the disposable PostgreSQL service}"
: "${PGDATABASE:?PGDATABASE must target the disposable test database}"
: "${PGUSER:?PGUSER must be the disposable database user}"

psql --no-psqlrc --set ON_ERROR_STOP=1 --file scripts/test-migration-aggregate-bootstrap.sql

aggregate_log="$(mktemp)"
compat_log="$(mktemp)"
trap 'rm -f "$aggregate_log" "$compat_log"' EXIT

if ! psql --no-psqlrc --set ON_ERROR_STOP=1 --file supabase/run_in_sql_editor_all.sql >"$aggregate_log" 2>&1; then
  cat "$aggregate_log"
  echo "Complete SQL Editor aggregate failed on disposable PostgreSQL 16." >&2
  exit 1
fi
cat "$aggregate_log"

psql --no-psqlrc --set ON_ERROR_STOP=1 --tuples-only --command "
DO \$assertions\$
DECLARE
  v_source text;
  v_hash text;
  v_crypto_schema text;
  v_suspended_not_null boolean;
BEGIN
  IF to_regclass('public.daily_lights') IS NULL
    OR to_regclass('public.daily_reflections') IS NULL
    OR to_regclass('public.delivery_provider_integrity_cases') IS NULL
    OR to_regclass('public.delivery_provider_integrity_conflict_evidence') IS NULL
    OR to_regclass('public.delivery_provider_integrity_conflict_history') IS NULL
    OR to_regprocedure('public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamp with time zone,bigint)') IS NULL
    OR to_regprocedure('public.admin_get_delivery_provider_integrity_conflict(bigint)') IS NULL THEN
    RAISE EXCEPTION 'aggregate omitted required 007/037/038 database objects';
  END IF;
  IF (SELECT count(*) FROM public.themes) <> 10
    OR (SELECT count(*) FROM public.badges) <> 3
    OR (SELECT count(*) FROM public.daily_posts) <> 1 THEN
    RAISE EXCEPTION 'bootstrap seed upsert counts or placement are incorrect';
  END IF;

  SELECT a.attnotnull INTO v_suspended_not_null
  FROM pg_catalog.pg_attribute a
  WHERE a.attrelid = 'public.profiles'::regclass
    AND a.attname = 'is_suspended'
    AND a.attnum > 0
    AND NOT a.attisdropped;
  IF v_suspended_not_null IS DISTINCT FROM true
    OR EXISTS (SELECT 1 FROM public.profiles WHERE is_suspended IS NULL) THEN
    RAISE EXCEPTION 'profiles.is_suspended NOT NULL invariant was not preserved';
  END IF;

  SELECT n.nspname INTO v_crypto_schema
  FROM pg_catalog.pg_extension e
  JOIN pg_catalog.pg_namespace n ON n.oid = e.extnamespace
  WHERE e.extname = 'pgcrypto';
  SELECT p.prosrc INTO v_source
  FROM pg_catalog.pg_proc p
  WHERE p.oid = 'public.is_admin()'::regprocedure;
  EXECUTE format('SELECT encode(%I.digest(convert_to($1, ''UTF8''), ''sha256''), ''hex'')', v_crypto_schema)
    INTO v_hash USING v_source;
  IF v_hash IS DISTINCT FROM '85e6838cf8feec05bcfe9e9051e5192bc8f0d42f7a53cb6c0450067d70bba74b' THEN
    RAISE EXCEPTION 'is_admin() source does not match Migration 038 reviewed fingerprint';
  END IF;
  IF NOT has_function_privilege('anon', 'public.is_admin()', 'EXECUTE')
    OR NOT has_function_privilege('authenticated', 'public.is_admin()', 'EXECUTE')
    OR NOT has_function_privilege('service_role', 'public.is_admin()', 'EXECUTE') THEN
    RAISE EXCEPTION 'is_admin() execution grants were not preserved';
  END IF;
END
\$assertions\$;
"

# Negative case 1: nullable suspension state must block the compatibility bridge.
psql --no-psqlrc --set ON_ERROR_STOP=1 --command "ALTER TABLE public.profiles ALTER COLUMN is_suspended DROP NOT NULL;"
if psql --no-psqlrc --set ON_ERROR_STOP=1 --file supabase/bootstrap/migration_038_admin_compatibility.sql >"$compat_log" 2>&1; then
  echo "Compatibility bridge unexpectedly accepted nullable profiles.is_suspended." >&2
  exit 1
fi
if ! grep -Fq "requires profiles.is_suspended to remain NOT NULL" "$compat_log"; then
  cat "$compat_log"
  echo "Compatibility bridge failed for an unexpected reason in nullable-column test." >&2
  exit 1
fi
psql --no-psqlrc --set ON_ERROR_STOP=1 --command "ALTER TABLE public.profiles ALTER COLUMN is_suspended SET NOT NULL;"

# Negative case 2: unknown is_admin source must remain fail-closed.
psql --no-psqlrc --set ON_ERROR_STOP=1 <<'SQL'
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $unexpected$
  SELECT false;
$unexpected$;
SQL
if psql --no-psqlrc --set ON_ERROR_STOP=1 --file supabase/bootstrap/migration_038_admin_compatibility.sql >"$compat_log" 2>&1; then
  echo "Compatibility bridge unexpectedly accepted an unknown is_admin() definition." >&2
  exit 1
fi
if ! grep -Fq "rejected unreviewed Sprint 6 is_admin() source" "$compat_log"; then
  cat "$compat_log"
  echo "Compatibility bridge failed for an unexpected reason in unknown-source test." >&2
  exit 1
fi

# Restore the exact historical Sprint 6 source to prove the approved bridge is reproducible.
psql --no-psqlrc --set ON_ERROR_STOP=1 <<'SQL'
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $sprint6$
  select exists (
    select 1
    from public.profiles
    where user_id = auth.uid()
      and role = 'admin'
      and coalesce(is_suspended, false) = false
  );
$sprint6$;
SQL
psql --no-psqlrc --set ON_ERROR_STOP=1 --file supabase/bootstrap/migration_038_admin_compatibility.sql

# Positive and negative administrator authorization behavior.
psql --no-psqlrc --set ON_ERROR_STOP=1 --tuples-only --command "
DO \$authorization\$
DECLARE
  v_admin uuid := '00000000-0000-4000-8000-000000000001';
  v_suspended uuid := '00000000-0000-4000-8000-000000000002';
  v_member uuid := '00000000-0000-4000-8000-000000000003';
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_admin, 'migration-038-admin@example.invalid'),
    (v_suspended, 'migration-038-suspended@example.invalid'),
    (v_member, 'migration-038-member@example.invalid')
  ON CONFLICT (id) DO NOTHING;

  UPDATE public.profiles SET role = 'admin', is_suspended = false WHERE user_id = v_admin;
  UPDATE public.profiles SET role = 'admin', is_suspended = true WHERE user_id = v_suspended;
  UPDATE public.profiles SET role = 'member', is_suspended = false WHERE user_id = v_member;

  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  IF public.is_admin() IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'unsuspended administrator was not authorized';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_suspended::text, true);
  IF public.is_admin() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'suspended administrator retained authorization';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_member::text, true);
  IF public.is_admin() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'ordinary member received administrator authorization';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF public.is_admin() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'anonymous request received administrator authorization';
  END IF;
END
\$authorization\$;
"

echo "Disposable PostgreSQL 16: all 39 migrations, seed, compatibility bridge, and Migration 038 executed."
echo "PASS: NOT NULL suspension invariant, exact function fingerprints, grants, and admin/suspension authorization behavior."
echo "PASS: nullable suspension and unknown is_admin() definitions are rejected fail-closed."
