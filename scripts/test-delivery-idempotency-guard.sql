\set ON_ERROR_STOP on

-- Synthetic isolated fixtures for migrations 030 and 031.
insert into public.weekly_goodness_features (week_start)
values ('2027-03-01'),('2027-03-08'),('2027-03-15'),('2027-03-22'),
       ('2027-03-29'),('2027-04-05'),('2027-04-12'),('2027-04-19'),
       ('2027-05-10'),('2027-05-17'),('2027-05-24'),('2027-05-31'),('2027-06-07')
on conflict (week_start) do nothing;

do $idempotency_guard$
begin
  if to_regprocedure('public.authorize_delivery_idempotency_window(uuid,uuid,text)') is null
    or to_regprocedure('public.authorize_delivery_idempotency_window(uuid,uuid)') is not null
    or pg_get_function_result(to_regprocedure('public.authorize_delivery_idempotency_window(uuid,uuid,text)')) is distinct from 'text'
    or has_function_privilege('anon','public.authorize_delivery_idempotency_window(uuid,uuid,text)','EXECUTE')
    or has_function_privilege('authenticated','public.authorize_delivery_idempotency_window(uuid,uuid,text)','EXECUTE')
    or not has_function_privilege('service_role','public.authorize_delivery_idempotency_window(uuid,uuid,text)','EXECUTE')
    or to_regprocedure('public.retry_delivery_job(uuid,uuid,text)') is null
    or to_regprocedure('public.mark_delivery_sent(uuid,uuid,text)') is null then
    raise exception 'Migration 031 final authorization and migration 030 receipt RPCs are missing or have an unexpected return type.';
  end if;
end;
$idempotency_guard$;

insert into public.delivery_ledger (
  id,user_id,kind,delivery_key,state,scheduled_for,claim_token,claimed_at,
  claim_expires_at,attempt_count,last_attempt_at,transport_started_at
) values
('00000000-0000-0000-0000-00000000c901','00000000-0000-0000-0000-000000000002','weekly_newsletter','weekly:2027-03-01','claimed',clock_timestamp(),'00000000-0000-0000-0000-00000000d901',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),clock_timestamp()),
('00000000-0000-0000-0000-00000000c902','00000000-0000-0000-0000-000000000002','weekly_newsletter','weekly:2027-03-08','claimed',clock_timestamp(),'00000000-0000-0000-0000-00000000d902',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),clock_timestamp()),
('00000000-0000-0000-0000-00000000c903','00000000-0000-0000-0000-000000000002','weekly_newsletter','weekly:2027-03-15','claimed',clock_timestamp(),'00000000-0000-0000-0000-00000000d903',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),null),
('00000000-0000-0000-0000-00000000c904','00000000-0000-0000-0000-000000000002','weekly_newsletter','weekly:2027-03-22','claimed',clock_timestamp(),'00000000-0000-0000-0000-00000000d904',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),clock_timestamp()-interval '22 hours'),
('00000000-0000-0000-0000-00000000c905','00000000-0000-0000-0000-000000000002','weekly_newsletter','weekly:2027-03-29','claimed',clock_timestamp(),'00000000-0000-0000-0000-00000000d905',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),clock_timestamp()-interval '23 hours 1 minute'),
('00000000-0000-0000-0000-00000000c906','00000000-0000-0000-0000-000000000002','weekly_newsletter','weekly:2027-04-05','claimed',clock_timestamp(),'00000000-0000-0000-0000-00000000d906',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),clock_timestamp()-interval '24 hours 1 second'),
('00000000-0000-0000-0000-00000000c907','00000000-0000-0000-0000-000000000002','weekly_newsletter','weekly:2027-04-12','claimed',clock_timestamp(),'00000000-0000-0000-0000-00000000d907',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),clock_timestamp()-interval '23 hours'),
('00000000-0000-0000-0000-00000000c908','00000000-0000-0000-0000-000000000002','weekly_newsletter','weekly:2027-04-19','claimed',clock_timestamp(),'00000000-0000-0000-0000-00000000d908',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),null),
('00000000-0000-0000-0000-00000000c909','00000000-0000-0000-0000-000000000001','daily_reminder','daily:2027-05-10','claimed','2027-05-10T08:00:00Z','00000000-0000-0000-0000-00000000d909',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),clock_timestamp()),
('00000000-0000-0000-0000-00000000c910','00000000-0000-0000-0000-000000000002','weekly_newsletter','weekly:2027-05-10','claimed',clock_timestamp(),'00000000-0000-0000-0000-00000000d910',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),clock_timestamp()),
('00000000-0000-0000-0000-00000000c911','00000000-0000-0000-0000-000000000002','weekly_newsletter','weekly:2027-05-17','claimed',clock_timestamp(),'00000000-0000-0000-0000-00000000d911',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),clock_timestamp()),
('00000000-0000-0000-0000-00000000c912','00000000-0000-0000-0000-000000000002','weekly_newsletter','weekly:2027-05-24','claimed',clock_timestamp(),'00000000-0000-0000-0000-00000000d912',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),clock_timestamp()),
('00000000-0000-0000-0000-00000000c913','00000000-0000-0000-0000-000000000002','weekly_newsletter','weekly:2027-05-31','claimed',clock_timestamp(),'00000000-0000-0000-0000-00000000d913',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),clock_timestamp()),
('00000000-0000-0000-0000-00000000c914','00000000-0000-0000-0000-000000000002','weekly_newsletter','weekly:2027-06-07','claimed',clock_timestamp(),'00000000-0000-0000-0000-00000000d914',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),clock_timestamp());

