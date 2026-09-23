-- Sprint 12.2 — Gentle Delivery Foundation
-- Transport-neutral queueing and authorization gates only.
-- This migration does not configure a cron trigger or any outbound provider.

begin;

-- ---------------------------------------------------------------------
-- 1. Reminder preference writes move behind one validating RPC.
-- ---------------------------------------------------------------------

create or replace function public.set_daily_reminder_preference(
  p_enabled boolean,
  p_reminder_time time without time zone,
  p_timezone text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_enabled boolean := coalesce(p_enabled, false);
  v_timezone text := btrim(coalesce(p_timezone, ''));
begin
  if v_actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  if p_reminder_time is null then
    raise exception 'A reminder time is required.' using errcode = '22023';
  end if;

  if char_length(v_timezone) < 1
     or char_length(v_timezone) > 64
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names tz
       where tz.name = v_timezone
     ) then
    raise exception 'A valid IANA timezone is required.' using errcode = '22023';
  end if;

  if v_enabled and exists (
    select 1
    from public.profiles p
    where p.user_id = v_actor
      and p.is_suspended = true
  ) then
    raise exception 'Reminder preferences cannot be enabled while community access is suspended.'
      using errcode = '42501';
  end if;

  insert into public.daily_reminder_preferences (
    user_id,
    daily_enabled,
    reminder_time,
    timezone
  )
  values (
    v_actor,
    v_enabled,
    p_reminder_time,
    v_timezone
  )
  on conflict (user_id)
  do update set
    daily_enabled = excluded.daily_enabled,
    reminder_time = excluded.reminder_time,
    timezone = excluded.timezone,
    updated_at = now();

  return v_enabled;
end;
$$;

revoke all privileges
on function public.set_daily_reminder_preference(boolean, time without time zone, text)
from public, anon, authenticated;

grant execute
on function public.set_daily_reminder_preference(boolean, time without time zone, text)
to authenticated;

revoke insert, update
on table public.daily_reminder_preferences
from authenticated;

-- ---------------------------------------------------------------------
-- 2. Private delivery ledger.
--    No recipient address or member content is stored here.
-- ---------------------------------------------------------------------

create table if not exists public.delivery_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null
    check (kind in ('daily_reminder', 'weekly_newsletter')),
  delivery_key text not null
    check (char_length(delivery_key) between 1 and 80),
  state text not null default 'queued'
    check (state in ('queued', 'claimed', 'cancelled', 'sent', 'failed')),
  scheduled_for timestamptz not null,
  claim_token uuid,
  claimed_at timestamptz,
  sent_at timestamptz,
  failed_at timestamptz,
  cancelled_at timestamptz,
  provider_result_id text
    check (
      provider_result_id is null
      or char_length(provider_result_id) between 1 and 255
    ),
  error_code text
    check (
      error_code is null
      or char_length(error_code) between 1 and 100
    ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (kind, user_id, delivery_key)
);

create index if not exists delivery_ledger_ready_idx
on public.delivery_ledger (state, scheduled_for, created_at);

create index if not exists delivery_ledger_user_idx
on public.delivery_ledger (user_id, created_at desc);

alter table public.delivery_ledger enable row level security;

drop trigger if exists delivery_ledger_set_updated_at
on public.delivery_ledger;

create trigger delivery_ledger_set_updated_at
before update on public.delivery_ledger
for each row execute function public.set_updated_at();

revoke all privileges
on table public.delivery_ledger
from public, anon, authenticated;

grant all privileges
on table public.delivery_ledger
to service_role;

-- ---------------------------------------------------------------------
-- 3. Deterministically enqueue today's due reminder for active opt-ins.
--    Repeated runs are idempotent through the unique delivery key.
-- ---------------------------------------------------------------------

create or replace function public.enqueue_due_daily_reminders(
  p_now timestamptz default now(),
  p_limit integer default 500
)
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_inserted integer := 0;
begin
  if p_now is null then
    raise exception 'A scheduler timestamp is required.' using errcode = '22023';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'p_limit must be between 1 and 5000.' using errcode = '22023';
  end if;

  with candidates as (
    select
      drp.user_id,
      timezone(drp.timezone, p_now)::date as local_date,
      (
        (
          timezone(drp.timezone, p_now)::date
          + drp.reminder_time
        ) at time zone drp.timezone
      ) as scheduled_for
    from public.daily_reminder_preferences drp
    join public.profiles p
      on p.user_id = drp.user_id
     and p.is_suspended = false
    join pg_catalog.pg_timezone_names tz
      on tz.name = drp.timezone
    where drp.daily_enabled = true
  ), due as (
    select *
    from candidates
    where scheduled_for <= p_now
    order by scheduled_for, user_id
    limit p_limit
  ), inserted as (
    insert into public.delivery_ledger (
      user_id,
      kind,
      delivery_key,
      scheduled_for
    )
    select
      due.user_id,
      'daily_reminder',
      'daily:' || due.local_date::text,
      due.scheduled_for
    from due
    on conflict (kind, user_id, delivery_key) do nothing
    returning 1
  )
  select count(*)::integer
  into v_inserted
  from inserted;

  return v_inserted;
