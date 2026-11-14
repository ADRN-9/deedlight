#!/usr/bin/env bash
# PR10 + C70 replay in isolated GitHub CI with synthetic PostgreSQL.
set -Eeuo pipefail
set +x
BASE=c983e2ed8b93c935139c935343261570ecea6978
AUDIT_BASE=aed588d771dc04fda5e5c18d8611239ac926a513
ROOT=$GITHUB_WORKSPACE
APP=$ROOT/app
AUDIT=$ROOT/audit
INPUT=$ROOT/evidence-src/evidence/deedlight-c72-pr10-c70/inputs
OUT=$ROOT/c72-output
mkdir -p "$OUT"
[[ "$GITHUB_REPOSITORY" == ADRN-9/deedlight ]]
[[ "$GITHUB_REF" == refs/heads/evidence/deedlight-c72-pr10-c70-rehearsal-62bf07c1-v1 ]]
[[ "$DELIVERY_ENABLED" == false ]]
for key in DATABASE_URL SUPABASE_URL SUPABASE_PROJECT_REF SUPABASE_SERVICE_ROLE_KEY SUPABASE_ACCESS_TOKEN SUPABASE_DB_PASSWORD CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID RESEND_API_KEY RESEND_WEBHOOK_SECRET; do
  [[ -z "$(printenv "$key" || true)" ]] || { echo "Forbidden environment variable: $key"; exit 3; }
done
[[ "$(git -C "$APP" rev-parse HEAD)" == "$BASE" ]]
[[ "$(git -C "$AUDIT" rev-parse HEAD)" == "$AUDIT_BASE" ]]
[[ "$(git -C "$APP" hash-object scripts/test-gentle-delivery-transport.sql)" == 5c6442a4b7ac0f8b115113d5cdaa647c8ecad3d1 ]]
[[ "$(git -C "$APP" hash-object supabase/migrations/202611120023_delivery_consent_linearization.sql)" == 75f5086feab2cbda381066cb9094390190c3332f ]]
[[ "$(git -C "$APP" hash-object supabase/migrations/202611120024_delivery_identity_lease_capacity.sql)" == 240271fd75081c062627cfc3d40bdc0c5feda049 ]]
[[ "$(git hash-object "$INPUT/test-gentle-delivery-transport.sql")" == e92c138cedef5ad7d4b2411e7c00cab7f225c5e8 ]]
cp "$INPUT/test-gentle-delivery-transport.sql" "$APP/scripts/test-gentle-delivery-transport.sql"
cd "$APP"
node - <<'NODE'
const p=require("./package.json");
if(p.dependencies.next!=="16.4.6" || p.dependencies.zod!=="4.6.7"
  || p.devDependencies["@opennextjs/cloudflare"]!=="1.20.17"
  || p.overrides?.["source-map-js"]!=="^1.2.2"
  || p.overrides?.["miniflare@5.20261110.2-beta"]?.undici!=="7.30.2"
  || !p.scripts["supabase:link"].startsWith("bash scripts/guard-supabase-migration-target.sh && ")
  || !p.scripts["supabase:push"].startsWith("bash scripts/guard-supabase-linked-project.sh && "))
  throw Error("PR10 delivery dependency or migration guard drift");
NODE
npm install --package-lock-only --save-exact --save-dev wrangler@4.162.0 --ignore-scripts \
  > "$OUT/npm-lock-resolution.log" 2>&1
node - <<'NODE'
const p=require("./package.json"),l=require("./package-lock.json");
if(p.devDependencies.wrangler!=="4.162.0"
||l.packages[""].devDependencies.wrangler!=="4.162.0"
||l.packages["node_modules/wrangler"]?.version!=="4.162.0"
||p.overrides["source-map-js"]!=="^1.2.2"
||p.overrides["miniflare@5.20261110.2-beta"]?.undici!=="7.30.2"
||JSON.stringify(l.packages[""].dependencies)!==JSON.stringify(p.dependencies)
||JSON.stringify(l.packages[""].devDependencies)!==JSON.stringify(p.devDependencies))
 throw Error("Candidate dependency lock/guard inconsistency");
console.log("Dependency lockfile and PR10 security controls: PASS");
NODE
git diff --check
git diff --name-only | sort > "$OUT/changed-files.txt"
diff -u <(printf '%s\n' package-lock.json package.json scripts/test-gentle-delivery-transport.sql | sort) "$OUT/changed-files.txt"
git add -- package.json package-lock.json scripts/test-gentle-delivery-transport.sql
git diff --cached --check
git diff --cached --binary > "$OUT/C72_PR10_C70_INTEGRATION.patch"
git write-tree > "$OUT/integration-tree.txt"
git rev-parse HEAD > "$OUT/pr10-base-commit.txt"
[[ -s "$OUT/C72_PR10_C70_INTEGRATION.patch" ]]
git worktree add --detach "$RUNNER_TEMP/deedlight-pr10-patch-replay" "$BASE" >/dev/null
git -C "$RUNNER_TEMP/deedlight-pr10-patch-replay" apply --check "$OUT/C72_PR10_C70_INTEGRATION.patch"
git -C "$RUNNER_TEMP/deedlight-pr10-patch-replay" apply "$OUT/C72_PR10_C70_INTEGRATION.patch"
git -C "$RUNNER_TEMP/deedlight-pr10-patch-replay" add -- package.json package-lock.json scripts/test-gentle-delivery-transport.sql
[[ "$(git -C "$RUNNER_TEMP/deedlight-pr10-patch-replay" write-tree)" == "$(cat "$OUT/integration-tree.txt")" ]]
git worktree remove --force "$RUNNER_TEMP/deedlight-pr10-patch-replay"
echo "git apply --check, clean replay and exact Git tree identity: PASS" | tee "$OUT/patch-integrity.log"
cp package.json "$OUT/package.json"
cp package-lock.json "$OUT/package-lock.json"
cp scripts/test-gentle-delivery-transport.sql "$OUT/test-gentle-delivery-transport.sql"
printf 'PR10 base=%s\nPR11 audit=%s\nC70 SQL blob=%s\nRehearsal tree=%s\n' "$BASE" "$AUDIT_BASE" e92c138cedef5ad7d4b2411e7c00cab7f225c5e8 "$(cat "$OUT/integration-tree.txt")" > "$OUT/IDENTITIES.txt"
npm ci > "$OUT/npm-ci.log" 2>&1
for script in verify-sprint12-1-security.mjs verify-sprint12-2-delivery-security.mjs \
 verify-delivery-reliability.mjs verify-gentle-delivery-transport.mjs \
 verify-delivery-consent-gates.mjs verify-auth-pgcrypto-schema-qualification.mjs; do
  echo "node scripts/$script" >> "$OUT/test-commands.log"
  node "scripts/$script" > "$OUT/$script.log" 2>&1
  echo "$script: PASS" | tee -a "$OUT/security-results.txt"
