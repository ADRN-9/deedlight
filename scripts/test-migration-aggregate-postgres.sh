#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:?PGHOST must target the disposable PostgreSQL service}"
: "${PGDATABASE:?PGDATABASE must target the disposable test database}"
: "${PGUSER:?PGUSER must be the disposable database user}"

psql --no-psqlrc --set ON_ERROR_STOP=1 --file scripts/test-migration-aggregate-bootstrap.sql
psql --no-psqlrc --set ON_ERROR_STOP=1 --file supabase/run_in_sql_editor_all.sql

psql --no-psqlrc --set ON_ERROR_STOP=1 --tuples-only --command "
DO \$assertions\$
BEGIN
  IF to_regclass('public.daily_lights') IS NULL
    OR to_regclass('public.daily_reflections') IS NULL
    OR to_regclass('public.delivery_provider_integrity_cases') IS NULL
    OR to_regclass('public.delivery_provider_integrity_conflict_evidence') IS NULL
    OR to_regclass('public.delivery_provider_integrity_conflict_history') IS NULL THEN
    RAISE EXCEPTION 'aggregate omitted one or more expected migration objects';
  END IF;
  IF to_regprocedure('public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamp with time zone,bigint)') IS NULL
    OR to_regprocedure('public.admin_get_delivery_provider_integrity_conflict(bigint)') IS NULL
    OR to_regprocedure('extensions.gen_random_bytes(integer)') IS NULL THEN
    RAISE EXCEPTION 'aggregate omitted a required 037/038 function or extension dependency';
  END IF;
  IF (SELECT count(*) FROM public.themes) <> 10
    OR (SELECT count(*) FROM public.badges) <> 3
    OR (SELECT count(*) FROM public.daily_posts) <> 1 THEN
    RAISE EXCEPTION 'bootstrap seed upsert counts or placement are incorrect';
  END IF;
END
\$assertions\$;
"
echo "PostgreSQL 16 SQL Editor aggregate execution PASS"
