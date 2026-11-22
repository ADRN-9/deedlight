# C253 — Deterministic final authorization concurrency matrix

## Scope

This suite exercises the real migration 031 RPC:

`public.authorize_delivery_idempotency_window(uuid, uuid, text)`

It does not replace, edit, or claim completion of C249. It does not change migration 031 or any historical migration. PR #11's metadata-only disposable fixture package remains separate and unchanged.

## Deterministic synchronization

Each lock-order case uses two independent PostgreSQL sessions. A FIFO-controlled psql session opens a transaction, acquires the mutation lock, and remains open until the test releases it. The competing session calls the final authorization RPC. The harness does not infer contention from a fixed SQL sleep: it polls `pg_stat_activity`, `wait_event_type`, and `pg_blocking_pids()` to prove the exact waiter is blocked by the intended holder before releasing either transaction.

The only short shell sleeps are polling intervals. No `pg_sleep` SQL barriers are used.

## Matrix

| Scenario | Expected result |
|---|---|
| Daily consent mutation first | Authorization waits, then cancels |
| Final authorization first, Daily revocation second | Revocation waits for authorization commit |
| Weekly consent, both lock orderings | First lock holder wins; revocation-first cancels, authorization-first commits before revocation |
| Profile suspension, both lock orderings | First lock holder wins the serialization boundary |
| Auth email change, both lock orderings | Stale recipient is cancelled; later change waits |
| Auth email-confirmation revocation, both lock orderings | Unconfirmed identity is cancelled when revocation wins; later revocation waits for authorization commit |
| Weekly curation removal, both lock orderings | Removal and authorization serialize |
| Provider complaint suppression, both lock orderings | Shared recipient advisory lock serializes the RPCs |
| Claim expires during Auth-row lock wait | RPC fails closed; claim remains unmodified and expired |
| Claim expires during recipient advisory-lock wait | RPC fails closed; claim remains unmodified and expired |
| Five-second lock timeout | SQLSTATE 55P03; no provider attempt |
| Stale claim token | SQLSTATE 42501; ledger claim remains unchanged |
| REPEATABLE READ | SQLSTATE 25000; ledger claim remains unchanged |
| Caller transaction rollback | RPC cancellation rolls back with the caller transaction |
| Worker connection termination while blocked | Backend rollback; no provider attempt |
| Same-recipient concurrent claims | Advisory wait is observed; deadlock counter does not increase |
| Duplicate attempts for one logical delivery | Ledger-row serialization; both authorizations retain the same stable provider idempotency key |

Every scenario asserts the delivery-ledger state, exact claim token, and exact expiry value (including intentionally expired leases). Cancellation assertions also verify the original live claim token and expiry snapshot, cleared claim token/expiry, cancellation timestamp, and authorization-revoked terminal code. A test-only provider-attempt probe records whether the Worker would proceed after authorization; denied outcomes must have zero probe rows. The probe never calls Resend or any external transport.

For authorized-first cases, the probe is written only after the authorization transaction commits and the later mutation completes. This deliberately demonstrates the documented post-commit boundary: a later revocation cannot recall an already-authorized attempt. No database transaction is held open across HTTP.

## Disposable execution boundary

The C253 job provisions its own GitHub Actions `postgres:16` service and a dedicated `deedlight_migration_order_test` database. The harness requires the exact repository, a push or pull-request event, the C253 CI-only acknowledgement, `DELIVERY_ENABLED=false`, the expected local service identity, and exactly one running `postgres:16` container. It refuses libpq routing overrides and Production credential/configuration variables. The database is ephemeral with the CI service; the script does not drop a fixed database or delete unrelated fixtures.

The job establishes the reviewed migration sequence through 031 in that isolated service before running the matrix. The Auth email-confirmation cases mutate only disposable Auth fixture rows: revocation-first must wait on the Auth row, observe the committed null confirmation timestamp, cancel and invalidate the claim with zero provider-attempt probes; authorization-first must hold the Auth share lock while revocation is observed waiting, then commit authorization before the revocation proceeds.

## Explicit non-claims

- C249 disposable PostgreSQL isolation remediation remains outstanding.
- No Production database, deployment, scheduler, or provider operation is performed.
- The probe validates the Worker authorization gate and stable key construction; it is not a live provider idempotency test.
- The tests prove database lock ordering and post-commit semantics, not the ability to recall an external request after authorization commits.
