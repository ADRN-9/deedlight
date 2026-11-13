\set ON_ERROR_STOP on
\ir test-gentle-delivery-transport.sql
\ir ../supabase/migrations/202611120023_delivery_consent_linearization.sql

-- New users are isolated from historical fixture data; no addresses leave local PG.
insert into auth.users (id, email, email_confirmed_at)
select
  ('00000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
  'fixture-' || i::text || '@example.test',
  now() - interval '2 days'
from generate_series(101, 108) as i;

insert into public.profiles (user_id, is_suspended)
select id, false from auth.users
where id::text like '00000000-0000-0000-0000-0000000001%';

-- Baseline fixtures completed their tests; isolate new batching candidates.
update public.daily_reminder_preferences set daily_enabled = false;
update public.newsletter_preferences set weekly_enabled = false;

insert into public.daily_reminder_preferences
  (user_id, daily_enabled, reminder_time, timezone)
select id, true, '00:00'::time, 'UTC'
from auth.users where id in (
  '00000000-0000-0000-0000-000000000101',
  '00000000-0000-0000-0000-000000000102',
  '00000000-0000-0000-0000-000000000103',
  '00000000-0000-0000-0000-000000000107'
);

insert into public.newsletter_preferences
  (user_id, weekly_enabled, consented_at, consent_source)
select id, true, now() - interval '1 day', 'test'
from auth.users where id in (
  '00000000-0000-0000-0000-000000000104',
  '00000000-0000-0000-0000-000000000105',
  '00000000-0000-0000-0000-000000000106',
  '00000000-0000-0000-0000-000000000108'
);

insert into public.weekly_goodness_features (week_start)
values ('2027-01-04') on conflict (week_start) do nothing;

set role service_role;
do $$
declare
  v_daily_now timestamptz := now() + interval '1 day';
  v_i integer;
begin
  -- Previously queued logical keys must not permanently occupy LIMIT 1.
  for v_i in 1..4 loop
    if public.enqueue_due_daily_reminders(v_daily_now, 1) <> 1 then
      raise exception 'Daily enqueue stalled at batch %.', v_i;
    end if;
  end loop;
  if public.enqueue_due_daily_reminders(v_daily_now, 1) <> 0 then
    raise exception 'Duplicate daily delivery was enqueued.';
  end if;
  if (
    select count(*) from public.delivery_ledger
    where kind = 'daily_reminder'
      and delivery_key = 'daily:' || timezone('UTC', v_daily_now)::date::text
      and user_id in (
        '00000000-0000-0000-0000-000000000101',
        '00000000-0000-0000-0000-000000000102',
        '00000000-0000-0000-0000-000000000103',
        '00000000-0000-0000-0000-000000000107'
      )
  ) <> 4 then
    raise exception 'Daily enqueue missed an eligible member.';
  end if;

  for v_i in 1..4 loop
    if public.enqueue_weekly_goodness_delivery('2027-01-04', now(), 1) <> 1 then
      raise exception 'Weekly enqueue stalled at batch %.', v_i;
    end if;
  end loop;
  if public.enqueue_weekly_goodness_delivery('2027-01-04', now(), 1) <> 0 then
    raise exception 'Duplicate weekly delivery was enqueued.';
  end if;

  perform * from public.claim_delivery_jobs(v_daily_now, 100);
end;
$$;

-- Revoke after the earlier authorize() call; only begin_transport() may decide.
do $$
declare
  v_job uuid;
  v_token uuid;
  v_started timestamptz;
begin
  select id, claim_token into v_job, v_token from public.delivery_ledger
  where user_id = '00000000-0000-0000-0000-000000000101'
    and kind = 'daily_reminder'
    and state = 'claimed';
  if v_job is null or public.authorize_delivery_job(v_job, v_token) is not true then
    raise exception 'Daily preliminary authorization failed.';
  end if;
  update public.daily_reminder_preferences
  set daily_enabled = false
  where user_id = '00000000-0000-0000-0000-000000000101';

  v_started := public.begin_delivery_transport(v_job, v_token);
  if v_started is not null then
    raise exception 'Revoked daily consent reached transport.';
  end if;
  if not exists (
    select 1 from public.delivery_ledger
    where id = v_job and state = 'cancelled'
      and error_code = 'authorization_revoked'
      and transport_started_at is null
      and claim_token is null
  ) then
    raise exception 'Daily revocation did not cancel the claim.';
  end if;

  select id, claim_token into v_job, v_token from public.delivery_ledger
  where user_id = '00000000-0000-0000-0000-000000000104'
    and kind = 'weekly_newsletter' and state = 'claimed';
  if v_job is null or public.authorize_delivery_job(v_job, v_token) is not true then
    raise exception 'Weekly preliminary authorization failed.';
  end if;
  update public.newsletter_preferences
  set weekly_enabled = false, consented_at = null
  where user_id = '00000000-0000-0000-0000-000000000104';
  if public.begin_delivery_transport(v_job, v_token) is not null then
    raise exception 'Revoked weekly consent reached transport.';
  end if;

  select id, claim_token into v_job, v_token from public.delivery_ledger
  where user_id = '00000000-0000-0000-0000-000000000105'
    and kind = 'weekly_newsletter' and state = 'claimed';
  if v_job is null or public.authorize_delivery_job(v_job, v_token) is not true then
    raise exception 'Suspension preliminary authorization failed.';
  end if;
  update public.profiles set is_suspended = true
  where user_id = '00000000-0000-0000-0000-000000000105';
  if public.begin_delivery_transport(v_job, v_token) is not null then
    raise exception 'Suspended member reached transport.';
  end if;

  select id, claim_token into v_job, v_token from public.delivery_ledger
  where user_id = '00000000-0000-0000-0000-000000000103'
    and kind = 'daily_reminder' and state = 'claimed';
  if v_job is null then raise exception 'Expired/stale fixture not claimed.'; end if;
  begin
    perform public.begin_delivery_transport(v_job, gen_random_uuid());
    raise exception 'Stale token unexpectedly reached transport.';
  exception when sqlstate '42501' then null;
  end;
  update public.delivery_ledger
  set claim_expires_at = now() - interval '1 second'
  where id = v_job;
  begin
    perform public.begin_delivery_transport(v_job, v_token);
    raise exception 'Expired claim unexpectedly reached transport.';
  exception when sqlstate '42501' then null;
  end;

  select id, claim_token into v_job, v_token from public.delivery_ledger
  where user_id = '00000000-0000-0000-0000-000000000108'
    and kind = 'weekly_newsletter' and state = 'claimed';
  v_started := public.begin_delivery_transport(v_job, v_token);
  if v_started is null or public.begin_delivery_transport(v_job, v_token) is distinct from v_started then
    raise exception 'Authorized transport timestamp is not stable.';
  end if;

  if has_function_privilege('anon', 'public.begin_delivery_transport(uuid,uuid)', 'EXECUTE')
    or has_function_privilege('authenticated', 'public.begin_delivery_transport(uuid,uuid)', 'EXECUTE')
    or not has_function_privilege('service_role', 'public.begin_delivery_transport(uuid,uuid)', 'EXECUTE')
  then
    raise exception 'Transport RPC grants regressed.';
  end if;
end;
$$;
reset role;

select jsonb_build_object(
  'consent_transport','pass',
  'daily_batch_size_one','pass',
  'weekly_batch_size_one','pass',
  'revocations_and_suspension','pass',
  'expired_and_stale_claims','pass'
) as delivery_security_behavior;
