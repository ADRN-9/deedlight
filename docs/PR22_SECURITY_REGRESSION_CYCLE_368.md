# PR #22 — Cycle 368 security and regression verification

**Repository:** `ADRN-9/deedlight`  
**PR:** [#22](https://github.com/ADRN-9/deedlight/pull/22)  
**Branch:** `security/private-daily-journey-admin-isolation-c408`  
**Starting HEAD reconciled:** `06480c266e7bfb3d7da3f291d610085c8322d00c`  
**Disposition:** Repository regression suites pass on the reconciled starting HEAD. Production SECURITY DEFINER owner attestation remains blocked on authoritative DBA evidence. No Production operation was performed.

## Scope and evidence

The starting PR metadata was re-read before changes: PR #22 was OPEN, DRAFT, unmerged, and based on `security/delivery-transport-consent-gates`. Its head matched the assigned starting SHA exactly. The branch had five commits ahead of its base and zero commits behind. The PR ancestry and draft/open state were preserved.

The existing exact-starting-HEAD GitHub Actions run [45467874361](https://github.com/ADRN-9/deedlight/actions/runs/45467874361) completed SUCCESS with all eight jobs successful. Its complete job inventory and step conclusions were inspected:

- `validate`
- `delivery_provider_webhook_database_behavior`
- `delivery_migration_order_database_behavior`
- `delivery_reliability_database_behavior`
- `privacy_authorization_database_behavior`
- `auth_pgcrypto_database_behavior`
- `gentle_delivery_transport_database_behavior`
- `sprint12_2_database_behavior`

This workflow ran on GitHub-hosted PostgreSQL 16 disposable services and the non-production CI configuration. It is not Production evidence.

## Regression coverage inspected

### Provider integrity — migration 037 and 038

The provider database job ran `scripts/test-delivery-provider-webhooks.sql` and `scripts/test-delivery-provider-webhook-concurrency.sh`. The SQL fixture applies migrations 025, 026, 027, 029, 032, 033, 034, 037 and 038 in the isolated test database; it seeds a pre-037 anomaly before 037 to exercise legacy anomaly backfill.

The successful run explicitly reported:

- Provider-integrity direct retrieval, exact counts, keyset boundaries, administrator append-only denial and newest reopening visibility: PASS.
- Concurrent conflicting duplicate integrity anomaly: PASS.
- Concurrent cross-recipient provider email ID collision with durable evidence: PASS.
- Concurrent exact/conflicting suppression events and cross-recipient suppression-ID isolation: PASS.
- Concurrent simultaneous first-insert event-ID conflict: PASS.
- Legacy seven-argument lifecycle wrapper event-ID-first locking: PASS.
- Legacy eight-argument compatibility wrapper event-ID-first locking: PASS.
- Five-argument legacy event wrapper event-ID-first locking: PASS.
- Concurrent suppression first-insert event-ID conflict: PASS.
- Controlled PostgreSQL deadlock: SQLSTATE 40P01, exactly one victim, surviving transaction acquired the released lock and committed, and final state contained only the survivor row: PASS.
- Existing bounded advisory-lock timeout: SQLSTATE 55P03 and unchanged database state: PASS.
- Process deadlines, bounded waits, watchdog and cleanup sentinel: PASS.

Migration 038 negative preflight fixtures deliberately induce source, grant, SECURITY DEFINER/search-path and missing-signature drift and assert atomic rollback. The corresponding PostgreSQL ERROR records in the service log are expected negative-test evidence; the provider job and all its steps completed successfully. They are not unhandled test failures.

### Canonical and legacy RPC behavior

The SQL and static regression coverage checks the canonical fingerprinted lifecycle RPC and its compatibility overloads, the legacy provider-event wrapper, and the suppression RPC. It verifies service-role-only execution for trusted provider writes, browser-role denial, fingerprint enforcement, canonical stored-event preservation on conflicting payloads, and consistent event-ID-first lock ordering before recipient and provider correlation locks. Legacy timestamp lookup is asserted to occur only after the corresponding locks.

### Recipient isolation and admin authorization

The provider-integrity tests cover recipient-bound cases, provider email-ID and suppression-ID reuse across recipients, preservation of the original canonical event, and unresolved anomalies remaining fail-closed. Authenticated non-admins are denied case listing, direct case retrieval, evidence/history pages, and resolution (SQLSTATE 42501). The admin RPCs require the existing `is_admin()` contract. Private case/evidence/history tables are not directly readable by browser roles or service_role.

### Immutable identifiers, keyset pagination and append-only evidence

The migration-038 and SQL tests verify immutable `conflict_id` ordering for case pagination (not mutable `last_detected_at`), exact totals, complete continuation cursors, no duplicate or skipped rows when new evidence arrives between requests, and newest reopening visibility. Evidence and resolution history reject UPDATE and DELETE through append-only triggers, including owner-level attempts. Partial/malformed cursors fail closed.

### Migration 036 — private Daily Journey reflection isolation

The privacy authorization database job ran `scripts/test-privacy-authorization-database.sh`, which applied migration 036 after the historical Daily reflection migrations. The assertions and fixture cleanup passed. Migration 036 removes the permissive admin-readable reflection policies and leaves authenticated SELECT/INSERT/UPDATE owner-only through `user_id = auth.uid()`; it does not grant browser DELETE. The suite reports:

- Privacy and authorization database behavior assertions: PASS.
- Fixture cleanup after behavior suite: PASS.
- Privacy and authorization database behavior: PASS.

### Delivery reliability and consent enforcement

The delivery reliability job passed terminal-state and retry-bound tests, including maximum attempt count five and expired-lease behavior under row-lock contention for `authorize_delivery_job`, `retry_delivery_job`, `mark_delivery_sent`, and `mark_delivery_failed`.

The gentle transport job passed daily/weekly consent, recipient identity, stale/expired claim, suspension/revocation, capacity and issue-wide cap assertions. Both synchronized revocation-first and transport-first races passed, as did consent-lock contention with expiring claims and weekly late-opt-in capacity behavior.

The validation job passed provider webhook/security assertions, consent-gate assertions, 29 transport unit tests, 48 webhook unit tests, TypeScript, Next.js production build, Cloudflare packaging, ESLint and moderate-or-higher dependency audit.

### Migration compatibility and historical files

The migration-order job passed positive and negative migration-order behavior, source drift/atomic rollback checks, and the pinned Supabase CLI duplicate-007 regression. Expected negative fixture errors include duplicate migration version (23505) and missing `daily_post_id` (42703); the harness asserts the resulting state and reports the duplicate-007/008/012/013 dependency suite PASS.

Migrations 036, 037 and 038 were read and revalidated through the disposable PostgreSQL CI fixtures and static verifier. No historical migration file was edited, reordered, renamed or rewritten. The SQL Editor aggregate mirror assertions passed. Production application status of migrations 036–038 remains UNKNOWN.

## SECURITY DEFINER ownership — P0 BLOCKER

The Production owner contract for all 18 exact SECURITY DEFINER signatures remains unavailable. Migration 038 currently verifies exact function source hashes, SECURITY DEFINER state, `proconfig` search paths, and EXECUTE privileges. It does not verify `pg_proc.proowner` against an approved expected owner. The source files do not use explicit `ALTER FUNCTION ... OWNER TO`; PostgreSQL assigns the executing role as owner, which can differ between CI, SQL Editor and Production. A CI owner is not a Production baseline.

**Do not guess or hardcode** `postgres`, `supabase_admin`, a migration runner, `current_user`, or any other role. Do not weaken migration 038, alter its historical SQL, or add guessed owner mappings or owner-drift expectations.

### Exact DBA dependency

A Production project owner/DBA must:

1. Independently verify the exact Production Supabase project reference `xaipiovflxomcbfwtwmu`.
2. Grant an existing connected identity project-scoped read-only access to that exact project, or provide an approved dedicated PostgreSQL audit connection.
3. Enforce read-only transactions and a least-privilege audit role. It must not inherit service-role, administrator, migration, schema-write, credential-management, or outbound-delivery authority; no `BYPASSRLS`, superuser, CREATEROLE, CREATEDB or REPLICATION.
4. Execute the prepared SELECT-only ownership inventory in `docs/PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md`, Query 8A, returning exactly 18 rows for the enumerated identity signatures. Every row must prove function presence, SECURITY DEFINER state, exact search-path configuration, ACL, `pg_proc.proowner`, resolved owner name and owner-role attributes.
5. Execute Query 8B to enumerate direct and transitive owner-role memberships, including INHERIT/SET options and effective membership privileges.
6. Have the Production DBA/security owner explicitly approve the expected owner mapping for each of the 18 signatures, acceptable owner-role attributes, and permitted membership/SET ROLE paths. Store raw evidence only in the access-controlled Production evidence location, not this public PR.
7. Have an independent database/security reviewer approve that owner contract before implementing expected-owner checks and positive/negative owner-drift fixtures. The negative fixture must prove preflight failure is atomic.

The 18-signature inventory is enumerated in Query 8A of the read-only audit packet. It includes `is_admin()`, canonical and legacy provider RPCs, migration-037 private helpers and admin RPCs, and migration-038 case/detail/evidence/history page RPCs.

Until these steps are complete, owner attestation is BLOCKED. No guessed owner mapping or owner fixture is safe. Production migration/effect classifications for 036–038 remain UNKNOWN until authorized read-only migration history and catalog evidence are independently reviewed.

## Production and release boundary

No Production migrations, deployments, merges, scheduler activation, delivery enablement, credentials, or privileged operations were performed. PR #22 remains OPEN and DRAFT. The Production ownership blocker and migration-application uncertainty remain explicit; CI success must not be interpreted as Production proof.
