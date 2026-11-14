\set ON_ERROR_STOP on
-- C77: disposable PostgreSQL 16 only; synthetic addresses; run after exact C73-76 migrations.
-- Provider submission is intentionally unresolved when events arrive.
DO $preflight$
BEGIN
 IF to_regprocedure('public.deedlight_record_resend_delivery_v2(text,text,text,text,timestamptz,text,text,text)') IS NULL
 OR to_regprocedure('public.deedlight_record_resend_suppression_verified(text,text,text,text,text,text,timestamptz,text)') IS NULL
 OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
   WHERE tgrelid='public.delivery_recipient_state'::regclass
     AND tgname='c76_preserve_uncertain_bounce_hold' AND tgenabled='A')
 THEN RAISE EXCEPTION 'C77 requires exact post-033 security schema'; END IF;
END $preflight$;

INSERT INTO auth.users(id,email,email_confirmed_at)
 SELECT ('70000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
   'c77-'||i::text||'@example.test',now()
 FROM generate_series(90,95) AS i;
INSERT INTO public.profiles(user_id,is_suspended)
 SELECT id,false FROM auth.users WHERE email LIKE 'c77-%@example.test';
INSERT INTO public.daily_reminder_preferences(user_id,daily_enabled,reminder_time,timezone)
 SELECT id,true,time '00:00','UTC' FROM auth.users WHERE email LIKE 'c77-%@example.test';
INSERT INTO public.newsletter_preferences(user_id,weekly_enabled,consented_at)
 SELECT id,true,now() FROM auth.users WHERE email LIKE 'c77-%@example.test';
INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
 SELECT id,'daily_reminder','daily:'||(timezone('UTC',now())::date-3)::text,
   ((timezone('UTC',now())::date-3)+time '00:00') AT TIME ZONE 'UTC'
 FROM auth.users WHERE email LIKE 'c77-%@example.test';

SET ROLE service_role;
DO $begin_transport$
DECLARE r record; j uuid; token uuid; authorized timestamptz; i integer;
BEGIN
 FOR i IN 1..12 LOOP
   EXIT WHEN (SELECT count(*) FROM public.delivery_ledger
       WHERE user_id IN (SELECT id FROM auth.users WHERE email LIKE 'c77-%@example.test')
         AND kind='daily_reminder' AND state='claimed')=6;
   PERFORM count(*) FROM public.claim_delivery_jobs('daily_reminder',now(),1000);
 END LOOP;
 FOR r IN SELECT u.id, u.email,l.id job_id,l.claim_token
    FROM auth.users u JOIN public.delivery_ledger l ON l.user_id=u.id
    WHERE u.email LIKE 'c77-%@example.test' AND l.kind='daily_reminder' LOOP
   IF r.claim_token IS NULL THEN RAISE EXCEPTION 'Unclaimed synthetic job: %',r.email; END IF;
   authorized:=public.begin_delivery_transport_identity_bound(r.job_id,r.claim_token,r.email);
   IF authorized IS NULL THEN RAISE EXCEPTION 'Initial transport authorization missing: %',r.email; END IF;
 END LOOP;
END $begin_transport$;

DO $pending_events$
DECLARE ts timestamptz:=clock_timestamp(); state text;
BEGIN
 state:=public.deedlight_record_resend_delivery_v2(
   'msg_c77_pending_permanent_0001','provider-c77-090','c77-90@example.test',
   'email.bounced',ts,repeat('a',64),'permanent_bounce','Permanent');
 IF state<>'pending' THEN RAISE EXCEPTION 'Permanent event was not pending: %',state; END IF;
 state:=public.deedlight_record_resend_delivery_v2(
   'msg_c77_pending_complaint_0002','provider-c77-091','c77-91@example.test',
   'email.complained',ts,repeat('b',64),'spam_complaint',NULL);
 IF state<>'pending' THEN RAISE EXCEPTION 'Complaint event was not pending: %',state; END IF;
 state:=public.deedlight_record_resend_delivery_v2(
   'msg_c77_pending_unknown_0003','provider-c77-092','c77-92@example.test',
   'email.bounced',ts,repeat('c',64),NULL,'Undetermined');
 IF state<>'pending' THEN RAISE EXCEPTION 'Undetermined event was not pending: %',state; END IF;
 state:=public.deedlight_record_resend_delivery_v2(
   'msg_c77_pending_provider_0004','provider-c77-093','c77-93@example.test',
   'email.suppressed',ts,repeat('d',64),NULL,NULL);
 IF state<>'pending' THEN RAISE EXCEPTION 'Provider suppression was not pending: %',state; END IF;
 state:=public.deedlight_record_resend_suppression_verified(
   'msg_c77_removed_ahead_0005','f59508fe-2cf3-4e12-9989-529c712e7777',
   'c77-91@example.test','manual',NULL,'suppression.removed',ts,repeat('e',64));
 IF state<>'recorded' THEN RAISE EXCEPTION 'Early removal not audited: %',state; END IF;
END $pending_events$;
RESET ROLE;
DO $pending_assert$
BEGIN
 IF (SELECT count(*) FROM public.delivery_provider_pending_events
      WHERE svix_event_id LIKE 'msg_c77_pending_%')<>4
 THEN RAISE EXCEPTION 'Pending projections missing'; END IF;
END $pending_assert$;
SET ROLE service_role;

DO $promote$
DECLARE r record; state text;
BEGIN
 FOR r IN SELECT u.email,l.id job_id,l.claim_token,
        'provider-c77-'||split_part(u.email,'-',2)::text AS provider_id
   FROM auth.users u JOIN public.delivery_ledger l ON l.user_id=u.id
   WHERE u.email LIKE 'c77-%@example.test' AND l.kind='daily_reminder'
   ORDER BY u.email LOOP
   IF public.mark_delivery_sent_identity_bound(
       r.job_id,r.claim_token,
       'provider-c77-'||lpad(split_part(split_part(r.email,'@',1),'-',2),3,'0')) IS DISTINCT FROM true
   THEN RAISE EXCEPTION 'Provider association failed after early event: %',r.email; END IF;
 END LOOP;
END $promote$;
RESET ROLE;

DO $assert_promoted$
DECLARE r record; expected text;
BEGIN
 IF EXISTS (SELECT 1 FROM public.delivery_provider_pending_events
    WHERE svix_event_id LIKE 'msg_c77_pending_%')
 THEN RAISE EXCEPTION 'Pending provider event failed to promote'; END IF;
 IF (SELECT count(*) FROM deedlight_event_private.provider_event_registry
    WHERE event_id LIKE 'msg_c77_pending_%' AND state='processed')<>4
 THEN RAISE EXCEPTION 'Registry identity not promoted exactly once'; END IF;
 IF EXISTS (SELECT 1 FROM deedlight_event_private.provider_event_registry
    WHERE event_id LIKE 'msg_c77_pending_%'
    GROUP BY provider,event_id HAVING count(*)<>1)
 THEN RAISE EXCEPTION 'Duplicate registry identity'; END IF;
 FOR r IN SELECT u.email,s.suppression_reason,s.provider_suppressed,s.pending_unmatched
   FROM auth.users u JOIN deedlight_private.recipient_fingerprints(u.email) f ON true
   JOIN public.delivery_recipient_state s ON s.recipient_fingerprint=f.fingerprint
   WHERE u.email IN ('c77-90@example.test','c77-91@example.test',
     'c77-92@example.test','c77-93@example.test') LOOP
   IF r.email='c77-90@example.test' AND r.suppression_reason IS DISTINCT FROM 'permanent_bounce'
     OR r.email='c77-91@example.test' AND r.suppression_reason IS DISTINCT FROM 'spam_complaint'
     OR r.email='c77-92@example.test' AND NOT r.pending_unmatched
     OR r.email='c77-93@example.test' AND NOT r.provider_suppressed
   THEN RAISE EXCEPTION 'Post-promotion hold missing for %',r.email; END IF;
 END LOOP;
 IF NOT EXISTS (SELECT 1 FROM public.delivery_recipient_state s
      JOIN deedlight_private.recipient_fingerprints('c77-92@example.test') f
      ON f.fingerprint=s.recipient_fingerprint
      WHERE s.pending_unmatched) THEN
  RAISE EXCEPTION 'Undetermined hold absent'; END IF;
END $assert_promoted$;

-- Reordered success, duplicate, modified-payload replay and account removals.
SET ROLE service_role;
DO $reordered$
DECLARE ts timestamptz:=clock_timestamp(); state text;
BEGIN
 state:=public.deedlight_record_resend_delivery_v2(
  'msg_c77_late_success_0006','provider-c77-090','c77-90@example.test',
  'email.delivered',ts,repeat('6',64),NULL,NULL);
 IF state<>'recorded' THEN RAISE EXCEPTION 'Late success failed: %',state; END IF;
 state:=public.deedlight_record_resend_delivery_v2(
  'msg_c77_late_success_0007','provider-c77-091','c77-91@example.test',
  'email.delivered',ts,repeat('7',64),NULL,NULL);
 IF state<>'recorded' THEN RAISE EXCEPTION 'Complaint late success failed: %',state; END IF;
 state:=public.deedlight_record_resend_delivery_v2(
  'msg_c77_late_success_0008','provider-c77-092','c77-92@example.test',
  'email.delivered',ts,repeat('8',64),NULL,NULL);
 IF state<>'recorded' THEN RAISE EXCEPTION 'Unknown late success failed: %',state; END IF;
 state:=public.deedlight_record_resend_delivery_v2(
  'msg_c77_pending_permanent_0001','provider-c77-090','c77-90@example.test',
  'email.bounced',ts,repeat('a',64),'permanent_bounce','Permanent');
 IF state<>'duplicate' THEN RAISE EXCEPTION 'Exact event replay not deduplicated: %',state; END IF;
 state:=public.deedlight_record_resend_delivery_v2(
  'msg_c77_pending_permanent_0001','provider-c77-090','c77-90@example.test',
  'email.bounced',ts,repeat('f',64),'permanent_bounce','Permanent');
 IF state<>'quarantined' THEN RAISE EXCEPTION 'Changed payload not quarantined: %',state; END IF;
 state:=public.deedlight_record_resend_suppression_verified(
  'msg_c77_removed_after_0009','f59508fe-2cf3-4e12-9989-529c712e7777',
  'c77-90@example.test','manual',NULL,'suppression.removed',ts,repeat('9',64));
 IF state<>'recorded' THEN RAISE EXCEPTION 'Late removal not audited'; END IF;
 state:=public.deedlight_record_resend_delivery_v2(
  'msg_c77_mismatch_0010','provider-c77-090','c77-95@example.test',
  'email.delivered',ts,repeat('1',64),NULL,NULL);
 IF state<>'quarantined' THEN RAISE EXCEPTION 'Wrong recipient not quarantined: %',state; END IF;
END $reordered$;
RESET ROLE;

DO $final_holds$
DECLARE s90 public.delivery_recipient_state%rowtype;
        s91 public.delivery_recipient_state%rowtype;
        s92 public.delivery_recipient_state%rowtype;
        s93 public.delivery_recipient_state%rowtype;
BEGIN
 SELECT s.* INTO s90 FROM public.delivery_recipient_state s
 JOIN deedlight_private.recipient_fingerprints('c77-90@example.test') f
 ON f.fingerprint=s.recipient_fingerprint LIMIT 1;
 SELECT s.* INTO s91 FROM public.delivery_recipient_state s
 JOIN deedlight_private.recipient_fingerprints('c77-91@example.test') f
 ON f.fingerprint=s.recipient_fingerprint LIMIT 1;
 SELECT s.* INTO s92 FROM public.delivery_recipient_state s
 JOIN deedlight_private.recipient_fingerprints('c77-92@example.test') f
 ON f.fingerprint=s.recipient_fingerprint LIMIT 1;
 SELECT s.* INTO s93 FROM public.delivery_recipient_state s
 JOIN deedlight_private.recipient_fingerprints('c77-93@example.test') f
 ON f.fingerprint=s.recipient_fingerprint LIMIT 1;
 IF s90.suppression_reason IS DISTINCT FROM 'permanent_bounce'
    OR s91.suppression_reason IS DISTINCT FROM 'spam_complaint'
    OR NOT s92.pending_unmatched OR NOT s93.provider_suppressed
 THEN RAISE EXCEPTION 'Out-of-order event cleared or downgraded safety hold'; END IF;
 IF EXISTS(SELECT 1 FROM public.delivery_recipient_state s
   JOIN deedlight_private.recipient_fingerprints('c77-95@example.test') f
   ON f.fingerprint=s.recipient_fingerprint
   WHERE s.provider_suppressed OR s.suppression_reason IS NOT NULL)
 THEN RAISE EXCEPTION 'Unrelated recipient suppressed'; END IF;
 IF (SELECT state FROM deedlight_event_private.provider_event_registry
    WHERE event_id='msg_c77_pending_permanent_0001')<>'identity_conflict'
 OR (SELECT state FROM deedlight_event_private.provider_event_registry
    WHERE event_id='msg_c77_mismatch_0010')<>'identity_conflict'
 THEN RAISE EXCEPTION 'Identity-conflict registry state lost'; END IF;
END $final_holds$;

-- Two historical HMAC versions: prior recipient suppression cannot be cleared.
UPDATE deedlight_private.delivery_recipient_key_control SET mode='locked' WHERE singleton;
UPDATE deedlight_private.delivery_recipient_keyring SET phase='legacy' WHERE key_version=1;
INSERT INTO deedlight_private.delivery_recipient_keyring(key_version,secret_bytes,phase)
 VALUES(2,decode(repeat('c7',32),'hex'),'active');
UPDATE deedlight_private.delivery_recipient_key_control
 SET required_key_versions=ARRAY[1,2]::smallint[],mode='ready' WHERE singleton;
DO $history$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM deedlight_private.recipient_fingerprints('c77-90@example.test');
 IF n<>2 THEN RAISE EXCEPTION 'Historical HMAC fingerprints missing: %',n; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.delivery_provider_submissions p
   JOIN deedlight_private.recipient_fingerprints('c77-90@example.test') f
    ON f.fingerprint=p.recipient_fingerprint
   WHERE p.provider_email_id='provider-c77-090' AND f.phase='legacy')
 THEN RAISE EXCEPTION 'Historical provider submission no longer correlates'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.delivery_recipient_state s
   JOIN deedlight_private.recipient_fingerprints('c77-91@example.test') f
     ON f.fingerprint=s.recipient_fingerprint
   WHERE f.phase='legacy' AND s.suppression_reason='spam_complaint')
 THEN RAISE EXCEPTION 'Complaint lost on key rotation'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.delivery_recipient_state s
   JOIN deedlight_private.recipient_fingerprints('c77-92@example.test') f
     ON f.fingerprint=s.recipient_fingerprint
   WHERE f.phase='legacy' AND s.pending_unmatched)
 THEN RAISE EXCEPTION 'Uncertain bounce lost on key rotation'; END IF;