set role service_role;
do $$
declare
  v_bad text;
  v_retry boolean;
  v_window text;
  v_next timestamptz;
  v_state text;
  v_error text;
begin
  if public.mark_delivery_sent('00000000-0000-0000-0000-00000000c901','00000000-0000-0000-0000-00000000d901','49a3999c-0ce1-4ea6-ab68-afcd6dc2e794') is not true then
    raise exception 'Valid Resend UUID receipt did not mark delivery sent.';
  end if;

  foreach v_bad in array array[
    null::text,'   ','provider-message-123',
    ' 49a3999c-0ce1-4ea6-ab68-afcd6dc2e794',
    '49a3999c-0ce1-4ea6-ab68-afcd6dc2e794 ',
    '49a3999c-0ce1-4ea6-ab68-afcd6dc2e794' || chr(10),
    'bad' || chr(9) || '49a3999c-0ce1-4ea6-ab68-afcd6dc2e794'
  ] loop
    begin
      perform public.mark_delivery_sent('00000000-0000-0000-0000-00000000c902','00000000-0000-0000-0000-00000000d902',v_bad);
      raise exception 'Malformed provider receipt was accepted.' using errcode='P0001';
    exception when sqlstate '22023' then null;
    end;
  end loop;
  if not exists (select 1 from public.delivery_ledger where id='00000000-0000-0000-0000-00000000c902'
    and state='claimed' and provider_result_id is null) then
    raise exception 'Rejected receipt attempts mutated the delivery.';
  end if;

  begin
    perform public.mark_delivery_sent('00000000-0000-0000-0000-00000000c903','00000000-0000-0000-0000-00000000d903','49a3999c-0ce1-4ea6-ab68-afcd6dc2e796');
    raise exception 'Sent transition accepted missing transport-start evidence.' using errcode='P0001';
  exception when sqlstate '42501' then null;
  end;

  -- Worker clock is two hours behind PostgreSQL; the legacy timestamp is ignored.
  if public.authorize_delivery_idempotency_window('00000000-0000-0000-0000-00000000c904','00000000-0000-0000-0000-00000000d904','two@example.test') is distinct from 'authorized' then
    raise exception 'Database rejected a retry inside the safe horizon.';
  end if;
  v_retry := public.retry_delivery_job('00000000-0000-0000-0000-00000000c904','00000000-0000-0000-0000-00000000d904',
    clock_timestamp()-interval '2 hours'+interval '5 minutes','worker_clock_two_hours_behind');
  select next_attempt_at into v_next from public.delivery_ledger where id='00000000-0000-0000-0000-00000000c904';
  if v_retry is not true or v_next <= clock_timestamp()+interval '4 minutes' or v_next > clock_timestamp()+interval '6 minutes' then
    raise exception 'Negative Worker clock skew influenced database retry timing.';
  end if;

  v_retry := public.retry_delivery_job('00000000-0000-0000-0000-00000000c905','00000000-0000-0000-0000-00000000d905',
    clock_timestamp()-interval '2 hours'+interval '5 minutes','worker_clock_two_hours_behind');
  if v_retry is not false or not exists (select 1 from public.delivery_ledger where id='00000000-0000-0000-0000-00000000c905'
    and state='failed' and error_code='provider_idempotency_window_expired') then
    raise exception 'Database did not fail closed when Worker skew exceeded the safe horizon.';
  end if;

  v_retry := public.retry_delivery_job('00000000-0000-0000-0000-00000000c906','00000000-0000-0000-0000-00000000d906','provider_retention_expired');
  if v_retry is not false or not exists (select 1 from public.delivery_ledger where id='00000000-0000-0000-0000-00000000c906'
    and state='failed' and error_code='provider_idempotency_window_expired') then
    raise exception 'Expired provider idempotency retention was not terminal.';
  end if;

  update public.delivery_ledger
  set transport_started_at=clock_timestamp()-interval '23 hours 5 minutes'
  where id='00000000-0000-0000-0000-00000000c907';
  v_window := public.authorize_delivery_idempotency_window(
    '00000000-0000-0000-0000-00000000c907',
    '00000000-0000-0000-0000-00000000d907',
    'two@example.test'
  );
  select state,error_code into v_state,v_error
  from public.delivery_ledger where id='00000000-0000-0000-0000-00000000c907';
  raise notice 'C226 pre-send gate: result %, state %, error %',v_window,v_state,v_error;
  if v_window is distinct from 'expired' or v_state is distinct from 'failed'
    or v_error is distinct from 'provider_idempotency_window_expired' then
    raise exception 'Pre-send provider idempotency horizon did not fail closed.';
  end if;

