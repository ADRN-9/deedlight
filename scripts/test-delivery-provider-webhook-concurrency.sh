#!/usr/bin/env bash
set -euo pipefail

psql_cmd=(psql -X -v ON_ERROR_STOP=1 --host 127.0.0.1 --port 5432 --username postgres --dbname deedlight_webhook_test)
psql_scalar() {
  "${psql_cmd[@]}" --quiet --no-align --tuples-only --pset=null=__NULL__ --command="$1"
}
psql_service_scalar() {
  "${psql_cmd[@]}" --quiet --no-align --tuples-only --pset=null=__NULL__ --command="set role service_role; $1"
}
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

# An exact duplicate blocks behind the first insert and remains an idempotent no-op.
"${psql_cmd[@]}" >"$tmp/exact-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  'evt_concurrent_exact_duplicate', 'email.bounced', 'resend-concurrent-exact',
  'concurrent-exact@example.test', '2027-03-02T09:00:00Z', 'Permanent', null,
  null, repeat('e', 64)
);
\echo EXACT_DUPLICATE_EVENT_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
exact_pid=$!
wait_for_marker "$exact_pid" "$tmp/exact-first.log" "EXACT_DUPLICATE_EVENT_LOCK_HELD"
exact_result="$(psql_service_scalar "select public.record_delivery_provider_lifecycle_event(
  'evt_concurrent_exact_duplicate', 'email.bounced', 'resend-concurrent-exact',
  'concurrent-exact@example.test', '2027-03-02T09:00:00Z', 'Permanent', null,
  null, repeat('e', 64)
)")"
wait "$exact_pid"
[[ "$exact_result" == "f" ]]
exact_event_count="$(psql_scalar "select count(*) from public.delivery_provider_events where event_id='evt_concurrent_exact_duplicate'")"
exact_suppression="$(psql_scalar "select reason || ':' || provider_event_id from public.delivery_provider_suppressions where recipient_email='concurrent-exact@example.test'")"
exact_status="$(psql_scalar "select status from public.delivery_provider_lifecycle where provider_email_id='resend-concurrent-exact'")"
exact_anomalies="$(psql_scalar "select count(*) from public.delivery_provider_integrity_anomalies where event_id='evt_concurrent_exact_duplicate'")"
[[ "$exact_event_count" == "1" ]]
[[ "$exact_suppression" == "permanent_bounce:evt_concurrent_exact_duplicate" ]]
[[ "$exact_status" == "email.bounced" ]]
[[ "$exact_anomalies" == "0" ]]
echo "Concurrent exact duplicate event: PASS"

# A concurrent conflicting payload under the same Svix ID is an integrity anomaly.
"${psql_cmd[@]}" >"$tmp/duplicate-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  'evt_concurrent_duplicate', 'email.bounced', 'resend-concurrent-duplicate',
  'concurrent-duplicate@example.test', '2027-03-02T10:00:00Z', 'Permanent', null,
  null, repeat('f', 64)
);
\echo DUPLICATE_EVENT_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
duplicate_pid=$!
wait_for_marker "$duplicate_pid" "$tmp/duplicate-first.log" "DUPLICATE_EVENT_LOCK_HELD"
duplicate_result="$(psql_service_scalar "select public.record_delivery_provider_lifecycle_event(
  'evt_concurrent_duplicate', 'email.complained', 'different-provider-id',
  'attacker-concurrent@example.test', '2027-03-02T10:01:00Z', null, null,
  null, repeat('a', 64)
)")"
wait "$duplicate_pid"
[[ "$duplicate_result" == "__NULL__" ]]
count="$(psql_scalar "select count(*) from public.delivery_provider_events where event_id='evt_concurrent_duplicate'")"
suppression="$(psql_scalar "select reason || ':' || provider_event_id from public.delivery_provider_suppressions where recipient_email='concurrent-duplicate@example.test'")"
event_state="$(psql_scalar "select event_type || ':' || provider_email_id || ':' || recipient_email || ':' || payload_fingerprint from public.delivery_provider_events where event_id='evt_concurrent_duplicate'")"
attacker_suppression="$(psql_scalar "select count(*) from public.delivery_provider_suppressions where recipient_email='attacker-concurrent@example.test'")"
anomaly="$(psql_scalar "select count(*) from public.delivery_provider_integrity_anomalies where event_id='evt_concurrent_duplicate' and anomaly_type='duplicate_event_id_conflict'")"
status="$(psql_scalar "select status from public.delivery_provider_lifecycle where provider_email_id='resend-concurrent-duplicate'")"
[[ "$count" == "1" ]]
[[ "$suppression" == "permanent_bounce:evt_concurrent_duplicate" ]]
[[ "$event_state" == "email.bounced:resend-concurrent-duplicate:concurrent-duplicate@example.test:$(printf 'f%.0s' {1..64})" ]]
[[ "$attacker_suppression" == "0" ]]
[[ "$anomaly" == "1" ]]
[[ "$status" == "integrity_anomaly" ]]
echo "Concurrent conflicting duplicate integrity anomaly: PASS"

