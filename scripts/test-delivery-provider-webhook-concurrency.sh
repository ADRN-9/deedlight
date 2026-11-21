#!/usr/bin/env bash
set -euo pipefail

psql_cmd=(psql -X -v ON_ERROR_STOP=1 --host 127.0.0.1 --port 5432 --username postgres --dbname deedlight_webhook_test)
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

wait_for_marker() {
  local pid="$1"
  local file="$2"
  local marker="$3"
  for _ in {1..100}; do
    if grep -q "$marker" "$file"; then return 0; fi
    if ! kill -0 "$pid" 2>/dev/null; then
      cat "$file"
      return 1
    fi
    sleep 0.05
  done
  cat "$file"
  return 1
}

# A concurrent conflicting payload under the same Svix ID is an integrity anomaly.
"${psql_cmd[@]}" >"$tmp/duplicate-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  'evt_concurrent_duplicate', 'email.sent', 'resend-concurrent-duplicate',
  'concurrent-duplicate@example.test', '2027-03-02T10:00:00Z', null, null
);
\echo DUPLICATE_EVENT_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
duplicate_pid=$!
wait_for_marker "$duplicate_pid" "$tmp/duplicate-first.log" "DUPLICATE_EVENT_LOCK_HELD"
"${psql_cmd[@]}" -Atc "set role service_role; select public.record_delivery_provider_lifecycle_event('evt_concurrent_duplicate','email.complained','resend-concurrent-duplicate','concurrent-duplicate@example.test','2027-03-02T10:01:00Z',null,null); reset role;" >"$tmp/duplicate-result"
wait "$duplicate_pid"
duplicate_result="$(cat "$tmp/duplicate-result")"
[[ -z "$duplicate_result" ]]
count="$("${psql_cmd[@]}" -Atc "select count(*) from public.delivery_provider_events where event_id='evt_concurrent_duplicate'")"
[[ "$count" == "1" ]]
suppression="$("${psql_cmd[@]}" -Atc "select count(*) from public.delivery_provider_suppressions where recipient_email='concurrent-duplicate@example.test'")"
[[ "$suppression" == "0" ]]
event_type="$(${psql_cmd[@]} -Atc "select event_type from public.delivery_provider_events where event_id='evt_concurrent_duplicate'")"
[[ "$event_type" == "email.sent" ]]
anomaly="$(${psql_cmd[@]} -Atc "select count(*) from public.delivery_provider_integrity_anomalies where event_id='evt_concurrent_duplicate' and anomaly_type='duplicate_event_id_conflict'")"
[[ "$anomaly" == "1" ]]
status="$(${psql_cmd[@]} -Atc "select status from public.delivery_provider_lifecycle where provider_email_id='resend-concurrent-duplicate'")"
[[ "$status" == "integrity_anomaly" ]]
echo "Concurrent conflicting duplicate integrity anomaly: PASS"


# Conflicting terminal outcomes are retained but never projected as delivered.
for order in delivered-first bounced-first; do
  if [[ "$order" == "delivered-first" ]]; then
    first_type="email.delivered"
    first_id="evt_concurrent_terminal_delivered"
    first_time="2027-03-02T11:00:00Z"
    first_bounce="null"
    second_type="email.bounced"
    second_id="evt_concurrent_terminal_bounced"
    second_time="2027-03-02T11:01:00Z"
    second_bounce="'Permanent'"
  else
    first_type="email.bounced"
    first_id="evt_concurrent_terminal_bounced_reverse"
    first_time="2027-03-02T11:10:00Z"
    first_bounce="'Permanent'"
    second_type="email.delivered"
    second_id="evt_concurrent_terminal_delivered_reverse"
    second_time="2027-03-02T11:11:00Z"
    second_bounce="null"
  fi
  provider_id="resend-concurrent-terminal-$order"
  recipient="concurrent-terminal-$order@example.test"
  log="$tmp/$order-first.log"
  result="$tmp/$order-result"
  "${psql_cmd[@]}" >"$log" 2>&1 <<SQL &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  '$first_id', '$first_type', '$provider_id', '$recipient',
  '$first_time', $first_bounce, null
);
\echo TERMINAL_EVENT_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
  terminal_pid=$!
  wait_for_marker "$terminal_pid" "$log" "TERMINAL_EVENT_LOCK_HELD"
  "${psql_cmd[@]}" -Atc "set role service_role; select public.record_delivery_provider_lifecycle_event('$second_id','$second_type','$provider_id','$recipient','$second_time',$second_bounce,null); reset role;" >"$result"
  wait "$terminal_pid"
  terminal_result="$(cat "$result")"
  [[ -z "$terminal_result" ]]
  status="$(${psql_cmd[@]} -Atc "select status from public.delivery_provider_lifecycle where provider_email_id='$provider_id'")"
  [[ "$status" == "integrity_anomaly" ]]
  count="$(${psql_cmd[@]} -Atc "select count(*) from public.delivery_provider_events where provider_email_id='$provider_id'")"
  [[ "$count" == "2" ]]
  anomaly="$(${psql_cmd[@]} -Atc "select count(*) from public.delivery_provider_integrity_anomalies where event_id='$second_id' and anomaly_type='contradictory_terminal_outcome'")"
  [[ "$anomaly" == "1" ]]
done
echo "Concurrent contradictory terminal outcomes in both arrival orders: PASS"

