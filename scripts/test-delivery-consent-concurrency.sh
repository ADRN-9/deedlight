#!/usr/bin/env bash
set -euo pipefail

psql_cmd=(psql -X -v ON_ERROR_STOP=1 --host 127.0.0.1 --port 5432 --username postgres --dbname deedlight_transport_test)
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A fresh eligible claimed daily job. Only synthetic local PostgreSQL data.
"${psql_cmd[@]}" <<'SQL'
insert into auth.users (id, email, email_confirmed_at)
values ('00000000-0000-0000-0000-000000000109', 'fixture-109@example.test', now())
on conflict do nothing;
insert into public.profiles (user_id, is_suspended)
values ('00000000-0000-0000-0000-000000000109', false) on conflict do nothing;
insert into public.daily_reminder_preferences (user_id, daily_enabled, reminder_time, timezone)
values ('00000000-0000-0000-0000-000000000109', true, '00:00', 'UTC')
on conflict (user_id) do update set daily_enabled=true;
insert into public.delivery_ledger (user_id, kind, delivery_key, scheduled_for)
values (
  '00000000-0000-0000-0000-000000000109',
  'daily_reminder',
  'daily:' || timezone('UTC',now())::date::text,
  (timezone('UTC',now())::date + time '00:00') at time zone 'UTC'
);
set role service_role;
select count(*) from public.claim_delivery_jobs(now(), 100);
reset role;
SQL

# Revocation gets its row lock first, holds it across the transport RPC.
"${psql_cmd[@]}" >"$tmp/revoker.log" 2>&1 <<'SQL' &
begin;
update public.daily_reminder_preferences set daily_enabled=false
where user_id = '00000000-0000-0000-0000-000000000109';
\echo REVOCATION_LOCK_HELD
select pg_sleep(3);
commit;
SQL
revoker_pid=$!

for i in {1..100}; do
  if grep -q REVOCATION_LOCK_HELD "$tmp/revoker.log"; then break; fi
  if ! kill -0 "$revoker_pid" 2>/dev/null; then
    cat "$tmp/revoker.log"; exit 1
  fi
  sleep 0.05
done
grep -q REVOCATION_LOCK_HELD "$tmp/revoker.log"

"${psql_cmd[@]}" >"$tmp/transport.log" 2>&1 <<'SQL'
set role service_role;
do $$
declare v_id uuid; v_token uuid;
begin
  select id, claim_token into v_id, v_token from public.delivery_ledger
  where user_id = '00000000-0000-0000-0000-000000000109'
  and state = 'claimed';
  if v_id is null then raise exception 'Missing concurrent test claim.'; end if;
  if public.begin_delivery_transport(v_id, v_token, 'fixture-109@example.test') is not null then
    raise exception 'Revocation committed before transport but transport started.';
  end if;
end;
$$;
reset role;
SQL
wait "$revoker_pid"
"${psql_cmd[@]}" -Atc "select state || ':' || (transport_started_at is null)::text from public.delivery_ledger where user_id='00000000-0000-0000-0000-000000000109'" >"$tmp/result"
grep -qx 'cancelled:true' "$tmp/result"
echo "Concurrent revocation-first transport authorization: PASS"

# Transport authorization acquires eligibility locks first. A later
# revocation may commit only after that authorization transaction releases.
"${psql_cmd[@]}" <<'SQL'
insert into auth.users (id, email, email_confirmed_at)
values ('00000000-0000-0000-0000-000000000110', 'fixture-110@example.test', now())
on conflict do nothing;
insert into public.profiles (user_id, is_suspended)
values ('00000000-0000-0000-0000-000000000110', false) on conflict do nothing;
insert into public.daily_reminder_preferences (user_id, daily_enabled, reminder_time, timezone)
values ('00000000-0000-0000-0000-000000000110', true, '00:00', 'UTC')
on conflict (user_id) do update set daily_enabled=true;
insert into public.delivery_ledger (user_id, kind, delivery_key, scheduled_for)
values (
  '00000000-0000-0000-0000-000000000110',
  'daily_reminder',
  'daily:' || timezone('UTC',now())::date::text,
  (timezone('UTC',now())::date + time '00:00') at time zone 'UTC'
);
set role service_role;
select count(*) from public.claim_delivery_jobs(now(), 100);
reset role;
SQL

