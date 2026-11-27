-- C525: database-enforced isolation between Daily and Weekly delivery claims.
-- The generic historical claim RPC is retained for provenance but disabled for
-- service roles. Only kind-bound entry points remain callable by the scheduler.
begin;

create or replace function public._claim_delivery_jobs_for_kind(
  p_kind text,
  p_now timestamptz,
  p_limit integer
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
  if p_kind is null or p_kind not in ('daily_reminder', 'weekly_newsletter') then
    raise exception 'A supported delivery kind is required.' using errcode = '22023';
  end if;

  if p_now is null then
    raise exception 'A claim timestamp is required.' using errcode = '22023';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'p_limit must be between 1 and 1000.' using errcode = '22023';
  end if;

  -- Retry exhaustion is scoped to the same kind as the caller's claim.
  update public.delivery_ledger dl
  set
    state = 'failed',
    failed_at = p_now,
    claim_token = null,
    claim_expires_at = null,
    next_attempt_at = null,
    error_code = 'retry_exhausted',
    updated_at = clock_timestamp()
  where dl.kind = p_kind
    and dl.state = 'claimed'
    and dl.claim_expires_at is not null
    and dl.claim_expires_at <= p_now
    and dl.attempt_count >= 5;

  return query
  with picked as (
    select dl.id
    from public.delivery_ledger dl
    where dl.kind = p_kind
      and (
        (
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
      updated_at = clock_timestamp()
    from picked
    where dl.id = picked.id
      and dl.kind = p_kind
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

create or replace function public.claim_daily_delivery_jobs(
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
language sql
security definer
set search_path = public, auth, pg_temp
as $$
  select *
  from public._claim_delivery_jobs_for_kind('daily_reminder', clock_timestamp(), p_limit);
$$;

create or replace function public.claim_weekly_delivery_jobs(
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
language sql
security definer
set search_path = public, auth, pg_temp
as $$
  select *
  from public._claim_delivery_jobs_for_kind('weekly_newsletter', clock_timestamp(), p_limit);
$$;

-- The helper and legacy all-kind RPC are not callable by any application role.
revoke all privileges
on function public._claim_delivery_jobs_for_kind(text, timestamptz, integer)
from public, anon, authenticated, service_role;

revoke all privileges
on function public.claim_delivery_jobs(timestamptz, integer)
from public, anon, authenticated, service_role;

revoke all privileges
on function public.claim_daily_delivery_jobs(integer)
from public, anon, authenticated, service_role;

revoke all privileges
on function public.claim_weekly_delivery_jobs(integer)
from public, anon, authenticated, service_role;

grant execute
on function public.claim_daily_delivery_jobs(integer)
to service_role;

grant execute
on function public.claim_weekly_delivery_jobs(integer)
to service_role;

comment on function public._claim_delivery_jobs_for_kind(text, timestamptz, integer)
  is 'Private claim implementation. Every state transition is restricted to the supplied delivery kind.';
comment on function public.claim_daily_delivery_jobs(integer)
  is 'Service-role-only claim RPC restricted to daily_reminder jobs.';
comment on function public.claim_weekly_delivery_jobs(integer)
  is 'Service-role-only claim RPC restricted to weekly_newsletter jobs.';

notify pgrst, 'reload schema';
commit;
