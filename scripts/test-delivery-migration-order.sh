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