done
node --test scripts/test-delivery-transport.mjs > "$OUT/delivery-transport-js.log" 2>&1
echo 'Delivery transport JS behavior: PASS' | tee -a "$OUT/security-results.txt"
set +e
npm audit --json > "$OUT/npm-audit.json" 2> "$OUT/npm-audit-json.stderr"
audit_json_exit=$?
set -e
echo "npm audit --json exit=$audit_json_exit (includes moderate findings)" > "$OUT/audit-json-status.txt"
npm audit --audit-level=high > "$OUT/npm-audit-high.log" 2>&1
node - "$OUT/npm-audit.json" <<'NODE'
const fs=require("node:fs"),x=JSON.parse(fs.readFileSync(process.argv[2],"utf8"));
const v=x.metadata?.vulnerabilities;
if(!v || v.high || v.critical) throw Error("Unresolved high/critical advisories");
fs.writeFileSync(process.argv[2]+".summary",JSON.stringify(v)+"\n");
console.log("High/critical audit PASS; actual counts:",JSON.stringify(v));
NODE
npx tsc --noEmit > "$OUT/typescript.log" 2>&1
npm run build > "$OUT/next-build.log" 2>&1
npx opennextjs-cloudflare build > "$OUT/cloudflare-package.log" 2>&1
echo 'Dependency audit, TypeScript, Next and Cloudflare packaging: PASS' | tee "$OUT/app-validation.txt"
(
 cd "$AUDIT/security/audit-deedlight"
 sha256sum --strict --check MANIFEST.sha256 > "$OUT/pr11-manifest.log"
 python3 original/check_package_static.py > "$OUT/pr11-original-static.log" 2>&1
 python3 audited/check_package_static.py > "$OUT/pr11-audited-static.log" 2>&1
 python3 -m unittest discover -s tests -v > "$OUT/pr11-unit-tests.log" 2>&1
)
echo 'PR11 static checks at immutable audit source SHA: PASS' | tee "$OUT/pr11-result.log"
export PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres
psql -X -At -v ON_ERROR_STOP=1 -d postgres -c 'show server_version;' > "$OUT/postgresql-version.txt"
for database in deedlight_test deedlight_reliability_test deedlight_transport_test deedlight_auth_test deedlight_migration_order_test; do
  createdb "$database"
done
run_pg() {
 local tag="$1" db="$2" file="$3"
 echo "psql -X -v ON_ERROR_STOP=1 -d $db -f $file" >> "$OUT/test-commands.log"
 psql -X -v ON_ERROR_STOP=1 -d "$db" -f "$file" > "$OUT/$tag.log" 2>&1
 echo "$tag: PASS" | tee -a "$OUT/postgresql-results.txt"
}
run_pg sprint12 deedlight_test scripts/test-sprint12-2-delivery.sql
run_pg reliability deedlight_reliability_test scripts/test-delivery-reliability-terminals.sql
run_pg transport-consent deedlight_transport_test scripts/test-delivery-consent-gates.sql
bash scripts/test-delivery-consent-concurrency.sh > "$OUT/transport-concurrency.log" 2>&1
echo "transport-concurrency: PASS" | tee -a "$OUT/postgresql-results.txt"
run_pg auth-pgcrypto deedlight_auth_test scripts/test-auth-pgcrypto-schema-qualification.sql
bash scripts/test-delivery-migration-order.sh > "$OUT/delivery-migration-order.log" 2>&1
echo "delivery-migration-order: PASS" | tee -a "$OUT/postgresql-results.txt"
grep -q '"gentle_delivery_transport_db": "pass"' "$OUT/transport-consent.log"
grep -q '"expired_and_stale_claims": "pass"' "$OUT/transport-consent.log"
grep -q 'Concurrent consent lock wait with expiring claim: PASS' "$OUT/transport-concurrency.log"
echo 'Live, expired, stale, consent, identity and migration-order regressions: PASS' | tee "$OUT/c72-regressions.log"
(
 cd "$OUT"
 find . -maxdepth 1 -type f ! -name SHA256SUMS.txt -printf '%P\n' | sort | \
  while IFS= read -r file; do sha256sum "$file"; done > SHA256SUMS.txt
)
echo "C72 isolated replay PASS: $(cat "$OUT/integration-tree.txt")"
