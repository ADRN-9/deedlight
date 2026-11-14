#!/usr/bin/env bash
set -Eeuo pipefail
set +x
# C69: synthetic-only, explicitly approved, disconnected Docker PostgreSQL 16.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${DEEDLIGHT_C69_DISPOSABLE_APPROVED:-}" != true ]]; then
  echo 'C69 PostgreSQL verification NOT RUN: explicit disposable approval required' >&2; exit 77
fi
for secret in SUPABASE_DB_PASSWORD SUPABASE_PROJECT_REF DATABASE_URL PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD RESEND_API_KEY RESEND_WEBHOOK_SECRET CLOUDFLARE_API_TOKEN; do
  [[ -z "${!secret:-}" ]] || { echo "C69 blocked: forbidden live environment variable $secret" >&2;exit 77; }
done
command -v docker >/dev/null || { echo 'C69 PostgreSQL NOT TESTED: Docker unavailable';exit 77; }
docker image inspect postgres:16 >/dev/null 2>&1 || {
  echo 'C69 PostgreSQL NOT TESTED: preloaded postgres:16 image required; no automatic pulls';exit 77;
}
bootstrap="${DEEDLIGHT_C69_APPROVED_BOOTSTRAP_SQL:-}"
[[ -n "$bootstrap" && -f "$bootstrap" ]] || {
  echo 'C69 missing approved, independently reviewed 019-024 bootstrap SQL'; exit 77;
}
# Exact original 025-028 blobs must be placed at sources/ by an independent
# fetch of published GitHub evidence; refuse synthetic/reconstructed files.
python3 - "$root" <<'PY'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]);catalog=json.loads((root/'sources/AUTHENTIC_SOURCE_MANIFEST.json').read_text())
for source in catalog['sources']:
    path=root/'sources'/source['file']
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=source['sha256']:
        raise SystemExit('C69 original 025-028 source missing or checksum mismatch: '+source['file'])
p=root/'sources/PROPOSED_POST_028_provider_event_registry_C61.sql'
if hashlib.sha256(p.read_bytes()).hexdigest()!='ed0dc53204c91b6171bc12de40929df6f54bae24e78716f0072d69593e008672':
    raise SystemExit('C69 original C61 SQL checksum mismatch')
PY
name="deedlight-c69-pg16-${$}"
cleanup(){ docker rm -f "$name" >/dev/null 2>&1 || :; }
trap cleanup EXIT
docker run --rm -d --network none --name "$name" \
  -e POSTGRES_PASSWORD=c69_disposable_only -e POSTGRES_DB=c69_synthetic postgres:16 >/dev/null
for _ in {1..60}; do
  if docker exec "$name" pg_isready -U postgres -d c69_synthetic >/dev/null 2>&1; then break; fi
  sleep 1
done
{
  cat "$bootstrap"
  for source in 202611130025_delivery_kind_claim_isolation.sql \
    202611130026_resend_webhook_lifecycle.sql \
    202611130027_recipient_suppression_serialization.sql \
    202611130028_database_authoritative_recipient_binding.sql; do
    cat "$root/sources/$source"
  done
  cat "$root/sources/PROPOSED_POST_028_provider_event_registry_C61.sql"
  cat "$root/tests/postgres_preexisting_history.sql"
  cat "$root/patch/PROPOSED_post029_c69_authentic_webhook_transport_hard_stop.sql"
  cat "$root/tests/postgres_negative_assertions.sql"
} | docker exec -i -e PGPASSWORD=c69_disposable_only "$name" \
    psql -X -v ON_ERROR_STOP=1 -U postgres -d c69_synthetic -f -
echo 'C69_POSTGRESQL_16_DISPOSABLE_PASS'
