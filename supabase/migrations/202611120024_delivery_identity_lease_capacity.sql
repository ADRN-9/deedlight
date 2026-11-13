-- Delivery recipient identity, actual lease clock, Weekly capacity (migration 024).
begin;
do $$
begin
  if to_regprocedure('public.begin_delivery_transport(uuid,uuid)') is null
    or to_regprocedure('public.enqueue_current_weekly_goodness_if_curated(timestamp with time zone,integer)') is null
    or to_regclass('public.delivery_ledger') is null
    or to_regclass('auth.users') is null then
    raise exception 'Migration 024 requires the reviewed delivery baseline through 023.';
  end if;
-- Fail closed unless migration 023's reviewed source-level contracts ran.
-- The markers are written by 023 itself, independent of CLI migration history.
  if coalesce(obj_description(
      to_regprocedure('public.enqueue_due_daily_reminders(timestamptz,integer)'), 'pg_proc'
    ), '') <> 'deedlight:023:daily-exclusion-before-limit:v1'
    or coalesce(obj_description(
      to_regprocedure('public.enqueue_weekly_goodness_delivery(date,timestamptz,integer)'), 'pg_proc'
    ), '') <> 'deedlight:023:weekly-exclusion-before-limit:v1'
    or coalesce(obj_description(
      to_regprocedure('public.begin_delivery_transport(uuid,uuid)'), 'pg_proc'
    ), '') <> 'deedlight:023:locked-consent-before-transport:v1'
    or coalesce(pg_get_functiondef(
      to_regprocedure('public.enqueue_due_daily_reminders(timestamptz,integer)')
    ), '') not ilike '%not exists (%'
    or coalesce(pg_get_functiondef(
      to_regprocedure('public.enqueue_weekly_goodness_delivery(date,timestamptz,integer)')
    ), '') not ilike '%not exists (%'
    or coalesce(pg_get_functiondef(
      to_regprocedure('public.begin_delivery_transport(uuid,uuid)')
    ), '') not ilike '%for share of drp, p%'
  then
    raise exception 'Migration 024 requires reviewed migration 023 functions and attestation.'
      using errcode = '55000';
  end if;
  if to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') is not null then
    raise exception 'Migration 024 recipient-bound RPC is already present.';
  end if;
end;
$$;

