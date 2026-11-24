#!/usr/bin/env bash
set -euo pipefail

psql_cmd=(psql -X -v ON_ERROR_STOP=1 --host 127.0.0.1 --port 5432 --username postgres --dbname deedlight_webhook_test)

command -v timeout >/dev/null 2>&1 || { echo "GNU timeout is required for bounded PostgreSQL tests." >&2; exit 1; }
command -v ps >/dev/null 2>&1 || { echo "ps is required for bounded child-process supervision." >&2; exit 1; }

command_timeout_seconds=25
wait_timeout_seconds=32
suite_timeout_seconds=840
child_pids=()

run_psql() {
  PGCONNECT_TIMEOUT=5 timeout --signal=TERM --kill-after=5s "${command_timeout_seconds}s" "${psql_cmd[@]}" "$@"
}

track_child() {
  child_pids+=("$1")
}

untrack_child() {
  local target="$1" pid
  local -a remaining=()
  for pid in "${child_pids[@]}"; do
    [[ "$pid" == "$target" ]] || remaining+=("$pid")
  done
  child_pids=("${remaining[@]}")
}

wait_bounded() {
  local pid="$1" label="$2" deadline state status=0
  deadline=$((SECONDS + wait_timeout_seconds))
  while (( SECONDS < deadline )); do
    state="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ -z "$state" || "$state" == Z* ]]; then
      wait "$pid" || status=$?
      untrack_child "$pid"
      return "$status"
    fi
    sleep 0.1
  done

  echo "Timed out waiting for child process: $label (pid $pid)" >&2
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  sleep 1
  kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  untrack_child "$pid"
  return 124
}

tmp="$(mktemp -d)"
suite_pid=$
timeout --signal=TERM --kill-after=2s "${suite_timeout_seconds}s" bash -c 'sleep "$1"; kill -TERM "$2"' _ "$suite_timeout_seconds" "$suite_pid" &
watchdog_pid=$!

cleanup() {
  local status=$? pid
  trap - EXIT
  set +e
  kill -TERM -- "-$watchdog_pid" 2>/dev/null || kill -TERM "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  for pid in "${child_pids[@]}"; do
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  done
  sleep 1
  for pid in "${child_pids[@]}"; do
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  rm -rf "$tmp"
  exit "$status"
}
trap 'exit 124' TERM
trap 'exit 130' INT
trap cleanup EXIT
psql_scalar() {
  run_psql --quiet --no-align --tuples-only --pset=null=__NULL__ --command="$1"
}
psql_service_scalar() {
  run_psql --quiet --no-align --tuples-only --pset=null=__NULL__ --command="set role service_role; $1"
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
run_psql >"$tmp/exact-first.log" 2>&1 <<'SQL' &
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
track_child "exact_pid"
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
run_psql >"$tmp/duplicate-first.log" 2>&1 <<'SQL' &
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
track_child "duplicate_pid"
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
run_psql >"$tmp/cross-recipient-first.log" 2>&1 <<'SQL' &
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
track_child "cross_recipient_first_pid"
wait_for_marker "$cross_recipient_first_pid" "$tmp/cross-recipient-first.log" "CROSS_RECIPIENT_PROVIDER_ID_LOCK_HELD"

psql_service_scalar "select public.record_delivery_provider_lifecycle_event(
  'evt_cross_recipient_second', 'email.complained', 'resend-cross-recipient-collision',
  'second-recipient@example.test', '2027-03-02T12:01:00Z', null, null,
  null, repeat('d', 64)
)" >"$tmp/cross-recipient-second.log" 2>&1 &
cross_recipient_second_pid=$!
track_child "cross_recipient_second_pid"
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
if ! wait "$cross_recipient_second_pid"; then
  cat "$tmp/cross-recipient-second.log"
  echo "Cross-recipient provider email ID conflict did not persist its evidence." >&2
  exit 1
fi
cross_recipient_result="$(tr -d '\r\n' <"$tmp/cross-recipient-second.log")"
[[ "$cross_recipient_result" == "__NULL__" ]]

collision_event_count="$(psql_scalar "select count(*) from public.delivery_provider_events where provider_email_id='resend-cross-recipient-collision'")"
collision_first_event="$(psql_scalar "select count(*) from public.delivery_provider_events where event_id='evt_cross_recipient_first' and recipient_email='first-recipient@example.test'")"
collision_second_event="$(psql_scalar "select count(*) from public.delivery_provider_events where event_id='evt_cross_recipient_second' or recipient_email='second-recipient@example.test'")"
collision_lifecycle="$(psql_scalar "select status || ':' || event_id from public.delivery_provider_lifecycle where provider_email_id='resend-cross-recipient-collision'")"
collision_suppression="$(psql_scalar "select count(*) from public.delivery_provider_suppressions where recipient_email='second-recipient@example.test'")"
collision_anomaly="$(psql_scalar "select count(*) from public.delivery_provider_integrity_anomalies where event_id='evt_cross_recipient_second'")"
[[ "$collision_event_count" == "1" ]]
[[ "$collision_first_event" == "1" ]]
[[ "$collision_second_event" == "0" ]]
[[ "$collision_lifecycle" == "integrity_anomaly:evt_cross_recipient_first" ]]
[[ "$collision_suppression" == "0" ]]
[[ "$collision_anomaly" == "0" ]]
collision_case="$(psql_scalar "select count(*) from public.delivery_provider_integrity_cases where recipient_email='second-recipient@example.test' and anomaly_type='provider_email_recipient_conflict' and state='open'")"
collision_evidence="$(psql_scalar "select count(*) from public.delivery_provider_integrity_conflict_evidence where event_id='evt_cross_recipient_second' and stored_event_id='evt_cross_recipient_first' and payload_fingerprint=repeat('d',64)")"
[[ "$collision_case" == "1" ]]
[[ "$collision_evidence" == "1" ]]
# Previous behavior: Provider email correlation does not match. Migration 037 records the retryable conflict and returns NULL.
echo "Concurrent cross-recipient provider email ID collision with durable evidence: PASS"

