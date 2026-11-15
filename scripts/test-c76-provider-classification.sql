\set ON_ERROR_STOP on
-- C76 ONLY. Run in a fresh synthetic postgres:16 database AFTER C73 test
-- migrations 019-030 and reviewed migrations 031,032,033. NO Production.
DO $acl$
DECLARE r record;
BEGIN
  IF has_function_privilege('service_role',
    'public.deedlight_record_resend_verified(text,text,text,text,timestamptz,text,text)','EXECUTE')
    OR NOT has_function_privilege('service_role',
      'public.deedlight_record_resend_delivery_v2(text,text,text,text,timestamptz,text,text,text)','EXECUTE')
    OR NOT has_function_privilege('service_role',
      'public.deedlight_record_resend_suppression_verified(text,text,text,text,text,text,timestamptz,text)','EXECUTE')
    OR has_function_privilege('anon',
      'public.deedlight_record_resend_suppression_verified(text,text,text,text,text,text,timestamptz,text)','EXECUTE')
    OR has_function_privilege('authenticated',
      'public.deedlight_record_resend_delivery_v2(text,text,text,text,timestamptz,text,text,text)','EXECUTE')
    OR has_table_privilege('service_role','deedlight_event_private.c76_uncertain_bounces','SELECT')
    OR has_table_privilege('anon','deedlight_event_private.c76_account_suppression_events','INSERT')
  THEN RAISE EXCEPTION 'C76 privileged entry-point or private-table ACL failure'; END IF;
  FOR r IN SELECT p.oid::regprocedure AS name,p.prosecdef,p.proconfig
    FROM pg_catalog.pg_proc p WHERE p.oid IN (
      'public.deedlight_record_resend_delivery_v2(text,text,text,text,timestamptz,text,text,text)'::regprocedure,
      'public.deedlight_record_resend_suppression_verified(text,text,text,text,text,text,timestamptz,text)'::regprocedure,
      'deedlight_event_private.c76_preserve_uncertain_bounce_hold()'::regprocedure)
  LOOP
    IF NOT r.prosecdef OR NOT ('search_path=pg_catalog,pg_temp'=ANY(r.proconfig) OR 'search_path=pg_catalog, pg_temp'=ANY(r.proconfig)) THEN
      RAISE EXCEPTION 'Unsafe SECURITY DEFINER configuration: %',r.name;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
    WHERE tgname='c76_preserve_uncertain_bounce_hold'
      AND tgrelid='public.delivery_recipient_state'::regclass AND tgenabled='A') THEN
    RAISE EXCEPTION 'Uncertain bounce ALWAYS trigger missing';
  END IF;
END $acl$;

INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
  ('70000000-0000-0000-0000-000000000076','c76-uncertain@example.test',now()),
  ('70000000-0000-0000-0000-000000000077','c76-provider@example.test',now()),
  ('70000000-0000-0000-0000-000000000078','c76-transient@example.test',now()),
  ('70000000-0000-0000-0000-000000000079','c76-permanent@example.test',now());
INSERT INTO public.profiles(user_id,is_suspended)
  SELECT id,false FROM auth.users WHERE id IN (
  '70000000-0000-0000-0000-000000000076','70000000-0000-0000-0000-000000000077',
  '70000000-0000-0000-0000-000000000078','70000000-0000-0000-0000-000000000079');
INSERT INTO public.daily_reminder_preferences(user_id,daily_enabled,reminder_time,timezone)
  SELECT id,true,'00:00','UTC' FROM auth.users WHERE id IN (
  '70000000-0000-0000-0000-000000000076','70000000-0000-0000-0000-000000000077',
  '70000000-0000-0000-0000-000000000078','70000000-0000-0000-0000-000000000079');
INSERT INTO public.newsletter_preferences(user_id,weekly_enabled,consented_at)
  SELECT id,true,now() FROM auth.users WHERE id IN (
  '70000000-0000-0000-0000-000000000076','70000000-0000-0000-0000-000000000077',
  '70000000-0000-0000-0000-000000000078','70000000-0000-0000-0000-000000000079');
