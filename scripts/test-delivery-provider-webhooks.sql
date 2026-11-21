\set ON_ERROR_STOP on
\ir test-delivery-consent-gates.sql
\ir ../supabase/migrations/202611190025_delivery_provider_webhooks.sql
\ir ../supabase/migrations/202611190026_delivery_provider_lifecycle.sql
\ir ../supabase/migrations/202611200027_delivery_provider_integrity.sql

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
  if public.record_delivery_provider_event(
    'msg_bounce_permanent_20001', 'email.bounced', 'resend-bounce-20001',
    'WEBHOOK-20001@EXAMPLE.TEST', 'Permanent'
  ) is not true then
    raise exception 'Permanent bounce event was not recorded.';
  end if;

  if public.record_delivery_provider_event(
    'msg_bounce_permanent_20001', 'email.bounced', 'resend-bounce-20001',
    'webhook-20001@example.test', 'Permanent'
  ) is not false then
    raise exception 'Exact duplicate provider event was not a successful no-op.';
  end if;

  if public.record_delivery_provider_event(
    'msg_bounce_transient_20002', 'email.bounced', 'resend-bounce-20002',
    'webhook-20002@example.test', 'Transient'
  ) is not true then
    raise exception 'Transient bounce event was not recorded.';
  end if;

  if public.record_delivery_provider_event(
    'msg_complaint_20003', 'email.complained', 'resend-complaint-20003',
    'webhook-20003@example.test', null
  ) is not true then
    raise exception 'Complaint event was not recorded.';
  end if;

  if public.record_delivery_provider_event(
    'msg_suppressed_20004', 'email.suppressed', 'resend-suppressed-20004',
    'webhook-20004@example.test', null
  ) is not true then
    raise exception 'Provider suppression event was not recorded.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_suppressed_previous_bounce', 'email.suppressed',
    'resend-suppressed-previous-bounce', 'lifecycle-previous-bounce@example.test',
    '2027-03-01T10:20:00Z', null, null, 'previous_bounce'
  ) is not true then
    raise exception 'previous_bounce suppression reason was not recorded.';
  end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_suppressed_previous_complaint', 'email.suppressed',
    'resend-suppressed-previous-complaint', 'lifecycle-previous-complaint@example.test',
    '2027-03-01T10:21:00Z', null, null, 'previous_complaint'
  ) is not true then
    raise exception 'previous_complaint suppression reason was not recorded.';
  end if;

  if public.record_delivery_provider_event(
    'msg_bounce_unknown_20005', 'email.bounced', 'resend-bounce-20005',
    'webhook-20005@example.test', 'Unknown'
  ) is not true then
    raise exception 'Unknown bounce event was not recorded.';
  end if;

  if public.record_delivery_provider_event(
    'msg_bounce_conflict_20006', 'email.bounced', 'resend-bounce-conflict-20006',
    'conflict-duplicate@example.test', 'Permanent'
  ) is not true then
    raise exception 'Conflicting duplicate fixture bounce was not recorded.';
  end if;

  if public.record_delivery_provider_event(
    'msg_bounce_conflict_20006', 'email.bounced', 'resend-bounce-conflict-20006',
    'conflict-duplicate@example.test', 'Permanent'
  ) is not false then
    raise exception 'Conflicting duplicate fixture exact replay was not a no-op.';
  end if;

  if public.record_delivery_provider_event(
    'msg_bounce_conflict_20006', 'email.complained', 'different-provider-id',
    'attacker@example.test', null
  ) is not null then
    raise exception 'Conflicting duplicate event ID was not recorded as an integrity anomaly.';
  end if;



  if public.record_delivery_provider_event(
    'msg_complaint_upgrade_20001', 'email.complained', 'resend-complaint-20001',
    'webhook-20001@example.test', null
  ) is not true then
    raise exception 'Complaint upgrade event was not recorded.';
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
end;
$$;
reset role;