# A replay of a pre-027 row with no fingerprint remains a no-op under concurrency.
run_psql >"$tmp/historical-first.log" 2>&1 <<'SQL' &
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
track_child "historical_pid"
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
  run_psql >"$first_log" 2>&1 <<SQL &
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
  track_child "first_pid"
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
  run_psql >"$log" 2>&1 <<SQL &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  '$first_id', '$first_type', '$provider_id', '$recipient',
  '$first_time', $first_bounce, null, null, repeat('1', 64)
);
\echo TERMINAL_EVENT_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
  terminal_pid=$!
  track_child "terminal_pid"
  wait_for_marker "$terminal_pid" "$log" "TERMINAL_EVENT_LOCK_HELD"
  psql_service_scalar "select public.record_delivery_provider_lifecycle_event('$second_id','$second_type','$provider_id','$recipient','$second_time',$second_bounce,null,null,repeat('2',64))" >"$result"
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
run_psql >"$tmp/delivered-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  'evt_concurrent_delivered', 'email.delivered', 'resend-concurrent-order',
  'concurrent-order@example.test', '2027-03-02T10:10:00Z', null, null, null, repeat('3', 64)
);
\echo DELIVERED_EVENT_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
delivered_pid=$!
track_child "delivered_pid"
wait_for_marker "$delivered_pid" "$tmp/delivered-first.log" "DELIVERED_EVENT_LOCK_HELD"
psql_service_scalar "select public.record_delivery_provider_lifecycle_event('evt_concurrent_delayed','email.delivery_delayed','resend-concurrent-order','concurrent-order@example.test','2027-03-02T10:05:00Z',null,null,null,repeat('4',64))" >"$tmp/delayed-result"
wait "$delivered_pid"
grep -qx 't' "$tmp/delayed-result"
status="$(psql_scalar "select status from public.delivery_provider_lifecycle where provider_email_id='resend-concurrent-order'")"
[[ "$status" == "email.delivered" ]]
count="$(psql_scalar "select count(*) from public.delivery_provider_events where provider_email_id='resend-concurrent-order'")"
[[ "$count" == "2" ]]
echo "Concurrent out-of-order lifecycle monotonicity: PASS"

# A suppression event that wins the shared address lock must cancel transport.
run_psql <<'SQL'
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

run_psql >"$tmp/suppression-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  'evt_suppression_race_first', 'email.complained', 'resend-suppression-race-first',
  'suppression-race@example.test', '2027-03-02T10:20:00Z', null, null, null, repeat('5', 64)
);
\echo SUPPRESSION_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
suppression_pid=$!
track_child "suppression_pid"
wait_for_marker "$suppression_pid" "$tmp/suppression-first.log" "SUPPRESSION_LOCK_HELD"
run_psql <<'SQL'
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
run_psql <<'SQL'
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

run_psql >"$tmp/transport-first.log" 2>&1 <<'SQL' &
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
track_child "transport_pid"
wait_for_marker "$transport_pid" "$tmp/transport-first.log" "TRANSPORT_LOCK_HELD"
psql_service_scalar "select public.record_delivery_provider_lifecycle_event('evt_suppression_race_after_transport','email.complained','resend-suppression-race-after','transport-race@example.test','2027-03-02T10:21:00Z',null,null,null,repeat('6',64))" >"$tmp/suppression-after-result"
wait "$transport_pid"
grep -qx 't' "$tmp/suppression-after-result"
result="$(psql_scalar "select (transport_started_at is not null)::text || ':' || (select count(*)::text from public.delivery_provider_suppressions where recipient_email='transport-race@example.test') from public.delivery_ledger where user_id='00000000-0000-0000-0000-000000020007'")"
[[ "$result" == "true:1" ]]
echo "Shared transport-first suppression ordering: PASS"


# Suppression-list exact duplicates serialize on the recipient lock and remain no-ops.
run_psql >"$tmp/suppression-duplicate-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_suppression_event(
  'evt_concurrent_suppression_duplicate','suppression.added','sup_concurrent_duplicate',
  'concurrent-suppression-duplicate@example.test','manual',null,
  '2026-11-22T17:00:00Z','2026-11-22T17:01:00Z',repeat('a',64)
);
\echo SUPPRESSION_DUPLICATE_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
suppression_duplicate_pid=$!
track_child "suppression_duplicate_pid"
wait_for_marker "$suppression_duplicate_pid" "$tmp/suppression-duplicate-first.log" "SUPPRESSION_DUPLICATE_LOCK_HELD"
suppression_duplicate_result="$(psql_service_scalar "select public.record_delivery_provider_suppression_event(
  'evt_concurrent_suppression_duplicate','suppression.added','sup_concurrent_duplicate',
  'concurrent-suppression-duplicate@example.test','manual',null,
  '2026-11-22T17:00:00Z','2026-11-22T17:01:00Z',repeat('a',64)
)")"
wait "$suppression_duplicate_pid"
[[ "$suppression_duplicate_result" == "f" ]]
suppression_duplicate_count="$(psql_scalar "select count(*) from public.delivery_provider_events where event_id='evt_concurrent_suppression_duplicate'")"
suppression_duplicate_state="$(psql_scalar "select is_active::text from public.delivery_provider_suppression_state where recipient_email='concurrent-suppression-duplicate@example.test'")"
[[ "$suppression_duplicate_count" == "1" ]]
[[ "$suppression_duplicate_state" == "true" ]]
echo "Concurrent exact duplicate suppression event: PASS"