INSERT INTO public.weekly_goodness_features(week_start)
  VALUES (timezone('UTC',now())::date - (extract(isodow from timezone('UTC',now()))::integer-1))
  ON CONFLICT DO NOTHING;
INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
  SELECT id,'daily_reminder','daily:'||(timezone('UTC',now())::date-1)::text,
    ((timezone('UTC',now())::date-1)+time '00:00') AT TIME ZONE 'UTC'
  FROM auth.users WHERE id IN ('70000000-0000-0000-0000-000000000076',
    '70000000-0000-0000-0000-000000000078','70000000-0000-0000-0000-000000000079');
INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
  SELECT id,'weekly_newsletter',
    'weekly:'||(timezone('UTC',now())::date-(extract(isodow from timezone('UTC',now()))::integer-1))::text,
    now()-interval '1 minute'
  FROM auth.users WHERE id IN ('70000000-0000-0000-0000-000000000076',
    '70000000-0000-0000-0000-000000000077');

-- Claim and finalize one synthetic provider message for each bounce class.
SET ROLE service_role;
DO $original_send$
DECLARE v_id uuid;v_token uuid;v_start timestamptz;v_user uuid;v_email text;v_result text;i integer;
BEGIN
  FOR v_user,v_email IN SELECT * FROM (VALUES
    ('70000000-0000-0000-0000-000000000076'::uuid,'c76-uncertain@example.test'),
    ('70000000-0000-0000-0000-000000000078'::uuid,'c76-transient@example.test'),
    ('70000000-0000-0000-0000-000000000079'::uuid,'c76-permanent@example.test')
  ) x(id,email) LOOP
    FOR i IN 1..10 LOOP
      EXIT WHEN EXISTS (SELECT 1 FROM public.delivery_ledger
        WHERE user_id=v_user AND kind='daily_reminder' AND state='claimed');
      PERFORM count(*) FROM public.claim_delivery_jobs('daily_reminder',now(),1000);
    END LOOP;
    SELECT id,claim_token INTO v_id,v_token FROM public.delivery_ledger
      WHERE user_id=v_user AND kind='daily_reminder';
    IF v_token IS NULL THEN RAISE EXCEPTION 'C76 synthetic daily claim missing'; END IF;
    v_start:=public.begin_delivery_transport_identity_bound(v_id,v_token,v_email);
    IF v_start IS NULL THEN RAISE EXCEPTION 'C76 synthetic first send denied'; END IF;
    IF public.mark_delivery_sent_identity_bound(v_id,v_token,
      'provider-c76-'||right(v_user::text,3)) IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'C76 provider message correlation failed';
    END IF;
  END LOOP;
END $original_send$;
RESET ROLE;

SET ROLE service_role;
DO $events$
DECLARE v_ts timestamptz:=clock_timestamp(); v_status text;
BEGIN
  v_status:=public.deedlight_record_resend_delivery_v2(
    'msg_c76_undetermined_0001','provider-c76-076','c76-uncertain@example.test',
    'email.bounced',v_ts,repeat('a',64),NULL,'Undetermined');
  IF v_status<>'recorded' THEN RAISE EXCEPTION 'Undetermined event not recorded: %',v_status; END IF;
  v_status:=public.deedlight_record_resend_delivery_v2(
    'msg_c76_transient_000001','provider-c76-078','c76-transient@example.test',
    'email.bounced',v_ts,repeat('b',64),NULL,'Transient');
  IF v_status<>'recorded' THEN RAISE EXCEPTION 'Transient event not recorded: %',v_status; END IF;
  v_status:=public.deedlight_record_resend_delivery_v2(
    'msg_c76_permanent_000001','provider-c76-079','c76-permanent@example.test',
    'email.bounced',v_ts,repeat('c',64),'permanent_bounce','Permanent');
  IF v_status<>'recorded' THEN RAISE EXCEPTION 'Permanent event not recorded: %',v_status; END IF;
  v_status:=public.deedlight_record_resend_suppression_verified(
    'msg_c76_account_add_00001','fe9751fd-9b5f-4aa8-9e04-50abbb6ad241',
    'c76-provider@example.test','manual',NULL,'suppression.added',v_ts,repeat('d',64));
  IF v_status<>'recorded' THEN RAISE EXCEPTION 'Account suppression not recorded: %',v_status; END IF;
  v_status:=public.deedlight_record_resend_suppression_verified(
    'msg_c76_account_add_00001','fe9751fd-9b5f-4aa8-9e04-50abbb6ad241',
    'c76-provider@example.test','manual',NULL,'suppression.added',v_ts,repeat('d',64));
  IF v_status<>'duplicate' THEN RAISE EXCEPTION 'Duplicate account event not deduplicated'; END IF;
  v_status:=public.deedlight_record_resend_suppression_verified(
    'msg_c76_account_remove01','fe9751fd-9b5f-4aa8-9e04-50abbb6ad241',
    'c76-provider@example.test','manual',NULL,'suppression.removed',v_ts,repeat('e',64));
  IF v_status<>'recorded' THEN RAISE EXCEPTION 'Removal audit not durable'; END IF;
  BEGIN
    PERFORM public.deedlight_record_resend_delivery_v2(
      'msg_c76_invalidclass0001','provider-c76-078','c76-transient@example.test',
      'email.bounced',v_ts,repeat('f',64),NULL,NULL);
    RAISE EXCEPTION 'Unclassified bounce bypassed new RPC' USING ERRCODE='ZX001';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
