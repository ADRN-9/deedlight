-- Resend bounce/complaint intake, replay suppression and transport gate.
-- Migration 025 is additive and does not activate outbound delivery.

begin;

do $$
begin
  if to_regclass('public.delivery_ledger') is null
    or to_regclass('auth.users') is null
    or to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') is null
    or to_regprocedure('public.enqueue_due_daily_reminders(timestamp with time zone,integer)') is null
    or to_regprocedure('public.enqueue_weekly_goodness_delivery(date,timestamp with time zone,integer)') is null then
    raise exception 'Migration 025 requires the reviewed delivery baseline through 024.';
  end if;
end;
$$;

create table public.delivery_provider_events (
  event_id text primary key
    check (char_length(event_id) between 1 and 255),
  event_type text not null
    check (event_type in ('email.bounced', 'email.complained', 'email.suppressed')),
  provider_email_id text not null
    check (char_length(provider_email_id) between 1 and 255),
  recipient_email text not null
    check (
      char_length(recipient_email) between 3 and 320
      and recipient_email = lower(btrim(recipient_email))
      and recipient_email !~ '[[:space:][:cntrl:]]'
      and position('@' in recipient_email) > 1
    ),
  bounce_type text
    check (bounce_type is null or bounce_type in ('Permanent', 'Transient', 'Unknown')),
  received_at timestamptz not null default clock_timestamp(),
  constraint delivery_provider_events_bounce_event_type_check
    check (
      (event_type = 'email.bounced' and bounce_type is not null)
      or (event_type <> 'email.bounced' and bounce_type is null)
    )
);

create index delivery_provider_events_email_id_idx
  on public.delivery_provider_events (provider_email_id);

create table public.delivery_provider_suppressions (
  recipient_email text primary key
    check (
      char_length(recipient_email) between 3 and 320
      and recipient_email = lower(btrim(recipient_email))
    ),
  reason text not null
    check (reason in ('permanent_bounce', 'complaint', 'provider_suppressed')),
  provider_event_id text not null
    references public.delivery_provider_events(event_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

alter table public.delivery_provider_events enable row level security;
alter table public.delivery_provider_suppressions enable row level security;

-- Even service_role uses the narrow RPC; raw recipient addresses stay private.
revoke all privileges on table public.delivery_provider_events
  from public, anon, authenticated, service_role;
revoke all privileges on table public.delivery_provider_suppressions
  from public, anon, authenticated, service_role;

create or replace function public.record_delivery_provider_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_bounce_type text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_email text;
  v_reason text;
  v_inserted integer;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_type is null
    or p_event_type not in ('email.bounced', 'email.complained', 'email.suppressed')
    or p_provider_email_id is null
    or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320 then
    raise exception 'Invalid delivery provider event.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid delivery provider recipient.' using errcode = '22023';
  end if;

  if p_event_type = 'email.bounced' then
    if p_bounce_type is null or p_bounce_type not in ('Permanent', 'Transient', 'Unknown') then
      raise exception 'Invalid delivery bounce classification.' using errcode = '22023';
    end if;
    if p_bounce_type <> 'Transient' then
      v_reason := 'permanent_bounce';
    end if;
  elsif p_bounce_type is not null then
    raise exception 'Bounce classification is only valid for bounced events.' using errcode = '22023';
  elsif p_event_type = 'email.complained' then
    v_reason := 'complaint';
  else
    v_reason := 'provider_suppressed';
  end if;

  -- Serialize the final transport authorization against provider suppression.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));

  insert into public.delivery_provider_events (
    event_id, event_type, provider_email_id, recipient_email, bounce_type
  ) values (
    p_event_id, p_event_type, p_provider_email_id, v_email, p_bounce_type
  )
  on conflict (event_id) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    return false;
  end if;

  if v_reason is not null then
    insert into public.delivery_provider_suppressions (
      recipient_email, reason, provider_event_id
    ) values (
      v_email, v_reason, p_event_id
    )
    on conflict (recipient_email) do update set
      reason = case
        when delivery_provider_suppressions.reason = 'complaint' then 'complaint'
        when excluded.reason = 'complaint' then 'complaint'
        when delivery_provider_suppressions.reason = 'permanent_bounce' then 'permanent_bounce'
        when excluded.reason = 'permanent_bounce' then 'permanent_bounce'
        else 'provider_suppressed'
      end,
      provider_event_id = case
        when delivery_provider_suppressions.reason = 'complaint'
          then delivery_provider_suppressions.provider_event_id
        when excluded.reason = 'complaint' then excluded.provider_event_id
        when delivery_provider_suppressions.reason = 'permanent_bounce'
          then delivery_provider_suppressions.provider_event_id
        when excluded.reason = 'permanent_bounce' then excluded.provider_event_id
        else excluded.provider_event_id
      end,
      updated_at = clock_timestamp();
  end if;

  return true;
