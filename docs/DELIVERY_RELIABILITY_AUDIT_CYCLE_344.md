# DeedLight outbound delivery reliability audit — Cycle 344

**Audit date:** 2026-11-23  
**Repository:** `ADRN-9/deedlight`  
**Primary PR:** [#10 — delivery consent and transport security](https://github.com/ADRN-9/deedlight/pull/10)  
**Inspected source HEAD:** `cfe05475dbe7822f96be639fd2c777a6062aedc4`  
**PR state:** OPEN / DRAFT / UNMERGED  
**Disposition:** **ENGINEERING CI PASS; PRODUCTION NO-GO; ONE HIGH-PRIORITY FAIL-CLOSED GAP IDENTIFIED**

## Scope and safety

Read-only inspection of PR #10 delivery implementation, database migrations, tests, workflow configuration, and rollout evidence. No source code or migration was modified. No Production database, provider, credentials, secrets, Cron settings, Worker settings, or deployment configuration was accessed or changed. No PR review, approval, or merge was submitted.

No local shell/test execution is claimed. CI evidence below is retrieved from GitHub Actions for the exact inspected source HEAD.

## Executive summary

The delivery implementation has strong repository-level controls:

- Resend-only server-side transport with fail-closed configuration.
- Current consent, suspension, exact confirmed Auth email, schedule/curation and provider suppression checked by database RPCs immediately before each provider request.
- Five-minute database-timed retries, five-attempt cap, five-minute claim leases, stale-token rejection, and a database-authoritative 23-hour retry/send horizon.
- Stable per-logical-job Resend idempotency keys.
- Signed, bounded, replay-aware provider webhooks; permanent/unknown bounce, complaint, and provider suppression handling; timestamp-ordered suppression-list synchronization.
- Separate exact Daily and Weekly cron routing; Weekly requires curation and a 5,000-logical-delivery ceiling.
- Automated PostgreSQL behavior/concurrency tests and transport/webhook tests.

**High-priority finding:** a conflicting duplicate provider event ID is recorded as an integrity anomaly, but the recipient is not necessarily placed under a delivery hold. The final transport gate checks only `delivery_provider_suppressions`, not unresolved integrity anomalies. If the original event was non-suppressing (for example, `email.delivered`) and the conflicting payload claims a complaint or bounce, future Daily/Weekly sends can remain eligible. The suppression-list duplicate-conflict path has a corresponding untested reverse-order case (original manual removal, conflicting add). This does not invalidate the many existing suppression tests, but it leaves a narrow fail-closed hole under provider-integrity ambiguity.

Production readiness is independently blocked: no live provider evidence, no Production webhook/account verification, no staged Daily Cron, no Production kill-switch exercise, no multiple healthy Daily cycles, no Weekly activation, no Production regression/smoke, and unresolved Production migration history. The candidate `wrangler.jsonc` still has an empty Cron list.

## Evidence matrix

| Area | Implemented behavior | Automated coverage | Exact-head CI | Production evidence / gap |
|---|---|---|---|---|
| Provider HTTP failures | Network/timeout, 408, 429, 5xx and concurrent idempotency 409 are retryable; other 4xx, auth rejection and idempotency conflict are terminal. Malformed 2xx is treated as ambiguous/retryable. | `scripts/test-delivery-transport.mjs` covers timeout/network, 408/429/5xx, 400/404, 401/403, 409, malformed 2xx and invalid receipts. | 29/29 transport tests passed in Validate. | No real Resend failure, quota, auth-rejection or timeout test was performed. |
| Permanent bounce / complaint | Permanent and unknown bounce, complaint, `previous_bounce`, `previous_complaint`, and generic provider suppression create address-level holds. Transient bounce is recorded without a hold. Complaint takes precedence over permanent bounce. | `scripts/test-delivery-provider-webhooks.sql`, `scripts/test-delivery-webhook.mjs`, signed route tests and concurrency suite cover the main paths and ordering. | Provider webhook DB behavior and concurrency job passed. 48 parser/route tests passed. | No live Resend webhook subscription, provider dashboard, controlled bounce or complaint evidence. |
| Provider suppression list | `suppression.added/removed` uses a separate suppression ID/state projection. Manual removal can clear only a matched generic provider hold; bounce/complaint-origin holds remain. Event-time ordering and shared recipient locks are implemented. | SQL tests cover add/remove ordering, missing add, equal timestamps, cross-stream ordering, bounce/complaint holds, duplicate and concurrency cases. | Provider webhook DB job passed. | Dedicated DeedLight Resend account and webhook subscriptions are operational prerequisites; neither is evidenced in Production. |
| Consent and recipient | `processClaimedDelivery` authorizes, resolves current Auth recipient, reauthorizes, begins transport, then calls the final recipient/consent/suppression/idempotency RPC before Resend. SQL locks preferences/profile/Auth/curated rows and serializes with suppression intake. | `scripts/test-delivery-consent-gates.sql`, `scripts/test-delivery-consent-concurrency.sh`, transport tests cover revocation, suspension, recipient change and both lock orders. | Gentle transport DB job and consent concurrency step passed. | No Production opt-out/revocation race was exercised. A revocation after the final authorization transaction commits cannot recall an already-authorized in-flight HTTP request; this boundary is documented. |
| Claim leases / stale tokens | Database claim leases, post-lock wall-clock checks, new claim tokens on reclaim, and live-lease checks on authorize/retry/sent/failed transitions. | `scripts/test-delivery-reliability-terminals.sql`, `scripts/test-delivery-reliability-concurrency.sh` cover retry exhaustion and lock-wait expiry. | Delivery reliability DB job passed. | No Production crash/reclaim observation. |
| Bounded retries | Retry time is fixed at five minutes using PostgreSQL `clock_timestamp()`; attempt five is terminal. Retry is refused when the 23-hour provider safety horizon would be crossed. | SQL terminal/concurrency tests and transport tests cover retry exhaustion and DB-authoritative time. | Delivery reliability DB job passed. | No live provider outage/ambiguous-response retry cycle. Fixed five-minute delay does not honor provider `Retry-After` or use jitter; see P2. |
| Provider idempotency | Stable key `deedlight/<kind>/<job-id>`; same key reused for each logical job retry. Resend receipt must be a canonical UUID. Database refuses further attempts near the 23-hour boundary. | Transport tests assert stable key, ambiguous 2xx handling and receipt validation; SQL/static tests cover DB-clock expiry and stale claims. | Validate and reliability DB jobs passed. | Provider-side deduplication has not been observed live. Resend documents a 24-hour key retention period; DeedLight's 23-hour cutoff is conservative. |
| Emergency kill switch | `DELIVERY_ENABLED` must equal `true`; any other/missing value disables the invocation before reading secrets. Disabled invocation returns no work. | Unit tests prove disabled no-work behavior and no secret reads. CI itself sets `DELIVERY_ENABLED=false`. | Validate passed. | Production switch not exercised. It is read once at invocation start; it does not stop a batch already running or an HTTP request already authorized. |
| Daily / Weekly scheduler | Custom Worker `scheduled()` invokes the scheduler. Exact cron strings are recognized; unknown strings are ignored. Daily is every five minutes; Weekly is Monday 16:00 UTC and requires an explicitly curated issue. | Schedule routing, Daily/Weekly enqueue, capacity, curation and database authorization tests pass. | All 8 CI jobs passed. | Candidate `wrangler.jsonc` has `crons: []`. Daily and Weekly are not activated in this branch. Production Cron state and runtime cycles are unverified. |

## Prioritized findings

### P1 — Integrity-anomaly events do not reliably block recipient eligibility

**Files / functions**

- `supabase/migrations/202611200027_delivery_provider_integrity.sql` — `_record_delivery_provider_lifecycle_event_fingerprinted_impl`, duplicate-event conflict branch after `ON CONFLICT (event_id) DO NOTHING`.
- `supabase/migrations/202611220032_resend_suppression_list_sync.sql` and `202611230034_delivery_suppression_timestamp_order.sql` — `record_delivery_provider_suppression_event`, duplicate-event conflict branch.
- `supabase/migrations/202611220031_delivery_final_recipient_suppression_gate.sql` — `authorize_delivery_idempotency_window`.
- `scripts/test-delivery-provider-webhooks.sql`.
- `scripts/test-delivery-provider-webhook-concurrency.sh`.

**Observed behavior**

For a conflicting duplicate lifecycle event ID, the RPC records `duplicate_event_id_conflict`, marks the original provider-email lifecycle projection `integrity_anomaly`, and returns NULL. It does not create a suppression for the original recipient. The suppression-list duplicate-event conflict branch similarly records an anomaly and returns NULL without changing the prior suppression state.

The final authorization RPC checks `delivery_provider_suppressions` for the current recipient. It does not deny on a matching `integrity_anomaly` or unresolved integrity-anomaly record.

Therefore, if the original lifecycle event was `email.delivered` / `email.sent` (no suppression) and a conflicting signed event reuses that event ID with `email.complained` or a permanent bounce, the lifecycle becomes anomalous but no recipient hold is created. The final gate can still authorize a later send. A corresponding suppression-list case exists if a manual removal is the original event and a conflicting add reuses its event ID.

**Coverage gap**

Existing duplicate-lifecycle conflict coverage seeds a permanent bounce first, so the original suppression row already blocks the address. The concurrent suppression-conflict test seeds `suppression.added` first and conflicting `suppression.removed`, so the state remains active. Neither proves the fail-closed reverse cases above.

**Risk**

A valid provider-integrity anomaly can leave an address eligible despite contradictory complaint/bounce/suppression evidence. This violates the intended fail-closed behavior for uncertain provider state.

**Recommended Developer action**

1. Add a recipient-scoped integrity hold based only on the original persisted event's recipient (never trust the conflicting payload's recipient to suppress an arbitrary third party).
2. Make the final transport gate deny while an unresolved provider integrity anomaly affects that recipient/provider identity.
3. Provide a narrow, auditable operator resolution path; do not automatically clear the hold on a later unrelated event.
4. Add PostgreSQL behavior and concurrency regressions for:
   - original `email.delivered` then same-ID conflicting `email.complained`;
   - original `email.sent` then same-ID conflicting permanent/unknown bounce;
   - original `suppression.removed` then same-ID conflicting `suppression.added`;
   - conflicting payload targeting a different recipient must not suppress that different recipient;
   - Daily and Weekly final authorization must both deny the original affected recipient until explicit resolution.

