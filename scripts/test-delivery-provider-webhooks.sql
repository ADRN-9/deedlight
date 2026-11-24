\set ON_ERROR_STOP on

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
\ir test-delivery-consent-gates.sql
\ir ../supabase/migrations/202611190025_delivery_provider_webhooks.sql

-- Preserve a real pre-026 row whose provider timestamp is also historically NULL.
set role service_role;
select public.record_delivery_provider_event(
  'evt_historical_025_suppressed',
  'email.suppressed',
  'resend-historical-025-suppressed',
  'historical-025-suppressed@example.test',
  null
);
reset role;

\ir ../supabase/migrations/202611190026_delivery_provider_lifecycle.sql

-- Seed a pre-027 lifecycle event before fingerprint/reason columns exist.
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  'evt_historical_026_complaint',
  'email.complained',
  'resend-historical-026-complaint',
  'historical-026-complaint@example.test',
  '2027-03-01T09:15:00Z',
  null,
  null
);
reset role;

\ir ../supabase/migrations/202611200027_delivery_provider_integrity.sql
\ir ../supabase/migrations/202611210029_delivery_legacy_replay_guard.sql
\ir ../supabase/migrations/202611220032_resend_suppression_list_sync.sql
\ir ../supabase/migrations/202611220033_delivery_cross_stream_suppression_order.sql
\ir ../supabase/migrations/202611230034_delivery_suppression_timestamp_order.sql
-- The isolated webhook fixture has only the member profile fields needed by
-- the delivery tests. Add the real admin contract used by migration 037.
alter table public.profiles
  add column role text not null default 'member';

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $is_admin_fixture$
  select exists (
    select 1 from public.profiles
    where user_id = auth.uid()
      and role = 'admin'
      and is_suspended = false
  );
$is_admin_fixture$;
grant execute on function public.is_admin() to anon, authenticated;

-- Seed one pre-037 anomaly so the migration backfill is exercised.
set role service_role;
do $c353_legacy_backfill$
begin
  if public.record_delivery_provider_lifecycle_event(
    'evt_c353_legacy_backfill', 'email.sent', 'resend-c353-legacy-backfill',
    'legacy-integrity-backfill@example.test', '2027-03-03T08:00:00Z',
    null, null, null, repeat('a', 64)
  ) is not true then
    raise exception 'Legacy provider-integrity backfill fixture was not inserted.';
  end if;
  if public.record_delivery_provider_lifecycle_event(
    'evt_c353_legacy_backfill', 'email.failed', 'resend-c353-legacy-backfill',
    'legacy-integrity-backfill@example.test', '2027-03-03T08:01:00Z',
    null, 'unknown', null, repeat('b', 64)
  ) is not null then
    raise exception 'Legacy provider-integrity backfill conflict was not detected.';
  end if;
end;
$c353_legacy_backfill$;
reset role;

\ir ../supabase/migrations/202611240037_delivery_provider_integrity_conflict_evidence.sql
\ir test-delivery-provider-suppressions.sql

-- Replays with a new digest must remain compatible with historical NULL metadata.
set role service_role;
do $historical_replay$
begin
  if public.record_delivery_provider_lifecycle_event(
    'evt_historical_025_suppressed',
    'email.suppressed',
    'resend-historical-025-suppressed',
    'historical-025-suppressed@example.test',
    '2027-03-01T09:00:00Z',
    null,
    null,
    'previous_complaint',
    repeat('d', 64)
  ) is not false then
    raise exception 'Pre-026 historical event replay was not a compatible no-op.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_historical_026_complaint',
    'email.complained',
    'resend-historical-026-complaint',
    'historical-026-complaint@example.test',
    '2027-03-01T09:15:00Z',
    null,
    null,
    null,
    repeat('e', 64)
  ) is not false then
    raise exception 'Pre-027 historical event replay was not a compatible no-op.';
  end if;
end;
$historical_replay$;
reset role;



-- Fingerprint-less RPCs must never create new provider-event IDs.
-- The canonical 9-argument RPC also rejects NULL fingerprints for new IDs.
set role service_role;
do $legacy_new_event_rejection$
begin
  begin
    perform public.record_delivery_provider_lifecycle_event(
      'evt_legacy_new_eight', 'email.sent', 'resend-legacy-new-eight',
      'legacy-new-eight@example.test', '2027-03-01T12:00:00Z',
      null, null, null
    );
    raise exception 'Eight-argument legacy RPC unexpectedly inserted a new event.' using errcode = 'P0001';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    perform public.record_delivery_provider_lifecycle_event(
      'evt_legacy_new_seven', 'email.sent', 'resend-legacy-new-seven',
      'legacy-new-seven@example.test', '2027-03-01T12:01:00Z', null, null
    );
    raise exception 'Seven-argument legacy RPC unexpectedly inserted a new event.' using errcode = 'P0001';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    perform public.record_delivery_provider_event(
      'evt_legacy_new_five', 'email.bounced', 'resend-legacy-new-five',
      'legacy-new-five@example.test', 'Permanent'
    );
    raise exception 'Five-argument legacy RPC unexpectedly inserted a new event.' using errcode = 'P0001';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    perform public.record_delivery_provider_lifecycle_event(
      'evt_canonical_null_fingerprint', 'email.sent', 'resend-canonical-null-fingerprint',
      'canonical-null-fingerprint@example.test', '2027-03-01T12:02:00Z',
      null, null, null, null
    );
    raise exception 'Canonical RPC unexpectedly inserted a new event without a fingerprint.' using errcode = 'P0001';
  exception when sqlstate '42501' then
    null;
  end;
end;
$legacy_new_event_rejection$;
reset role;

do $legacy_new_event_assertions$
begin
  if exists (
    select 1 from public.delivery_provider_events
    where event_id in (
      'evt_legacy_new_eight',
      'evt_legacy_new_seven',
      'evt_legacy_new_five',
      'evt_canonical_null_fingerprint'
    )
  ) then
    raise exception 'A fingerprint-less RPC created a new provider event.';
  end if;
end;
$legacy_new_event_assertions$;

-- Legacy RPCs may replay genuinely historical rows whose stored fingerprint
-- is NULL, but must not bypass fingerprint checks on newer fingerprinted rows.
set role service_role;
do $legacy_fingerprint_replays$
begin
  if public.record_delivery_provider_lifecycle_event(
    'evt_historical_025_suppressed', 'email.suppressed',
    'resend-historical-025-suppressed', 'historical-025-suppressed@example.test',
    '2027-03-01T09:00:00Z', null, null, 'previous_complaint'
  ) is not false then
    raise exception 'Historical NULL fingerprint was not compatible through the eight-argument RPC.';
  end if;
  if public.record_delivery_provider_lifecycle_event(
    'evt_historical_026_complaint', 'email.complained',
    'resend-historical-026-complaint', 'historical-026-complaint@example.test',
    '2027-03-01T09:15:00Z', null, null
  ) is not false then
    raise exception 'Historical NULL fingerprint was not compatible through the seven-argument RPC.';
  end if;
  if public.record_delivery_provider_event(
    'evt_historical_025_suppressed', 'email.suppressed',
    'resend-historical-025-suppressed', 'historical-025-suppressed@example.test', null
  ) is not false then
    raise exception 'Historical NULL fingerprint was not compatible through the five-argument RPC.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_legacy_eight_fingerprint', 'email.sent', 'resend-legacy-eight-fingerprint',
    'legacy-eight@example.test', '2027-03-01T11:00:00Z', null, null, null, repeat('8', 64)
  ) is not true then raise exception 'Eight-argument legacy fingerprint fixture was not inserted.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_legacy_eight_fingerprint', 'email.sent', 'resend-legacy-eight-fingerprint',
    'legacy-eight@example.test', '2027-03-01T11:00:00Z', null, null, null
  ) is not null then
    raise exception 'Eight-argument legacy RPC bypassed a stored provider payload fingerprint.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_legacy_seven_fingerprint', 'email.sent', 'resend-legacy-seven-fingerprint',
    'legacy-seven@example.test', '2027-03-01T11:01:00Z', null, null, null, repeat('7', 64)
  ) is not true then raise exception 'Seven-argument legacy fingerprint fixture was not inserted.'; end if;
  if public.record_delivery_provider_lifecycle_event(
    'evt_legacy_seven_fingerprint', 'email.sent', 'resend-legacy-seven-fingerprint',
    'legacy-seven@example.test', '2027-03-01T11:01:00Z', null, null
  ) is not null then
    raise exception 'Seven-argument legacy RPC bypassed a stored provider payload fingerprint.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_legacy_five_fingerprint', 'email.bounced', 'resend-legacy-five-fingerprint',
    'legacy-five@example.test', '2027-03-01T11:02:00Z', 'Permanent', null, null, repeat('5', 64)
  ) is not true then raise exception 'Five-argument legacy fingerprint fixture was not inserted.'; end if;
  if public.record_delivery_provider_event(
    'evt_legacy_five_fingerprint', 'email.bounced', 'resend-legacy-five-fingerprint',
    'legacy-five@example.test', 'Permanent'
  ) is not null then
    raise exception 'Five-argument legacy provider-event RPC bypassed a stored provider payload fingerprint.';
  end if;