-- Identity is compared against the currently confirmed Auth email, locked
-- with the consent/profile rows. The address is never persisted in the ledger.
create function public.begin_delivery_transport(
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
begin
  if p_job_id is null or p_claim_token is null
    or p_expected_email is null
    or char_length(p_expected_email) > 320
    or nullif(btrim(p_expected_email), '') is null then
    raise exception 'Invalid delivery transport authorization arguments.'
      using errcode = '22023';
  end if;

  select * into v_job from public.delivery_ledger dl
  where dl.id = p_job_id for update;

  if not found or v_job.state <> 'claimed'
    or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null
    or v_job.claim_expires_at <= clock_timestamp() then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  if v_job.kind = 'daily_reminder' then
    perform 1 from public.daily_reminder_preferences drp
    join public.profiles p on p.user_id = drp.user_id and p.is_suspended = false
    join auth.users u on u.id = drp.user_id
      and u.email_confirmed_at is not null and btrim(u.email) = p_expected_email
    join pg_catalog.pg_timezone_names tz on tz.name = drp.timezone
    where drp.user_id = v_job.user_id
      and drp.daily_enabled = true
      and v_job.delivery_key =
        'daily:' || timezone(drp.timezone, v_job.scheduled_for)::date::text
      and v_job.scheduled_for = (
        (timezone(drp.timezone, v_job.scheduled_for)::date
          + drp.reminder_time) at time zone drp.timezone
      )
    for share of drp, p, u;
    v_authorized := found;
  elsif v_job.kind = 'weekly_newsletter' then
    perform 1 from public.newsletter_preferences np
    join public.profiles p on p.user_id = np.user_id and p.is_suspended = false
    join auth.users u on u.id = np.user_id
      and u.email_confirmed_at is not null and btrim(u.email) = p_expected_email
    join public.weekly_goodness_features f
      on v_job.delivery_key = 'weekly:' || f.week_start::text
    where np.user_id = v_job.user_id
      and np.weekly_enabled = true and np.consented_at is not null
    for share of np, p, u, f;
    v_authorized := found;
  else
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  -- now() is transaction-start time; lock waits must use actual wall clock.
  if v_job.claim_expires_at <= clock_timestamp() then
    raise exception 'Claim expired during transport authorization.'
      using errcode = '42501';
  end if;

  if not v_authorized then
    update public.delivery_ledger set
      state = 'cancelled', cancelled_at = clock_timestamp(),
      claim_token = null, claim_expires_at = null, next_attempt_at = null,
      error_code = 'authorization_revoked', updated_at = clock_timestamp()
    where id = v_job.id;
    return null;
  end if;

  update public.delivery_ledger set
    transport_started_at = coalesce(transport_started_at, clock_timestamp()),
    updated_at = clock_timestamp()
  where id = v_job.id and state = 'claimed'
    and claim_token = p_claim_token
    and claim_expires_at > clock_timestamp()
  returning transport_started_at into v_started_at;

  if not found then
    raise exception 'Claim expired during transport authorization.'
      using errcode = '42501';
  end if;
  return v_started_at;
end;
$$;

revoke all privileges on function public.begin_delivery_transport(uuid,uuid,text)
from public, anon, authenticated;
grant execute on function public.begin_delivery_transport(uuid,uuid,text)
to service_role;
-- Old two-argument entry point must not bypass identity authorization.
drop function public.begin_delivery_transport(uuid,uuid);

-- All weekly enqueue entry points share this per-issue advisory lock.
-- A distinct logical ledger row counts forever, regardless of state. The
-- serialized eligible cohort is sampled after acquiring the lock. Late opt-ins
-- are considered by the next invocation; at capacity they cause a visible
-- SQLSTATE 54000 error rather than a false successful completion.
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
    raise exception 'A curated Monday and timestamp are required.'
      using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'Weekly batch limit must be between 1 and 5000.'
      using errcode = '22023';
  end if;
  v_delivery_key := 'weekly:' || p_week_start::text;

  -- Transaction-scoped lock serializes direct and wrapper service-role RPCs.
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
      using errcode = '54000';
  end if;
  v_room := least(5000 - v_existing, p_limit);

  -- Selection is a single SQL statement/snapshot under the issue lock.
  -- Never silently enqueue only the first p_limit members.
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
      using errcode = '54000';
  end if;
  if v_candidate_count = 0 then
    return 0;
  end if;

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
on function public.enqueue_weekly_goodness_delivery(date,timestamptz,integer)
from public, anon, authenticated;
grant execute
on function public.enqueue_weekly_goodness_delivery(date,timestamptz,integer)
to service_role;

-- The public scheduler entry point delegates to the same serialized capacity
-- policy. An uncurated issue is a harmless no-op; an over-capacity issue fails.
create or replace function public.enqueue_current_weekly_goodness_if_curated(
  p_now timestamptz default now(),
  p_limit integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_week_start date;
begin
  if p_now is null then
    raise exception 'A scheduler timestamp is required.' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'Weekly batch limit must be between 1 and 5000.'
      using errcode = '22023';
  end if;
  v_week_start := timezone('UTC', p_now)::date
    - (extract(isodow from timezone('UTC', p_now))::integer - 1);

  if not exists (
    select 1 from public.weekly_goodness_features f
    where f.week_start = v_week_start
  ) then
    return 0;
  end if;

  return public.enqueue_weekly_goodness_delivery(
    v_week_start, p_now, p_limit
  );
end;
$$;

revoke all privileges
on function public.enqueue_current_weekly_goodness_if_curated(timestamptz,integer)
from public, anon, authenticated;
grant execute
on function public.enqueue_current_weekly_goodness_if_curated(timestamptz,integer)
to service_role;

notify pgrst, 'reload schema';
commit;
