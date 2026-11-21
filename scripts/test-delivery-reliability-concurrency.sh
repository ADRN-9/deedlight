#!/usr/bin/env bash
set -euo pipefail
psql_cmd=(psql -X -v ON_ERROR_STOP=1 --host 127.0.0.1 --port 5432 --username postgres --dbname deedlight_reliability_test)
psql_scalar() {
  "${psql_cmd[@]}" --quiet --no-align --tuples-only --pset=null=__NULL__ --command="$1"
}
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

wait_for_marker() {
  local pid="$1" file="$2" marker="$3"
  for _ in {1..100}; do
    if grep -q "$marker" "$file"; then return 0; fi
    if ! kill -0 "$pid" 2>/dev/null; then cat "$file"; return 1; fi
    sleep 0.05
  done
  cat "$file"
  return 1
}
wait_for_row_lock_wait() {
  local app_name="$1" pid="$2" file="$3"
  for _ in {1..100}; do
    local waiting
    waiting="$(psql_scalar "select count(*) from pg_stat_activity where application_name='$app_name' and wait_event_type='Lock'")"
    if [[ "$waiting" == "1" ]]; then return 0; fi
    if ! kill -0 "$pid" 2>/dev/null; then cat "$file"; return 1; fi
    sleep 0.05
  done
  cat "$file"
  echo "Timed out waiting for $app_name to block on the ledger row lock." >&2
  return 1
}

"${psql_cmd[@]}" <<'SQL'
insert into public.weekly_goodness_features (week_start)
select date_trunc('week', current_date::timestamp)::date + (n * 7)
from generate_series(0, 3) as n
on conflict (week_start) do nothing;

insert into public.delivery_ledger (
  id, user_id, kind, delivery_key, state, scheduled_for,
  claim_token, claimed_at, claim_expires_at, attempt_count
)
select
  ('70000000-0000-0000-0000-' || lpad((n + 1)::text, 12, '0'))::uuid,
  '00000000-0000-0000-0000-000000000002',
  'weekly_newsletter',
  'weekly:' || (date_trunc('week', current_date::timestamp)::date + (n * 7))::text,
  'claimed',
  clock_timestamp() - interval '1 minute',
  ('60000000-0000-0000-0000-' || lpad((n + 1)::text, 12, '0'))::uuid,
  clock_timestamp(),
  clock_timestamp() + interval '1 second',
  1
from generate_series(0, 3) as n;
SQL

run_expired_transition() {
  local name="$1" job_id="$2" token="$3" call="$4"
  local holder_log="$tmp/$name-holder.log"
  local candidate_log="$tmp/$name-candidate.log"
  local app_name="F01_$name"

  "${psql_cmd[@]}" >"$holder_log" 2>&1 <<SQL &
begin;
select id from public.delivery_ledger where id='$job_id' for update;
\echo ${app_name}_LOCK_HELD
select pg_sleep(2);
commit;
SQL
  local holder_pid=$!
  wait_for_marker "$holder_pid" "$holder_log" "${app_name}_LOCK_HELD"

  "${psql_cmd[@]}" >"$candidate_log" 2>&1 <<SQL &
set application_name = '$app_name';
set role service_role;
do \$expect_expired\$
begin
  $call
  raise exception 'F-01 regression: $name accepted a lease after lock contention.';
exception when sqlstate '42501' then
  null;
end;
\$expect_expired\$;
reset role;
SQL
  local candidate_pid=$!
  wait_for_row_lock_wait "$app_name" "$candidate_pid" "$candidate_log"
  wait "$holder_pid"
  wait "$candidate_pid"

  local state
  state="$(psql_scalar "select state || ':' || (claim_token = '$token')::text || ':' || (sent_at is null)::text || ':' || (failed_at is null)::text || ':' || (next_attempt_at is null)::text || ':' || (error_code is null)::text from public.delivery_ledger where id='$job_id'")"
  if [[ "$state" != "claimed:true:true:true:true:true" ]]; then
    echo "F-01 regression: $name changed an expired claim: $state" >&2
    cat "$candidate_log" >&2
    exit 1
  fi
  echo "Expired lease after row-lock contention ($name): PASS"
}

run_expired_transition authorize_delivery_job   70000000-0000-0000-0000-000000000001 60000000-0000-0000-0000-000000000001   "if public.authorize_delivery_job('70000000-0000-0000-0000-000000000001','60000000-0000-0000-0000-000000000001') is not true then raise exception 'Unexpected authorization result.'; end if;"
run_expired_transition retry_delivery_job   70000000-0000-0000-0000-000000000002 60000000-0000-0000-0000-000000000002   "if public.retry_delivery_job('70000000-0000-0000-0000-000000000002','60000000-0000-0000-0000-000000000002',clock_timestamp() + interval '5 minutes','lock_wait_retry') is not true then raise exception 'Unexpected retry result.'; end if;"
run_expired_transition mark_delivery_sent   70000000-0000-0000-0000-000000000003 60000000-0000-0000-0000-000000000003   "if public.mark_delivery_sent('70000000-0000-0000-0000-000000000003','60000000-0000-0000-0000-000000000003','lock-wait-provider-id') is not true then raise exception 'Unexpected sent result.'; end if;"
run_expired_transition mark_delivery_failed   70000000-0000-0000-0000-000000000004 60000000-0000-0000-0000-000000000004   "if public.mark_delivery_failed('70000000-0000-0000-0000-000000000004','60000000-0000-0000-0000-000000000004','lock_wait_failure') is not true then raise exception 'Unexpected failed result.'; end if;"
echo "Delivery lease lock-contention concurrency assertions: PASS"