end;
$legacy_fingerprint_replays$;
reset role;

do $legacy_fingerprint_assertions$
begin
  if not exists (select 1 from public.delivery_provider_events
      where event_id = 'evt_legacy_eight_fingerprint' and payload_fingerprint = repeat('8', 64))
    or not exists (select 1 from public.delivery_provider_integrity_anomalies
      where event_id = 'evt_legacy_eight_fingerprint' and anomaly_type = 'duplicate_event_id_conflict')
    or (select status from public.delivery_provider_lifecycle
      where provider_email_id = 'resend-legacy-eight-fingerprint') is distinct from 'integrity_anomaly' then
    raise exception 'Eight-argument legacy replay changed or failed to flag fingerprinted event history.';
  end if;
  if not exists (select 1 from public.delivery_provider_events
      where event_id = 'evt_legacy_seven_fingerprint' and payload_fingerprint = repeat('7', 64))
    or not exists (select 1 from public.delivery_provider_integrity_anomalies
      where event_id = 'evt_legacy_seven_fingerprint' and anomaly_type = 'duplicate_event_id_conflict')
    or (select status from public.delivery_provider_lifecycle
      where provider_email_id = 'resend-legacy-seven-fingerprint') is distinct from 'integrity_anomaly' then
    raise exception 'Seven-argument legacy replay changed or failed to flag fingerprinted event history.';
  end if;
  if not exists (select 1 from public.delivery_provider_events
      where event_id = 'evt_legacy_five_fingerprint' and payload_fingerprint = repeat('5', 64))
    or not exists (select 1 from public.delivery_provider_integrity_anomalies
      where event_id = 'evt_legacy_five_fingerprint' and anomaly_type = 'duplicate_event_id_conflict')
    or (select status from public.delivery_provider_lifecycle
      where provider_email_id = 'resend-legacy-five-fingerprint') is distinct from 'integrity_anomaly' then
    raise exception 'Five-argument legacy replay changed or failed to flag fingerprinted event history.';
  end if;
  if exists (select 1 from public.delivery_provider_integrity_anomalies
      where event_id in ('evt_historical_025_suppressed', 'evt_historical_026_complaint')) then
    raise exception 'Historical NULL-fingerprint compatibility was incorrectly flagged as a conflict.';
  end if;
  if exists (
    select 1
    from (values
      ('evt_legacy_eight_fingerprint', 'email.sent', 'resend-legacy-eight-fingerprint',
        'legacy-eight@example.test', '2027-03-01T11:00:00Z'::timestamptz,
        null::text, repeat('8', 64)),
      ('evt_legacy_seven_fingerprint', 'email.sent', 'resend-legacy-seven-fingerprint',
        'legacy-seven@example.test', '2027-03-01T11:01:00Z'::timestamptz,
        null::text, repeat('7', 64)),
      ('evt_legacy_five_fingerprint', 'email.bounced', 'resend-legacy-five-fingerprint',
        'legacy-five@example.test', '2027-03-01T11:02:00Z'::timestamptz,
        'Permanent'::text, repeat('5', 64))
    ) as expected(event_id, event_type, provider_email_id, recipient_email,
                  provider_created_at, bounce_type, payload_fingerprint)
    left join public.delivery_provider_events e using (event_id)
    where e.event_id is null
      or e.event_type is distinct from expected.event_type
      or e.provider_email_id is distinct from expected.provider_email_id
      or e.recipient_email is distinct from expected.recipient_email
      or e.provider_created_at is distinct from expected.provider_created_at
      or e.bounce_type is distinct from expected.bounce_type
      or e.failure_class is not null
      or e.suppression_reason is not null
      or e.payload_fingerprint is distinct from expected.payload_fingerprint
  ) then
    raise exception 'Legacy fingerprint conflicts mutated or removed existing event records.';
  end if;
  if not exists (
    select 1 from public.delivery_provider_suppressions
    where recipient_email = 'legacy-five@example.test'
      and reason = 'permanent_bounce'
      and provider_event_id = 'evt_legacy_five_fingerprint'
  ) then
    raise exception 'Five-argument legacy fingerprint conflict mutated existing suppression state.';
  end if;
end;
$legacy_fingerprint_assertions$;

do $historical_assertions$
begin
  if not exists (
    select 1
    from public.delivery_provider_events
    where event_id = 'evt_historical_025_suppressed'
      and event_type = 'email.suppressed'
      and provider_created_at is null
      and suppression_reason is null
      and payload_fingerprint is null
  )
    or not exists (
      select 1
      from public.delivery_provider_suppressions
      where recipient_email = 'historical-025-suppressed@example.test'
        and reason = 'provider_suppressed'
        and provider_event_id = 'evt_historical_025_suppressed'
    )
    or exists (
      select 1 from public.delivery_provider_integrity_anomalies
      where event_id = 'evt_historical_025_suppressed'
    ) then
    raise exception 'Pre-026 event history or fail-closed suppression state changed on replay.';
  end if;

  if not exists (
    select 1
    from public.delivery_provider_events
    where event_id = 'evt_historical_026_complaint'
      and event_type = 'email.complained'
      and provider_created_at = '2027-03-01T09:15:00Z'::timestamptz
      and suppression_reason is null
      and payload_fingerprint is null
  )
    or not exists (
      select 1
      from public.delivery_provider_suppressions
      where recipient_email = 'historical-026-complaint@example.test'
        and reason = 'complaint'
        and provider_event_id = 'evt_historical_026_complaint'
    )
    or not exists (
      select 1
      from public.delivery_provider_lifecycle
      where provider_email_id = 'resend-historical-026-complaint'
        and status = 'email.complained'
        and event_id = 'evt_historical_026_complaint'
    )
    or exists (
      select 1 from public.delivery_provider_integrity_anomalies
      where event_id = 'evt_historical_026_complaint'
    ) then
    raise exception 'Pre-027 event history or complaint suppression changed on replay.';
  end if;
end;
$historical_assertions$;


-- Synthetic local-only users; no provider sends or Production data.
update public.daily_reminder_preferences set daily_enabled = false;
update public.newsletter_preferences set weekly_enabled = false;