end;
$$;

-- Model the production RPC boundary: transport start, settings mutation, and
-- final provider authorization are separate PostgreSQL statements/transactions.
do $consent_transport_start$
begin
  if not exists (
    select 1 from public.newsletter_preferences
    where user_id='00000000-0000-0000-0000-000000000002'
      and weekly_enabled=true and consented_at is not null
  ) then
    raise exception 'Consent-revocation fixture did not start with active consent.';
  end if;

  if public.begin_delivery_transport(
    '00000000-0000-0000-0000-00000000c908',
    '00000000-0000-0000-0000-00000000d908',
    'two@example.test'
  ) is null then
    raise exception 'Consent-revocation fixture did not begin transport.';
  end if;

  if not exists (
    select 1 from public.delivery_ledger
    where id='00000000-0000-0000-0000-00000000c908'
      and transport_started_at is not null
  ) then
    raise exception 'Consent-revocation fixture did not persist transport-start evidence.';
  end if;
end;
$consent_transport_start$;

update public.newsletter_preferences
set weekly_enabled=false, consented_at=null
where user_id='00000000-0000-0000-0000-000000000002';

do $consent_revocation$
declare
  v_window text;
  v_state text;
  v_error text;
begin
  if not exists (
    select 1 from public.newsletter_preferences
    where user_id='00000000-0000-0000-0000-000000000002'
      and weekly_enabled=false and consented_at is null
  ) then
    raise exception 'Consent-revocation fixture did not persist the revoked preference.';
  end if;

  v_window := public.authorize_delivery_idempotency_window(
    '00000000-0000-0000-0000-00000000c908',
    '00000000-0000-0000-0000-00000000d908',
    'two@example.test'
  );
  select state,error_code into v_state,v_error
  from public.delivery_ledger
  where id='00000000-0000-0000-0000-00000000c908';
  raise notice 'C230 consent-revocation gate: result %, state %, error %',v_window,v_state,v_error;

  if v_window is distinct from 'cancelled' or v_state is distinct from 'cancelled'
    or v_error is distinct from 'authorization_revoked'
    or not exists (
      select 1 from public.delivery_ledger
      where id='00000000-0000-0000-0000-00000000c908'
        and claim_token is null and claim_expires_at is null
    ) then
    raise exception 'Final provider gate failed to recheck revoked newsletter consent.';
  end if;
