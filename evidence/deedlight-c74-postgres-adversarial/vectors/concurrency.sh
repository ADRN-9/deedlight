#!/usr/bin/env bash
set -Eeuo pipefail
set +x
OUT="$GITHUB_WORKSPACE/c74-results"
mkdir -p "$OUT"
test "$GITHUB_REPOSITORY" = ADRN-9/deedlight
test "$DELIVERY_ENABLED" = false
export PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres
psql -X -v ON_ERROR_STOP=1 -d deedlight_c74_adversarial >"$OUT/duplicate-a.log" 2>&1 <<'SQL' &
BEGIN;
SET LOCAL ROLE service_role;
SELECT public.deedlight_record_resend_verified(
 'msg_c74_concurrent_dupe001','provider-c74-unknown-001','c73-b@example.test',
 'email.delivered',now(),repeat('6',64),NULL) AS first_ingestion;
\echo C74_A_LOCK_HELD
SELECT pg_sleep(3);
COMMIT;
SQL
a=$!
for i in {1..100}; do
 if grep -q C74_A_LOCK_HELD "$OUT/duplicate-a.log"; then break; fi
 if ! kill -0 "$a" 2>/dev/null; then cat "$OUT/duplicate-a.log"; exit 1; fi
 sleep 0.05
done
grep -q C74_A_LOCK_HELD "$OUT/duplicate-a.log"
psql -X -v ON_ERROR_STOP=1 -d deedlight_c74_adversarial >"$OUT/duplicate-b.log" 2>&1 <<'SQL'
SET ROLE service_role;
SELECT public.deedlight_record_resend_verified(
 'msg_c74_concurrent_dupe001','provider-c74-unknown-001','c73-b@example.test',
 'email.delivered',now(),repeat('6',64),NULL) AS second_ingestion;
RESET ROLE;
SQL
wait "$a"
grep -q pending "$OUT/duplicate-a.log"
grep -q pending "$OUT/duplicate-b.log"
psql -X -v ON_ERROR_STOP=1 -At -d deedlight_c74_adversarial >"$OUT/duplicate-invariants.log" <<'SQL'
DO $$
BEGIN
 IF (SELECT count(*) FROM deedlight_event_private.provider_event_registry WHERE event_id='msg_c74_concurrent_dupe001')<>1
 OR (SELECT count(*) FROM public.delivery_provider_pending_events WHERE svix_event_id='msg_c74_concurrent_dupe001')<>1
 OR EXISTS(SELECT 1 FROM public.delivery_provider_events WHERE svix_event_id='msg_c74_concurrent_dupe001')
 OR EXISTS(SELECT 1 FROM public.delivery_provider_identity_conflicts WHERE svix_event_id='msg_c74_concurrent_dupe001')
 THEN RAISE EXCEPTION 'Concurrent duplicate created conflicting lifecycle rows'; END IF;
END $$;
SET ROLE service_role;
SELECT public.deedlight_record_resend_verified(
 'msg_c74_concurrent_dupe001','provider-c74-unknown-001','c73-b@example.test',
 'email.delivered',now(),repeat('7',64),NULL);
RESET ROLE;
DO $$
BEGIN
 IF (SELECT state FROM deedlight_event_private.provider_event_registry
 WHERE event_id='msg_c74_concurrent_dupe001')<>'identity_conflict'
 THEN RAISE EXCEPTION 'Conflicting replay not quarantined'; END IF;
END $$;
SQL
grep -q quarantined "$OUT/duplicate-invariants.log"
echo 'Concurrent same-ID ingestion + mismatched replay: PASS' | tee "$OUT/concurrency-status.txt"
psql -X -v ON_ERROR_STOP=1 -d deedlight_c74_adversarial > "$OUT/race-setup.log" <<'SQL'
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES ('70000000-0000-0000-0000-000000000006','c74-race@example.test',now());
INSERT INTO public.profiles(user_id,is_suspended) VALUES ('70000000-0000-0000-0000-000000000006',false);
INSERT INTO public.daily_reminder_preferences(user_id,daily_enabled,reminder_time,timezone) VALUES ('70000000-0000-0000-0000-000000000006',true,'00:00','UTC');
INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for) VALUES
 ('70000000-0000-0000-0000-000000000006','daily_reminder','daily:' || (timezone('UTC',now())::date - 1)::text,
    ((timezone('UTC',now())::date - 1) + time '00:00') AT TIME ZONE 'UTC'),
 ('70000000-0000-0000-0000-000000000006','daily_reminder','daily:' || timezone('UTC',now())::date::text,
    (timezone('UTC',now())::date + time '00:00') AT TIME ZONE 'UTC');