insert into auth.users (id, email, email_confirmed_at)
select
  ('00000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
  'webhook-' || i::text || '@example.test',
  now()
from generate_series(20001, 20005) as i;

insert into public.profiles (user_id, is_suspended)
select id, false from auth.users
where id::text like '00000000-0000-0000-0000-000000020%';

insert into public.daily_reminder_preferences
  (user_id, daily_enabled, reminder_time, timezone)
select id, true, '00:00'::time, 'UTC'
from auth.users
where id::text like '00000000-0000-0000-0000-000000020%';

insert into public.newsletter_preferences
  (user_id, weekly_enabled, consented_at, consent_source)
select id, true, now(), 'provider-webhook-fixture'
from auth.users
where id::text like '00000000-0000-0000-0000-000000020%';

insert into public.weekly_goodness_features (week_start)
values ('2027-03-01') on conflict (week_start) do nothing;

set role service_role;
do $$
begin
  if public.record_delivery_provider_lifecycle_event(
    'msg_bounce_permanent_20001', 'email.bounced', 'resend-bounce-20001',
    'WEBHOOK-20001@EXAMPLE.TEST', '2027-03-01T10:00:00Z', 'Permanent',
    null, null, repeat('1', 64)
  ) is not true then
    raise exception 'Permanent bounce event was not recorded.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'msg_bounce_permanent_20001', 'email.bounced', 'resend-bounce-20001',
    'webhook-20001@example.test', '2027-03-01T10:00:00Z', 'Permanent',
    null, null, repeat('1', 64)
  ) is not false then
    raise exception 'Exact duplicate provider event was not a successful no-op.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'msg_bounce_transient_20002', 'email.bounced', 'resend-bounce-20002',
    'webhook-20002@example.test', '2027-03-01T10:01:00Z', 'Transient',
    null, null, repeat('2', 64)
  ) is not true then
    raise exception 'Transient bounce event was not recorded.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'msg_complaint_20003', 'email.complained', 'resend-complaint-20003',
    'webhook-20003@example.test', '2027-03-01T10:02:00Z',
    null, null, null, repeat('3', 64)
  ) is not true then
    raise exception 'Complaint event was not recorded.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'msg_suppressed_20004', 'email.suppressed', 'resend-suppressed-20004',
    'webhook-20004@example.test', '2027-03-01T10:03:00Z',
    null, null, 'provider_suppressed', repeat('4', 64)
  ) is not true then
    raise exception 'Provider suppression event was not recorded.';
  end if;
  perform public.record_delivery_provider_suppression_event('evt_c331_manual_add_after_lifecycle_20004','suppression.added','sup_c331_manual_20004','webhook-20004@example.test','manual',null,'2027-03-01T10:00:00Z','2027-03-01T10:01:00Z',repeat('8',64));
  perform public.record_delivery_provider_suppression_event('evt_c331_old_manual_remove_after_lifecycle_20004','suppression.removed','sup_c331_manual_20004','webhook-20004@example.test','manual',null,'2027-03-01T10:00:00Z','2027-03-01T10:02:00Z',repeat('9',64));

  if public.record_delivery_provider_lifecycle_event(
    'evt_suppressed_previous_bounce', 'email.suppressed',
    'resend-suppressed-previous-bounce', 'lifecycle-previous-bounce@example.test',
    '2027-03-01T10:20:00Z', null, null, 'previous_bounce', repeat('5', 64)
  ) is not true then
    raise exception 'previous_bounce suppression reason was not recorded.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_suppressed_previous_complaint', 'email.suppressed',
    'resend-suppressed-previous-complaint', 'lifecycle-previous-complaint@example.test',
    '2027-03-01T10:21:00Z', null, null, 'previous_complaint', repeat('6', 64)
  ) is not true then
    raise exception 'previous_complaint suppression reason was not recorded.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'msg_bounce_unknown_20005', 'email.bounced', 'resend-bounce-20005',
    'webhook-20005@example.test', '2027-03-01T10:04:00Z', 'Unknown',
    null, null, repeat('7', 64)
  ) is not true then
    raise exception 'Unknown bounce event was not recorded.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'msg_bounce_conflict_20006', 'email.bounced', 'resend-bounce-conflict-20006',
    'conflict-duplicate@example.test', '2027-03-01T10:05:00Z', 'Permanent',
    null, null, repeat('8', 64)
  ) is not true then
    raise exception 'Conflicting duplicate fixture bounce was not recorded.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'msg_bounce_conflict_20006', 'email.bounced', 'resend-bounce-conflict-20006',
    'conflict-duplicate@example.test', '2027-03-01T10:05:00Z', 'Permanent',
    null, null, repeat('8', 64)
  ) is not false then
    raise exception 'Conflicting duplicate fixture exact replay was not a no-op.';
  end if;



  if public.record_delivery_provider_lifecycle_event(
    'msg_complaint_upgrade_20001', 'email.complained', 'resend-complaint-20001',
    'webhook-20001@example.test', '2027-03-01T10:06:00Z',
    null, null, null, repeat('9', 64)
  ) is not true then
    raise exception 'Complaint upgrade event was not recorded.';
  end if;
end;
$$;
reset role;

-- Snapshot private rows as the privileged test connection, not service_role.
create temporary table provider_conflict_event_snapshot as
  select to_jsonb(e) as row_data
  from public.delivery_provider_events e
  where e.event_id = 'msg_bounce_conflict_20006';

create temporary table provider_conflict_suppression_snapshot as
  select to_jsonb(s) as row_data
  from public.delivery_provider_suppressions s
  where s.recipient_email = 'conflict-duplicate@example.test';

set role service_role;
do $$
begin
  if public.record_delivery_provider_event(
    'msg_bounce_conflict_20006', 'email.complained', 'different-provider-id',
    'attacker@example.test', null
  ) is not null then
    raise exception 'Conflicting duplicate event ID was not recorded as an integrity anomaly.';
  end if;
end;
$$;
reset role;

do $$
begin
  if (select event_type from public.delivery_provider_events
      where event_id = 'msg_bounce_conflict_20006') <> 'email.bounced'
    or (select provider_email_id from public.delivery_provider_events
      where event_id = 'msg_bounce_conflict_20006') <> 'resend-bounce-conflict-20006'
    or (select recipient_email from public.delivery_provider_events
      where event_id = 'msg_bounce_conflict_20006') <> 'conflict-duplicate@example.test'
    or (select reason from public.delivery_provider_suppressions
      where recipient_email = 'conflict-duplicate@example.test') <> 'permanent_bounce'
    or (select status from public.delivery_provider_lifecycle
      where provider_email_id = 'resend-bounce-conflict-20006') <> 'integrity_anomaly'
    or not exists (
      select 1 from public.delivery_provider_integrity_anomalies
      where event_id = 'msg_bounce_conflict_20006'
        and anomaly_type = 'duplicate_event_id_conflict'
    ) then
    raise exception 'Conflicting duplicate changed original event or suppression state.';
  end if;
  if (select row_data from provider_conflict_event_snapshot)
       is distinct from (
         select to_jsonb(e) from public.delivery_provider_events e
         where e.event_id = 'msg_bounce_conflict_20006'
       )
    or (select row_data from provider_conflict_suppression_snapshot)
       is distinct from (
         select to_jsonb(s) from public.delivery_provider_suppressions s
         where s.recipient_email = 'conflict-duplicate@example.test'
       ) then
    raise exception 'Conflicting duplicate mutated original event history or suppression row.';
  end if;
  if (select reason from public.delivery_provider_suppressions
      where recipient_email = 'webhook-20001@example.test') <> 'complaint' then
    raise exception 'Complaint did not take precedence over a permanent bounce.';
  end if;
  if (select reason from public.delivery_provider_suppressions
      where recipient_email = 'webhook-20003@example.test') <> 'complaint' then
    raise exception 'Complaint suppression was not recorded.';
  end if;
  if (select reason from public.delivery_provider_suppressions
      where recipient_email = 'webhook-20004@example.test') <> 'provider_suppressed' then
    raise exception 'Provider suppression was not recorded.';
  end if;
  if (select reason from public.delivery_provider_suppressions
      where recipient_email = 'webhook-20005@example.test') <> 'permanent_bounce' then
    raise exception 'Unknown bounce classification did not fail closed.';
  end if;
  if exists (select 1 from public.delivery_provider_suppressions
      where recipient_email = 'webhook-20002@example.test') then
    raise exception 'Transient bounce incorrectly suppressed the recipient.';
  end if;
  if exists (select 1 from public.delivery_provider_suppressions
      where recipient_email = 'attacker@example.test') then
    raise exception 'Duplicate event ID changed the suppression recipient.';
  end if;
