#!/usr/bin/env bash
set -euo pipefail
# Only a locally created, network-isolated Docker postgres:16. No host port mapping.
if [[ "${DEEDLIGHT_C61_DISPOSABLE_ACK:-}" != "I_CONFIRM_SYNTHETIC_DATA_ONLY" ]]; then
  echo 'Refusing execution without explicit synthetic PostgreSQL acknowledgment' >&2
  exit 2
fi
command -v docker >/dev/null || { echo 'docker unavailable; PostgreSQL tests NOT RUN' >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd)"
container="deedlight_c61_disposable_$BASHPID"
cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT
# Docker creates the database INSIDE this ephemeral container; no Production tunnel.
docker run --rm --detach --network none --label 'deedlight-c61=synthetic-only' \
  --name "$container" -e POSTGRES_PASSWORD='synthetic-c61-local-only' postgres:16 >/dev/null
ready=false
for i in $(seq 1 45); do
  if docker exec "$container" pg_isready -U postgres -d postgres >/dev/null 2>&1; then ready=true; break; fi
  sleep 1
done
[[ "$ready" == true ]] || { echo 'postgres 16 container did not become ready' >&2; exit 1; }
docker cp "$root/patch/PROPOSED_POST_028_provider_event_registry.sql" "$container:/tmp/deedlight_c61_migration.sql"
docker cp "$root/tests/postgres_fixture.sql" "$container:/tmp/deedlight_c61_fixture.sql"
docker exec "$container" psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f /tmp/deedlight_c61_fixture.sql
# Real concurrent transactions exercise primary key uniqueness, not a mock.
outputs="$(mktemp -d)"
trap 'rm -rf "$outputs"; cleanup' EXIT
for n in $(seq 1 12); do
  docker exec "$container" psql -v ON_ERROR_STOP=1 -At -U postgres -d postgres \
    -c "select public.deedlight_reserve_provider_event('resend','evt_concurrent',decode(repeat('03',32),'hex'),'email.complained','mail_concurrent')" \
    >"$outputs/$n.txt" 2>"$outputs/$n.err" &
done
wait
[[ "$(grep -lFx NEW_PENDING "$outputs"/*.txt | wc -l)" -eq 1 ]] || { echo 'concurrent uniqueness winner count incorrect' >&2; exit 1; }
[[ "$(grep -lFx DUPLICATE_PENDING "$outputs"/*.txt | wc -l)" -eq 11 ]] || { echo 'concurrent duplicate count incorrect' >&2; exit 1; }
if grep -q . "$outputs"/*.err; then echo 'unexpected PostgreSQL stderr' >&2; exit 1; fi
docker exec "$container" psql -v ON_ERROR_STOP=1 -At -U postgres -d postgres \
  -c "select count(*) from deedlight_event_private.provider_event_registry where event_id='evt_concurrent'" \
  | grep -qx 1 || { echo 'concurrent registry count incorrect' >&2; exit 1; }
echo 'POSTGRESQL 16 CONCURRENT UNIQUE EVENT-ID FIXTURE PASS'
