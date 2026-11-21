# Deedlight Resend Provider Webhook Contract

## Scope

Migration 025 established authenticated bounce/complaint suppression and the shared suppression/transport lock. Additive migration 026 extends the server-only `POST /api/webhooks/resend` route to persist all seven delivery lifecycle events. Additive migration 027 adds full-payload idempotency fingerprints, private integrity-anomaly recording, and normalized Resend suppression reasons: `email.sent`, `email.delivered`, `email.delivery_delayed`, `email.bounced`, `email.complained`, `email.suppressed`, and `email.failed`. It does not activate outbound delivery, configure a Production webhook, or send messages.

## Provider configuration (human-only)

Before a Production rollout, an authorized operator must:

1. Create a Resend webhook endpoint targeting `https://deedlight.com/api/webhooks/resend`.
2. Subscribe to the seven lifecycle events listed above.
3. Store the returned `whsec_` signing secret as the server-only Cloudflare secret `RESEND_WEBHOOK_SECRET`.
4. Confirm the webhook belongs to the Resend account used by Deedlight and that outbound events include the `application=deedlight` tag.
5. Send a deliberately authorized, synthetic/provider-test event only after the Production canary approval and verify webhook, database and provider-dashboard evidence.

Do not put the signing secret in `NEXT_PUBLIC_*`, source control, client configuration, ordinary logs, or chat. Webhook processing also requires server-side `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. The inbound endpoint intentionally remains available while `DELIVERY_ENABLED=false`; the outbound kill switch must not disable safety intake.

## Authenticity and replay protection

- Verification uses the exact raw UTF-8 request body and the Resend/Svix `svix-id`, `svix-timestamp`, and `svix-signature` headers.
- HMAC-SHA256 v1 signatures are verified using the base64 key in the `whsec_` secret.
- Timestamps more than five minutes in the past or future are rejected.
- The request body is streamed with a 64 KiB maximum.
- Only sends tagged `application=deedlight` are processed; unrelated Resend events are acknowledged without changing Deedlight data.
- The provider event ID is the database primary key. Exact signed-body replays are idempotent no-ops, including concurrent duplicate deliveries. A reused event ID with conflicting normalized fields, or different fingerprints when both are present, records an integrity anomaly, preserves the original event and suppression state, and returns a retryable failure.
- A SHA-256 fingerprint of the exact signed request body supports full-payload comparison for events that have one. Rows created before migration 027 and trusted legacy RPC calls may have no fingerprint (and historical suppression rows may have no normalized suppression reason). For those rows, the RPC compares every field available to the older schema and treats missing new metadata as unknown; it never fabricates a digest or overwrites the original event. Two present, unequal fingerprints remain a conflict. Raw webhook bodies and provider diagnostics are not stored.
- Provider `created_at` is preserved as `provider_created_at`; `received_at` is assigned by PostgreSQL at receipt.
- Invalid signatures return 401, malformed signed payloads return 400, oversized bodies return 413, and missing server configuration or database failures return 503 so the provider can retry.

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

CI exercises parser and route handling for all seven event types, raw-body HMAC authenticity, timestamp validation, malformed payloads, normalized failure classes, event-ID replay, PostgreSQL lifecycle persistence, provider/receipt timestamps, out-of-order and concurrent events, cross-recipient provider-email-ID collision rollback, complaint precedence, shared suppression/transport locking, RLS/table grants, and the no-queue-mutation invariant. Provider calls in CI use fake fetch and synthetic local PostgreSQL fixtures only; no real provider email is sent.

## Production status

The route, migration and CI tests are repository changes only. Production webhook creation, secret configuration, provider event delivery, actual suppression behavior, canary evidence, Cron operation and the Production kill-switch exercise remain unverified and NO-GO.
