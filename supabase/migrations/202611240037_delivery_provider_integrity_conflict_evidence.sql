-- Durable recipient-scoped provider-integrity conflict evidence.
-- Migration 036 remains immutable. This migration adds an auditable case/evidence model
-- and wraps the existing provider RPCs without changing their trusted caller signatures.

begin;

do $migration_037_preflight$
declare
  v_lifecycle_comment text;
  v_suppression_comment text;
begin
  if to_regclass('public.delivery_provider_events') is null
    or to_regclass('public.delivery_provider_lifecycle') is null
    or to_regclass('public.delivery_provider_suppressions') is null
    or to_regclass('public.delivery_provider_suppression_state') is null
    or to_regclass('public.delivery_provider_integrity_anomalies') is null
    or to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)') is null
    or to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)') is null
    or to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)') is null
    or to_regprocedure('public.record_delivery_provider_event(text,text,text,text,text)') is null
    or to_regprocedure('public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)') is null
    or to_regprocedure('public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)') is null
    or to_regprocedure('public.is_admin()') is null then
    raise exception 'Migration 037 requires the reviewed provider RPC, suppression-state, integrity and admin prerequisites.';
  end if;

  select obj_description(
    to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)'),
    'pg_proc'
  ) into v_lifecycle_comment;
  select obj_description(
    to_regprocedure('public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)'),
    'pg_proc'
  ) into v_suppression_comment;

  if v_lifecycle_comment is distinct from 'deedlight:033:cross-stream-suppression-order:v1'
    or v_suppression_comment is distinct from 'deedlight:034:provider-suppression-timestamp-order:v1' then
    raise exception 'Migration 037 refuses an unrecognized provider RPC implementation.';
  end if;

  if to_regprocedure('public._record_delivery_provider_lifecycle_event_pre037_impl(text,text,text,text,timestamptz,text,text,text,text)') is not null
    or to_regprocedure('public._record_delivery_provider_suppression_event_pre037_impl(text,text,text,text,text,text,timestamptz,timestamptz,text)') is not null
    or to_regclass('public.delivery_provider_integrity_cases') is not null
    or to_regclass('public.delivery_provider_integrity_conflict_evidence') is not null
    or to_regclass('public.delivery_provider_integrity_conflict_history') is not null then
    raise exception 'Migration 037 refuses pre-existing objects with an unknown origin.';
  end if;
end;
$migration_037_preflight$;

create table public.delivery_provider_integrity_cases (
  conflict_id bigint generated always as identity primary key,
  recipient_email text not null
    check (
      char_length(recipient_email) between 3 and 320
      and recipient_email = lower(btrim(recipient_email))
      and recipient_email !~ '[[:space:][:cntrl:]]'
      and position('@' in recipient_email) > 1
    ),
  anomaly_type text not null
    check (anomaly_type in (
      'duplicate_event_id_conflict',
      'contradictory_terminal_outcome',
      'suppression_event_timestamp_conflict',
      'provider_email_recipient_conflict',
      'provider_suppression_recipient_conflict'
    )),
  state text not null default 'open'
    check (state in ('open', 'resolved')),
  first_detected_at timestamptz not null default clock_timestamp(),
  last_detected_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete restrict,
  resolution_note text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint delivery_provider_integrity_cases_resolution_shape_check
    check (
      (state = 'open' and resolved_at is null and resolved_by is null and resolution_note is null)
      or
      (state = 'resolved' and resolved_at is not null and resolved_by is not null
        and resolution_note is not null and char_length(btrim(resolution_note)) between 12 and 2000)
    ),
  constraint delivery_provider_integrity_cases_recipient_anomaly_unique
    unique (recipient_email, anomaly_type)
);

create index delivery_provider_integrity_cases_state_detected_idx
  on public.delivery_provider_integrity_cases (state, last_detected_at desc);