"${psql_cmd[@]}" >"$tmp/transport-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
do $$
declare v_id uuid; v_token uuid;
begin
  select id, claim_token into v_id, v_token from public.delivery_ledger
  where user_id = '00000000-0000-0000-0000-000000000110' and state = 'claimed';
  if v_id is null or public.begin_delivery_transport(v_id, v_token, 'fixture-110@example.test') is null then
    raise exception 'Valid in-flight transport failed to start.';
  end if;
end;
$$;
\echo TRANSPORT_LOCK_HELD
select pg_sleep(3);
commit;
SQL
transport_pid=$!
for i in {1..100}; do
  if grep -q TRANSPORT_LOCK_HELD "$tmp/transport-first.log"; then break; fi
  if ! kill -0 "$transport_pid" 2>/dev/null; then
    cat "$tmp/transport-first.log"; exit 1
  fi
  sleep 0.05
done
grep -q TRANSPORT_LOCK_HELD "$tmp/transport-first.log"
"${psql_cmd[@]}" -c "update public.daily_reminder_preferences set daily_enabled=false where user_id='00000000-0000-0000-0000-000000000110'" >"$tmp/revoke-after.log" 2>&1
wait "$transport_pid"
"${psql_cmd[@]}" -Atc "select (dl.transport_started_at is not null)::text || ':' || (not drp.daily_enabled)::text from public.delivery_ledger dl join public.daily_reminder_preferences drp using(user_id) where dl.user_id='00000000-0000-0000-0000-000000000110'" >"$tmp/result-after"
grep -qx 'true:true' "$tmp/result-after"
echo "Concurrent transport-first then later revocation ordering: PASS"

# A lease expiring during a consent row lock wait must not be authorized.
"${psql_cmd[@]}" <<'SQL'
insert into auth.users (id,email,email_confirmed_at)
values ('00000000-0000-0000-0000-000000000111','fixture-111@example.test',now());
insert into public.profiles(user_id,is_suspended)
values ('00000000-0000-0000-0000-000000000111',false);
insert into public.daily_reminder_preferences(user_id,daily_enabled,reminder_time,timezone)
values ('00000000-0000-0000-0000-000000000111',true,'00:00','UTC');
insert into public.delivery_ledger(user_id,kind,delivery_key,scheduled_for)
values ('00000000-0000-0000-0000-000000000111',
 'daily_reminder','daily:' || timezone('UTC',now())::date::text,
 (timezone('UTC',now())::date + time '00:00') at time zone 'UTC');
set role service_role;
select count(*) from public.claim_delivery_jobs(now(),100);
reset role;
update public.delivery_ledger
set claim_expires_at=clock_timestamp() + interval '2 seconds'
where user_id='00000000-0000-0000-0000-000000000111';
SQL

"${psql_cmd[@]}" >"$tmp/lease-lock.log" 2>&1 <<'SQL' &
begin;
update public.daily_reminder_preferences set daily_enabled=true
where user_id='00000000-0000-0000-0000-000000000111';
\echo LEASE_CONSENT_LOCK_HELD
select pg_sleep(4);
commit;
SQL
lease_pid=$!
for i in {1..100}; do
  if grep -q LEASE_CONSENT_LOCK_HELD "$tmp/lease-lock.log"; then break; fi
  if ! kill -0 "$lease_pid" 2>/dev/null; then
    cat "$tmp/lease-lock.log"; exit 1
  fi
  sleep 0.05
done
grep -q LEASE_CONSENT_LOCK_HELD "$tmp/lease-lock.log"
"${psql_cmd[@]}" <<'SQL'
set role service_role;
do $$
declare v_id uuid; v_token uuid;
begin
  select id,claim_token into v_id,v_token from public.delivery_ledger
  where user_id='00000000-0000-0000-0000-000000000111';
  begin
    perform public.begin_delivery_transport(
      v_id,v_token,'fixture-111@example.test');
    raise exception 'Claim expiring while waiting on lock authorized transport.';
  exception when sqlstate '42501' then null;
  end;