# A conflicting duplicate suppression event ID is retained as an integrity anomaly.
run_psql >"$tmp/suppression-conflict-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_suppression_event(
  'evt_concurrent_suppression_conflict','suppression.added','sup_concurrent_conflict',
  'concurrent-suppression-conflict@example.test','manual',null,
  '2026-11-22T18:00:00Z','2026-11-22T18:01:00Z',repeat('b',64)
);
\echo SUPPRESSION_CONFLICT_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
suppression_conflict_pid=$!
track_child "suppression_conflict_pid"
wait_for_marker "$suppression_conflict_pid" "$tmp/suppression-conflict-first.log" "SUPPRESSION_CONFLICT_LOCK_HELD"
suppression_conflict_result="$(psql_service_scalar "select public.record_delivery_provider_suppression_event(
  'evt_concurrent_suppression_conflict','suppression.removed','sup_concurrent_conflict',
  'concurrent-suppression-conflict@example.test','manual',null,
  '2026-11-22T18:00:00Z','2026-11-22T18:02:00Z',repeat('c',64)
)")"
wait "$suppression_conflict_pid"
[[ "$suppression_conflict_result" == "__NULL__" ]]
suppression_conflict_anomaly="$(psql_scalar "select count(*) from public.delivery_provider_integrity_anomalies where event_id='evt_concurrent_suppression_conflict' and anomaly_type='duplicate_event_id_conflict'")"
suppression_conflict_state="$(psql_scalar "select is_active::text from public.delivery_provider_suppression_state where recipient_email='concurrent-suppression-conflict@example.test'")"
[[ "$suppression_conflict_anomaly" == "1" ]]
[[ "$suppression_conflict_state" == "true" ]]
echo "Concurrent conflicting duplicate suppression event: PASS"

# The same provider suppression ID cannot be rebound to another recipient concurrently.
run_psql >"$tmp/suppression-cross-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_suppression_event(
  'evt_concurrent_suppression_cross_first','suppression.added','sup_concurrent_cross',
  'concurrent-suppression-first@example.test','manual',null,
  '2026-11-22T19:00:00Z','2026-11-22T19:01:00Z',repeat('d',64)
);
\echo SUPPRESSION_CROSS_ID_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
suppression_cross_first_pid=$!
track_child "suppression_cross_first_pid"
wait_for_marker "$suppression_cross_first_pid" "$tmp/suppression-cross-first.log" "SUPPRESSION_CROSS_ID_LOCK_HELD"
psql_service_scalar "select public.record_delivery_provider_suppression_event(
  'evt_concurrent_suppression_cross_second','suppression.removed','sup_concurrent_cross',
  'concurrent-suppression-second@example.test','manual',null,
  '2026-11-22T19:00:00Z','2026-11-22T19:02:00Z',repeat('e',64)
)" >"$tmp/suppression-cross-second.log" 2>&1 &
suppression_cross_second_pid=$!
track_child "suppression_cross_second_pid"
cross_id_waiting="0"
for _ in {1..100}; do
  cross_id_waiting="$(psql_scalar "select count(*) from pg_stat_activity where wait_event_type='Lock' and wait_event='advisory' and query like '%sup_concurrent_cross%'")"
  if [[ "$cross_id_waiting" == "1" ]]; then break; fi
  sleep 0.05
done
if [[ "$cross_id_waiting" != "1" ]]; then
  cat "$tmp/suppression-cross-second.log"
  echo "Cross-recipient suppression callback did not wait on the suppression-ID advisory lock." >&2
  exit 1
fi
wait "$suppression_cross_first_pid"
if ! wait "$suppression_cross_second_pid"; then
  cat "$tmp/suppression-cross-second.log"
  echo "Cross-recipient suppression ID conflict did not persist its evidence." >&2
  exit 1
fi
suppression_cross_result="$(tr -d '\r\n' <"$tmp/suppression-cross-second.log")"
[[ "$suppression_cross_result" == "__NULL__" ]]
suppression_cross_events="$(psql_scalar "select count(*) from public.delivery_provider_events where provider_suppression_id='sup_concurrent_cross'")"
suppression_cross_first="$(psql_scalar "select count(*) from public.delivery_provider_suppression_state where recipient_email='concurrent-suppression-first@example.test' and is_active")"
suppression_cross_second="$(psql_scalar "select count(*) from public.delivery_provider_suppression_state where recipient_email='concurrent-suppression-second@example.test'")"
[[ "$suppression_cross_events" == "1" ]]
suppression_cross_case="$(psql_scalar "select count(*) from public.delivery_provider_integrity_cases where recipient_email='concurrent-suppression-second@example.test' and anomaly_type='provider_suppression_recipient_conflict' and state='open'")"
suppression_cross_evidence="$(psql_scalar "select count(*) from public.delivery_provider_integrity_conflict_evidence where event_id='evt_concurrent_suppression_cross_second' and stored_event_id='evt_concurrent_suppression_cross_first' and payload_fingerprint=repeat('e',64)")"
[[ "$suppression_cross_case" == "1" ]]
[[ "$suppression_cross_evidence" == "1" ]]
echo "Concurrent cross-recipient suppression ID collision: PASS (durable evidence retained)"
[[ "$suppression_cross_first" == "1" ]]
[[ "$suppression_cross_second" == "0" ]]
echo "Concurrent cross-recipient suppression ID collision: PASS"