SET ROLE service_role;
DO $$
DECLARE j uuid;t uuid;
BEGIN
 PERFORM public.claim_delivery_jobs('daily_reminder',now(),100);
 SELECT id,claim_token INTO j,t FROM public.delivery_ledger WHERE delivery_key='daily:' || (timezone('UTC',now())::date - 1)::text;
 IF public.begin_delivery_transport_identity_bound(j,t,'c74-race@example.test') IS NULL
 OR public.mark_delivery_sent_identity_bound(j,t,'provider-c74-race-001') IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Initial provider correlation failed'; END IF;
END $$;
RESET ROLE;
SQL
psql -X -v ON_ERROR_STOP=1 -d deedlight_c74_adversarial >"$OUT/suppression-first.log" 2>&1 <<'SQL' &
BEGIN;
SET LOCAL ROLE service_role;
SELECT public.deedlight_record_resend_verified(
 'msg_c74_race_complaint001','provider-c74-race-001','c74-race@example.test',
 'email.complained',now(),repeat('a',64),'spam_complaint');
\echo C74_SUPPRESSION_LOCK_HELD
SELECT pg_sleep(4);
COMMIT;
SQL
s=$!
for i in {1..100}; do
 if grep -q C74_SUPPRESSION_LOCK_HELD "$OUT/suppression-first.log"; then break; fi
 if ! kill -0 "$s" 2>/dev/null; then cat "$OUT/suppression-first.log"; exit 1; fi
 sleep 0.05
done
grep -q C74_SUPPRESSION_LOCK_HELD "$OUT/suppression-first.log"
psql -X -v ON_ERROR_STOP=1 -d deedlight_c74_adversarial >"$OUT/transport-race.log" 2>&1 <<'SQL'
SET ROLE service_role;
DO $$
DECLARE j uuid;t uuid;attempt timestamptz;
BEGIN
 SELECT id,claim_token INTO j,t FROM public.delivery_ledger WHERE delivery_key='daily:' || timezone('UTC',now())::date::text;
 BEGIN
  attempt:=public.begin_delivery_transport_identity_bound(j,t,'c74-race@example.test');
  IF attempt IS NOT NULL THEN RAISE EXCEPTION 'C74 UNSAFE SEND: complaint raced final send'; END IF;
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
 END;
 IF EXISTS(SELECT 1 FROM public.delivery_ledger WHERE id=j AND transport_started_at IS NOT NULL)
 THEN RAISE EXCEPTION 'Suppression race persisted transport intent'; END IF;
END $$;
RESET ROLE;
SQL
wait "$s"
psql -X -v ON_ERROR_STOP=1 -d deedlight_c74_adversarial >"$OUT/suppression-invariants.log" <<'SQL'
DO $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.delivery_provider_submissions p JOIN public.delivery_recipient_state r ON r.recipient_fingerprint=p.recipient_fingerprint
 WHERE p.provider_email_id='provider-c74-race-001' AND r.suppression_reason='spam_complaint')
 OR EXISTS(SELECT 1 FROM public.delivery_ledger WHERE delivery_key='daily:' || timezone('UTC',now())::date::text AND transport_started_at IS NOT NULL)
 THEN RAISE EXCEPTION 'Complaint/send race broke permanent safety'; END IF;
END $$;
SQL
echo 'Complaint-before-final-authorization serialization: PASS' | tee -a "$OUT/concurrency-status.txt"
psql -X -v ON_ERROR_STOP=1 -d deedlight_c74_adversarial >"$OUT/rollback.log" 2>&1 <<'SQL'
BEGIN;
SET LOCAL ROLE service_role;
SELECT public.deedlight_record_resend_verified(
 'msg_c74_rollback_retry001','provider-c74-rollback-001','c73-b@example.test','email.sent',now(),repeat('3',64),NULL);
ROLLBACK;
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM deedlight_event_private.provider_event_registry WHERE event_id='msg_c74_rollback_retry001')
 THEN RAISE EXCEPTION 'Rolled-back event reservation persisted'; END IF;
END $$;
SET ROLE service_role;
SELECT public.deedlight_record_resend_verified(
 'msg_c74_rollback_retry001','provider-c74-rollback-001','c73-b@example.test','email.sent',now(),repeat('3',64),NULL);
RESET ROLE;
SQL
grep -q pending "$OUT/rollback.log"
echo 'Transaction rollback / retry: PASS' | tee -a "$OUT/concurrency-status.txt"
