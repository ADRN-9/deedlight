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

# Migration 029 pins the exact reviewed migration-027 implementation before rename.
"${psql_cmd[@]}" <<'SQL'
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
SQL
"${psql_cmd[@]}" --file supabase/migrations/202611190025_delivery_provider_webhooks.sql >"$tmp/m025.log"
"${psql_cmd[@]}" --file supabase/migrations/202611190026_delivery_provider_lifecycle.sql >"$tmp/m026.log"
"${psql_cmd[@]}" --file supabase/migrations/202611200027_delivery_provider_integrity.sql >"$tmp/m027.log"
"${psql_cmd[@]}" --file supabase/migrations/202611210028_delivery_claim_lock_expiry.sql >"$tmp/m028.log"
"${psql_cmd[@]}" <<'SQL'
create table public.c323_m028_function_snapshot as
select p.proname, pg_get_functiondef(p.oid) as definition
from pg_catalog.pg_proc p
where p.oid in (
  to_regprocedure('public.authorize_delivery_job(uuid,uuid)'),
  to_regprocedure('public.mark_delivery_failed(uuid,uuid,text)')
);
do $c323$
declare
  v_crypto_schema text;
  v_functions_attested boolean;
begin
  select n.nspname into v_crypto_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_crypto_schema is null then
    raise exception 'Migration 028 test requires pgcrypto for source attestation.';
  end if;

  execute format($attestation$
    select
      exists (
        select 1 from pg_catalog.pg_proc p
        where p.oid = to_regprocedure('public.authorize_delivery_job(uuid,uuid)')
          and encode(%I.digest(convert_to(p.prosrc, 'UTF8'), 'sha256'), 'hex') = %L
          and p.prosecdef
          and p.proconfig = array['search_path=public, auth, pg_temp']::text[]
          and not has_function_privilege('anon', p.oid, 'EXECUTE')
          and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
          and has_function_privilege('service_role', p.oid, 'EXECUTE')
      )
      and exists (
        select 1 from pg_catalog.pg_proc p
        where p.oid = to_regprocedure('public.mark_delivery_failed(uuid,uuid,text)')
          and encode(%I.digest(convert_to(p.prosrc, 'UTF8'), 'sha256'), 'hex') = %L
          and p.prosecdef
          and p.proconfig = array['search_path=public, auth, pg_temp']::text[]
          and not has_function_privilege('anon', p.oid, 'EXECUTE')
          and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
          and has_function_privilege('service_role', p.oid, 'EXECUTE')
      )
  $attestation$, v_crypto_schema,
    'dea4d0ecb1518edec6c60f1ec998669af65b2164a547cffe67f5cbdaa8644215',
    v_crypto_schema,
    'c7830ca2281fa85e4466fa45c32c1067dba4c9766eeeb26d26dcdb3b46b72b78'
  ) into v_functions_attested;

  if (select count(*) from public.c323_m028_function_snapshot) <> 2
    or v_functions_attested is distinct from true then
    raise exception 'Migration 028 positive path did not install the attested service-role-only RPCs.';
  end if;
end;
$c323$;
SQL
echo "Migration 028 exact hardened RPC source and privilege attestation: PASS"
"${psql_cmd[@]}" <<'SQL'
set role service_role;
select public.record_delivery_provider_event(
  'evt_c226_migration029_replay','email.bounced','resend-c226-migration029',
  'c226-provider-replay@example.test','Permanent'
);
reset role;
create table public.c226_provider_impl_snapshot as
select pg_get_functiondef(p.oid) definition, p.proacl acl, p.prosecdef security_definer,
       p.proconfig function_config, p.proowner owner_oid, obj_description(p.oid,'pg_proc') function_comment