# A delayed event arriving after a later delivered event cannot regress status.
"${psql_cmd[@]}" >"$tmp/delivered-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  'evt_concurrent_delivered', 'email.delivered', 'resend-concurrent-order',
  'concurrent-order@example.test', '2027-03-02T10:10:00Z', null, null
);
\echo DELIVERED_EVENT_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
delivered_pid=$!
wait_for_marker "$delivered_pid" "$tmp/delivered-first.log" "DELIVERED_EVENT_LOCK_HELD"
"${psql_cmd[@]}" -Atc "set role service_role; select public.record_delivery_provider_lifecycle_event('evt_concurrent_delayed','email.delivery_delayed','resend-concurrent-order','concurrent-order@example.test','2027-03-02T10:05:00Z',null,null); reset role;" >"$tmp/delayed-result"
wait "$delivered_pid"
grep -qx 't' "$tmp/delayed-result"
status="$("${psql_cmd[@]}" -Atc "select status from public.delivery_provider_lifecycle where provider_email_id='resend-concurrent-order'")"
[[ "$status" == "email.delivered" ]]
count="$("${psql_cmd[@]}" -Atc "select count(*) from public.delivery_provider_events where provider_email_id='resend-concurrent-order'")"
[[ "$count" == "2" ]]
echo "Concurrent out-of-order lifecycle monotonicity: PASS"

# A suppression event that wins the shared address lock must cancel transport.
"${psql_cmd[@]}" <<'SQL'
insert into auth.users (id,email,email_confirmed_at)
values ('00000000-0000-0000-0000-000000020006','suppression-race@example.test',now());
insert into public.profiles (user_id,is_suspended)
values ('00000000-0000-0000-0000-000000020006',false);
insert into public.daily_reminder_preferences (user_id,daily_enabled,reminder_time,timezone)
values ('00000000-0000-0000-0000-000000020006',true,'00:00','UTC');
insert into public.delivery_ledger (
  user_id,kind,delivery_key,state,scheduled_for,claim_token,
  claimed_at,claim_expires_at,attempt_count
) values (
  '00000000-0000-0000-0000-000000020006',
  'daily_reminder',
  'daily:' || timezone('UTC',now())::date::text,
  'claimed',
  (timezone('UTC',now())::date + time '00:00') at time zone 'UTC',
  '33333333-3333-3333-3333-333333332006',
  now(),now() + interval '5 minutes',1
);
SQL

"${psql_cmd[@]}" >"$tmp/suppression-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  'evt_suppression_race_first', 'email.complained', 'resend-suppression-race-first',
  'suppression-race@example.test', '2027-03-02T10:20:00Z', null, null
);
\echo SUPPRESSION_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
suppression_pid=$!
wait_for_marker "$suppression_pid" "$tmp/suppression-first.log" "SUPPRESSION_LOCK_HELD"
"${psql_cmd[@]}" <<'SQL'
set role service_role;
do $$
declare v_id uuid; v_token uuid;
begin
  select id,claim_token into v_id,v_token
  from public.delivery_ledger
  where user_id='00000000-0000-0000-0000-000000020006';
  if v_id is null then raise exception 'Missing suppression race claim.'; end if;
  if public.begin_delivery_transport(v_id,v_token,'suppression-race@example.test') is not null then
    raise exception 'Transport passed after provider suppression won the address lock.';
  end if;
end;
$$;
reset role;
SQL
wait "$suppression_pid"
result="$("${psql_cmd[@]}" -Atc "select state || ':' || (transport_started_at is null)::text from public.delivery_ledger where user_id='00000000-0000-0000-0000-000000020006'")"
[[ "$result" == "cancelled:true" ]]
echo "Shared suppression-first transport authorization: PASS"

# If transport authorization wins first, the provider event waits; no provider send occurs here.
"${psql_cmd[@]}" <<'SQL'
insert into auth.users (id,email,email_confirmed_at)
values ('00000000-0000-0000-0000-000000020007','transport-race@example.test',now());
insert into public.profiles (user_id,is_suspended)
values ('00000000-0000-0000-0000-000000020007',false);
insert into public.daily_reminder_preferences (user_id,daily_enabled,reminder_time,timezone)
values ('00000000-0000-0000-0000-000000020007',true,'00:00','UTC');
insert into public.delivery_ledger (
  user_id,kind,delivery_key,state,scheduled_for,claim_token,
  claimed_at,claim_expires_at,attempt_count
) values (
  '00000000-0000-0000-0000-000000020007',
  'daily_reminder',
  'daily:' || timezone('UTC',now())::date::text,
  'claimed',
  (timezone('UTC',now())::date + time '00:00') at time zone 'UTC',
  '33333333-3333-3333-3333-333333332007',
  now(),now() + interval '5 minutes',1
);
SQL

"${psql_cmd[@]}" >"$tmp/transport-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
do $$
declare v_id uuid; v_token uuid;
begin
  select id,claim_token into v_id,v_token
  from public.delivery_ledger
  where user_id='00000000-0000-0000-0000-000000020007';
  if v_id is null or public.begin_delivery_transport(v_id,v_token,'transport-race@example.test') is null then
    raise exception 'Valid transport-first authorization failed.';
  end if;
end;
$$;
\echo TRANSPORT_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
transport_pid=$!
wait_for_marker "$transport_pid" "$tmp/transport-first.log" "TRANSPORT_LOCK_HELD"
"${psql_cmd[@]}" -Atc "set role service_role; select public.record_delivery_provider_lifecycle_event('evt_suppression_race_after_transport','email.complained','resend-suppression-race-after','transport-race@example.test','2027-03-02T10:21:00Z',null,null); reset role;" >"$tmp/suppression-after-result"
wait "$transport_pid"
grep -qx 't' "$tmp/suppression-after-result"
result="$("${psql_cmd[@]}" -Atc "select (transport_started_at is not null)::text || ':' || (select count(*)::text from public.delivery_provider_suppressions where recipient_email='transport-race@example.test') from public.delivery_ledger where user_id='00000000-0000-0000-0000-000000020007'")"
[[ "$result" == "true:1" ]]
echo "Shared transport-first suppression ordering: PASS"
