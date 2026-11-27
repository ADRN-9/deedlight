\set ON_ERROR_STOP on

-- This suite runs after migration 039 on a disposable PostgreSQL 16 database.
-- All records use synthetic IDs and addresses; no provider or Production IO.
insert into public.delivery_ledger (
  id, user_id, kind, delivery_key, state, scheduled_for,
  claim_token, claimed_at, claim_expires_at, attempt_count
) values
  ('91000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000002',
   'daily_reminder','daily:c525:queued','queued',clock_timestamp() - interval '2 minutes',
   null,null,null,0),
  ('91000000-0000-0000-0000-000000000102','00000000-0000-0000-0000-000000000002',
   'weekly_newsletter','weekly:c525:queued','queued',clock_timestamp() - interval '2 minutes',
   null,null,null,0),
  ('91000000-0000-0000-0000-000000000103','00000000-0000-0000-0000-000000000002',
   'daily_reminder','daily:c525:expired','claimed',clock_timestamp() - interval '3 minutes',
   '92000000-0000-0000-0000-000000000103',clock_timestamp() - interval '10 minutes',
   clock_timestamp() - interval '1 minute',1),
  ('91000000-0000-0000-0000-000000000104','00000000-0000-0000-0000-000000000002',
   'weekly_newsletter','weekly:c525:expired','claimed',clock_timestamp() - interval '3 minutes',
   '92000000-0000-0000-0000-000000000104',clock_timestamp() - interval '10 minutes',
   clock_timestamp() - interval '1 minute',1),
  ('91000000-0000-0000-0000-000000000105','00000000-0000-0000-0000-000000000002',
   'daily_reminder','daily:c525:exhausted','claimed',clock_timestamp() - interval '4 minutes',
   '92000000-0000-0000-0000-000000000105',clock_timestamp() - interval '10 minutes',
   clock_timestamp() - interval '1 minute',5),
  ('91000000-0000-0000-0000-000000000106','00000000-0000-0000-0000-000000000002',
   'weekly_newsletter','weekly:c525:exhausted','claimed',clock_timestamp() - interval '4 minutes',
   '92000000-0000-0000-0000-000000000106',clock_timestamp() - interval '10 minutes',
   clock_timestamp() - interval '1 minute',5);

do $privileges$
begin
  if has_function_privilege('anon','public.claim_daily_delivery_jobs(integer)','EXECUTE')
    or has_function_privilege('authenticated','public.claim_daily_delivery_jobs(integer)','EXECUTE')
    or not has_function_privilege('service_role','public.claim_daily_delivery_jobs(integer)','EXECUTE')
    or has_function_privilege('anon','public.claim_weekly_delivery_jobs(integer)','EXECUTE')
    or has_function_privilege('authenticated','public.claim_weekly_delivery_jobs(integer)','EXECUTE')
    or not has_function_privilege('service_role','public.claim_weekly_delivery_jobs(integer)','EXECUTE') then
    raise exception 'Kind-specific claim RPC privilege boundary is invalid.';
  end if;

  if has_function_privilege('service_role','public.claim_delivery_jobs(timestamp with time zone,integer)','EXECUTE')
    or has_function_privilege('service_role','public._claim_delivery_jobs_for_kind(text,timestamp with time zone,integer)','EXECUTE') then
    raise exception 'Generic or internal claim function remains callable by service_role.';
  end if;
end;
$privileges$;

set role service_role;
do $daily$
declare
  v_count integer;