# A provider email ID is permanently bound to one recipient, even across concurrent callbacks.
"${psql_cmd[@]}" >"$tmp/cross-recipient-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  'evt_cross_recipient_first', 'email.delivered', 'resend-cross-recipient-collision',
  'first-recipient@example.test', '2027-03-02T12:00:00Z', null, null,
  null, repeat('c', 64)
);
\echo CROSS_RECIPIENT_PROVIDER_ID_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
cross_recipient_first_pid=$!
wait_for_marker "$cross_recipient_first_pid" "$tmp/cross-recipient-first.log" "CROSS_RECIPIENT_PROVIDER_ID_LOCK_HELD"

psql_service_scalar "select public.record_delivery_provider_lifecycle_event(
  'evt_cross_recipient_second', 'email.complained', 'resend-cross-recipient-collision',
  'second-recipient@example.test', '2027-03-02T12:01:00Z', null, null,
  null, repeat('d', 64)
)" >"$tmp/cross-recipient-second.log" 2>&1 &
cross_recipient_second_pid=$!
cross_recipient_waiting="0"
for _ in {1..100}; do
  cross_recipient_waiting="$(psql_scalar "select count(*) from pg_stat_activity where wait_event_type='Lock' and wait_event='advisory' and query like '%evt_cross_recipient_second%'")"
  if [[ "$cross_recipient_waiting" == "1" ]]; then break; fi
  sleep 0.05
done
if [[ "$cross_recipient_waiting" != "1" ]]; then
  cat "$tmp/cross-recipient-second.log"
  echo "Cross-recipient callback did not wait on the provider-email-ID advisory lock." >&2
  exit 1
fi
wait "$cross_recipient_first_pid"
if wait "$cross_recipient_second_pid"; then
  echo "Cross-recipient provider email ID collision was accepted." >&2
  exit 1
fi
grep -q "Provider email correlation does not match." "$tmp/cross-recipient-second.log"

collision_event_count="$(psql_scalar "select count(*) from public.delivery_provider_events where provider_email_id='resend-cross-recipient-collision'")"
collision_first_event="$(psql_scalar "select count(*) from public.delivery_provider_events where event_id='evt_cross_recipient_first' and recipient_email='first-recipient@example.test'")"
collision_second_event="$(psql_scalar "select count(*) from public.delivery_provider_events where event_id='evt_cross_recipient_second' or recipient_email='second-recipient@example.test'")"
collision_lifecycle="$(psql_scalar "select status || ':' || event_id from public.delivery_provider_lifecycle where provider_email_id='resend-cross-recipient-collision'")"
collision_suppression="$(psql_scalar "select count(*) from public.delivery_provider_suppressions where recipient_email='second-recipient@example.test'")"
collision_anomaly="$(psql_scalar "select count(*) from public.delivery_provider_integrity_anomalies where event_id='evt_cross_recipient_second'")"
[[ "$collision_event_count" == "1" ]]
[[ "$collision_first_event" == "1" ]]
[[ "$collision_second_event" == "0" ]]
[[ "$collision_lifecycle" == "email.delivered:evt_cross_recipient_first" ]]
[[ "$collision_suppression" == "0" ]]
[[ "$collision_anomaly" == "0" ]]
echo "Concurrent cross-recipient provider email ID collision: PASS"

