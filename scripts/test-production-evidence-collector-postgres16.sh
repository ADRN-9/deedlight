#!/usr/bin/env bash
set -euo pipefail

: "$DEEDLIGHT_POSTGRES_CONTAINER_ID"
: "$RUNNER_TEMP"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

readonly project_ref="xaipiovflxomcbfwtwmu"
readonly endpoint_host="db.$project_ref.supabase.co"
readonly fixture_db="deedlight_migration_order_test"
readonly fixture_auth="deedlight-postgres16-ci-disposable-v1"
readonly work="$RUNNER_TEMP/deedlight-collector-e2e-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
rm -rf "$work"
mkdir -m 700 -p "$work/tls"

redirect_id="$DEEDLIGHT_POSTGRES_REDIRECT_CONTAINER_ID"
redirect_addr="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$redirect_id")"
[[ "$redirect_addr" =~ ^[0-9]{1,3}(\\.[0-9]{1,3}){3}$ ]]
tls_container_id="$DEEDLIGHT_POSTGRES_CONTAINER_ID"

export DEEDLIGHT_EXPECTED_SERVER_ADDR="127.0.0.1"
export DEEDLIGHT_REDIRECT_SERVER_ADDR="$redirect_addr"
export DEEDLIGHT_DISPOSABLE_FIXTURE_AUTHORIZATION="$fixture_auth"
export DEEDLIGHT_FIXTURE_AUDITOR_PASSWORD="$(openssl rand -hex 32)"
export DEEDLIGHT_FIXTURE_SPOOFED_PASSWORD="$(openssl rand -hex 32)"
export DEEDLIGHT_FIXTURE_PRIVILEGED_PASSWORD="$(openssl rand -hex 32)"

# Prepare only the synthetic schema precondition expected by the repository fixture.
env -i PATH="$PATH" HOME="$HOME" PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres \\
  PGDATABASE="$fixture_db" PGSSLMODE=disable psql -X -v ON_ERROR_STOP=1 \\
  -c "CREATE SCHEMA auth AUTHORIZATION postgres"

# The repository fixture's disposable endpoint label is populated from the actual
# server address inside the same PostgreSQL session, avoiding host-port NAT ambiguity.
sed "s/SELECT pg_catalog.set_config('deedlight.fixture_expected_server_addr', :'fixture_expected_server_addr', false);/SELECT pg_catalog.set_config('deedlight.fixture_expected_server_addr', pg_catalog.host(pg_catalog.inet_server_addr()), false);/" \\
  scripts/test-production-migration-readonly-audit-postgres16-fixture.sql >"$work/collector-fixture.sql"
env DEEDLIGHT_EXPECTED_SERVER_ADDR="$DEEDLIGHT_EXPECTED_SERVER_ADDR" \\
  DEEDLIGHT_DISPOSABLE_FIXTURE_AUTHORIZATION="$DEEDLIGHT_DISPOSABLE_FIXTURE_AUTHORIZATION" \\
  DEEDLIGHT_FIXTURE_AUDITOR_PASSWORD="$DEEDLIGHT_FIXTURE_AUDITOR_PASSWORD" \\
  DEEDLIGHT_FIXTURE_SPOOFED_PASSWORD="$DEEDLIGHT_FIXTURE_SPOOFED_PASSWORD" \\
  DEEDLIGHT_FIXTURE_PRIVILEGED_PASSWORD="$DEEDLIGHT_FIXTURE_PRIVILEGED_PASSWORD" \\
  PGPASSWORD=postgres psql -X -h 127.0.0.1 -p 5432 -U postgres -d "$fixture_db" \\
  -v ON_ERROR_STOP=1 --file "$work/collector-fixture.sql"

tls="$work/tls"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
  -keyout "$tls/ca.key" -out "$tls/ca.crt" \
  -subj "/CN=DeedLight disposable collector test CA" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes \
  -keyout "$tls/server.key" -out "$tls/server.csr" \
  -subj "/CN=$endpoint_host" >/dev/null 2>&1
cat >"$tls/server.ext" <<EOF
subjectAltName=DNS:$endpoint_host
extendedKeyUsage=serverAuth
keyUsage=digitalSignature,keyEncipherment
EOF
openssl x509 -req -in "$tls/server.csr" -CA "$tls/ca.crt" -CAkey "$tls/ca.key" \
  -CAcreateserial -out "$tls/server.crt" -days 2 -sha256 -extfile "$tls/server.ext" >/dev/null 2>&1

