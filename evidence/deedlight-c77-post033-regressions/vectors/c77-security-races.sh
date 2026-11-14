#!/usr/bin/env bash
# Disposable PostgreSQL 16 only; synthetic provider events, no outbound network.
set -Eeuo pipefail
set +x
test "$GITHUB_REPOSITORY" = "ADRN-9/deedlight"
test "$DELIVERY_ENABLED" = false
DB=deedlight_c77_races
OUT="$GITHUB_WORKSPACE/c77-race-logs"
mkdir -p "$OUT"
wait_for() {
  local pattern="$1" logfile="$2" child="$3"
  for i in {1..140}; do
    if grep -q "$pattern" "$logfile" 2>/dev/null; then return 0; fi
    if ! kill -0 "$child" 2>/dev/null; then cat "$logfile" >&2; return 1; fi
    sleep .05
  done
  cat "$logfile" >&2
  echo "Concurrency barrier timed out" >&2
  return 1
}

psql -X -v ON_ERROR_STOP=1 -d "$DB" > "$OUT/setup.log" 2>&1 <<'SQL'
INSERT INTO auth.users(id,email,email_confirmed_at)
 SELECT ('70000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,
   'c77-race-'||i||'@example.test',now() FROM generate_series(96,98) i;
INSERT INTO public.profiles(user_id,is_suspended)
 SELECT id,false FROM auth.users WHERE email LIKE 'c77-race-%@example.test';
INSERT INTO public.daily_reminder_preferences(user_id,daily_enabled,reminder_time,timezone)
 SELECT id,true,time '00:00','UTC' FROM auth.users WHERE email LIKE 'c77-race-%@example.test';
INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
 SELECT id,'daily_reminder','daily:'||(timezone('UTC',now())::date-1)::text,
   ((timezone('UTC',now())::date-1)+time '00:00') AT TIME ZONE 'UTC' FROM auth.users WHERE email LIKE 'c77-race-%@example.test';
SET ROLE service_role;
DO $first$
DECLARE r record;i integer;started timestamptz; provider_id text;
BEGIN
 FOR i IN 1..12 LOOP
   EXIT WHEN (SELECT count(*) FROM public.delivery_ledger l JOIN auth.users u ON u.id=l.user_id
     WHERE u.email LIKE 'c77-race-%@example.test' AND l.state='claimed')=3;
   PERFORM count(*) FROM public.claim_delivery_jobs('daily_reminder',now(),1000);
 END LOOP;
 FOR r IN SELECT u.email,l.id,l.claim_token FROM public.delivery_ledger l
   JOIN auth.users u ON u.id=l.user_id
   WHERE u.email LIKE 'c77-race-%@example.test' LOOP
   IF r.claim_token IS NULL THEN RAISE EXCEPTION 'Original claim missing'; END IF;
   started:=public.begin_delivery_transport_identity_bound(r.id,r.claim_token,r.email);
   IF started IS NULL THEN RAISE EXCEPTION 'Original transport not authorized'; END IF;
   provider_id:='provider-c77-race-'||lpad(split_part(split_part(r.email,'@',1),'-',3),3,'0');
   IF public.mark_delivery_sent_identity_bound(r.id,r.claim_token,provider_id) IS DISTINCT FROM true
   THEN RAISE EXCEPTION 'Original provider submission absent'; END IF;
 END LOOP;
END $first$;
RESET ROLE;
INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
 SELECT id,'daily_reminder','daily:'||timezone('UTC',now())::date::text,
   (timezone('UTC',now())::date+time '00:00') AT TIME ZONE 'UTC'
 FROM auth.users WHERE email IN ('c77-race-96@example.test','c77-race-97@example.test');
SET ROLE service_role;
DO $retry$
DECLARE i integer;
BEGIN
 FOR i IN 1..12 LOOP
  EXIT WHEN (SELECT count(*) FROM public.delivery_ledger l JOIN auth.users u ON u.id=l.user_id
    WHERE u.email IN ('c77-race-96@example.test','c77-race-97@example.test')
      AND l.state='claimed')=2;
  PERFORM count(*) FROM public.claim_delivery_jobs('daily_reminder',now(),1000);
 END LOOP;
 IF (SELECT count(*) FROM public.delivery_ledger l JOIN auth.users u ON u.id=l.user_id
   WHERE u.email IN ('c77-race-96@example.test','c77-race-97@example.test')
     AND l.state='claimed')<>2 THEN RAISE EXCEPTION 'Retry claim unavailable'; END IF;
END $retry$;
RESET ROLE;
SQL

# C: Signed-provider classification is supplied through the narrow DB-bound RPC.
psql -X -v ON_ERROR_STOP=1 -d "$DB" > "$OUT/complaint-writer.log" 2>&1 <<'SQL' &
BEGIN;
SET LOCAL ROLE service_role;
DO $event$
DECLARE result text;
BEGIN
 result:=public.deedlight_record_resend_delivery_v2(
  'msg_c77_race_complaint_0096','provider-c77-race-096',
  'c77-race-96@example.test','email.complained',
  clock_timestamp(),repeat('a',64),'spam_complaint',NULL);
 IF result<>'recorded' THEN RAISE EXCEPTION 'Complaint result: %',result; END IF;
END $event$;
\echo C77_COMPLAINT_HELD
SELECT pg_sleep(4);
COMMIT;
SQL
worker=$!
wait_for C77_COMPLAINT_HELD "$OUT/complaint-writer.log" "$worker"
psql -X -v ON_ERROR_STOP=1 -d "$DB" > "$OUT/complaint-final.log" 2>&1 <<'SQL'
SET ROLE service_role;
DO $denial$
DECLARE j uuid;token uuid;ts timestamptz;
BEGIN
 SELECT l.id,l.claim_token INTO j,token FROM public.delivery_ledger l
 JOIN auth.users u ON u.id=l.user_id
 WHERE u.email='c77-race-96@example.test' AND l.state='claimed';
 IF token IS NULL THEN RAISE EXCEPTION 'No complaint-race claim'; END IF;
 BEGIN
  ts:=public.begin_delivery_transport_identity_bound(j,token,'c77-race-96@example.test');
  IF ts IS NOT NULL THEN RAISE EXCEPTION 'Complaint raced through final authorization' USING ERRCODE='ZX001'; END IF;
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
 END;
END $denial$;
RESET ROLE;
SQL
wait "$worker"

# D: Mismatch event freezes the original recipient while retry attempts final authorization.
psql -X -v ON_ERROR_STOP=1 -d "$DB" > "$OUT/conflict-writer.log" 2>&1 <<'SQL' &
BEGIN;
SET LOCAL ROLE service_role;
DO $event$
DECLARE result text;
BEGIN
 result:=public.deedlight_record_resend_delivery_v2(
  'msg_c77_race_mismatch_0097','provider-c77-race-097',
  'unrelated-c77@example.test','email.delivered',
  clock_timestamp(),repeat('b',64),NULL,NULL);
 IF result<>'quarantined' THEN RAISE EXCEPTION 'Conflict result: %',result; END IF;
END $event$;
\echo C77_CONFLICT_HELD
SELECT pg_sleep(4);
COMMIT;
SQL
worker=$!
wait_for C77_CONFLICT_HELD "$OUT/conflict-writer.log" "$worker"
psql -X -v ON_ERROR_STOP=1 -d "$DB" > "$OUT/conflict-final.log" 2>&1 <<'SQL'
SET ROLE service_role;
DO $denial$
DECLARE j uuid;token uuid;ts timestamptz;
BEGIN
 SELECT l.id,l.claim_token INTO j,token FROM public.delivery_ledger l
 JOIN auth.users u ON u.id=l.user_id
 WHERE u.email='c77-race-97@example.test' AND l.state='claimed';
 IF token IS NULL THEN RAISE EXCEPTION 'No conflict-race claim'; END IF;
 BEGIN
  ts:=public.begin_delivery_transport_identity_bound(j,token,'c77-race-97@example.test');
  IF ts IS NOT NULL THEN RAISE EXCEPTION 'Conflict raced through final authorization' USING ERRCODE='ZX002'; END IF;
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
 END;
END $denial$;
RESET ROLE;
SQL
wait "$worker"

# E: Removal transaction and permanent bounce serialize by recipient fingerprint.
psql -X -v ON_ERROR_STOP=1 -d "$DB" > "$OUT/removal-writer.log" 2>&1 <<'SQL' &
BEGIN;
SET LOCAL ROLE service_role;
DO $event$
DECLARE result text;
BEGIN
 result:=public.deedlight_record_resend_suppression_verified(
  'msg_c77_race_remove_0098','53eb6b44-42a1-4291-9f7a-9a1efbb84d21',
  'c77-race-98@example.test','manual',NULL,'suppression.removed',
  clock_timestamp(),repeat('c',64));
 IF result<>'recorded' THEN RAISE EXCEPTION 'Removal event result: %',result; END IF;
END $event$;
\echo C77_REMOVAL_HELD
SELECT pg_sleep(4);
COMMIT;
SQL
worker=$!
wait_for C77_REMOVAL_HELD "$OUT/removal-writer.log" "$worker"
psql -X -v ON_ERROR_STOP=1 -d "$DB" > "$OUT/bounce-writer.log" 2>&1 <<'SQL'
SET ROLE service_role;
DO $event$
DECLARE result text;
BEGIN
 result:=public.deedlight_record_resend_delivery_v2(
  'msg_c77_race_bounce_0098','provider-c77-race-098',
  'c77-race-98@example.test','email.bounced',
  clock_timestamp(),repeat('d',64),'permanent_bounce','Permanent');
 IF result<>'recorded' THEN RAISE EXCEPTION 'Bounce event result: %',result; END IF;
END $event$;
RESET ROLE;
SQL
wait "$worker"

psql -X -v ON_ERROR_STOP=1 -d "$DB" > "$OUT/assertions.log" 2>&1 <<'SQL'
DO $verify$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.delivery_recipient_state s
   JOIN deedlight_private.recipient_fingerprints('c77-race-96@example.test') f
     ON f.fingerprint=s.recipient_fingerprint WHERE s.suppression_reason='spam_complaint')
 OR NOT EXISTS (SELECT 1 FROM public.delivery_recipient_state s
   JOIN deedlight_private.recipient_fingerprints('c77-race-97@example.test') f
     ON f.fingerprint=s.recipient_fingerprint WHERE s.pending_unmatched)
 OR NOT EXISTS (SELECT 1 FROM public.delivery_recipient_state s
   JOIN deedlight_private.recipient_fingerprints('c77-race-98@example.test') f
     ON f.fingerprint=s.recipient_fingerprint WHERE s.suppression_reason='permanent_bounce')
 OR NOT EXISTS (SELECT 1 FROM deedlight_event_private.provider_event_registry
   WHERE event_id='msg_c77_race_mismatch_0097' AND state='identity_conflict')
 THEN RAISE EXCEPTION 'Concurrent recipient hold not monotone'; END IF;
 IF EXISTS (SELECT 1 FROM public.delivery_ledger l JOIN auth.users u ON u.id=l.user_id
   WHERE u.email IN ('c77-race-96@example.test','c77-race-97@example.test')
     AND l.delivery_key='daily:'||timezone('UTC',now())::date::text
     AND l.transport_started_at IS NOT NULL)
 THEN RAISE EXCEPTION 'Concurrent final authorization began external transport'; END IF;
END $verify$;
SELECT jsonb_build_object(
 'complaint_vs_final_send','pass',
 'identity_conflict_vs_retry','pass',
 'removal_vs_permanent_bounce','pass',
 'cross_session_postgresql','pass',
 'synthetic_only','pass') AS c77_concurrency;
SQL
printf 'C77 cross-session complaint, identity, removal races PASS\n' > "$OUT/result.txt"
