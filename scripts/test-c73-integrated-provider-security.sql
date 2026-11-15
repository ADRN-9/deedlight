\set ON_ERROR_STOP on
-- Synthetic PostgreSQL 16 only. Must not run against any external/Production database.
\ir test-delivery-consent-gates.sql
CREATE SCHEMA IF NOT EXISTS extensions;
ALTER EXTENSION pgcrypto SET SCHEMA extensions;
\ir ../supabase/migrations/202611130025_delivery_kind_claim_isolation.sql
\ir ../supabase/migrations/202611130026_resend_webhook_lifecycle.sql
\ir ../supabase/migrations/202611130027_recipient_suppression_serialization.sql
\ir ../supabase/migrations/202611130028_database_authoritative_recipient_binding.sql
\ir ../supabase/migrations/202611130029_global_provider_event_registry.sql
\ir ../supabase/migrations/202611130030_global_provider_security_cutover.sql

-- This fixture never uses real provider addresses/IDs/keys.
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
  ('70000000-0000-0000-0000-000000000001','c73-a@example.test',now()),
  ('70000000-0000-0000-0000-000000000002','c73-b@example.test',now()),
  ('70000000-0000-0000-0000-000000000003','c73-c@example.test',now()),
  ('70000000-0000-0000-0000-000000000004','c73-d@example.test',now());
INSERT INTO public.profiles(user_id,is_suspended)
  SELECT id,false FROM auth.users WHERE id::text LIKE '70000000-%';
INSERT INTO public.daily_reminder_preferences(user_id,daily_enabled,reminder_time,timezone)
  SELECT id,true,'00:00'::time,'UTC' FROM auth.users
  WHERE id IN ('70000000-0000-0000-0000-000000000001',
               '70000000-0000-0000-0000-000000000002',
               '70000000-0000-0000-0000-000000000003');
INSERT INTO public.newsletter_preferences(user_id,weekly_enabled,consented_at)
  VALUES ('70000000-0000-0000-0000-000000000004',true,now());
INSERT INTO public.weekly_goodness_features(week_start)
  SELECT timezone('UTC',now())::date
    - (extract(isodow from timezone('UTC',now()))::integer - 1)
  ON CONFLICT DO NOTHING;
INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
  SELECT id,'daily_reminder','daily:' || timezone('UTC',now())::date::text,
    (timezone('UTC',now())::date+time '00:00') at time zone 'UTC'
  FROM auth.users WHERE id IN ('70000000-0000-0000-0000-000000000001',
                               '70000000-0000-0000-0000-000000000002',
                               '70000000-0000-0000-0000-000000000003');
INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
  SELECT '70000000-0000-0000-0000-000000000004'::uuid,'weekly_newsletter',
    'weekly:' || (timezone('UTC',now())::date
      - (extract(isodow from timezone('UTC',now()))::integer - 1))::text,
    now() - interval '1 minute';

-- Default disabled registry / locked keyring block all outbound final sends.
SET ROLE service_role;
DO $negative$
DECLARE v_id uuid; v_token uuid;
BEGIN
  PERFORM public.claim_delivery_jobs('daily_reminder',now(),100);
  IF EXISTS (SELECT 1 FROM public.delivery_ledger WHERE user_id=
    '70000000-0000-0000-0000-000000000004' AND state='claimed') THEN
    RAISE EXCEPTION 'Daily claim consumed a Weekly job.';
  END IF;
  SELECT id,claim_token INTO v_id,v_token FROM public.delivery_ledger
    WHERE user_id='70000000-0000-0000-0000-000000000001';
  BEGIN
    PERFORM public.begin_delivery_transport_identity_bound(v_id,v_token,'c73-a@example.test');
    RAISE EXCEPTION 'Disabled recipient keyring authorized external transport';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.delivery_ledger WHERE id=v_id AND transport_started_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Failed final authorization changed transport state';
  END IF;
  BEGIN
    PERFORM public.claim_delivery_jobs('unknown-kind',now(),100);
    RAISE EXCEPTION 'Unsupported kind accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
END $negative$;
RESET ROLE;

-- Test-only key and explicit empty-history reconciliation. Not a Production runbook.
INSERT INTO deedlight_private.delivery_recipient_keyring(key_version,secret_bytes,phase)
VALUES (1,decode(repeat('b9',32),'hex'),'active');
UPDATE deedlight_private.delivery_recipient_key_control
SET required_key_versions=ARRAY[1]::smallint[],mode='ready' WHERE singleton;
UPDATE deedlight_event_private.registry_control
SET accepting_new_events=true,reconciled_at=clock_timestamp(),
    reconciled_evidence='C73-SYNTHETIC-EMPTY-HISTORY-EXPLICIT'
