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

legacy_fixture_active=0

cleanup_legacy_fixture() {
  "${psql_cmd[@]}" --file scripts/test-privacy-authorization-legacy-policy-cleanup.sql || return
  legacy_fixture_active=0
  echo "Historical moderation-note fixture cleanup: PASS"
}

cleanup_on_exit() {
  local exit_status=$?
  local cleanup_status=0
  trap - EXIT

  if [[ "$legacy_fixture_active" == "1" ]]; then
    set +e
    cleanup_legacy_fixture
    cleanup_status=$?
    set -e
    if [[ "$cleanup_status" -ne 0 ]]; then
      echo "EXIT cleanup could not remove the historical privacy fixture." >&2
      exit_status=1
    fi
  fi

  exit "$exit_status"
}
trap cleanup_on_exit EXIT

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
legacy_fixture_active=1
"${psql_cmd[@]}" --file scripts/test-privacy-authorization-legacy-policy.sql

echo "Applying supabase/migrations/202611220023_sprint12_3_private_offering_base_table_access.sql"
"${psql_cmd[@]}" --file supabase/migrations/202611220023_sprint12_3_private_offering_base_table_access.sql

echo "Applying supabase/migrations/202611220024_sprint12_4_private_daily_reflection_owner_access.sql"
"${psql_cmd[@]}" --file supabase/migrations/202611220024_sprint12_4_private_daily_reflection_owner_access.sql

echo "Applying supabase/migrations/202611220025_sprint12_5_private_daily_reflection_owner_delete.sql"
"${psql_cmd[@]}" --file supabase/migrations/202611220025_sprint12_5_private_daily_reflection_owner_delete.sql

echo "Applying supabase/migrations/202611220026_sprint12_6_daily_reflection_restrict_parent_delete.sql"
"${psql_cmd[@]}" --file supabase/migrations/202611220026_sprint12_6_daily_reflection_restrict_parent_delete.sql

echo "Applying supabase/migrations/202611220027_sprint12_7_daily_journey_restrict_parent_delete.sql"
"${psql_cmd[@]}" --file supabase/migrations/202611220027_sprint12_7_daily_journey_restrict_parent_delete.sql

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
      'daily reflections select own or admin',
      'daily_reflections_update_own_or_admin',
      'daily reflections update own or admin',
      'daily_reflections_delete_admin',
      'daily reflections delete admin'
    );
")"
if [[ "$daily_reflection_legacy_policy_count" != "0" ]]; then
  echo "Migration 024/025 left a historical administrator-inclusive Daily reflection policy." >&2
  exit 1
fi

daily_reflection_policy_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'daily_reflections';
")"
if [[ "$daily_reflection_policy_count" != "4" ]]; then
  echo "Daily reflections have unexpected additional RLS policies." >&2
  exit 1
fi

daily_reflection_admin_policy_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'daily_reflections'
    AND (
      coalesce(qual, '') || ' ' || coalesce(with_check, '')
    ) ILIKE '%is_admin%';
")"
if [[ "$daily_reflection_admin_policy_count" != "0" ]]; then
  echo "Daily reflection RLS still contains an administrator-inclusive policy." >&2
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
      OR
      (policyname = 'daily_reflections_delete_own'
        AND cmd = 'DELETE'
        AND coalesce(qual, '') LIKE '%user_id = auth.uid()%')
    );
")"
if [[ "$daily_reflection_owner_policy_count" != "4" ]]; then
  echo "Migration 024/025 did not install all four owner-only Daily reflection policies." >&2
  exit 1
fi

daily_reflection_command_counts="$("${psql_cmd[@]}" -Atqc "
  SELECT
    count(*) FILTER (WHERE cmd = 'SELECT') || ':' ||
    count(*) FILTER (WHERE cmd = 'INSERT') || ':' ||
    count(*) FILTER (WHERE cmd = 'UPDATE') || ':' ||
    count(*) FILTER (WHERE cmd = 'DELETE')
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'daily_reflections';
")"
if [[ "$daily_reflection_command_counts" != "1:1:1:1" ]]; then
  echo "Daily reflection RLS must have exactly one policy per CRUD operation." >&2
  exit 1
fi
echo "Migration 024/025 owner-only Daily reflection policies: PASS"

daily_reflection_parent_fk_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_constraint c
  JOIN pg_attribute a
    ON a.attrelid = c.conrelid
   AND a.attnum = c.conkey[1]
  WHERE c.conrelid = 'public.daily_reflections'::regclass
    AND c.contype = 'f'
    AND cardinality(c.conkey) = 1
    AND (
      (a.attname = 'daily_post_id'
        AND c.confrelid = 'public.daily_posts'::regclass)
      OR
      (a.attname = 'daily_light_id'
        AND c.confrelid = 'public.daily_lights'::regclass)
    );
