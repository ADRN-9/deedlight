#!/usr/bin/env bash
set -euo pipefail

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
export PGDATABASE="${PGDATABASE:-deedlight_privacy_test}"

validate_connection_target() {
  case "$PGHOST" in
    127.0.0.1|localhost|::1) ;;
    *)
      echo "Refusing unsafe PostgreSQL destination: PGHOST must be loopback." >&2
      return 1
      ;;
  esac
  if [[ "$PGPORT" != "5432" ]]; then
    echo "Refusing unsafe PostgreSQL destination: PGPORT must be 5432." >&2
    return 1
  fi
  if [[ "$PGUSER" != "postgres" ]]; then
    echo "Refusing unsafe PostgreSQL destination: PGUSER must be postgres." >&2
    return 1
  fi
  if [[ "$PGDATABASE" != "deedlight_privacy_test" ]]; then
    echo "Refusing unsafe PostgreSQL destination: PGDATABASE must be deedlight_privacy_test." >&2
    return 1
  fi
  if [[ -n "${PGHOSTADDR:-}" || -n "${PGSERVICE:-}" || -n "${PGSERVICEFILE:-}" || -n "${PGOPTIONS:-}" ]]; then
    echo "Refusing unsafe PostgreSQL destination: PGHOSTADDR, PGSERVICE, PGSERVICEFILE and PGOPTIONS must be unset." >&2
    return 1
  fi
}

if ! validate_connection_target; then
  exit 64
fi
if [[ "${1:-}" == "--validate-config-only" ]]; then
  if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 [--validate-config-only]" >&2
    exit 64
  fi
  echo "Privacy runner destination validation PASS"
  exit 0
fi
if [[ "$#" -ne 0 ]]; then
  echo "Usage: $0 [--validate-config-only]" >&2
  exit 64
fi

psql_cmd=(psql -X -v ON_ERROR_STOP=1)

# Minimal Supabase-compatible auth/storage boundary for a disposable database.
"${psql_cmd[@]}" <<'SQL'
CREATE ROLE anon NOLOGIN NOBYPASSRLS;
CREATE ROLE authenticated NOLOGIN NOBYPASSRLS;
CREATE ROLE service_role NOLOGIN BYPASSRLS;

