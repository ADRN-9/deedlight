#!/usr/bin/env bash
set -euo pipefail
: "${DEEDLIGHT_DISPOSABLE_FIXTURE_AUTHORIZATION:?missing disposable fixture authorization}"
: "${DEEDLIGHT_EXPECTED_SERVER_ADDR:?missing expected PostgreSQL service address}"
test "${DEEDLIGHT_DISPOSABLE_FIXTURE_AUTHORIZATION}" = "deedlight-postgres16-ci-disposable-v1"
test "${PGHOST:-127.0.0.1}" = "127.0.0.1"
test "${PGDATABASE:-deedlight_migration037_test}" = "deedlight_migration037_test"
test -z "${SUPABASE_SERVICE_ROLE_KEY:-}"
test -z "${SUPABASE_DB_PASSWORD:-}"
test -z "${SUPABASE_ACCESS_TOKEN:-}"
test -z "${RESEND_API_KEY:-}"
export DEEDLIGHT_BACKFILL_UNAUTHORIZED_PASSWORD="$(openssl rand -hex 32)"
psql_fixture() {
  env -i PATH="${PATH}" HOME="${HOME:-/tmp}" PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=deedlight_migration037_test PGCONNECT_TIMEOUT=5 PGSSLMODE=disable DEEDLIGHT_DISPOSABLE_FIXTURE_AUTHORIZATION="${DEEDLIGHT_DISPOSABLE_FIXTURE_AUTHORIZATION}" DEEDLIGHT_EXPECTED_SERVER_ADDR="${DEEDLIGHT_EXPECTED_SERVER_ADDR}" DEEDLIGHT_BACKFILL_UNAUTHORIZED_PASSWORD="${DEEDLIGHT_BACKFILL_UNAUTHORIZED_PASSWORD}" psql -X "$@"
}
identity="$(psql_fixture -qAt -F '|' -c "SELECT current_database(), current_setting('server_version_num')::integer / 10000, host(inet_server_addr()), inet_server_port(), session_user")"
IFS='|' read -r database major server_addr server_port login <<< "${identity}"
test "${database}" = "deedlight_migration037_test"
test "${major}" = "16"
test "${server_addr}" = "${DEEDLIGHT_EXPECTED_SERVER_ADDR}"
test "${server_port}" = "5432"
test "${login}" = "postgres"
psql_fixture -v ON_ERROR_STOP=1 --file scripts/test-migration-037-backfill-audit-postgres16-fixture.sql >/dev/null

audit() {
  psql_fixture -qAt -F '|' -v ON_ERROR_STOP=1 --file scripts/production-migration-037-backfill-aggregate-audit.sql
}
first="$(audit)"
IFS='|' read -r projection source_count missing_event missing_stored case_count missing_cases expected_evidence actual_evidence missing_null extra_null missing_fp extra_fp conflicts unmatched rpc_only complete <<< "${first}"
test "${projection}" = "migration_037_backfill_v1"
test "${source_count}" = "3"
test "${missing_event}" = "0"
test "${missing_stored}" = "0"
test "${case_count}" = "2"
test "${missing_cases}" = "0"
test "${expected_evidence}" = "3"
test "${actual_evidence}" = "2"
test "${missing_fp}" = "1"
test "${complete}" = "f"
if printf '%s' "${first}" | grep -Eq 'one@example|two@example|provider-00|evt-00'; then
  echo "FAIL: aggregate audit output exposed a private identifier" >&2
  exit 1
fi
echo "PASS: incomplete Migration 037 backfill is detected using aggregate-only output"

psql_fixture -v ON_ERROR_STOP=1 -c "
INSERT INTO public.delivery_provider_integrity_conflict_evidence (
  conflict_id, recipient_email, event_id, related_event_id, event_type,
  provider_email_id, provider_suppression_id, provider_created_at, bounce_type,
  failure_class, suppression_reason, suppression_origin, suppression_source_id,
  suppression_created_at, payload_fingerprint, stored_event_id, stored_recipient_email,
  evidence_source, observed_at
)
SELECT c.conflict_id, e.recipient_email, a.event_id, a.related_event_id, e.event_type,
  e.provider_email_id, e.provider_suppression_id, e.provider_created_at, e.bounce_type,
  e.failure_class, e.suppression_reason, e.suppression_origin, e.suppression_source_id,
  e.suppression_created_at, e.payload_fingerprint, stored.event_id, stored.recipient_email,
  'legacy_anomaly_backfill', a.detected_at
FROM public.delivery_provider_integrity_anomalies a
JOIN public.delivery_provider_events e ON e.event_id = a.event_id
JOIN public.delivery_provider_integrity_cases c
  ON c.recipient_email = e.recipient_email AND c.anomaly_type = a.anomaly_type
JOIN public.delivery_provider_events stored
  ON stored.event_id = coalesce(a.related_event_id, a.event_id)
WHERE a.event_id = 'evt-003';
" >/dev/null
second="$(audit)"
IFS='|' read -r projection source_count missing_event missing_stored case_count missing_cases expected_evidence actual_evidence missing_null extra_null missing_fp extra_fp conflicts unmatched rpc_only complete <<< "${second}"
test "${complete}" = "t"
test "${expected_evidence}" = "3"
test "${actual_evidence}" = "3"
test "${missing_fp}" = "0"
echo "PASS: complete Migration 037 backfill produces a complete aggregate"

psql_fixture -v ON_ERROR_STOP=1 -c "UPDATE public.delivery_provider_integrity_conflict_evidence SET stored_event_id='evt-001', stored_recipient_email='one@example.invalid' WHERE event_id='evt-003'" >/dev/null
third="$(audit)"
IFS='|' read -r projection source_count missing_event missing_stored case_count missing_cases expected_evidence actual_evidence missing_null extra_null missing_fp extra_fp conflicts unmatched rpc_only complete <<< "${third}"
test "${complete}" = "f"
test "${unmatched}" = "1"
echo "PASS: inconsistent evidence-to-source association fails closed"

if env -i PATH="${PATH}" HOME="${HOME:-/tmp}" PGHOST=127.0.0.1 PGPORT=5432 PGUSER=deedlight_backfill_unauthorized PGPASSWORD="${DEEDLIGHT_BACKFILL_UNAUTHORIZED_PASSWORD}" PGDATABASE=deedlight_migration037_test PGCONNECT_TIMEOUT=5 PGSSLMODE=disable psql -X -qAt -v ON_ERROR_STOP=1 -c "SELECT recipient_email FROM public.delivery_provider_events" >/dev/null 2>&1; then
  echo "FAIL: unauthorized role could read private provider recipient records" >&2
  exit 1
fi
if env -i PATH="${PATH}" HOME="${HOME:-/tmp}" PGHOST=127.0.0.1 PGPORT=5432 PGUSER=deedlight_backfill_unauthorized PGPASSWORD="${DEEDLIGHT_BACKFILL_UNAUTHORIZED_PASSWORD}" PGDATABASE=deedlight_migration037_test PGCONNECT_TIMEOUT=5 PGSSLMODE=disable psql -X -qAt -v ON_ERROR_STOP=1 --file scripts/production-migration-037-backfill-aggregate-audit.sql >/dev/null 2>&1; then
  echo "FAIL: unauthorized role executed the privileged backfill aggregate audit" >&2
  exit 1
fi
echo "PASS: unauthorized database role cannot read underlying records or execute the aggregate audit"
