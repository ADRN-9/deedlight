#!/usr/bin/env bash
# Review-only verification. Run from a disposable checkout with the fixture patch applied.
set -euo pipefail

repo="${1:-$PWD}"
if [[ ! -f "$repo/scripts/test-gentle-delivery-transport.sql" ]]; then
  echo 'Missing DeedLight checkout or patched transport fixture' >&2
  exit 2
fi
if ! grep -q 'v_now timestamptz := now()' "$repo/scripts/test-gentle-delivery-transport.sql"; then
  echo 'Refusing to test the unpatched historical fixture' >&2
  exit 2
fi
command -v docker >/dev/null || { echo 'Docker is required for disposable PG16' >&2; exit 2; }

container="deedlight-c70-claim-$$"
cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# No published ports and no Production credentials. Trust applies only to disposable PG16.
docker run --detach --name "$container" \
  --env POSTGRES_HOST_AUTH_METHOD=trust \
  --env POSTGRES_DB=deedlight_fixture \
  --volume "$repo:/deedlight:ro" \
  postgres:16 >/dev/null

ready=false
for _ in $(seq 1 40); do
  if docker exec "$container" pg_isready -U postgres -d deedlight_fixture >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo 'PostgreSQL did not become ready' >&2
  exit 1
fi

docker exec "$container" psql \
  --username postgres \
  --dbname deedlight_fixture \
  --set ON_ERROR_STOP=on \
  --file /deedlight/scripts/test-gentle-delivery-transport.sql
