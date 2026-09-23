-- Gentle Delivery Transport — provider-idempotency boundary and weekly scheduler helper.
-- Requires delivery reliability migration 020.

begin;

do $$
begin
  if to_regclass('public.delivery_ledger') is null
     or to_regprocedure('public.retry_delivery_job(uuid,uuid,timestamp with time zone,text)') is null
     or not exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'delivery_ledger'
         and column_name = 'claim_expires_at'
     ) then
    raise exception 'Delivery reliability migration 020 must be applied first.';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'delivery_ledger'
      and column_name = 'transport_started_at'
  )
  or to_regprocedure('public.begin_delivery_transport(uuid,uuid)') is not null
  or to_regprocedure('public.enqueue_current_weekly_goodness_if_curated(timestamp with time zone,integer)') is not null then
    raise exception 'Gentle delivery transport migration appears partially applied.';
  end if;
end;
$$;

alter table public.delivery_ledger
  add column transport_started_at timestamptz;

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
  v_started_at timestamptz;
begin
  if p_job_id is null or p_claim_token is null then
    raise exception 'A job ID and claim token are required.' using errcode = '22023';
  end if;

  update public.delivery_ledger
  set
    transport_started_at = coalesce(transport_started_at, now()),
    updated_at = now()
  where id = p_job_id
    and state = 'claimed'
    and claim_token = p_claim_token
    and claim_expires_at > now()
  returning transport_started_at into v_started_at;

  if not found then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  return v_started_at;
end;
$$;

revoke all privileges
on function public.begin_delivery_transport(uuid, uuid)
from public, anon, authenticated;

grant execute
on function public.begin_delivery_transport(uuid, uuid)
to service_role;

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

  if p_limit is null or p_limit < 1 or p_limit > 10000 then
    raise exception 'p_limit must be between 1 and 10000.' using errcode = '22023';
  end if;

  v_week_start := (
    timezone('UTC', p_now)::date
    - (extract(isodow from timezone('UTC', p_now))::integer - 1)
  );

  if not exists (
    select 1
    from public.weekly_goodness_features f
    where f.week_start = v_week_start
  ) then
    return 0;
  end if;

  return public.enqueue_weekly_goodness_delivery(v_week_start, p_now, p_limit);
end;
$$;

revoke all privileges
on function public.enqueue_current_weekly_goodness_if_curated(timestamptz, integer)
from public, anon, authenticated;

grant execute
on function public.enqueue_current_weekly_goodness_if_curated(timestamptz, integer)
to service_role;

notify pgrst, 'reload schema';

commit;
