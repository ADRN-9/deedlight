\set ON_ERROR_STOP on
-- Run ONLY after scripts/test-c73-integrated-provider-security.sql in a fresh
-- synthetic PostgreSQL 16 database. NO Production target.
DO $c74_catalog$
DECLARE r record; n integer;
BEGIN
  FOR r IN SELECT p.oid::regprocedure::text AS name,
     p.prosecdef, p.proconfig
     FROM pg_catalog.pg_proc p
     WHERE p.oid IN (
       'public.deedlight_record_resend_verified(text,text,text,text,timestamptz,text,text)'::regprocedure,
       'public.begin_delivery_transport_identity_bound(uuid,uuid,text)'::regprocedure,
       'public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)'::regprocedure
     )
  LOOP
    IF NOT r.prosecdef OR NOT ('search_path=pg_catalog, pg_temp'=ANY(r.proconfig)
      OR 'search_path=pg_catalog,pg_temp'=ANY(r.proconfig)) THEN
      RAISE EXCEPTION 'Security definer without safe search_path: %', r.name;
    END IF;
  END LOOP;
  SELECT count(*) INTO n
  FROM pg_catalog.pg_trigger t
  WHERE t.tgname='c73_registry_guard' AND t.tgenabled='A'
    AND t.tgrelid IN (
      'public.delivery_provider_events'::regclass,
      'public.delivery_provider_pending_events'::regclass,
      'public.delivery_provider_identity_conflicts'::regclass
    );
  IF n<>3 THEN RAISE EXCEPTION 'Expected 3 ALWAYS registry triggers, got %',n; END IF;
  IF has_function_privilege('anon','public.deedlight_record_resend_verified(text,text,text,text,timestamptz,text,text)','EXECUTE')
    OR has_function_privilege('authenticated','public.deedlight_record_resend_verified(text,text,text,text,timestamptz,text,text)','EXECUTE')
    OR has_function_privilege('service_role','public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)','EXECUTE')
    OR has_table_privilege('authenticated','public.delivery_provider_pending_events','INSERT')
    OR has_table_privilege('anon','deedlight_event_private.provider_event_registry','SELECT') THEN
    RAISE EXCEPTION 'Legacy privilege or browser event registry exposure';
  END IF;
END $c74_catalog$;

-- A processed event must not coexist in the PENDING lifecycle table.
-- This test is deliberately adversarial; passing requires a 42501 denial.
DO $c74_cross_table$
BEGIN
  BEGIN
    INSERT INTO public.delivery_provider_pending_events
      (svix_event_id, provider_email_id, recipient_fingerprint,
       event_type, event_at, payload_sha256, suppression_reason)
    SELECT svix_event_id, provider_email_id, recipient_fingerprint,
       event_type, event_at, payload_sha256, suppression_reason
    FROM public.delivery_provider_events
    WHERE svix_event_id='msg_c73_complained_00002';
    IF FOUND THEN
      RAISE EXCEPTION 'C74 DEFECT: processed event ID accepted into pending table';
    END IF;
    RAISE EXCEPTION 'Processed fixture missing';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END $c74_cross_table$;

-- A permanent provider-level suppression can arrive BEFORE the provider
-- message-to-ledger association. It must remain in force after promotion.
INSERT INTO auth.users(id,email,email_confirmed_at)
  VALUES ('70000000-0000-0000-0000-000000000005','c74-pending@example.test',now());
INSERT INTO public.profiles(user_id,is_suspended)
  VALUES ('70000000-0000-0000-0000-000000000005',false);
INSERT INTO public.daily_reminder_preferences(user_id,daily_enabled,reminder_time,timezone)
  VALUES ('70000000-0000-0000-0000-000000000005',true,'00:00','UTC');
INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
  VALUES ('70000000-0000-0000-0000-000000000005','daily_reminder',
    'daily:' || (timezone('UTC',now())::date - 1)::text,
    ((timezone('UTC',now())::date - 1) + time '00:00') AT TIME ZONE 'UTC');
SET ROLE service_role;
DO $c74_promotion$
DECLARE j uuid; t uuid; result text; stamp timestamptz:=clock_timestamp();
BEGIN
  PERFORM public.claim_delivery_jobs('daily_reminder',now(),100);
  SELECT id,claim_token INTO j,t FROM public.delivery_ledger
   WHERE user_id='70000000-0000-0000-0000-000000000005';
  IF j IS NULL OR t IS NULL OR public.begin_delivery_transport_identity_bound(
      j,t,'c74-pending@example.test') IS NULL THEN
    RAISE EXCEPTION 'Synthetic pre-send authorization missing';
  END IF;
  result:=public.deedlight_record_resend_verified(
    'msg_c74_presuppression00001','provider-c74-pending-001',
    'c74-pending@example.test','email.suppressed',stamp,repeat('d',64),NULL);
  IF result<>'pending' THEN RAISE EXCEPTION 'Unassociated suppression not held: %',result; END IF;
  IF public.mark_delivery_sent_identity_bound(j,t,'provider-c74-pending-001') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Provider correlation/pending promotion failed';
  END IF;