end;
$$;

revoke all privileges
on function public.enqueue_due_daily_reminders(timestamptz, integer)
from public, anon, authenticated;

grant execute
on function public.enqueue_due_daily_reminders(timestamptz, integer)
to service_role;

-- ---------------------------------------------------------------------
-- 4. Enqueue one explicitly identified Weekly Goodness issue.
--    Email addresses remain in Supabase Auth and are never copied here.
-- ---------------------------------------------------------------------

create or replace function public.enqueue_weekly_goodness_delivery(
  p_week_start date,
  p_scheduled_for timestamptz default now(),
  p_limit integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_inserted integer := 0;
begin
  if p_week_start is null
     or extract(isodow from p_week_start) <> 1 then
    raise exception 'p_week_start must be a Monday.' using errcode = '22023';
  end if;

  if p_scheduled_for is null then
    raise exception 'A scheduled timestamp is required.' using errcode = '22023';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 10000 then
    raise exception 'p_limit must be between 1 and 10000.' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.weekly_goodness_features f
    where f.week_start = p_week_start
  ) then
    raise exception 'Weekly Goodness issue has not been explicitly curated.'
      using errcode = '22023';
  end if;

  with eligible as (
    select np.user_id
    from public.newsletter_preferences np
    join public.profiles p
      on p.user_id = np.user_id
     and p.is_suspended = false
    join auth.users u
      on u.id = np.user_id
     and u.email_confirmed_at is not null
     and nullif(btrim(u.email), '') is not null
    where np.weekly_enabled = true
      and np.consented_at is not null
    order by np.user_id
    limit p_limit
  ), inserted as (
    insert into public.delivery_ledger (
      user_id,
      kind,
      delivery_key,
      scheduled_for
    )
    select
      eligible.user_id,
      'weekly_newsletter',
      'weekly:' || p_week_start::text,
      p_scheduled_for
    from eligible
    on conflict (kind, user_id, delivery_key) do nothing
    returning 1
  )
  select count(*)::integer
  into v_inserted
  from inserted;

  return v_inserted;
end;
$$;

revoke all privileges
on function public.enqueue_weekly_goodness_delivery(date, timestamptz, integer)
from public, anon, authenticated;

grant execute
on function public.enqueue_weekly_goodness_delivery(date, timestamptz, integer)
to service_role;

-- ---------------------------------------------------------------------
-- 5. Claim due jobs without exposing recipient addresses.
-- ---------------------------------------------------------------------