# Cross-stream ordering: a later manual removal must win when an older email.suppressed waits on the shared address lock.
run_psql >"$tmp/cross-stream-removal-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_suppression_event(
  'evt_c323_concurrent_manual_add','suppression.added','sup_c323_concurrent_manual',
  'c323-cross-stream-removal-first@example.test','manual',null,
  '2026-11-22T20:00:00Z','2026-11-22T20:01:00Z',repeat('a',64)
);
select public.record_delivery_provider_suppression_event(
  'evt_c323_concurrent_manual_remove','suppression.removed','sup_c323_concurrent_manual',
  'c323-cross-stream-removal-first@example.test','manual',null,
  '2026-11-22T20:00:00Z','2026-11-22T20:02:00Z',repeat('b',64)
);
\echo C323_CROSS_STREAM_REMOVAL_FIRST_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
cross_stream_removal_pid=$!
track_child "cross_stream_removal_pid"
wait_for_marker "$cross_stream_removal_pid" "$tmp/cross-stream-removal-first.log" "C323_CROSS_STREAM_REMOVAL_FIRST_LOCK_HELD"
run_psql >"$tmp/cross-stream-lifecycle-second.log" 2>&1 <<'SQL' &
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  'evt_c323_concurrent_old_email_suppressed','email.suppressed','resend_c323_concurrent_old',
  'c323-cross-stream-removal-first@example.test','2026-11-22T19:00:00Z',null,null,
  'provider_suppressed',repeat('c',64)
);
reset role;
SQL
cross_stream_lifecycle_pid=$!
track_child "cross_stream_lifecycle_pid"
cross_stream_waiting="0"
for _ in {1..100}; do
  cross_stream_waiting="$(psql_scalar "select count(*) from pg_stat_activity where wait_event_type='Lock' and wait_event='advisory' and query like '%evt_c323_concurrent_old_email_suppressed%'")"
  if [[ "$cross_stream_waiting" == "1" ]]; then break; fi
  sleep 0.05
done
if [[ "$cross_stream_waiting" != "1" ]]; then
  cat "$tmp/cross-stream-lifecycle-second.log"
  echo "Older email.suppressed did not wait on the provider suppression address lock." >&2
  exit 1
fi
wait "$cross_stream_removal_pid"
if ! wait "$cross_stream_lifecycle_pid"; then
  cat "$tmp/cross-stream-lifecycle-second.log"
  exit 1
fi
cross_stream_removal_state="$(psql_scalar "select is_active::text from public.delivery_provider_suppression_state where recipient_email='c323-cross-stream-removal-first@example.test'")"
cross_stream_removal_hold="$(psql_scalar "select count(*) from public.delivery_provider_suppressions where recipient_email='c323-cross-stream-removal-first@example.test'")"
[[ "$cross_stream_removal_state" == "false" ]]
[[ "$cross_stream_removal_hold" == "0" ]]
echo "Concurrent cross-stream removal-first ordering: PASS"

# The opposite lock order is also safe: the later provider removal clears a lifecycle hold.
run_psql >"$tmp/cross-stream-lifecycle-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  'evt_c323_concurrent_lifecycle_first','email.suppressed','resend_c323_concurrent_first',
  'c323-cross-stream-lifecycle-first@example.test','2026-11-22T21:00:00Z',null,null,
  'provider_suppressed',repeat('d',64)
);
\echo C323_CROSS_STREAM_LIFECYCLE_FIRST_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
cross_stream_lifecycle_first_pid=$!
track_child "cross_stream_lifecycle_first_pid"
wait_for_marker "$cross_stream_lifecycle_first_pid" "$tmp/cross-stream-lifecycle-first.log" "C323_CROSS_STREAM_LIFECYCLE_FIRST_LOCK_HELD"
run_psql >"$tmp/cross-stream-removal-second.log" 2>&1 <<'SQL' &
set role service_role;
select public.record_delivery_provider_suppression_event(
  'evt_c323_concurrent_later_add','suppression.added','sup_c323_concurrent_later',
  'c323-cross-stream-lifecycle-first@example.test','manual',null,
  '2026-11-22T21:01:00Z','2026-11-22T21:02:00Z',repeat('e',64)
);
select public.record_delivery_provider_suppression_event(
  'evt_c323_concurrent_later_remove','suppression.removed','sup_c323_concurrent_later',
  'c323-cross-stream-lifecycle-first@example.test','manual',null,
  '2026-11-22T21:01:00Z','2026-11-22T21:03:00Z',repeat('f',64)
);
reset role;
SQL
cross_stream_removal_second_pid=$!
track_child "cross_stream_removal_second_pid"
cross_stream_waiting="0"
for _ in {1..100}; do
  cross_stream_waiting="$(psql_scalar "select count(*) from pg_stat_activity where wait_event_type='Lock' and wait_event='advisory' and query like '%evt_c323_concurrent_later_add%'")"
  if [[ "$cross_stream_waiting" == "1" ]]; then break; fi
  sleep 0.05