end;
$consent_revocation$;
reset role;


-- C252: every mutable authorization record is rechecked at the final provider gate.
set role service_role;
do $c252_start$
begin
  if public.begin_delivery_transport(
    '00000000-0000-0000-0000-00000000c909',
    '00000000-0000-0000-0000-00000000d909',
    'one@example.test'
  ) is null then
    raise exception 'Daily final-authorization fixture did not begin transport.';
  end if;
end;
$c252_start$;
reset role;

update public.daily_reminder_preferences
set daily_enabled = false
where user_id = '00000000-0000-0000-0000-000000000001';

set role service_role;
do $c252_daily$
declare v_result text;
begin
  v_result := public.authorize_delivery_idempotency_window(
    '00000000-0000-0000-0000-00000000c909',
    '00000000-0000-0000-0000-00000000d909',
    'one@example.test'
  );
  if v_result is distinct from 'cancelled'
    or not exists (
      select 1 from public.delivery_ledger
      where id = '00000000-0000-0000-0000-00000000c909'
        and state = 'cancelled' and claim_token is null and claim_expires_at is null
    ) then
    raise exception 'Final provider gate did not cancel revoked Daily consent.';
  end if;
end;
$c252_daily$;
reset role;

update public.newsletter_preferences
set weekly_enabled = true, consented_at = clock_timestamp()
where user_id = '00000000-0000-0000-0000-000000000002';

set role service_role;
do $c252_weekly_start$
begin
  if public.begin_delivery_transport('00000000-0000-0000-0000-00000000c910',
      '00000000-0000-0000-0000-00000000d910','two@example.test') is null
    or public.begin_delivery_transport('00000000-0000-0000-0000-00000000c911',
      '00000000-0000-0000-0000-00000000d911','two@example.test') is null
    or public.begin_delivery_transport('00000000-0000-0000-0000-00000000c912',
      '00000000-0000-0000-0000-00000000d912','two@example.test') is null
    or public.begin_delivery_transport('00000000-0000-0000-0000-00000000c913',
      '00000000-0000-0000-0000-00000000d913','two@example.test') is null
    or public.begin_delivery_transport('00000000-0000-0000-0000-00000000c914',
      '00000000-0000-0000-0000-00000000d914','two@example.test') is null then
    raise exception 'Weekly final-authorization fixtures did not begin transport.';
  end if;
end;
$c252_weekly_start$;
reset role;

update public.profiles set is_suspended = true
where user_id = '00000000-0000-0000-0000-000000000002';
set role service_role;
do $c252_profile$
declare
  v_result text;
  v_suspended boolean;
  v_state text;
  v_error text;
begin
  select is_suspended into v_suspended
  from public.profiles
  where user_id = '00000000-0000-0000-0000-000000000002';
  v_result := public.authorize_delivery_idempotency_window(
    '00000000-0000-0000-0000-00000000c910',
    '00000000-0000-0000-0000-00000000d910',
    'two@example.test'
  );
  select state,error_code into v_state,v_error
  from public.delivery_ledger
  where id = '00000000-0000-0000-0000-00000000c910';
  raise notice 'C252 profile gate: suspended %, result %, state %, error %',v_suspended,v_result,v_state,v_error;
  if v_suspended is distinct from true
    or v_result is distinct from 'cancelled'
    or v_state is distinct from 'cancelled'
    or not exists (select 1 from public.delivery_ledger where id='00000000-0000-0000-0000-00000000c910'
      and claim_token is null and claim_expires_at is null) then
    raise exception 'Final provider gate did not cancel a suspended member.';
  end if;
end;
$c252_profile$;
reset role;
update public.profiles set is_suspended = false
where user_id = '00000000-0000-0000-0000-000000000002';

update auth.users set email_confirmed_at = null
where id = '00000000-0000-0000-0000-000000000002';
set role service_role;
do $c252_auth$
declare
  v_result text;
  v_confirmed timestamptz;
  v_state text;
  v_error text;