This is a source-level finding from the inspected migrations; the failing scenario was not executed against Production.

### P1 — Production acceptance evidence is absent

**Evidence**

- `wrangler.jsonc` at inspected HEAD has `triggers.crons: []`.
- `docs/DELIVERY_ROLLOUT_TRACKER.md` explicitly records PRODUCTION NO-GO, no staged Daily Cron, no healthy Daily cycles, no kill-switch exercise, no safe re-enablement, Weekly held, no Production regression/smoke, and no live provider evidence.
- `docs/DELIVERY_PROVIDER_WEBHOOKS.md` requires a dedicated DeedLight Resend account and subscriptions for seven lifecycle plus two suppression-list events.
- `docs/GENTLE_DELIVERY_TRANSPORT.md` explicitly distinguishes CI from Production runtime evidence.
- PR #10 is OPEN / DRAFT / UNMERGED.

**CI boundary**

The PR workflow deliberately sets `DELIVERY_ENABLED=false`, uses non-Production URLs/placeholders, and asserts that Production credentials and Resend secrets are absent. Transport and webhook tests use fake fetch and synthetic PostgreSQL fixtures. This is correct for CI, but cannot prove provider delivery or Production authorization.

**Recommended next action**

After P1 integrity remediation and independent review, use an authorized operator-approved rollout: verify the dedicated provider account/webhook configuration, approved canary, staged Daily Cron, multiple healthy Daily cycles, Production kill-switch exercise, safe re-enablement, and only then curated Weekly Cron. Collect provider dashboard, webhook receipt, ledger, deployment and runtime evidence. Do not activate Weekly first or infer success from source/CI.

