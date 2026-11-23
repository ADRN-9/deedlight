-- Forward-only hardening for cross-stream provider suppression event timestamps.
-- Keep migrations 032/033 immutable; this replaces only the suppression-list RPC.
begin;

create index if not exists delivery_provider_events_generic_suppression_order_idx
  on public.delivery_provider_events (recipient_email, provider_created_at)
  where event_type = 'email.suppressed'
    and (suppression_reason = 'provider_suppressed' or suppression_reason is null);

create or replace function public.record_delivery_provider_suppression_event(
  p_event_id text,
  p_event_type text,
  p_provider_suppression_id text,
  p_recipient_email text,
  p_suppression_origin text,
  p_suppression_source_id text,
  p_suppression_created_at timestamptz,
  p_provider_created_at timestamptz,
  p_payload_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $suppression_sync$
declare
  v_email text;
  v_inserted integer;
  v_existing public.delivery_provider_events%rowtype;
  v_state public.delivery_provider_suppression_state%rowtype;
  v_reason text;
  v_active boolean;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_id !~ '^[[:graph:]]+$'
    or p_event_type is null
    or p_event_type not in ('suppression.added', 'suppression.removed')
    or p_provider_suppression_id is null
    or char_length(p_provider_suppression_id) not between 1 and 255
    or p_provider_suppression_id !~ '^[[:graph:]]+$'
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320
    or p_suppression_origin is null
    or p_suppression_origin not in ('bounce', 'complaint', 'manual')
    or (p_suppression_source_id is not null
      and (char_length(p_suppression_source_id) not between 1 and 255
        or p_suppression_source_id !~ '^[[:graph:]]+$'))
    or p_suppression_created_at is null
    or p_provider_created_at is null
    or p_payload_fingerprint is null
    or p_payload_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid provider suppression event.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid provider suppression recipient.' using errcode = '22023';
  end if;

  -- Match the existing delivery and lifecycle lock order: address, then provider ID.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261127, hashtext(p_provider_suppression_id));

  if exists (
    select 1
    from public.delivery_provider_events e
    where e.provider_suppression_id = p_provider_suppression_id
      and e.recipient_email <> v_email
  ) then
    raise exception 'Provider suppression correlation does not match.'
      using errcode = '22023';
  end if;

  insert into public.delivery_provider_events (
    event_id,
    event_type,
    provider_email_id,
    recipient_email,
    bounce_type,
    provider_created_at,
    failure_class,
    suppression_reason,
    payload_fingerprint,
    provider_suppression_id,
    suppression_origin,
    suppression_source_id,
    suppression_created_at
  ) values (
    p_event_id,
    p_event_type,
    null,
    v_email,
    null,
    p_provider_created_at,
    null,
    null,
    p_payload_fingerprint,
    p_provider_suppression_id,
    p_suppression_origin,
    p_suppression_source_id,
    p_suppression_created_at
  )
  on conflict (event_id) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    select e.* into v_existing
    from public.delivery_provider_events e
    where e.event_id = p_event_id
    for update;

    if not found then
      raise exception 'Conflicting provider suppression event could not be inspected.'
        using errcode = 'XX000';
    end if;

    if v_existing.event_type = p_event_type
      and v_existing.provider_email_id is null
      and v_existing.recipient_email = v_email
      and v_existing.provider_created_at = p_provider_created_at
      and v_existing.provider_suppression_id = p_provider_suppression_id
      and v_existing.suppression_origin = p_suppression_origin
      and v_existing.suppression_source_id is not distinct from p_suppression_source_id
      and v_existing.suppression_created_at = p_suppression_created_at
      and v_existing.payload_fingerprint = p_payload_fingerprint then
      return false;
    end if;

    insert into public.delivery_provider_integrity_anomalies (
      event_id, related_event_id, anomaly_type
    ) values (
      v_existing.event_id, null, 'duplicate_event_id_conflict'
    )
    on conflict do nothing;

    if v_existing.provider_email_id is not null then
      update public.delivery_provider_lifecycle
      set status = 'integrity_anomaly',
          status_rank = 80,
          failure_class = null,
          updated_at = clock_timestamp()
      where provider_email_id = v_existing.provider_email_id;
    end if;

    return null;
  end if;

  select * into v_state
  from public.delivery_provider_suppression_state s
  where s.recipient_email = v_email
  for update;

  v_active := p_event_type = 'suppression.added';

  if not found then
    insert into public.delivery_provider_suppression_state (
      recipient_email,
      provider_suppression_id,
      origin,
      is_active,
      provider_created_at,
      event_id
    ) values (
      v_email,
      p_provider_suppression_id,
      p_suppression_origin,
      v_active,
      p_provider_created_at,
      p_event_id
    )
    returning * into v_state;
  elsif p_provider_created_at > v_state.provider_created_at then
    update public.delivery_provider_suppression_state
    set provider_suppression_id = p_provider_suppression_id,
        origin = p_suppression_origin,
        is_active = v_active,
        provider_created_at = p_provider_created_at,
        event_id = p_event_id,
        updated_at = clock_timestamp()
    where recipient_email = v_email
    returning * into v_state;
  elsif p_provider_created_at = v_state.provider_created_at
    and (
      v_state.provider_suppression_id <> p_provider_suppression_id
      or v_state.origin <> p_suppression_origin
      or v_state.is_active <> v_active
    ) then
    -- Equal-time contradictory state is ambiguous: preserve the block.
    insert into public.delivery_provider_integrity_anomalies (
      event_id, related_event_id, anomaly_type
    ) values (
      p_event_id, v_state.event_id, 'suppression_event_timestamp_conflict'
    )
    on conflict do nothing;

    update public.delivery_provider_suppression_state
    set provider_suppression_id = greatest(provider_suppression_id, p_provider_suppression_id),
        origin = case
          when origin = 'complaint' or p_suppression_origin = 'complaint' then 'complaint'
          when origin = 'bounce' or p_suppression_origin = 'bounce' then 'bounce'
          else 'manual'
        end,
        is_active = true,
        event_id = greatest(event_id, p_event_id),
        updated_at = clock_timestamp()
    where recipient_email = v_email
    returning * into v_state;
  elsif p_provider_created_at = v_state.provider_created_at
    and p_event_id > v_state.event_id then
    update public.delivery_provider_suppression_state
    set event_id = p_event_id,
        updated_at = clock_timestamp()
    where recipient_email = v_email
    returning * into v_state;
  end if;

  -- Any bounce/complaint origin is an independent Deedlight hold, even
  -- when that event arrives after a newer provider removal event.
  if p_suppression_origin in ('bounce', 'complaint')
    or v_state.origin in ('bounce', 'complaint') then
    v_reason := case
      when p_suppression_origin = 'complaint' or v_state.origin = 'complaint'
        then 'complaint'
      else 'permanent_bounce'
    end;
  elsif v_state.is_active then
    v_reason := 'provider_suppressed';
  else
    v_reason := null;
  end if;

  if v_reason is not null then
    insert into public.delivery_provider_suppressions (
      recipient_email, reason, provider_event_id
    ) values (
      v_email,
      v_reason,
      case
        when v_state.origin = 'complaint' then v_state.event_id
        when p_suppression_origin = 'complaint' then p_event_id
        when v_state.origin = 'bounce' then v_state.event_id
        when p_suppression_origin = 'bounce' then p_event_id
        else v_state.event_id
      end
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
  elsif v_state.origin = 'manual'
    and exists (
      select 1
      from public.delivery_provider_events added
      where added.event_type = 'suppression.added'
        and added.provider_suppression_id = v_state.provider_suppression_id
        and added.recipient_email = v_email
        and added.suppression_origin = 'manual'
    )
    and not exists (
      select 1
      from public.delivery_provider_events lifecycle
      where lifecycle.event_type = 'email.suppressed'
        and lifecycle.recipient_email = v_email
        and (
          lifecycle.suppression_reason = 'provider_suppressed'
          or lifecycle.suppression_reason is null
        )
        and (
          lifecycle.provider_created_at is null
          or lifecycle.provider_created_at >= p_provider_created_at
        )
    ) then
    -- Only a strictly newer manual removal may clear generic lifecycle evidence.
    -- Unknown legacy timestamps are ambiguous and therefore fail closed.
    delete from public.delivery_provider_suppressions
    where recipient_email = v_email
      and reason = 'provider_suppressed';
  end if;

  return true;
end;
$suppression_sync$;


revoke all privileges
on function public.record_delivery_provider_suppression_event(
  text, text, text, text, text, text, timestamptz, timestamptz, text
)
from public, anon, authenticated, service_role;
grant execute
on function public.record_delivery_provider_suppression_event(
  text, text, text, text, text, text, timestamptz, timestamptz, text
)
to service_role;
comment on function public.record_delivery_provider_suppression_event(
  text, text, text, text, text, text, timestamptz, timestamptz, text
)
is 'deedlight:034:provider-suppression-timestamp-order:v1';

notify pgrst, 'reload schema';
commit;
