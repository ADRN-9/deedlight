-- Fail-closed provider event idempotency and lifecycle integrity.
-- Migration 025 remains immutable; all changes are additive.
begin;

alter table public.delivery_provider_events
  add column suppression_reason text,
  add column payload_fingerprint text,
  add constraint delivery_provider_events_suppression_reason_check
  check (
    (event_type = 'email.suppressed'
      and (suppression_reason is null or suppression_reason in (
        'previous_bounce',
        'previous_complaint',
        'provider_suppressed'
      )))
    or (event_type <> 'email.suppressed' and suppression_reason is null)
  ),
  add constraint delivery_provider_events_payload_fingerprint_check
  check (payload_fingerprint is null or payload_fingerprint ~ '^[0-9a-f]{64}$');

alter table public.delivery_provider_lifecycle
  drop constraint delivery_provider_lifecycle_status_check;

alter table public.delivery_provider_lifecycle
  add constraint delivery_provider_lifecycle_status_check
  check (status in (
    'email.sent',
    'email.delivered',
    'email.delivery_delayed',
    'email.bounced',
    'email.complained',
    'email.suppressed',
    'email.failed',
    'integrity_anomaly'
  ));

alter table public.delivery_provider_lifecycle
  drop constraint delivery_provider_lifecycle_status_rank_check;

alter table public.delivery_provider_lifecycle
  add constraint delivery_provider_lifecycle_status_rank_check
  check (status_rank = case status
    when 'email.sent' then 10
    when 'email.delivery_delayed' then 20
    when 'email.failed' then 30
    when 'email.bounced' then 40
    when 'email.suppressed' then 50
    when 'email.delivered' then 60
    when 'email.complained' then 70
    when 'integrity_anomaly' then 80
    else 0
  end);

create table public.delivery_provider_integrity_anomalies (
  event_id text not null
    references public.delivery_provider_events(event_id) on delete restrict,
  related_event_id text
    references public.delivery_provider_events(event_id) on delete restrict,
  anomaly_type text not null
    check (anomaly_type in (
      'duplicate_event_id_conflict',
      'contradictory_terminal_outcome'
    )),
  detected_at timestamptz not null default clock_timestamp(),
  constraint delivery_provider_integrity_anomalies_related_event_check
    check (related_event_id is null or related_event_id <> event_id)
);

create unique index delivery_provider_integrity_anomalies_dedupe_idx
  on public.delivery_provider_integrity_anomalies (
    event_id,
    anomaly_type,
    (coalesce(related_event_id, ''))
  );

alter table public.delivery_provider_integrity_anomalies enable row level security;

revoke all privileges on table public.delivery_provider_integrity_anomalies
  from public, anon, authenticated, service_role;

comment on table public.delivery_provider_integrity_anomalies
  is 'Private append-only integrity markers; contains no recipient or raw provider diagnostics.';

comment on column public.delivery_provider_events.suppression_reason
  is 'Normalized Resend data.suppressed.reason; null for historical or non-suppression events.';

comment on column public.delivery_provider_events.payload_fingerprint
  is 'SHA-256 of the signed raw webhook body; never stores the raw payload or provider diagnostics.';