from pg_catalog.pg_proc p
where p.oid=to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)');
create table public.c226_provider_replay_fixture as
select event_id,provider_created_at from public.delivery_provider_events
where event_id='evt_c226_migration029_replay';
grant select on public.c226_provider_replay_fixture to service_role;
do $c226$
declare v_definition text;
begin
  select definition into v_definition from public.c226_provider_impl_snapshot;
  if v_definition is null or position('v_email := lower(btrim(p_recipient_email));' in v_definition)=0 then
    raise exception 'C226 migration-027 drift fixture could not find its source anchor.';
  end if;
  execute replace(v_definition,
    'v_email := lower(btrim(p_recipient_email));',
    'v_email := lower(btrim(p_recipient_email)); -- C226 deliberate source drift');
end;
$c226$;
SQL
if "${psql_cmd[@]}" --file supabase/migrations/202611210029_delivery_legacy_replay_guard.sql >"$tmp/m029-negative.log" 2>&1; then
  echo "ERROR: Migration 029 accepted a drifted migration-027 implementation." >&2
  exit 1
fi
if ! grep -q "Migration 029 refuses an unrecognized migration-027 provider lifecycle implementation" "$tmp/m029-negative.log"; then
  echo "ERROR: Migration 029 drift rejection occurred outside its identity check." >&2
  grep -E 'ERROR:|FATAL:' "$tmp/m029-negative.log" >&2 || true
  exit 1
fi
"${psql_cmd[@]}" <<'SQL'
do $c226$
declare v_source text;
begin
  if to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)') is null
    or to_regprocedure('public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)') is not null then
    raise exception 'Rejected migration 029 left a partial function rename.';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc p cross join public.c226_provider_impl_snapshot s
    where p.oid=to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)')
      and p.proacl is not distinct from s.acl and p.prosecdef is not distinct from s.security_definer
      and p.proconfig is not distinct from s.function_config and p.proowner is not distinct from s.owner_oid
      and obj_description(p.oid,'pg_proc') is not distinct from s.function_comment
  ) then raise exception 'Rejected migration 029 changed RPC ACL or security properties.'; end if;
  select p.prosrc into v_source from pg_catalog.pg_proc p
  where p.oid=to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)');
  if position('C226 deliberate source drift' in v_source)=0 then
    raise exception 'Failed migration 029 did not leave the deliberate drift fixture intact.';
  end if;
end;
$c226$;
set role service_role;
do $c226$
declare v_created timestamptz;
begin
  select provider_created_at into v_created from public.c226_provider_replay_fixture;
  if public.record_delivery_provider_lifecycle_event(
      'evt_c226_migration029_replay','email.bounced','resend-c226-migration029',
      'c226-provider-replay@example.test',v_created,'Permanent',null,null) is not false
    or public.record_delivery_provider_lifecycle_event(
      'evt_c226_migration029_replay','email.bounced','resend-c226-migration029',
      'c226-provider-replay@example.test',v_created,'Permanent',null) is not false
    or public.record_delivery_provider_event(
      'evt_c226_migration029_replay','email.bounced','resend-c226-migration029',
      'c226-provider-replay@example.test','Permanent') is not false then
    raise exception 'Historical 8-, 7- or 5-argument replay changed after failed migration 029.';
  end if;
end;
$c226$;
reset role;
do $c226$
declare v_definition text;
begin
  select definition into v_definition from public.c226_provider_impl_snapshot;
  execute v_definition;
