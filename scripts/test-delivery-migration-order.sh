#!/usr/bin/env bash
set -euo pipefail

psql_cmd=(psql -X -v ON_ERROR_STOP=1 --host 127.0.0.1 --port 5432 --username postgres --dbname deedlight_migration_order_test)
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Non-Production PostgreSQL: deliberately establish schema through migration 021.
"${psql_cmd[@]}" --file scripts/test-gentle-delivery-transport.sql >"$tmp/fixture.log"

# 021 directly to 024 must reject the missing reviewed 023 contract.
if "${psql_cmd[@]}" --file supabase/migrations/202611120024_delivery_identity_lease_capacity.sql >"$tmp/negative.log" 2>&1; then
  echo "ERROR: Migration 024 unexpectedly accepted schema through 021." >&2
  exit 1
fi
if ! grep -q "Migration 024 requires reviewed migration 023 functions and attestation" "$tmp/negative.log"; then
  echo "ERROR: 024 failed for an unexpected reason, not its 023 prerequisite." >&2
  grep -E 'ERROR:|FATAL:' "$tmp/negative.log" >&2 || true
  exit 1
fi
"${psql_cmd[@]}" <<'SQL'
do $$
begin
  if to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') is not null
    or to_regprocedure('public.begin_delivery_transport(uuid,uuid)') is null then
    raise exception 'A failed 024 migration left partial authorization schema.';
  end if;
  if (select count(*) from pg_proc
      where proname='enqueue_weekly_goodness_delivery'
        and obj_description(oid,'pg_proc') =
          'deedlight:023:weekly-exclusion-before-limit:v1') > 0 then
    raise exception 'Failed migration incorrectly installed 023 attestations.';
  end if;
end;
$$;
SQL
echo "Migration 021 -> 024 fails closed with no partial schema: PASS"

"${psql_cmd[@]}" --file supabase/migrations/202611120023_delivery_consent_linearization.sql >"$tmp/m023.log"

# Retain all 023 markers and recognizable SQL predicates, but alter the
# Daily suspension decision in an otherwise valid CREATE OR REPLACE.
"${psql_cmd[@]}" <<'SQL'
do $$
declare
  v_proc regprocedure := to_regprocedure('public.enqueue_due_daily_reminders(timestamptz,integer)');
  v_definition text;
  v_comment text;
begin
  select pg_get_functiondef(v_proc), obj_description(v_proc, 'pg_proc')
    into v_definition, v_comment;
  if v_comment <> 'deedlight:023:daily-exclusion-before-limit:v1'
    or position('p.is_suspended = false' in v_definition) = 0
    or position('not exists (' in v_definition) = 0 then
    raise exception 'Drift fixture missing authentic 023 source.';
  end if;
  execute replace(v_definition, 'p.is_suspended = false', 'p.is_suspended = true');
  if obj_description(v_proc, 'pg_proc') is distinct from v_comment
    or position('not exists (' in pg_get_functiondef(v_proc)) = 0 then
    raise exception 'Drift fixture unexpectedly lost its marker or broad SQL checks.';
  end if;
end;
$$;
SQL
if "${psql_cmd[@]}" --file supabase/migrations/202611120024_delivery_identity_lease_capacity.sql >"$tmp/drift-negative.log" 2>&1; then
  echo "ERROR: 024 accepted modified 023 body with unchanged markers." >&2
  exit 1
fi
if ! grep -q "Migration 024 requires reviewed migration 023 functions and attestation" "$tmp/drift-negative.log"; then
  echo "ERROR: 024 drift failure occurred outside its prerequisite check." >&2
  grep -E 'ERROR:|FATAL:' "$tmp/drift-negative.log" >&2 || true
  exit 1
fi
"${psql_cmd[@]}" <<'SQL'
do $$
begin
  if to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') is not null
    or to_regprocedure('public.begin_delivery_transport(uuid,uuid)') is null then
    raise exception 'Drift-denied 024 left partial authorization schema.';
  end if;
  if obj_description(
    to_regprocedure('public.enqueue_due_daily_reminders(timestamptz,integer)'),
    'pg_proc') <> 'deedlight:023:daily-exclusion-before-limit:v1' then
    raise exception 'Drift-negative fixture did not retain its original comment.';
  end if;
end;
$$;
SQL
echo "021 -> 023 -> drifted function (same comment) -> 024 rejects atomically: PASS"

# Restore the reviewed 023 implementation and assert successful upgrade.
"${psql_cmd[@]}" --file supabase/migrations/202611120023_delivery_consent_linearization.sql >"$tmp/m023-restored.log"
"${psql_cmd[@]}" --file supabase/migrations/202611120024_delivery_identity_lease_capacity.sql >"$tmp/m024.log"
"${psql_cmd[@]}" <<'SQL'
do $$
begin
  if to_regprocedure('public.begin_delivery_transport(uuid,uuid)') is not null
    or to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') is null then
    raise exception '023 -> 024 did not install recipient-bound transport safely.';
  end if;
  if coalesce(obj_description(
      to_regprocedure('public.enqueue_weekly_goodness_delivery(date,timestamptz,integer)'),
      'pg_proc'), '') <> 'deedlight:023:weekly-exclusion-before-limit:v1' then
    raise exception 'Reviewed 023 contract marker was lost.';
  end if;
  if has_function_privilege('anon','public.begin_delivery_transport(uuid,uuid,text)','EXECUTE')
    or has_function_privilege('authenticated','public.begin_delivery_transport(uuid,uuid,text)','EXECUTE')
    or not has_function_privilege('service_role','public.begin_delivery_transport(uuid,uuid,text)','EXECUTE') then
    raise exception 'Recipient-bound function privilege boundary regressed.';
  end if;
end;
$$;
SQL
echo "Migration 021 -> 023 -> 024 with browser-role denial: PASS"