### P1 — Production migration and deployment governance are not ready

**Evidence**

- GitHub reports `main.protected=false`; repository rulesets endpoint returns an empty list.
- `.github/workflows/supabase-migrations.yml` requires `github.ref == 'refs/heads/main' && github.ref_protected`. With current `main.protected=false`, that job cannot satisfy its own protected-main gate.
- `docs/PRODUCTION_MIGRATION_RECONCILIATION.md` records 36 migration files, 35 unique version prefixes, two distinct bodies sharing migration version `202607260007`, and all Production migration/schema effects UNKNOWN because authorized read-only Production history/catalog evidence is unavailable.
- Production Environment approvals and secret scopes remain unverified in the rollout tracker.

**Recommended next action**

Owner/admin must establish and verify protected-main required checks/reviews, Production Environment independent approval and self-review prevention, and Environment-only credential scope. Separately obtain scoped read-only Production migration history/catalog/audit evidence and resolve the duplicate-007 history/schema discrepancy. Do not run normal Production `supabase db push` or mark migrations applied by assumption.

### P2 — Kill switch does not interrupt an invocation already in progress

**Files / functions**

- `lib/delivery/config.ts` — `parseDeliveryRuntimeConfig`.
- `lib/delivery/scheduler.ts` — `runScheduledDelivery`.
- `lib/delivery/run-delivery.ts` — `processClaimedDelivery`.
- `docs/GENTLE_DELIVERY_TRANSPORT.md` — Rollback / kill switch.