end;
$$;

-- Suppressed recipients are removed before daily/weekly batch limits.
do $$
declare
  v_daily integer;
  v_weekly integer;
begin
  v_daily := public.enqueue_due_daily_reminders(now() + interval '2 days', 5000);
  if v_daily <> 1 then
    raise exception 'Expected only the transient-bounce daily recipient, got %.', v_daily;
  end if;

  v_weekly := public.enqueue_weekly_goodness_delivery(
    '2027-03-01', now(), 5000
  );
  if v_weekly <> 1 then
    raise exception 'Expected only the transient-bounce weekly recipient, got %.', v_weekly;
  end if;
end;
$$;

-- A pre-existing queued/claimed row is still stopped at the final transport gate.
insert into public.delivery_ledger (
  user_id, kind, delivery_key, state, scheduled_for,
  claim_token, claimed_at, claim_expires_at, attempt_count
) values
(
  '00000000-0000-0000-0000-000000020001',
  'daily_reminder',
  'daily:' || timezone('UTC', now() + interval '3 days')::date::text,
  'claimed',
  (timezone('UTC', now() + interval '3 days')::date + time '00:00') at time zone 'UTC',
  '33333333-3333-3333-3333-333333332001',
  now(),
  now() + interval '5 minutes',
  1
),
(
  '00000000-0000-0000-0000-000000020003',
  'weekly_newsletter',
  'weekly:2027-03-01',
  'claimed',
  '2027-03-01 16:00:00+00',
  '33333333-3333-3333-3333-333333332003',
  now(),
  now() + interval '5 minutes',
  1
),
(
  '00000000-0000-0000-0000-000000020004',
  'daily_reminder',
  'daily:' || timezone('UTC', now() + interval '3 days')::date::text,
  'claimed',
  (timezone('UTC', now() + interval '3 days')::date + time '00:00') at time zone 'UTC',
  '33333333-3333-3333-3333-333333332004',
  now(),
  now() + interval '5 minutes',
  1
);

set role service_role;
do $$
begin
  if public.begin_delivery_transport(
    (select id from public.delivery_ledger
      where user_id='00000000-0000-0000-0000-000000020001'
        and kind='daily_reminder' and state='claimed'),
    '33333333-3333-3333-3333-333333332001',
    'webhook-20001@example.test'
  ) is not null then
    raise exception 'Suppressed daily recipient reached transport.';
  end if;

  if public.begin_delivery_transport(
    (select id from public.delivery_ledger
      where user_id='00000000-0000-0000-0000-000000020003'
        and kind='weekly_newsletter' and state='claimed'),
    '33333333-3333-3333-3333-333333332003',
    'webhook-20003@example.test'
  ) is not null then
    raise exception 'Complained weekly recipient reached transport.';
  end if;
  if public.begin_delivery_transport(
    (select id from public.delivery_ledger where user_id='00000000-0000-0000-0000-000000020004' and kind='daily_reminder' and state='claimed'),
    '33333333-3333-3333-3333-333333332004','webhook-20004@example.test'
  ) is not null then
    raise exception 'Cross-stream stale manual removal bypassed final transport authorization.';
  end if;
end;
$$;
reset role;