do $$
begin
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
       'public.record_delivery_provider_event(text,text,text,text,text)','EXECUTE') then
    raise exception 'Provider event RPC grants regressed.';
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
    'lifecycle-order@example.test', '2027-03-01T10:00:00Z', null, null
  ) is not true then raise exception 'email.sent was not recorded.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_order_delayed', 'email.delivery_delayed', 'resend-order-20001',
    'lifecycle-order@example.test', '2027-03-01T10:05:00Z', null, null
  ) is not true then raise exception 'email.delivery_delayed was not recorded.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_order_delivered', 'email.delivered', 'resend-order-20001',
    'lifecycle-order@example.test', '2027-03-01T10:10:00Z', null, null
  ) is not true then raise exception 'email.delivered was not recorded.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_order_delayed_old', 'email.delivery_delayed', 'resend-order-20001',
    'lifecycle-order@example.test', '2027-03-01T10:04:00Z', null, null
  ) is not true then raise exception 'Out-of-order delayed event was not retained.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_failed_quota', 'email.failed', 'resend-failed-20002',
    'lifecycle-failed@example.test', '2027-03-01T10:11:00Z', null, 'quota_exceeded'
  ) is not true then raise exception 'email.failed was not recorded.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_precedence_bounce', 'email.bounced', 'resend-precedence-20003',
    'lifecycle-precedence@example.test', '2027-03-01T10:00:00Z', 'Permanent', null
  ) is not true then raise exception 'Lifecycle permanent bounce was not recorded.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_precedence_complaint', 'email.complained', 'resend-precedence-20003',
    'lifecycle-precedence@example.test', '2027-03-01T10:01:00Z', null, null
  ) is not null then raise exception 'Contradictory complaint after bounce was not flagged.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_precedence_bounce_late', 'email.bounced', 'resend-precedence-20003',
    'lifecycle-precedence@example.test', '2027-03-01T10:02:00Z', 'Permanent', null
  ) is not null then raise exception 'Contradictory late bounce was not flagged.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_provider_suppressed', 'email.suppressed', 'resend-lifecycle-suppressed-20004',
    'lifecycle-suppressed@example.test', '2027-03-01T10:12:00Z', null, null
  ) is not true then raise exception 'email.suppressed was not recorded.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_transient_bounce', 'email.bounced', 'resend-lifecycle-transient-20005',
    'lifecycle-transient@example.test', '2027-03-01T10:13:00Z', 'Transient', null
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
    'terminal-delivered-first@example.test', '2027-03-01T10:30:00Z', null, null
  ) is not true then raise exception 'Delivered-first terminal fixture failed.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_terminal_bounce_after', 'email.bounced', 'resend-terminal-delivered-first',
    'terminal-delivered-first@example.test', '2027-03-01T10:31:00Z', 'Permanent', null
  ) is not null then raise exception 'Delivered then bounced was not flagged.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_terminal_bounce_first', 'email.bounced', 'resend-terminal-bounced-first',
    'terminal-bounced-first@example.test', '2027-03-01T10:40:00Z', 'Permanent', null
  ) is not true then raise exception 'Bounced-first terminal fixture failed.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_terminal_delivered_after', 'email.delivered', 'resend-terminal-bounced-first',
    'terminal-bounced-first@example.test', '2027-03-01T10:41:00Z', null, null
  ) is not null then raise exception 'Bounced then delivered was not flagged.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_precedence_complaint_first', 'email.complained', 'resend-precedence-reverse',
    'lifecycle-precedence-reverse@example.test', '2027-03-01T10:50:00Z', null, null
  ) is not true then raise exception 'Complaint-first fixture failed.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_precedence_bounce_after', 'email.bounced', 'resend-precedence-reverse',
    'lifecycle-precedence-reverse@example.test', '2027-03-01T10:51:00Z', 'Permanent', null
  ) is not null then raise exception 'Complaint then bounce was not flagged.'; end if;

  if public.record_delivery_provider_lifecycle_event(
    'evt_order_delayed_old', 'email.delivery_delayed', 'resend-order-20001',
    'lifecycle-order@example.test', '2027-03-01T10:04:00Z', null, null
  ) is not false then raise exception 'Exact lifecycle replay was not an idempotent no-op.'; end if;

  begin
    perform public.record_delivery_provider_lifecycle_event(
      'evt_provider_id_wrong_recipient', 'email.sent', 'resend-order-20001',
      'different-recipient@example.test', '2027-03-01T10:15:00Z', null, null
    );
    raise exception 'Provider email ID was accepted for a different recipient.';
  exception when sqlstate '22023' then
    null;
  end;
end;
$lifecycle$;
reset role;

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
      where provider_email_id = 'resend-order-20001') <> 'email.delivered' then
    raise exception 'Out-of-order event regressed delivered lifecycle evidence.';
  end if;
  if not exists (
    select 1 from public.delivery_provider_lifecycle l
    join public.delivery_provider_events e using (event_id)
    where l.provider_email_id = 'resend-order-20001'
      and l.status = 'email.delivered'
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
      and status = 'email.failed'
      and failure_class = 'quota_exceeded'
  ) then
    raise exception 'Normalized email.failed classification was not persisted.';
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
