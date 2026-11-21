\set ON_ERROR_STOP on

-- Synthetic isolated fixtures for migration 030.
insert into public.weekly_goodness_features (week_start)
values ('2027-03-01'),('2027-03-08'),('2027-03-15'),('2027-03-22'),
       ('2027-03-29'),('2027-04-05'),('2027-04-12'),('2027-04-19')
on conflict (week_start) do nothing;

do $idempotency_guard$
begin
  if to_regprocedure('public.authorize_delivery_idempotency_window(uuid,uuid)') is null
    or pg_get_function_result(to_regprocedure('public.authorize_delivery_idempotency_window(uuid,uuid)')) is distinct from 'text'
    or to_regprocedure('public.retry_delivery_job(uuid,uuid,text)') is null
    or to_regprocedure('public.mark_delivery_sent(uuid,uuid,text)') is null then
    raise exception 'Migration 030 idempotency and receipt RPCs are missing or have an unexpected return type.';
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
('00000000-0000-0000-0000-00000000c908','00000000-0000-0000-0000-000000000002','weekly_newsletter','weekly:2027-04-19','claimed',clock_timestamp(),'00000000-0000-0000-0000-00000000d908',clock_timestamp(),clock_timestamp()+interval '10 minutes',1,clock_timestamp(),null);

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
  if public.authorize_delivery_idempotency_window('00000000-0000-0000-0000-00000000c904','00000000-0000-0000-0000-00000000d904') is distinct from 'authorized' then
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
    '00000000-0000-0000-0000-00000000d907'
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
    '00000000-0000-0000-0000-00000000d908'
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

select jsonb_build_object(
  'provider_receipt_validation','pass',
  'database_authoritative_idempotency_horizon','pass',
  'negative_worker_clock_skew','pass',
  'expired_provider_retention','pass',
  'consent_revocation_after_transport_start','pass'
) as delivery_idempotency_receipt_behavior;