create table public.delivery_provider_integrity_conflict_evidence (
  evidence_id bigint generated always as identity primary key,
  conflict_id bigint not null
    references public.delivery_provider_integrity_cases(conflict_id) on delete restrict,
  recipient_email text not null
    check (
      char_length(recipient_email) between 3 and 320
      and recipient_email = lower(btrim(recipient_email))
      and recipient_email !~ '[[:space:][:cntrl:]]'
      and position('@' in recipient_email) > 1
    ),
  event_id text not null check (char_length(event_id) between 1 and 255),
  related_event_id text
    references public.delivery_provider_events(event_id) on delete restrict,
  event_type text not null
    check (event_type in (
      'email.sent',
      'email.delivered',
      'email.delivery_delayed',
      'email.bounced',
      'email.complained',
      'email.suppressed',
      'email.failed',
      'suppression.added',
      'suppression.removed'
    )),
  provider_email_id text,
  provider_suppression_id text,
  provider_created_at timestamptz,
  bounce_type text
    check (bounce_type is null or bounce_type in ('Permanent', 'Transient', 'Unknown')),
  failure_class text
    check (failure_class is null or failure_class in (
      'invalid_recipient',
      'provider_authentication',
      'domain_verification',
      'quota_exceeded',
      'content_rejected',
      'unknown'
    )),
  suppression_reason text
    check (suppression_reason is null or suppression_reason in (
      'previous_bounce',
      'previous_complaint',
      'provider_suppressed'
    )),
  suppression_origin text
    check (suppression_origin is null or suppression_origin in ('bounce', 'complaint', 'manual')),
  suppression_source_id text,
  suppression_created_at timestamptz,
  payload_fingerprint text
    check (payload_fingerprint is null or payload_fingerprint ~ '^[0-9a-f]{64}$'),
  stored_event_id text not null
    references public.delivery_provider_events(event_id) on delete restrict,
  stored_recipient_email text not null
    check (
      char_length(stored_recipient_email) between 3 and 320
      and stored_recipient_email = lower(btrim(stored_recipient_email))
      and stored_recipient_email !~ '[[:space:][:cntrl:]]'
      and position('@' in stored_recipient_email) > 1
    ),
  evidence_source text not null
    check (evidence_source in ('provider_rpc', 'legacy_anomaly_backfill')),
  observed_at timestamptz not null default clock_timestamp(),
  constraint delivery_provider_integrity_conflict_evidence_event_shape_check
    check (
      (event_type in ('suppression.added', 'suppression.removed')
        and provider_email_id is null and provider_suppression_id is not null)
      or
      (event_type not in ('suppression.added', 'suppression.removed')
        and provider_email_id is not null and provider_suppression_id is null)
    )
);

create index delivery_provider_integrity_conflict_evidence_case_order_idx
  on public.delivery_provider_integrity_conflict_evidence (conflict_id, observed_at desc, evidence_id desc);

-- A repeated signed payload is the same evidence. Fingerprint-less legacy conflicts
-- remain individually visible because their identity cannot be proven.
create unique index delivery_provider_integrity_conflict_evidence_fingerprint_idx
  on public.delivery_provider_integrity_conflict_evidence (conflict_id, payload_fingerprint)
  where payload_fingerprint is not null;

