#!/usr/bin/env bash
set -euo pipefail
set +x

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

# This matrix is CI-only and may connect only to its own disposable PostgreSQL 16 service.
[[ "${GITHUB_ACTIONS:-}" == "true" ]] || fail "GitHub Actions is required."
[[ "${GITHUB_REPOSITORY:-}" == "ADRN-9/deedlight" ]] || fail "Unexpected repository."
[[ "${GITHUB_EVENT_NAME:-}" == "push" || "${GITHUB_EVENT_NAME:-}" == "pull_request" ]] || fail "Unexpected workflow event."
[[ "${DEEDLIGHT_C253_CI_ONLY:-}" == "true" ]] || fail "Missing C253 CI-only acknowledgement."
[[ "${DELIVERY_ENABLED:-false}" == "false" ]] || fail "Outbound delivery must remain disabled."
[[ "${PGPASSWORD:-}" == "postgres" ]] || fail "Disposable PostgreSQL service password identity mismatch."
[[ "${PGHOST:-127.0.0.1}" == "127.0.0.1" ]] || fail "Unexpected PostgreSQL host."
[[ "${PGPORT:-5432}" == "5432" ]] || fail "Unexpected PostgreSQL port."
[[ "${PGUSER:-postgres}" == "postgres" ]] || fail "Unexpected PostgreSQL role."
case "${GITHUB_REF:-}" in
  refs/heads/security/delivery-final-authorization-concurrency-c253|refs/pull/[0-9]*/merge) ;;
  *) fail "C253 may run only on its implementation branch or its pull-request merge ref." ;;
esac

for envname in PGHOSTADDR PGSERVICE PGSERVICEFILE PGSYSCONFDIR PGPASSFILE PGOPTIONS PGDATABASE \
  PGSSLMODE PGSSLCERT PGSSLKEY PGSSLROOTCERT PGSSLCRL PGREQUIRESSL PGGSSENCMODE \
  PGTARGETSESSIONATTRS PGCONNECT_TIMEOUT PGCHANNELBINDING PGAPPNAME; do
  if [[ -n "$(printenv "$envname" 2>/dev/null || true)" ]]; then
    fail "Refusing libpq override $envname."
  fi
done
for envname in DATABASE_URL SUPABASE_URL SUPABASE_PROJECT_REF SUPABASE_ACCESS_TOKEN \
  SUPABASE_DB_PASSWORD SUPABASE_SERVICE_ROLE_KEY CLOUDFLARE_API_TOKEN \
  CLOUDFLARE_ACCOUNT_ID RESEND_API_KEY RESEND_WEBHOOK_SECRET DELIVERY_FROM_EMAIL; do
  if [[ -n "$(printenv "$envname" 2>/dev/null || true)" ]]; then
    fail "Refusing Production credential/configuration variable $envname."
  fi
done

command -v docker >/dev/null || fail "Docker is required to attest the disposable service."
command -v psql >/dev/null || fail "PostgreSQL client is required."
postgres_container="$(docker ps --filter ancestor=postgres:16 --format '{{.ID}}')"
[[ -n "$postgres_container" ]] || fail "A running postgres:16 service container is required."
[[ "$(printf '%s\n' "$postgres_container" | wc -l | tr -d ' ')" == "1" ]] \
  || fail "Exactly one running postgres:16 service container is required."
docker port "$postgres_container" 5432/tcp | grep -Eq '(^|:)5432$' \
  || fail "Disposable PostgreSQL service is not publishing port 5432."

psql_exec() {
  command psql -X -v ON_ERROR_STOP=1 --host 127.0.0.1 --port 5432 --username postgres --dbname deedlight_migration_order_test "$@"
}
psql_scalar() {
  psql_exec --quiet --no-align --tuples-only --pset=null=__NULL__ --command="$1"
}

db_name="$(psql_scalar "select current_database()")"
db_role="$(psql_scalar "select current_user")"
pg_major="$(psql_scalar "select current_setting('server_version_num')::integer / 10000")"
[[ "$db_name" == "deedlight_migration_order_test" && "$db_role" == "postgres" && "$pg_major" == "16" ]] \
  || fail "Connected database identity is not the expected disposable PostgreSQL 16 fixture."
sql_sleep_pattern='pg_'
sql_sleep_pattern+='sleep('
if grep -Fq "$sql_sleep_pattern" "$0"; then
  fail "Fixed SQL sleep barriers are prohibited; wait for observed PostgreSQL lock state instead."
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

wait_for_marker() {
  local pid="$1" log="$2" marker="$3"
  for _ in {1..400}; do
    if grep -Fq -- "$marker" "$log"; then return 0; fi
    if ! kill -0 "$pid" 2>/dev/null; then
      cat "$log" >&2
      return 1
    fi
    sleep 0.025
  done
  cat "$log" >&2
  echo "Timed out waiting for session marker $marker." >&2
  return 1
}

wait_for_lock_wait() {
  local waiter_app="$1" holder_app="$2" waiter_pid="$3" log="$4" expected_event=""
  if [[ "$#" -ge 5 ]]; then expected_event="$5"; fi
  local query
  query="select exists (
    select 1
    from pg_stat_activity waiter
    cross join lateral unnest(pg_blocking_pids(waiter.pid)) blocker(pid)
    join pg_stat_activity holder on holder.pid = blocker.pid
    where waiter.application_name = '$waiter_app'
      and waiter.wait_event_type = 'Lock'
      and holder.application_name = '$holder_app'
      and ('$expected_event' = '' or waiter.wait_event = '$expected_event')
  )"
  for _ in {1..400}; do
    if [[ "$(psql_scalar "$query")" == "t" ]]; then return 0; fi
    if ! kill -0 "$waiter_pid" 2>/dev/null; then
      cat "$log" >&2
      echo "Waiter $waiter_app exited before the expected lock wait." >&2
      return 1
    fi
    sleep 0.025
  done
  cat "$log" >&2
  echo "No observed pg_stat_activity lock wait from $waiter_app to $holder_app." >&2
  return 1
}

