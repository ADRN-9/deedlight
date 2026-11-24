#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:?PGHOST must target the disposable PostgreSQL service}"
: "${PGDATABASE:?PGDATABASE must target the disposable test database}"
: "${PGUSER:?PGUSER must be the disposable database user}"

psql --no-psqlrc --set ON_ERROR_STOP=1 --file scripts/test-migration-aggregate-bootstrap.sql

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT

if psql --no-psqlrc --set ON_ERROR_STOP=1 --file supabase/run_in_sql_editor_all.sql >"$log_file" 2>&1; then
  cat "$log_file"
  echo "Expected the protected Migration 038 source-drift guard to fail closed, but the aggregate completed." >&2
  exit 1
fi

expected_error="Migration 038 rejected unreviewed function source for public.is_admin()."
if ! grep -Fq "$expected_error" "$log_file"; then
  cat "$log_file"
  echo "Aggregate failed before or for a reason other than the reviewed Migration 038 compatibility blocker." >&2
  exit 1
fi

psql --no-psqlrc --set ON_ERROR_STOP=1 --tuples-only --command "
DO \$assertions\$
DECLARE
  v_is_admin_source text;
BEGIN
  IF to_regclass('public.daily_lights') IS NULL
    OR to_regclass('public.daily_reflections') IS NULL
    OR to_regclass('public.delivery_provider_integrity_cases') IS NULL
    OR to_regclass('public.delivery_provider_integrity_conflict_evidence') IS NULL
    OR to_regclass('public.delivery_provider_integrity_conflict_history') IS NULL THEN
    RAISE EXCEPTION 'aggregate did not execute through migration 037';
  END IF;
  IF to_regprocedure('public.admin_list_delivery_provider_integrity_conflicts(text,integer)') IS NULL
    OR to_regprocedure('public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamp with time zone,bigint)') IS NOT NULL
    OR to_regprocedure('extensions.gen_random_bytes(integer)') IS NULL THEN
    RAISE EXCEPTION 'migration 037 state or migration 038 transaction rollback is incorrect';
  END IF;
  IF (SELECT count(*) FROM public.themes) <> 10
    OR (SELECT count(*) FROM public.badges) <> 3
    OR (SELECT count(*) FROM public.daily_posts) <> 1 THEN
    RAISE EXCEPTION 'bootstrap seed upsert counts or placement are incorrect';
  END IF;
  SELECT p.prosrc INTO v_is_admin_source
  FROM pg_catalog.pg_proc p
  WHERE p.oid = 'public.is_admin()'::regprocedure;
  IF v_is_admin_source NOT LIKE '%coalesce(is_suspended, false) = false%' THEN
    RAISE EXCEPTION 'unexpected final is_admin source before migration 038';
  END IF;
END
\$assertions\$;
"

echo "Disposable PostgreSQL 16: migrations 001-037 and the three bootstrap upserts executed."
echo "EXPECTED BLOCKER: migration 038 rejected public.is_admin() after Sprint 6 migration 007 replaced the reviewed source with the coalesce(is_suspended, false) variant."
echo "Migration 038 transaction rollback verified; no migration or Production history was changed."