")"
if [[ "$daily_reflection_parent_fk_count" != "2" ]]; then
  echo "Daily reflections must retain exactly the two expected parent foreign keys." >&2
  exit 1
fi

daily_reflection_parent_restrict_fk_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_constraint c
  JOIN pg_attribute a
    ON a.attrelid = c.conrelid
   AND a.attnum = c.conkey[1]
  WHERE c.conrelid = 'public.daily_reflections'::regclass
    AND c.contype = 'f'
    AND cardinality(c.conkey) = 1
    AND c.confdeltype = 'r'
    AND (
      (a.attname = 'daily_post_id'
        AND c.confrelid = 'public.daily_posts'::regclass)
      OR
      (a.attname = 'daily_light_id'
        AND c.confrelid = 'public.daily_lights'::regclass)
    );
")"
if [[ "$daily_reflection_parent_restrict_fk_count" != "2" ]]; then
  echo "Migration 026 did not install both restrictive Daily reflection parent foreign keys." >&2
  exit 1
fi

daily_reflection_parent_cascade_fk_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_constraint c
  JOIN pg_attribute a
    ON a.attrelid = c.conrelid
   AND a.attnum = c.conkey[1]
  WHERE c.conrelid = 'public.daily_reflections'::regclass
    AND c.contype = 'f'
    AND cardinality(c.conkey) = 1
    AND c.confdeltype = 'c'
    AND (
      (a.attname = 'daily_post_id'
        AND c.confrelid = 'public.daily_posts'::regclass)
      OR
      (a.attname = 'daily_light_id'
        AND c.confrelid = 'public.daily_lights'::regclass)
    );
")"
if [[ "$daily_reflection_parent_cascade_fk_count" != "0" ]]; then
  echo "Migration 026 left a cascading Daily reflection parent foreign key." >&2
  exit 1
fi

daily_reflection_account_erasure_fk_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_constraint
  WHERE conrelid = 'public.daily_reflections'::regclass
    AND contype = 'f'
    AND conname = 'daily_reflections_user_id_fkey'
    AND confrelid = 'auth.users'::regclass
    AND confdeltype = 'c';
")"
if [[ "$daily_reflection_account_erasure_fk_count" != "1" ]]; then
  echo "Migration 026 changed the auth.users account-erasure cascade." >&2
  exit 1
fi

daily_private_parent_fk_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_constraint c
  JOIN pg_attribute a
    ON a.attrelid = c.conrelid
   AND a.attnum = c.conkey[1]
  WHERE c.contype = 'f'
    AND cardinality(c.conkey) = 1
    AND (
      (c.conrelid = 'public.saved_lights'::regclass
        AND a.attname = 'daily_post_id'
        AND c.confrelid = 'public.daily_posts'::regclass)
      OR
      (c.conrelid = 'public.saved_lights'::regclass
        AND a.attname = 'daily_light_id'
        AND c.confrelid = 'public.daily_lights'::regclass)
      OR
      (c.conrelid = 'public.daily_deed_completions'::regclass
        AND a.attname = 'daily_post_id'
        AND c.confrelid = 'public.daily_posts'::regclass)
      OR
      (c.conrelid = 'public.daily_deed_completions'::regclass
        AND a.attname = 'daily_light_id'
        AND c.confrelid = 'public.daily_lights'::regclass)
    );
")"
if [[ "$daily_private_parent_fk_count" != "4" ]]; then
  echo "Saved Lights and Daily Journey must retain exactly four expected Daily parent foreign keys." >&2
  exit 1
fi

daily_private_parent_restrict_fk_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_constraint c
  JOIN pg_attribute a
    ON a.attrelid = c.conrelid
   AND a.attnum = c.conkey[1]
  WHERE c.contype = 'f'
    AND cardinality(c.conkey) = 1
    AND c.confdeltype = 'r'
    AND (
      (c.conrelid = 'public.saved_lights'::regclass
        AND a.attname = 'daily_post_id'
        AND c.confrelid = 'public.daily_posts'::regclass)
      OR
      (c.conrelid = 'public.saved_lights'::regclass
        AND a.attname = 'daily_light_id'
        AND c.confrelid = 'public.daily_lights'::regclass)
      OR
      (c.conrelid = 'public.daily_deed_completions'::regclass
        AND a.attname = 'daily_post_id'
        AND c.confrelid = 'public.daily_posts'::regclass)
      OR
      (c.conrelid = 'public.daily_deed_completions'::regclass
        AND a.attname = 'daily_light_id'
        AND c.confrelid = 'public.daily_lights'::regclass)
    );