END $c74_promotion$;
RESET ROLE;
DO $c74_check_promotion$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.delivery_provider_events
      WHERE svix_event_id='msg_c74_presuppression00001'
    ) OR EXISTS(
      SELECT 1 FROM public.delivery_provider_pending_events
      WHERE svix_event_id='msg_c74_presuppression00001'
    ) OR NOT EXISTS(
      SELECT 1 FROM public.delivery_provider_submissions sub
      JOIN public.delivery_recipient_state s USING(recipient_fingerprint)
      WHERE sub.provider_email_id='provider-c74-pending-001'
        AND s.provider_suppressed=true AND s.pending_unmatched=true
    ) THEN
    RAISE EXCEPTION 'Pending provider suppression did not survive promotion';
  END IF;
END $c74_check_promotion$;

INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
  VALUES ('70000000-0000-0000-0000-000000000005','daily_reminder',
    'daily:' || timezone('UTC',now())::date::text,
    (timezone('UTC',now())::date + time '00:00') AT TIME ZONE 'UTC');
SET ROLE service_role;
DO $c74_deny_retry$
DECLARE j uuid;t uuid;stamp timestamptz;
BEGIN
  PERFORM public.claim_delivery_jobs('daily_reminder',now(),100);
  SELECT id,claim_token INTO j,t FROM public.delivery_ledger
   WHERE user_id='70000000-0000-0000-0000-000000000005'
     AND delivery_key='daily:' || timezone('UTC',now())::date::text;
  BEGIN
    stamp:=public.begin_delivery_transport_identity_bound(j,t,'c74-pending@example.test');
    IF stamp IS NOT NULL THEN RAISE EXCEPTION 'Suppressed recipient authorized next logical send'; END IF;
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.delivery_ledger WHERE id=j AND transport_started_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Suppression denial changed transport_started_at';
  END IF;
END $c74_deny_retry$;
RESET ROLE;

-- Explicit TEST-ONLY key rotation, retaining the original key as legacy.
UPDATE deedlight_private.delivery_recipient_key_control SET mode='locked' WHERE singleton;
UPDATE deedlight_private.delivery_recipient_keyring SET phase='legacy' WHERE key_version=1;
INSERT INTO deedlight_private.delivery_recipient_keyring(key_version,secret_bytes,phase)
VALUES(2,decode(repeat('cb',32),'hex'),'active');
UPDATE deedlight_private.delivery_recipient_key_control
  SET required_key_versions=ARRAY[1,2]::smallint[],mode='ready' WHERE singleton;
INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
  VALUES ('70000000-0000-0000-0000-000000000005','daily_reminder',
    'daily:' || (timezone('UTC',now())::date - 2)::text,
    ((timezone('UTC',now())::date - 2) + time '00:00') AT TIME ZONE 'UTC');
DO $c74_rotation_catalog$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM deedlight_private.recipient_fingerprints('c74-pending@EXAMPLE.TEST');
  IF n<>2 THEN RAISE EXCEPTION 'Expected both historical and active fingerprints'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM deedlight_private.recipient_fingerprints('c74-pending@example.test') f
    JOIN public.delivery_recipient_state s ON s.recipient_fingerprint=f.fingerprint
    WHERE f.phase='legacy' AND s.provider_suppressed
  ) THEN RAISE EXCEPTION 'Prior key fingerprint lost suppression'; END IF;
END $c74_rotation_catalog$;
SET ROLE service_role;
DO $c74_rotation$
DECLARE j uuid;t uuid;stamp timestamptz;
BEGIN
  PERFORM public.claim_delivery_jobs('daily_reminder',now(),100);
  SELECT id,claim_token INTO j,t FROM public.delivery_ledger
    WHERE delivery_key='daily:' || (timezone('UTC',now())::date - 2)::text AND
      user_id='70000000-0000-0000-0000-000000000005';
  BEGIN
    stamp:=public.begin_delivery_transport_identity_bound(j,t,'c74-pending@example.test');
    IF stamp IS NOT NULL THEN RAISE EXCEPTION 'Key rotation erased provider suppression'; END IF;
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  IF EXISTS(SELECT 1 FROM public.delivery_ledger WHERE id=j AND transport_started_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Rotated suppressed send crossed final authorization';
  END IF;
END $c74_rotation$;
RESET ROLE;

SELECT jsonb_build_object(
 'postgres_16_catalog_acl','pass',
 'processed_pending_global_uniqueness','pass',
 'provider_suppressed_before_send_correlation','pass',
 'retry_suppression_survives','pass',
 'rotation_legacy_fingerprint_suppression','pass',
 'outbound_provider_calls',0
) AS c74_adversarial_security_result;