wait_until_claim_expired() {
  local job="$1" waiter_pid="$2" log="$3"
  for _ in {1..400}; do
    if [[ "$(psql_scalar "select claim_expires_at <= clock_timestamp() from public.delivery_ledger where id='$job'")" == "t" ]]; then
      return 0
    fi
    if ! kill -0 "$waiter_pid" 2>/dev/null; then
      cat "$log" >&2
      echo "Authorization waiter exited before its claim expired." >&2
      return 1
    fi
    sleep 0.025
  done
  cat "$log" >&2
  echo "Claim did not expire while the authorization session was blocked." >&2
  return 1
}

wait_for_session_gone() {
  local app="$1"
  for _ in {1..200}; do
    if [[ "$(psql_scalar "select count(*) = 0 from pg_stat_activity where application_name='$app'")" == "t" ]]; then
      return 0
    fi
    sleep 0.025
  done
  fail "PostgreSQL backend $app did not terminate."
}

start_fifo_session() {
  local fifo="$1" log="$2"
  mkfifo "$fifo"
  psql_exec --quiet --no-align --tuples-only <"$fifo" >"$log" 2>&1 &
  SESSION_PID=$!
  exec {SESSION_FD}>"$fifo"
  SESSION_FIFO="$fifo"
}

send_fd() {
  local fd="$1" sql="$2"
  printf '%s\n' "$sql" >&"$fd"
}

close_fd() {
  local fd="$1"
  exec {fd}>&-
}

finish_fifo_session() {
  local fd="$1" pid="$2" log="$3" final_sql="COMMIT;"
  if [[ "$#" -ge 4 ]]; then final_sql="$4"; fi
  send_fd "$fd" "$final_sql"
  send_fd "$fd" '\q'
  close_fd "$fd"
  if ! wait "$pid"; then
    cat "$log" >&2
    return 1
  fi
}

start_background_sql() {
  local app="$1" log="$2" sql="$3"
  psql_exec --quiet --no-align --tuples-only \
    --command="BEGIN; SET application_name = '$app'; $sql; COMMIT;" >"$log" 2>&1 &
  SQL_PID=$!
}

job_id() { printf '30000000-0000-0000-0000-%012d' "$1"; }
user_id() { printf '50000000-0000-0000-0000-%012d' "$1"; }
claim_token() { printf '40000000-0000-0000-0000-%012d' "$1"; }
recipient_email() { printf 'c253-%04d@example.test' "$1"; }

assert_cancelled() {
  local id="$1"
  local result
  result="$(psql_scalar "select state = 'cancelled' and claim_token is null and claim_expires_at is null and transport_started_at is not null from public.delivery_ledger where id='$id'")"
  [[ "$result" == "t" ]] || fail "Denied authorization did not cancel and invalidate claim $id."
}

assert_claimed() {
  local id="$1" token="$2"
  local result
  result="$(psql_scalar "select state = 'claimed' and claim_token = '$token' and claim_expires_at > clock_timestamp() and transport_started_at is not null from public.delivery_ledger where id='$id'")"
  [[ "$result" == "t" ]] || fail "Authorization-first or rollback path changed live claim $id."
}

assert_expired_claimed() {
  local id="$1" token="$2"
  local result
  result="$(psql_scalar "select state = 'claimed' and claim_token = '$token' and claim_expires_at <= clock_timestamp() from public.delivery_ledger where id='$id'")"
  [[ "$result" == "t" ]] || fail "Expired lock-wait claim $id was mutated or retained a live lease."
}

assert_no_provider_attempt() {
  local id="$1"
  [[ "$(psql_scalar "select count(*) from public.c253_provider_attempts where job_id='$id'")" == "0" ]] \
    || fail "A provider attempt was recorded after denied authorization for $id."
}

record_provider_attempt() {
  local id="$1" label="$2"
  psql_exec --quiet --command="
    insert into public.c253_provider_attempts(job_id, attempt_label, idempotency_key)
    select id, '$label', 'deedlight/' || kind || '/' || id::text
    from public.delivery_ledger
    where id = '$id'
      and state = 'claimed'
    "
}

assert_mutation() {
  local query="$1" label="$2"
  [[ "$(psql_scalar "$query")" == "t" ]] || fail "Concurrent mutation did not commit: $label."
}

run_row_lock_first() {
  local name="$1" n="$2" mutation_sql="$3" mutation_check="$4" wait_event=""
  if [[ "$#" -ge 5 ]]; then wait_event="$5"; fi
  local id token email holder_app waiter_app holder_log waiter_log fifo result
  id="$(job_id "$n")"
  token="$(claim_token "$n")"
  email="$(recipient_email "$n")"
  holder_app="c253-holder-$name"
  waiter_app="c253-waiter-$name"
  holder_log="$tmp/$name-holder.log"
  waiter_log="$tmp/$name-waiter.log"
  fifo="$tmp/$name-holder.fifo"

  start_fifo_session "$fifo" "$holder_log"
  local holder_pid="$SESSION_PID" holder_fd="$SESSION_FD"
  send_fd "$holder_fd" "BEGIN;"
  send_fd "$holder_fd" "SET application_name = '$holder_app';"
  send_fd "$holder_fd" "$mutation_sql"
  send_fd "$holder_fd" "\echo C253_HOLDER_READY_$name"
  wait_for_marker "$holder_pid" "$holder_log" "C253_HOLDER_READY_$name"

  start_background_sql "$waiter_app" "$waiter_log" \
    "SET ROLE service_role; SELECT public.authorize_delivery_idempotency_window('$id', '$token', '$email');"
  local waiter_pid="$SQL_PID"
  wait_for_lock_wait "$waiter_app" "$holder_app" "$waiter_pid" "$waiter_log" "$wait_event"

  finish_fifo_session "$holder_fd" "$holder_pid" "$holder_log" "COMMIT;"
  rm -f "$fifo"
  wait "$waiter_pid" || { cat "$waiter_log" >&2; fail "Authorization waiter failed for $name."; }

  result="$(grep -E '^(authorized|cancelled|expired)$' "$waiter_log" | tail -n 1 || true)"
  [[ "$result" == "cancelled" ]] || { cat "$waiter_log" >&2; fail "$name expected cancelled, got $result."; }
  assert_cancelled "$id"
  assert_mutation "$mutation_check" "$name"
  assert_no_provider_attempt "$id"
  echo "C253 $name: observed lock wait, cancelled, claim invalidated, zero provider attempts: PASS"
}