end;
$$;
reset role;
SQL
wait "$lease_pid"
"${psql_cmd[@]}" -Atc "select (transport_started_at is null)::text from public.delivery_ledger where user_id='00000000-0000-0000-0000-000000000111'" >"$tmp/lease-result"
grep -qx 'true' "$tmp/lease-result"
echo "Concurrent consent lock wait with expiring claim: PASS"

# Concurrent schedulers must serialize by issue and count the rows already queued.
# Opt-in cutoff is the first eligible snapshot AFTER acquiring the issue lock.
"${psql_cmd[@]}" <<'SQL'
insert into public.weekly_goodness_features(week_start)
values ('2027-02-15') on conflict do nothing;
update public.newsletter_preferences set weekly_enabled=false
where user_id in (
  '00000000-0000-0000-0000-000000010001',
  '00000000-0000-0000-0000-000000010002'
);
set role service_role;
do $$
begin
  if public.enqueue_weekly_goodness_delivery('2027-02-15',now(),5000) <> 4999 then
    raise exception 'Concurrent fixture requires 4999 pre-existing weekly jobs.';
  end if;
end;
$$;
reset role;
update public.newsletter_preferences set weekly_enabled=true
where user_id='00000000-0000-0000-0000-000000010002';
SQL

"${psql_cmd[@]}" >"$tmp/weekly-first.log" 2>&1 <<'SQL' &
begin;
set role service_role;
do $$
begin
  if public.enqueue_weekly_goodness_delivery('2027-02-15',now(),5000) <> 1 then
    raise exception 'First scheduler did not enqueue the final available slot.';
  end if;
end;
$$;
\echo WEEKLY_ISSUE_LOCK_HELD
select pg_sleep(3);
commit;
SQL
weekly_first_pid=$!
for i in {1..100}; do
  if grep -q WEEKLY_ISSUE_LOCK_HELD "$tmp/weekly-first.log"; then break; fi
  if ! kill -0 "$weekly_first_pid" 2>/dev/null; then
    cat "$tmp/weekly-first.log"; exit 1
  fi
  sleep 0.05
done
grep -q WEEKLY_ISSUE_LOCK_HELD "$tmp/weekly-first.log"

"${psql_cmd[@]}" >"$tmp/weekly-second.log" 2>&1 <<'SQL'
set role service_role;
do $$
begin
  if public.enqueue_weekly_goodness_delivery('2027-02-15',now(),5000) <> 0 then
    raise exception 'Concurrent scheduler duplicated the final weekly slot.';
  end if;
end;
$$;
reset role;
SQL
wait "$weekly_first_pid"
"${psql_cmd[@]}" -Atc "select count(*) from public.delivery_ledger where kind='weekly_newsletter' and delivery_key='weekly:2027-02-15'" >"$tmp/weekly-count"
grep -qx '5000' "$tmp/weekly-count"

# After the synchronized invocations, another opt-in must fail visibly.
"${psql_cmd[@]}" <<'SQL'
update public.newsletter_preferences set weekly_enabled=true
where user_id='00000000-0000-0000-0000-000000010001';
set role service_role;
do $$
begin
  begin
    perform public.enqueue_weekly_goodness_delivery('2027-02-15',now(),5000);
    raise exception 'Late opt-in bypassed issue-wide concurrent cap.';
  exception when sqlstate '54000' then null;
  end;
end;
$$;
reset role;
SQL
"${psql_cmd[@]}" -Atc "select count(*) from public.delivery_ledger where kind='weekly_newsletter' and delivery_key='weekly:2027-02-15'" >"$tmp/weekly-count-after"
grep -qx '5000' "$tmp/weekly-count-after"
echo "Concurrent weekly scheduler issue-wide capacity and late opt-in: PASS"