do $$
begin
  if (select reason from public.delivery_provider_suppressions where recipient_email='webhook-20004@example.test') is distinct from 'provider_suppressed' then
    raise exception 'Older manual removal erased newer lifecycle suppression before final authorization.';
  end if;
  if exists (select 1 from public.delivery_ledger
      where user_id='00000000-0000-0000-0000-000000020001'
        and kind='daily_reminder' and state='claimed') then
    raise exception 'Suppressed daily job was not cancelled.';
  end if;
  if exists (select 1 from public.delivery_ledger
      where user_id='00000000-0000-0000-0000-000000020003'
        and kind='weekly_newsletter' and state='claimed') then
    raise exception 'Suppressed weekly job was not cancelled.';
  end if;
  if exists (select 1 from public.delivery_ledger where user_id='00000000-0000-0000-0000-000000020004' and kind='daily_reminder' and state='claimed') then
    raise exception 'Cross-stream stale-removal daily job was not cancelled.';
  end if;
  if has_table_privilege('anon','public.delivery_provider_events','SELECT')
    or has_table_privilege('authenticated','public.delivery_provider_events','SELECT')
    or has_table_privilege('service_role','public.delivery_provider_events','SELECT')
    or has_table_privilege('anon','public.delivery_provider_suppressions','SELECT')
    or has_table_privilege('authenticated','public.delivery_provider_suppressions','SELECT')
    or has_table_privilege('service_role','public.delivery_provider_suppressions','SELECT')
    or has_table_privilege('anon','public.delivery_provider_integrity_anomalies','SELECT')
    or has_table_privilege('authenticated','public.delivery_provider_integrity_anomalies','SELECT')
    or has_table_privilege('service_role','public.delivery_provider_integrity_anomalies','SELECT') then
    raise exception 'Provider webhook and integrity tables are directly readable.';
  end if;
  if has_function_privilege('anon',
       'public.record_delivery_provider_event(text,text,text,text,text)','EXECUTE')
    or has_function_privilege('authenticated',
       'public.record_delivery_provider_event(text,text,text,text,text)','EXECUTE')
    or not has_function_privilege('service_role',
       'public.record_delivery_provider_event(text,text,text,text,text)','EXECUTE')
    or has_function_privilege('anon',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)','EXECUTE')
    or has_function_privilege('authenticated',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)','EXECUTE')
    or not has_function_privilege('service_role',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)','EXECUTE')
    or has_function_privilege('anon',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or has_function_privilege('authenticated',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or not has_function_privilege('service_role',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or has_function_privilege('service_role',
       'public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or exists (
      select 1
      from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid = to_regprocedure('public.record_delivery_provider_event(text,text,text,text,text)')
        and a.grantee = 0 and a.privilege_type = 'EXECUTE'
    ) then
    raise exception 'Provider event RPC direct ACLs or canonical implementation isolation regressed.';
  end if;
  if not (select relrowsecurity from pg_class where oid='public.delivery_provider_events'::regclass)
    or not (select relrowsecurity from pg_class where oid='public.delivery_provider_suppressions'::regclass)
    or not (select relrowsecurity from pg_class where oid='public.delivery_provider_integrity_anomalies'::regclass) then
    raise exception 'Provider webhook and integrity tables must retain RLS.';
  end if;
end;
$$;


-- Snapshot the entire queue ledger: provider lifecycle intake must never mutate it.
create temporary table delivery_ledger_lifecycle_snapshot as
select id, to_jsonb(dl) as row_data
from public.delivery_ledger dl;

set role service_role;
do $lifecycle$
begin
  if public.record_delivery_provider_lifecycle_event(
    'evt_order_sent', 'email.sent', 'resend-order-20001',
    'lifecycle-order@example.test', '2027-03-01T10:00:00Z',
    null, null, null, repeat('a', 64)
  ) is not true then raise exception 'email.sent was not recorded.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_order_delayed', 'email.delivery_delayed', 'resend-order-20001',
    'lifecycle-order@example.test', '2027-03-01T10:05:00Z',
    null, null, null, repeat('b', 64)
  ) is not true then raise exception 'email.delivery_delayed was not recorded.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_order_delivered', 'email.delivered', 'resend-order-20001',
    'lifecycle-order@example.test', '2027-03-01T10:10:00Z',
    null, null, null, repeat('c', 64)
  ) is not true then raise exception 'email.delivered was not recorded.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_order_delayed_old', 'email.delivery_delayed', 'resend-order-20001',
    'lifecycle-order@example.test', '2027-03-01T10:04:00Z',
    null, null, null, repeat('d', 64)
  ) is not true then raise exception 'Out-of-order delayed event was not retained.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_failed_quota', 'email.failed', 'resend-failed-20002',
    'lifecycle-failed@example.test', '2027-03-01T10:11:00Z',
    null, 'quota_exceeded', null, repeat('e', 64)
  ) is not true then raise exception 'email.failed was not recorded.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_c353_failure_conflicting_delivered', 'email.delivered', 'resend-failed-20002',
    'lifecycle-failed@example.test', '2027-03-01T10:12:00Z',
    null, null, null, repeat('4', 64)
  ) is not null then
    raise exception 'Contradictory delivered event was not recorded as a conflict.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_failed_quota', 'email.sent', 'resend-failed-20002',
    'lifecycle-failed@example.test', '2027-03-01T10:11:00Z',
    null, null, null, repeat('5', 64)
  ) is not null then
    raise exception 'Duplicate event conflict was not recorded.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_precedence_bounce', 'email.bounced', 'resend-precedence-20003',
    'lifecycle-precedence@example.test', '2027-03-01T10:00:00Z',
    'Permanent', null, null, repeat('f', 64)
  ) is not true then raise exception 'Lifecycle permanent bounce was not recorded.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_precedence_complaint', 'email.complained', 'resend-precedence-20003',
    'lifecycle-precedence@example.test', '2027-03-01T10:01:00Z',
    null, null, null, repeat('0', 64)
  ) is not null then raise exception 'Contradictory complaint after bounce was not flagged.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_precedence_bounce_late', 'email.bounced', 'resend-precedence-20003',
    'lifecycle-precedence@example.test', '2027-03-01T10:02:00Z',
    'Permanent', null, null, repeat('a', 64)
  ) is not null then raise exception 'Contradictory late bounce was not flagged.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_provider_suppressed', 'email.suppressed', 'resend-lifecycle-suppressed-20004',
    'lifecycle-suppressed@example.test', '2027-03-01T10:12:00Z',
    null, null, 'provider_suppressed', repeat('b', 64)
  ) is not true then raise exception 'email.suppressed was not recorded.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_transient_bounce', 'email.bounced', 'resend-lifecycle-transient-20005',
    'lifecycle-transient@example.test', '2027-03-01T10:13:00Z',
    'Transient', null, null, repeat('c', 64)
  ) is not true then raise exception 'Transient lifecycle bounce was not recorded.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_payload_fingerprint', 'email.sent', 'resend-payload-fingerprint',
    'payload-fingerprint@example.test', '2027-03-01T10:25:00Z',
    null, null, null, repeat('a', 64)
  ) is not true then raise exception 'Payload fingerprint fixture was not recorded.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_payload_fingerprint', 'email.sent', 'resend-payload-fingerprint',
    'payload-fingerprint@example.test', '2027-03-01T10:25:00Z',
    null, null, null, repeat('a', 64)
  ) is not false then raise exception 'Exact payload fingerprint replay was not a no-op.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_payload_fingerprint', 'email.sent', 'resend-payload-fingerprint',
    'payload-fingerprint@example.test', '2027-03-01T10:25:00Z',
    null, null, null, repeat('b', 64)
  ) is not null then raise exception 'Payload fingerprint conflict was not recorded as an integrity anomaly.'; end if;



  if public.record_delivery_provider_lifecycle_event(
    'evt_terminal_delivered_first', 'email.delivered', 'resend-terminal-delivered-first',
    'terminal-delivered-first@example.test', '2027-03-01T10:30:00Z',
    null, null, null, repeat('d', 64)
  ) is not true then raise exception 'Delivered-first terminal fixture failed.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_terminal_bounce_after', 'email.bounced', 'resend-terminal-delivered-first',
    'terminal-delivered-first@example.test', '2027-03-01T10:31:00Z',
    'Permanent', null, null, repeat('e', 64)
  ) is not null then raise exception 'Delivered then bounced was not flagged.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_terminal_bounce_first', 'email.bounced', 'resend-terminal-bounced-first',
    'terminal-bounced-first@example.test', '2027-03-01T10:40:00Z',
    'Permanent', null, null, repeat('f', 64)
  ) is not true then raise exception 'Bounced-first terminal fixture failed.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_terminal_delivered_after', 'email.delivered', 'resend-terminal-bounced-first',
    'terminal-bounced-first@example.test', '2027-03-01T10:41:00Z',
    null, null, null, repeat('0', 64)
  ) is not null then raise exception 'Bounced then delivered was not flagged.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_precedence_complaint_first', 'email.complained', 'resend-precedence-reverse',
    'lifecycle-precedence-reverse@example.test', '2027-03-01T10:50:00Z',
    null, null, null, repeat('1', 64)
  ) is not true then raise exception 'Complaint-first fixture failed.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_precedence_bounce_after', 'email.bounced', 'resend-precedence-reverse',
    'lifecycle-precedence-reverse@example.test', '2027-03-01T10:51:00Z',
    'Permanent', null, null, repeat('2', 64)
  ) is not null then raise exception 'Complaint then bounce was not flagged.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_order_delayed_old', 'email.delivery_delayed', 'resend-order-20001',
    'lifecycle-order@example.test', '2027-03-01T10:04:00Z',
    null, null, null, repeat('d', 64)
  ) is not false then raise exception 'Exact lifecycle replay was not an idempotent no-op.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_provider_id_wrong_recipient', 'email.sent', 'resend-order-20001',
    'different-recipient@example.test', '2027-03-01T10:15:00Z',
    null, null, null, repeat('3', 64)
  ) is not null then
    raise exception 'Provider email ID was accepted for a different recipient.';
  end if;
end;
$lifecycle$;
reset role;

do $c353_provider_email_recipient_assertions$
begin
  if not exists (
    select 1 from public.delivery_provider_integrity_cases
    where recipient_email='different-recipient@example.test'
      and anomaly_type='provider_email_recipient_conflict'
      and state='open'
  ) then
    raise exception 'Cross-recipient provider email ID conflict did not create a recipient-scoped case.';
  end if;

  if not exists (
    select 1 from public.delivery_provider_integrity_conflict_evidence
    where recipient_email='different-recipient@example.test'
      and event_id='evt_provider_id_wrong_recipient'
      and stored_event_id='evt_order_sent'
      and stored_recipient_email='lifecycle-order@example.test'
      and payload_fingerprint=repeat('3', 64)
  ) then
    raise exception 'Cross-recipient provider email ID conflict evidence was not preserved.';
  end if;

  if (select status from public.delivery_provider_lifecycle
      where provider_email_id='resend-order-20001') is distinct from 'integrity_anomaly' then
    raise exception 'Cross-recipient provider email ID collision did not fail closed in the lifecycle projection.';
  end if;
end;
$c353_provider_email_recipient_assertions$;