END $events$;
RESET ROLE;

-- Confirm the registry is one ID per event and classification is immutable.
DO $audit$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM deedlight_event_private.c76_bounce_classifications
    WHERE event_id='msg_c76_undetermined_0001' AND bounce_type='Undetermined')
    OR NOT EXISTS (SELECT 1 FROM deedlight_event_private.c76_bounce_classifications
    WHERE event_id='msg_c76_transient_000001' AND bounce_type='Transient')
    OR NOT EXISTS (SELECT 1 FROM deedlight_event_private.c76_bounce_classifications
    WHERE event_id='msg_c76_permanent_000001' AND bounce_type='Permanent')
    OR (SELECT count(*) FROM deedlight_event_private.provider_event_registry
      WHERE event_id='msg_c76_account_add_00001')<>1
    OR (SELECT count(*) FROM deedlight_event_private.c76_account_suppression_events
      WHERE event_id='msg_c76_account_add_00001')<>1
    OR NOT EXISTS (SELECT 1 FROM public.delivery_recipient_state s
      JOIN deedlight_private.recipient_fingerprints('c76-uncertain@example.test') f
        ON f.fingerprint=s.recipient_fingerprint
      WHERE s.pending_unmatched AND s.suppression_reason IS NULL AND NOT s.provider_suppressed)
    OR NOT EXISTS (SELECT 1 FROM public.delivery_recipient_state s
      JOIN deedlight_private.recipient_fingerprints('c76-provider@example.test') f
        ON f.fingerprint=s.recipient_fingerprint
      WHERE s.provider_suppressed AND s.pending_unmatched)
    OR EXISTS (SELECT 1 FROM public.delivery_recipient_state s
      JOIN deedlight_private.recipient_fingerprints('c76-transient@example.test') f
        ON f.fingerprint=s.recipient_fingerprint
      WHERE s.suppression_reason IS NOT NULL OR s.provider_suppressed OR s.pending_unmatched)
    OR NOT EXISTS (SELECT 1 FROM public.delivery_recipient_state s
      JOIN deedlight_private.recipient_fingerprints('c76-permanent@example.test') f
        ON f.fingerprint=s.recipient_fingerprint
      WHERE s.suppression_reason='permanent_bounce') THEN
    RAISE EXCEPTION 'C76 bounce classification or durable suppression invariant failed';
  END IF;
END $audit$;

-- An unrelated signed delivery success cannot erase the uncertain hold.
SET ROLE service_role;
DO $after_success$
DECLARE v_status text;
BEGIN
  v_status:=public.deedlight_record_resend_delivery_v2(
    'msg_c76_late_success0001','provider-c76-076','c76-uncertain@example.test',
    'email.delivered',clock_timestamp(),repeat('1',64),NULL,NULL);
  IF v_status<>'recorded' THEN RAISE EXCEPTION 'Late success not recorded'; END IF;