docker exec "$tls_container_id" mkdir -p /var/lib/postgresql/data/deedlight-tls
docker cp "$tls/server.crt" "$tls_container_id:/var/lib/postgresql/data/deedlight-tls/server.crt"
docker cp "$tls/server.key" "$tls_container_id:/var/lib/postgresql/data/deedlight-tls/server.key"
docker exec -u postgres "$tls_container_id" chmod 600 /var/lib/postgresql/data/deedlight-tls/server.key
docker exec -u postgres "$tls_container_id" chown postgres:postgres \
  /var/lib/postgresql/data/deedlight-tls/server.crt /var/lib/postgresql/data/deedlight-tls/server.key

PGPASSWORD=postgres psql -X -h 127.0.0.1 -p 5432 -U postgres -d "$fixture_db" \
  -v ON_ERROR_STOP=1 -c "ALTER SYSTEM SET ssl = 'on'" \
  -c "ALTER SYSTEM SET ssl_cert_file = '/var/lib/postgresql/data/deedlight-tls/server.crt'" \
  -c "ALTER SYSTEM SET ssl_key_file = '/var/lib/postgresql/data/deedlight-tls/server.key'" \
  -c "SELECT pg_catalog.pg_reload_conf()"
for attempt in {1..30}; do
  if PGPASSWORD=postgres psql -X -h 127.0.0.1 -p 5432 -U postgres -d "$fixture_db" -At -c "SHOW ssl" | grep -Fxq on; then break; fi
  sleep 1
done
PGPASSWORD=postgres psql -X -h 127.0.0.1 -p 5432 -U postgres -d "$fixture_db" -At -c "SHOW ssl" | grep -Fxq on

if ! getent hosts "$endpoint_host" >/dev/null; then
  echo "127.0.0.1 $endpoint_host" | sudo tee -a /etc/hosts >/dev/null
fi
getent hosts "$endpoint_host" | grep -Fq "127.0.0.1"

cat >"$work/collector-endpoint.json" <<EOF
{
  "schemaVersion": 1,
  "projectRef": "$project_ref",
  "host": "$endpoint_host",
  "port": 5432,
  "database": "$fixture_db",
  "username": "deedlight_catalog_auditor",
  "tlsRootCertPath": "$tls/ca.crt",
  "passwordFilePath": "$work/collector.pgpass"
}
EOF
chmod 600 "$work/collector-endpoint.json"
printf '%s:%s:%s:%s:%s\n' "$endpoint_host" 5432 "$fixture_db" \
  deedlight_catalog_auditor "$DEEDLIGHT_FIXTURE_AUDITOR_PASSWORD" >"$work/collector.pgpass"
chmod 600 "$work/collector.pgpass"

# Confirm the dedicated login cannot read synthetic application rows over verified TLS.
if PGHOST="$endpoint_host" PGPORT=5432 PGUSER=deedlight_catalog_auditor PGDATABASE="$fixture_db" \\
  PGPASSFILE="$work/collector.pgpass" PGSSLROOTCERT="$tls/ca.crt" PGSSLMODE=verify-full \\
  /usr/bin/psql -X -w -v ON_ERROR_STOP=1 -c "SELECT private_value FROM public.audit_fixture_private" \\
  >"$work/application-data.stdout" 2>"$work/application-data.stderr"; then
  echo "FAIL: collector login unexpectedly read synthetic application data" >&2
  exit 1
fi

profile_digest="$(sha256sum "$work/collector-endpoint.json" | awk '{print $1}')"
# Hostile inherited libpq settings must not redirect or weaken the collector's child.
PGHOSTADDR="$redirect_addr" PGSERVICE="attacker" PGSERVICEFILE="/dev/null" \
PGOPTIONS="-c search_path=pg_catalog" PGSSLMODE=disable PGPASSWORD=wrong \
DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256="$profile_digest" \
  node scripts/collect-production-migration-evidence.mjs \
    --profile "$work/collector-endpoint.json" --output "$work/evidence-success"

node --input-type=module - "$work/evidence-success" <<'NODE'
import assert from "node:assert/strict";
import { readFileSync, statSync } from "node:fs";
import { verifyReceiptAndEvidence } from "./scripts/collect-production-migration-evidence.mjs";
const dir = process.argv[2];
const receipt = JSON.parse(readFileSync(dir + "/receipt.json", "utf8"));
const evidence = readFileSync(dir + "/evidence.csv");
assert.equal(receipt.status, "UNSIGNED_NOT_ACCEPTED");
assert.equal(receipt.projectRef, "xaipiovflxomcbfwtwmu");
assert.equal(receipt.execution.authenticatedPrincipal, "deedlight_catalog_auditor");
assert.equal(receipt.endpoint.tlsMode, "verify-full");
assert.equal(verifyReceiptAndEvidence(receipt, evidence), true);
assert.equal(statSync(dir).mode & 0o777, 0o700);
assert.equal(statSync(dir + "/receipt.json").mode & 0o777, 0o600);
assert.equal(statSync(dir + "/evidence.csv").mode & 0o777, 0o600);
NODE