CREATE SCHEMA auth;
CREATE TABLE auth.users (
  id uuid PRIMARY KEY,
  email text,
  raw_user_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

CREATE SCHEMA storage;
CREATE TABLE storage.buckets (
  id text PRIMARY KEY,
  name text NOT NULL,
  public boolean NOT NULL DEFAULT false
);
CREATE TABLE storage.objects (
  bucket_id text NOT NULL,
  name text NOT NULL
);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION storage.foldername(p_name text)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
  SELECT string_to_array(p_name, '/');
$$;

GRANT USAGE ON SCHEMA public, auth, storage TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION storage.foldername(text) TO anon, authenticated, service_role;
SQL

# Apply the real migrations needed by the public projections, RLS, reactions,
# profile privacy, member moderation, Saved Lights, and owner-removal RPCs.
migrations_before_daily=(
  supabase/migrations/202607210001_initial_schema.sql
  supabase/migrations/202607210002_rls_policies.sql
  supabase/migrations/202607220003_sprint3_offerings_review.sql
  supabase/migrations/202607260004_sprint4_reactions.sql
  supabase/migrations/202607260005_sprint5_moderation.sql
  supabase/migrations/202607260006_sprint5_admin_edit_hide_hotfix.sql
)

for migration in "${migrations_before_daily[@]}"; do
  echo "Applying ${migration}"
  "${psql_cmd[@]}" --file "$migration"
done

# Sprint 6's fallback seed omits the legacy daily_posts.date column, which is
# NOT NULL in the actual initial schema. A temporary synthetic row keeps that
# unrelated seed branch from running while the real migration is applied.
"${psql_cmd[@]}" <<'SQL'
INSERT INTO public.daily_posts (
  date, slug, title, reflection, daily_action, status
)
VALUES (
  current_date,
  'c296-migration-seed-placeholder',
  'C296 migration placeholder',
  'Synthetic placeholder used only to exercise the actual Sprint 6 migration.',
  'No action; this row is removed before the behavior fixtures run.',
  'published'
);
SQL

"${psql_cmd[@]}" --file supabase/migrations/202607260007_sprint6_daily_deedlight.sql
"${psql_cmd[@]}" -c "DELETE FROM public.daily_posts WHERE slug = 'c296-migration-seed-placeholder';"

migrations_after_daily=(
  supabase/migrations/202607260007_sprint7_pwa_daily_engagement.sql
  supabase/migrations/202608060009_sprint9_profiles_privacy.sql
  supabase/migrations/202608100010_sprint9_2_community_identity_consistency.sql
  supabase/migrations/202608100011_sprint9_3_moderation_aware_members.sql
  supabase/migrations/202608110012_sprint10_1_daily_deed_completion.sql
  supabase/migrations/202608110013_sprint10_2_saved_lights_gentle_rhythm.sql
  supabase/migrations/202608130015_sprint11_2_weekly_goodness.sql
  supabase/migrations/202608130017_sprint12_1_offering_ownership_engagement.sql
  supabase/migrations/202608140018_sprint12_1_owner_removal_guard_hotfix.sql
)

for migration in "${migrations_after_daily[@]}"; do
  echo "Applying ${migration}"
  "${psql_cmd[@]}" --file "$migration"
done

echo "Verifying historical Sprint 5 Offering policy fixture"
"${psql_cmd[@]}" --file scripts/test-privacy-authorization-legacy-policy.sql

echo "Applying supabase/migrations/202611220023_sprint12_3_private_offering_base_table_access.sql"
"${psql_cmd[@]}" --file supabase/migrations/202611220023_sprint12_3_private_offering_base_table_access.sql

echo "Applying supabase/migrations/202611220024_sprint12_4_private_daily_reflection_owner_access.sql"
"${psql_cmd[@]}" --file supabase/migrations/202611220024_sprint12_4_private_daily_reflection_owner_access.sql

legacy_policy_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'offerings'
    AND policyname = 'offerings_select_public_or_own';
")"
if [[ "$legacy_policy_count" != "0" ]]; then
  echo "Migration 023 did not remove offerings_select_public_or_own." >&2
  exit 1
fi
echo "Migration 023 legacy Offering policy removal: PASS"

daily_reflection_legacy_policy_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'daily_reflections'
    AND policyname IN (
      'daily_reflections_select_own_or_admin',
      'daily reflections select own or admin'
    );
")"
if [[ "$daily_reflection_legacy_policy_count" != "0" ]]; then
  echo "Migration 024 left the historical administrator-inclusive SELECT policy." >&2
  exit 1
fi

daily_reflection_owner_policy_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'daily_reflections'
    AND (
      (policyname = 'daily_reflections_select_own'
        AND cmd = 'SELECT'
        AND coalesce(qual, '') LIKE '%user_id = auth.uid()%')
      OR
      (policyname = 'daily_reflections_insert_own'
        AND cmd = 'INSERT'
        AND coalesce(with_check, '') LIKE '%user_id = auth.uid()%')
      OR
      (policyname = 'daily_reflections_update_own'
        AND cmd = 'UPDATE'
        AND coalesce(qual, '') LIKE '%user_id = auth.uid()%'
        AND coalesce(with_check, '') LIKE '%user_id = auth.uid()%')
    );
")"
if [[ "$daily_reflection_owner_policy_count" != "3" ]]; then
  echo "Migration 024 did not install all three owner-only Daily reflection policies." >&2
  exit 1
fi

daily_reflection_select_policy_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'daily_reflections'
    AND cmd = 'SELECT';
")"
if [[ "$daily_reflection_select_policy_count" != "1" ]]; then
  echo "Daily reflection SELECT has an unexpected additional policy." >&2
  exit 1
fi
daily_reflection_insert_policy_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'daily_reflections'
    AND cmd = 'INSERT';
")"
if [[ "$daily_reflection_insert_policy_count" != "1" ]]; then
  echo "Daily reflection INSERT has an unexpected additional policy." >&2
  exit 1
fi

daily_reflection_update_policy_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'daily_reflections'
    AND cmd = 'UPDATE';
")"
if [[ "$daily_reflection_update_policy_count" != "1" ]]; then
  echo "Daily reflection UPDATE has an unexpected additional policy." >&2
  exit 1
fi
echo "Migration 024 owner-only Daily reflection policies: PASS"

cleanup_legacy_fixture() {
  "${psql_cmd[@]}" --file scripts/test-privacy-authorization-legacy-policy-cleanup.sql
  echo "Historical moderation-note fixture cleanup: PASS"
}

cleanup_check() {
  local phase="$1"
  local result

  result="$("${psql_cmd[@]}" -Atqc "
    SELECT CASE WHEN
      NOT EXISTS (
        SELECT 1 FROM auth.users
        WHERE id IN (
          '00000000-0000-4000-8000-000000000101',
          '00000000-0000-4000-8000-000000000102',
          '00000000-0000-4000-8000-000000000103',
          '00000000-0000-4000-8000-000000000104',
          '00000000-0000-4000-8000-000000000109',
          '00000000-0000-4000-8000-000000000110',
          '00000000-0000-4000-8000-000000000111'
        )
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE user_id IN (
          '00000000-0000-4000-8000-000000000101',
          '00000000-0000-4000-8000-000000000102',
          '00000000-0000-4000-8000-000000000103',
          '00000000-0000-4000-8000-000000000104',
          '00000000-0000-4000-8000-000000000109',
          '00000000-0000-4000-8000-000000000110',
          '00000000-0000-4000-8000-000000000111'
        )
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.offerings
        WHERE id BETWEEN
          '00000000-0000-4000-8000-000000000201'::uuid
          AND '00000000-0000-4000-8000-000000000205'::uuid
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.offerings
        WHERE id IN (
          '00000000-0000-4000-8000-000000000210',
          '00000000-0000-4000-8000-000000000211'
        )
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.saved_lights
        WHERE id IN (
          '00000000-0000-4000-8000-000000000301',
          '00000000-0000-4000-8000-000000000302',
          '00000000-0000-4000-8000-000000000307'
        )
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.reactions
        WHERE id BETWEEN
          '00000000-0000-4000-8000-000000000303'::uuid
          AND '00000000-0000-4000-8000-000000000310'::uuid
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.daily_lights
        WHERE id IN (
          '00000000-0000-4000-8000-000000000206',
          '00000000-0000-4000-8000-000000000207'
        )
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.daily_deed_completions
        WHERE id IN (
          '00000000-0000-4000-8000-000000000311',
          '00000000-0000-4000-8000-000000000312',
          '00000000-0000-4000-8000-000000000313',
          '00000000-0000-4000-8000-000000000314'
        )
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.weekly_goodness_features
        WHERE offering_id = '00000000-0000-4000-8000-000000000201'
          AND selected_by = '00000000-0000-4000-8000-000000000104'
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.reports
        WHERE id = '00000000-0000-4000-8000-000000000304'
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.member_moderation_events
        WHERE id = '00000000-0000-4000-8000-000000000305'
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.reflections
        WHERE id = '00000000-0000-4000-8000-000000000306'
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.daily_reflections
        WHERE reflection_text IN (
          'C296_PRIVATE_DAILY_REFLECTION_SENTINEL',
          'C298_PRIVATE_DAILY_REFLECTION_MEMBER_B_SENTINEL'
        )
          OR reflection IN (
            'C298_PRIVATE_DAILY_LIGHT_REFLECTION_MEMBER_A_SENTINEL',
            'C298_PRIVATE_DAILY_LIGHT_REFLECTION_MEMBER_B_SENTINEL'
          )
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.daily_reflections
        WHERE reflection_text IN (
          'C300_PRIVATE_DAILY_REFLECTION_OWNER_UPDATE_SENTINEL',
          'C300_PRIVATE_DAILY_REFLECTION_OWNER_INSERT_SENTINEL'
        )
          OR reflection IN (
            'C300_PRIVATE_DAILY_REFLECTION_OWNER_UPDATE_BODY_SENTINEL'
          )
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.daily_posts
        WHERE slug IN (
          'c296-privacy-test-daily-post',
          'c300-privacy-test-owner-write-daily-post'
        )
      )
      THEN 'privacy_fixture_cleanup=pass'
      ELSE 'privacy_fixture_cleanup=FAIL'
    END;
  ")"

  if [[ "$result" != "privacy_fixture_cleanup=pass" ]]; then
    echo "Fixture cleanup failed after ${phase}: ${result}" >&2
    return 1
  fi

  echo "Fixture cleanup after ${phase}: PASS"
}

# A failed psql test disconnects with its open transaction, forcing PostgreSQL
# to roll back all synthetic fixtures. Check cleanup even when assertions fail.
set +e
"${psql_cmd[@]}" --file scripts/test-privacy-authorization-database.sql
behavior_status=$?
set -e

cleanup_legacy_fixture
cleanup_check "behavior suite"

if [[ "$behavior_status" -ne 0 ]]; then
  echo "Privacy and authorization database behavior assertions FAILED." >&2
  exit "$behavior_status"
fi

# Prove that a failed test execution also rolls back auth.users and its
# trigger-created profile, then verify no fixture survives the failure.
failure_log="${RUNNER_TEMP:-/tmp}/deedlight-privacy-cleanup-failure.log"
set +e
"${psql_cmd[@]}" --file scripts/test-privacy-authorization-cleanup-failure.sql >"$failure_log" 2>&1
failure_status=$?
set -e

if [[ "$failure_status" -eq 0 ]]; then
  echo "Failure-cleanup probe unexpectedly succeeded." >&2
  exit 1
fi

if ! grep -Fq "C296 intentional cleanup probe failure" "$failure_log"; then
  cat "$failure_log" >&2
  echo "Failure-cleanup probe did not reach its intentional failure." >&2
  exit 1
fi

cleanup_legacy_fixture
cleanup_check "forced failure probe"

echo "Privacy and authorization database behavior PASS"