create table public.delivery_provider_integrity_conflict_history (
  history_id bigint generated always as identity primary key,
  conflict_id bigint not null
    references public.delivery_provider_integrity_cases(conflict_id) on delete restrict,
  action text not null check (action in ('resolved', 'reopened')),
  actor_id uuid references auth.users(id) on delete restrict,
  note text not null check (char_length(btrim(note)) between 12 and 2000),
  evidence_id bigint
    references public.delivery_provider_integrity_conflict_evidence(evidence_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint delivery_provider_integrity_conflict_history_actor_check
    check (
      (action = 'resolved' and actor_id is not null and evidence_id is null)
      or (action = 'reopened' and actor_id is null and evidence_id is not null)
    )
);

create index delivery_provider_integrity_conflict_history_case_order_idx
  on public.delivery_provider_integrity_conflict_history (conflict_id, created_at, history_id);

alter table public.delivery_provider_integrity_cases enable row level security;
alter table public.delivery_provider_integrity_conflict_evidence enable row level security;
alter table public.delivery_provider_integrity_conflict_history enable row level security;

revoke all privileges on table public.delivery_provider_integrity_cases
  from public, anon, authenticated, service_role;
revoke all privileges on table public.delivery_provider_integrity_conflict_evidence
  from public, anon, authenticated, service_role;
revoke all privileges on table public.delivery_provider_integrity_conflict_history
  from public, anon, authenticated, service_role;

comment on table public.delivery_provider_integrity_cases
  is 'Private recipient-scoped provider-integrity cases. Case state is mutable only through guarded internal/admin RPCs.';
comment on table public.delivery_provider_integrity_conflict_evidence
  is 'Private append-only normalized provider conflict evidence; stores fingerprints and event fields, never raw webhook bodies or diagnostics.';
comment on table public.delivery_provider_integrity_conflict_history
  is 'Private append-only resolution/reopening audit trail for provider-integrity cases.';

create or replace function public._deny_delivery_provider_integrity_audit_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $immutable$
begin
  raise exception 'Provider-integrity evidence and resolution history are append-only.'
    using errcode = '42501';
end;
$immutable$;

revoke all privileges
on function public._deny_delivery_provider_integrity_audit_mutation()
from public, anon, authenticated, service_role;

create trigger delivery_provider_integrity_conflict_evidence_immutable
before update or delete on public.delivery_provider_integrity_conflict_evidence
for each row execute function public._deny_delivery_provider_integrity_audit_mutation();

create trigger delivery_provider_integrity_conflict_history_immutable
before update or delete on public.delivery_provider_integrity_conflict_history
for each row execute function public._deny_delivery_provider_integrity_audit_mutation();

-- Preserve every historical anomaly marker that can be tied to a known recipient.
-- Earlier migrations did not retain the conflicting payload, so this backfill records
-- only the canonical event fields that actually exist and labels them as legacy evidence.
insert into public.delivery_provider_integrity_cases (
  recipient_email, anomaly_type, first_detected_at, last_detected_at
)
select
  e.recipient_email,
  a.anomaly_type,
  min(a.detected_at),
  max(a.detected_at)
from public.delivery_provider_integrity_anomalies a
join public.delivery_provider_events e on e.event_id = a.event_id
group by e.recipient_email, a.anomaly_type
on conflict (recipient_email, anomaly_type) do nothing;

insert into public.delivery_provider_integrity_conflict_evidence (
  conflict_id,
  recipient_email,
  event_id,
  related_event_id,
  event_type,
  provider_email_id,
  provider_suppression_id,
  provider_created_at,
  bounce_type,
  failure_class,
  suppression_reason,
  suppression_origin,
  suppression_source_id,
  suppression_created_at,
  payload_fingerprint,
  stored_event_id,
  stored_recipient_email,
  evidence_source,
  observed_at
)
select
  c.conflict_id,
  e.recipient_email,
  a.event_id,
  a.related_event_id,
  e.event_type,
  e.provider_email_id,
  e.provider_suppression_id,
  e.provider_created_at,
  e.bounce_type,
  e.failure_class,
  e.suppression_reason,
  e.suppression_origin,
  e.suppression_source_id,
  e.suppression_created_at,
  e.payload_fingerprint,
  stored.event_id,
  stored.recipient_email,
  'legacy_anomaly_backfill',
  a.detected_at
from public.delivery_provider_integrity_anomalies a
join public.delivery_provider_events e on e.event_id = a.event_id
join public.delivery_provider_integrity_cases c
  on c.recipient_email = e.recipient_email
 and c.anomaly_type = a.anomaly_type
join public.delivery_provider_events stored
  on stored.event_id = coalesce(a.related_event_id, a.event_id)
on conflict do nothing;

create or replace function public._record_delivery_provider_integrity_conflict(
  p_recipient_email text,
  p_event_id text,
  p_related_event_id text,
  p_anomaly_type text,
  p_event_type text,
  p_provider_email_id text,
  p_provider_suppression_id text,
  p_provider_created_at timestamptz,
  p_bounce_type text,
  p_failure_class text,
  p_suppression_reason text,
  p_suppression_origin text,
  p_suppression_source_id text,
  p_suppression_created_at timestamptz,
  p_payload_fingerprint text,
  p_stored_event_id text,
  p_stored_recipient_email text
)
returns bigint
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $record_conflict$
declare
  v_email text;
  v_now timestamptz := clock_timestamp();
  v_conflict_id bigint;
  v_evidence_id bigint;
  v_state text;
begin
  v_email := lower(btrim(p_recipient_email));
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_anomaly_type is null or p_anomaly_type not in (
      'duplicate_event_id_conflict',
      'contradictory_terminal_outcome',
      'suppression_event_timestamp_conflict',
      'provider_email_recipient_conflict',
      'provider_suppression_recipient_conflict'
    )
    or p_event_type is null or p_event_type not in (
      'email.sent', 'email.delivered', 'email.delivery_delayed', 'email.bounced',
      'email.complained', 'email.suppressed', 'email.failed',
      'suppression.added', 'suppression.removed'
    )
    or p_stored_event_id is null or char_length(p_stored_event_id) not between 1 and 255
    or p_payload_fingerprint is not null and p_payload_fingerprint !~ '^[0-9a-f]{64}$'
    or char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or p_stored_recipient_email is null
    or p_stored_recipient_email <> lower(btrim(p_stored_recipient_email)) then
    raise exception 'Invalid normalized provider-integrity conflict evidence.' using errcode = '22023';
  end if;

  insert into public.delivery_provider_integrity_cases (
    recipient_email, anomaly_type, first_detected_at, last_detected_at
  ) values (
    v_email, p_anomaly_type, v_now, v_now
  )
  on conflict (recipient_email, anomaly_type) do nothing
  returning conflict_id into v_conflict_id;

  if v_conflict_id is null then
    select c.conflict_id, c.state
      into v_conflict_id, v_state
    from public.delivery_provider_integrity_cases c
    where c.recipient_email = v_email
      and c.anomaly_type = p_anomaly_type
    for update;
  else
    select c.state into v_state
    from public.delivery_provider_integrity_cases c
    where c.conflict_id = v_conflict_id
    for update;
  end if;

  if v_conflict_id is null then
    raise exception 'Provider-integrity case could not be locked.' using errcode = 'XX000';
  end if;

  insert into public.delivery_provider_integrity_conflict_evidence (
    conflict_id,
    recipient_email,
    event_id,
    related_event_id,
    event_type,
    provider_email_id,
    provider_suppression_id,
    provider_created_at,
    bounce_type,
    failure_class,
    suppression_reason,
    suppression_origin,
    suppression_source_id,
    suppression_created_at,
    payload_fingerprint,
    stored_event_id,
    stored_recipient_email,
    evidence_source,
    observed_at
  ) values (
    v_conflict_id,
    v_email,
    p_event_id,
    p_related_event_id,
    p_event_type,
    p_provider_email_id,
    p_provider_suppression_id,
    p_provider_created_at,
    p_bounce_type,
    p_failure_class,
    p_suppression_reason,
    p_suppression_origin,
    p_suppression_source_id,
    p_suppression_created_at,
    p_payload_fingerprint,
    p_stored_event_id,
    lower(btrim(p_stored_recipient_email)),
    'provider_rpc',
    v_now
  )
  on conflict (conflict_id, payload_fingerprint)
    where payload_fingerprint is not null
    do nothing
  returning evidence_id into v_evidence_id;

  -- An identical signed payload is not new evidence and cannot reopen a case.
  if v_evidence_id is null then
    return v_conflict_id;
  end if;

  if v_state = 'resolved' then
    insert into public.delivery_provider_integrity_conflict_history (
      conflict_id, action, actor_id, note, evidence_id, created_at
    ) values (
      v_conflict_id,
      'reopened',
      null,
      'New conflicting provider evidence arrived after resolution; the prior resolution is retained in this audit history.',
      v_evidence_id,
      v_now
    );
  end if;

  update public.delivery_provider_integrity_cases
  set state = 'open',
      last_detected_at = v_now,
      resolved_at = null,
      resolved_by = null,
      resolution_note = null,
      updated_at = v_now
  where conflict_id = v_conflict_id;

  return v_conflict_id;
end;
$record_conflict$;

revoke all privileges
on function public._record_delivery_provider_integrity_conflict(text,text,text,text,text,text,text,timestamptz,text,text,text,text,text,timestamptz,text,text,text)
from public, anon, authenticated, service_role;

comment on function public._record_delivery_provider_integrity_conflict(text,text,text,text,text,text,text,timestamptz,text,text,text,text,text,timestamptz,text,text,text)
  is 'Private migration-037 helper. Call only while holding the provider RPC recipient and correlation advisory locks.';

-- Keep the prior lifecycle implementation private and call it only after acquiring
-- the same recipient-then-provider-ID transaction locks used by migration 027.
alter function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text, text
) rename to _record_delivery_provider_lifecycle_event_pre037_impl;