WHERE singleton;

SET ROLE service_role;
DO $claims$
DECLARE v_id uuid; v_token uuid; v_started timestamptz; v_started2 timestamptz;
BEGIN
  SELECT id,claim_token INTO v_id,v_token FROM public.delivery_ledger
    WHERE user_id='70000000-0000-0000-0000-000000000001';
  v_started:=public.begin_delivery_transport_identity_bound(v_id,v_token,'c73-a@example.test');
  v_started2:=public.begin_delivery_transport_identity_bound(v_id,v_token,'c73-a@example.test');
  IF v_started IS NULL OR v_started IS DISTINCT FROM v_started2 THEN
    RAISE EXCEPTION 'Authorized transport timestamp unstable';
  END IF;
  SELECT id,claim_token INTO v_id,v_token FROM public.delivery_ledger
    WHERE user_id='70000000-0000-0000-0000-000000000002';
  BEGIN
    PERFORM public.begin_delivery_transport_identity_bound(v_id,
      '00000000-0000-0000-0000-000000000000'::uuid,'c73-b@example.test');
    RAISE EXCEPTION 'Stale claim unexpectedly authorized transport';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
END $claims$;
RESET ROLE;
UPDATE public.delivery_ledger SET claim_expires_at=clock_timestamp()-interval '1 second'
  WHERE user_id='70000000-0000-0000-0000-000000000002';
UPDATE public.daily_reminder_preferences SET daily_enabled=false
  WHERE user_id='70000000-0000-0000-0000-000000000003';
