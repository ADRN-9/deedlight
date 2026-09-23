\set ON_ERROR_STOP on

create extension if not exists pgcrypto;

DO $$ BEGIN
  create role anon nologin;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  create role authenticated nologin;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
DO $$ BEGIN
  create role service_role nologin bypassrls;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

create schema if not exists auth;

grant usage on schema public, auth to anon, authenticated, service_role;

create table auth.users (
  id uuid primary key,
  email text,
  email_confirmed_at timestamptz
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

grant execute on function auth.uid() to public;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_suspended boolean not null default false
);

create table public.daily_reminder_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  daily_enabled boolean not null default false,
  reminder_time time without time zone not null default '08:00',
  timezone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.newsletter_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  weekly_enabled boolean not null default false,
  consented_at timestamptz,
  unsubscribed_at timestamptz,
  consent_source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.weekly_goodness_features (
  week_start date primary key
);

grant select, insert, update on public.daily_reminder_preferences to authenticated;
grant select on public.newsletter_preferences to authenticated;
grant all privileges on all tables in schema public to service_role;
grant select on auth.users to service_role;

\ir ../supabase/migrations/202609230019_sprint12_2_gentle_delivery_foundation.sql

-- Privilege boundary: browser roles cannot touch the delivery ledger or queue RPCs.
do $$
begin
  if has_table_privilege('anon', 'public.delivery_ledger', 'SELECT')
     or has_table_privilege('authenticated', 'public.delivery_ledger', 'SELECT')
     or has_table_privilege('authenticated', 'public.delivery_ledger', 'INSERT')
     or has_table_privilege('authenticated', 'public.delivery_ledger', 'UPDATE') then
    raise exception 'Browser delivery ledger privilege regression.';
  end if;

  if has_table_privilege('authenticated', 'public.daily_reminder_preferences', 'INSERT')
     or has_table_privilege('authenticated', 'public.daily_reminder_preferences', 'UPDATE') then
    raise exception 'Authenticated direct reminder mutation privilege was not revoked.';
  end if;

  if not has_function_privilege(
      'authenticated',
      'public.set_daily_reminder_preference(boolean,time without time zone,text)',
      'EXECUTE'
    ) then
    raise exception 'Authenticated reminder preference RPC execution is missing.';
  end if;

  if has_function_privilege(
      'anon',
      'public.set_daily_reminder_preference(boolean,time without time zone,text)',
      'EXECUTE'
    ) then
    raise exception 'Anon reminder preference RPC execution must remain denied.';
  end if;

  if has_function_privilege(
      'authenticated',
      'public.enqueue_due_daily_reminders(timestamp with time zone,integer)',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'public.enqueue_weekly_goodness_delivery(date,timestamp with time zone,integer)',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'public.claim_delivery_jobs(timestamp with time zone,integer)',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'public.authorize_delivery_job(uuid,uuid)',
      'EXECUTE'
    ) then
    raise exception 'Authenticated queue/claim execution must remain denied.';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'delivery_ledger'
      and column_name = 'email'
  ) then
    raise exception 'Delivery ledger must not store recipient email.';
  end if;
end;
$$;

-- Test members.
insert into auth.users (id, email, email_confirmed_at) values
  ('00000000-0000-0000-0000-000000000001', 'one@example.test', '2026-09-01T00:00:00Z'),
  ('00000000-0000-0000-0000-000000000002', 'two@example.test', '2026-09-01T00:00:00Z'),
  ('00000000-0000-0000-0000-000000000003', 'three@example.test', null),
  ('00000000-0000-0000-0000-000000000004', 'four@example.test', '2026-09-01T00:00:00Z'),
  ('00000000-0000-0000-0000-000000000005', 'five@example.test', '2026-09-01T00:00:00Z');

insert into public.profiles (user_id, is_suspended) values
  ('00000000-0000-0000-0000-000000000001', false),
  ('00000000-0000-0000-0000-000000000002', false),
  ('00000000-0000-0000-0000-000000000003', false),
  ('00000000-0000-0000-0000-000000000004', true),
  ('00000000-0000-0000-0000-000000000005', false);

-- Reminder preference validation and suspension behavior.
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  false
);
set role authenticated;
select public.set_daily_reminder_preference(true, '08:00', 'UTC');

do $$
begin
  begin
    perform public.set_daily_reminder_preference(true, '08:00', 'Mars/Olympus');
    raise exception 'Invalid timezone unexpectedly accepted.';
  exception when sqlstate '22023' then
    null;
  end;
end;
$$;
reset role;

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000004',
  false
);
set role authenticated;
do $$
begin
  begin
    perform public.set_daily_reminder_preference(true, '08:00', 'UTC');
    raise exception 'Suspended member unexpectedly enabled reminders.';
  exception when sqlstate '42501' then
    null;
  end;
end;
$$;
select public.set_daily_reminder_preference(false, '08:00', 'UTC');
reset role;

-- Insert a disabled active preference directly as setup data. It must not queue.
insert into public.daily_reminder_preferences (
  user_id, daily_enabled, reminder_time, timezone
) values (
  '00000000-0000-0000-0000-000000000005', false, '08:00', 'UTC'
);