begin
  select email_confirmed_at into v_confirmed
  from auth.users
  where id = '00000000-0000-0000-0000-000000000002';
  v_result := public.authorize_delivery_idempotency_window(
    '00000000-0000-0000-0000-00000000c911',
    '00000000-0000-0000-0000-00000000d911',
    'two@example.test'
  );
  select state,error_code into v_state,v_error
  from public.delivery_ledger
  where id = '00000000-0000-0000-0000-00000000c911';
  raise notice 'C252 Auth gate: confirmed %, result %, state %, error %',v_confirmed,v_result,v_state,v_error;
  if v_confirmed is not null
    or v_result is distinct from 'cancelled'
    or v_state is distinct from 'cancelled'
    or not exists (select 1 from public.delivery_ledger where id='00000000-0000-0000-0000-00000000c911'
      and claim_token is null and claim_expires_at is null) then
    raise exception 'Final provider gate did not cancel an unconfirmed Auth identity.';
  end if;
end;
$c252_auth$;
reset role;
update auth.users set email_confirmed_at = '2026-09-01T00:00:00Z'
where id = '00000000-0000-0000-0000-000000000002';

delete from public.weekly_goodness_features where week_start = '2027-05-24';
set role service_role;
do $c252_feature$
begin
  if public.authorize_delivery_idempotency_window(
      '00000000-0000-0000-0000-00000000c912',
      '00000000-0000-0000-0000-00000000d912',
      'two@example.test') is distinct from 'cancelled'
    or not exists (select 1 from public.delivery_ledger where id='00000000-0000-0000-0000-00000000c912'
      and state='cancelled' and claim_token is null and claim_expires_at is null) then
    raise exception 'Final provider gate did not cancel a removed Weekly curation record.';
  end if;
end;
$c252_feature$;
reset role;
insert into public.weekly_goodness_features (week_start) values ('2027-05-24');

update auth.users set email = 'two-changed@example.test'
where id = '00000000-0000-0000-0000-000000000002';
set role service_role;
do $c252_identity$
declare v_result text;
begin
  v_result := public.authorize_delivery_idempotency_window(
    '00000000-0000-0000-0000-00000000c913',
    '00000000-0000-0000-0000-00000000d913',
    'two@example.test'
  );
  if v_result is distinct from 'cancelled'
    or not exists (select 1 from public.delivery_ledger where id='00000000-0000-0000-0000-00000000c913'
      and state='cancelled' and error_code='recipient_identity_changed'
      and claim_token is null and claim_expires_at is null) then
    raise exception 'Final provider gate accepted a changed recipient identity.';
  end if;
end;
$c252_identity$;
reset role;
update auth.users set email = 'two@example.test'
where id = '00000000-0000-0000-0000-000000000002';

set role service_role;
do $c252_suppression$
begin
  if public.record_delivery_provider_event(
    'evt_c252_suppression_after_transport',
    'email.complained',
    'resend-c252-suppression',
    'two@example.test',
    null
  ) is not true then
    raise exception 'C252 provider suppression fixture was not recorded.';
  end if;
  if public.authorize_delivery_idempotency_window(
      '00000000-0000-0000-0000-00000000c914',
      '00000000-0000-0000-0000-00000000d914',
      'two@example.test') is distinct from 'cancelled'
    or not exists (select 1 from public.delivery_ledger where id='00000000-0000-0000-0000-00000000c914'
      and state='cancelled' and claim_token is null and claim_expires_at is null) then
    raise exception 'Final provider gate did not recheck provider suppression.';
  end if;
end;
$c252_suppression$;
reset role;

select jsonb_build_object(
  'daily_consent_rechecked','pass',
  'weekly_consent_rechecked','pass',
  'profile_suspension_rechecked','pass',
  'auth_confirmation_rechecked','pass',
  'weekly_curation_rechecked','pass',
  'recipient_identity_bound','pass',
  'provider_suppression_rechecked','pass',
  'cancelled_claims_invalidated','pass'
) as c252_final_authorization_behavior;

select jsonb_build_object(
  'provider_receipt_validation','pass',
  'database_authoritative_idempotency_horizon','pass',
  'negative_worker_clock_skew','pass',
  'expired_provider_retention','pass',
  'consent_revocation_after_transport_start','pass'
) as delivery_idempotency_receipt_behavior;
