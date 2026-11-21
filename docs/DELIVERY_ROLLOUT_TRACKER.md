# Deedlight outbound delivery rollout tracker

**Status: PRODUCTION NO-GO.** This tracker separates repository evidence from Production evidence. A green CI run does not prove live consent, provider, scheduler, ledger, or kill-switch behavior.

## Current code and review state

- Delivery-security branch: `security/delivery-transport-consent-gates`.
- C225 independent-review target: HEAD `2d5d00371409a151c7c2ce23cb978b2eaa867e91`, tree `64253539093d9057a571c8a3103766292cf370ce`, base `ce82b3fdf1a73510de70e3729a487d4ae00e66e3`.
- PR #10 remains OPEN, DRAFT, UNMERGED. C222 added SQL ACL assertions for the private provider lifecycle implementation; commit `2d5d00371409a151c7c2ce23cb978b2eaa867e91`.
- Migrations 028 and 029 are part of the reviewed delivery path. C226 adds migration 030 for database-authoritative provider idempotency timing and validated Resend receipts.
- C225 findings: HIGH — migration 029 trusted a matching signature without proving migration-027 implementation identity; MEDIUM — Worker-clock skew could underestimate provider idempotency age; MEDIUM — provider receipt IDs were accepted without format validation.
- C226 remediation: migration 029 pins the migration-027 PL/pgSQL source SHA-256 and verifies SECURITY DEFINER/search_path metadata; migration 030 moves retry/horizon decisions to PostgreSQL `clock_timestamp()`, checks persisted `transport_started_at`, and validates provider UUID receipts before the sent transition. Regression tests are added; acceptance remains pending exact-head CI and independent security review.
- Read-only GitHub inspection found `main.protected=false` and no repository rulesets. Production Environment protection and secret scopes have not been verified.
- No Production migration, provider send, webhook configuration, Cron activation, secret change, or kill-switch mutation is part of this work.

## Rollout order and gates

