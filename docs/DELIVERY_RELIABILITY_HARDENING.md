# Delivery Reliability Hardening

## Baseline

This increment starts from `main` at `4e8df4f6a7658a3aeaaedd0486983595bd823930` (`sprint-12-2-complete`). Sprint 12.2 established a private, service-role-only delivery ledger plus deterministic enqueue, claim, authorization, sent, and failed transitions. It intentionally did not activate any outbound transport.

The current claim model has one important pre-transport reliability gap: a job moved to `claimed` has no lease expiry or reclaim path. A worker crash after claim can therefore strand that job indefinitely. In addition, the current terminal `failed` state does not distinguish a temporary transport failure that should be retried from a permanent failure.

No real provider should be connected until those failure modes are bounded and tested.

## Scope

This increment will harden the delivery state machine without activating outbound delivery:

1. Add a bounded claim lease to claimed delivery jobs.
2. Track delivery attempt count and the most recent attempt timestamp.
3. Allow expired claims to be reclaimed safely with a new claim token.
4. Bound the number of delivery attempts. Exhausted jobs become terminal failures instead of retrying forever.
5. Add a service-role-only retry transition for temporary failures with a bounded future retry time.
6. Require a live, unexpired claim lease for pre-transport authorization and terminal state changes.
7. Ensure an old/stale claim token cannot authorize, retry, mark sent, or mark failed after a lease has expired or a job has been reclaimed.
8. Keep queue deduplication unchanged: one logical delivery remains unique by `(kind, user_id, delivery_key)`.
9. Keep recipient addresses and member content out of the delivery ledger.
10. Add static security assertions and PostgreSQL behavior coverage for lease expiry, reclaim, retry, attempt exhaustion, stale-token rejection, and browser privilege denial.
11. Mirror the canonical migration into `supabase/run_in_sql_editor_all.sql` before the increment is considered complete.

## Proposed state-machine rules

The intended claim lifecycle is:

```text
queued
  -> claimed (attempt + 1, short lease)
      -> sent
      -> failed (permanent failure)
      -> queued (temporary failure, bounded retry time)
      -> cancelled (authorization revoked)

expired claimed
  -> claimed again with a new token if attempts remain
  -> failed with retry_exhausted when the attempt limit is reached
```

A claim token remains concurrency control only. It is never delivery authority.

## Security and privacy invariants

- `anon` and `authenticated` must not read or mutate `delivery_ledger`.
- Queue, claim, retry, authorization, and terminal-state RPCs remain service-role-only.
- Every security-definer delivery RPC must use a constrained `search_path`.
- Authorization must still be evaluated immediately before any future external transport.
- Expired claim leases fail closed.
- Provider identifiers and error codes remain bounded.
- Recipient email addresses remain in the authentication system and are not copied into the ledger.
- No reflection text, Offering body, Saved Light, Journey content, or other private member content is added to delivery jobs.

## Future transport idempotency boundary

A database claim lease cannot make an external provider side effect atomic. A future worker can successfully hand a message to a provider and then crash before `mark_delivery_sent` commits. Once that lease expires, a safe reclaim cannot know from the ledger alone whether the provider already accepted the send.

Before outbound transport is activated:

- the provider adapter must use a stable idempotency key derived from the logical delivery job when the provider supports idempotency,
- provider request timeouts must remain comfortably shorter than the five-minute claim lease,
- an ambiguous provider outcome must not be treated as confirmed success,
- providers without usable idempotency semantics require an explicit, tested ambiguity strategy before they are accepted for production delivery,
- retry/reclaim behavior must never assume that a missing `sent` transition proves no external side effect occurred.

This is a transport-layer requirement, not something the queue can safely infer after the fact.

## Explicit exclusions

This increment does **not** add:

- an email/SMS/push provider,
- provider credentials,
- a Cloudflare Cron Trigger,
- a browser-accessible service-role endpoint,
- actual outbound delivery,
- public delivery metrics,
- delivery rankings or engagement scoring.

Provider/channel selection remains a separate decision after the queue state machine is crash-safe and retry-safe.

## Acceptance criteria

Before landing, CI must prove at least:

1. A claimed job receives a finite lease and increments its attempt count.
2. A non-expired claim cannot be stolen by another worker.
3. An expired claim can be reclaimed with a different token when attempts remain.
4. The previous token becomes unusable after reclaim.
5. Pre-transport authorization rejects an expired claim.
6. `mark_delivery_sent` and `mark_delivery_failed` reject expired or stale claims.
7. A temporary failure can requeue the same logical job for a bounded future retry.
8. The job cannot be claimed before that retry time.
9. Retry exhaustion becomes a terminal failure and cannot loop forever.
10. Browser roles cannot execute the retry/reliability RPCs or gain ledger privileges.
11. Existing Sprint 12.2 consent, suspension, deduplication, and privacy tests remain green.
12. TypeScript, Next.js build, dependency audit, and Cloudflare packaging remain green.
13. No provider dependency, Cron Trigger, or outbound call is introduced.