run_auth_lock_first() {
  local name="$1" n="$2" mutation_sql="$3" mutation_check="$4" wait_event=""
  if [[ "$#" -ge 5 ]]; then wait_event="$5"; fi
  local id token email auth_app mutation_app auth_log mutation_log fifo
  id="$(job_id "$n")"
  token="$(claim_token "$n")"
  email="$(recipient_email "$n")"
  auth_app="c253-auth-$name"
  mutation_app="c253-mutation-$name"
  auth_log="$tmp/$name-auth.log"
  mutation_log="$tmp/$name-mutation.log"
  fifo="$tmp/$name-auth.fifo"

  start_fifo_session "$fifo" "$auth_log"
  local auth_pid="$SESSION_PID" auth_fd="$SESSION_FD"
  send_fd "$auth_fd" "BEGIN;"
  send_fd "$auth_fd" "SET application_name = '$auth_app';"
  send_fd "$auth_fd" "SET ROLE service_role;"
  send_fd "$auth_fd" "SELECT public.authorize_delivery_idempotency_window('$id', '$token', '$email');"
  send_fd "$auth_fd" "\echo C253_AUTHORIZED_READY_$name"
  wait_for_marker "$auth_pid" "$auth_log" "C253_AUTHORIZED_READY_$name"
  grep -Fxq "authorized" "$auth_log" || { cat "$auth_log" >&2; fail "$name did not authorize before the mutation."; }

  start_background_sql "$mutation_app" "$mutation_log" "$mutation_sql"
  local mutation_pid="$SQL_PID"
  wait_for_lock_wait "$mutation_app" "$auth_app" "$mutation_pid" "$mutation_log" "$wait_event"

  finish_fifo_session "$auth_fd" "$auth_pid" "$auth_log" "COMMIT;"
  rm -f "$fifo"
  wait "$mutation_pid" || { cat "$mutation_log" >&2; fail "Later mutation failed for $name."; }

  assert_claimed "$id" "$token"
  assert_mutation "$mutation_check" "$name"
  record_provider_attempt "$id" "post-commit-$name"
  [[ "$(psql_scalar "select count(*) from public.c253_provider_attempts where job_id='$id'")" == "1" ]] \
    || fail "$name did not record exactly one authorized provider-attempt probe."
  echo "C253 $name: authorization committed first, mutation waited, later mutation did not revoke authorization: PASS"
}

# Unique synthetic fixtures; no existing delivery rows are deleted or cleaned up.
psql_exec <<'SQL'
create table public.c253_provider_attempts (
  job_id uuid not null,
  attempt_label text not null,
  idempotency_key text not null,
  attempted_at timestamptz not null default clock_timestamp(),
  primary key (job_id, attempt_label)
);