")"
if [[ "$daily_private_parent_restrict_fk_count" != "4" ]]; then
  echo "Migration 027 did not install all four restrictive Saved Lights/Journey parent foreign keys." >&2
  exit 1
fi

daily_private_parent_cascade_fk_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_constraint c
  JOIN pg_attribute a
    ON a.attrelid = c.conrelid
   AND a.attnum = c.conkey[1]
  WHERE c.contype = 'f'
    AND cardinality(c.conkey) = 1
    AND c.confdeltype = 'c'
    AND (
      (c.conrelid = 'public.saved_lights'::regclass
        AND a.attname = 'daily_post_id'
        AND c.confrelid = 'public.daily_posts'::regclass)
      OR
      (c.conrelid = 'public.saved_lights'::regclass
        AND a.attname = 'daily_light_id'
        AND c.confrelid = 'public.daily_lights'::regclass)
      OR
      (c.conrelid = 'public.daily_deed_completions'::regclass
        AND a.attname = 'daily_post_id'
        AND c.confdeltype = 'c'
        AND c.confrelid = 'public.daily_posts'::regclass)
      OR
      (c.conrelid = 'public.daily_deed_completions'::regclass
        AND a.attname = 'daily_light_id'
        AND c.confdeltype = 'c'
        AND c.confrelid = 'public.daily_lights'::regclass)
    );
")"
if [[ "$daily_private_parent_cascade_fk_count" != "0" ]]; then
  echo "Migration 027 left a cascading Daily parent foreign key on private Journey or Saved Lights data." >&2
  exit 1
fi

daily_private_user_fk_cascade_count="$("${psql_cmd[@]}" -Atqc "
  SELECT count(*)
  FROM pg_constraint c
  JOIN pg_attribute a
    ON a.attrelid = c.conrelid
   AND a.attnum = c.conkey[1]
  WHERE c.contype = 'f'
    AND cardinality(c.conkey) = 1
    AND a.attname = 'user_id'
    AND c.confrelid = 'auth.users'::regclass
    AND c.confdeltype = 'c'
    AND c.conrelid IN (
      'public.saved_lights'::regclass,
      'public.daily_deed_completions'::regclass
    );
")"
if [[ "$daily_private_user_fk_cascade_count" != "2" ]]; then
  echo "Migration 027 changed the auth.users account-erasure cascades for Saved Lights or Daily Journey." >&2
  exit 1
fi
echo "Migration 027 Saved Lights/Journey parent RESTRICT and account-erasure cascade catalog checks: PASS"


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
          '00000000-0000-4000-8000-000000000105',
          '00000000-0000-4000-8000-000000000106',
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
          '00000000-0000-4000-8000-000000000105',
          '00000000-0000-4000-8000-000000000106',
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
          '00000000-0000-4000-8000-000000000307',
          '00000000-0000-4000-8000-000000000315',
          '00000000-0000-4000-8000-000000000316',
          '00000000-0000-4000-8000-000000000317',
          '00000000-0000-4000-8000-000000000321',
          '00000000-0000-4000-8000-000000000322'
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
          '00000000-0000-4000-8000-000000000207',
          '00000000-0000-4000-8000-000000000208',
          '00000000-0000-4000-8000-000000000216',
          '00000000-0000-4000-8000-000000000217',
          '00000000-0000-4000-8000-000000000218'
        )
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.daily_deed_completions
        WHERE id IN (
          '00000000-0000-4000-8000-000000000311',
          '00000000-0000-4000-8000-000000000312',
          '00000000-0000-4000-8000-000000000313',
          '00000000-0000-4000-8000-000000000314',
          '00000000-0000-4000-8000-000000000315',
          '00000000-0000-4000-8000-000000000316',
          '00000000-0000-4000-8000-000000000321',
          '00000000-0000-4000-8000-000000000322'
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
          'C300_PRIVATE_DAILY_REFLECTION_OWNER_INSERT_SENTINEL',
          'C302_ADMIN_CROSS_MEMBER_REFLECTION_INSERT_SHOULD_FAIL',
          'C302_ADMIN_CROSS_MEMBER_REFLECTION_UPDATE_SHOULD_FAIL',
          'C304_ACCOUNT_ERASURE_REFLECTION_SENTINEL'
        )
          OR reflection IN (
            'C300_PRIVATE_DAILY_REFLECTION_OWNER_UPDATE_BODY_SENTINEL'
          )
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.daily_posts
        WHERE slug IN (
          'c296-privacy-test-daily-post',
          'c300-privacy-test-owner-write-daily-post',
          'c304-privacy-test-unreferenced-daily-post',
          'c307-privacy-test-completion-only-daily-post',
          'c307-privacy-test-saved-light-only-daily-post'
        )
      )
      AND NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'offerings'
          AND policyname = 'offerings_select_public_or_own'
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
