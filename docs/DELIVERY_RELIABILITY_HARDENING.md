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