end;
$c226$;
SQL
"${psql_cmd[@]}" --file supabase/migrations/202611210029_delivery_legacy_replay_guard.sql >"$tmp/m029-positive.log"
"${psql_cmd[@]}" <<'SQL'
do $c226$
begin
  if to_regprocedure('public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)') is null
    or has_function_privilege('anon','public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or has_function_privilege('authenticated','public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or has_function_privilege('service_role','public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or has_function_privilege('anon','public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or has_function_privilege('authenticated','public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or not has_function_privilege('service_role','public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE') then
    raise exception 'Migration 029 positive path failed its private ACL boundary.';
  end if;
end;
$c226$;
set role service_role;
do $c226$
declare v_created timestamptz;
begin
  select provider_created_at into v_created from public.c226_provider_replay_fixture;
  if public.record_delivery_provider_lifecycle_event(
      'evt_c226_migration029_replay','email.bounced','resend-c226-migration029',
      'c226-provider-replay@example.test',v_created,'Permanent',null,null) is not false
    or public.record_delivery_provider_lifecycle_event(
      'evt_c226_migration029_replay','email.bounced','resend-c226-migration029',
      'c226-provider-replay@example.test',v_created,'Permanent',null) is not false
    or public.record_delivery_provider_event(
      'evt_c226_migration029_replay','email.bounced','resend-c226-migration029',
      'c226-provider-replay@example.test','Permanent') is not false then
    raise exception 'Historical 8-, 7- or 5-argument replay changed after successful migration 029.';
  end if;
end;
$c226$;
reset role;
drop table public.c226_provider_replay_fixture;
drop table public.c226_provider_impl_snapshot;
SQL
echo "Migration 029 source identity drift rejection, atomic rollback and legacy replay compatibility: PASS"

# Migration 030 must reject missing or source-drifted migration-028 prerequisites atomically.
"${psql_cmd[@]}" <<'SQL'
drop function public.mark_delivery_failed(uuid,uuid,text);
SQL
if "${psql_cmd[@]}" --file supabase/migrations/202611210030_delivery_idempotency_receipt_guard.sql >"$tmp/m030-missing.log" 2>&1; then
  echo "ERROR: Migration 030 accepted a missing migration-028 prerequisite." >&2
  exit 1
fi
if ! grep -q "Migration 030 requires the exact hardened migration-028 authorize_delivery_job and mark_delivery_failed implementations" "$tmp/m030-missing.log"; then
  echo "ERROR: Migration 030 missing-prerequisite rejection came from an unexpected check." >&2
  grep -E 'ERROR:|FATAL:' "$tmp/m030-missing.log" >&2 || true
  exit 1
fi
"${psql_cmd[@]}" <<'SQL'
do $c323$
declare v_definition text;
begin
  select definition into v_definition from public.c323_m028_function_snapshot where proname = 'mark_delivery_failed';
  if v_definition is null then raise exception 'Missing mark_delivery_failed snapshot.'; end if;
  execute v_definition;
end;
$c323$;
revoke all privileges on function public.mark_delivery_failed(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.mark_delivery_failed(uuid,uuid,text) to service_role;
do $c323$
begin
  if to_regprocedure('public.authorize_delivery_idempotency_window(uuid,uuid)') is not null then
    raise exception 'Failed migration 030 installed partial provider authorization schema.';
  end if;
end;
$c323$;
SQL

# Drift authorize_delivery_job without changing its privilege boundary.
"${psql_cmd[@]}" <<'SQL'
do $c323$
declare v_definition text;
begin
  select definition into v_definition from public.c323_m028_function_snapshot where proname = 'authorize_delivery_job';
  if v_definition is null or position('v_job public.delivery_ledger%rowtype;' in v_definition) = 0 then
    raise exception 'Could not locate authorize_delivery_job source drift anchor.';
  end if;
  execute replace(v_definition,
    'v_job public.delivery_ledger%rowtype;',
    'v_job public.delivery_ledger%rowtype; -- C323 deliberate source drift');
end;
$c323$;
SQL
if "${psql_cmd[@]}" --file supabase/migrations/202611210030_delivery_idempotency_receipt_guard.sql >"$tmp/m030-drift-authorize.log" 2>&1; then
  echo "ERROR: Migration 030 accepted a drifted authorize_delivery_job prerequisite." >&2
  exit 1
fi
if ! grep -q "Migration 030 requires the exact hardened migration-028 authorize_delivery_job and mark_delivery_failed implementations" "$tmp/m030-drift-authorize.log"; then
  echo "ERROR: Migration 030 authorize_delivery_job drift rejection came from an unexpected check." >&2
  grep -E 'ERROR:|FATAL:' "$tmp/m030-drift-authorize.log" >&2 || true
  exit 1
fi
"${psql_cmd[@]}" <<'SQL'
do $c323$
declare v_definition text;
begin
  select definition into v_definition from public.c323_m028_function_snapshot where proname = 'authorize_delivery_job';
  execute v_definition;
end;
$c323$;
SQL

# Drift mark_delivery_failed independently and require the same fail-closed result.
"${psql_cmd[@]}" <<'SQL'
do $c323$
declare v_definition text;
begin
  select definition into v_definition from public.c323_m028_function_snapshot where proname = 'mark_delivery_failed';
  if v_definition is null or position('v_job public.delivery_ledger%rowtype;' in v_definition) = 0 then
    raise exception 'Could not locate mark_delivery_failed source drift anchor.';
  end if;
  execute replace(v_definition,
    'v_job public.delivery_ledger%rowtype;',
    'v_job public.delivery_ledger%rowtype; -- C323 deliberate source drift');
end;
$c323$;
SQL
if "${psql_cmd[@]}" --file supabase/migrations/202611210030_delivery_idempotency_receipt_guard.sql >"$tmp/m030-drift-failed.log" 2>&1; then
  echo "ERROR: Migration 030 accepted a drifted mark_delivery_failed prerequisite." >&2
  exit 1
fi
if ! grep -q "Migration 030 requires the exact hardened migration-028 authorize_delivery_job and mark_delivery_failed implementations" "$tmp/m030-drift-failed.log"; then
  echo "ERROR: Migration 030 mark_delivery_failed drift rejection came from an unexpected check." >&2
  grep -E 'ERROR:|FATAL:' "$tmp/m030-drift-failed.log" >&2 || true
  exit 1
fi
"${psql_cmd[@]}" <<'SQL'
do $c323$
declare v_definition text;
begin
  select definition into v_definition from public.c323_m028_function_snapshot where proname = 'mark_delivery_failed';
  execute v_definition;
end;
$c323$;
SQL
"${psql_cmd[@]}" --command="drop table public.c323_m028_function_snapshot"
echo "Migration 030 rejects missing and drifted migration-028 prerequisite RPCs atomically: PASS"

"${psql_cmd[@]}" --file supabase/migrations/202611210030_delivery_idempotency_receipt_guard.sql >"$tmp/m030.log"
"${psql_cmd[@]}" --file supabase/migrations/202611220031_delivery_final_recipient_suppression_gate.sql >"$tmp/m031.log"
"${psql_cmd[@]}" --file supabase/migrations/202611220032_resend_suppression_list_sync.sql >"$tmp/m032.log"
"${psql_cmd[@]}" --file supabase/migrations/202611220033_delivery_cross_stream_suppression_order.sql >"$tmp/m033.log"
"${psql_cmd[@]}" --file supabase/migrations/202611230034_delivery_suppression_timestamp_order.sql >"$tmp/m034.log"
"${psql_cmd[@]}" --file scripts/test-delivery-idempotency-guard.sql >"$tmp/idempotency-guard.log"
cat "$tmp/idempotency-guard.log"
"${psql_cmd[@]}" --file scripts/test-delivery-provider-suppressions.sql >"$tmp/provider-suppressions.log"
cat "$tmp/provider-suppressions.log"
echo "Migrations 030-034 delivery idempotency, final recipient, Resend suppression and timestamp ordering: PASS"

# Migration 039 replaces the unrestricted claim path with kind-bound service RPCs.
"${psql_cmd[@]}" --file supabase/migrations/202611260039_delivery_kind_scoped_claims.sql >"$tmp/m039.log"
"${psql_cmd[@]}" --file scripts/test-delivery-kind-claims.sql >"$tmp/kind-claims.log"
cat "$tmp/kind-claims.log"
echo "Migration 039 Daily/Weekly database-enforced claim isolation: PASS"

