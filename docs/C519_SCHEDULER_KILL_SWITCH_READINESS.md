# C519 — Scheduler and emergency kill-switch readiness

**Repository:** `ADRN-9/deedlight`  
**Inspection baseline:** C518 exact HEAD `97c3ac4aab41dc8a2b598f5bee7b63186f746a37`  
**Implementation branch:** `feat/production-evidence-collector-e1-e2`  
**Production disposition:** **NO-GO**. No Cron was activated, no Production environment variable or queue was changed, no credentials were accessed, and no real provider email was sent.

## C518 CI refresh

The C518 exact-head run [45910456594](https://github.com/ADRN-9/deedlight/actions/runs/45910456594) is now **completed / cancelled**, with exact `head_sha=97c3ac4aab41dc8a2b598f5bee7b63186f746a37`. The workflow-jobs endpoint returned no jobs for this run. This is not a PASS and does not establish whether the new package-integrity test executed. The preceding C518 push runs on intermediate commits were cancelled due to subsequent branch pushes. The older baseline run 45909902352 succeeded at the pre-C518 source SHA `4c15744e9b8d5540559e68ef11cdfdfd64fa96b1`; it cannot validate C518 changes.

C519 implementation commits supersede that HEAD; a new exact-head run is required.

## Scheduler implementation inspected

- `custom-worker.ts` receives Cloudflare scheduled events and passes their cron string and scheduled timestamp to `runScheduledDelivery`.
- `lib/delivery/scheduler.ts` routes exact cron strings: Daily `*/5 * * * *`; Weekly `0 16 * * 1`.
- `wrangler.jsonc` has `triggers.crons: []`. There are no configured Cron Triggers in the inspected source. This is source/configuration evidence, not proof of the deployed Production Worker configuration.
- The scheduler parses `DELIVERY_ENABLED` before doing work. Any value other than exact `"true"` returns disabled before enqueue, claim, runtime creation or provider IO.
- With delivery enabled, Daily enqueue uses the event's scheduled time; claiming uses the database RPC. Claim batches are capped at five.
- Weekly enqueue uses the curated issue RPC, bounded 5,000 issue ceiling and safe error handling. The SQL enqueuer enforces current curation/consent and capacity constraints.
- `processClaimedDelivery` checks authorization before recipient lookup, checks again after lookup, calls the atomic `begin_delivery_transport` gate, then calls the database-authoritative provider-idempotency-window authorization before the provider side effect.
- The final DB gate binds current recipient email, preference/consent, suspension and provider suppression state, claim token/lease and the provider idempotency horizon.
- Resend uses a stable key per logical ledger job, bounded request timeout, classifies retryable/permanent/ambiguous results, and does not log recipient/provider payloads.

## C519 bounded implementation

A defense-in-depth Weekly gate was missing: although Wrangler has no Cron triggers, a manually configured or accidentally added Weekly trigger would route to Weekly enqueue whenever the global `DELIVERY_ENABLED=true`.

Added to `lib/delivery/scheduler.ts`:
- `WEEKLY_DELIVERY_ENABLED` must equal exact `"true"` before Weekly schedule processing.
- Missing, false, malformed or differently cased values hold Weekly before Supabase runtime construction, enqueue, claim or provider IO.
- A held invocation returns an ignored summary and logs only a fixed reason code.

Added to `scripts/test-delivery-transport.mjs`:
- Tests for missing, false, uppercase and explicit true Weekly flag values.
- A simulated Weekly event with global delivery enabled but Weekly flag absent; asserts no enqueue, claim or send and verifies the fixed safe log.
- A disabled invocation followed by configuration parsing of an enabled state; confirms the kill-switch configuration is reversible without queue mutation.

Added to `scripts/verify-gentle-delivery-transport.mjs`:
- CI static assertions that the Weekly gate exists and executes before runtime construction.
- Existing assertion continues to require an empty Wrangler Cron array.

This does not activate either schedule. It creates a second, independently controlled gate for any future Weekly Cron.

## Existing executable coverage and limits

| Invariant | Existing coverage | Evidence class / remaining gap |
|---|---|---|
| Current consent before provider send | Transport unit tests cover revocation after recipient lookup; SQL consent/final-recipient gates and concurrency tests cover row-lock behavior | Simulated and disposable PostgreSQL CI only; no Production consent race test |
| Expired claim / stale token | Migration 028 lock/lease tests and reliability concurrency SQL; migration 030 final provider gate tests | CI database behavior; no Production lease evidence |
| Idempotency and bounded retries | Stable provider idempotency key tests; migration 030 DB-clock retry and 23-hour safe horizon; five-attempt terminal tests | CI only; no real provider retry/ambiguous-outcome evidence |
| Provider failure / ambiguous outcome | Transport tests for 408/429/5xx, 4xx, auth rejection, malformed 409, network timeout, malformed success, invalid receipt ID | Simulated fetch only; no Production provider response evidence |
| Global kill switch | Config parser tests prove any value other than exact true is disabled; scheduler test asserts disabled invocation has zero work and does not read secrets | Unit/simulated only; Production no-enqueue/no-claim/no-send proof absent |
| Safe re-enablement | Config test confirms disabled and enabled config states parse as expected; DB retry/claim logic remains authoritative | Does not prove Production re-enable, queue drain, stale claim recovery or safe provider replay |
| Weekly not premature | Curated SQL RPC, capacity tests, existing exact Cron routing, empty Wrangler Cron list | C519 adds explicit second environment gate and simulated negative test; no deployed Production gate inspection |
| Multiple healthy Daily cycles | No Production cycle evidence found | Not established; requires staged live evidence described below |

The transport tests use fake gateway/recipient/transport implementations and fake fetch responses. PostgreSQL tests use disposable PostgreSQL 16 services. These are not live scheduler invocations, not actual Resend sends, and not Production ledger/runtime evidence.

## Required staged Daily evidence (non-Production first)

A staging environment must be isolated from Production data, credentials and provider recipient lists. Use an approved staging provider account/domain and explicit test recipients only.

For each observed cycle capture:
1. Exact Worker deployment ID, source commit SHA and effective Cron configuration.
2. Scheduled event timestamp, expected Daily schedule kind, and invocation start/end.
3. Redacted scheduler summary: enqueued, claimed, sent, retried, failed, cancelled, processing errors; no member IDs, emails, claim tokens or raw provider payloads.
4. Corresponding staging ledger rows and transition timestamps, with stable logical delivery key and claim/attempt state.
5. Provider request/response evidence: stable idempotency key (redacted or hashed), provider message ID, accepted/delivered/bounced/complained status and provider event timestamp.
6. Consent snapshot/authorization decision immediately before send, suppression status and final recipient identity binding, captured without exposing email addresses.
7. Reconciliation proving one logical job per eligible recipient/day, no duplicate provider message IDs, no sends after opt-out/suspension, and no stuck claims beyond lease.
8. Cron invocation gaps, error rate, queue age, retry exhaustion and provider suppression/integrity anomalies.

Acceptance should require at least three consecutive scheduled Daily cycles with nonzero expected test deliveries, all ledger transitions reconciled to provider evidence, no duplicate external sends, no unexpected cancellations/failures, and no unresolved ambiguous provider outcomes. The owner must approve the exact cycle count and acceptable latency/error thresholds before staging execution. The count is an operational acceptance proposal, not a completed test.

## Production activation sequence — human approval at every gate

**Gate 0 — prerequisites**
- Complete independent security review and PR #25 acceptance; resolve migration-history reconciliation blockers.
- Confirm branch protection, Production Environment protections, named independent approver and Environment-only secret scope.
- Verify provider webhook, bounce/complaint suppression and integrity monitoring using approved non-member tests.
- Confirm `DELIVERY_ENABLED=false`, `WEEKLY_DELIVERY_ENABLED=false`, and deployed Cron list empty.
- Approve rollback owner, provider contact, on-call coverage, observation window and abort thresholds.

**Gate 1 — Daily only**
- Human approver enables only Daily Cron `*/5 * * * *` in the controlled deployment/configuration process.
- Keep `WEEKLY_DELIVERY_ENABLED=false` and do not add Weekly Cron.
- Start with a separately approved small staging cohort; Production cohort requires a distinct explicit release approval.
- Reconcile every invocation, ledger transition and provider outcome. Do not proceed on aggregate send counts alone.

**Gate 2 — multiple healthy Daily cycles**
- Complete the agreed number of consecutive cycles (proposed minimum three) with full invocation/ledger/provider/consent evidence.
- Investigate and close all retry exhaustion, ambiguous outcomes, claim lease anomalies, duplicate provider IDs, suppression conflicts and consent mismatches.
- Independent reviewer signs the cycle evidence index and acceptance decision.

**Gate 3 — emergency kill switch**
- Human operator sets `DELIVERY_ENABLED=false` in the protected Production environment.
- Verify subsequent invocations show disabled reason and zero enqueue, claim and provider requests; verify no new logical deliveries are introduced.
- Verify in-flight calls are bounded and reconcile any provider request whose outcome was ambiguous before re-enable.
- Preserve queue, ledger and suppression evidence; do not delete or rewrite rows to simulate success.

**Gate 4 — safe re-enablement**
- Human operator restores `DELIVERY_ENABLED=true` only after the kill-switch evidence is independently accepted.
- Verify only eligible, consented and unsuppressed jobs resume; expired claims are safely reclaimed; stable provider idempotency prevents duplicate logical delivery.
- Reconcile all pre-disable in-flight attempts before any retry. Any unresolved provider ambiguity blocks re-enable.

**Gate 5 — Weekly Goodness**
- Only after Daily cycle acceptance, kill-switch proof and safe re-enablement acceptance.
- Require curated Weekly issue and valid consent; set `WEEKLY_DELIVERY_ENABLED=true` through a separate approved change.
- Add Weekly Cron `0 16 * * 1` only with a separate change approval and monitored capacity.
- Confirm 5,000 issue-wide capacity guard, explicit curation, recipient consent, ledger/provider reconciliation and safe rollback. If any gate is missing, keep Weekly flag false and Cron absent.

## Production operational checklist

### Before each approved window
- [ ] Exact commit, Worker deployment and effective Cron configuration recorded.
- [ ] Delivery global flag and Weekly flag independently inspected (values only; no secrets).
- [ ] Provider account/domain/webhook health verified; no unresolved bounce/complaint/suppression anomalies.
- [ ] Named operator, independent approver, DBA/security contact and rollback owner present.
- [ ] Staging acceptance and migration/PR approval gates complete.
- [ ] Baseline ledger, queue age, retry and provider reconciliation captured.

### During observation
- [ ] Invocation success/failure, duration, missing Cron ticks and scheduler summary.
- [ ] Queue depth/oldest eligible item, claim age/expiry, retry attempt count and terminal failures.
- [ ] Ledger-to-provider reconciliation and duplicate provider ID checks.
- [ ] Current consent and suppression decisions; opt-out test confirms zero provider requests.
- [ ] Bounce, complaint, hard/soft bounce, provider auth failure, rate limit and ambiguous timeout monitoring.
- [ ] Privacy-safe logs only; no email, token, raw webhook body or provider secret.

### Abort and rollback
Immediately disable outbound delivery and stop future Cron triggers for any consent mismatch, duplicate send, stale-token acceptance, claim lease anomaly, provider idempotency ambiguity beyond safe horizon, suppression-integrity conflict, credential exposure, abnormal failure/complaint rate, missing telemetry or unexplained queue growth. Keep inbound provider webhooks active for suppression safety. Preserve evidence and reconcile ambiguous sends before retry. Never clear suppressions or mutate queue history to force a green dashboard.

### Evidence package
- Worker deployment ID, exact commit, effective Cron and environment change audit events.
- Per-cycle redacted invocation summaries, ledger transition extracts, provider event/message evidence, consent/suppression authorization results.
- Kill-switch operator/time, subsequent no-work invocations, zero provider-request proof, in-flight reconciliation and re-enable approval.
- Weekly curation approval, capacity result and separately approved flag/Cron change.
- Independent reviewer acceptance, rollback outcome and final smoke evidence.

## Human-controlled dependencies and blockers

- Cloudflare administrator must supply effective deployed Worker/Cron and Production Environment configuration evidence; repository Wrangler file cannot prove deployed state.
- Production owner must approve each environment/flag/Cron change. No automation or repository commit authorizes this.
- Resend account owner must provide redacted provider delivery/bounce/complaint and webhook evidence; no real send was performed.
- DBA/security must approve Production collector/ledger inspection and any read-only evidence export.
- Independent security reviewer must accept PR #25; PR #25 remains OPEN/UNMERGED at last inspected state.
- Migration provenance reconciliation remains outstanding; unknown duplicate 007 and other uncertain historical migrations block normal Production migration push.
- Production branch protection, environment reviewer and secret-scope controls remain to be independently verified.
- No actual Production scheduler cycles, kill-switch exercise, re-enablement, or Weekly scheduling are evidenced.

**Status: implementation and test assertions committed; exact-head C519 CI pending. Production remains NO-GO.**

## Follow-up: C518 package fixture failure and correction

During C519 inspection, the intermediate run [45910822310](https://github.com/ADRN-9/deedlight/actions/runs/45910822310) executed the C518 offline package tests and failed at `TRANSACTION_CLOSE_MARKER_MISSING`. The fixture had emitted a two-column row `collector_transaction_closed,t`, while the collector's CSV contract requires a one-column marker header followed by a separate one-column `t` rollback result. Corrected `scripts/test-evidence-package-integrity.mjs` to emit those two rows exactly. This is a fixture-only correction; production collector behavior was not changed. The subsequent exact-head run must confirm it.

C519 exact-head validation is pending at [run 45910980847](https://github.com/ADRN-9/deedlight/actions/runs/45910980847), HEAD `d8ccd5dfaa3eaaae147e9ebaa1ae651733bdc834`, at the time this report was last updated. No job results were yet available. The prior run 45910933290 is on an earlier documentation commit and does not validate the corrected fixture or final C519 source head.