do $lifecycle$
begin
  if (select payload_fingerprint from public.delivery_provider_events
      where event_id = 'evt_payload_fingerprint') <> repeat('a', 64)
    or not exists (
      select 1 from public.delivery_provider_integrity_anomalies
      where event_id = 'evt_payload_fingerprint'
        and anomaly_type = 'duplicate_event_id_conflict'
    ) then
    raise exception 'Payload fingerprint conflict replaced the original event.';
  end if;
  if (select status from public.delivery_provider_lifecycle
      where provider_email_id = 'resend-order-20001') <> 'integrity_anomaly' then
    raise exception 'Out-of-order event regressed delivered lifecycle evidence.';
  end if;
  if not exists (
    select 1 from public.delivery_provider_lifecycle l
    join public.delivery_provider_events e using (event_id)
    where l.provider_email_id = 'resend-order-20001'
      and l.status = 'integrity_anomaly'
      and l.event_id = 'evt_order_delivered'
      and l.provider_created_at = '2027-03-01T10:10:00Z'::timestamptz
      and l.received_at = e.received_at
      and e.provider_created_at = '2027-03-01T10:10:00Z'::timestamptz
      and e.received_at <= clock_timestamp()
  ) then
    raise exception 'Provider and database receipt timestamps were not preserved.';
  end if;
  if (select count(*) from public.delivery_provider_events
      where provider_email_id = 'resend-order-20001') <> 4 then
    raise exception 'Lifecycle history did not retain all unique out-of-order events.';
  end if;
  if not exists (
    select 1 from public.delivery_provider_lifecycle
    where provider_email_id = 'resend-failed-20002'
      and status = 'integrity_anomaly'
      and event_id = 'evt_failed_quota'
      and failure_class is null
  ) or not exists (
    select 1 from public.delivery_provider_events
    where event_id = 'evt_failed_quota'
      and failure_class = 'quota_exceeded'
  ) then
    raise exception 'Conflicting provider events erased the original failure classification or canonical event.';
  end if;

  if not exists (
    select 1 from public.delivery_provider_integrity_cases
    where recipient_email = 'lifecycle-failed@example.test'
      and anomaly_type = 'contradictory_terminal_outcome'
      and state = 'open'
  ) or not exists (
    select 1 from public.delivery_provider_integrity_conflict_evidence
    where event_id = 'evt_c353_failure_conflicting_delivered'
      and stored_event_id = 'evt_failed_quota'
      and payload_fingerprint = repeat('4', 64)
  ) or not exists (
    select 1 from public.delivery_provider_integrity_cases
    where recipient_email = 'lifecycle-failed@example.test'
      and anomaly_type = 'duplicate_event_id_conflict'
      and state = 'open'
  ) or not exists (
    select 1 from public.delivery_provider_integrity_conflict_evidence
    where event_id = 'evt_failed_quota'
      and stored_event_id = 'evt_failed_quota'
      and payload_fingerprint = repeat('5', 64)
  ) then
    raise exception 'Conflicting provider event evidence or its recipient-scoped cases were not preserved.';
  end if;
  if (select status from public.delivery_provider_lifecycle
      where provider_email_id = 'resend-precedence-20003') <> 'integrity_anomaly'
    or not exists (
      select 1 from public.delivery_provider_integrity_anomalies
      where event_id = 'evt_precedence_complaint'
        and anomaly_type = 'contradictory_terminal_outcome'
    ) then
    raise exception 'Contradictory bounce/complaint lifecycle was not marked as an integrity anomaly.';
  end if;
  if (select reason from public.delivery_provider_suppressions
      where recipient_email = 'lifecycle-precedence@example.test') <> 'complaint' then
    raise exception 'Complaint did not retain precedence over later permanent bounce.';
  end if;
  if not exists (
    select 1 from public.delivery_provider_lifecycle
    where provider_email_id = 'resend-lifecycle-suppressed-20004'
      and status = 'email.suppressed'
  ) or not exists (
    select 1 from public.delivery_provider_suppressions
    where recipient_email = 'lifecycle-suppressed@example.test'
      and reason = 'provider_suppressed'
  ) then
    raise exception 'Provider suppression lifecycle was not persisted.';
  end if;
  if not exists (
    select 1 from public.delivery_provider_lifecycle
    where provider_email_id = 'resend-lifecycle-transient-20005'
      and status = 'email.bounced'
  ) then
    raise exception 'Transient bounce lifecycle evidence was not persisted.';
  end if;
  if (select reason from public.delivery_provider_suppressions
      where recipient_email = 'lifecycle-previous-bounce@example.test') <> 'permanent_bounce'
    or (select reason from public.delivery_provider_suppressions
      where recipient_email = 'lifecycle-previous-complaint@example.test') <> 'complaint' then
    raise exception 'Resend nested suppression reasons were not mapped to the correct suppression classes.';
  end if;
  if (select status from public.delivery_provider_lifecycle
      where provider_email_id = 'resend-terminal-delivered-first') <> 'integrity_anomaly'
    or (select count(*) from public.delivery_provider_events
      where provider_email_id = 'resend-terminal-delivered-first') <> 2 then
    raise exception 'Delivered-then-bounced terminal conflict was not retained and flagged.';
  end if;
  if (select status from public.delivery_provider_lifecycle
      where provider_email_id = 'resend-terminal-bounced-first') <> 'integrity_anomaly'
    or (select count(*) from public.delivery_provider_events
      where provider_email_id = 'resend-terminal-bounced-first') <> 2 then
    raise exception 'Bounced-then-delivered terminal conflict was not retained and flagged.';
  end if;
  if (select reason from public.delivery_provider_suppressions
      where recipient_email = 'lifecycle-precedence-reverse@example.test') <> 'complaint'
    or (select status from public.delivery_provider_lifecycle
      where provider_email_id = 'resend-precedence-reverse') <> 'integrity_anomaly' then
    raise exception 'Complaint precedence was not preserved for reverse-order contradictory outcomes.';
  end if;
  if exists (select 1 from public.delivery_provider_suppressions
      where recipient_email in (
        'lifecycle-transient@example.test',
        'lifecycle-failed@example.test',
        'lifecycle-order@example.test'
      )) then
    raise exception 'Informational, transient or failed lifecycle events incorrectly suppressed recipients.';
  end if;
  if exists (select 1 from public.delivery_provider_suppressions
      where recipient_email = 'different-recipient@example.test') then
    raise exception 'Provider email ID mismatch created an unintended suppression.';
  end if;
  if exists (
    select id, row_data from delivery_ledger_lifecycle_snapshot
    except
    select id, to_jsonb(dl) from public.delivery_ledger dl
  ) or exists (
    select id, to_jsonb(dl) from public.delivery_ledger dl
    except
    select id, row_data from delivery_ledger_lifecycle_snapshot
  ) then
    raise exception 'Lifecycle webhook mutated delivery queue, claim or retry state.';
  end if;
  if has_table_privilege('anon','public.delivery_provider_lifecycle','SELECT')
    or has_table_privilege('authenticated','public.delivery_provider_lifecycle','SELECT')
    or has_table_privilege('service_role','public.delivery_provider_lifecycle','SELECT') then
    raise exception 'Provider lifecycle projection is directly readable.';
  end if;
  if not (select relrowsecurity from pg_class where oid='public.delivery_provider_lifecycle'::regclass) then
    raise exception 'Provider lifecycle projection must retain RLS.';
  end if;
  -- The renamed implementation is private even to service_role; only the
  -- guarded canonical RPC may invoke it.
  if has_function_privilege('anon',
       'public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or has_function_privilege('authenticated',
       'public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or has_function_privilege('service_role',
       'public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or exists (
      select 1
      from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid = to_regprocedure('public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)')
        and a.grantee = 0 and a.privilege_type = 'EXECUTE'
    ) then
    raise exception 'Private provider lifecycle implementation ACLs regressed.';
  end if;

  -- The public canonical RPC retains its existing service_role-only boundary.
  if has_function_privilege('anon',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or has_function_privilege('authenticated',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or not has_function_privilege('service_role',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or exists (
      select 1
      from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid = to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)')
        and a.grantee = 0 and a.privilege_type = 'EXECUTE'
    ) then
    raise exception 'Canonical provider lifecycle RPC ACLs regressed.';
  end if;

  if has_function_privilege('anon',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)','EXECUTE')
    or has_function_privilege('authenticated',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)','EXECUTE')
    or not has_function_privilege('service_role',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)','EXECUTE')
    or has_function_privilege('anon',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)','EXECUTE')
    or has_function_privilege('authenticated',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)','EXECUTE')
    or not has_function_privilege('service_role',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)','EXECUTE')
    or has_function_privilege('anon',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or has_function_privilege('authenticated',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE')
    or not has_function_privilege('service_role',
       'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE') then
    raise exception 'Provider lifecycle RPC grants regressed.';
  end if;
  if not exists (
    select 1 from pg_attribute
    where attrelid = 'public.delivery_provider_events'::regclass
      and attnum > 0 and not attisdropped
      and attname = 'payload_fingerprint'
  ) then
    raise exception 'Provider event payload fingerprint column is missing.';
  end if;
  if exists (
    select 1 from pg_attribute
    where attrelid = 'public.delivery_provider_lifecycle'::regclass
      and attnum > 0 and not attisdropped
      and attname = 'recipient_email'
  ) or exists (
    select 1 from pg_attribute
    where attrelid in (
        'public.delivery_provider_lifecycle'::regclass,
        'public.delivery_provider_events'::regclass
      )
      and attnum > 0 and not attisdropped
      and attname in ('raw_payload', 'diagnostic_code', 'diagnostic_message',
                      'failure_reason', 'provider_error')
  ) then
    raise exception 'Provider lifecycle storage contains private recipient or raw diagnostic fields.';
  end if;
end;
$lifecycle$;

select jsonb_build_object(
  'provider_event_dedupe','pass',
  'payload_fingerprint_idempotency','pass',
  'conflicting_duplicate_integrity_anomaly','pass',
  'resend_suppression_reason_mapping','pass',
  'contradictory_terminal_outcomes','pass',
  'permanent_bounce_suppression','pass',
  'transient_bounce_not_suppressed','pass',
  'complaint_and_provider_suppression','pass',
  'unknown_bounce_fail_closed','pass',
  'daily_weekly_enqueue_exclusion','pass',
  'final_transport_gate','pass',
  'private_table_and_rpc_grants','pass',
  'seven_event_lifecycle_persistence','pass',
  'provider_and_receipt_timestamps','pass',
  'out_of_order_evidence_monotonicity','pass',
  'normalized_failure_classification','pass',
  'complaint_precedence','pass',
  'no_queue_or_retry_mutation','pass',
  'lifecycle_projection_privacy','pass'
) as delivery_provider_webhook_behavior;


-- Migration 037 backfills legacy anomaly markers and preserves the original event.
do $c353_legacy_backfill_assertions$
begin
  if not exists (
    select 1
    from public.delivery_provider_integrity_cases c
    join public.delivery_provider_integrity_conflict_evidence e using (conflict_id)
    where c.recipient_email = 'legacy-integrity-backfill@example.test'
      and c.anomaly_type = 'duplicate_event_id_conflict'
      and c.state = 'open'
      and e.event_id = 'evt_c353_legacy_backfill'
      and e.evidence_source = 'legacy_anomaly_backfill'
  ) then
    raise exception 'Migration 037 did not backfill the historical anomaly as recipient-scoped evidence.';
  end if;
  if not exists (
    select 1 from public.delivery_provider_events
    where event_id = 'evt_c353_legacy_backfill'
      and event_type = 'email.sent'
      and payload_fingerprint = repeat('a', 64)
  ) then
    raise exception 'Migration 037 changed the canonical historical provider event.';
  end if;
end;
$c353_legacy_backfill_assertions$;

-- Create a new conflict, resolve it as an authenticated administrator, then
-- prove that a distinct conflicting fingerprint reopens the same recipient case.
insert into auth.users (id, email, email_confirmed_at)
values (
  '00000000-0000-0000-0000-000000020008',
  'provider-integrity-admin@example.test',
  now()
);
insert into public.profiles (user_id, role, is_suspended)
values ('00000000-0000-0000-0000-000000020008', 'admin', false);

set role service_role;
do $c353_new_conflict$
begin
  if public.record_delivery_provider_lifecycle_event(
    'evt_c353_integrity_reopen', 'email.bounced', 'resend-c353-integrity-reopen',
    'integrity-reopen@example.test', '2027-03-03T09:00:00Z',
    'Permanent', null, null, repeat('1', 64)
  ) is not true then
    raise exception 'Provider integrity reopen fixture was not inserted.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_c353_integrity_reopen', 'email.complained', 'resend-c353-integrity-reopen',
    'integrity-reopen@example.test', '2027-03-03T09:01:00Z',
    null, null, null, repeat('2', 64)
  ) is not null then
    raise exception 'Conflicting duplicate provider event did not return the retryable NULL result.';
  end if;
end;
$c353_new_conflict$;
reset role;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000020008', true);
do $c353_admin_resolution$
declare
  v_case_id bigint;
  v_count bigint;
begin
  if not public.is_admin() then
    raise exception 'Synthetic administrator fixture was not recognized.';
  end if;

  select c.conflict_id into v_case_id
  from public.admin_list_delivery_provider_integrity_conflicts('all', 200) c
  where c.recipient_email = 'integrity-reopen@example.test'
    and c.anomaly_type = 'duplicate_event_id_conflict';

  if v_case_id is null then
    raise exception 'Recipient-scoped duplicate conflict case was not created.';
  end if;

  if public.admin_resolve_delivery_provider_integrity_conflict(
    v_case_id,
    'Reviewed conflicting provider event; retain the original bounce record.'
  ) is not true then
    raise exception 'Administrator could not resolve an open provider-integrity case.';
  end if;

  select count(*) into v_count
  from public.admin_list_delivery_provider_integrity_conflicts('resolved', 200)
  where conflict_id = v_case_id and state = 'resolved'
    and resolved_by = auth.uid()
    and resolution_note = 'Reviewed conflicting provider event; retain the original bounce record.';

  if v_count <> 1 then
    raise exception 'Admin conflict list did not expose the audited resolution.';
  end if;

  select count(*) into v_count
  from public.admin_list_delivery_provider_integrity_evidence(v_case_id, 100)
  where payload_fingerprint = repeat('2', 64);

  if v_count <> 1 then
    raise exception 'Admin evidence list did not expose the normalized conflicting event.';
  end if;

  select count(*) into v_count
  from public.admin_list_delivery_provider_integrity_history(v_case_id, 100)
  where action = 'resolved' and actor_id = auth.uid();

  if v_count <> 1 then
    raise exception 'Resolution history did not retain the administrator actor and action.';
  end if;
end;
$c353_admin_resolution$;
commit;
reset role;

set role service_role;
do $c353_reopen$
begin
  if public.record_delivery_provider_lifecycle_event(
    'evt_c353_integrity_reopen', 'email.failed', 'resend-c353-integrity-reopen',
    'integrity-reopen@example.test', '2027-03-03T09:02:00Z',
    null, 'unknown', null, repeat('3', 64)
  ) is not null then
    raise exception 'New conflicting provider evidence was not classified as a conflict.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_c353_integrity_reopen', 'email.failed', 'resend-c353-integrity-reopen',
    'integrity-reopen@example.test', '2027-03-03T09:02:00Z',
    null, 'unknown', null, repeat('3', 64)
  ) is not null then
    raise exception 'Conflicting provider payload replay did not remain an anomaly.';
  end if;
end;
$c353_reopen$;
reset role;

do $c353_reopen_assertions$
declare
  v_case_id bigint;
  v_count bigint;
begin
  select c.conflict_id into v_case_id
  from public.delivery_provider_integrity_cases c
  where c.recipient_email = 'integrity-reopen@example.test'
    and c.anomaly_type = 'duplicate_event_id_conflict'
    and c.state = 'open'
    and c.resolved_at is null
    and c.resolved_by is null
    and c.resolution_note is null;

  if v_case_id is null then
    raise exception 'New distinct provider evidence did not reopen the resolved case.';
  end if;

  select count(*) into v_count
  from public.delivery_provider_integrity_conflict_evidence e
  where e.conflict_id = v_case_id
    and e.payload_fingerprint in (repeat('2', 64), repeat('3', 64));

  if v_count <> 2 then
    raise exception 'Distinct conflicting fingerprints were not durably retained exactly once.';
  end if;

  select count(*) into v_count
  from public.delivery_provider_integrity_conflict_history h
  where h.conflict_id = v_case_id
    and h.action in ('resolved', 'reopened');

  if v_count <> 2 then
    raise exception 'Resolution/reopening history was overwritten or duplicated.';
  end if;

  if not exists (
    select 1 from public.delivery_provider_events
    where event_id = 'evt_c353_integrity_reopen'
      and event_type = 'email.bounced'
      and payload_fingerprint = repeat('1', 64)
      and recipient_email = 'integrity-reopen@example.test'
  ) then
    raise exception 'Conflicting provider event replaced the canonical event.';
  end if;

  if (select reason from public.delivery_provider_suppressions
      where recipient_email = 'integrity-reopen@example.test') is distinct from 'permanent_bounce' then
    raise exception 'Conflicting provider event weakened permanent-bounce protection.';
  end if;
end;
$c353_reopen_assertions$;

-- Authenticated non-admins cannot inspect or resolve private provider conflicts.
select set_config(
  'test.provider_integrity_case_id',
  (
    select conflict_id::text
    from public.delivery_provider_integrity_cases
    where recipient_email = 'integrity-reopen@example.test'
      and anomaly_type = 'duplicate_event_id_conflict'
  ),
  false
);
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000020005', true);
do $c354_non_admin$
declare
  v_case_id bigint := current_setting('test.provider_integrity_case_id')::bigint;
  v_denied boolean;
begin
  v_denied := false;
  begin
    perform * from public.admin_list_delivery_provider_integrity_conflicts('all', 100);
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'Non-admin authenticated member accessed provider-integrity cases.';
  end if;

  v_denied := false;
  begin
    perform * from public.admin_list_delivery_provider_integrity_evidence(v_case_id, 100);
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'Non-admin authenticated member accessed provider-integrity evidence.';
  end if;

  v_denied := false;
  begin
    perform * from public.admin_list_delivery_provider_integrity_history(v_case_id, 100);
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'Non-admin authenticated member accessed provider-integrity resolution history.';
  end if;

  v_denied := false;
  begin
    perform public.admin_resolve_delivery_provider_integrity_conflict(
      v_case_id,
      'Attempted unauthorized provider-integrity resolution.'
    );
  exception when sqlstate '42501' then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'Non-admin authenticated member resolved a provider-integrity case.';
  end if;
end;
$c354_non_admin$;
commit;
reset role;

do $c353_privacy_assertions$
begin
  if has_table_privilege('anon', 'public.delivery_provider_integrity_cases', 'SELECT')
    or has_table_privilege('authenticated', 'public.delivery_provider_integrity_cases', 'SELECT')
    or has_table_privilege('service_role', 'public.delivery_provider_integrity_cases', 'SELECT')
    or has_table_privilege('anon', 'public.delivery_provider_integrity_conflict_evidence', 'SELECT')
    or has_table_privilege('authenticated', 'public.delivery_provider_integrity_conflict_evidence', 'SELECT')
    or has_table_privilege('service_role', 'public.delivery_provider_integrity_conflict_evidence', 'SELECT')
    or has_table_privilege('anon', 'public.delivery_provider_integrity_conflict_history', 'SELECT')
    or has_table_privilege('authenticated', 'public.delivery_provider_integrity_conflict_history', 'SELECT')
    or has_table_privilege('service_role', 'public.delivery_provider_integrity_conflict_history', 'SELECT') then
    raise exception 'Provider-integrity case/evidence/history tables are directly readable.';
  end if;

  if not (select relrowsecurity from pg_class where oid='public.delivery_provider_integrity_cases'::regclass)
    or not (select relrowsecurity from pg_class where oid='public.delivery_provider_integrity_conflict_evidence'::regclass)
    or not (select relrowsecurity from pg_class where oid='public.delivery_provider_integrity_conflict_history'::regclass) then
    raise exception 'Provider-integrity case/evidence/history tables must retain RLS.';
  end if;

  if has_function_privilege('anon', 'public.admin_list_delivery_provider_integrity_conflicts(text,integer)', 'EXECUTE')
    or has_function_privilege('service_role', 'public.admin_list_delivery_provider_integrity_conflicts(text,integer)', 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.admin_list_delivery_provider_integrity_conflicts(text,integer)', 'EXECUTE')
    or has_function_privilege('anon', 'public.admin_list_delivery_provider_integrity_evidence(bigint,integer)', 'EXECUTE')
    or has_function_privilege('service_role', 'public.admin_list_delivery_provider_integrity_evidence(bigint,integer)', 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.admin_list_delivery_provider_integrity_evidence(bigint,integer)', 'EXECUTE')
    or has_function_privilege('anon', 'public.admin_list_delivery_provider_integrity_history(bigint,integer)', 'EXECUTE')
    or has_function_privilege('service_role', 'public.admin_list_delivery_provider_integrity_history(bigint,integer)', 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.admin_list_delivery_provider_integrity_history(bigint,integer)', 'EXECUTE')
    or has_function_privilege('anon', 'public.admin_resolve_delivery_provider_integrity_conflict(bigint,text)', 'EXECUTE')
    or has_function_privilege('service_role', 'public.admin_resolve_delivery_provider_integrity_conflict(bigint,text)', 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.admin_resolve_delivery_provider_integrity_conflict(bigint,text)', 'EXECUTE') then
    raise exception 'Provider-integrity admin RPC grants are not least-privilege.';
  end if;

  if has_function_privilege('anon', 'public._record_delivery_provider_integrity_conflict(text,text,text,text,text,text,text,timestamptz,text,text,text,text,text,timestamptz,text,text,text)', 'EXECUTE')
    or has_function_privilege('authenticated', 'public._record_delivery_provider_integrity_conflict(text,text,text,text,text,text,text,timestamptz,text,text,text,text,text,timestamptz,text,text,text)', 'EXECUTE')
    or has_function_privilege('service_role', 'public._record_delivery_provider_integrity_conflict(text,text,text,text,text,text,text,timestamptz,text,text,text,text,text,timestamptz,text,text,text)', 'EXECUTE')
    or has_function_privilege('service_role', 'public._record_delivery_provider_lifecycle_event_pre037_impl(text,text,text,text,timestamptz,text,text,text,text)', 'EXECUTE')
    or has_function_privilege('service_role', 'public._record_delivery_provider_suppression_event_pre037_impl(text,text,text,text,text,text,timestamptz,timestamptz,text)', 'EXECUTE') then
    raise exception 'Migration 037 private provider-integrity implementations became directly executable.';
  end if;
end;
$c353_privacy_assertions$;

select jsonb_build_object(
  'migration_037_legacy_anomaly_backfill','pass',
  'recipient_scoped_conflict_cases','pass',
  'append_only_conflict_evidence','pass',
  'administrator_resolution_audit','pass',
  'new_evidence_reopens_resolved_case','pass',
  'exact_conflict_replay_deduplicated','pass',
  'original_event_and_bounce_protection_preserved','pass',
  'non_admin_resolution_denied','pass',
  'provider_integrity_private_grants','pass',
  'conflicting_projection_preserves_original_event','pass'
) as delivery_provider_integrity_migration_037_behavior;
