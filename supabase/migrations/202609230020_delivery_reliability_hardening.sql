-- Delivery Reliability Hardening
-- Adds bounded claim leases and retry safety without activating transport.

begin;

-- ---------------------------------------------------------------------
-- 1. Refuse an unexpected or partially applied baseline.
-- ---------------------------------------------------------------------

do $$
begin
  if to_regclass('public.delivery_ledger') is null then
    raise exception 'Delivery reliability hardening requires the Sprint 12.2 delivery ledger.';
  end if;

  if to_regprocedure('public.claim_delivery_jobs(timestamp with time zone,integer)') is null
     or to_regprocedure('public.authorize_delivery_job(uuid,uuid)') is null
     or to_regprocedure('public.mark_delivery_sent(uuid,uuid,text)') is null
     or to_regprocedure('public.mark_delivery_failed(uuid,uuid,text)') is null then
    raise exception 'Delivery reliability hardening requires the complete Sprint 12.2 RPC baseline.';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'delivery_ledger'
      and column_name in (
        'claim_expires_at',
        'attempt_count',
        'last_attempt_at',
        'next_attempt_at'
      )
  )
  or to_regprocedure(
    'public.retry_delivery_job(uuid,uuid,timestamp with time zone,text)'
  ) is not null then
    raise exception 'Delivery reliability hardening is already or partially applied.';
  end if;

  if exists (
    select 1
    from public.delivery_ledger
    where state = 'claimed'
  ) then
    raise exception 'Delivery reliability hardening refuses to migrate live claimed jobs.';
  end if;
end
$$;

-- ---------------------------------------------------------------------
-- 2. Add bounded lease/retry metadata. Original scheduled_for remains the
--    semantic delivery time; next_attempt_at is transport retry availability.
-- ---------------------------------------------------------------------

alter table public.delivery_ledger
  add column claim_expires_at timestamptz,
  add column attempt_count integer not null default 0,
  add column last_attempt_at timestamptz,
  add column next_attempt_at timestamptz;

update public.delivery_ledger
set
  claim_token = null,
  claim_expires_at = null
where state <> 'claimed';

alter table public.delivery_ledger
  add constraint delivery_ledger_attempt_count_check
  check (attempt_count between 0 and 5),
  add constraint delivery_ledger_claim_lease_check
  check (
    (
      state = 'claimed'
      and claim_token is not null
      and claimed_at is not null
      and claim_expires_at is not null
    )
    or
    (
      state <> 'claimed'
      and claim_token is null
      and claim_expires_at is null
    )
  );

create index delivery_ledger_retry_ready_idx
on public.delivery_ledger (
  state,
  next_attempt_at,
  scheduled_for,
  created_at
);

-- ---------------------------------------------------------------------
-- 3. Claim queued jobs or reclaim expired leases. Each successful claim is
--    one attempt. Expired fifth attempts become terminal retry_exhausted.
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

  update public.delivery_ledger dl
  set
    state = 'failed',
    failed_at = p_now,
    claim_token = null,
    claim_expires_at = null,
    next_attempt_at = null,
    error_code = 'retry_exhausted',
    updated_at = now()
  where dl.state = 'claimed'
    and dl.claim_expires_at is not null
    and dl.claim_expires_at <= p_now
    and dl.attempt_count >= 5;

  return query
  with picked as (
    select dl.id
    from public.delivery_ledger dl
    where (
        dl.state = 'queued'
        and coalesce(dl.next_attempt_at, dl.scheduled_for) <= p_now
        and dl.attempt_count < 5
      )
      or (
        dl.state = 'claimed'
        and dl.claim_expires_at is not null
        and dl.claim_expires_at <= p_now
        and dl.attempt_count < 5
      )
    order by
      coalesce(dl.next_attempt_at, dl.scheduled_for),
      dl.created_at,
      dl.id
    for update skip locked
    limit p_limit
  ), claimed as (
    update public.delivery_ledger dl
    set
      state = 'claimed',
      claim_token = gen_random_uuid(),
      claimed_at = p_now,
      claim_expires_at = p_now + interval '5 minutes',
      attempt_count = dl.attempt_count + 1,
      last_attempt_at = p_now,
      next_attempt_at = null,
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
-- 4. A claim must still be live when current authorization is checked.
--    Revoked consent/suspension cancels the job and invalidates the token.
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
     or v_job.claim_token is distinct from p_claim_token
     or v_job.claim_expires_at is null
     or v_job.claim_expires_at <= now() then
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
      claim_token = null,
      claim_expires_at = null,
      next_attempt_at = null,
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
-- 5. Temporary provider failures requeue the same logical job without
--    changing scheduled_for. A fifth failed attempt becomes terminal.
-- ---------------------------------------------------------------------

create or replace function public.retry_delivery_job(
  p_job_id uuid,
  p_claim_token uuid,
  p_retry_at timestamptz,
  p_error_code text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_job public.delivery_ledger%rowtype;
  v_error_code text := btrim(coalesce(p_error_code, ''));
begin
  if p_job_id is null or p_claim_token is null or p_retry_at is null then
    raise exception 'A job ID, claim token, and retry time are required.' using errcode = '22023';
  end if;

  if char_length(v_error_code) < 1
     or char_length(v_error_code) > 100 then
    raise exception 'A bounded error code is required.' using errcode = '22023';
  end if;

  if p_retry_at <= now()
     or p_retry_at > now() + interval '24 hours' then
    raise exception 'Retry time must be within the next 24 hours.' using errcode = '22023';
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

  if v_job.attempt_count >= 5 then
    update public.delivery_ledger
    set
      state = 'failed',
      failed_at = now(),
      claim_token = null,
      claim_expires_at = null,
      next_attempt_at = null,
      error_code = 'retry_exhausted',
      updated_at = now()
    where id = v_job.id;

    return false;
  end if;

  update public.delivery_ledger
  set
    state = 'queued',
    claim_token = null,
    claim_expires_at = null,
    next_attempt_at = p_retry_at,
    error_code = v_error_code,
    updated_at = now()
  where id = v_job.id;

  return true;
end;
$$;

revoke all privileges
on function public.retry_delivery_job(uuid, uuid, timestamptz, text)
from public, anon, authenticated;

grant execute
on function public.retry_delivery_job(uuid, uuid, timestamptz, text)
to service_role;

-- ---------------------------------------------------------------------
-- 6. Terminal outcomes require a live claim and invalidate its token.
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
    claim_token = null,
    claim_expires_at = null,
    next_attempt_at = null,
    provider_result_id = nullif(btrim(p_provider_result_id), ''),
    error_code = null,
    updated_at = now()
  where id = p_job_id
    and state = 'claimed'
    and claim_token = p_claim_token
    and claim_expires_at is not null
    and claim_expires_at > now();

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
    claim_token = null,
    claim_expires_at = null,
    next_attempt_at = null,
    error_code = v_error_code,
    updated_at = now()
  where id = p_job_id
    and state = 'claimed'
    and claim_token = p_claim_token
    and claim_expires_at is not null
    and claim_expires_at > now();

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