create or replace function public.claim_delivery_jobs(
  p_now timestamptz default now(),
  p_limit integer default 100
)
returns table (
  job_id uuid,
  user_id uuid,
  kind text,
  delivery_key text,
  scheduled_for timestamptz,
  claim_token uuid
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if p_now is null then
    raise exception 'A claim timestamp is required.' using errcode = '22023';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'p_limit must be between 1 and 1000.' using errcode = '22023';
  end if;

  return query
  with picked as (
    select dl.id
    from public.delivery_ledger dl
    where dl.state = 'queued'
      and dl.scheduled_for <= p_now
    order by dl.scheduled_for, dl.created_at, dl.id
    for update skip locked
    limit p_limit
  ), claimed as (
    update public.delivery_ledger dl
    set
      state = 'claimed',
      claim_token = gen_random_uuid(),
      claimed_at = p_now,
      error_code = null,
      updated_at = now()
    from picked
    where dl.id = picked.id
    returning
      dl.id,
      dl.user_id,
      dl.kind,
      dl.delivery_key,
      dl.scheduled_for,
      dl.claim_token
  )
  select
    claimed.id,
    claimed.user_id,
    claimed.kind,
    claimed.delivery_key,
    claimed.scheduled_for,
    claimed.claim_token
  from claimed;
end;
$$;

revoke all privileges
on function public.claim_delivery_jobs(timestamptz, integer)
from public, anon, authenticated;

grant execute
on function public.claim_delivery_jobs(timestamptz, integer)
to service_role;

-- ---------------------------------------------------------------------
-- 6. Re-authorize immediately before any future external transport.
--    Revoked consent or suspension cancels the claimed job.
-- ---------------------------------------------------------------------

create or replace function public.authorize_delivery_job(
  p_job_id uuid,
  p_claim_token uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_job public.delivery_ledger%rowtype;
  v_authorized boolean := false;
begin
  if p_job_id is null or p_claim_token is null then
    raise exception 'A job ID and claim token are required.' using errcode = '22023';
  end if;

  select * into v_job
  from public.delivery_ledger dl
  where dl.id = p_job_id
  for update;

  if not found
     or v_job.state <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  if v_job.kind = 'daily_reminder' then
    select exists (
      select 1
      from public.daily_reminder_preferences drp
      join public.profiles p
        on p.user_id = drp.user_id
       and p.is_suspended = false
      join pg_catalog.pg_timezone_names tz
        on tz.name = drp.timezone
      where drp.user_id = v_job.user_id
        and drp.daily_enabled = true
        and v_job.delivery_key =
          'daily:' || timezone(drp.timezone, v_job.scheduled_for)::date::text
        and v_job.scheduled_for = (
          (
            timezone(drp.timezone, v_job.scheduled_for)::date
            + drp.reminder_time
          ) at time zone drp.timezone
        )
    ) into v_authorized;
  elsif v_job.kind = 'weekly_newsletter' then
    select exists (
      select 1
      from public.newsletter_preferences np
      join public.profiles p
        on p.user_id = np.user_id
       and p.is_suspended = false
      join auth.users u
        on u.id = np.user_id
       and u.email_confirmed_at is not null
       and nullif(btrim(u.email), '') is not null
      join public.weekly_goodness_features f
        on v_job.delivery_key = 'weekly:' || f.week_start::text
      where np.user_id = v_job.user_id
        and np.weekly_enabled = true
        and np.consented_at is not null
    ) into v_authorized;
  else
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  if not v_authorized then
    update public.delivery_ledger
    set
      state = 'cancelled',
      cancelled_at = now(),
      error_code = 'authorization_revoked',
      updated_at = now()
    where id = v_job.id;

    return false;
  end if;

  return true;
end;
$$;

revoke all privileges
on function public.authorize_delivery_job(uuid, uuid)
from public, anon, authenticated;

grant execute
on function public.authorize_delivery_job(uuid, uuid)
to service_role;

-- ---------------------------------------------------------------------
-- 7. Terminal state transitions. These record provider-neutral outcomes only.
-- ---------------------------------------------------------------------

create or replace function public.mark_delivery_sent(
  p_job_id uuid,
  p_claim_token uuid,
  p_provider_result_id text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if p_provider_result_id is not null
     and char_length(p_provider_result_id) > 255 then
    raise exception 'Provider result identifier is too long.' using errcode = '22023';
  end if;

  update public.delivery_ledger
  set
    state = 'sent',
    sent_at = now(),
    provider_result_id = nullif(btrim(p_provider_result_id), ''),
    error_code = null,
    updated_at = now()
  where id = p_job_id
    and state = 'claimed'
    and claim_token = p_claim_token;

  if not found then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  return true;
end;
$$;

revoke all privileges
on function public.mark_delivery_sent(uuid, uuid, text)
from public, anon, authenticated;

grant execute
on function public.mark_delivery_sent(uuid, uuid, text)
to service_role;

create or replace function public.mark_delivery_failed(
  p_job_id uuid,
  p_claim_token uuid,
  p_error_code text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_error_code text := btrim(coalesce(p_error_code, ''));
begin
  if char_length(v_error_code) < 1
     or char_length(v_error_code) > 100 then
    raise exception 'A bounded error code is required.' using errcode = '22023';
  end if;

  update public.delivery_ledger
  set
    state = 'failed',
    failed_at = now(),
    error_code = v_error_code,
    updated_at = now()
  where id = p_job_id
    and state = 'claimed'
    and claim_token = p_claim_token;

  if not found then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  return true;
end;
$$;

revoke all privileges
on function public.mark_delivery_failed(uuid, uuid, text)
from public, anon, authenticated;

grant execute
on function public.mark_delivery_failed(uuid, uuid, text)
to service_role;

notify pgrst, 'reload schema';

commit;
