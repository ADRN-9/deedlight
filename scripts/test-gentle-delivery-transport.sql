\set ON_ERROR_STOP on

\ir test-delivery-reliability-terminals.sql
\ir ../supabase/migrations/202609230021_gentle_delivery_transport.sql

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'delivery_ledger'
      and column_name = 'transport_started_at'
  ) then
    raise exception 'transport_started_at is missing.';
  end if;

  if has_function_privilege('anon', 'public.begin_delivery_transport(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.begin_delivery_transport(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.enqueue_current_weekly_goodness_if_curated(timestamp with time zone,integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.enqueue_current_weekly_goodness_if_curated(timestamp with time zone,integer)', 'EXECUTE') then
    raise exception 'Browser roles must not execute transport scheduler RPCs.';
  end if;

  if not has_function_privilege('service_role', 'public.begin_delivery_transport(uuid,uuid)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.enqueue_current_weekly_goodness_if_curated(timestamp with time zone,integer)', 'EXECUTE') then
    raise exception 'Service role transport scheduler execution is incomplete.';
  end if;
end;
$$;

-- Keep the fixture week and claim lease on one database transaction clock.
begin;

insert into public.weekly_goodness_features (week_start)
values (date_trunc('week', timezone('UTC', transaction_timestamp()))::date)
on conflict (week_start) do nothing;

set role service_role;
do $$
declare
  v_now timestamptz := transaction_timestamp();
  v_week_start date := date_trunc('week', timezone('UTC', transaction_timestamp()))::date;
  v_inserted integer;
  v_inserted_again integer;
  v_id uuid;
  v_token uuid;
  v_started_1 timestamptz;
  v_started_2 timestamptz;
begin
  v_inserted := public.enqueue_current_weekly_goodness_if_curated(
    v_now,
    5000
  );

  if v_inserted <> 1 then
    raise exception 'Expected one eligible curated weekly delivery, got %.', v_inserted;
  end if;

  v_inserted_again := public.enqueue_current_weekly_goodness_if_curated(
    v_now,
    5000
  );

  if v_inserted_again <> 0 then
    raise exception 'Repeated weekly scheduler call created duplicate logical deliveries.';
  end if;

  select job_id, claim_token
  into v_id, v_token
  from public.claim_delivery_jobs(v_now, 100)
  where delivery_key = 'weekly:' || v_week_start::text
  limit 1;

  if v_id is null or v_token is null then
    raise exception 'Transport test delivery was not claimed.';
  end if;

  if public.authorize_delivery_job(v_id, v_token) is not true then
    raise exception 'Transport test delivery was unexpectedly unauthorized.';
  end if;

  v_started_1 := public.begin_delivery_transport(v_id, v_token);
  v_started_2 := public.begin_delivery_transport(v_id, v_token);

  if v_started_1 is null or v_started_2 is distinct from v_started_1 then
    raise exception 'Transport start timestamp is not stable across retries.';
  end if;

  -- An expired lease must fail closed for both authorization and transport.
  update public.delivery_ledger
  set claim_expires_at = v_now - interval '1 second'
  where id = v_id;

  begin
    perform public.authorize_delivery_job(v_id, v_token);
    raise exception 'Expired claim unexpectedly authorized.';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    perform public.begin_delivery_transport(v_id, v_token);
    raise exception 'Expired claim unexpectedly began transport.';
  exception when sqlstate '42501' then
    null;
  end;
end;
$$;
reset role;
commit;

select jsonb_build_object(
  'gentle_delivery_transport_db', 'pass',
  'transport_started_jobs', count(*) filter (where transport_started_at is not null)
) as gentle_delivery_transport_behavior
from public.delivery_ledger;