## Production boundary

A repository migration for this increment must not be applied to Production merely because the migration file exists. Production must first be inspected to prove the expected Sprint 12.2 baseline, then the exact migration must be applied through the existing guarded rollout discipline, followed by schema, privilege, RLS, RPC, and behavioral verification.

Merging to `main` is also a production deployment action because Cloudflare native deployment follows `main`. Production database rollout and `main` landing therefore remain explicit later gates; this branch is non-production work only.


## C208 — outbound transport and provider lifecycle verification

The delivery implementation now has a concrete provider boundary and executable lifecycle evidence on the delivery-security branch. This addendum records the contracts that must remain true; it does not authorize Production activation.

### Current-consent authorization

- The worker performs an initial authorization, resolves the current Auth recipient, performs a second authorization, then invokes the service-role-only \`begin_delivery_transport(job, claimToken, expectedEmail)\` database RPC immediately before provider transport.
- The final RPC locks the ledger claim, current consent/preference row, active profile, current confirmed Auth email, and (for Weekly) the curated issue. It checks the claim token and live lease using \`clock_timestamp()\` after lock waits and again in the final transport-start update.
- A revoked preference, suspension, changed recipient, unconfirmed email, missing curated issue, expired lease, or stale claim fails closed. A denied RPC returns NULL or an authorization error; the worker makes zero provider calls.
- A retry re-enters the same authorization path. Queue state and a claim token are concurrency controls, never authorization.

The authorization RPC is the database linearization point. A later revocation cannot recall an already-authorized external request; every subsequent attempt must pass fresh authorization.

### Retry and ambiguous provider outcomes

- Claim lease: five minutes, checked against the database wall clock.
- Retry delay: five minutes; database attempt ceiling: five attempts.
- Provider request timeout: 15 seconds by default, hard maximum 30 seconds.
- Stable Resend idempotency key: \`deedlight/<kind>/<logical-job-uuid>\`, reused across retries.
- The worker stops retrying before the provider's idempotency safety horizon (23 hours) expires. Timeout, network failure, malformed success body, and in-progress idempotency conflicts are ambiguous/retryable only within that horizon. A mismatched idempotency key is permanent failure.
- Expired claims are reclaimed only with a fresh token; stale tokens cannot authorize, retry, mark sent, or mark failed. Retry exhaustion becomes terminal failure.

### Provider event intake

Migrations 025–027 and the server-only signed Resend webhook record bounce, complaint, suppression, and all seven lifecycle event types. Event-ID duplicates are idempotent only when compatible; payload fingerprints detect same-ID/different-body conflicts. Provider-email IDs are locked and bound to one recipient. Conflicting terminal outcomes are retained as evidence and project to \`integrity_anomaly\`, never to successful delivery. Permanent/unknown bounces, complaints, and provider suppressions block subsequent sends; transient bounces are recorded without suppression. Complaint suppression wins over bounce suppression.

C208 adds regression coverage for Resend's published payload shapes: bounce \`diagnosticCode\` is optional and \`subType: "Suppressed"\` is accepted; suppression \`diagnosticCode\` and \`reason\` are optional, with missing/unrecognized reasons mapped to the fail-closed generic \`provider_suppressed\` classification. Provider diagnostics and raw payloads remain unpersisted.

### Evidence and limits

Before C208, PR #10 exact-head [PR Validation run 44875441190](https://github.com/ADRN-9/deedlight/actions/runs/44875441190) and [push validation run 44875436665](https://github.com/ADRN-9/deedlight/actions/runs/44875436665) passed 7/7 jobs at \`95fb79152243f9581647eae961f3c35cf5d1043b\`. This included provider webhook parser/route tests, PostgreSQL lifecycle and concurrency behavior, consent/transport tests, TypeScript, Next build, Cloudflare packaging, and dependency audit. C208 source/test head `06ca8cf1e21215645bd70dd93f178cd954196929` passed exact-head [PR run 44903895136](https://github.com/ADRN-9/deedlight/actions/runs/44903895136) and [push run 44903890652](https://github.com/ADRN-9/deedlight/actions/runs/44903890652), both 7/7 jobs. The webhook suite reported 34/34 parser/route tests passing; the transport suite reported 25/25 tests passing. PostgreSQL provider-event concurrency and consent/transport race tests passed, as did TypeScript, Next build, Cloudflare packaging, and dependency audit.

No Production migrations, webhook configuration, provider sends, Cron activation, kill-switch changes, or credentials were performed in C208. Production provider lifecycle, current consent revocation behavior, scheduler cycles, and final smoke remain unverified in Production.
