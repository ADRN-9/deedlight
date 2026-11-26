# Controlled Production Resend webhook verification

## Purpose and safety boundary

This runbook is for a separately approved Production verification window. C507 changes application validation only. It does not change Production configuration, create provider events, send email, mutate Production data, or expose credentials.

Do not begin until the release owner authorizes the window, the exact deployed commit is recorded, and the provider webhook configuration owner confirms the intended endpoint. Use a dedicated monitored test mailbox only if a real outbound test is explicitly approved; otherwise use provider-generated lifecycle events and previously existing controlled events. Never send unsolicited test mail.

## Destination identity preflight

The only accepted privileged database destination is the canonical origin:

`https://xaipiovflxomcbfwtwmu.supabase.co`

The authoritative project reference is a repository constant independent of `SUPABASE_URL`. Confirm the Production runtime's server-only `SUPABASE_URL` equals that exact origin. Do not print `SUPABASE_SERVICE_ROLE_KEY`, webhook signing secret, provider API key, or full environment. A missing or noncanonical URL must cause the endpoint to return 503 before a privileged Supabase client is constructed. Do not temporarily weaken this guard to facilitate verification.

Confirm the webhook signing secret is present in the server-side secret store and matches the provider endpoint configuration. Do not copy it into tickets, logs, shell history, CI variables, or browser configuration. Confirm the endpoint uses HTTPS and that the currently deployed commit includes Svix verification and the database event-id idempotency RPCs.

## Supported lifecycle coverage

The application currently accepts these signed Resend event types:

| Provider event | Expected verification |
|---|---|
| `email.sent` | Event recorded; no suppression |
| `email.delivered` | Event recorded; no suppression |
| `email.delivery_delayed` | Event recorded; no suppression |
| `email.failed` | Event recorded; no inferred suppression |
| `email.bounced` — Permanent | Event recorded; permanent-bounce suppression applied |
| `email.bounced` — Transient | Event recorded; no permanent suppression |
| `email.bounced` — Undetermined | Event recorded; no permanent suppression |
| `email.complained` | Event recorded; spam-complaint suppression applied |
| `email.suppressed` | Provider suppression event recorded; suppression classification remains explicit |
| `suppression.added` | Account-level suppression added using suppression identity and origin |
| `suppression.removed` | Account-level suppression removal recorded; current database policy remains authoritative |

For each event, capture only event type, provider event ID, receipt timestamp, HTTP status, database outcome and correlation-safe deployment metadata. Do not log recipient email addresses, raw payloads, signatures, authorization headers or provider secrets.

## Controlled verification sequence

1. Record the approved change ticket, operator, UTC window, deployed commit SHA, provider endpoint identity, and the expected canonical Supabase origin. Confirm no Production schema migration is part of this operation.
2. Confirm the endpoint returns 503 when the required destination configuration is absent or noncanonical using the non-Production test suite. Do not alter Production environment variables to test negative cases.
3. From the provider's supported webhook test/replay facility, select one controlled event for each lifecycle type above. If the provider cannot generate an event type without an actual mail event, use a previously existing event or defer that case; do not fabricate a provider signature or send an unapproved email.
4. Verify each accepted request uses a valid Svix signature over the exact raw request body and a timestamp within the replay window. A bad signature, modified body, malformed event, or stale timestamp must be rejected without a database mutation.
5. Replay the same signed provider event through the provider's official retry/replay mechanism. Verify the database returns the duplicate/idempotent outcome and that no second logical lifecycle effect is applied. Record both HTTP responses and the durable event outcome.
6. For a permanent bounce and a complaint, verify the corresponding suppression state is durable and that subsequent outbound authorization is denied for that recipient. Do not attempt a live send to the suppressed recipient.
7. For transient and undetermined bounce classifications, verify the event is retained without silently upgrading it to permanent suppression. Verify retry/recovery only through the existing delivery worker's bounded retry path and provider event ledger; do not manually reset terminal jobs or bypass authorization.
8. For `suppression.added` and `suppression.removed`, verify the account-level suppression RPC records the exact event identity and origin. Confirm duplicate event delivery is idempotent and a removal does not override any independent permanent-bounce or complaint suppression.
9. If a provider replay receives 5xx because the database is temporarily unavailable, allow the provider's documented retry process to recover after the dependency is restored. Verify exactly one durable event effect after recovery. Do not deliberately interrupt Production database connectivity as part of this runbook.
10. Confirm no unexpected recipient-facing sends occurred, all expected event identities are durable, and webhook logs contain no secrets or raw personal data. Close the window only after the release owner signs off on the evidence.

## Failure handling and rollback

- A 503 for wrong/missing destination identity is an intentional fail-closed result. Restore only the independently verified canonical configuration through the normal approved secret/configuration process.
- A signature or replay rejection is not a reason to disable Svix verification. Check provider endpoint secret rotation through the approved secret-management procedure.
- A duplicate outcome is expected for a repeated event ID. Do not delete registry rows to force reprocessing.
- If suppression state is ambiguous or conflicts with existing recipient state, stop outbound verification and escalate to the delivery/security owner. Never manually clear complaint or permanent-bounce suppression to make a test pass.
- If a webhook event remains unprocessed after the provider retry horizon, preserve its event identity and provider evidence for controlled investigation. Do not replay with a fabricated event ID or bypass database idempotency.

## Evidence record

Attach the change ticket and deployed commit SHA; provider event IDs and event types (not raw payloads); endpoint HTTP statuses; database outcome categories; duplicate replay evidence; bounce/complaint suppression assertions; retry recovery timing; log redaction review; and operator/release-owner sign-off. Keep the evidence access-controlled and redact recipient addresses and all secret material.

A successful runbook execution is Production operational evidence only for the exact tested commit, endpoint and event set. CI and synthetic fixtures do not substitute for this Production verification.
