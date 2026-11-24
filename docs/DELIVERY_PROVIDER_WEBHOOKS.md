# Deedlight Resend Provider Webhook Contract

## Scope

Migration 025 established authenticated bounce/complaint suppression and the shared suppression/transport lock. Additive migration 026 extends the server-only `POST /api/webhooks/resend` route to persist all seven email lifecycle events. Additive migration 027 adds full-payload idempotency fingerprints, private integrity-anomaly recording, and normalized Resend suppression reasons. Migration 032 adds the separate `suppression.added` / `suppression.removed` contract without treating suppression-record IDs as email IDs. The complete endpoint accepts seven email lifecycle events plus these two suppression-list events. It does not activate outbound delivery, configure a Production webhook, or send messages.

## Provider configuration (human-only)

Before a Production rollout, an authorized operator must:

1. Create a Resend webhook endpoint targeting `https://deedlight.com/api/webhooks/resend`.
2. Subscribe to the seven email lifecycle events and both `suppression.added` and `suppression.removed` events. Suppression-list events are account/team-wide and do not carry the `application=deedlight` email tag; use a dedicated Resend account for Deedlight rather than sharing this endpoint with unrelated products.
3. Store the returned `whsec_` signing secret as the server-only Cloudflare secret `RESEND_WEBHOOK_SECRET`.
4. Confirm the webhook belongs to a Resend account dedicated to Deedlight. Email lifecycle events must include the `application=deedlight` tag; suppression-list events are account-wide and intentionally do not require that tag.
5. Send a deliberately authorized, synthetic/provider-test event only after the Production canary approval and verify webhook, database and provider-dashboard evidence.

