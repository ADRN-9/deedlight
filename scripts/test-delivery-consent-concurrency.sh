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
  if public.begin_delivery_transport(v_id, v_token) is not null then
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