done
if [[ "$cross_stream_waiting" != "1" ]]; then
  cat "$tmp/cross-stream-removal-second.log"
  echo "Later provider suppression events did not wait on the lifecycle address lock." >&2
  exit 1
fi
wait "$cross_stream_lifecycle_first_pid"
if ! wait "$cross_stream_removal_second_pid"; then
  cat "$tmp/cross-stream-removal-second.log"
  exit 1
fi
cross_stream_lifecycle_state="$(psql_scalar "select is_active::text from public.delivery_provider_suppression_state where recipient_email='c323-cross-stream-lifecycle-first@example.test'")"
cross_stream_lifecycle_hold="$(psql_scalar "select count(*) from public.delivery_provider_suppressions where recipient_email='c323-cross-stream-lifecycle-first@example.test'")"
[[ "$cross_stream_lifecycle_state" == "false" ]]
[[ "$cross_stream_lifecycle_hold" == "0" ]]
echo "Concurrent cross-stream lifecycle-first ordering: PASS"
# Older manual removal processed first, followed by newer lifecycle evidence: the hold must remain.
run_psql >"$tmp/c331-removal-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_suppression_event(
  'evt_c331_concurrent_removal_first_add','suppression.added','sup_c331_concurrent_removal_first',
  'c331-concurrent-removal-first@example.test','manual',null,
  '2027-03-02T13:00:00Z','2027-03-02T13:01:00Z',repeat('a',64)
);
select public.record_delivery_provider_suppression_event(
  'evt_c331_concurrent_removal_first_remove','suppression.removed','sup_c331_concurrent_removal_first',
  'c331-concurrent-removal-first@example.test','manual',null,
  '2027-03-02T13:00:00Z','2027-03-02T13:02:00Z',repeat('b',64)
);
\echo C331_CROSS_STREAM_OLDER_REMOVAL_FIRST_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
c331_removal_first_pid=$!
track_child "c331_removal_first_pid"
wait_for_marker "$c331_removal_first_pid" "$tmp/c331-removal-first.log" "C331_CROSS_STREAM_OLDER_REMOVAL_FIRST_LOCK_HELD"
run_psql >"$tmp/c331-lifecycle-second.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  'evt_c331_concurrent_newer_lifecycle_after_removal','email.suppressed','resend_c331_concurrent_newer_after_removal',
  'c331-concurrent-removal-first@example.test','2027-03-02T13:03:00Z',null,null,
  'provider_suppressed',repeat('c',64)
);
commit;
reset role;
SQL
c331_lifecycle_second_pid=$!
track_child "c331_lifecycle_second_pid"
c331_waiting="0"
for _ in {1..100}; do
  c331_waiting="$(psql_scalar "select count(*) from pg_stat_activity where wait_event_type='Lock' and wait_event='advisory' and query like '%evt_c331_concurrent_newer_lifecycle_after_removal%'")"
  if [[ "$c331_waiting" == "1" ]]; then break; fi
  sleep 0.05
done
if [[ "$c331_waiting" != "1" ]]; then
  cat "$tmp/c331-lifecycle-second.log"
  echo "Newer lifecycle event did not wait on the recipient advisory lock." >&2
  exit 1
fi
wait "$c331_removal_first_pid"
if ! wait "$c331_lifecycle_second_pid"; then
  cat "$tmp/c331-lifecycle-second.log"
  exit 1
fi
c331_removal_first_state="$(psql_scalar "select is_active::text from public.delivery_provider_suppression_state where recipient_email='c331-concurrent-removal-first@example.test'")"
c331_removal_first_hold="$(psql_scalar "select reason from public.delivery_provider_suppressions where recipient_email='c331-concurrent-removal-first@example.test'")"
[[ "$c331_removal_first_state" == "false" ]]
[[ "$c331_removal_first_hold" == "provider_suppressed" ]]
echo "Concurrent older removal-first timestamp ordering: PASS"

# Newer lifecycle evidence processed first, followed by an older manual removal: the hold must remain.
run_psql >"$tmp/c331-lifecycle-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_lifecycle_event(
  'evt_c331_concurrent_newer_lifecycle_first','email.suppressed','resend_c331_concurrent_newer_first',
  'c331-concurrent-lifecycle-first@example.test','2027-03-02T14:03:00Z',null,null,
  'provider_suppressed',repeat('d',64)
);
\echo C331_CROSS_STREAM_NEWER_LIFECYCLE_FIRST_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
c331_lifecycle_first_pid=$!
track_child "c331_lifecycle_first_pid"
wait_for_marker "$c331_lifecycle_first_pid" "$tmp/c331-lifecycle-first.log" "C331_CROSS_STREAM_NEWER_LIFECYCLE_FIRST_LOCK_HELD"
run_psql >"$tmp/c331-removal-second.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select public.record_delivery_provider_suppression_event(
  'evt_c331_concurrent_old_manual_add','suppression.added','sup_c331_concurrent_old_manual',
  'c331-concurrent-lifecycle-first@example.test','manual',null,
  '2027-03-02T14:00:00Z','2027-03-02T14:01:00Z',repeat('e',64)
);
select public.record_delivery_provider_suppression_event(
  'evt_c331_concurrent_old_manual_remove','suppression.removed','sup_c331_concurrent_old_manual',
  'c331-concurrent-lifecycle-first@example.test','manual',null,
  '2027-03-02T14:00:00Z','2027-03-02T14:02:00Z',repeat('f',64)
);
commit;
reset role;
SQL
c331_removal_second_pid=$!
track_child "c331_removal_second_pid"
c331_waiting="0"
for _ in {1..100}; do
  c331_waiting="$(psql_scalar "select count(*) from pg_stat_activity where wait_event_type='Lock' and wait_event='advisory' and query like '%evt_c331_concurrent_old_manual_add%'")"
  if [[ "$c331_waiting" == "1" ]]; then break; fi
  sleep 0.05