**Observed behavior**

`DELIVERY_ENABLED` is parsed once when `runScheduledDelivery` starts. Setting it false prevents future invocations after the binding propagates, but does not stop an already-running batch or an HTTP request already authorized by the final gate. The documentation correctly discloses this limitation.

**Recommended Developer action**

Decide whether the acceptance contract requires only future-invocation shutdown or also interruption of the remaining jobs in an active batch. If the latter, add a service-role-only database delivery-control row checked atomically by the final per-job gate; test disabling between two jobs and assert the second job makes zero provider calls. No database control can recall a request already authorized and sent. Production must still exercise the documented drain/disable/cron-removal procedure.

### P2 — Integrity anomalies have no demonstrated operator inspection/alert path

**Evidence**

Migrations 027/032 keep provider events, suppression state and integrity-anomaly tables private and revoke direct table privileges, including from `service_role`. The inspected delivery migrations/routes expose write-only RPCs for intake; no safe operator-facing anomaly summary/inspection RPC or alert path was identified. CI reads the tables as the database owner in synthetic tests.

**Recommended Developer action**

Add a narrowly scoped admin/operations read RPC or sanitized operational report for anomaly counts/types/timestamps and affected provider identifiers. Avoid returning recipient addresses, raw webhook bodies, diagnostics, secrets or message content. Alert on unresolved integrity anomalies and repeated webhook 503 responses.

### P2 — `email.failed` is recorded but intentionally does not suppress or change the ledger

**Evidence**

- Migrations 026/027 persist a normalized `failure_class` (`invalid_recipient`, `provider_authentication`, `domain_verification`, `quota_exceeded`, `content_rejected`, `unknown`).
- The lifecycle RPC does not set a suppression reason for `email.failed`; it does not mutate the delivery ledger.
- `scripts/test-delivery-provider-webhooks.sql` explicitly asserts that failed lifecycle events do not create recipient suppressions.
- `scripts/test-delivery-webhook.mjs` covers normalization, including invalid recipient.

**Assessment**

This appears intentional rather than an accidental omission. However, `invalid_recipient` remains eligible for future Daily/Weekly logical deliveries unless a separate suppression-list event or other hold is received. Confirm that this is the intended product policy. If invalid-recipient failures are permanent, introduce a distinct fail-closed address hold and tests; do not suppress for provider authentication, domain, quota or transient account-level failures.

### P2 — Retry delay is fixed, without provider Retry-After or jitter

**Files**

- `lib/delivery/resend-transport.ts` — `classifyProviderFailure`.
- `supabase/migrations/202611210030_delivery_idempotency_receipt_guard.sql` — `retry_delivery_job`.

**Observed behavior**

Retryable HTTP/network/timeout outcomes are requeued after a fixed five minutes, for at most five attempts and only while within the DB-clock 23-hour horizon. This is bounded and safe against indefinite retries, but does not honor a provider Retry-After value or add jitter.

**Recommended Developer action**

Consider a bounded Retry-After-aware delay for 429/503 and capped exponential backoff with jitter. Keep PostgreSQL authoritative, cap every delay by the remaining idempotency horizon, and preserve the five-attempt limit. This is an availability improvement, not a demonstrated duplicate-send defect.

