#!/usr/bin/env bash
# C76 disposable PostgreSQL 16: genuine simultaneous Daily / Weekly claimers.
set -Eeuo pipefail
set +x
[[ "$GITHUB_REPOSITORY" == ADRN-9/deedlight ]]
[[ "$DELIVERY_ENABLED" == false ]]
export PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres
OUT="$GITHUB_WORKSPACE/c76-kind-logs"
mkdir -p "$OUT"
DB=deedlight_c76_kinds
PSQL=(psql -X -v ON_ERROR_STOP=1 -d "$DB")
"${PSQL[@]}" >"$OUT/synthetic-setup.log" 2>&1 <<'SQL'
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
 ('70000000-0000-0000-0000-000000000080','c76-daily-worker@example.test',now()),
 ('70000000-0000-0000-0000-000000000081','c76-weekly-worker@example.test',now());
INSERT INTO public.profiles(user_id,is_suspended)
 VALUES('70000000-0000-0000-0000-000000000080',false),('70000000-0000-0000-0000-000000000081',false);
INSERT INTO public.daily_reminder_preferences(user_id,daily_enabled,reminder_time,timezone)
 VALUES('70000000-0000-0000-0000-000000000080',true,'00:00','UTC');
INSERT INTO public.newsletter_preferences(user_id,weekly_enabled,consented_at)
 VALUES('70000000-0000-0000-0000-000000000081',true,now());
INSERT INTO public.weekly_goodness_features(week_start)
 VALUES(timezone('UTC',now())::date-(extract(isodow from timezone('UTC',now()))::integer-1))
 ON CONFLICT DO NOTHING;
INSERT INTO public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
 VALUES('70000000-0000-0000-0000-000000000080','daily_reminder',
    'daily:'||(timezone('UTC',now())::date-1)::text,
    ((timezone('UTC',now())::date-1)+time '00:00') AT TIME ZONE 'UTC'),
   ('70000000-0000-0000-0000-000000000081','weekly_newsletter',
    'weekly:'||(timezone('UTC',now())::date-(extract(isodow from timezone('UTC',now()))::integer-1))::text,
    now()-interval '1 minute');
SQL
"${PSQL[@]}" >"$OUT/daily-transaction.log" 2>&1 <<'SQL' &
BEGIN;
SET LOCAL ROLE service_role;
DO $daily$
DECLARE i integer;
BEGIN
 FOR i IN 1..12 LOOP
   EXIT WHEN EXISTS(SELECT 1 FROM public.delivery_ledger
    WHERE user_id='70000000-0000-0000-0000-000000000080'
      AND kind='daily_reminder' AND state='claimed');
   PERFORM count(*) FROM public.claim_delivery_jobs('daily_reminder',now(),1000);
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM public.delivery_ledger
    WHERE user_id='70000000-0000-0000-0000-000000000080'
      AND kind='daily_reminder' AND state='claimed')
 THEN RAISE EXCEPTION 'Daily worker did not claim its own synthetic job'; END IF;
END $daily$;
\echo C76_DAILY_TRANSACTION_LOCK_HELD
SELECT pg_sleep(4);
COMMIT;
SQL
a=$!
for i in {1..120}; do
 if grep -q C76_DAILY_TRANSACTION_LOCK_HELD "$OUT/daily-transaction.log"; then break; fi
 if ! kill -0 "$a" 2>/dev/null; then cat "$OUT/daily-transaction.log"; exit 1; fi
 sleep 0.05
done
grep -q C76_DAILY_TRANSACTION_LOCK_HELD "$OUT/daily-transaction.log"
"${PSQL[@]}" >"$OUT/weekly-transaction.log" 2>&1 <<'SQL'
BEGIN;
SET LOCAL ROLE service_role;
DO $weekly$
DECLARE i integer;
BEGIN
 FOR i IN 1..12 LOOP
   EXIT WHEN EXISTS(SELECT 1 FROM public.delivery_ledger
    WHERE user_id='70000000-0000-0000-0000-000000000081'
      AND kind='weekly_newsletter' AND state='claimed');
   PERFORM count(*) FROM public.claim_delivery_jobs('weekly_newsletter',now(),1000);
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM public.delivery_ledger
   WHERE user_id='70000000-0000-0000-0000-000000000081'
     AND kind='weekly_newsletter' AND state='claimed')
 THEN RAISE EXCEPTION 'Weekly worker did not claim its own synthetic job'; END IF;
