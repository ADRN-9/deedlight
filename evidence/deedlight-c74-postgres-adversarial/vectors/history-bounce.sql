\set ON_ERROR_STOP on
-- Historical collisions: simulated only in a rolled-back PostgreSQL 16
-- transaction with two guards disabled briefly by disposable DB owner.
BEGIN;
UPDATE deedlight_event_private.registry_control
  SET accepting_new_events=false WHERE singleton;
ALTER TABLE public.delivery_provider_pending_events DISABLE TRIGGER c73_registry_guard;
ALTER TABLE public.delivery_provider_pending_events DISABLE TRIGGER c74_lifecycle_guard;
INSERT INTO public.delivery_provider_pending_events
 (svix_event_id,provider_email_id,recipient_fingerprint,event_type,event_at,payload_sha256,suppression_reason)
SELECT svix_event_id,provider_email_id,recipient_fingerprint,event_type,event_at,payload_sha256,suppression_reason
FROM public.delivery_provider_events WHERE svix_event_id='msg_c73_complained_00002';
ALTER TABLE public.delivery_provider_pending_events ENABLE ALWAYS TRIGGER c73_registry_guard;
ALTER TABLE public.delivery_provider_pending_events ENABLE ALWAYS TRIGGER c74_lifecycle_guard;
DO $collision$
BEGIN
 IF (SELECT count(*) FROM public.delivery_provider_pending_events
     WHERE svix_event_id='msg_c73_complained_00002')<>1 THEN
   RAISE EXCEPTION 'Historical collision fixture missing';
 END IF;
 BEGIN
   UPDATE deedlight_event_private.registry_control
     SET accepting_new_events=true,reconciled_at=clock_timestamp(),
         reconciled_evidence='C74-INVALID-HISTORICAL-DUPLICATE' WHERE singleton;
   RAISE EXCEPTION 'Historical duplicate allowed registry re-enable';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;
 END;
END $collision$;
ROLLBACK;
DO $clean$
BEGIN
 IF (SELECT accepting_new_events FROM deedlight_event_private.registry_control
     WHERE singleton) IS DISTINCT FROM true
 OR EXISTS(SELECT 1 FROM public.delivery_provider_pending_events
     WHERE svix_event_id='msg_c73_complained_00002') THEN
   RAISE EXCEPTION 'Rolled-back history simulation contaminated live registry';
 END IF;
END $clean$;

-- Two kinds for one confirmed synthetic recipient. The Daily send creates
-- the sole authoritative provider message association, then receives events.
INSERT INTO auth.users(id,email,email_confirmed_at)
 VALUES ('70000000-0000-0000-0000-000000000007','c74-bounce@example.test',now());
INSERT INTO public.profiles(user_id,is_suspended)
 VALUES ('70000000-0000-0000-0000-000000000007',false);
INSERT INTO public.daily_reminder_preferences(user_id,daily_enabled,reminder_time,timezone)
 VALUES ('70000000-0000-0000-0000-000000000007',true,'00:00','UTC');
INSERT INTO public.newsletter_preferences(user_id,weekly_enabled,consented_at)
 VALUES ('70000000-0000-0000-0000-000000000007',true,now());
INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
 VALUES ('70000000-0000-0000-0000-000000000007','daily_reminder',
 'daily:' || (timezone('UTC',now())::date - 1)::text,
 ((timezone('UTC',now())::date - 1) + time '00:00') AT TIME ZONE 'UTC');
INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
 VALUES ('70000000-0000-0000-0000-000000000007','weekly_newsletter',
 'weekly:' || (timezone('UTC',now())::date
    - (extract(isodow from timezone('UTC',now()))::int - 1))::text,
 now()-interval '1 minute');