# Wrong trusted CA: TLS chain verification must fail before evidence is emitted.
openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
  -keyout "$tls/wrong-ca.key" -out "$tls/wrong-ca.crt" \
  -subj "/CN=Untrusted DeedLight test CA" >/dev/null 2>&1
jq --arg ca "$tls/wrong-ca.crt" '.tlsRootCertPath = $ca' \
  "$work/collector-endpoint.json" >"$work/wrong-ca-profile.json"
chmod 600 "$work/wrong-ca-profile.json"
wrong_ca_digest="$(sha256sum "$work/wrong-ca-profile.json" | awk '{print $1}')"
if DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256="$wrong_ca_digest" \
  node scripts/collect-production-migration-evidence.mjs \
    --profile "$work/wrong-ca-profile.json" --output "$work/evidence-wrong-ca" \
    >"$work/wrong-ca.stdout" 2>"$work/wrong-ca.stderr"; then
  echo "FAIL: collector accepted a server certificate signed by an untrusted CA" >&2
  exit 1
fi
grep -Fq "SQL_EXECUTION_FAILED" "$work/wrong-ca.stderr"
test ! -e "$work/evidence-wrong-ca/receipt.json"

# A trusted certificate with the wrong SAN must also fail verify-full.
openssl req -newkey rsa:2048 -nodes \
  -keyout "$tls/wrong-host.key" -out "$tls/wrong-host.csr" \
  -subj "/CN=wrong-host.invalid" >/dev/null 2>&1
printf 'subjectAltName=DNS:wrong-host.invalid\nextendedKeyUsage=serverAuth\nkeyUsage=digitalSignature,keyEncipherment\n' >"$tls/wrong-host.ext"
openssl x509 -req -in "$tls/wrong-host.csr" -CA "$tls/ca.crt" -CAkey "$tls/ca.key" \
  -CAcreateserial -out "$tls/wrong-host.crt" -days 2 -sha256 -extfile "$tls/wrong-host.ext" >/dev/null 2>&1
docker cp "$tls/wrong-host.crt" "$tls_container_id:/var/lib/postgresql/data/deedlight-tls/server.crt"
docker cp "$tls/wrong-host.key" "$tls_container_id:/var/lib/postgresql/data/deedlight-tls/server.key"
docker exec -u postgres "$tls_container_id" chmod 600 /var/lib/postgresql/data/deedlight-tls/server.key
docker exec -u postgres "$tls_container_id" chown postgres:postgres \
  /var/lib/postgresql/data/deedlight-tls/server.crt /var/lib/postgresql/data/deedlight-tls/server.key
PGPASSWORD=postgres psql -X -h 127.0.0.1 -p 5432 -U postgres -d "$fixture_db" \
  -v ON_ERROR_STOP=1 -c "SELECT pg_catalog.pg_reload_conf()"
sleep 2
if DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256="$profile_digest" \
  node scripts/collect-production-migration-evidence.mjs \
    --profile "$work/collector-endpoint.json" --output "$work/evidence-wrong-host" \
    >"$work/wrong-host.stdout" 2>"$work/wrong-host.stderr"; then
  echo "FAIL: collector accepted a certificate with an incorrect hostname SAN" >&2
  exit 1
fi
grep -Fq "SQL_EXECUTION_FAILED" "$work/wrong-host.stderr"
test ! -e "$work/evidence-wrong-host/receipt.json"

# Wrong project reference is rejected even when the profile digest is recomputed.
jq '.projectRef = "incorrect-project"' "$work/collector-endpoint.json" >"$work/wrong-project-profile.json"
chmod 600 "$work/wrong-project-profile.json"
wrong_project_digest="$(sha256sum "$work/wrong-project-profile.json" | awk '{print $1}')"
if DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256="$wrong_project_digest" \
  node scripts/collect-production-migration-evidence.mjs \
    --profile "$work/wrong-project-profile.json" --output "$work/evidence-wrong-project" \
    >"$work/wrong-project.stdout" 2>"$work/wrong-project.stderr"; then
  echo "FAIL: collector accepted an incorrect project reference" >&2
  exit 1
fi
grep -Fq "ENDPOINT_IDENTITY_MISMATCH" "$work/wrong-project.stderr"
test ! -e "$work/evidence-wrong-project/receipt.json"

echo "PASS: collector direct login, PostgreSQL 16 fixture, TLS chain/hostname, endpoint pinning, environment isolation and receipt verification"