| Gate | Required evidence | Current disposition |
|---|---|---|
| Delivery security in CI | Exact-head assertions, fake transport, PostgreSQL behavior and concurrency tests | C222 exact-head runs passed 7/7 at 2d5d003; C226 remediation requires new exact-head validation and independent review |
| Provider failure lifecycle | Signed event intake; bounce, complaint, suppression, failure classification and validated Resend receipt UUIDs | Repository tests cover receipt format; live provider evidence absent |
| Duplicate and conflicting events | Event-ID idempotency, payload fingerprint conflicts, provider-ID recipient binding, terminal-outcome anomalies | PostgreSQL and synchronized concurrency fixtures exist; Production unverified |
| Consent before each send | Fresh preference/profile/Auth-email/curated-issue locks in final transport RPC; denial means zero provider calls | Repository tests exist; Production revocation test not run |
| Retry and ambiguous outcomes | Five-minute DB-timed retry, five-attempt cap, stable provider key, DB-clock 23-hour horizon, stale-token rejection | C226 migration 030 and regression tests added; exact-head CI pending, Production provider ambiguity evidence absent |
| Daily scheduler | Explicit approval, staged Cron, multiple healthy cycles and ledger/provider reconciliation | NOT ACTIVATED / NOT VERIFIED in C208 |
| Kill switch | Exercise \`DELIVERY_ENABLED=false\`, prove no new enqueue/claim/send, then safe re-enable | NOT EXERCISED in C208 |
| Weekly Goodness | Daily accepted first; explicit curation, 5,000 logical-row cap, separate Cron only after Daily evidence | HELD; no Weekly activation |
| Production regression | Authenticated/unauthenticated journeys, privacy, moderation, DB and Cloudflare checks | NOT RUN in C208 |
| Release | Exact-head CI, authorized deploy, Production smoke, rollout approval | BLOCKED |

## Delivery safety invariants

1. \`DELIVERY_ENABLED\` must remain disabled until a separately approved staged rollout.
2. Daily delivery precedes Weekly Goodness. Weekly stays inactive until multiple healthy Daily cycles, kill-switch behavior, and safe re-enablement are evidenced.
3. Every external attempt must pass current database authorization immediately before transport. Consent, suspension, current confirmed recipient identity, claim token and live lease are checked together. A claim token alone never grants send authority.
4. Resend uses one stable idempotency key per logical ledger job. PostgreSQL calculates retries from persisted first-transport evidence and its own clock; the Worker cannot extend the safe horizon. Ambiguous outcomes fail closed after the 23-hour boundary.
5. Provider webhook events cannot enqueue, claim, retry, or mutate the delivery ledger. Conflicting events remain private integrity anomalies; they never overwrite original evidence or project contradictory terminal outcomes as success.
6. Permanent/unknown bounce, complaint, and provider suppression block subsequent attempts. Transient bounce remains observable but does not suppress.
7. Recipient addresses, provider diagnostics, raw webhook bodies, claim tokens, and service credentials remain private/server-side.
8. Suppression is never cleared automatically. Any manual correction requires independent review and evidence that the address is safe to contact.

## Provider setup — human-only

An authorized operator must create the Resend webhook endpoint, subscribe to the seven supported lifecycle events, store \`RESEND_WEBHOOK_SECRET\` only as a server-side Cloudflare secret, and verify the endpoint is associated with the same Resend account used for outbound delivery. Do not copy the signing secret into source control, client configuration, chat, or logs. Provider test events must be deliberately authorized and must not be used to send real member messages without separate approval.

## Human-only GitHub governance blocker

**Responsible administrator:** the ADRN-9 repository owner (or a delegated GitHub organization/repository administrator with Environment administration rights). A named human approver must be designated before the Production gate can close; no administrator identity is inferred here.

Read-only repository evidence currently shows `main.protected=false` and an empty repository rulesets list. Production Environment branch restrictions, required reviewers, the `Prevent self-review` setting, and secret scopes were not available for independent verification.

The administrator must complete these settings manually:

1. Protect `main`: require PR review and required CI checks, disallow force-push and branch deletion, and require the approved review policy.
2. Restrict the Production Environment to deployments from protected `main` only.
3. Require independent Production Environment approval and enable `Prevent self-review`.
4. Keep Production credentials only in the Production Environment secret store. Remove duplicate Production credentials at repository and organization scope; never expose secret values in evidence.
5. Prevent PR authors from satisfying their own review requirement.

Evidence required to close this blocker: read-only branch/ruleset API output showing `main.protected=true` and required checks/reviews; Environment settings export or screenshots showing protected-main-only deployment, required independent reviewers and self-review prevention; and secret-name/scope inventory proving Production secrets exist only at Environment scope (values redacted). The repository owner/admin must attest the configuration and identify the independent approver.

## Production prerequisites and rollback

Before any migration or activation, independently inspect the live Production schema and reconcile historical Supabase migration history. Do not use normal \`supabase db push\`, mark unknown migrations applied, or reset Production based on repository state.

Rollback is operational and fail-closed: disable new outbound work, remove future Cron triggers, allow already-authorized requests to drain, and reconcile ledger/provider outcomes. Preserve queue and suppression history. Keep the inbound provider webhook available while outbound delivery is disabled; it is a safety intake path, not an outbound activation. Never restore an obsolete consent-bypassing RPC or clear suppression state to make delivery resume.

## C208 evidence ledger

- Pre-C208 exact-head PR #10 validation: [44875441190](https://github.com/ADRN-9/deedlight/actions/runs/44875441190), 7/7 PASS at \`95fb79152243f9581647eae961f3c35cf5d1043b\`.
- Pre-C208 exact-head push validation: [44875436665](https://github.com/ADRN-9/deedlight/actions/runs/44875436665), 7/7 PASS at the same SHA.
- C208 provider-payload compatibility source/test head: `06ca8cf1e21215645bd70dd93f178cd954196929` (tree `fe5e4f98a084d56ee2594fed231b3e8f0d5388f3`). Exact-head [push run 44903890652](https://github.com/ADRN-9/deedlight/actions/runs/44903890652) and [PR run 44903895136](https://github.com/ADRN-9/deedlight/actions/runs/44903895136) both completed **7/7 PASS** at that SHA. All database behavior jobs, provider webhook/concurrency tests, transport revocation races, TypeScript, Next build, Cloudflare packaging, and dependency audit passed.
- No live Production provider, ledger, Cron, consent-revocation, or kill-switch evidence is claimed.

## C226 remediation evidence ledger

- C225 reviewed target: `2d5d00371409a151c7c2ce23cb978b2eaa867e91`, tree `64253539093d9057a571c8a3103766292cf370ce`.
- C222 SQL ACL regression: `scripts/test-delivery-provider-webhooks.sql` asserts effective privileges for `anon`, `authenticated`, and `service_role`, including the renamed private implementation and legacy RPC overloads.
- Historical C222 exact-head validation: [push run 44929835404](https://github.com/ADRN-9/deedlight/actions/runs/44929835404) and [PR run 44929840101](https://github.com/ADRN-9/deedlight/actions/runs/44929840101), both 7/7 PASS at C222 HEAD.
- C226 migration 029 identity regression: migration-order test mutates the migration-027 implementation without changing its signature/security metadata, expects migration 029 to reject and roll back, then restores the original and proves the positive migration path plus 5/7/8-argument historical replay.
- C226 migration 030 regression: isolated PostgreSQL tests cover Worker clock two hours behind, skew beyond the 23-hour safety horizon, expired 24-hour provider retention, pre-send fail-closed behavior, invalid/whitespace/control-character receipt IDs, and missing transport-start evidence.
- C226 exact-head CI and independent review: pending; do not infer acceptance from historical C222 runs.
- Human-only GitHub governance and all Production rollout gates remain open. Production remains NO-GO.