SET ROLE service_role;
DO $denial$
DECLARE v_id uuid; v_token uuid;
BEGIN
  SELECT id,claim_token INTO v_id,v_token FROM public.delivery_ledger
    WHERE user_id='70000000-0000-0000-0000-000000000002';
  BEGIN
    PERFORM public.begin_delivery_transport_identity_bound(v_id,v_token,'c73-b@example.test');
    RAISE EXCEPTION 'Expired claim unexpectedly authorized';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  SELECT id,claim_token INTO v_id,v_token FROM public.delivery_ledger
    WHERE user_id='70000000-0000-0000-0000-000000000003';
  IF public.begin_delivery_transport_identity_bound(v_id,v_token,'c73-c@example.test') IS NOT NULL THEN
    RAISE EXCEPTION 'Revoked consent authorized transport';
  END IF;
  IF EXISTS (SELECT 1 FROM public.delivery_ledger WHERE id=v_id AND state<>'cancelled') THEN
    RAISE EXCEPTION 'Consent denial failed to cancel claim';
  END IF;
  IF has_function_privilege('service_role','public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)','EXECUTE')
    OR has_function_privilege('service_role','public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)','EXECUTE')
    OR has_function_privilege('service_role','public.begin_delivery_transport(uuid,uuid,text)','EXECUTE')
    OR has_function_privilege('service_role','public.deedlight_reserve_provider_event(text,text,bytea,text,text)','EXECUTE')
    OR has_function_privilege('anon','public.deedlight_record_resend_verified(text,text,text,text,timestamptz,text,text)','EXECUTE')
    OR has_function_privilege('authenticated','public.deedlight_record_resend_verified(text,text,text,text,timestamptz,text,text)','EXECUTE')
    OR NOT has_function_privilege('service_role','public.deedlight_record_resend_verified(text,text,text,text,timestamptz,text,text)','EXECUTE')
    OR to_regprocedure('public.claim_delivery_jobs(timestamptz,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'A legacy or browser-controlled webhook/claim bypass remains';
  END IF;
  BEGIN
    PERFORM public.record_resend_webhook_event_identity_bound(
      'msg_c73_stalelegacy1','provider-c73-001','c73-a@example.test',
      'email.delivered',now(),repeat('a',64),NULL);
    RAISE EXCEPTION 'Legacy definer wrapper remains usable';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  PERFORM public.claim_delivery_jobs('weekly_newsletter',now(),100);
  IF (SELECT state FROM public.delivery_ledger WHERE user_id=
    '70000000-0000-0000-0000-000000000004')<>'claimed' THEN
    RAISE EXCEPTION 'Weekly scoped claim was not taken';
  END IF;
END $denial$;
RESET ROLE;

-- Pending event -> mark sent -> same event processed exactly once.
SET ROLE service_role;
DO $webhooks$
DECLARE v_id uuid; v_token uuid; v_ts timestamptz:=clock_timestamp(); v_status text;
BEGIN
  SELECT id,claim_token INTO v_id,v_token FROM public.delivery_ledger
    WHERE user_id='70000000-0000-0000-0000-000000000001';
  v_status:=public.deedlight_record_resend_verified(
    'msg_c73_delivered_00001','provider-c73-001','c73-a@example.test',
    'email.delivered',v_ts,repeat('a',64),NULL);
  IF v_status<>'pending' THEN RAISE EXCEPTION 'Out-of-order event not durable: %',v_status; END IF;
  IF public.mark_delivery_sent_identity_bound(v_id,v_token,'provider-c73-001') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Recipient-bound mark sent rejected a valid reply';
  END IF;
  v_status:=public.deedlight_record_resend_verified(
    'msg_c73_delivered_00001','provider-c73-001','c73-a@example.test',
    'email.delivered',v_ts,repeat('a',64),NULL);
  IF v_status<>'duplicate' THEN RAISE EXCEPTION 'Exact replay was not idempotent'; END IF;
  v_status:=public.deedlight_record_resend_verified(
    'msg_c73_complained_00002','provider-c73-001','c73-a@example.test',
    'email.complained',v_ts,repeat('b',64),'spam_complaint');
  IF v_status<>'recorded' THEN RAISE EXCEPTION 'Complaint was not durably processed'; END IF;
  v_status:=public.deedlight_record_resend_verified(
    'msg_c73_mismatch_000003','provider-c73-001','c73-d@example.test',
    'email.delivered',v_ts,repeat('c',64),NULL);
  IF v_status<>'quarantined' THEN
    RAISE EXCEPTION 'Conflicting provider-recipient association not quarantined';
  END IF;
  v_status:=public.deedlight_record_resend_verified(
      'msg_c73_delivered_00001','provider-c73-001','c73-a@example.test',
      'email.delivered',v_ts,repeat('f',64),NULL);
  IF v_status<>'quarantined' THEN
    RAISE EXCEPTION 'Conflicting payload reused an event identity without quarantine';
  END IF;
END $webhooks$;
RESET ROLE;

DO $verify$
BEGIN
  IF (SELECT state FROM deedlight_event_private.provider_event_registry
      WHERE event_id='msg_c73_delivered_00001')<>'identity_conflict'
    OR (SELECT state FROM deedlight_event_private.provider_event_registry
      WHERE event_id='msg_c73_complained_00002')<>'processed'
    OR (SELECT state FROM deedlight_event_private.provider_event_registry
      WHERE event_id='msg_c73_mismatch_000003')<>'identity_conflict'
    OR NOT EXISTS (SELECT 1 FROM public.delivery_recipient_state s
      JOIN public.delivery_provider_submissions p ON p.recipient_fingerprint=s.recipient_fingerprint
      WHERE p.provider_email_id='provider-c73-001' AND s.suppression_reason='spam_complaint')
    OR NOT EXISTS (SELECT 1 FROM public.delivery_provider_events
      WHERE svix_event_id='msg_c73_delivered_00001')
    OR EXISTS (SELECT 1 FROM public.delivery_provider_pending_events
      WHERE svix_event_id='msg_c73_delivered_00001') THEN
    RAISE EXCEPTION 'Global registry/pending promotion/complaint/conflict invariants failed';
  END IF;
END $verify$;

-- Service cannot directly write a legacy acceptance row; even the owner
-- cannot create a row without an authoritative event reservation.
DO $triggers$
BEGIN
  BEGIN
    INSERT INTO public.delivery_provider_pending_events
      (svix_event_id,provider_email_id,recipient_fingerprint,event_type,event_at,payload_sha256)
    VALUES ('msg_c73_direct_0000001','fake',repeat('b',64),'email.delivered',now(),repeat('c',64));
    RAISE EXCEPTION 'Legacy pending event accepted without registry';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  BEGIN
    TRUNCATE public.delivery_provider_events;
    RAISE EXCEPTION 'Legacy processed event truncate bypassed veto';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
END $triggers$;

SELECT jsonb_build_object(
  'c73_postgresql16_integrated_provider_security','pass',
  'claim_kind_isolation','pass',
  'expired_stale_claims','pass',
  'revoked_consent','pass',
  'global_event_id','pass',
  'pending_promotion','pass',
  'complaint_suppression','pass',
  'identity_conflict_quarantine','pass',
  'legacy_bypass_denial','pass',
  'outbound_enabled','false'
) AS c73_integrated_security_result;