END $history$;
SELECT jsonb_build_object(
 'pending_permanent_promotion','pass',
 'pending_complaint_promotion','pass',
 'pending_undetermined_promotion','pass',
 'pending_provider_suppression_promotion','pass',
 'removal_before_and_after_promotion','pass',
 'duplicate_event_identity','pass',
 'modified_payload_quarantine','pass',
 'late_success_monotonic','pass',
 'recipient_mismatch_quarantine','pass',
 'unrelated_recipient_not_suppressed','pass',
 'historical_binding_and_hold','pass'
) AS c77_post033_regression;

-- Fail closed if historical key catalog names a missing version; exception rolls back fixture change.
DO $missing_key$
BEGIN
 BEGIN
  UPDATE deedlight_private.delivery_recipient_key_control
    SET required_key_versions=ARRAY[1,2,99]::smallint[] WHERE singleton;
  PERFORM count(*) FROM deedlight_private.recipient_fingerprints('c77-95@example.test');
  RAISE EXCEPTION 'Unknown historical key version silently accepted' USING ERRCODE='ZX077';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
 END;
 IF (SELECT required_key_versions FROM deedlight_private.delivery_recipient_key_control WHERE singleton)
    IS DISTINCT FROM ARRAY[1,2]::smallint[] THEN
   RAISE EXCEPTION 'Missing-key test failed to restore key catalog'; END IF;