revoke all privileges
on function public._record_delivery_provider_lifecycle_event_pre037_impl(
  text, text, text, text, timestamptz, text, text, text, text
)
from public, anon, authenticated, service_role;

comment on function public._record_delivery_provider_lifecycle_event_pre037_impl(
  text, text, text, text, timestamptz, text, text, text, text
)
is 'Private pre-037 lifecycle RPC; preserves migration 033 cross-stream behavior and migration 029 fingerprint enforcement.';

create function public.record_delivery_provider_lifecycle_event(
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
as $lifecycle_037$
declare
  v_email text;
  v_existing public.delivery_provider_events%rowtype;
  v_related public.delivery_provider_events%rowtype;
  v_anomaly public.delivery_provider_integrity_anomalies%rowtype;
  v_existing_lifecycle public.delivery_provider_lifecycle%rowtype;
  v_had_lifecycle boolean := false;
  v_result boolean;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_type is null
    or p_event_type not in (
      'email.sent', 'email.delivered', 'email.delivery_delayed', 'email.bounced',
      'email.complained', 'email.suppressed', 'email.failed'
    )
    or p_provider_email_id is null
    or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320
    or p_provider_created_at is null
    or (p_payload_fingerprint is not null and p_payload_fingerprint !~ '^[0-9a-f]{64}$') then
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
  elsif p_bounce_type is not null then
    raise exception 'Bounce classification is only valid for bounced events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.failed' then
    if p_failure_class is null or p_failure_class not in (
      'invalid_recipient', 'provider_authentication', 'domain_verification',
      'quota_exceeded', 'content_rejected', 'unknown'
    ) then
      raise exception 'Invalid normalized provider failure classification.' using errcode = '22023';
    end if;
  elsif p_failure_class is not null then
    raise exception 'Failure classification is only valid for failed events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.suppressed' then
    if p_suppression_reason is null or p_suppression_reason not in (
      'previous_bounce', 'previous_complaint', 'provider_suppressed'
    ) then
      raise exception 'Invalid normalized provider suppression reason.' using errcode = '22023';
    end if;
  elsif p_suppression_reason is not null then
    raise exception 'Suppression reason is only valid for suppressed events.' using errcode = '22023';
  end if;

  -- Lock order is a contract shared with delivery transport and migration 034:
  -- normalized recipient first, provider email ID second. Both locks last to commit.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, hashtext(p_provider_email_id));

  select e.* into v_existing
  from public.delivery_provider_events e
  where e.event_id = p_event_id
  for update;

  select l.* into v_existing_lifecycle
  from public.delivery_provider_lifecycle l
  where l.provider_email_id = p_provider_email_id
  for update;
  v_had_lifecycle := found;

  -- Migration 027 used to raise and roll back on a provider-email-ID recipient
  -- collision. Persist the rejected attempt as private evidence instead, return
  -- NULL (the webhook route maps it to retryable HTTP 503), and keep the original
  -- event/suppression state untouched.
  select e.* into v_related
  from public.delivery_provider_events e
  where e.provider_email_id = p_provider_email_id
    and e.recipient_email <> v_email
  order by e.received_at, e.event_id
  limit 1
  for update;

  if found then
    perform public._record_delivery_provider_integrity_conflict(
      v_email, p_event_id, v_related.event_id, 'provider_email_recipient_conflict',
      p_event_type, p_provider_email_id, null, p_provider_created_at,
      p_bounce_type, p_failure_class, p_suppression_reason, null, null, null,
      p_payload_fingerprint, v_related.event_id, v_related.recipient_email
    );

    update public.delivery_provider_lifecycle
    set status = 'integrity_anomaly',
        status_rank = 80,
        failure_class = null,
        updated_at = clock_timestamp()
    where provider_email_id = p_provider_email_id;

    return null;
  end if;

  v_result := public._record_delivery_provider_lifecycle_event_pre037_impl(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    v_email,
    p_provider_created_at,
    p_bounce_type,
    p_failure_class,
    p_suppression_reason,
    p_payload_fingerprint
  );

  if v_result is null then
    select a.* into v_anomaly
    from public.delivery_provider_integrity_anomalies a
    where a.event_id = p_event_id
      and a.anomaly_type in ('duplicate_event_id_conflict', 'contradictory_terminal_outcome')
    order by a.detected_at desc
    limit 1;

    if not found then
      raise exception 'Provider lifecycle conflict was not durably classified.' using errcode = 'XX000';
    end if;

    select e.* into v_existing
    from public.delivery_provider_events e
    where e.event_id = p_event_id
    for update;

    if v_anomaly.anomaly_type = 'duplicate_event_id_conflict' then
      if not found then
        raise exception 'Conflicting duplicate provider event has no canonical event row.' using errcode = 'XX000';
      end if;
      perform public._record_delivery_provider_integrity_conflict(
        v_email, p_event_id, null, v_anomaly.anomaly_type,
        p_event_type, p_provider_email_id, null, p_provider_created_at,
        p_bounce_type, p_failure_class, p_suppression_reason, null, null, null,
        p_payload_fingerprint, v_existing.event_id, v_existing.recipient_email
      );

    else
      select e.* into v_related
      from public.delivery_provider_events e
      where e.event_id = v_anomaly.related_event_id
      for update;
      if not found then
        raise exception 'Contradictory provider event has no related canonical event.' using errcode = 'XX000';
      end if;
      perform public._record_delivery_provider_integrity_conflict(
        v_email, p_event_id, v_anomaly.related_event_id, v_anomaly.anomaly_type,
        p_event_type, p_provider_email_id, null, p_provider_created_at,
        p_bounce_type, p_failure_class, p_suppression_reason, null, null, null,
        p_payload_fingerprint, v_related.event_id, v_related.recipient_email
      );

      -- The prior implementation projected the conflicting terminal event over
      -- the canonical one. Keep only the integrity status overlay and restore all
      -- previously authoritative event/timestamp/classification fields.
      if v_had_lifecycle then
        update public.delivery_provider_lifecycle
        set status = 'integrity_anomaly',
            status_rank = 80,
            provider_created_at = v_existing_lifecycle.provider_created_at,
            received_at = v_existing_lifecycle.received_at,
            event_id = v_existing_lifecycle.event_id,
            failure_class = null,
            updated_at = clock_timestamp()
        where provider_email_id = p_provider_email_id;
      end if;
    end if;
  end if;

  return v_result;