SET ROLE service_role;
DO $events$
DECLARE j uuid; t uuid; event_time timestamptz:=clock_timestamp(); result text;
BEGIN
 PERFORM public.claim_delivery_jobs('daily_reminder',now(),1000);
 SELECT id,claim_token INTO j,t FROM public.delivery_ledger
   WHERE user_id='70000000-0000-0000-0000-000000000007' AND kind='daily_reminder';
 IF j IS NULL OR t IS NULL
   OR public.begin_delivery_transport_identity_bound(j,t,'c74-bounce@example.test') IS NULL
   OR public.mark_delivery_sent_identity_bound(j,t,'provider-c74-bounce-007') IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Synthetic provider association not created'; END IF;
 result:=public.deedlight_record_resend_verified('msg_c74_transient_bounce001','provider-c74-bounce-007',
   'c74-bounce@example.test','email.bounced',event_time,repeat('1',64),NULL);
 IF result<>'recorded' THEN RAISE EXCEPTION 'Transient bounce not recorded'; END IF;
 result:=public.deedlight_record_resend_verified('msg_c74_permanent_bounce001','provider-c74-bounce-007',
   'c74-bounce@example.test','email.bounced',event_time,repeat('2',64),'permanent_bounce');
 IF result<>'recorded' THEN RAISE EXCEPTION 'Permanent bounce not recorded'; END IF;
 result:=public.deedlight_record_resend_verified('msg_c74_late_delivery001','provider-c74-bounce-007',
   'c74-bounce@example.test','email.delivered',event_time,repeat('3',64),NULL);
 IF result<>'recorded' THEN RAISE EXCEPTION 'Late delivery event not recorded'; END IF;
 result:=public.deedlight_record_resend_verified('msg_c74_complaint_after_bounce001','provider-c74-bounce-007',
   'c74-bounce@example.test','email.complained',event_time,repeat('4',64),'spam_complaint');
 IF result<>'recorded' THEN RAISE EXCEPTION 'Complaint escalation failed'; END IF;
 result:=public.deedlight_record_resend_verified('msg_c74_complaint_after_bounce001','provider-c74-bounce-007',
   'c74-bounce@example.test','email.complained',event_time,repeat('4',64),'spam_complaint');
 IF result<>'duplicate' THEN RAISE EXCEPTION 'Signed complaint replay not idempotent'; END IF;
 result:=public.deedlight_record_resend_verified('msg_c74_provider_suppressed001','provider-c74-bounce-007',
   'c74-bounce@example.test','email.suppressed',event_time,repeat('5',64),NULL);
 IF result<>'recorded' THEN RAISE EXCEPTION 'Provider suppression not recorded'; END IF;
END $events$;
RESET ROLE;
DO $suppression$
BEGIN
 IF NOT EXISTS (
   SELECT 1 FROM public.delivery_provider_submissions p
   JOIN public.delivery_recipient_state s ON s.recipient_fingerprint=p.recipient_fingerprint
   WHERE p.provider_email_id='provider-c74-bounce-007'
    AND s.suppression_reason='spam_complaint'
    AND s.provider_suppressed AND s.pending_unmatched
    AND p.lifecycle_state='complained'
 ) THEN RAISE EXCEPTION 'Bounce/complaint/provider suppression monotonicity failed'; END IF;
END $suppression$;
SET ROLE service_role;
DO $weekly$
DECLARE j uuid;t uuid;attempt timestamptz;
BEGIN
 PERFORM public.claim_delivery_jobs('weekly_newsletter',now(),1000);
 SELECT id,claim_token INTO j,t FROM public.delivery_ledger
  WHERE user_id='70000000-0000-0000-0000-000000000007' AND kind='weekly_newsletter';
 IF j IS NULL OR t IS NULL THEN RAISE EXCEPTION 'Synthetic Weekly claim missing'; END IF;
 BEGIN
  attempt:=public.begin_delivery_transport_identity_bound(j,t,'c74-bounce@example.test');
  IF attempt IS NOT NULL THEN RAISE EXCEPTION 'Suppression bypassed by Weekly claim'; END IF;
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
 END;
 IF EXISTS(SELECT 1 FROM public.delivery_ledger
     WHERE id=j AND transport_started_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Suppressed Weekly send recorded transport';
 END IF;
END $weekly$;
RESET ROLE;
SELECT jsonb_build_object(
 'historical_duplicate_reenable','denied','transient_bounce','recorded',
 'permanent_bounce','suppressed','late_delivery_did_not_unsuppress','pass',
 'complaint_escalation','pass','provider_suppression','durable',
 'weekly_after_daily_suppression','denied') AS c74_history_bounce_result;