END $missing_key$;

DO $guess_denial$
DECLARE v_id uuid;v_token uuid;
BEGIN
 SELECT l.id,l.claim_token INTO v_id,v_token
 FROM public.delivery_ledger l JOIN auth.users u ON u.id=l.user_id
 WHERE u.email='c77-95@example.test' AND l.kind='daily_reminder' LIMIT 1;
 IF v_id IS NULL OR v_token IS NULL THEN RAISE EXCEPTION 'Expected synthetic delivery absent'; END IF;
END $guess_denial$;
SET ROLE service_role;
DO $wrong_email$
DECLARE v_id uuid;v_token uuid;
BEGIN
 SELECT l.id,l.claim_token INTO v_id,v_token
 FROM public.delivery_ledger l JOIN auth.users u ON u.id=l.user_id
 WHERE u.email='c77-95@example.test' AND l.kind='daily_reminder' LIMIT 1;
 BEGIN
   PERFORM public.begin_delivery_transport_identity_bound(v_id,v_token,'c77-94@example.test');
   RAISE EXCEPTION 'Guessed Auth recipient authorized transport' USING ERRCODE='ZX078';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
 END;
END $wrong_email$;
RESET ROLE;
SELECT jsonb_build_object('unknown_key_version','pass',
  'guessed_recipient_denied','pass') AS c77_key_fencing;