end;
$lifecycle_037$;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text, text)
from public, anon, authenticated, service_role;
grant execute
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text, text)
to service_role;
comment on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text, text)
  is 'deedlight:037:recipient-scoped-provider-integrity-evidence:v1';

-- Preserve the seven-argument legacy RPC but acquire the same locks before
-- reading its historical timestamp. The eight- and five-argument wrappers
-- continue to delegate to this guarded canonical path.
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
as $legacy_037$
declare
  v_email text;
  v_existing_provider_created_at timestamptz;
  v_suppression_reason text;
begin
  if p_recipient_email is not null and p_provider_email_id is not null then
    v_email := lower(btrim(p_recipient_email));
    perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
    perform pg_catalog.pg_advisory_xact_lock(20261126, hashtext(p_provider_email_id));
    select e.provider_created_at into v_existing_provider_created_at
    from public.delivery_provider_events e
    where e.event_id = p_event_id
    for update;
  end if;

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
$legacy_037$;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)
from public, anon, authenticated, service_role;
grant execute
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)
to service_role;

-- Reassert the original eight- and five-argument trusted legacy boundaries.
revoke all privileges
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text)
from public, anon, authenticated, service_role;
grant execute
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text)
to service_role;

revoke all privileges
on function public.record_delivery_provider_event(text, text, text, text, text)
from public, anon, authenticated, service_role;
grant execute
on function public.record_delivery_provider_event(text, text, text, text, text)
to service_role;

