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

  if has_function_privilege('anon', 'public.claim_delivery_jobs(timestamp with time zone,integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.claim_delivery_jobs(timestamp with time zone,integer)', 'EXECUTE')
     or has_function_privilege('anon', 'public.authorize_delivery_job(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.authorize_delivery_job(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.begin_delivery_transport(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.begin_delivery_transport(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.enqueue_current_weekly_goodness_if_curated(timestamp with time zone,integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.enqueue_current_weekly_goodness_if_curated(timestamp with time zone,integer)', 'EXECUTE') then
    raise exception 'Browser roles must not execute delivery claim, authorization, transport, or scheduler RPCs.';
  end if;

  if not has_function_privilege('service_role', 'public.claim_delivery_jobs(timestamp with time zone,integer)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.authorize_delivery_job(uuid,uuid)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.begin_delivery_transport(uuid,uuid)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.enqueue_current_weekly_goodness_if_curated(timestamp with time zone,integer)', 'EXECUTE') then
    raise exception 'Service role delivery claim/authorization/transport/scheduler execution is incomplete.';
  end if;

  if not has_schema_privilege('service_role', 'public', 'USAGE')
     or has_schema_privilege('anon', 'public', 'CREATE')
     or has_schema_privilege('authenticated', 'public', 'CREATE') then
    raise exception 'Delivery schema permissions are not least-privilege.';
  end if;

  if not exists (
    select 1
    from pg_roles
    where rolname = 'service_role'
      and rolbypassrls
  ) then
    raise exception 'Service role must retain its explicit BYPASSRLS runtime attribute.';
  end if;

  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'delivery_ledger'
      and c.relrowsecurity
  ) then
    raise exception 'Delivery ledger row-level security must remain enabled.';
  end if;

  if (
    select count(*)
    from pg_proc p
    where p.oid in (
      to_regprocedure('public.claim_delivery_jobs(timestamp with time zone,integer)'),
      to_regprocedure('public.authorize_delivery_job(uuid,uuid)'),
      to_regprocedure('public.begin_delivery_transport(uuid,uuid)')
    )
      and p.prosecdef
      and pg_get_userbyid(p.proowner) = current_user
  ) <> 3 then
    raise exception 'Delivery claim/authorization/transport functions must remain SECURITY DEFINER and owned by the migration executor.';
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
  v_database_now timestamptz;
  v_wall_clock timestamptz;
  v_claimed_at timestamptz;
  v_claim_expires_at timestamptz;
  v_week_start date := date_trunc('week', timezone('UTC', transaction_timestamp()))::date;
  v_inserted integer;
  v_inserted_again integer;
  v_id uuid;
  v_token uuid;
  v_wrong_token uuid;
  v_started_1 timestamptz;
  v_started_2 timestamptz;
begin
  if current_user <> 'service_role' then
    raise exception 'Delivery transport test must execute as service_role, got %.', current_user;
  end if;

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

  select now(), clock_timestamp(), claimed_at, claim_expires_at
  into v_database_now, v_wall_clock, v_claimed_at, v_claim_expires_at
  from public.delivery_ledger
  where id = v_id
    and claim_token = v_token
    and state = 'claimed';

  if not found then
    raise exception 'Claim token did not match the active delivery ledger row.';
  end if;

  raise notice
    'delivery lease evidence: database_now=%, wall_clock=%, claimed_at=%, claim_expires_at=%, remaining=%',
    v_database_now, v_wall_clock, v_claimed_at, v_claim_expires_at,
    v_claim_expires_at - v_database_now;

  if v_database_now is distinct from v_now
     or v_claimed_at is distinct from v_now then
    raise exception 'Fixture and authorization database clocks differ: fixture=%, database_now=%, claimed_at=%.',
      v_now, v_database_now, v_claimed_at;
  end if;

  if v_claim_expires_at is distinct from v_now + interval '5 minutes'
     or v_claim_expires_at <= v_database_now
     or v_claim_expires_at <= v_wall_clock then
    raise exception 'New claim lease is not live for five minutes: database_now=%, wall_clock=%, expires_at=%.',
      v_database_now, v_wall_clock, v_claim_expires_at;
  end if;

  if public.authorize_delivery_job(v_id, v_token) is not true then
    raise exception 'Transport test delivery was unexpectedly unauthorized.';
  end if;

  v_started_1 := public.begin_delivery_transport(v_id, v_token);
  v_started_2 := public.begin_delivery_transport(v_id, v_token);

  if v_started_1 is null or v_started_2 is distinct from v_started_1 then
    raise exception 'Transport start timestamp is not stable across retries.';
  end if;

  -- A different token must not authorize the active claim.
  v_wrong_token := gen_random_uuid();
  if v_wrong_token = v_token then
    raise exception 'Wrong-token fixture unexpectedly equals the claim token.';
  end if;

  begin
    perform public.authorize_delivery_job(v_id, v_wrong_token);
    raise exception 'Mismatched claim token unexpectedly authorized.';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    perform public.begin_delivery_transport(v_id, v_wrong_token);
    raise exception 'Mismatched claim token unexpectedly began transport.';
  exception when sqlstate '42501' then
    null;
  end;

  -- An expired lease must fail closed for both authorization and transport.
  update public.delivery_ledger
  set claim_expires_at = v_database_now - interval '1 second'
  where id = v_id
    and claim_token = v_token;

  select claim_expires_at
  into v_claim_expires_at
  from public.delivery_ledger
  where id = v_id
    and claim_token = v_token;

  if v_claim_expires_at is null or v_claim_expires_at >= now() then
    raise exception 'Expired-claim fixture did not expire relative to database now(): now=%, expires_at=%.',
      now(), v_claim_expires_at;
  end if;

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
