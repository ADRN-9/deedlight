-- C525: database-enforced isolation between Daily and Weekly delivery claims.
-- Each invoker RPC has a literal kind predicate in both lease cleanup and claim.
-- service_role already owns the ledger grants and bypass-RLS authority; no new
-- SECURITY DEFINER surface is introduced.

begin;

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
language plpgsql
security invoker
set search_path = pg_catalog, public, auth, pg_temp
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'p_limit must be between 1 and 1000.' using errcode = '22023';
  end if;

  -- Retry exhaustion is restricted to this function's immutable delivery kind.
  update public.delivery_ledger dl
  set
    state = 'failed',
    failed_at = clock_timestamp(),
    claim_token = null,
    claim_expires_at = null,
    next_attempt_at = null,
    error_code = 'retry_exhausted',
    updated_at = clock_timestamp()
  where dl.kind = 'daily_reminder'
    and dl.state = 'claimed'
    and dl.claim_expires_at is not null
    and dl.claim_expires_at <= clock_timestamp()
    and dl.attempt_count >= 5;

  return query
  with picked as (
    select dl.id
    from public.delivery_ledger dl
    where dl.kind = 'daily_reminder'
      and (
        (
          dl.state = 'queued'
          and coalesce(dl.next_attempt_at, dl.scheduled_for) <= clock_timestamp()
          and dl.attempt_count < 5
        )
        or (
          dl.state = 'claimed'
          and dl.claim_expires_at is not null
          and dl.claim_expires_at <= clock_timestamp()
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
      claimed_at = clock_timestamp(),
      claim_expires_at = clock_timestamp() + interval '5 minutes',
      attempt_count = dl.attempt_count + 1,
      last_attempt_at = clock_timestamp(),
      next_attempt_at = null,
      error_code = null,
      updated_at = clock_timestamp()
    from picked
    where dl.id = picked.id
      and dl.kind = 'daily_reminder'
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
language plpgsql
security invoker
set search_path = pg_catalog, public, auth, pg_temp
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'p_limit must be between 1 and 1000.' using errcode = '22023';
  end if;

  -- Retry exhaustion is restricted to this function's immutable delivery kind.
  update public.delivery_ledger dl
  set
    state = 'failed',
    failed_at = clock_timestamp(),
    claim_token = null,
    claim_expires_at = null,
    next_attempt_at = null,
    error_code = 'retry_exhausted',
    updated_at = clock_timestamp()
  where dl.kind = 'weekly_newsletter'
    and dl.state = 'claimed'
    and dl.claim_expires_at is not null
    and dl.claim_expires_at <= clock_timestamp()
    and dl.attempt_count >= 5;

  return query
  with picked as (
    select dl.id
    from public.delivery_ledger dl
    where dl.kind = 'weekly_newsletter'
      and (
        (
          dl.state = 'queued'
          and coalesce(dl.next_attempt_at, dl.scheduled_for) <= clock_timestamp()
          and dl.attempt_count < 5
        )
        or (
          dl.state = 'claimed'
          and dl.claim_expires_at is not null
          and dl.claim_expires_at <= clock_timestamp()
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
      claimed_at = clock_timestamp(),
      claim_expires_at = clock_timestamp() + interval '5 minutes',
      attempt_count = dl.attempt_count + 1,
      last_attempt_at = clock_timestamp(),
      next_attempt_at = null,
      error_code = null,
      updated_at = clock_timestamp()
    from picked
    where dl.id = picked.id
      and dl.kind = 'weekly_newsletter'
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


-- The historical all-kind RPC remains for migration/test provenance only.
-- No application role, including service_role, can execute it after this migration.
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

comment on function public.claim_daily_delivery_jobs(integer)
  is 'Service-role invoker RPC restricted to daily_reminder jobs.';
comment on function public.claim_weekly_delivery_jobs(integer)
  is 'Service-role invoker RPC restricted to weekly_newsletter jobs.';

notify pgrst, 'reload schema';
commit;
