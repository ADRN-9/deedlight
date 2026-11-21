# Deedlight outbound delivery rollout tracker

**Status: PRODUCTION NO-GO.** This tracker separates repository evidence from Production evidence. A green CI run does not prove live consent, provider, scheduler, ledger, or kill-switch behavior.

## Current code and review state

- Delivery-security implementation branch: \`security/delivery-transport-consent-gates\`.
- Reviewed baseline before C208: \`95fb79152243f9581647eae961f3c35cf5d1043b\` (tree \`b49a2152af7a141bdc088dba52e4b9fed818a7de\`).
- PR #10 remains OPEN, DRAFT, UNMERGED. It contains migrations 023–027, final transport authorization, Resend lifecycle intake, duplicate/conflict handling, and CI coverage.
- PR #13 remains separate and unmerged; preserve its retirement of the legacy Production migration workflow. Do not restore that workflow to resolve a conflict.
- PR #15 remains separate and unmerged; preserve its Supabase CLI target safeguards and empty approved Non-Production allowlist.
- PR #14 is a separate open test-fixture correction; do not merge it as part of C208.
- No Production migration, provider send, webhook configuration, Cron activation, secret change, or kill-switch mutation is part of this work.

## Rollout order and gates

| Gate | Required evidence | Current disposition |
|---|---|---|
| Delivery security in CI | Exact-head assertions, fake transport, PostgreSQL behavior and concurrency tests | Existing PR #10 baseline passed 7/7; C208 exact-head run pending |
| Provider failure lifecycle | Signed event intake; bounce, complaint, suppression and failure classification | Implemented in repository; live provider evidence absent |
| Duplicate and conflicting events | Event-ID idempotency, payload fingerprint conflicts, provider-ID recipient binding, terminal-outcome anomalies | PostgreSQL and synchronized concurrency fixtures exist; Production unverified |
| Consent before each send | Fresh preference/profile/Auth-email/curated-issue locks in final transport RPC; denial means zero provider calls | Repository tests exist; Production revocation test not run |
| Retry and ambiguous outcomes | Five-minute lease and retry, five-attempt cap, stable provider key, 23-hour safety horizon, stale-token rejection | Repository implementation/tests exist; live provider ambiguity evidence absent |
| Daily scheduler | Explicit approval, staged Cron, multiple healthy cycles and ledger/provider reconciliation | NOT ACTIVATED / NOT VERIFIED in C208 |
| Kill switch | Exercise \`DELIVERY_ENABLED=false\`, prove no new enqueue/claim/send, then safe re-enable | NOT EXERCISED in C208 |
| Weekly Goodness | Daily accepted first; explicit curation, 5,000 logical-row cap, separate Cron only after Daily evidence | HELD; no Weekly activation |
| Production regression | Authenticated/unauthenticated journeys, privacy, moderation, DB and Cloudflare checks | NOT RUN in C208 |
| Release | Exact-head CI, authorized deploy, Production smoke, rollout approval | BLOCKED |

## Delivery safety invariants

1. \`DELIVERY_ENABLED\` must remain disabled until a separately approved staged rollout.
2. Daily delivery precedes Weekly Goodness. Weekly stays inactive until multiple healthy Daily cycles, kill-switch behavior, and safe re-enablement are evidenced.
3. Every external attempt must pass current database authorization immediately before transport. Consent, suspension, current confirmed recipient identity, claim token and live lease are checked together. A claim token alone never grants send authority.
4. Resend uses one stable idempotency key per logical ledger job. Ambiguous outcomes may retry only inside the bounded safe horizon; after that they fail closed.
5. Provider webhook events cannot enqueue, claim, retry, or mutate the delivery ledger. Conflicting events remain private integrity anomalies; they never overwrite original evidence or project contradictory terminal outcomes as success.
6. Permanent/unknown bounce, complaint, and provider suppression block subsequent attempts. Transient bounce remains observable but does not suppress.
7. Recipient addresses, provider diagnostics, raw webhook bodies, claim tokens, and service credentials remain private/server-side.
8. Suppression is never cleared automatically. Any manual correction requires independent review and evidence that the address is safe to contact.

## Provider setup — human-only

An authorized operator must create the Resend webhook endpoint, subscribe to the seven supported lifecycle events, store \`RESEND_WEBHOOK_SECRET\` only as a server-side Cloudflare secret, and verify the endpoint is associated with the same Resend account used for outbound delivery. Do not copy the signing secret into source control, client configuration, chat, or logs. Provider test events must be deliberately authorized and must not be used to send real member messages without separate approval.

## Production prerequisites and rollback

Before any migration or activation, independently inspect the live Production schema and reconcile historical Supabase migration history. Do not use normal \`supabase db push\`, mark unknown migrations applied, or reset Production based on repository state.

Rollback is operational and fail-closed: disable new outbound work, remove future Cron triggers, allow already-authorized requests to drain, and reconcile ledger/provider outcomes. Preserve queue and suppression history. Keep the inbound provider webhook available while outbound delivery is disabled; it is a safety intake path, not an outbound activation. Never restore an obsolete consent-bypassing RPC or clear suppression state to make delivery resume.

## C208 evidence ledger

- Pre-C208 exact-head PR #10 validation: [44875441190](https://github.com/ADRN-9/deedlight/actions/runs/44875441190), 7/7 PASS at \`95fb79152243f9581647eae961f3c35cf5d1043b\`.
- Pre-C208 exact-head push validation: [44875436665](https://github.com/ADRN-9/deedlight/actions/runs/44875436665), 7/7 PASS at the same SHA.
- C208 provider-payload compatibility source/test head: `06ca8cf1e21215645bd70dd93f178cd954196929` (tree `fe5e4f98a084d56ee2594fed231b3e8f0d5388f3`). Exact-head [push run 44903890652](https://github.com/ADRN-9/deedlight/actions/runs/44903890652) and [PR run 44903895136](https://github.com/ADRN-9/deedlight/actions/runs/44903895136) both completed **7/7 PASS** at that SHA. All database behavior jobs, provider webhook/concurrency tests, transport revocation races, TypeScript, Next build, Cloudflare packaging, and dependency audit passed.
- No live Production provider, ledger, Cron, consent-revocation, or kill-switch evidence is claimed.