Do not put the signing secret in `NEXT_PUBLIC_*`, source control, client configuration, ordinary logs, or chat. Webhook processing also requires server-side `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. The inbound endpoint intentionally remains available while `DELIVERY_ENABLED=false`; the outbound kill switch must not disable safety intake.

## Authenticity and replay protection

- Verification uses the exact raw UTF-8 request body and the Resend/Svix `svix-id`, `svix-timestamp`, and `svix-signature` headers.
- HMAC-SHA256 v1 signatures are verified using the base64 key in the `whsec_` secret. The signature header is capped at 4,096 characters, at most five v1 candidates are considered (supporting bounded key rotation), and every decoded candidate must be exactly 32 bytes. Malformed or excessive candidates are rejected before cryptographic verification.
- Timestamps more than five minutes in the past or future are rejected.
- The request body is streamed with a 64 KiB maximum.
- Email lifecycle events are processed only when tagged `application=deedlight`; suppression-list events are account-wide and are processed without that email-only tag. Other unrelated Resend event types are acknowledged without changing Deedlight data.
- The provider event ID is the database primary key. Exact signed-body replays are idempotent no-ops, including concurrent duplicate deliveries. A reused event ID with conflicting normalized fields, or different fingerprints when both are present, records an integrity anomaly, preserves the original event and suppression state, and returns a retryable failure.
- A SHA-256 fingerprint of the exact signed request body supports full-payload comparison for events that have one. Rows created before migration 027 and trusted legacy RPC calls may have no fingerprint (and historical suppression rows may have no normalized suppression reason). For those rows, the RPC compares every field available to the older schema and treats missing new metadata as unknown; it never fabricates a digest or overwrites the original event. Two present, unequal fingerprints remain a conflict. Raw webhook bodies and provider diagnostics are not stored.
- Provider `created_at` is preserved as `provider_created_at`; `received_at` is assigned by PostgreSQL at receipt.
- Invalid signatures return 401, malformed signed payloads return 400, oversized bodies return 413, and missing server configuration or database failures return 503 so the provider can retry.

## Provider payload compatibility

The parser follows Resend's published webhook examples rather than assuming optional diagnostic metadata is always present:

- `data.bounce.diagnosticCode` is optional. The documented bounce example omits it and uses `subType: "Suppressed"`; this subtype is accepted and the permanent bounce still suppresses the address.
- `data.suppressed.diagnosticCode` and `data.suppressed.reason` are optional. Resend's published `OnAccountSuppressionList` example includes neither. Missing or unrecognized suppression reasons map to the generic `provider_suppressed` class, which still blocks future sends.
- Explicit `previous_bounce` and `previous_complaint` reasons retain their more specific mapping and complaint precedence.

These cases are covered by parser and signed-route regression tests using the provider's documented payload shape. References: [Resend Webhook Event Visibility](https://resend.com/changelog/webhook-event-visibility) and [Resend Email Suppression Visibility](https://resend.com/changelog/email-suppression-visibility).

## Lifecycle and ordering

The lifecycle projection is keyed by Resend's provider email ID, which is bound to exactly one normalized recipient address. The RPC takes a transaction-scoped advisory lock for that provider email ID before inserting the event; a concurrent event that reuses the ID for another recipient aborts and rolls back the entire transaction. It cannot create a second event, change the original lifecycle projection, or create suppression for the rejected recipient. Events are retained individually, while the projection advances monotonically by evidence rank. A delayed event may legitimately arrive after delivery and cannot regress the projection. A complaint after delivery is also valid later evidence. Incompatible terminal outcomes (including delivered/bounced, delivered/failed, and delivered/suppressed) are retained in event history, recorded in a private integrity-anomaly table, and projected as `integrity_anomaly` rather than successful delivery. Reused event IDs with conflicting payloads also mark the original lifecycle projection anomalous without replacing the original event or changing its suppression. The legacy 025 service-role RPC remains as a compatibility wrapper for its original three event types; because that signature has no provider timestamp parameter, it records database receipt time in that legacy path. The webhook route uses the 027 RPC and the actual provider event timestamp.

`email.delivery_delayed` is informational. Resend retries deferred delivery itself; Deedlight does not resend, reset a retry, reset a claim, or re-enqueue in response to any lifecycle event. `email.failed` is recorded with one normalized class only: `invalid_recipient`, `provider_authentication`, `domain_verification`, `quota_exceeded`, `content_rejected`, or `unknown`. Raw failure reasons, bounce diagnostics, message content and raw payloads are not persisted.

## Bounce and complaint policy

- Permanent and unknown bounces suppress the normalized recipient address.
- Transient bounces are recorded but do not suppress future deliveries.
- Complaints suppress the address.
- Resend `email.suppressed` events require the provider-shaped `data.suppressed` object. `previous_complaint` maps to complaint suppression; `previous_bounce` maps to permanent-bounce suppression.
- A complaint takes precedence over a permanent bounce regardless of event arrival order.
- Suppression is address-scoped, not account-scoped. If the member later changes their Auth email address, the old address suppression does not block the new address.
- Suppressed recipients are excluded before daily/weekly batch limits and are checked again in the final transport authorization RPC.
- Lifecycle suppression and final transport authorization take the same per-address PostgreSQL advisory lock. If suppression commits first, transport is denied. If transport authorization acquires the lock first, a subsequent provider event cannot recall an already-authorized in-flight HTTP request.

## Privacy and database boundary

Migration 025's private event and suppression tables remain inaccessible through direct grants, including to `service_role`. Migration 026 adds a private lifecycle table, and migration 027 adds a private integrity-anomaly table; both have RLS enabled and no direct grants to `public`, `anon`, `authenticated`, or `service_role`. The service-role-only SECURITY DEFINER lifecycle RPC stores normalized classifications, not recipient addresses or raw provider diagnostics, in the lifecycle projection. The existing event table retains normalized recipient addresses only for suppression/transport safety and remains unreadable except inside its narrow database functions.

The lifecycle RPC does not read or mutate `delivery_ledger`, queue state, claim tokens, retry counters, or scheduler state. It cannot initiate an outbound send. Suppression records are not automatically removed; clearing one requires an independently reviewed operational decision and confirmation that the address is safe to contact.

## Automated evidence

CI exercises parser and route handling for all seven email lifecycle events and both suppression-list events, raw-body HMAC authenticity, timestamp validation, malformed payloads, normalized failure classes, event-ID replay, PostgreSQL lifecycle and suppression-state persistence, provider/receipt timestamps, out-of-order and concurrent events, cross-recipient provider-email-ID and suppression-ID collision rollback, complaint/bounce precedence, shared suppression/transport locking, RLS/table grants, and the no-queue-mutation invariant. Provider calls in CI use fake fetch and synthetic local PostgreSQL fixtures only; no real provider email is sent. The route also maps thrown Supabase client/database transport exceptions to an empty-body 503; a route regression fixture explicitly rejects the database fetch and verifies this retryable response.

## Production status

The route, migration and CI tests are repository changes only. Production webhook creation, secret configuration, provider event delivery, actual suppression behavior, canary evidence, Cron operation and the Production kill-switch exercise remain unverified and NO-GO.


## Managed suppression-list events (migration 032)

Resend's current OpenAPI schema defines both `suppression.added` and `suppression.removed` as the standard webhook envelope (`type`, `created_at`, `data`). The required `data` fields are:

- `id`: provider suppression-record ID (not an email ID)
- `email`: suppressed recipient address
- `origin`: exactly `bounce`, `complaint`, or `manual`
- `source_id`: required but nullable; references the email event for bounce/complaint entries and is null for manual entries
- `created_at`: creation timestamp of the suppression record

The envelope `created_at` is the event timestamp used for ordering; `data.created_at` is retained separately as the original suppression-record creation time. The parser validates the published fields, normalizes the recipient, rejects malformed known suppression events, and does not require the email-only `application=deedlight` tag. Unknown event types remain ignored.

References: [Resend suppression-list changelog](https://resend.com/changelog/suppression-list-support) and [Resend official OpenAPI webhook schemas](https://github.com/resend/resend-openapi/blob/main/resend.yaml).

### Persistence and ordering

Migration 032 extends the existing private provider-event ledger with nullable `provider_email_id` only for suppression-list events and separate suppression-record ID/origin/source/creation fields. The event ID remains globally unique across email and suppression event types; the exact signed-body SHA-256 fingerprint is mandatory for new suppression events.

A separate private `delivery_provider_suppression_state` projection tracks the latest provider state per normalized recipient. Ingestion acquires the same per-recipient advisory lock as delivery authorization and webhook lifecycle ingestion, then a distinct suppression-ID advisory lock. A suppression ID is permanently bound to one recipient. Provider event time, not webhook receipt order, determines the projection. Older events are retained in history but cannot regress the current state. Equal-time contradictory add/remove or ID/origin states are recorded as integrity anomalies and fail closed as active suppression.

The route uses a dedicated service-role-only `record_delivery_provider_suppression_event` RPC. It never maps a suppression-record ID into `provider_email_id`, never writes a fake email lifecycle projection, and never mutates the delivery queue, claims or retry counters. Private tables remain inaccessible to browser roles and service_role direct table reads.

### Removal policy — independent DeedLight holds are never cleared

- `suppression.added` with origin `manual` establishes a provider-level `provider_suppressed` hold.
- `suppression.added` with origin `bounce` or `complaint` establishes the corresponding permanent-bounce or complaint hold.
- `suppression.removed` with origin `manual` may clear only the generic provider-level hold, and only after the matching `suppression.added` record has been observed. A removal received before its add is retained; when the older matching add later arrives, the event-time projection remains removed and the generic provider hold can then be cleared.
- A removal event without its matching prior manual add is not authority to clear an existing provider hold. This deliberately fails closed if the endpoint was subscribed too late or provider event history is incomplete.
- A `suppression.removed` event whose origin is `bounce` or `complaint` never clears that protection. Those origins are retained as DeedLight's independent permanent-bounce/complaint holds, including when their event arrives out of order.
- Existing `email.bounced`, `email.complained`, and reasoned `email.suppressed` protections keep their existing precedence. The removal path deletes only a `provider_suppressed` row; it never deletes `complaint` or `permanent_bounce`.

The policy is intentionally stricter than mirroring Resend's current list blindly: provider removal is not consent to contact someone whose address has independently complained or permanently bounced.

### Production setup and remaining evidence

The authorized Resend operator must subscribe the deployed endpoint to both new suppression events, confirm the endpoint belongs to Deedlight's dedicated provider account, and verify signed test events for manual add/remove, bounce-origin and complaint-origin records. Confirm the provider dashboard list and the private database state agree for each controlled test. Do not manually remove a complaint/bounce hold merely to make the provider and local projections match.

CI uses synthetic PostgreSQL fixtures and signed fake HTTP requests only. It does not prove Production webhook subscriptions, signing-secret correctness, event delivery/retry behavior, account isolation, or actual provider suppression-list synchronization. Those remain Production-only rollout gates.

## Cross-stream suppression ordering (migration 033)

Migration `202611220033_delivery_cross_stream_suppression_order.sql` reconciles generic `email.suppressed` lifecycle events with migration 032's `delivery_provider_suppression_state` projection. Both event families serialize on the same normalized-recipient advisory lock. If the projection records a manual removal with a strictly newer provider event timestamp, a later-arriving older lifecycle event remains in event/lifecycle history but cannot recreate the generic `provider_suppressed` hold. Equal timestamps remain blocked as ambiguous.

The reconciliation deletes only a generic `provider_suppressed` row, and only when the newer manual removal has a matching observed `suppression.added` event for the same provider suppression ID and recipient. A removal without its matching add remains non-authoritative and cannot clear an existing generic block. `previous_complaint` and `previous_bounce` lifecycle reasons continue to establish independent `complaint` and `permanent_bounce` holds; existing complaint/bounce rows are never deleted by this path. PostgreSQL regressions cover older lifecycle events after a newer manual removal, unmatched removals, both reasoned protections, equal timestamps, and both lock acquisition orders.

The lifecycle RPC remains service-role-only and retains migration 029's fingerprint-required insertion and historical replay-only compatibility gate. Migrations 031 and 032 are unchanged.


## Recipient-scoped provider-integrity evidence (migration 037)

Migration `202611240037_delivery_provider_integrity_conflict_evidence.sql` adds a private case/evidence/history model without rewriting migrations 025–036. Existing `delivery_provider_integrity_anomalies` rows are backfilled into recipient-scoped cases where their canonical event row supplies a recipient. Historical rows cannot reconstruct the conflicting payload that older RPCs did not store; their evidence source is explicitly labelled `legacy_anomaly_backfill`.

The new case is grouped by normalized recipient and anomaly type. Each conflict attempt adds normalized event fields, provider correlation IDs, provider timestamps, the signed-body SHA-256 fingerprint when available, and a reference to the canonical stored event. Raw webhook bodies, diagnostic text and provider error payloads are never stored. Exact repeated signed fingerprints are deduplicated; fingerprint-less legacy conflicts remain separate because equivalence cannot be proven.

The service-role webhook RPC signatures remain unchanged. Migration 037 wraps the nine-argument lifecycle and suppression-list RPCs, preserves the eight-, seven- and five-argument lifecycle compatibility paths, and keeps the prior implementations private. Duplicate event-ID conflicts, contradictory terminal outcomes, equal-time suppression conflicts and cross-recipient provider email/suppression ID collisions create durable evidence. A rejected cross-recipient collision returns SQL `NULL`; the existing webhook route maps that result to retryable HTTP 503. It does not insert the rejected event, change suppression state, or authorize an outbound send. A provider email-ID collision also marks the existing lifecycle projection `integrity_anomaly`, rather than leaving it presented as an unqualified success. The integrity status is an overlay: the wrapper snapshots and restores the prior canonical event ID, provider/receipt timestamps and failure classification after the legacy implementation returns a conflict. A conflict cannot erase the original lifecycle evidence.

### Resolution and reopening

Only an authenticated user for whom `public.is_admin()` is true may list cases/evidence/history or resolve a case. Direct table grants remain revoked for `anon`, `authenticated` and `service_role`. The admin RPCs expose normalized evidence and the immutable history, not raw webhook content. A resolution requires a non-empty operator note and records the authenticated actor. New distinct conflicting evidence reopens a resolved recipient/anomaly case, clears only the current resolution fields, and appends a `reopened` history event that retains the prior resolution. Replays with the same signed payload fingerprint do not create duplicate evidence or reopen a case.

### Transaction locks

The provider RPCs retain transaction-scoped advisory-lock order and hold the locks until commit:

1. Normalized recipient: `pg_advisory_xact_lock(20261119, hashtext(recipient_email))`.
2. Lifecycle provider email ID: `pg_advisory_xact_lock(20261126, hashtext(provider_email_id))`.
3. Suppression-list provider suppression ID: `pg_advisory_xact_lock(20261127, hashtext(provider_suppression_id))`.

The recipient lock is always acquired before the provider correlation lock. The internal case helper then locks the recipient/anomaly case row before inserting evidence and changing its state. Administrator resolution locks only the case row. Do not call the internal helper outside the guarded provider RPC transaction or reverse the recipient/correlation lock order.

The seven-argument legacy lifecycle wrapper now takes the same recipient/provider locks before reading a historical event timestamp. It still delegates to the fingerprint-enforcing canonical RPC; it cannot create a new fingerprint-less event.

### Rollback limitations

This is a forward-only integrity migration. Migration 036 and all historical migrations remain unchanged. Dropping the new tables or restoring the pre-037 RPCs would discard conflict evidence, resolution history, and the guarded capture path; that is not an acceptable rollback. If a defect is found, keep the evidence tables and protections intact and ship a corrective forward migration. Production application is not authorized by repository CI and remains NO-GO.