done
if [[ "$c331_waiting" != "1" ]]; then
  cat "$tmp/c331-removal-second.log"
  echo "Older manual suppression add did not wait on the recipient advisory lock." >&2
  exit 1
fi
wait "$c331_lifecycle_first_pid"
if ! wait "$c331_removal_second_pid"; then
  cat "$tmp/c331-removal-second.log"
  exit 1
fi
c331_lifecycle_first_state="$(psql_scalar "select is_active::text from public.delivery_provider_suppression_state where recipient_email='c331-concurrent-lifecycle-first@example.test'")"
c331_lifecycle_first_hold="$(psql_scalar "select reason from public.delivery_provider_suppressions where recipient_email='c331-concurrent-lifecycle-first@example.test'")"
[[ "$c331_lifecycle_first_state" == "false" ]]
[[ "$c331_lifecycle_first_hold" == "provider_suppressed" ]]
echo "Concurrent newer lifecycle-first timestamp ordering: PASS"


# Two first-insert requests with one event ID must serialize before recipient state is inspected.
run_psql >"$tmp/c356-simultaneous-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext('evt_c356_simultaneous_first_insert'));
select public.record_delivery_provider_lifecycle_event(
  'evt_c356_simultaneous_first_insert','email.bounced','resend-c356-first-insert',
  'c356-first-insert@example.test','2027-03-02T15:00:00Z','Permanent',null,
  null,repeat('1',64)
);
\echo C356_SIMULTANEOUS_FIRST_INSERT_EVENT_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
c356_first_pid=$!
track_child "c356_first_pid"
wait_for_marker "$c356_first_pid" "$tmp/c356-simultaneous-first.log" "C356_SIMULTANEOUS_FIRST_INSERT_EVENT_LOCK_HELD"
psql_service_scalar "select public.record_delivery_provider_lifecycle_event(
  'evt_c356_simultaneous_first_insert','email.complained','resend-c356-second-insert',
  'c356-second-insert@example.test','2027-03-02T15:01:00Z',null,null,
  null,repeat('2',64)
)" >"$tmp/c356-simultaneous-second.log" 2>&1 &
c356_second_pid=$!
track_child "c356_second_pid"
c356_waiting="0"
for _ in {1..100}; do
  c356_waiting="$(psql_scalar "select count(*) from pg_stat_activity where wait_event_type='Lock' and wait_event='advisory' and query like '%evt_c356_simultaneous_first_insert%'")"
  if [[ "$c356_waiting" == "1" ]]; then break; fi
  sleep 0.05
done
if [[ "$c356_waiting" != "1" ]]; then
  cat "$tmp/c356-simultaneous-second.log"
  echo "Simultaneous first insert did not wait on the global event-ID advisory lock." >&2
  exit 1
fi
wait "$c356_first_pid"
if ! wait "$c356_second_pid"; then
  cat "$tmp/c356-simultaneous-second.log"
  exit 1
fi
[[ "$(tr -d '\r\n' <"$tmp/c356-simultaneous-second.log")" == "__NULL__" ]]
[[ "$(psql_scalar "select count(*) from public.delivery_provider_events where event_id='evt_c356_simultaneous_first_insert'")" == "1" ]]
[[ "$(psql_scalar "select count(*) from public.delivery_provider_suppressions where recipient_email='c356-first-insert@example.test' and reason='permanent_bounce'")" == "1" ]]
[[ "$(psql_scalar "select count(*) from public.delivery_provider_suppressions where recipient_email='c356-second-insert@example.test'")" == "0" ]]
[[ "$(psql_scalar "select count(*) from public.delivery_provider_integrity_conflict_evidence where event_id='evt_c356_simultaneous_first_insert' and stored_recipient_email='c356-first-insert@example.test' and recipient_email='c356-second-insert@example.test'")" == "1" ]]
echo "Concurrent simultaneous first-insert event-ID conflict: PASS"

# The seven-argument legacy wrapper locks the event ID before its historical timestamp lookup.
run_psql >"$tmp/c356-legacy-lock-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext('evt_historical_026_complaint'));
\echo C356_LEGACY_EVENT_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
c356_legacy_first_pid=$!
track_child "c356_legacy_first_pid"
wait_for_marker "$c356_legacy_first_pid" "$tmp/c356-legacy-lock-first.log" "C356_LEGACY_EVENT_LOCK_HELD"
psql_service_scalar "select public.record_delivery_provider_lifecycle_event(
  'evt_historical_026_complaint','email.complained','resend-historical-026-complaint',
  'historical-026-complaint@example.test','2027-03-01T09:15:00Z',null,null
)" >"$tmp/c356-legacy-lock-second.log" 2>&1 &
c356_legacy_second_pid=$!
track_child "c356_legacy_second_pid"
c356_legacy_waiting="0"
for _ in {1..100}; do
  c356_legacy_waiting="$(psql_scalar "select count(*) from pg_stat_activity where wait_event_type='Lock' and wait_event='advisory' and query like '%evt_historical_026_complaint%'")"
  if [[ "$c356_legacy_waiting" == "1" ]]; then break; fi
  sleep 0.05