END $after_success$;
RESET ROLE;
DO $safety$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.delivery_recipient_state s
    JOIN deedlight_private.recipient_fingerprints('c76-uncertain@example.test') f
      ON f.fingerprint=s.recipient_fingerprint
    WHERE s.pending_unmatched AND s.suppression_reason IS NULL) THEN
    RAISE EXCEPTION 'Delivery success cleared Undetermined hold';
  END IF;
END $safety$;

-- Key rotation must not clear a prior suppression or temporary hold.
UPDATE deedlight_private.delivery_recipient_key_control SET mode='locked' WHERE singleton;
UPDATE deedlight_private.delivery_recipient_keyring SET phase='legacy' WHERE key_version=1;
INSERT INTO deedlight_private.delivery_recipient_keyring(key_version,secret_bytes,phase)
  VALUES (2,decode(repeat('d6',32),'hex'),'active');
UPDATE deedlight_private.delivery_recipient_key_control SET
  required_key_versions=ARRAY[1,2]::smallint[],mode='ready' WHERE singleton;
DO $rotation$
BEGIN
  IF (SELECT count(*) FROM deedlight_private.recipient_fingerprints('c76-provider@example.test'))<>2
    OR NOT EXISTS (SELECT 1 FROM deedlight_private.recipient_fingerprints('c76-provider@example.test') f
      JOIN public.delivery_recipient_state s ON s.recipient_fingerprint=f.fingerprint
      WHERE f.phase='legacy' AND s.provider_suppressed) THEN
    RAISE EXCEPTION 'Historical HMAC key lost account-level provider suppression';
  END IF;
END $rotation$;

-- Even a claimed Weekly job cannot use previous consent or the old key to send.
SET ROLE service_role;
DO $claim_weekly$
DECLARE i integer; n integer;
BEGIN
  FOR i IN 1..10 LOOP
    EXIT WHEN (SELECT count(*) FROM public.delivery_ledger
      WHERE user_id IN ('70000000-0000-0000-0000-000000000076',
        '70000000-0000-0000-0000-000000000077')
      AND kind='weekly_newsletter' AND state='claimed')=2;
    PERFORM count(*) FROM public.claim_delivery_jobs('weekly_newsletter',now(),1000);
  END LOOP;
  SELECT count(*) INTO n FROM public.delivery_ledger
    WHERE user_id IN ('70000000-0000-0000-0000-000000000076',
      '70000000-0000-0000-0000-000000000077') AND kind='weekly_newsletter' AND state='claimed';
  IF n<>2 THEN RAISE EXCEPTION 'Weekly scoped claim did not reach both held members: %',n; END IF;
END $claim_weekly$;
DO $cross_kind$
DECLARE v_id uuid;v_token uuid;v_email text;v_ts timestamptz;
BEGIN
  FOR v_id,v_token,v_email IN SELECT l.id,l.claim_token,u.email
    FROM public.delivery_ledger l JOIN auth.users u ON u.id=l.user_id
    WHERE l.user_id IN ('70000000-0000-0000-0000-000000000076',
      '70000000-0000-0000-0000-000000000077') AND l.kind='weekly_newsletter'
  LOOP
    BEGIN
      v_ts:=public.begin_delivery_transport_identity_bound(v_id,v_token,v_email);
      IF v_ts IS NOT NULL THEN
        RAISE EXCEPTION 'Weekly send escaped Daily provider hold' USING ERRCODE='ZX001';
      END IF;
    EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
    END;
  END LOOP;
END $cross_kind$;
RESET ROLE;

SELECT jsonb_build_object(
  'c76_postgres_security','pass',
  'undetermined_hold_survives_success','pass',
  'transient_nonpermanent','pass',
  'permanent_bounce','pass',
  'account_suppression_added','pass',
  'provider_removal_no_auto_release','pass',
  'legacy_fingerprint_rotation','pass',
  'cross_kind_final_send_denied','pass',
  'registered_event_identity','pass'
) AS c76_security_result;
