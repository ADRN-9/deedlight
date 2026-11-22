#!/usr/bin/env bash
set -euo pipefail

runner="scripts/test-privacy-authorization-database.sh"
if [[ ! -x "$runner" ]]; then
  echo "Privacy database runner is missing or not executable: $runner" >&2
  exit 1
fi

if ! grep -Fq 'trap cleanup_on_exit EXIT' "$runner" ||
   ! grep -Fq 'legacy_fixture_active=1' "$runner" ||
   ! grep -Fq 'if [[ "$legacy_fixture_active" == "1" ]]; then' "$runner"; then
  echo "Privacy database runner is missing its historical-fixture EXIT cleanup guard." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/bin"

cat > "$tmpdir/bin/psql" <<EOF
#!/usr/bin/env bash
touch "$tmpdir/psql-was-invoked"
exit 97
EOF
chmod +x "$tmpdir/bin/psql"
test_path="$tmpdir/bin:$PATH"

expect_valid() {
  local label="$1"
  shift
  if ! env -i PATH="$test_path" "$@" "$runner" --validate-config-only >"$tmpdir/valid.log" 2>&1; then
    cat "$tmpdir/valid.log" >&2
    echo "Supported $label PostgreSQL configuration was rejected." >&2
    exit 1
  fi
  if [[ -e "$tmpdir/psql-was-invoked" ]]; then
    echo "psql was invoked during $label configuration validation." >&2
    exit 1
  fi
}

expect_rejected() {
  local label="$1"
  shift
  rm -f "$tmpdir/psql-was-invoked"
  if env -i PATH="$test_path" "$@" "$runner" --validate-config-only >"$tmpdir/rejected.log" 2>&1; then
    echo "Unsafe $label PostgreSQL configuration was accepted." >&2
    exit 1
  fi
  if [[ -e "$tmpdir/psql-was-invoked" ]]; then
    echo "psql was invoked for unsafe $label PostgreSQL configuration." >&2
    exit 1
  fi
  if ! grep -Fq "Refusing unsafe PostgreSQL destination" "$tmpdir/rejected.log"; then
    cat "$tmpdir/rejected.log" >&2
    echo "Unsafe $label configuration did not fail at the destination guard." >&2
    exit 1
  fi
}

expect_valid "local" PGHOST=localhost PGPORT=5432 PGUSER=postgres PGDATABASE=deedlight_privacy_test
expect_valid "GitHub Actions" PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=deedlight_privacy_test

expect_rejected "remote host" PGHOST=192.0.2.10 PGPORT=5432 PGUSER=postgres PGDATABASE=deedlight_privacy_test
expect_rejected "nonstandard port" PGHOST=127.0.0.1 PGPORT=5433 PGUSER=postgres PGDATABASE=deedlight_privacy_test
expect_rejected "privileged user" PGHOST=127.0.0.1 PGPORT=5432 PGUSER=service_role PGDATABASE=deedlight_privacy_test
expect_rejected "non-test database" PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=postgres
expect_rejected "host address override" PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=deedlight_privacy_test PGHOSTADDR=192.0.2.10
expect_rejected "service override" PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=deedlight_privacy_test PGSERVICE=production
expect_rejected "service file override" PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=deedlight_privacy_test PGSERVICEFILE=/tmp/production.pg_service.conf
expect_rejected "session options override" PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGDATABASE=deedlight_privacy_test PGOPTIONS='-c role=service_role'

echo "Privacy runner destination safety assertions PASS"
