\set ON_ERROR_STOP on
\ir test-delivery-consent-gates.sql
\ir ../supabase/migrations/202611190025_delivery_provider_webhooks.sql

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

  if public.record_delivery_provider_event(
    'msg_bounce_unknown_20005', 'email.bounced', 'resend-bounce-20005',
    'webhook-20005@example.test', 'Unknown'
  ) is not true then
    raise exception 'Unknown bounce event was not recorded.';
  end if;

  if public.record_delivery_provider_event(
    'msg_bounce_permanent_20001', 'email.complained', 'different-provider-id',
    'attacker@example.test', null
  ) is not false then
    raise exception 'Duplicate provider event ID was processed twice.';
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
    or has_table_privilege('service_role','public.delivery_provider_suppressions','SELECT') then
    raise exception 'Provider webhook tables are directly readable.';
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
    or not (select relrowsecurity from pg_class where oid='public.delivery_provider_suppressions'::regclass) then
    raise exception 'Provider webhook tables must retain RLS.';
  end if;
end;
$$;

select jsonb_build_object(
  'provider_event_dedupe','pass',
  'permanent_bounce_suppression','pass',
  'transient_bounce_not_suppressed','pass',
  'complaint_and_provider_suppression','pass',
  'unknown_bounce_fail_closed','pass',
  'daily_weekly_enqueue_exclusion','pass',
  'final_transport_gate','pass',
  'private_table_and_rpc_grants','pass'
) as delivery_provider_webhook_behavior;