### P2 — Rollout tracker source baseline is stale

`docs/DELIVERY_ROLLOUT_TRACKER.md` and `docs/PRODUCTION_MIGRATION_RECONCILIATION.md` identify PR #10 source HEAD `c256a1e959f42d0a66b47ad16b3aef3b4705f11e`; the inspected PR HEAD is now `cfe05475dbe7822f96be639fd2c777a6062aedc4`. The tracker still contains older C208/C230 evidence references and historical rollout rows. Its NO-GO disposition remains appropriate, but the exact source baseline and current CI references should be refreshed by the Developer/Manager after the next implementation commit.

## Exact-head CI evidence

Both GitHub Actions runs checked out the exact inspected source HEAD `cfe05475dbe7822f96be639fd2c777a6062aedc4` and completed successfully with all eight jobs:

- Push Validation [run 45175563783](https://github.com/ADRN-9/deedlight/actions/runs/45175563783): SUCCESS, 8/8.
- PR Validation [run 45165655190](https://github.com/ADRN-9/deedlight/actions/runs/45165655190): SUCCESS, 8/8.

The Validate job passed:
- delivery security assertions and current-consent/migration-target assertions;
- Resend provider webhook security assertions;
- ESLint on the configured delivery/webhook files;
- 29/29 delivery transport tests;
- 48/48 webhook parser/route tests;
- TypeScript check;
- Next.js production build;
- Cloudflare/OpenNext packaging build;
- `npm audit --audit-level=moderate` (0 vulnerabilities reported in this run).

The PostgreSQL 16 jobs passed:
- provider webhook lifecycle/suppression behavior and synchronized webhook concurrency;
- consent/transport race behavior;
- lease expiry under row-lock contention;
- migration ordering and duplicate-007 CLI behavior;
- privacy authorization, Auth pgcrypto and Sprint 12.2 database behavior.

This is strong engineering CI evidence for the exact source HEAD. It is not Production evidence. The workflow explicitly runs with outbound delivery disabled and no Production credentials.

## Production evidence status

| Required evidence | Status |
|---|---|
| Live Resend send / provider receipt / ledger reconciliation | NOT VERIFIED |
| Provider failure, permanent bounce and complaint handling in Production | NOT VERIFIED |
| Production webhook signature, endpoint subscriptions and dedicated-account isolation | NOT VERIFIED |
| Current-consent revocation race in Production | NOT VERIFIED |
| Daily Cron staged activation and multiple healthy cycles | NOT ACTIVATED / NOT VERIFIED |
| Production `DELIVERY_ENABLED=false` exercise | NOT EXERCISED |
| Safe re-enablement after kill-switch test | NOT VERIFIED |
| Curated Weekly Cron after Daily acceptance | HELD / NOT ACTIVATED |
| Production authenticated regression and final smoke | NOT RUN |
| Production migration history/live schema reconciliation | UNKNOWN / BLOCKED |
| Authorized Production deploy and exact deployed revision | NOT VERIFIED |

## Recommended next Developer cycle

1. Fix P1 integrity-anomaly eligibility gap with recipient-safe fail-closed holds and reverse-order duplicate-ID PostgreSQL tests for lifecycle and suppression events.
2. Add a safe operator-facing anomaly inspection/alert path.
3. Decide and test kill-switch semantics for an active batch; implement the database control gate if required.
4. Obtain an explicit product/operations decision for `email.failed: invalid_recipient` eligibility.
5. Consider bounded Retry-After-aware backoff without extending the 23-hour provider idempotency horizon.
6. Refresh the rollout tracker to the current exact source HEAD and CI runs after implementation.

## Final disposition

**Engineering:** substantial implementation; exact-head CI PASS (8/8 push and 8/8 PR integration).  
**Security/reliability:** P1 provider-integrity fail-closed gap requires remediation before Production activation.  
**Production:** **NO-GO**. Live provider, webhook, Cron, kill-switch, migration, deployment and smoke evidence remains incomplete.  
**Reviewer actions:** no PR approval, review submission, merge, source edit, migration edit, credential operation or Production operation performed.