# A replay of a pre-027 row with no fingerprint remains a no-op under concurrency.
"${psql_cmd[@]}" >"$tmp/historical-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  'evt_historical_026_complaint', 'email.complained', 'resend-historical-026-complaint',
  'historical-026-complaint@example.test', '2027-03-01T09:15:00Z', null, null,
  null, null
);
\echo HISTORICAL_EVENT_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
historical_pid=$!
wait_for_marker "$historical_pid" "$tmp/historical-first.log" "HISTORICAL_EVENT_LOCK_HELD"
historical_result="$(psql_service_scalar "select public.record_delivery_provider_lifecycle_event(
  'evt_historical_026_complaint', 'email.complained', 'resend-historical-026-complaint',
  'historical-026-complaint@example.test', '2027-03-01T09:15:00Z', null, null,
  null, repeat('e', 64)
)")"
wait "$historical_pid"
historical_fingerprint="$(psql_scalar "select coalesce(payload_fingerprint, '__NULL__') from public.delivery_provider_events where event_id='evt_historical_026_complaint'")"
historical_anomalies="$(psql_scalar "select count(*) from public.delivery_provider_integrity_anomalies where event_id='evt_historical_026_complaint'")"
historical_suppression="$(psql_scalar "select reason || ':' || provider_event_id from public.delivery_provider_suppressions where recipient_email='historical-026-complaint@example.test'")"
historical_status="$(psql_scalar "select status from public.delivery_provider_lifecycle where provider_email_id='resend-historical-026-complaint'")"
[[ "$historical_result" == "f" ]]
[[ "$historical_fingerprint" == "__NULL__" ]]
[[ "$historical_anomalies" == "0" ]]
[[ "$historical_suppression" == "complaint:evt_historical_026_complaint" ]]
[[ "$historical_status" == "email.complained" ]]
echo "Concurrent historical event without fingerprint: PASS"

# Previous complaint always outranks previous-bounce suppression, regardless of lock order.
for order in complaint-first bounce-first; do
  if [[ "$order" == "complaint-first" ]]; then
    first_reason="previous_complaint"
    first_id="evt_concurrent_previous_complaint_first"
    first_provider_id="resend-concurrent-previous-complaint-first"
    first_time="2027-03-02T10:30:00Z"
    second_reason="previous_bounce"
    second_id="evt_concurrent_previous_bounce_second"
    second_provider_id="resend-concurrent-previous-bounce-second"
    second_time="2027-03-02T10:31:00Z"
    complaint_id="$first_id"
  else
    first_reason="previous_bounce"
    first_id="evt_concurrent_previous_bounce_first"
    first_provider_id="resend-concurrent-previous-bounce-first"
    first_time="2027-03-02T10:40:00Z"
    second_reason="previous_complaint"
    second_id="evt_concurrent_previous_complaint_second"
    second_provider_id="resend-concurrent-previous-complaint-second"
    second_time="2027-03-02T10:41:00Z"
    complaint_id="$second_id"
  fi
  recipient="concurrent-previous-$order@example.test"
  first_log="$tmp/previous-$order-first.log"
  "${psql_cmd[@]}" >"$first_log" 2>&1 <<SQL &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  '$first_id', 'email.suppressed', '$first_provider_id', '$recipient',
  '$first_time', null, null, '$first_reason', repeat('1', 64)
);
\echo PREVIOUS_SUPPRESSION_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
  first_pid=$!
  wait_for_marker "$first_pid" "$first_log" "PREVIOUS_SUPPRESSION_LOCK_HELD"
  second_result="$(psql_service_scalar "select public.record_delivery_provider_lifecycle_event(
    '$second_id', 'email.suppressed', '$second_provider_id', '$recipient',
    '$second_time', null, null, '$second_reason', repeat('2', 64)
  )")"
  wait "$first_pid"
  suppression_state="$(psql_scalar "select reason || ':' || provider_event_id from public.delivery_provider_suppressions where recipient_email='$recipient'")"
  event_count="$(psql_scalar "select count(*) from public.delivery_provider_events where recipient_email='$recipient'")"
  anomaly_count="$(psql_scalar "select count(*) from public.delivery_provider_integrity_anomalies where event_id in ('$first_id','$second_id')")"
  [[ "$second_result" == "t" ]]
  [[ "$suppression_state" == "complaint:$complaint_id" ]]
  [[ "$event_count" == "2" ]]
  [[ "$anomaly_count" == "0" ]]
