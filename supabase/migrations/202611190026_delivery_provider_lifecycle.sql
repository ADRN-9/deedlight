-- Provider lifecycle observability. This migration is additive; migration 025 is immutable.
begin;

do $$
begin
  if to_regclass('public.delivery_provider_events') is null
    or to_regprocedure('public.record_delivery_provider_event(text,text,text,text,text)') is null then
    raise exception 'Migration 026 requires the reviewed provider webhook baseline from migration 025.';
  end if;
end;
$$;

alter table public.delivery_provider_events
  add column provider_created_at timestamptz,
  add column failure_class text;

alter table public.delivery_provider_events
  drop constraint delivery_provider_events_event_type_check;

alter table public.delivery_provider_events
  add constraint delivery_provider_events_event_type_check
  check (event_type in (
    'email.sent',
    'email.delivered',
    'email.delivery_delayed',
    'email.bounced',
    'email.complained',
    'email.suppressed',
    'email.failed'
  )),
  add constraint delivery_provider_events_provider_created_at_check
  check (
    provider_created_at is not null
    or event_type in ('email.bounced', 'email.complained', 'email.suppressed')
  ),
  add constraint delivery_provider_events_failure_class_check
  check (
    (event_type = 'email.failed' and failure_class in (
      'invalid_recipient',
      'provider_authentication',
      'domain_verification',
      'quota_exceeded',
      'content_rejected',
      'unknown'
    ))
    or (event_type <> 'email.failed' and failure_class is null)
  );

create table public.delivery_provider_lifecycle (
  provider_email_id text primary key
    check (char_length(provider_email_id) between 1 and 255),
  status text not null
    check (status in (
      'email.sent',
      'email.delivered',
      'email.delivery_delayed',
      'email.bounced',
      'email.complained',
      'email.suppressed',
      'email.failed'
    )),
  status_rank smallint not null,
  provider_created_at timestamptz not null,
  received_at timestamptz not null,
  event_id text not null unique
    references public.delivery_provider_events(event_id) on delete restrict,
  failure_class text
    check (failure_class is null or failure_class in (
      'invalid_recipient',
      'provider_authentication',
      'domain_verification',
      'quota_exceeded',
      'content_rejected',
      'unknown'
    )),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint delivery_provider_lifecycle_status_rank_check
    check (status_rank = case status
      when 'email.sent' then 10
      when 'email.delivery_delayed' then 20
      when 'email.failed' then 30
      when 'email.bounced' then 40
      when 'email.suppressed' then 50
      when 'email.delivered' then 60
      when 'email.complained' then 70
      else 0
    end),
  constraint delivery_provider_lifecycle_failure_status_check
    check (
      (status = 'email.failed' and failure_class is not null)
      or (status <> 'email.failed' and failure_class is null)
    )
);

create index delivery_provider_lifecycle_status_idx
  on public.delivery_provider_lifecycle (status, provider_created_at desc);

alter table public.delivery_provider_lifecycle enable row level security;

revoke all privileges on table public.delivery_provider_lifecycle
  from public, anon, authenticated, service_role;

create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text default null,
  p_failure_class text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_email text;
  v_reason text;
  v_status_rank smallint;
  v_inserted integer;
  v_received_at timestamptz;
  v_lifecycle_rows integer;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_type is null
    or p_event_type not in (
      'email.sent',
      'email.delivered',
      'email.delivery_delayed',
      'email.bounced',
      'email.complained',
      'email.suppressed',
      'email.failed'
    )
    or p_provider_email_id is null
    or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320
    or p_provider_created_at is null then
    raise exception 'Invalid delivery provider lifecycle event.' using errcode = '22023';
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
  end if;

  if p_event_type = 'email.failed' then
    if p_failure_class is null or p_failure_class not in (
      'invalid_recipient',
      'provider_authentication',
      'domain_verification',
      'quota_exceeded',
      'content_rejected',
      'unknown'
    ) then
      raise exception 'Invalid normalized provider failure classification.' using errcode = '22023';
    end if;
  elsif p_failure_class is not null then
    raise exception 'Failure classification is only valid for failed events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.complained' then
    v_reason := 'complaint';
  elsif p_event_type = 'email.suppressed' then
    v_reason := 'provider_suppressed';
  end if;

  v_status_rank := case p_event_type
    when 'email.sent' then 10
    when 'email.delivery_delayed' then 20
    when 'email.failed' then 30
    when 'email.bounced' then 40
    when 'email.suppressed' then 50
    when 'email.delivered' then 60
    when 'email.complained' then 70
    else 0
  end;

  -- Keep the existing suppression/transport serialization point and also
  -- serialize provider-ID-to-recipient correlation without exposing it.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, hashtext(p_provider_email_id));

  if exists (
    select 1
    from public.delivery_provider_events e
    where e.provider_email_id = p_provider_email_id
      and e.recipient_email <> v_email
  ) then
    raise exception 'Provider email correlation does not match.' using errcode = '22023';
  end if;

  insert into public.delivery_provider_events (
    event_id,
    event_type,
    provider_email_id,
    recipient_email,
    bounce_type,
    provider_created_at,
    failure_class
  ) values (
    p_event_id,
    p_event_type,
    p_provider_email_id,
    v_email,
    p_bounce_type,
    p_provider_created_at,
    p_failure_class
  )
  on conflict (event_id) do nothing
  returning received_at into v_received_at;

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

  -- Evidence rank is monotonic: late sent/delayed/failed events cannot replace
  -- delivered or complaint evidence. Equal-rank events use provider time,
  -- then event ID, as a deterministic tie-break independent of arrival order.
  insert into public.delivery_provider_lifecycle (
    provider_email_id,
    status,
    status_rank,
    provider_created_at,
    received_at,
    event_id,
    failure_class
  ) values (
    p_provider_email_id,
    p_event_type,
    v_status_rank,
    p_provider_created_at,
    v_received_at,
    p_event_id,
    p_failure_class
  )
  on conflict (provider_email_id) do update set
    status = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.status
      else delivery_provider_lifecycle.status
    end,
    status_rank = greatest(
      delivery_provider_lifecycle.status_rank,
      excluded.status_rank
    ),
    provider_created_at = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.provider_created_at
      else delivery_provider_lifecycle.provider_created_at
    end,
    received_at = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.received_at
      else delivery_provider_lifecycle.received_at
    end,
    event_id = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.event_id
      else delivery_provider_lifecycle.event_id
    end,
    failure_class = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.failure_class
      else delivery_provider_lifecycle.failure_class
    end,
    updated_at = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then clock_timestamp()
      else delivery_provider_lifecycle.updated_at
    end;

  get diagnostics v_lifecycle_rows = row_count;
  if v_lifecycle_rows <> 1 then
    raise exception 'Provider lifecycle persistence failed.' using errcode = '23505';
  end if;

  return true;
end;
$$;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)
to service_role;

comment on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)
  is 'deedlight:026:provider-lifecycle-idempotent-monotonic:v1';


-- Preserve the legacy suppression RPC contract while routing it through the
-- same provider-ID lock and lifecycle projection. Legacy callers have no
-- provider timestamp, so receipt time is the only safe timestamp available.
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
as $legacy$
begin
  if p_event_type not in ('email.bounced', 'email.complained', 'email.suppressed') then
    raise exception 'Unsupported legacy provider event type.' using errcode = '22023';
  end if;

  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    clock_timestamp(),
    p_bounce_type,
    null
  );
end;
$legacy$;

revoke all privileges
on function public.record_delivery_provider_event(text, text, text, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_event(text, text, text, text, text)
to service_role;

notify pgrst, 'reload schema';
commit;