-- Keep the previous suppression-list implementation private. The wrapper below
-- captures duplicate IDs, equal-timestamp conflicts and cross-recipient ID reuse.
alter function public.record_delivery_provider_suppression_event(
  text, text, text, text, text, text, timestamptz, timestamptz, text
) rename to _record_delivery_provider_suppression_event_pre037_impl;

revoke all privileges
on function public._record_delivery_provider_suppression_event_pre037_impl(
  text, text, text, text, text, text, timestamptz, timestamptz, text
)
from public, anon, authenticated, service_role;

comment on function public._record_delivery_provider_suppression_event_pre037_impl(
  text, text, text, text, text, text, timestamptz, timestamptz, text
)
is 'Private pre-037 suppression-list RPC; preserves migration 034 event ordering and complaint/bounce holds.';

create function public.record_delivery_provider_suppression_event(
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
as $suppression_037$
declare
  v_email text;
  v_related public.delivery_provider_events%rowtype;
  v_existing public.delivery_provider_events%rowtype;
  v_anomaly public.delivery_provider_integrity_anomalies%rowtype;
  v_result boolean;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_id !~ '^[[:graph:]]+$'
    or p_event_type is null or p_event_type not in ('suppression.added', 'suppression.removed')
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

  -- Match migration 034: normalized recipient first, suppression ID second.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261127, hashtext(p_provider_suppression_id));

  select e.* into v_existing
  from public.delivery_provider_events e
  where e.event_id = p_event_id
  for update;

  select e.* into v_related
  from public.delivery_provider_events e
  where e.provider_suppression_id = p_provider_suppression_id
    and e.recipient_email <> v_email
  order by e.received_at, e.event_id
  limit 1
  for update;

  if found then
    perform public._record_delivery_provider_integrity_conflict(
      v_email, p_event_id, v_related.event_id, 'provider_suppression_recipient_conflict',
      p_event_type, null, p_provider_suppression_id, p_provider_created_at,
      null, null, null, p_suppression_origin, p_suppression_source_id,
      p_suppression_created_at, p_payload_fingerprint,
      v_related.event_id, v_related.recipient_email
    );
    return null;
  end if;

  v_result := public._record_delivery_provider_suppression_event_pre037_impl(
    p_event_id,
    p_event_type,
    p_provider_suppression_id,
    v_email,
    p_suppression_origin,
    p_suppression_source_id,
    p_suppression_created_at,
    p_provider_created_at,
    p_payload_fingerprint
  );

  if v_result is null or v_result is true then
    select a.* into v_anomaly
    from public.delivery_provider_integrity_anomalies a
    where a.event_id = p_event_id
      and a.anomaly_type in ('duplicate_event_id_conflict', 'suppression_event_timestamp_conflict')
    order by a.detected_at desc
    limit 1;

    if found then
      select e.* into v_existing
      from public.delivery_provider_events e
      where e.event_id = coalesce(v_anomaly.related_event_id, v_anomaly.event_id)
      for update;

      if not found then
        raise exception 'Conflicting suppression event has no canonical event row.' using errcode = 'XX000';
      end if;

      perform public._record_delivery_provider_integrity_conflict(
        v_email,
        p_event_id,
        v_anomaly.related_event_id,
        v_anomaly.anomaly_type,
        p_event_type,
        null,
        p_provider_suppression_id,
        p_provider_created_at,
        null,
        null,
        null,
        p_suppression_origin,
        p_suppression_source_id,
        p_suppression_created_at,
        p_payload_fingerprint,
        v_existing.event_id,
        v_existing.recipient_email
      );
    elsif v_result is null then
      raise exception 'Provider suppression conflict was not durably classified.' using errcode = 'XX000';
    end if;
  end if;

  return v_result;
