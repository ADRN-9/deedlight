# Deedlight outbound delivery rollout tracker

**Status: PRODUCTION NO-GO.** This tracker separates repository evidence from Production evidence. A green CI run does not prove live consent, provider, scheduler, ledger, or kill-switch behavior.

## Current code and review state

- Delivery-security branch: `security/delivery-transport-consent-gates`.
- Historical C225 independent-review target: HEAD `2d5d00371409a151c7c2ce23cb978b2eaa867e91`, tree `64253539093d9057a571c8a3103766292cf370ce`, base `ce82b3fdf1a73510de70e3729a487d4ae00e66e3`.
- Current reviewed branch HEAD: `cb82b3b31311eef2a8f177ff22998b99c74371dc`, tree `9415f9da3fe366f1923cd576e70a83db13912e2e`, parent `2ba303e613ed9f4d2a7f401cf49e46f5356d9d03`; the live PR and branch refs matched this exact commit at C232 start.
- PR #10 remains OPEN, DRAFT, UNMERGED. C222 added SQL ACL assertions for the private provider lifecycle implementation; commit `2d5d00371409a151c7c2ce23cb978b2eaa867e91`.
- Migrations 028 and 029 are part of the reviewed delivery path. C226 adds migration 030 for database-authoritative provider idempotency timing and validated Resend receipts.
- C225 findings: HIGH — migration 029 trusted a matching signature without proving migration-027 implementation identity; MEDIUM — Worker-clock skew could underestimate provider idempotency age; MEDIUM — provider receipt IDs were accepted without format validation.
- C226 remediation: migration 029 pins the migration-027 PL/pgSQL source SHA-256 and verifies SECURITY DEFINER/search_path metadata; migration 030 moves retry/horizon decisions to PostgreSQL `clock_timestamp()`, checks persisted `transport_started_at`, and validates provider UUID receipts before the sent transition. C230 exact-head CI and C231 independent-review disposition are recorded below; these establish engineering acceptance only, not Production acceptance.
- Read-only GitHub inspection reports `main.protected=false` and no repository rulesets; main branch protection is therefore not established. Production Environment branch restrictions/required approvals and Production secret scoping remain unverified.
- No Production migration, provider send, webhook configuration, Cron activation, secret change, or kill-switch mutation is part of this work.

## Rollout order and gates