done
echo "Concurrent previous complaint/bounce suppression precedence: PASS"




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
  psql_service_scalar "select public.record_delivery_provider_lifecycle_event('$second_id','$second_type','$provider_id','$recipient','$second_time',$second_bounce,null)" >"$result"
  wait "$terminal_pid"
  terminal_result="$(cat "$result")"
  [[ "$terminal_result" == "__NULL__" ]]
  status="$(psql_scalar "select status from public.delivery_provider_lifecycle where provider_email_id='$provider_id'")"
  [[ "$status" == "integrity_anomaly" ]]
  count="$(psql_scalar "select count(*) from public.delivery_provider_events where provider_email_id='$provider_id'")"
  [[ "$count" == "2" ]]
  anomaly="$(psql_scalar "select count(*) from public.delivery_provider_integrity_anomalies where event_id='$second_id' and anomaly_type='contradictory_terminal_outcome'")"
  [[ "$anomaly" == "1" ]]
  if [[ "$order" == "delivered-first" ]]; then bounce_event_id="$second_id"; else bounce_event_id="$first_id"; fi
  suppression_state="$(psql_scalar "select reason || ':' || provider_event_id from public.delivery_provider_suppressions where recipient_email='$recipient'")"
  first_event_type="$(psql_scalar "select event_type from public.delivery_provider_events where event_id='$first_id'")"
  second_event_type="$(psql_scalar "select event_type from public.delivery_provider_events where event_id='$second_id'")"
  [[ "$first_event_type" == "$first_type" ]]
  [[ "$second_event_type" == "$second_type" ]]
  [[ "$suppression_state" == "permanent_bounce:$bounce_event_id" ]]
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
psql_service_scalar "select public.record_delivery_provider_lifecycle_event('evt_concurrent_delayed','email.delivery_delayed','resend-concurrent-order','concurrent-order@example.test','2027-03-02T10:05:00Z',null,null)" >"$tmp/delayed-result"
wait "$delivered_pid"
grep -qx 't' "$tmp/delayed-result"
status="$(psql_scalar "select status from public.delivery_provider_lifecycle where provider_email_id='resend-concurrent-order'")"
[[ "$status" == "email.delivered" ]]
count="$(psql_scalar "select count(*) from public.delivery_provider_events where provider_email_id='resend-concurrent-order'")"
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
result="$(psql_scalar "select state || ':' || (transport_started_at is null)::text from public.delivery_ledger where user_id='00000000-0000-0000-0000-000000020006'")"
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
psql_service_scalar "select public.record_delivery_provider_lifecycle_event('evt_suppression_race_after_transport','email.complained','resend-suppression-race-after','transport-race@example.test','2027-03-02T10:21:00Z',null,null)" >"$tmp/suppression-after-result"
wait "$transport_pid"
grep -qx 't' "$tmp/suppression-after-result"
result="$(psql_scalar "select (transport_started_at is not null)::text || ':' || (select count(*)::text from public.delivery_provider_suppressions where recipient_email='transport-race@example.test') from public.delivery_ledger where user_id='00000000-0000-0000-0000-000000020007'")"
[[ "$result" == "true:1" ]]
echo "Shared transport-first suppression ordering: PASS"