end;
$suppression_037$;

revoke all privileges
on function public.record_delivery_provider_suppression_event(text, text, text, text, text, text, timestamptz, timestamptz, text)
from public, anon, authenticated, service_role;
grant execute
on function public.record_delivery_provider_suppression_event(text, text, text, text, text, text, timestamptz, timestamptz, text)
to service_role;
comment on function public.record_delivery_provider_suppression_event(text, text, text, text, text, text, timestamptz, timestamptz, text)
  is 'deedlight:037:recipient-scoped-provider-suppression-integrity-evidence:v1';

create function public.admin_list_delivery_provider_integrity_conflicts(
  p_state text default 'open',
  p_limit integer default 100
)
returns table (
  conflict_id bigint,
  recipient_email text,
  anomaly_type text,
  state text,
  first_detected_at timestamptz,
  last_detected_at timestamptz,
  evidence_count bigint,
  resolved_at timestamptz,
  resolved_by uuid,
  resolution_note text
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $admin_list$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_state is null or p_state not in ('open', 'resolved', 'all')
    or p_limit is null or p_limit not between 1 and 200 then
    raise exception 'Invalid provider-integrity conflict list parameters.' using errcode = '22023';
  end if;

  return query
  select
    c.conflict_id,
    c.recipient_email,
    c.anomaly_type,
    c.state,
    c.first_detected_at,
    c.last_detected_at,
    count(e.evidence_id)::bigint,
    c.resolved_at,
    c.resolved_by,
    c.resolution_note
  from public.delivery_provider_integrity_cases c
  left join public.delivery_provider_integrity_conflict_evidence e
    on e.conflict_id = c.conflict_id
  where p_state = 'all' or c.state = p_state
  group by c.conflict_id
  order by c.last_detected_at desc, c.conflict_id desc
  limit p_limit;
end;
$admin_list$;

revoke all privileges
on function public.admin_list_delivery_provider_integrity_conflicts(text, integer)
from public, anon, authenticated, service_role;
grant execute
on function public.admin_list_delivery_provider_integrity_conflicts(text, integer)
to authenticated;

create function public.admin_list_delivery_provider_integrity_evidence(
  p_conflict_id bigint,
  p_limit integer default 100
)
returns table (
  evidence_id bigint,
  observed_at timestamptz,
  recipient_email text,
  event_id text,
  related_event_id text,
  event_type text,
  provider_email_id text,
  provider_suppression_id text,
  provider_created_at timestamptz,
  bounce_type text,
  failure_class text,
  suppression_reason text,
  suppression_origin text,
  suppression_source_id text,
  suppression_created_at timestamptz,
  payload_fingerprint text,
  stored_event_id text,
  stored_recipient_email text,
  evidence_source text
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $admin_evidence$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_conflict_id is null or p_limit is null or p_limit not between 1 and 500 then
    raise exception 'Invalid provider-integrity evidence list parameters.' using errcode = '22023';
  end if;

  return query
  select
    e.evidence_id,
    e.observed_at,
    e.recipient_email,
    e.event_id,
    e.related_event_id,
    e.event_type,
    e.provider_email_id,
    e.provider_suppression_id,
    e.provider_created_at,
    e.bounce_type,
    e.failure_class,
    e.suppression_reason,
    e.suppression_origin,
    e.suppression_source_id,
    e.suppression_created_at,
    e.payload_fingerprint,
    e.stored_event_id,
    e.stored_recipient_email,
    e.evidence_source
  from public.delivery_provider_integrity_conflict_evidence e
  where e.conflict_id = p_conflict_id
  order by e.observed_at desc, e.evidence_id desc
  limit p_limit;
end;
$admin_evidence$;

revoke all privileges
on function public.admin_list_delivery_provider_integrity_evidence(bigint, integer)
from public, anon, authenticated, service_role;
grant execute
on function public.admin_list_delivery_provider_integrity_evidence(bigint, integer)
to authenticated;

create function public.admin_list_delivery_provider_integrity_history(
  p_conflict_id bigint,
  p_limit integer default 100
)
returns table (
  history_id bigint,
  action text,
  actor_id uuid,
  note text,
  evidence_id bigint,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $admin_history$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_conflict_id is null or p_limit is null or p_limit not between 1 and 500 then
    raise exception 'Invalid provider-integrity history list parameters.' using errcode = '22023';
  end if;

  return query
  select h.history_id, h.action, h.actor_id, h.note, h.evidence_id, h.created_at
  from public.delivery_provider_integrity_conflict_history h
  where h.conflict_id = p_conflict_id
  order by h.created_at, h.history_id
  limit p_limit;
end;
$admin_history$;

revoke all privileges
on function public.admin_list_delivery_provider_integrity_history(bigint, integer)
from public, anon, authenticated, service_role;
grant execute
on function public.admin_list_delivery_provider_integrity_history(bigint, integer)
to authenticated;

create function public.admin_resolve_delivery_provider_integrity_conflict(
  p_conflict_id bigint,
  p_resolution_note text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $admin_resolve$
declare
  v_case public.delivery_provider_integrity_cases%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_conflict_id is null or p_resolution_note is null
    or char_length(btrim(p_resolution_note)) not between 12 and 2000 then
    raise exception 'A conflict ID and meaningful resolution note are required.' using errcode = '22023';
  end if;

  select c.* into v_case
  from public.delivery_provider_integrity_cases c
  where c.conflict_id = p_conflict_id
  for update;

  if not found then
    raise exception 'Provider-integrity conflict case was not found.' using errcode = '22023';
  end if;
  if v_case.state = 'resolved' then
    return false;
  end if;

  insert into public.delivery_provider_integrity_conflict_history (
    conflict_id, action, actor_id, note, evidence_id, created_at
  ) values (
    v_case.conflict_id,
    'resolved',
    auth.uid(),
    btrim(p_resolution_note),
    null,
    v_now
  );

  update public.delivery_provider_integrity_cases
  set state = 'resolved',
      resolved_at = v_now,
      resolved_by = auth.uid(),
      resolution_note = btrim(p_resolution_note),
      updated_at = v_now
  where conflict_id = v_case.conflict_id;

  return true;
end;
$admin_resolve$;

revoke all privileges
on function public.admin_resolve_delivery_provider_integrity_conflict(bigint, text)
from public, anon, authenticated, service_role;
grant execute
on function public.admin_resolve_delivery_provider_integrity_conflict(bigint, text)
to authenticated;

comment on function public.admin_list_delivery_provider_integrity_conflicts(text, integer)
  is 'Admin-only private listing of recipient-scoped provider-integrity cases.';
comment on function public.admin_list_delivery_provider_integrity_evidence(bigint, integer)
  is 'Admin-only listing of normalized provider-integrity evidence; never exposes raw webhook bodies.';
comment on function public.admin_list_delivery_provider_integrity_history(bigint, integer)
  is 'Admin-only listing of immutable provider-integrity resolution/reopening history.';
comment on function public.admin_resolve_delivery_provider_integrity_conflict(bigint, text)
  is 'Admin-only resolution transition. New distinct conflict evidence automatically reopens the case and preserves this history.';

notify pgrst, 'reload schema';
commit;
