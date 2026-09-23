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

- daily reminder links to `/today` and `/settings/reminders`;
- Weekly Goodness links to `/weekly` and `/settings/newsletter`.

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
- Worker/DB clock skew is never interpreted as an expired provider window; negative elapsed time is clamped to zero and the horizon is measured from the persisted database transport-start timestamp.

## Failure classification

Temporary failures include network/timeout failures, HTTP 408, HTTP 429, 5xx responses, concurrent idempotent requests, and ambiguous 2xx responses.

Permanent failures include provider authentication rejection, non-retryable 4xx responses, and idempotency conflicts indicating the same key was reused with a different payload.

Provider error bodies are not copied into the ledger. Only bounded internal error codes are stored.

## Scheduler contract

The custom OpenNext Worker exposes a Cloudflare `scheduled()` handler without adding a browser-accessible service-role endpoint.

The code recognizes only these schedules:

- daily delivery sweep: `*/5 * * * *`;
- Weekly Goodness sweep: `0 16 * * 1` (UTC).

Production `wrangler.jsonc` intentionally declares `triggers.crons: []` until rollout is explicitly activated. Unknown Cron expressions are ignored. Daily and weekly enqueue functions remain idempotent at the database layer, claim batches are bounded, and provider selection fails closed.

## Production rollout gate

Production activation must occur in this order. Do not skip a gate because repository CI is green.

1. Verify the current Production migration history and delivery-ledger baseline.
2. Apply migration 020 and verify reliability columns, constraints, RLS, grants, and RPC privileges.
3. Apply migration 021 and verify `transport_started_at`, transport-start RPC privileges, weekly scheduler-helper privileges, and aggregate SQL parity.
4. Configure and verify the provider sender/domain.
5. Install `SUPABASE_SERVICE_ROLE_KEY` and `RESEND_API_KEY` only in server-side/Cloudflare secret storage. Never expose them as `NEXT_PUBLIC_*` values.
6. Deploy with `DELIVERY_ENABLED=false` and with no Cron expressions configured.
7. Re-run Production smoke checks for the existing application before any outbound send.
8. Enable delivery only for a deliberately selected opted-in canary account and perform one bounded manual/scheduled invocation with Cron still globally disabled.
9. Verify ledger evidence and provider evidence agree on the same logical delivery and stable provider idempotency key behavior.
10. Disable the canary preference and prove a newly claimed or queued delivery cannot send; repeat the check with suspension/revocation if needed.
11. Inspect provider delivery/failure/bounce/complaint evidence for the canary. No broader scheduler activation occurs while evidence is ambiguous.
12. Configure the daily Cron first with the normal bounded batch size. Observe multiple invocations before adding the weekly Cron.
13. Add the weekly Cron only after the daily path is healthy and a curated Weekly Goodness row exists for the intended week.
14. Re-run Production application smoke checks after Cron activation.
15. Create the completion tag only after all Production evidence below is recorded.

## Required Production evidence

The final benchmark is not achieved until all of these are proven on the deployed Production revision:

- migrations 020 and 021 are recorded in Production history;
- browser roles still cannot read/mutate `delivery_ledger` or execute delivery RPCs;
- the service role can enqueue, claim, authorize, begin transport, retry, and terminally transition jobs;
- one opted-in canary delivery is accepted by the provider and marked sent with matching ledger/provider evidence;
- revocation/opt-out after enqueue or claim prevents the external send;
- a retryable provider failure does not create a duplicate logical delivery;
- provider failure/bounce/complaint evidence has been inspected;
- daily Cron has run successfully with bounded work and no duplicate logical deliveries;
- weekly Cron is either proven against a curated week or intentionally left disabled with the rollout incomplete;
- existing `/`, `/sign-in`, `/auth/callback`, `/api/auth/callback`, `/today`, `/weekly`, `/me`, and `/offering/new` smoke expectations remain healthy;
- rollback controls are verified;
- the final clean-head CI run is green;
- a completion tag following the repository's `sprint-*-complete` convention is created only after all preceding evidence exists.

## Rollback / kill switch

The fastest safe rollback is operational rather than destructive:

1. Set `DELIVERY_ENABLED=false`.
2. Set Cloudflare Cron expressions back to an empty list.
3. Confirm no new delivery jobs are being claimed or externally sent.
4. Preserve ledger rows for diagnosis; do not delete delivery history to make metrics look clean.
5. Inspect the bounded internal error codes plus provider evidence without copying provider bodies or recipient addresses into the ledger.
6. Fix forward on a feature branch and repeat the canary sequence before reactivation.

Disabling delivery must not require deleting provider credentials, reverting migrations, weakening RLS, or changing member preference data. Database migrations 020 and 021 are additive and may remain in place while transport is disabled.

## Completion rule

No completion tag, "Production deploy PASS", or "Production smoke PASS" should be reported from repository CI alone. Those statuses require evidence from the actual deployed Production revision and provider/database runtime.