-- Daily reminder enqueue: enabled active member only, deterministic and deduplicated.
set role service_role;
do $$
begin
  if public.enqueue_due_daily_reminders('2026-09-23T12:00:00Z', 100) <> 1 then
    raise exception 'Expected exactly one due daily reminder.';
  end if;

  if public.enqueue_due_daily_reminders('2026-09-23T12:00:00Z', 100) <> 0 then
    raise exception 'Duplicate daily enqueue was not deduplicated.';
  end if;
end;
$$;
reset role;

-- Weekly candidates: only explicit consent + confirmed email + active profile.
insert into public.newsletter_preferences (
  user_id, weekly_enabled, consented_at, consent_source
) values
  ('00000000-0000-0000-0000-000000000002', true, '2026-09-01T00:00:00Z', 'settings'),
  ('00000000-0000-0000-0000-000000000003', true, '2026-09-01T00:00:00Z', 'settings'),
  ('00000000-0000-0000-0000-000000000004', true, '2026-09-01T00:00:00Z', 'settings'),
  ('00000000-0000-0000-0000-000000000005', false, null, null);

insert into public.weekly_goodness_features (week_start)
values ('2026-09-21');

set role service_role;
do $$
begin
  if public.enqueue_weekly_goodness_delivery(
      '2026-09-21',
      '2026-09-23T12:30:00Z',
      100
    ) <> 1 then
    raise exception 'Expected exactly one eligible weekly newsletter job.';
  end if;

  if public.enqueue_weekly_goodness_delivery(
      '2026-09-21',
      '2026-09-23T12:30:00Z',
      100
    ) <> 0 then
    raise exception 'Duplicate weekly enqueue was not deduplicated.';
  end if;
end;
$$;
reset role;

-- Claim both due jobs.
set role service_role;
do $$
declare
  v_claimed integer;
begin
  select count(*) into v_claimed
  from public.claim_delivery_jobs('2026-09-23T13:00:00Z', 10);

  if v_claimed <> 2 then
    raise exception 'Expected two claimed delivery jobs, got %.', v_claimed;
  end if;
end;
$$;
reset role;

-- Revoke reminder authorization after claim. The pre-transport gate must cancel it.
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  false
);
set role authenticated;
select public.set_daily_reminder_preference(false, '08:00', 'UTC');
reset role;

set role service_role;
do $$
declare
  v_id uuid;
  v_token uuid;
begin
  select id, claim_token into v_id, v_token
  from public.delivery_ledger
  where kind = 'daily_reminder'
    and delivery_key = 'daily:2026-09-23';

  if public.authorize_delivery_job(v_id, v_token) is not false then
    raise exception 'Revoked reminder authorization was not cancelled.';
  end if;

  if not exists (
    select 1
    from public.delivery_ledger
    where id = v_id
      and state = 'cancelled'
      and error_code = 'authorization_revoked'
  ) then
    raise exception 'Cancelled reminder terminal state is incorrect.';
  end if;
end;
$$;
reset role;

-- Current weekly consent remains valid; record a provider-neutral sent terminal state.
set role service_role;
do $$
declare
  v_id uuid;
  v_token uuid;
begin
  select id, claim_token into v_id, v_token
  from public.delivery_ledger
  where kind = 'weekly_newsletter'
    and delivery_key = 'weekly:2026-09-21';

  if public.authorize_delivery_job(v_id, v_token) is not true then
    raise exception 'Current weekly authorization unexpectedly failed.';
  end if;

  perform public.mark_delivery_sent(v_id, v_token, 'behavior-test-result');

  if not exists (
    select 1
    from public.delivery_ledger
    where id = v_id
      and state = 'sent'
      and provider_result_id = 'behavior-test-result'
  ) then
    raise exception 'Sent terminal state is incorrect.';
  end if;
end;
$$;
reset role;

-- Create a second-day reminder and exercise the failed terminal state.
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  false
);
set role authenticated;
select public.set_daily_reminder_preference(true, '08:00', 'UTC');
reset role;

set role service_role;
do $$
declare
  v_id uuid;
  v_token uuid;
  v_claimed integer;
begin
  if public.enqueue_due_daily_reminders('2026-09-24T12:00:00Z', 100) <> 1 then
    raise exception 'Second-day reminder did not enqueue.';
  end if;

  select count(*) into v_claimed
  from public.claim_delivery_jobs('2026-09-24T12:00:00Z', 10);

  if v_claimed <> 1 then
    raise exception 'Second-day reminder did not claim.';
  end if;

  select id, claim_token into v_id, v_token
  from public.delivery_ledger
  where kind = 'daily_reminder'
    and delivery_key = 'daily:2026-09-24';

  if public.authorize_delivery_job(v_id, v_token) is not true then
    raise exception 'Current reminder authorization unexpectedly failed.';
  end if;

  perform public.mark_delivery_failed(v_id, v_token, 'behavior_test_failure');

  if not exists (
    select 1
    from public.delivery_ledger
    where id = v_id
      and state = 'failed'
      and error_code = 'behavior_test_failure'
  ) then
    raise exception 'Failed terminal state is incorrect.';
  end if;
end;
$$;
reset role;

select jsonb_build_object(
  'delivery_behavior', 'pass',
  'cancelled_jobs', count(*) filter (where state = 'cancelled'),
  'sent_jobs', count(*) filter (where state = 'sent'),
  'failed_jobs', count(*) filter (where state = 'failed'),
  'total_jobs', count(*)
) as sprint_12_2_delivery_behavior
from public.delivery_ledger;