begin
  select count(*) into v_count from public.claim_daily_delivery_jobs(10)
  where job_id in ('91000000-0000-0000-0000-000000000101','91000000-0000-0000-0000-000000000103');
  if v_count <> 2 then
    raise exception 'Daily claim should claim exactly its queued and expired-retry rows; got %.', v_count;
  end if;

  if exists (
    select 1 from public.delivery_ledger
    where id in (
      '91000000-0000-0000-0000-000000000101',
      '91000000-0000-0000-0000-000000000103'
    )
      and (state <> 'claimed' or kind <> 'daily_reminder'
        or claim_token is null or claim_expires_at <= clock_timestamp()
        or attempt_count <> case when id='91000000-0000-0000-0000-000000000101' then 1 else 2 end)
  ) then
    raise exception 'Daily rows were not claimed with a fresh token and finite lease.';
  end if;

  if exists (
    select 1 from public.delivery_ledger
    where id in (
      '91000000-0000-0000-0000-000000000102',
      '91000000-0000-0000-0000-000000000104',
      '91000000-0000-0000-0000-000000000106'
    )
      and (state <> case when id='91000000-0000-0000-0000-000000000102' then 'queued' else 'claimed' end
        or claim_token is distinct from case
          when id='91000000-0000-0000-0000-000000000104' then '92000000-0000-0000-0000-000000000104'::uuid
          when id='91000000-0000-0000-0000-000000000106' then '92000000-0000-0000-0000-000000000106'::uuid
          else null end)
  ) then
    raise exception 'Daily claim mutated a Weekly queued, expired, or exhausted job.';
  end if;

  if not exists (
    select 1 from public.delivery_ledger
    where id='91000000-0000-0000-0000-000000000105'
      and kind='daily_reminder' and state='failed'
      and error_code='retry_exhausted' and claim_token is null
  ) then
    raise exception 'Daily claim did not terminalize only its own exhausted lease.';
  end if;

  begin
    perform public.claim_daily_delivery_jobs(0);
    raise exception 'Daily claim accepted zero batch size.';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.claim_daily_delivery_jobs(1001);
    raise exception 'Daily claim accepted oversized batch size.';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.claim_daily_delivery_jobs(null);
    raise exception 'Daily claim accepted null batch size.';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.claim_weekly_delivery_jobs(0);
    raise exception 'Weekly claim accepted zero batch size.';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.claim_weekly_delivery_jobs(1001);
    raise exception 'Weekly claim accepted oversized batch size.';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.claim_weekly_delivery_jobs(null);
    raise exception 'Weekly claim accepted null batch size.';
  exception when sqlstate '22023' then null;
  end;

  begin
    perform * from public.claim_delivery_jobs(clock_timestamp(), 10);
    raise exception 'Service role executed the legacy unrestricted claim RPC.';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from public._claim_delivery_jobs_for_kind('daily_reminder', clock_timestamp(), 10);
    raise exception 'Service role executed the private claim implementation.';
  exception when insufficient_privilege then null;
  end;
end;
$daily$;
reset role;

-- A stale token from before the Daily reclaim cannot authorize the same row.
set role service_role;
do $stale$
begin
  begin
    perform public.authorize_delivery_job(
      '91000000-0000-0000-0000-000000000103',
      '92000000-0000-0000-0000-000000000103'
    );
    raise exception 'A stale pre-reclaim Daily claim token was accepted.';
  exception when insufficient_privilege then null;
  end;
end;
$stale$;
reset role;

set role service_role;
do $weekly$
declare
  v_count integer;
begin
  select count(*) into v_count from public.claim_weekly_delivery_jobs(10)
  where job_id in ('91000000-0000-0000-0000-000000000102','91000000-0000-0000-0000-000000000104');
  if v_count <> 2 then
    raise exception 'Weekly claim should claim exactly its queued and expired-retry rows; got %.', v_count;
  end if;

  if exists (
    select 1 from public.delivery_ledger
    where id in (
      '91000000-0000-0000-0000-000000000102',
      '91000000-0000-0000-0000-000000000104'
    )
      and (state <> 'claimed' or kind <> 'weekly_newsletter'
        or claim_token is null or claim_expires_at <= clock_timestamp()
        or attempt_count <> case when id='91000000-0000-0000-0000-000000000102' then 1 else 2 end)
  ) then
    raise exception 'Weekly rows were not claimed with a fresh token and finite lease.';
  end if;

  if exists (
    select 1 from public.delivery_ledger
    where id in (
      '91000000-0000-0000-0000-000000000101',
      '91000000-0000-0000-0000-000000000103'
    )
      and (state <> 'claimed' or kind <> 'daily_reminder')
  ) then
    raise exception 'Weekly claim mutated an already-claimed Daily job.';
  end if;

  if not exists (
    select 1 from public.delivery_ledger
    where id='91000000-0000-0000-0000-000000000106'
      and kind='weekly_newsletter' and state='failed'
      and error_code='retry_exhausted' and claim_token is null
  ) then
    raise exception 'Weekly claim did not terminalize only its own exhausted lease.';
  end if;
end;
$weekly$;
reset role;

-- Browser roles cannot execute either claim RPC.
set role anon;
do $anon$
begin
  begin
    perform * from public.claim_daily_delivery_jobs(1);
    raise exception 'Anonymous role executed Daily claim.';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from public.claim_weekly_delivery_jobs(1);
    raise exception 'Anonymous role executed Weekly claim.';
  exception when insufficient_privilege then null;
  end;
end;
$anon$;
reset role;

set role authenticated;
do $authenticated$
begin
  begin
    perform * from public.claim_daily_delivery_jobs(1);
    raise exception 'Authenticated role executed Daily claim.';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from public.claim_weekly_delivery_jobs(1);
    raise exception 'Authenticated role executed Weekly claim.';
  exception when insufficient_privilege then null;
  end;
end;
$authenticated$;
reset role;

select jsonb_build_object(
  'daily_weekly_claim_isolation','pass',
  'kind_scoped_retry_exhaustion','pass',
  'malformed_batch_rejection','pass',
  'legacy_generic_rpc_denied','pass',
  'private_helper_denied','pass',
  'stale_token_rejected','pass',
  'browser_role_denial','pass'
) as delivery_kind_claim_behavior;