with fixtures(n, kind, week_start) as (
  values
    (2501, 'daily_reminder', null::date),
    (2502, 'daily_reminder', null::date),
    (2503, 'daily_reminder', null::date),
    (2504, 'daily_reminder', null::date),
    (2505, 'daily_reminder', null::date),
    (2506, 'daily_reminder', null::date),
    (2507, 'weekly_newsletter', date '2027-07-05'),
    (2508, 'weekly_newsletter', date '2027-07-12'),
    (2509, 'weekly_newsletter', date '2027-07-19'),
    (2510, 'weekly_newsletter', date '2027-07-26'),
    (2511, 'weekly_newsletter', date '2027-08-02'),
    (2512, 'daily_reminder', null::date),
    (2513, 'daily_reminder', null::date),
    (2514, 'daily_reminder', null::date),
    (2515, 'daily_reminder', null::date),
    (2516, 'daily_reminder', null::date),
    (2517, 'daily_reminder', null::date),
    (2518, 'daily_reminder', null::date),
    (2519, 'daily_reminder', null::date),
    (2520, 'daily_reminder', null::date)
)
insert into auth.users(id, email, email_confirmed_at)
select
  ('50000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'c253-' || lpad(n::text, 4, '0') || '@example.test',
  clock_timestamp()
from fixtures;

with fixtures(n) as (
  values (2501),(2502),(2503),(2504),(2505),(2506),(2507),(2508),(2509),(2510),
         (2511),(2512),(2513),(2514),(2515),(2516),(2517),(2518),(2519),(2520)
)
insert into public.profiles(user_id, is_suspended)
select ('50000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, false
from fixtures
on conflict (user_id) do update set is_suspended = false;

with fixtures(n, kind, week_start) as (
  values
    (2501, 'daily_reminder', null::date),(2502, 'daily_reminder', null::date),
    (2503, 'daily_reminder', null::date),(2504, 'daily_reminder', null::date),
    (2505, 'daily_reminder', null::date),(2506, 'daily_reminder', null::date),
    (2507, 'weekly_newsletter', date '2027-07-05'),
    (2508, 'weekly_newsletter', date '2027-07-12'),
    (2509, 'weekly_newsletter', date '2027-07-19'),
    (2510, 'weekly_newsletter', date '2027-07-26'),
    (2511, 'weekly_newsletter', date '2027-08-02'),
    (2512, 'daily_reminder', null::date),(2513, 'daily_reminder', null::date),
    (2514, 'daily_reminder', null::date),(2515, 'daily_reminder', null::date),
    (2516, 'daily_reminder', null::date),(2517, 'daily_reminder', null::date),
    (2518, 'daily_reminder', null::date),(2519, 'daily_reminder', null::date),
    (2520, 'daily_reminder', null::date)
)
insert into public.daily_reminder_preferences(user_id, daily_enabled, reminder_time, timezone)
select ('50000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, true, time '00:00', 'UTC'
from fixtures where kind = 'daily_reminder';

with fixtures(n, kind, week_start) as (
  values
    (2507, 'weekly_newsletter', date '2027-07-05'),
    (2508, 'weekly_newsletter', date '2027-07-12'),
    (2509, 'weekly_newsletter', date '2027-07-19'),
    (2510, 'weekly_newsletter', date '2027-07-26'),
    (2511, 'weekly_newsletter', date '2027-08-02')
)
insert into public.newsletter_preferences(user_id, weekly_enabled, consented_at, consent_source)
select
  ('50000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  true, clock_timestamp(), 'test'
from fixtures;

insert into public.weekly_goodness_features(week_start)
values (date '2027-07-05'),(date '2027-07-12'),(date '2027-07-19'),
       (date '2027-07-26'),(date '2027-08-02')
on conflict (week_start) do nothing;

with fixtures(n, kind, week_start) as (
  values
    (2501, 'daily_reminder', null::date),(2502, 'daily_reminder', null::date),
    (2503, 'daily_reminder', null::date),(2504, 'daily_reminder', null::date),
    (2505, 'daily_reminder', null::date),(2506, 'daily_reminder', null::date),
    (2507, 'weekly_newsletter', date '2027-07-05'),
    (2508, 'weekly_newsletter', date '2027-07-12'),
    (2509, 'weekly_newsletter', date '2027-07-19'),
    (2510, 'weekly_newsletter', date '2027-07-26'),
    (2511, 'weekly_newsletter', date '2027-08-02'),
    (2512, 'daily_reminder', null::date),(2513, 'daily_reminder', null::date),
    (2514, 'daily_reminder', null::date),(2515, 'daily_reminder', null::date),
    (2516, 'daily_reminder', null::date),(2517, 'daily_reminder', null::date),
    (2518, 'daily_reminder', null::date),(2519, 'daily_reminder', null::date),
    (2520, 'daily_reminder', null::date)
)
insert into public.delivery_ledger(
  id, user_id, kind, delivery_key, state, scheduled_for,
  claim_token, claimed_at, claim_expires_at, attempt_count,
  last_attempt_at, transport_started_at
)
select
  ('30000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  ('50000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  kind,
  case when kind = 'daily_reminder' then 'daily:2027-06-21' else 'weekly:' || week_start::text end,
  'claimed',
  case when kind = 'daily_reminder'
    then timestamptz '2027-06-21 00:00:00+00'
    else (week_start::timestamp + time '00:00') at time zone 'UTC'
  end,
  ('40000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  clock_timestamp(), clock_timestamp() + interval '10 minutes', 1,
  clock_timestamp(), clock_timestamp() - interval '1 minute'
from fixtures;

insert into public.delivery_ledger(
  id, user_id, kind, delivery_key, state, scheduled_for,
  claim_token, claimed_at, claim_expires_at, attempt_count,
  last_attempt_at, transport_started_at
)
values (
  '30000000-0000-0000-0000-000000002620',
  '50000000-0000-0000-0000-000000002520',
  'daily_reminder', 'daily:2027-06-22', 'claimed',
  timestamptz '2027-06-22 00:00:00+00',
  '40000000-0000-0000-0000-000000002620',
  clock_timestamp(), clock_timestamp() + interval '10 minutes', 1,
  clock_timestamp(), clock_timestamp() - interval '1 minute'
);
SQL

# Consent and member-state mutations win first; the real final RPC must wait, then cancel.
run_row_lock_first "daily-consent-first" 2501 \
  "UPDATE public.daily_reminder_preferences SET daily_enabled = false WHERE user_id = '$(user_id 2501)';" \
  "select not daily_enabled from public.daily_reminder_preferences where user_id = '$(user_id 2501)'"

run_auth_lock_first "daily-consent-auth-first" 2502 \
  "UPDATE public.daily_reminder_preferences SET daily_enabled = false WHERE user_id = '$(user_id 2502)';" \
  "select not daily_enabled from public.daily_reminder_preferences where user_id = '$(user_id 2502)'"

run_row_lock_first "weekly-consent-first" 2507 \
  "UPDATE public.newsletter_preferences SET weekly_enabled = false, consented_at = null WHERE user_id = '$(user_id 2507)';" \
  "select not weekly_enabled and consented_at is null from public.newsletter_preferences where user_id = '$(user_id 2507)'"

run_row_lock_first "profile-suspension-first" 2503 \
  "UPDATE public.profiles SET is_suspended = true WHERE user_id = '$(user_id 2503)';" \
  "select is_suspended from public.profiles where user_id = '$(user_id 2503)'"

run_auth_lock_first "profile-suspension-auth-first" 2504 \
  "UPDATE public.profiles SET is_suspended = true WHERE user_id = '$(user_id 2504)';" \
  "select is_suspended from public.profiles where user_id = '$(user_id 2504)'"

run_row_lock_first "auth-email-change-first" 2505 \
  "UPDATE auth.users SET email = 'changed-2505@example.test' WHERE id = '$(user_id 2505)';" \
  "select email = 'changed-2505@example.test' from auth.users where id = '$(user_id 2505)'"

run_auth_lock_first "auth-email-change-auth-first" 2506 \
  "UPDATE auth.users SET email = 'changed-2506@example.test' WHERE id = '$(user_id 2506)';" \
  "select email = 'changed-2506@example.test' from auth.users where id = '$(user_id 2506)'"

run_row_lock_first "weekly-curation-removal-first" 2508 \
  "DELETE FROM public.weekly_goodness_features WHERE week_start = date '2027-07-12';" \
  "select not exists (select 1 from public.weekly_goodness_features where week_start = date '2027-07-12')"

run_auth_lock_first "weekly-curation-auth-first" 2509 \
  "DELETE FROM public.weekly_goodness_features WHERE week_start = date '2027-07-19';" \
  "select not exists (select 1 from public.weekly_goodness_features where week_start = date '2027-07-19')"

complaint_first_sql() {
  printf "SET ROLE service_role; SELECT public.record_delivery_provider_lifecycle_event('evt_c253_complaint_%s', 'email.complained', 'resend-c253-complaint-%s', '%s', clock_timestamp(), null, null, null, repeat('c', 64)); RESET ROLE;" \
    "$1" "$1" "$2"
}
run_row_lock_first "provider-complaint-first" 2510 \
  "$(complaint_first_sql first "$(recipient_email 2510)")" \
  "select exists (select 1 from public.delivery_provider_suppressions where recipient_email = '$(recipient_email 2510)' and reason = 'complaint')" \
  "advisory"

run_auth_lock_first "provider-complaint-auth-first" 2511 \
  "$(complaint_first_sql second "$(recipient_email 2511)")" \
  "select exists (select 1 from public.delivery_provider_suppressions where recipient_email = '$(recipient_email 2511)' and reason = 'complaint')" \
  "advisory"

# Expiry while blocked on an Auth authorization row lock.
row_expiry_id="$(job_id 2512)"
row_expiry_token="$(claim_token 2512)"
row_expiry_user="$(user_id 2512)"
row_expiry_email="$(recipient_email 2512)"
row_holder_app="c253-holder-row-expiry"
row_waiter_app="c253-waiter-row-expiry"
row_holder_log="$tmp/row-expiry-holder.log"
row_waiter_log="$tmp/row-expiry-waiter.log"
row_fifo="$tmp/row-expiry-holder.fifo"
psql_scalar "update public.delivery_ledger set claim_expires_at = clock_timestamp() + interval '4 seconds' where id='$row_expiry_id'" >/dev/null
start_fifo_session "$row_fifo" "$row_holder_log"
row_holder_pid="$SESSION_PID" row_holder_fd="$SESSION_FD"
send_fd "$row_holder_fd" "BEGIN;"
send_fd "$row_holder_fd" "SET application_name = '$row_holder_app';"
send_fd "$row_holder_fd" "SELECT id FROM auth.users WHERE id = '$row_expiry_user' FOR UPDATE;"
send_fd "$row_holder_fd" "\echo C253_HOLDER_READY_ROW_EXPIRY"
wait_for_marker "$row_holder_pid" "$row_holder_log" "C253_HOLDER_READY_ROW_EXPIRY"
row_error_sql="SET ROLE service_role; DO \$c253\$ BEGIN BEGIN PERFORM public.authorize_delivery_idempotency_window('$row_expiry_id', '$row_expiry_token', '$row_expiry_email'); RAISE EXCEPTION 'Expired row-lock claim was authorized.' USING ERRCODE = 'P0001'; EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END; END \$c253\$; SELECT 'denied';"
start_background_sql "$row_waiter_app" "$row_waiter_log" "$row_error_sql"
row_waiter_pid="$SQL_PID"
wait_for_lock_wait "$row_waiter_app" "$row_holder_app" "$row_waiter_pid" "$row_waiter_log"
[[ "$(psql_scalar "select claim_expires_at > clock_timestamp() from public.delivery_ledger where id='$row_expiry_id'")" == "t" ]] \
  || fail "Row-lock expiry fixture was not observed waiting before the lease expired."
wait_until_claim_expired "$row_expiry_id" "$row_waiter_pid" "$row_waiter_log"
finish_fifo_session "$row_holder_fd" "$row_holder_pid" "$row_holder_log" "COMMIT;"
rm -f "$row_fifo"
wait "$row_waiter_pid" || { cat "$row_waiter_log" >&2; fail "Row-lock expiry authorization did not fail safely."; }
grep -Fxq "denied" "$row_waiter_log" || fail "Row-lock expiry did not return its denial marker."
assert_expired_claimed "$row_expiry_id" "$row_expiry_token"
assert_no_provider_attempt "$row_expiry_id"
echo "C253 claim expiration while waiting for authorization-row lock: PASS"

# Expiry while blocked on the exact provider-address advisory lock.
advisory_expiry_id="$(job_id 2513)"
advisory_expiry_token="$(claim_token 2513)"
advisory_expiry_email="$(recipient_email 2513)"
advisory_holder_app="c253-holder-advisory-expiry"
advisory_waiter_app="c253-waiter-advisory-expiry"
advisory_holder_log="$tmp/advisory-expiry-holder.log"
advisory_waiter_log="$tmp/advisory-expiry-waiter.log"
advisory_fifo="$tmp/advisory-expiry-holder.fifo"
psql_scalar "update public.delivery_ledger set claim_expires_at = clock_timestamp() + interval '4 seconds' where id='$advisory_expiry_id'" >/dev/null
start_fifo_session "$advisory_fifo" "$advisory_holder_log"
advisory_holder_pid="$SESSION_PID" advisory_holder_fd="$SESSION_FD"
send_fd "$advisory_holder_fd" "BEGIN;"
send_fd "$advisory_holder_fd" "SET application_name = '$advisory_holder_app';"
send_fd "$advisory_holder_fd" "SELECT pg_advisory_xact_lock(20261119, hashtext('$advisory_expiry_email'));"
send_fd "$advisory_holder_fd" "\echo C253_HOLDER_READY_ADVISORY_EXPIRY"
wait_for_marker "$advisory_holder_pid" "$advisory_holder_log" "C253_HOLDER_READY_ADVISORY_EXPIRY"
advisory_error_sql="SET ROLE service_role; DO \$c253\$ BEGIN BEGIN PERFORM public.authorize_delivery_idempotency_window('$advisory_expiry_id', '$advisory_expiry_token', '$advisory_expiry_email'); RAISE EXCEPTION 'Expired advisory-lock claim was authorized.' USING ERRCODE = 'P0001'; EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END; END \$c253\$; SELECT 'denied';"
start_background_sql "$advisory_waiter_app" "$advisory_waiter_log" "$advisory_error_sql"
advisory_waiter_pid="$SQL_PID"
wait_for_lock_wait "$advisory_waiter_app" "$advisory_holder_app" "$advisory_waiter_pid" "$advisory_waiter_log" "advisory"
[[ "$(psql_scalar "select claim_expires_at > clock_timestamp() from public.delivery_ledger where id='$advisory_expiry_id'")" == "t" ]] \
  || fail "Advisory-lock expiry fixture was not observed waiting before the lease expired."
wait_until_claim_expired "$advisory_expiry_id" "$advisory_waiter_pid" "$advisory_waiter_log"
finish_fifo_session "$advisory_holder_fd" "$advisory_holder_pid" "$advisory_holder_log" "COMMIT;"
rm -f "$advisory_fifo"
wait "$advisory_waiter_pid" || { cat "$advisory_waiter_log" >&2; fail "Advisory-lock expiry authorization did not fail safely."; }
grep -Fxq "denied" "$advisory_waiter_log" || fail "Advisory-lock expiry did not return its denial marker."
assert_expired_claimed "$advisory_expiry_id" "$advisory_expiry_token"
assert_no_provider_attempt "$advisory_expiry_id"
echo "C253 claim expiration while waiting for provider advisory lock: PASS"

# The five-second lock timeout must surface as 55P03 and leave the live claim untouched.
timeout_id="$(job_id 2514)"
timeout_token="$(claim_token 2514)"
timeout_user="$(user_id 2514)"
timeout_email="$(recipient_email 2514)"
timeout_holder_app="c253-holder-lock-timeout"
timeout_waiter_app="c253-waiter-lock-timeout"
timeout_holder_log="$tmp/lock-timeout-holder.log"
timeout_waiter_log="$tmp/lock-timeout-waiter.log"
timeout_fifo="$tmp/lock-timeout-holder.fifo"
start_fifo_session "$timeout_fifo" "$timeout_holder_log"
timeout_holder_pid="$SESSION_PID" timeout_holder_fd="$SESSION_FD"
send_fd "$timeout_holder_fd" "BEGIN;"
send_fd "$timeout_holder_fd" "SET application_name = '$timeout_holder_app';"
send_fd "$timeout_holder_fd" "SELECT id FROM auth.users WHERE id = '$timeout_user' FOR UPDATE;"
send_fd "$timeout_holder_fd" "\echo C253_HOLDER_READY_LOCK_TIMEOUT"
wait_for_marker "$timeout_holder_pid" "$timeout_holder_log" "C253_HOLDER_READY_LOCK_TIMEOUT"
timeout_error_sql="SET statement_timeout = '15s'; SET ROLE service_role; DO \$c253\$ DECLARE v_state text; BEGIN BEGIN PERFORM public.authorize_delivery_idempotency_window('$timeout_id', '$timeout_token', '$timeout_email'); RAISE EXCEPTION 'Lock-timeout fixture unexpectedly authorized.' USING ERRCODE = 'P0001'; EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE; IF v_state <> '55P03' THEN RAISE; END IF; END; END \$c253\$; SELECT 'denied';"
timeout_started_ms="$(date +%s%3N)"
start_background_sql "$timeout_waiter_app" "$timeout_waiter_log" "$timeout_error_sql"
timeout_waiter_pid="$SQL_PID"
wait_for_lock_wait "$timeout_waiter_app" "$timeout_holder_app" "$timeout_waiter_pid" "$timeout_waiter_log"
wait "$timeout_waiter_pid" || { cat "$timeout_waiter_log" >&2; fail "Five-second lock timeout did not fail closed."; }
timeout_finished_ms="$(date +%s%3N)"
timeout_elapsed_ms=$((timeout_finished_ms - timeout_started_ms))
finish_fifo_session "$timeout_holder_fd" "$timeout_holder_pid" "$timeout_holder_log" "COMMIT;"
rm -f "$timeout_fifo"
grep -Fxq "denied" "$timeout_waiter_log" || fail "Lock timeout did not return its denial marker."
(( timeout_elapsed_ms >= 4500 && timeout_elapsed_ms <= 15000 )) \
  || fail "Expected approximately five seconds of lock waiting, observed $timeout_elapsed_ms ms."
assert_claimed "$timeout_id" "$timeout_token"
assert_no_provider_attempt "$timeout_id"
echo "C253 five-second lock timeout (SQLSTATE 55P03, $timeout_elapsed_ms ms): PASS"

# Stale claim token and unsupported isolation are explicit failures with no ledger mutation.
stale_id="$(job_id 2515)"
stale_token="$(claim_token 2515)"
stale_email="$(recipient_email 2515)"
stale_sql="SET ROLE service_role; DO \$c253\$ BEGIN BEGIN PERFORM public.authorize_delivery_idempotency_window('$stale_id', '49999999-0000-0000-0000-000000009999', '$stale_email'); RAISE EXCEPTION 'Stale claim token was accepted.' USING ERRCODE = 'P0001'; EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END; END \$c253\$; SELECT 'denied';"
psql_exec --quiet --no-align --tuples-only --command="BEGIN; $stale_sql COMMIT;" >"$tmp/stale-token.log" 2>&1
grep -Fxq "denied" "$tmp/stale-token.log" || { cat "$tmp/stale-token.log" >&2; fail "Stale claim token did not fail closed."; }
assert_claimed "$stale_id" "$stale_token"
assert_no_provider_attempt "$stale_id"
echo "C253 stale claim token: PASS"

isolation_id="$(job_id 2518)"
isolation_token="$(claim_token 2518)"
isolation_email="$(recipient_email 2518)"
isolation_sql="SET ROLE service_role; DO \$c253\$ BEGIN BEGIN PERFORM public.authorize_delivery_idempotency_window('$isolation_id', '$isolation_token', '$isolation_email'); RAISE EXCEPTION 'Unsupported isolation was accepted.' USING ERRCODE = 'P0001'; EXCEPTION WHEN SQLSTATE '25000' THEN NULL; END; END \$c253\$; SELECT 'denied';"
psql_exec --quiet --no-align --tuples-only --command="BEGIN; SET TRANSACTION ISOLATION LEVEL REPEATABLE READ; $isolation_sql COMMIT;" >"$tmp/isolation.log" 2>&1
grep -Fxq "denied" "$tmp/isolation.log" || { cat "$tmp/isolation.log" >&2; fail "REPEATABLE READ was not rejected."; }
assert_claimed "$isolation_id" "$isolation_token"
assert_no_provider_attempt "$isolation_id"
echo "C253 unsupported REPEATABLE READ isolation: PASS"

# A caller rollback must roll back the cancellation update from the real RPC.
rollback_id="$(job_id 2516)"
rollback_token="$(claim_token 2516)"
rollback_email="$(recipient_email 2516)"
psql_scalar "update public.daily_reminder_preferences set daily_enabled = false where user_id = '$(user_id 2516)'" >/dev/null
psql_exec --quiet --no-align --tuples-only \
  --command="BEGIN; SET ROLE service_role; SELECT public.authorize_delivery_idempotency_window('$rollback_id', '$rollback_token', '$rollback_email'); ROLLBACK;" \
  >"$tmp/rollback.log" 2>&1
grep -Fxq "cancelled" "$tmp/rollback.log" || { cat "$tmp/rollback.log" >&2; fail "Rollback fixture did not first receive cancelled from the RPC."; }
assert_claimed "$rollback_id" "$rollback_token"
assert_no_provider_attempt "$rollback_id"
echo "C253 transaction rollback restores the pre-RPC ledger claim: PASS"

# A Worker connection interrupted while the real authorization RPC is blocked must roll back.
interrupt_id="$(job_id 2519)"
interrupt_token="$(claim_token 2519)"
interrupt_user="$(user_id 2519)"
interrupt_email="$(recipient_email 2519)"
interrupt_holder_app="c253-holder-worker-interruption"
interrupt_waiter_app="c253-waiter-worker-interruption"
interrupt_holder_log="$tmp/worker-interruption-holder.log"
interrupt_waiter_log="$tmp/worker-interruption-waiter.log"
interrupt_fifo="$tmp/worker-interruption-holder.fifo"
start_fifo_session "$interrupt_fifo" "$interrupt_holder_log"
interrupt_holder_pid="$SESSION_PID" interrupt_holder_fd="$SESSION_FD"
send_fd "$interrupt_holder_fd" "BEGIN;"
send_fd "$interrupt_holder_fd" "SET application_name = '$interrupt_holder_app';"
send_fd "$interrupt_holder_fd" "SELECT id FROM auth.users WHERE id = '$interrupt_user' FOR UPDATE;"
send_fd "$interrupt_holder_fd" "\echo C253_HOLDER_READY_WORKER_INTERRUPTION"
wait_for_marker "$interrupt_holder_pid" "$interrupt_holder_log" "C253_HOLDER_READY_WORKER_INTERRUPTION"
start_background_sql "$interrupt_waiter_app" "$interrupt_waiter_log" \
  "SET ROLE service_role; SELECT public.authorize_delivery_idempotency_window('$interrupt_id', '$interrupt_token', '$interrupt_email');"
interrupt_waiter_pid="$SQL_PID"
wait_for_lock_wait "$interrupt_waiter_app" "$interrupt_holder_app" "$interrupt_waiter_pid" "$interrupt_waiter_log"
terminated="$(psql_scalar "select pg_terminate_backend(pid) from pg_stat_activity where application_name='$interrupt_waiter_app'")"
[[ "$terminated" == "t" ]] || fail "Could not terminate the blocked Worker authorization backend."
if wait "$interrupt_waiter_pid"; then
  fail "Worker authorization connection unexpectedly survived pg_terminate_backend."
fi
wait_for_session_gone "$interrupt_waiter_app"
finish_fifo_session "$interrupt_holder_fd" "$interrupt_holder_pid" "$interrupt_holder_log" "COMMIT;"
rm -f "$interrupt_fifo"
assert_claimed "$interrupt_id" "$interrupt_token"
assert_no_provider_attempt "$interrupt_id"
echo "C253 Worker interruption during blocked authorization: PASS"

# Two claims for the same recipient must wait on the same advisory lock without a deadlock.
deadlocks_before="$(psql_scalar "select deadlocks from pg_stat_database where datname = current_database()")"
deadlock_first_id="$(job_id 2520)"
deadlock_first_token="$(claim_token 2520)"
deadlock_second_id="30000000-0000-0000-0000-000000002620"
deadlock_second_token="40000000-0000-0000-0000-000000002620"
deadlock_email="$(recipient_email 2520)"
deadlock_auth_app="c253-auth-same-recipient-first"
deadlock_waiter_app="c253-auth-same-recipient-second"
deadlock_auth_log="$tmp/deadlock-first.log"
deadlock_waiter_log="$tmp/deadlock-second.log"
deadlock_fifo="$tmp/deadlock-first.fifo"
start_fifo_session "$deadlock_fifo" "$deadlock_auth_log"
deadlock_auth_pid="$SESSION_PID" deadlock_auth_fd="$SESSION_FD"
send_fd "$deadlock_auth_fd" "BEGIN;"
send_fd "$deadlock_auth_fd" "SET application_name = '$deadlock_auth_app';"
send_fd "$deadlock_auth_fd" "SET ROLE service_role;"
send_fd "$deadlock_auth_fd" "SELECT public.authorize_delivery_idempotency_window('$deadlock_first_id', '$deadlock_first_token', '$deadlock_email');"
send_fd "$deadlock_auth_fd" "\echo C253_AUTHORIZED_READY_DEADLOCK"
wait_for_marker "$deadlock_auth_pid" "$deadlock_auth_log" "C253_AUTHORIZED_READY_DEADLOCK"
grep -Fxq "authorized" "$deadlock_auth_log" || { cat "$deadlock_auth_log" >&2; fail "First same-recipient authorization failed."; }
start_background_sql "$deadlock_waiter_app" "$deadlock_waiter_log" \
  "SET ROLE service_role; SELECT public.authorize_delivery_idempotency_window('$deadlock_second_id', '$deadlock_second_token', '$deadlock_email');"
deadlock_waiter_pid="$SQL_PID"
wait_for_lock_wait "$deadlock_waiter_app" "$deadlock_auth_app" "$deadlock_waiter_pid" "$deadlock_waiter_log" "advisory"
finish_fifo_session "$deadlock_auth_fd" "$deadlock_auth_pid" "$deadlock_auth_log" "COMMIT;"
rm -f "$deadlock_fifo"
wait "$deadlock_waiter_pid" || { cat "$deadlock_waiter_log" >&2; fail "Second same-recipient authorization failed."; }
grep -Fxq "authorized" "$deadlock_waiter_log" || { cat "$deadlock_waiter_log" >&2; fail "Second same-recipient authorization was not authorized."; }
deadlocks_after="$(psql_scalar "select deadlocks from pg_stat_database where datname = current_database()")"
[[ "$deadlocks_after" == "$deadlocks_before" ]] || fail "Same-recipient authorization lock order introduced a PostgreSQL deadlock."
assert_claimed "$deadlock_first_id" "$deadlock_first_token"
assert_claimed "$deadlock_second_id" "$deadlock_second_token"
record_provider_attempt "$deadlock_first_id" "same-recipient-first"
record_provider_attempt "$deadlock_second_id" "same-recipient-second"
echo "C253 same-recipient advisory-lock ordering and deadlock counter: PASS"

# Duplicate attempts for the same logical delivery serialize on the ledger row and retain one stable key.
duplicate_id="$(job_id 2517)"
duplicate_token="$(claim_token 2517)"
duplicate_email="$(recipient_email 2517)"
duplicate_auth_app="c253-auth-duplicate-first"
duplicate_waiter_app="c253-auth-duplicate-second"
duplicate_auth_log="$tmp/duplicate-first.log"
duplicate_waiter_log="$tmp/duplicate-second.log"
duplicate_fifo="$tmp/duplicate-first.fifo"
start_fifo_session "$duplicate_fifo" "$duplicate_auth_log"
duplicate_auth_pid="$SESSION_PID" duplicate_auth_fd="$SESSION_FD"
send_fd "$duplicate_auth_fd" "BEGIN;"
send_fd "$duplicate_auth_fd" "SET application_name = '$duplicate_auth_app';"
send_fd "$duplicate_auth_fd" "SET ROLE service_role;"
send_fd "$duplicate_auth_fd" "SELECT public.authorize_delivery_idempotency_window('$duplicate_id', '$duplicate_token', '$duplicate_email');"
send_fd "$duplicate_auth_fd" "\echo C253_AUTHORIZED_READY_DUPLICATE"
wait_for_marker "$duplicate_auth_pid" "$duplicate_auth_log" "C253_AUTHORIZED_READY_DUPLICATE"
grep -Fxq "authorized" "$duplicate_auth_log" || { cat "$duplicate_auth_log" >&2; fail "First duplicate authorization failed."; }
start_background_sql "$duplicate_waiter_app" "$duplicate_waiter_log" \
  "SET ROLE service_role; SELECT public.authorize_delivery_idempotency_window('$duplicate_id', '$duplicate_token', '$duplicate_email');"
duplicate_waiter_pid="$SQL_PID"
wait_for_lock_wait "$duplicate_waiter_app" "$duplicate_auth_app" "$duplicate_waiter_pid" "$duplicate_waiter_log"
finish_fifo_session "$duplicate_auth_fd" "$duplicate_auth_pid" "$duplicate_auth_log" "COMMIT;"
rm -f "$duplicate_fifo"
wait "$duplicate_waiter_pid" || { cat "$duplicate_waiter_log" >&2; fail "Second duplicate authorization failed."; }
grep -Fxq "authorized" "$duplicate_waiter_log" || { cat "$duplicate_waiter_log" >&2; fail "Second duplicate attempt was not authorized."; }
assert_claimed "$duplicate_id" "$duplicate_token"
record_provider_attempt "$duplicate_id" "duplicate-attempt-one"
record_provider_attempt "$duplicate_id" "duplicate-attempt-two"
duplicate_key="deedlight/daily_reminder/$duplicate_id"
duplicate_result="$(psql_scalar "select count(*) = 2 and count(distinct idempotency_key) = 1 and min(idempotency_key) = '$duplicate_key' from public.c253_provider_attempts where job_id='$duplicate_id'")"
[[ "$duplicate_result" == "t" ]] || fail "Duplicate attempts did not retain the same stable Worker idempotency key."
grep -Fq '"Idempotency-Key": idempotencyKey(job),' lib/delivery/resend-transport.ts \
  || fail "Worker no longer sends the deterministic idempotency key."
grep -Fq 'deedlight/' lib/delivery/resend-transport.ts \
  || fail "Worker idempotency key namespace changed without updating the concurrency assertion."
grep -Fq 'job.jobId' lib/delivery/resend-transport.ts \
  || fail "Worker idempotency key is no longer bound to the logical delivery ID."
echo "C253 duplicate delivery attempts serialize and retain one stable provider idempotency key: PASS"

echo "C253 deterministic final authorization two-session PostgreSQL matrix: PASS"