done
if [[ "$c356_legacy_waiting" != "1" ]]; then
  cat "$tmp/c356-legacy-lock-second.log"
  echo "Legacy seven-argument wrapper did not wait on the event-ID lock before reading." >&2
  exit 1
fi
wait "$c356_legacy_first_pid"
if ! wait "$c356_legacy_second_pid"; then cat "$tmp/c356-legacy-lock-second.log"; exit 1; fi
[[ "$(tr -d '\r\n' <"$tmp/c356-legacy-lock-second.log")" == "f" ]]
[[ "$(psql_scalar "select count(*) from public.delivery_provider_events where event_id='evt_historical_026_complaint'")" == "1" ]]
echo "Legacy seven-argument lifecycle wrapper event-ID-first locking: PASS"

# The eight-argument compatibility wrapper uses the same lock order on a historical fingerprint-less row.
run_psql >"$tmp/c356-compat-lock-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext('evt_historical_025_suppressed'));
\echo C356_COMPAT_EVENT_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
c356_compat_first_pid=$!
track_child "c356_compat_first_pid"
wait_for_marker "$c356_compat_first_pid" "$tmp/c356-compat-lock-first.log" "C356_COMPAT_EVENT_LOCK_HELD"
psql_service_scalar "select public.record_delivery_provider_lifecycle_event(
  'evt_historical_025_suppressed','email.suppressed','resend-historical-025-suppressed',
  'historical-025-suppressed@example.test','2027-03-01T09:00:00Z',null,null,'provider_suppressed'
)" >"$tmp/c356-compat-lock-second.log" 2>&1 &
c356_compat_second_pid=$!
track_child "c356_compat_second_pid"
c356_compat_waiting="0"
for _ in {1..100}; do
  c356_compat_waiting="$(psql_scalar "select count(*) from pg_stat_activity where wait_event_type='Lock' and wait_event='advisory' and query like '%evt_historical_025_suppressed%'")"
  if [[ "$c356_compat_waiting" == "1" ]]; then break; fi
  sleep 0.05
done
if [[ "$c356_compat_waiting" != "1" ]]; then
  cat "$tmp/c356-compat-lock-second.log"
  echo "Eight-argument compatibility wrapper did not wait on the event-ID lock." >&2
  exit 1
fi
wait "$c356_compat_first_pid"
if ! wait "$c356_compat_second_pid"; then cat "$tmp/c356-compat-lock-second.log"; exit 1; fi
[[ "$(tr -d '\r\n' <"$tmp/c356-compat-lock-second.log")" == "f" ]]
[[ "$(psql_scalar "select count(*) from public.delivery_provider_events where event_id='evt_historical_025_suppressed'")" == "1" ]]
echo "Legacy eight-argument compatibility wrapper event-ID-first locking: PASS"

# The five-argument record_delivery_provider_event wrapper locks before delegating and preserves the historical event.
run_psql >"$tmp/c356-legacy-event-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext('evt_historical_025_suppressed'));
\echo C356_LEGACY_EVENT_WRAPPER_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
c356_legacy_event_first_pid=$!
track_child "c356_legacy_event_first_pid"
wait_for_marker "$c356_legacy_event_first_pid" "$tmp/c356-legacy-event-first.log" "C356_LEGACY_EVENT_WRAPPER_LOCK_HELD"
psql_service_scalar "select public.record_delivery_provider_event(
  'evt_historical_025_suppressed','email.suppressed','resend-c356-legacy-event-attacker',
  'c356-legacy-event-attacker@example.test',null
)" >"$tmp/c356-legacy-event-second.log" 2>&1 &
c356_legacy_event_second_pid=$!
track_child "c356_legacy_event_second_pid"
c356_legacy_event_waiting="0"
for _ in {1..100}; do
  c356_legacy_event_waiting="$(psql_scalar "select count(*) from pg_stat_activity where wait_event_type='Lock' and wait_event='advisory' and query like '%evt_historical_025_suppressed%'")"
  if [[ "$c356_legacy_event_waiting" == "1" ]]; then break; fi
  sleep 0.05
done
if [[ "$c356_legacy_event_waiting" != "1" ]]; then
  cat "$tmp/c356-legacy-event-second.log"
  echo "Five-argument legacy event wrapper did not wait on the event-ID lock." >&2
  exit 1