| Gate | Required evidence | Current disposition |
|---|---|---|
| Delivery security in CI | Exact-head assertions, fake transport, PostgreSQL behavior and concurrency tests | C230 branch run #754 `44944676676` and PR run #755 `44944681070` both SUCCESS, 7/7; C231 independent reviewer disposition ACCEPT. CI/reviewer acceptance is not Production acceptance. |
| Provider failure lifecycle | Signed event intake; bounce, complaint, suppression, failure classification and validated Resend receipt UUIDs | Repository tests cover receipt format; live provider evidence absent |
| Duplicate and conflicting events | Event-ID idempotency, payload fingerprint conflicts, provider-ID recipient binding, terminal-outcome anomalies | PostgreSQL and synchronized concurrency fixtures exist; Production unverified |
| Consent before each send | Fresh preference/profile/Auth-email/curated-issue locks in final transport RPC; denial means zero provider calls | PostgreSQL CI proves post-transport-start consent revocation returns `cancelled` / `authorization_revoked` and clears the claim; Production revocation test not run |
| Retry and ambiguous outcomes | Five-minute DB-timed retry, five-attempt cap, stable provider key, DB-clock 23-hour horizon, stale-token rejection | C230 exact-head PostgreSQL CI passes negative two-hour Worker clock skew, 24-hour/1-second expiry, receipt validation and DB-authoritative horizon; Production provider ambiguity evidence absent |
| Daily scheduler | Explicit approval, staged Cron, multiple healthy cycles and ledger/provider reconciliation | NOT ACTIVATED / NOT VERIFIED in C208 |
| Kill switch | Exercise \`DELIVERY_ENABLED=false\`, prove no new enqueue/claim/send, then safe re-enable | NOT EXERCISED in C208 |
| Weekly Goodness | Daily accepted first; explicit curation, 5,000 logical-row cap, separate Cron only after Daily evidence | HELD; no Weekly activation |
| Production regression | Authenticated/unauthenticated journeys, privacy, moderation, DB and Cloudflare checks | NOT RUN in C208 |
| Release | Exact-head CI, authorized deploy, Production smoke, rollout approval | BLOCKED |

## Delivery safety invariants

1. \`DELIVERY_ENABLED\` must remain disabled until a separately approved staged rollout.
2. Daily delivery precedes Weekly Goodness. Weekly stays inactive until multiple healthy Daily cycles, kill-switch behavior, and safe re-enablement are evidenced.
3. Every external attempt must pass current database authorization immediately before transport. Consent, suspension, current confirmed recipient identity, claim token and live lease are checked together. A claim token alone never grants send authority.
4. Resend uses one stable idempotency key per logical ledger job. PostgreSQL calculates retries from persisted first-transport evidence and its own clock; the Worker cannot extend the safe horizon. Ambiguous outcomes fail closed after the 23-hour boundary.
5. Provider webhook events cannot enqueue, claim, retry, or mutate the delivery ledger. Conflicting events remain private integrity anomalies; they never overwrite original evidence or project contradictory terminal outcomes as success.
6. Permanent/unknown bounce, complaint, and provider suppression block subsequent attempts. Transient bounce remains observable but does not suppress.
7. Recipient addresses, provider diagnostics, raw webhook bodies, claim tokens, and service credentials remain private/server-side.
8. Suppression is never cleared automatically. Any manual correction requires independent review and evidence that the address is safe to contact.

## Provider setup — human-only

An authorized operator must create the Resend webhook endpoint, subscribe to the seven supported lifecycle events, store \`RESEND_WEBHOOK_SECRET\` only as a server-side Cloudflare secret, and verify the endpoint is associated with the same Resend account used for outbound delivery. Do not copy the signing secret into source control, client configuration, chat, or logs. Provider test events must be deliberately authorized and must not be used to send real member messages without separate approval.

## Human-only GitHub governance blocker

**Responsible administrator:** the ADRN-9 repository owner (or a delegated GitHub organization/repository administrator with Environment administration rights). A named human approver must be designated before the Production gate can close; no administrator identity is inferred here.

Read-only repository evidence currently shows `main.protected=false` and an empty repository rulesets list. Production Environment branch restrictions, required reviewers, the `Prevent self-review` setting, and secret scopes were not available for independent verification.

The administrator must complete these settings manually:

1. Protect `main`: require PR review and required CI checks, disallow force-push and branch deletion, and require the approved review policy.
2. Restrict the Production Environment to deployments from protected `main` only.
3. Require independent Production Environment approval and enable `Prevent self-review`.
4. Keep Production credentials only in the Production Environment secret store. Remove duplicate Production credentials at repository and organization scope; never expose secret values in evidence.
5. Prevent PR authors from satisfying their own review requirement.

Evidence required to close this blocker: read-only branch/ruleset API output showing `main.protected=true` and required checks/reviews; Environment settings export or screenshots showing protected-main-only deployment, required independent reviewers and self-review prevention; and secret-name/scope inventory proving Production secrets exist only at Environment scope (values redacted). The repository owner/admin must attest the configuration and identify the independent approver.

## Production prerequisites and rollback

Before any migration or activation, independently inspect the live Production schema and reconcile historical Supabase migration history. Do not use normal \`supabase db push\`, mark unknown migrations applied, or reset Production based on repository state.

Rollback is operational and fail-closed: disable new outbound work, remove future Cron triggers, allow already-authorized requests to drain, and reconcile ledger/provider outcomes. Preserve queue and suppression history. Keep the inbound provider webhook available while outbound delivery is disabled; it is a safety intake path, not an outbound activation. Never restore an obsolete consent-bypassing RPC or clear suppression state to make delivery resume.

## C208 evidence ledger

- Pre-C208 exact-head PR #10 validation: [44875441190](https://github.com/ADRN-9/deedlight/actions/runs/44875441190), 7/7 PASS at \`95fb79152243f9581647eae961f3c35cf5d1043b\`.
- Pre-C208 exact-head push validation: [44875436665](https://github.com/ADRN-9/deedlight/actions/runs/44875436665), 7/7 PASS at the same SHA.
- C208 provider-payload compatibility source/test head: `06ca8cf1e21215645bd70dd93f178cd954196929` (tree `fe5e4f98a084d56ee2594fed231b3e8f0d5388f3`). Exact-head [push run 44903890652](https://github.com/ADRN-9/deedlight/actions/runs/44903890652) and [PR run 44903895136](https://github.com/ADRN-9/deedlight/actions/runs/44903895136) both completed **7/7 PASS** at that SHA. All database behavior jobs, provider webhook/concurrency tests, transport revocation races, TypeScript, Next build, Cloudflare packaging, and dependency audit passed.
- No live Production provider, ledger, Cron, consent-revocation, or kill-switch evidence is claimed.

## C226 remediation evidence ledger

- C225 reviewed target: `2d5d00371409a151c7c2ce23cb978b2eaa867e91`, tree `64253539093d9057a571c8a3103766292cf370ce`.
- C222 SQL ACL regression: `scripts/test-delivery-provider-webhooks.sql` asserts effective privileges for `anon`, `authenticated`, and `service_role`, including the renamed private implementation and legacy RPC overloads.
- Historical C222 exact-head validation: [push run 44929835404](https://github.com/ADRN-9/deedlight/actions/runs/44929835404) and [PR run 44929840101](https://github.com/ADRN-9/deedlight/actions/runs/44929840101), both 7/7 PASS at C222 HEAD.
- C226 migration 029 identity regression: migration-order test mutates the migration-027 implementation without changing its signature/security metadata, expects migration 029 to reject and roll back, then restores the original and proves the positive migration path plus 5/7/8-argument historical replay.
- C226 migration 030 regression: isolated PostgreSQL tests cover Worker clock two hours behind, skew beyond the 23-hour safety horizon, expired 24-hour provider retention, pre-send fail-closed behavior, invalid/whitespace/control-character receipt IDs, and missing transport-start evidence.
- C230 exact-head CI: PASS at HEAD `cb82b3b31311eef2a8f177ff22998b99c74371dc`, tree `9415f9da3fe366f1923cd576e70a83db13912e2e`. Branch Push Validation #754 ([44944676676](https://github.com/ADRN-9/deedlight/actions/runs/44944676676)) completed SUCCESS, 7/7 jobs; its `validate`, migration-order, delivery reliability, gentle transport, provider webhook, Sprint 12.2 and Auth pgcrypto jobs all passed. PR Validation #755 ([44944681070](https://github.com/ADRN-9/deedlight/actions/runs/44944681070)) completed SUCCESS, 7/7 jobs. Its validation jobs checked out synthetic merge commit `008e57c534ec24b6de882053635bf9fc0d5b735f`; treat this as PR merge-ref integration evidence, while #754 is the exact branch-HEAD run.
- C230 migration 029 PostgreSQL regression: PASS — deliberate migration-027 function-source drift is rejected, migration rollback is atomic, and the positive migration path plus historical 5/7/8-argument replay compatibility pass. Exact job: Push run #754 `delivery_migration_order_database_behavior` (job `136969257779`).
- C230 migration 030 PostgreSQL regression: PASS — DB-authoritative idempotency horizon, negative Worker clock skew (Worker clock two hours behind), expired 24-hour provider retention (`24 hours 1 second`), provider receipt validation, and consent revocation after transport start all pass. The consent fixture reports `result cancelled, state cancelled, error authorization_revoked`; the assertion also requires the claim token and expiry to be cleared. Exact job: Push run #754 job `136969257779`.
- C230 aggregate SQL parity: PASS — `scripts/verify-delivery-reliability.mjs` confirms the canonical migration, migration 028, and migration 030 are mirrored verbatim in `supabase/run_in_sql_editor_all.sql`. Independent file comparison at the reviewed HEAD also confirms both migration 029 and migration 030 contents occur verbatim in the aggregate. Migration 029 blob SHA `872fc49ec47e49b17e96ecf6ccaf5c8eb0e6322a`; migration 030 blob SHA `42c227cc1c36b2889e88d9bee1432e6fc6829d41`; aggregate blob SHA `83725a196186f4fd913fab1cf5c9c02c9c6d822c`.
- C230 security/validation: PASS — migration 030 return-type and method-specific adapter assertions, final DB authorization ordering, consent cancellation, expired/unknown authorization fail-closed checks, TypeScript, Next.js production build, Cloudflare packaging, and ESLint (changed delivery-security files) passed in Push run #754. `npm audit --audit-level=high` passed; it still reports **9 moderate-severity advisories**, retained as tracked dependency-maintenance work. The CI job ran with `DELIVERY_ENABLED=false`, non-Production URLs, and no Production API credentials.
- C231 independent review disposition: **ACCEPT**, as reported in the Manager's C232 handoff. Qualification: the accessible GitHub PR reviews endpoint returned zero submitted reviews, the accessible PR issue-comment history contains no C231 review artifact, and the PR body contains no C231 entry. Record this as the independent reviewer disposition supplied to this handoff, not as a formal GitHub PR approval, merge, or Production authorization.
- Engineering acceptance is distinct from Production acceptance. PR #10 remains OPEN / DRAFT / UNMERGED. No Production deployment, database mutation, provider operation, Cron activation, kill-switch exercise, credential change, approval, or merge is evidenced by these CI runs.
- Dependency maintenance: preserve the **9 moderate** npm advisories as tracked maintenance work. The configured high/critical audit gate passed; do not suppress the moderate findings or apply forced breaking dependency changes as part of this tracker update.
- Administrative blockers: main branch protection is not established (`main.protected=false`; repository rulesets list empty). Production Environment deployment restrictions and independent approval/self-review controls are unverified. Production secret scoping (Environment-only versus repository/organization scope) is unverified.
- Production remains **NO-GO**. Outstanding rollout gates: Daily Cron staged activation; multiple healthy Daily cycles; live provider failure, bounce and complaint handling; Production `DELIVERY_ENABLED=false` kill-switch exercise; safe re-enablement; curated Weekly Cron after Daily acceptance; authenticated Production regression; Supabase migration-history/live-schema reconciliation; authorized Production deployment; and final Production smoke tests. Do not close the rollout tracker or create a `sprint-*-complete` tag until all applicable gates are evidenced.
- Human-only GitHub governance and all Production rollout gates remain open. Production remains NO-GO.
