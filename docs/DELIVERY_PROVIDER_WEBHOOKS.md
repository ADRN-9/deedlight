# Deedlight Resend Provider Webhook Contract

## Scope

Migration 025 and the server-only `POST /api/webhooks/resend` route add authenticated handling for Resend `email.bounced`, `email.complained`, and `email.suppressed` events. This closes the provider suppression path; it does not activate delivery, configure a Production webhook, or send messages.

## Provider configuration (human-only)

Before a Production rollout, an authorized operator must:

1. Create a Resend webhook endpoint targeting `https://deedlight.com/api/webhooks/resend`.
2. Subscribe to `email.bounced`, `email.complained`, and `email.suppressed`.
3. Store the returned `whsec_` signing secret as the server-only Cloudflare secret `RESEND_WEBHOOK_SECRET`.
4. Confirm the webhook belongs to the Resend account used by Deedlight and that delivery events include the `application=deedlight` tag.
5. Send a deliberately authorized, synthetic/provider-test event only after the Production canary approval and verify the webhook response, database suppression and provider dashboard evidence.

Do not put the signing secret in `NEXT_PUBLIC_*`, source control, client configuration, ordinary logs, or chat. Webhook processing also requires server-side `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. The inbound endpoint intentionally continues to record provider suppression events while `DELIVERY_ENABLED=false`; the outbound kill switch must not disable safety intake.

## Authenticity and replay protection

- Verification uses the exact raw UTF-8 request body and the Resend/Svix `svix-id`, `svix-timestamp`, and `svix-signature` headers.
- HMAC-SHA256 v1 signatures are verified using the base64 key in the `whsec_` secret.
- Timestamps more than five minutes in the past or future are rejected.
- The request body is streamed with a 64 KiB maximum.
- Only sends tagged `application=deedlight` are processed; unrelated Resend account events are acknowledged without changing Deedlight data.
- The provider event ID is the database primary key. A duplicate/replayed event is an idempotent no-op.
- Invalid signatures return 401, malformed signed payloads return 400, oversized bodies return 413, and missing server configuration or database failures return 503 so the provider can retry.

## Bounce and complaint policy

- Permanent bounces suppress the normalized recipient address.
- Unknown bounce classifications fail closed and suppress the address.
- Transient bounces are recorded but do not suppress future deliveries.
- Complaints and provider-level suppressions suppress the address.
- A complaint takes precedence over a bounce reason.
- Suppression is address-scoped, not account-scoped. If the member later changes their Auth email address, the old address suppression does not block the new address.
- Suppressed recipients are excluded before daily/weekly batch limits and are checked again in the final transport authorization RPC.
- The webhook RPC and final transport authorization take the same per-address PostgreSQL advisory lock. If the suppression event commits first, transport is denied. If transport authorization acquires the lock first, a subsequent provider event cannot recall an already-authorized in-flight HTTP request; this is the same unavoidable external-side-effect boundary documented for consent revocation.

## Provider lifecycle coverage not yet implemented

The current parser intentionally ignores other valid Resend event types, including email.sent, email.delivered, email.delivery_delayed, and email.failed. As a result, Deedlight does not currently retain provider-side delivery confirmation, delayed-delivery history, or asynchronous send-failure events. A successful send RPC is only provider acceptance; it is not proof that the recipient's mail server accepted the message.

Resend documents delivery and delayed-delivery events, and its current event model also includes failed sends. See the official event references in the engineering handoff.

A follow-up should add a new additive migration (without rewriting migration 025) for an allowlisted lifecycle-event record and a narrow service-role-only RPC. Preserve provider event-ID idempotency, application=deedlight scoping, raw-payload minimization, and recipient privacy. Treat email.delivery_delayed as informational, not a reason to resend: Resend retries deferred delivery itself. Define and test the policy for email.failed separately from bounce/complaint suppression before enabling it. Add delivery-status correlation to the provider email ID without exposing recipient addresses or message content to browser roles.

No lifecycle-event schema or event subscriptions are added by this remediation. Production subscription and event evidence remain human/provider-side dependencies.

## Privacy and database boundary

Migration 025 stores only the provider event ID, event type, provider email ID, normalized recipient email, bounce classification, and receipt timestamp. It never stores the raw webhook body, provider error text, message content, or private member activity.

The event and suppression tables have RLS enabled and no direct table grants, including to `service_role`. The narrow `record_delivery_provider_event` SECURITY DEFINER RPC is executable only by `service_role`. No browser role can read event IDs, email addresses, or suppression state.

Suppression records are not automatically removed. Re-enabling a suppressed address requires an independently reviewed operational decision and confirmation that the address is safe to contact; a member's reminder/newsletter preference alone must not clear a provider complaint or hard-bounce suppression.

## Automated evidence

CI exercises:
- raw-body HMAC authenticity, timestamp tolerance, invalid signatures and signature rotation candidates;
- bounce, transient bounce, complaint, suppression, Deedlight tag scoping and malformed event handling;
- event-ID replay idempotency and complaint precedence in PostgreSQL 16;
- suppression exclusion from daily and Weekly Goodness enqueue;
- final daily and weekly transport denial for suppressed addresses;
- RLS, table privileges and service-role-only RPC grants;
- provider HTTP failures, network/timeouts, ambiguous outcomes, stable idempotency keys and retry-window boundaries.

All provider calls in CI use fake fetch or synthetic local PostgreSQL fixtures. No real provider email is sent.

## Production status

The route, migration and CI tests are repository changes only. Production webhook creation, secret configuration, provider event delivery, actual suppression behavior, canary evidence, Cron operation and the Production kill-switch exercise remain unverified and NO-GO.
