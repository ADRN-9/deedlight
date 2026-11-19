# C164 — PR #11 Production-readiness remediation

**Repository:** `ADRN-9/deedlight`  
**PR:** #11 — metadata-only delivery schema audit and disposable PostgreSQL 16 fixtures  
**Scope:** dependency-audit remediation, date-independent gentle transport fixture, stronger migration-history metadata and schema-audit tests.  
**Production status:** NO-GO; no Production connection, SQL, migration, deployment, provider send or scheduler action was performed.

## PR #11 failure investigation

The inherited exact-head PR Validation run [43436809787](https://github.com/ADRN-9/deedlight/actions/runs/43436809787), source `aed588d771dc04fda5e5c18d8611239ac926a513`, failed two independent jobs:

1. `validate` failed `npm audit --audit-level=high`: 21 reported advisories (12 moderate, 7 high, 2 critical). The report identified actual affected versions, not merely advisory-database noise: Next.js 16.3.6 (critical cache-poisoning/content-disclosure/RCE/DoS advisories), Zod 4.4.3 (high memory-exhaustion advisory), source-map-js 1.2.1 (high event-loop DoS), Undici 7.29.0 (high transport/cache/TLS/DoS advisories), sharp 0.35.4 (high librsvg dependency advisory), plus affected body-parser 2.3.0, proxy-addr 2.0.7 and qs 6.16.0. The OpenNext/Miniflare dependency tree also carried vulnerable transitive versions.
2. `gentle_delivery_transport_database_behavior` failed at `authorize_delivery_job` with SQLSTATE `42501`, “Delivery claim is not authorized.” The test hard-coded a 2026-10-26 weekly scheduler/claim timestamp while migration 020 correctly rejects claims whose `claim_expires_at <= now()`. This is a stale test fixture, not a reason to relax authorization.

## Dependency remediation

The PR #11 dependency graph now uses the already CI-validated patched dependency set from PR #10, without importing PR #10's unrelated Supabase CLI guard scripts or delivery code:

- Next.js 16.3.6 → 16.4.6.
- Zod 4.4.3 → 4.6.7.
- OpenNext Cloudflare 1.20.2 → 1.20.17 (AWS adapter 4.1.16).
- source-map-js override `^1.2.2`.
- Miniflare 5.20261110.2-beta scoped Undici override 7.30.2.
- Lockfile brings patched body-parser 2.4.0, proxy-addr 2.0.8, qs 6.17.1 and sharp 0.35.5.

The exact PR #10 dependency set passed [run 43356210249](https://github.com/ADRN-9/deedlight). Its unsuppressed `npm audit --audit-level=high` output contained 9 moderate advisories in glob/minimatch (GHSA-3g3m-2fjr-6pw4 and GHSA-g3hv-75wg-m249) and no high/critical findings. These remaining moderate advisories are genuine, not false positives; the audit's suggested `--force` path would downgrade OpenNext Cloudflare to 0.3.0, a breaking adapter change. They remain visible and are not suppressed; the configured high/critical gate passes. Reassess when upstream-compatible fixed releases are available.

## Gentle transport fixture correction

The test now uses the current UTC week and the current transaction timestamp instead of a historical fixed date. The scheduler insert, claim, authorization, idempotent transport-start check and expired-claim rejection run inside one explicit transaction, so `now()` is stable across the fixture. The final ROLLBACK removes synthetic queue mutations. The claim expiry and authorization production logic are unchanged.

## Stronger migration-history and schema-audit coverage

The read-only catalog audit adds `migration_history:catalog_shape`, checking only:

- `supabase_migrations.schema_migrations` exists as an ordinary or partitioned table;
- its `version` column is `text NOT NULL`;
- `version` is the single-column primary key.

Twelve disposable PostgreSQL 16 fixtures now cover the original A-J cases plus:
- K: wrong history `version` type (bigint) → `FAILED`;
- L: composite primary key rather than version-only → `FAILED`.

Case I supplies a valid synthetic history table with one sample row → catalog shape `VERIFIED`. In **every** fixture, `migration_history:recorded_versions` remains `UNKNOWN` and `actual.queried=false`. The assertion consumer rejects any promotion to VERIFIED or any claim that version rows were queried. The SQL remains REPEATABLE READ / READ ONLY and ends in ROLLBACK; it never SELECTs migration-history rows. The original audit archive remains unchanged.

The runner still checks out exact reviewed delivery source `c983e2ed8b93c935139c935343261570ecea6978`, runs only inside the dedicated GitHub Actions PostgreSQL 16 service, refuses Production environment variables and libpq redirects, and creates/drops a separate synthetic database for each case.

## Production migration prerequisites — still blocked

A valid history-table catalog shape is not evidence that migrations 019–024 are recorded or applied, and current catalog shape cannot prove historical execution order. Production reconciliation remains blocked pending:

1. Independent human attestation of the exact Supabase Production project identity.
2. Explicitly authorized least-privilege read-only access to current Production schema, roles and migration-history evidence.
3. Separate, reviewed comparison of live catalog state, actual history rows and repository migration files 019–024.
4. A written reconciliation plan that distinguishes proven applied migrations from unapplied or drifted state.
5. Explicit human approval before any history repair, migration, `supabase db push` or other Production mutation. Never blindly mark migrations applied.

Provider dashboard access, Cloudflare deployment/canary approval, Cron staging, kill-switch exercise and Production smoke remain separate human-authorized gates. No Production secrets or customer data were accessed or changed.

## CI evidence

Exact-head CI was pending when this remediation note was authored. Final PR Validation and the dedicated disposable PostgreSQL 16 workflow run IDs, exact head/tree SHA and outcomes are recorded in PR #11 after completion. A passing synthetic CI run is not Production readiness.
