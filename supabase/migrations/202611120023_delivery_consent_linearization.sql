-- Delivery consent linearization and starvation-free enqueue.
-- Migration 023: additive function replacements, no runtime activation.
begin;

do $$
begin
  if to_regclass('public.delivery_ledger') is null
     or to_regclass('public.daily_reminder_preferences') is null
     or to_regclass('public.newsletter_preferences') is null
     or to_regclass('public.profiles') is null
     or to_regclass('public.weekly_goodness_features') is null
     or to_regprocedure('public.begin_delivery_transport(uuid,uuid)') is null
     or to_regprocedure('public.retry_delivery_job(uuid,uuid,timestamp with time zone,text)') is null
     or not exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'delivery_ledger'
         and column_name = 'transport_started_at'
     ) then
    raise exception 'Migration 023 requires the verified delivery 019-021 baseline.';
  end if;
end;
$$;

-- Eliminate starvation: exclude existing logical jobs BEFORE the limit.
-- Uniqueness and ON CONFLICT remain the final concurrent-insertion guard.
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
    select c.*
    from candidates c
    where c.scheduled_for <= p_now
      and not exists (
        select 1
        from public.delivery_ledger dl
        where dl.kind = 'daily_reminder'
          and dl.user_id = c.user_id
          and dl.delivery_key = 'daily:' || c.local_date::text
      )
    order by c.scheduled_for, c.user_id
    limit p_limit
  ), inserted as (
    insert into public.delivery_ledger (
      user_id, kind, delivery_key, scheduled_for
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
  select count(*)::integer into v_inserted from inserted;

  return v_inserted;
end;
$$;

revoke all privileges
on function public.enqueue_due_daily_reminders(timestamptz, integer)
from public, anon, authenticated;
grant execute
on function public.enqueue_due_daily_reminders(timestamptz, integer)
to service_role;

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
    select 1 from public.weekly_goodness_features f
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
      and not exists (
        select 1 from public.delivery_ledger dl
        where dl.kind = 'weekly_newsletter'
          and dl.user_id = np.user_id
          and dl.delivery_key = 'weekly:' || p_week_start::text
      )
    order by np.user_id
    limit p_limit
  ), inserted as (
    insert into public.delivery_ledger (
      user_id, kind, delivery_key, scheduled_for
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
  select count(*)::integer into v_inserted from inserted;

  return v_inserted;
end;
$$;

revoke all privileges
on function public.enqueue_weekly_goodness_delivery(date, timestamptz, integer)
from public, anon, authenticated;
grant execute
on function public.enqueue_weekly_goodness_delivery(date, timestamptz, integer)
to service_role;

-- This RPC is the final authority immediately before external transport.
-- Under READ COMMITTED, FOR SHARE conflicts with consent/suspension UPDATE;
-- a revocation committed first is observed after waiting for its row lock.
-- Once this transaction commits, a later revocation cannot recall in-flight IO.
create or replace function public.begin_delivery_transport(
  p_job_id uuid,
  p_claim_token uuid
)
returns timestamptz
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_job public.delivery_ledger%rowtype;
  v_started_at timestamptz;
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
     or v_job.claim_token is distinct from p_claim_token
     or v_job.claim_expires_at is null
     or v_job.claim_expires_at <= now() then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  if v_job.kind = 'daily_reminder' then
    perform 1
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
    for share of drp, p;
    v_authorized := found;
  elsif v_job.kind = 'weekly_newsletter' then
    perform 1
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
    for share of np, p, u, f;
    v_authorized := found;
  else
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  if not v_authorized then
    update public.delivery_ledger
    set state = 'cancelled',
        cancelled_at = now(),
        claim_token = null,
        claim_expires_at = null,
        next_attempt_at = null,
        error_code = 'authorization_revoked',
        updated_at = now()
    where id = v_job.id;
    -- NULL is a deny decision. The worker must never call the provider.
    return null;
  end if;

  update public.delivery_ledger
  set transport_started_at = coalesce(transport_started_at, now()),
      updated_at = now()
  where id = v_job.id
  returning transport_started_at into v_started_at;

  return v_started_at;
end;
$$;

revoke all privileges
on function public.begin_delivery_transport(uuid, uuid)
from public, anon, authenticated;
grant execute
on function public.begin_delivery_transport(uuid, uuid)
to service_role;


-- An auditable, schema-local attestation of the reviewed 023 function contract.
-- Migration history alone is not evidence that these exact replacements ran.
comment on function public.enqueue_due_daily_reminders(timestamptz, integer)
  is 'deedlight:023:daily-exclusion-before-limit:v1';
comment on function public.enqueue_weekly_goodness_delivery(date, timestamptz, integer)
  is 'deedlight:023:weekly-exclusion-before-limit:v1';
comment on function public.begin_delivery_transport(uuid, uuid)
  is 'deedlight:023:locked-consent-before-transport:v1';

notify pgrst, 'reload schema';
commit;