END $weekly$;
COMMIT;
SQL
wait "$a"
"${PSQL[@]}" >"$OUT/kind-and-lease-regressions.log" 2>&1 <<'SQL'
DO $post_parallel$
BEGIN
 IF (SELECT count(*) FROM public.delivery_ledger
    WHERE user_id='70000000-0000-0000-0000-000000000080'
      AND state='claimed' AND kind='daily_reminder')<>1
 OR (SELECT count(*) FROM public.delivery_ledger
    WHERE user_id='70000000-0000-0000-0000-000000000081'
      AND state='claimed' AND kind='weekly_newsletter')<>1
 THEN RAISE EXCEPTION 'Parallel workers crossed delivery kinds'; END IF;
 IF has_function_privilege('anon',
   'public.claim_delivery_jobs(text,timestamptz,integer)','EXECUTE')
 THEN RAISE EXCEPTION 'Browser can execute privileged claim function'; END IF;
END $post_parallel$;
SET ROLE service_role;
DO $reclaim$
DECLARE j uuid; old_token uuid; new_token uuid; old_key text; i integer; started timestamptz;
BEGIN
 SELECT id,claim_token,delivery_key INTO j,old_token,old_key
 FROM public.delivery_ledger
 WHERE user_id='70000000-0000-0000-0000-000000000080' AND kind='daily_reminder';
 IF old_token IS NULL THEN RAISE EXCEPTION 'Daily token absent after parallel claim'; END IF;
 BEGIN
  started:=public.begin_delivery_transport_identity_bound(j,gen_random_uuid(),
   'c76-daily-worker@example.test');
  IF started IS NOT NULL THEN RAISE EXCEPTION 'Stale-token sent' USING ERRCODE='ZX001'; END IF;
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
 END;
 UPDATE public.delivery_ledger SET claim_expires_at=clock_timestamp()-interval '1 second'
 WHERE id=j AND state='claimed';
 PERFORM count(*) FROM public.claim_delivery_jobs('weekly_newsletter',now(),1000);
 IF (SELECT claim_token FROM public.delivery_ledger WHERE id=j) IS DISTINCT FROM old_token
 THEN RAISE EXCEPTION 'Weekly worker reclaimed an expired Daily lease'; END IF;
 FOR i IN 1..12 LOOP
  EXIT WHEN (SELECT claim_token FROM public.delivery_ledger WHERE id=j) IS DISTINCT FROM old_token;
  PERFORM count(*) FROM public.claim_delivery_jobs('daily_reminder',now(),1000);
 END LOOP;
 SELECT claim_token INTO new_token FROM public.delivery_ledger WHERE id=j;
 IF new_token IS NULL OR new_token=old_token
   OR (SELECT delivery_key FROM public.delivery_ledger WHERE id=j) IS DISTINCT FROM old_key
 THEN RAISE EXCEPTION 'Daily worker failed safe lease token rotation / logical idempotency'; END IF;
 BEGIN
  started:=public.begin_delivery_transport_identity_bound(j,old_token,
   'c76-daily-worker@example.test');
  IF started IS NOT NULL THEN RAISE EXCEPTION 'Expired claim token reauthorized' USING ERRCODE='ZX002'; END IF;
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
 END;
 BEGIN
  PERFORM public.claim_delivery_jobs('unsupported',now(),10);
  RAISE EXCEPTION 'Unsupported kind allowed' USING ERRCODE='ZX003';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
 END;
END $reclaim$;
RESET ROLE;
UPDATE public.daily_reminder_preferences SET daily_enabled=false
 WHERE user_id='70000000-0000-0000-0000-000000000080';
UPDATE public.newsletter_preferences SET weekly_enabled=false
 WHERE user_id='70000000-0000-0000-0000-000000000081';
SET ROLE service_role;
DO $revoked$
DECLARE j uuid;t uuid; u text; started timestamptz;
BEGIN
 FOR j,t,u IN SELECT dl.id,dl.claim_token,au.email
 FROM public.delivery_ledger dl JOIN auth.users au ON au.id=dl.user_id
 WHERE dl.user_id IN ('70000000-0000-0000-0000-000000000080',
   '70000000-0000-0000-0000-000000000081') AND dl.state='claimed'
 LOOP
  BEGIN
   started:=public.begin_delivery_transport_identity_bound(j,t,u);
   IF started IS NOT NULL THEN
     RAISE EXCEPTION 'Revoked current consent authorized a send' USING ERRCODE='ZX004';
   END IF;
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  IF EXISTS(SELECT 1 FROM public.delivery_ledger WHERE id=j AND transport_started_at IS NOT NULL)
  THEN RAISE EXCEPTION 'Revoked consent persisted a new transport'; END IF;
 END LOOP;
END $revoked$;
RESET ROLE;
SELECT jsonb_build_object('concurrent_daily_weekly_claims','pass',
  'expired_lease_kind_isolation','pass',
  'stale_claim_token_rejected','pass',
  'idempotent_delivery_key_preserved','pass',
  'revoked_daily_consent_denied','pass',
  'revoked_weekly_consent_denied','pass',
  'browser_claim_privilege_denied','pass') AS c76_concurrent_kind_security;
SQL
echo 'C76 real two-session Daily/Weekly claim race + expired lease + revoked consent: PASS' > "$OUT/concurrency-result.txt"