fi
wait "$c356_legacy_event_first_pid"
if ! wait "$c356_legacy_event_second_pid"; then cat "$tmp/c356-legacy-event-second.log"; exit 1; fi
[[ "$(tr -d '\r\n' <"$tmp/c356-legacy-event-second.log")" == "__NULL__" ]]
[[ "$(psql_scalar "select count(*) from public.delivery_provider_events where event_id='evt_historical_025_suppressed'")" == "1" ]]
[[ "$(psql_scalar "select count(*) from public.delivery_provider_events where recipient_email='c356-legacy-event-attacker@example.test'")" == "0" ]]
[[ "$(psql_scalar "select count(*) from public.delivery_provider_integrity_conflict_evidence where event_id='evt_historical_025_suppressed' and recipient_email='c356-legacy-event-attacker@example.test' and stored_recipient_email='historical-025-suppressed@example.test'")" == "1" ]]
echo "Five-argument legacy event wrapper event-ID-first locking: PASS"
# Suppression-list first inserts share the same global event-ID lock namespace as lifecycle events.
run_psql >"$tmp/c356-suppression-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
select pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext('evt_c356_suppression_first_insert'));
select public.record_delivery_provider_suppression_event(
  'evt_c356_suppression_first_insert','suppression.added','sup-c356-first',
  'c356-suppression-first@example.test','manual',null,
  '2027-03-02T15:20:00Z','2027-03-02T15:21:00Z',repeat('3',64)
);
\echo C356_SUPPRESSION_FIRST_INSERT_EVENT_LOCK_HELD
select pg_sleep(2);
commit;
reset role;
SQL
c356_suppression_first_pid=$!
track_child "c356_suppression_first_pid"
wait_for_marker "$c356_suppression_first_pid" "$tmp/c356-suppression-first.log" "C356_SUPPRESSION_FIRST_INSERT_EVENT_LOCK_HELD"
psql_service_scalar "select public.record_delivery_provider_suppression_event(
  'evt_c356_suppression_first_insert','suppression.removed','sup-c356-second',
  'c356-suppression-second@example.test','manual',null,
  '2027-03-02T15:20:00Z','2027-03-02T15:22:00Z',repeat('4',64)
)" >"$tmp/c356-suppression-second.log" 2>&1 &
c356_suppression_second_pid=$!
track_child "c356_suppression_second_pid"
c356_suppression_waiting="0"
for _ in {1..100}; do
  c356_suppression_waiting="$(psql_scalar "select count(*) from pg_stat_activity where wait_event_type='Lock' and wait_event='advisory' and query like '%evt_c356_suppression_first_insert%'")"
  if [[ "$c356_suppression_waiting" == "1" ]]; then break; fi
  sleep 0.05
done
if [[ "$c356_suppression_waiting" != "1" ]]; then
  cat "$tmp/c356-suppression-second.log"
  echo "Suppression callback did not wait on the shared event-ID lock." >&2
  exit 1
fi
wait "$c356_suppression_first_pid"
if ! wait "$c356_suppression_second_pid"; then
  cat "$tmp/c356-suppression-second.log"
  exit 1
fi
[[ "$(tr -d '\r\n' <"$tmp/c356-suppression-second.log")" == "__NULL__" ]]
[[ "$(psql_scalar "select count(*) from public.delivery_provider_events where event_id='evt_c356_suppression_first_insert'")" == "1" ]]
[[ "$(psql_scalar "select count(*) from public.delivery_provider_suppression_state where recipient_email='c356-suppression-first@example.test' and is_active")" == "1" ]]
[[ "$(psql_scalar "select count(*) from public.delivery_provider_suppression_state where recipient_email='c356-suppression-second@example.test'")" == "0" ]]
[[ "$(psql_scalar "select count(*) from public.delivery_provider_integrity_conflict_evidence where event_id='evt_c356_suppression_first_insert' and stored_recipient_email='c356-suppression-first@example.test' and recipient_email='c356-suppression-second@example.test'")" == "1" ]]
echo "Concurrent suppression first-insert event-ID conflict: PASS"

# A controlled event-ID advisory-lock conflict must fail as PostgreSQL lock_not_available (55P03).
run_psql >"$tmp/c362-lock-holder.log" 2>&1 <<'SQL' &
begin;
select pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext('evt_c362_bounded_lock_timeout'));
\\echo C362_LOCK_TIMEOUT_HOLDER_READY
select pg_sleep(3);
rollback;
SQL
c362_lock_holder_pid=$!
track_child "$c362_lock_holder_pid"
wait_for_marker "$c362_lock_holder_pid" "$tmp/c362-lock-holder.log" "C362_LOCK_TIMEOUT_HOLDER_READY"

set +e
run_psql >"$tmp/c362-lock-timeout.log" 2>&1 <<'SQL'
begin;
set role service_role;
do $c362_expected_lock_timeout$
begin
  perform set_config('lock_timeout', '250ms', true);
  perform public.record_delivery_provider_lifecycle_event(
    'evt_c362_bounded_lock_timeout',
    'email.delivered',
    'resend-c362-bounded-lock-timeout',
    'c362-bounded-lock-timeout@example.test',
    '2027-03-02T16:00:00Z',
    null,
    null,
    null,
    repeat('5', 64)
  );
  raise exception 'Expected advisory-lock timeout was not raised.';
exception
  when lock_not_available then
    if SQLSTATE <> '55P03' then
      raise exception 'Unexpected PostgreSQL lock failure classification: %', SQLSTATE;
    end if;
    raise notice 'C362_EXPECTED_LOCK_TIMEOUT_SQLSTATE=%', SQLSTATE;
end
$c362_expected_lock_timeout$;
rollback;
SQL
c362_timeout_status=$?
set -e
if [[ "$c362_timeout_status" != "0" ]] || ! grep -Fq "C362_EXPECTED_LOCK_TIMEOUT_SQLSTATE=55P03" "$tmp/c362-lock-timeout.log"; then
  cat "$tmp/c362-lock-timeout.log" >&2
  echo "Controlled advisory-lock conflict did not fail with SQLSTATE 55P03." >&2
  exit 1
fi
wait_bounded "$c362_lock_holder_pid" "c362 lock-timeout holder"
[[ "$(psql_scalar "select count(*) from public.delivery_provider_events where event_id='evt_c362_bounded_lock_timeout'")" == "0" ]]
echo "Bounded advisory-lock conflict SQLSTATE 55P03 and unchanged database state: PASS"
echo "Concurrency test process deadlines, bounded waits, and cleanup watchdog: ENABLED"
