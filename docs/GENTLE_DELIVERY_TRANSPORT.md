# Gentle Delivery Transport Contract

## Purpose

This increment adds one server-only outbound channel behind a narrow transport interface. It does not activate scheduling or Production delivery by itself.

## First channel and provider

- Channel: email only.
- Provider: Resend only.
- Provider selection fails closed for any other value.
- CI uses fake fetch/transport implementations and never sends real email.
- Sender identity is supplied only at runtime through `DELIVERY_FROM_EMAIL`; no sender credential or address is committed as Production configuration.

Resend was selected because its email API supports a stable idempotency key for retrying the same request without repeating the send. Provider idempotency is bounded, so Deedlight applies a stricter internal safety horizon rather than retrying indefinitely.

## Required enabled runtime configuration

Delivery is disabled unless `DELIVERY_ENABLED=true` exactly. When enabled, all of the following are mandatory and validated before work begins:

- `DELIVERY_PROVIDER=resend`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `RESEND_API_KEY`
- `DELIVERY_FROM_EMAIL`
- `NEXT_PUBLIC_SITE_URL`
- optional `DELIVERY_BATCH_SIZE` from 1 to 100, default 25

The delivery runtime never imports or falls back to the public Supabase browser configuration. A missing service-role URL/key fails closed.

## Message privacy

The first email templates are intentionally generic:

- daily reminder links to `/today` and reminder settings;
- Weekly Goodness links to `/weekly` and newsletter settings.

No reflection text, Saved Light, Journey content, Offering body, profile metadata, reaction history, or other private member content is copied into the email payload or delivery ledger.

## Authorization sequence

The runtime contract is:

```text
enqueue
→ claim
→ authorize current consent/suspension
→ resolve recipient from Supabase Auth
→ authorize again
→ begin transport/idempotency window
→ provider send
→ mark sent, retry, or mark failed
```

The second authorization is deliberate: recipient lookup must happen only after authorization, while a consent or suspension change during that lookup must still prevent the external send.

## Retry and idempotency rules

- Provider request timeout: 15 seconds by default, never more than 30 seconds.
- Claim lease: five minutes from reliability migration 020.
- Stable idempotency key: `deedlight/<kind>/<job-id>`.
- Temporary provider failures are retried after five minutes through the database retry transition.
- Permanent provider failures terminate the job.
- Malformed successful provider responses are treated as ambiguous temporary failures.
- Deedlight will not retry an ambiguous external send at or beyond 23 hours from the first transport attempt. This stays inside the provider's 24-hour idempotency window and fails closed after long outages.

## Failure classification

Temporary failures include network/timeout failures, HTTP 408, HTTP 429, 5xx responses, concurrent idempotent requests, and ambiguous 2xx responses.

Permanent failures include provider authentication rejection, non-retryable 4xx responses, and idempotency conflicts indicating the same key was reused with a different payload.

Provider error bodies are not copied into the ledger. Only bounded internal error codes are stored.

## Rollback / kill switch

`DELIVERY_ENABLED` is the primary kill switch. Any value other than exact `true` disables delivery without requiring provider or service-role secrets. Scheduler configuration is a separate later phase and must remain disabled until transport and database behavior are independently green.