end;
$$;

revoke all privileges
on function public.record_delivery_provider_event(text, text, text, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_event(text, text, text, text, text)
to service_role;

-- Exclude suppressed addresses before the batch limit so they cannot starve
-- eligible recipients or create a new logical job every day.
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
        (timezone(drp.timezone, p_now)::date + drp.reminder_time)
        at time zone drp.timezone
      ) as scheduled_for
    from public.daily_reminder_preferences drp
    join public.profiles p
      on p.user_id = drp.user_id and p.is_suspended = false
    join auth.users u
      on u.id = drp.user_id
     and u.email_confirmed_at is not null
     and nullif(btrim(u.email), '') is not null
    join pg_catalog.pg_timezone_names tz
      on tz.name = drp.timezone
    where drp.daily_enabled = true
      and not exists (
        select 1 from public.delivery_provider_suppressions s
        where s.recipient_email = lower(btrim(u.email))
      )
  ), due as (
    select c.*
    from candidates c
    where c.scheduled_for <= p_now
      and not exists (
        select 1 from public.delivery_ledger dl
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

-- Preserve the issue-wide 5,000-row cap and serialization from migration 024.
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
  v_delivery_key text;
  v_existing integer;
  v_room integer;
  v_candidates uuid[];
  v_candidate_count integer;
  v_inserted integer;
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Weekly scheduling requires READ COMMITTED isolation.'
      using errcode = '25000';
  end if;
  if p_week_start is null or extract(isodow from p_week_start) <> 1
    or p_scheduled_for is null then
    raise exception 'A curated Monday and timestamp are required.' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'Weekly batch limit must be between 1 and 5000.' using errcode = '22023';
  end if;

  v_delivery_key := 'weekly:' || p_week_start::text;
  perform pg_catalog.pg_advisory_xact_lock(
    20261112, p_week_start - date '2000-01-01'
  );

  if not exists (
    select 1 from public.weekly_goodness_features f
    where f.week_start = p_week_start
  ) then
    raise exception 'Weekly Goodness issue has not been explicitly curated.'
      using errcode = '22023';
  end if;

  select count(*)::integer into v_existing
  from public.delivery_ledger dl
  where dl.kind = 'weekly_newsletter' and dl.delivery_key = v_delivery_key;

  if v_existing > 5000 then
    raise exception 'Weekly issue already exceeds the 5000-delivery ceiling.'
      using errcode = '54000', detail = 'deedlight:weekly-issue-capacity:v1';
  end if;
  v_room := least(5000 - v_existing, p_limit);

  select coalesce(array_agg(c.user_id order by c.user_id), array[]::uuid[])
    into v_candidates
  from (
    select np.user_id
    from public.newsletter_preferences np
    join public.profiles p
      on p.user_id = np.user_id and p.is_suspended = false
    join auth.users u
      on u.id = np.user_id
     and u.email_confirmed_at is not null
     and nullif(btrim(u.email), '') is not null
    where np.weekly_enabled = true
      and np.consented_at is not null
      and not exists (
        select 1 from public.delivery_provider_suppressions s
        where s.recipient_email = lower(btrim(u.email))
      )
      and not exists (
        select 1 from public.delivery_ledger dl
        where dl.kind = 'weekly_newsletter'
          and dl.user_id = np.user_id
          and dl.delivery_key = v_delivery_key
      )
    order by np.user_id
    limit v_room + 1
  ) c;

  v_candidate_count := cardinality(v_candidates);
  if v_candidate_count > v_room then
    raise exception 'Weekly delivery capacity exceeded; no jobs enqueued.'
      using errcode = '54000', detail = 'deedlight:weekly-issue-capacity:v1';
  end if;
  if v_candidate_count = 0 then return 0; end if;

  insert into public.delivery_ledger (
    user_id, kind, delivery_key, scheduled_for
  )
  select candidate.user_id, 'weekly_newsletter', v_delivery_key, p_scheduled_for
  from unnest(v_candidates) as candidate(user_id)
  on conflict (kind, user_id, delivery_key) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted <> v_candidate_count then
    raise exception 'Concurrent weekly ledger write detected; transaction rolled back.'
      using errcode = '40001';
  end if;
  return v_inserted;
end;
$$;

revoke all privileges
on function public.enqueue_weekly_goodness_delivery(date, timestamptz, integer)
from public, anon, authenticated;
grant execute
on function public.enqueue_weekly_goodness_delivery(date, timestamptz, integer)
to service_role;

-- This final authorization gate serializes against a bounce/complaint event.
-- If the provider event wins the per-address lock, no external send starts.
create or replace function public.begin_delivery_transport(
  p_job_id uuid,
  p_claim_token uuid,
  p_expected_email text
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
  v_email text;
begin
  if p_job_id is null or p_claim_token is null
    or p_expected_email is null
    or char_length(p_expected_email) > 320
    or nullif(btrim(p_expected_email), '') is null then
    raise exception 'Invalid delivery transport authorization arguments.'
      using errcode = '22023';
  end if;

  v_email := lower(btrim(p_expected_email));

  select * into v_job from public.delivery_ledger dl
  where dl.id = p_job_id for update;

  if not found or v_job.state <> 'claimed'
    or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null
    or v_job.claim_expires_at <= clock_timestamp() then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  -- The webhook RPC takes this same lock before inserting a suppression.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));

  if v_job.kind = 'daily_reminder' then
    perform 1 from public.daily_reminder_preferences drp
    join public.profiles p
      on p.user_id = drp.user_id and p.is_suspended = false
    join auth.users u
      on u.id = drp.user_id
     and u.email_confirmed_at is not null
     and lower(btrim(u.email)) = v_email
    join pg_catalog.pg_timezone_names tz
      on tz.name = drp.timezone
    where drp.user_id = v_job.user_id
      and drp.daily_enabled = true
      and v_job.delivery_key =
        'daily:' || timezone(drp.timezone, v_job.scheduled_for)::date::text
      and v_job.scheduled_for = (
        (timezone(drp.timezone, v_job.scheduled_for)::date
          + drp.reminder_time) at time zone drp.timezone
      )
      and not exists (
        select 1 from public.delivery_provider_suppressions s
        where s.recipient_email = v_email
      )
    for share of drp, p, u;
    v_authorized := found;
  elsif v_job.kind = 'weekly_newsletter' then
    perform 1 from public.newsletter_preferences np
    join public.profiles p
      on p.user_id = np.user_id and p.is_suspended = false
    join auth.users u
      on u.id = np.user_id
     and u.email_confirmed_at is not null
     and lower(btrim(u.email)) = v_email
    join public.weekly_goodness_features f
      on v_job.delivery_key = 'weekly:' || f.week_start::text
    where np.user_id = v_job.user_id
      and np.weekly_enabled = true
      and np.consented_at is not null
      and not exists (
        select 1 from public.delivery_provider_suppressions s
        where s.recipient_email = v_email
      )
    for share of np, p, u, f;
    v_authorized := found;
  else
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  if v_job.claim_expires_at <= clock_timestamp() then
    raise exception 'Claim expired during transport authorization.' using errcode = '42501';
  end if;

  if not v_authorized then
    update public.delivery_ledger set
      state = 'cancelled',
      cancelled_at = clock_timestamp(),
      claim_token = null,
      claim_expires_at = null,
      next_attempt_at = null,
      error_code = 'authorization_revoked',
      updated_at = clock_timestamp()
    where id = v_job.id;
    return null;
  end if;

  update public.delivery_ledger set
    transport_started_at = coalesce(transport_started_at, clock_timestamp()),
    updated_at = clock_timestamp()
  where id = v_job.id
    and state = 'claimed'
    and claim_token = p_claim_token
    and claim_expires_at > clock_timestamp()
  returning transport_started_at into v_started_at;

  if not found then
    raise exception 'Claim expired during transport authorization.' using errcode = '42501';
  end if;
  return v_started_at;
end;
$$;

revoke all privileges
on function public.begin_delivery_transport(uuid, uuid, text)
from public, anon, authenticated;
grant execute
on function public.begin_delivery_transport(uuid, uuid, text)
to service_role;

comment on function public.begin_delivery_transport(uuid, uuid, text)
  is 'deedlight:025:provider-suppression-before-transport:v1';

notify pgrst, 'reload schema';
commit;