create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text,
  p_failure_class text,
  p_suppression_reason text,
  p_payload_fingerprint text
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
  v_existing public.delivery_provider_events%rowtype;
  v_conflicting_event_id text;
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
    or p_provider_created_at is null
    or (p_payload_fingerprint is not null
      and p_payload_fingerprint !~ '^[0-9a-f]{64}$') then
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

  if p_event_type = 'email.suppressed' then
    if p_suppression_reason is null or p_suppression_reason not in (
      'previous_bounce',
      'previous_complaint',
      'provider_suppressed'
    ) then
      raise exception 'Invalid normalized provider suppression reason.' using errcode = '22023';
    end if;
    v_reason := case p_suppression_reason
      when 'previous_complaint' then 'complaint'
      when 'previous_bounce' then 'permanent_bounce'
      else 'provider_suppressed'
    end;
  elsif p_suppression_reason is not null then
    raise exception 'Suppression reason is only valid for suppressed events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.complained' then
    v_reason := 'complaint';
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

  -- Preserve the shared address lock and provider-ID correlation lock.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, hashtext(p_provider_email_id));

  insert into public.delivery_provider_events (
    event_id,
    event_type,
    provider_email_id,
    recipient_email,
    bounce_type,
    provider_created_at,
    failure_class,
    suppression_reason,
    payload_fingerprint
  ) values (
    p_event_id,
    p_event_type,
    p_provider_email_id,
    v_email,
    p_bounce_type,
    p_provider_created_at,
    p_failure_class,
    p_suppression_reason,
    p_payload_fingerprint
  )
  on conflict (event_id) do nothing
  returning received_at into v_received_at;

  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    select e.* into v_existing
    from public.delivery_provider_events e
    where e.event_id = p_event_id
    for update;

    if not found then
      raise exception 'Conflicting provider event could not be inspected.' using errcode = 'XX000';
    end if;

    if v_existing.event_type = p_event_type
      and v_existing.provider_email_id = p_provider_email_id
      and v_existing.recipient_email = v_email
      and v_existing.bounce_type is not distinct from p_bounce_type
      and (v_existing.provider_created_at is null
        or v_existing.provider_created_at = p_provider_created_at)
      and v_existing.failure_class is not distinct from p_failure_class
      -- Older events and legacy RPC callers have no fingerprint or suppression reason.
      -- Compare new metadata only when both sides actually carry it; never invent a digest.
      and (
        v_existing.suppression_reason is null
        or p_suppression_reason is null
        or v_existing.suppression_reason = p_suppression_reason
      )
      and (
        -- Only genuinely historical rows without a stored digest are compatible.
        -- Fingerprinted rows require an exact, non-NULL digest on every replay.
        v_existing.payload_fingerprint is null
        or (p_payload_fingerprint is not null
          and v_existing.payload_fingerprint = p_payload_fingerprint)
      ) then
      return false;
    end if;

    insert into public.delivery_provider_integrity_anomalies (
      event_id, related_event_id, anomaly_type
    ) values (
      v_existing.event_id, null, 'duplicate_event_id_conflict'
    )
    on conflict do nothing;

    update public.delivery_provider_lifecycle
    set status = 'integrity_anomaly',
        status_rank = 80,
        failure_class = null,
        updated_at = clock_timestamp()
    where provider_email_id = v_existing.provider_email_id;

    return null;
  end if;

  if exists (
    select 1
    from public.delivery_provider_events e
    where e.provider_email_id = p_provider_email_id
      and e.recipient_email <> v_email
  ) then
    raise exception 'Provider email correlation does not match.' using errcode = '22023';
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

  -- Delayed-to-delivered and delivered-to-complaint progression are valid.
  -- Incompatible terminal pairs are retained but never projected as success.
  select e.event_id into v_conflicting_event_id
  from public.delivery_provider_events e
  where e.provider_email_id = p_provider_email_id
    and e.event_id <> p_event_id
    and (
      (p_event_type = 'email.delivered'
        and e.event_type in ('email.bounced', 'email.failed', 'email.suppressed'))
      or (p_event_type in ('email.bounced', 'email.failed', 'email.suppressed')
        and e.event_type in ('email.delivered', 'email.complained'))
      or (p_event_type = 'email.complained'
        and e.event_type in ('email.bounced', 'email.failed', 'email.suppressed'))
      or (p_event_type = 'email.bounced'
        and e.event_type in ('email.failed', 'email.suppressed'))
      or (p_event_type = 'email.failed'
        and e.event_type in ('email.bounced', 'email.suppressed'))
      or (p_event_type = 'email.suppressed'
        and e.event_type in ('email.bounced', 'email.failed'))
    )
  order by e.received_at, e.event_id
  limit 1;

  if v_conflicting_event_id is not null then
    insert into public.delivery_provider_integrity_anomalies (
      event_id, related_event_id, anomaly_type
    ) values (
      p_event_id, v_conflicting_event_id, 'contradictory_terminal_outcome'
    )
    on conflict do nothing;

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
      'integrity_anomaly',
      80,
      p_provider_created_at,
      v_received_at,
      p_event_id,
      null
    )
    on conflict (provider_email_id) do update set
      status = 'integrity_anomaly',
      status_rank = 80,
      provider_created_at = excluded.provider_created_at,
      received_at = excluded.received_at,
      event_id = excluded.event_id,
      failure_class = null,
      updated_at = clock_timestamp();

    get diagnostics v_lifecycle_rows = row_count;
    if v_lifecycle_rows <> 1 then
      raise exception 'Provider lifecycle integrity state could not be persisted.' using errcode = '23505';
    end if;

    return null;
  end if;

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
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text, text)
to service_role;

comment on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text, text)
  is 'deedlight:027:provider-lifecycle-integrity-and-suppression-reasons:v1';

-- Compatibility wrapper for callers that already supply suppression_reason.
create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text,
  p_failure_class text,
  p_suppression_reason text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $compat$
begin
  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    p_provider_created_at,
    p_bounce_type,
    p_failure_class,
    p_suppression_reason,
    null
  );
end;
$compat$;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text)
to service_role;

-- Keep the original seven-argument RPC contract for trusted legacy callers.
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
as $legacy$
declare
  v_existing_provider_created_at timestamptz;
  v_suppression_reason text;
begin
  select e.provider_created_at into v_existing_provider_created_at
  from public.delivery_provider_events e
  where e.event_id = p_event_id;

  if p_event_type = 'email.suppressed' then
    v_suppression_reason := 'provider_suppressed';
  end if;

  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    coalesce(v_existing_provider_created_at, p_provider_created_at, clock_timestamp()),
    p_bounce_type,
    p_failure_class,
    v_suppression_reason,
    null
  );
end;
$legacy$;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)
to service_role;

-- Preserve the original five-argument suppression RPC as a narrow wrapper.
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
