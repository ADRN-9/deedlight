# Delivery Security Remediation — Cycle 3

Base: `ce82b3fdf1a73510de70e3729a487d4ae00e66e3`.

## Authority and concurrency

Migration 023 replaces the two enqueue functions and `begin_delivery_transport`, without editing historically applied migrations. The service-role-only transport RPC locks the claimed ledger row, validates claim state/token/lease, then takes `FOR SHARE` locks on the current relevant consent, active profile and (weekly) confirmed Auth user / curated feature rows. `FOR SHARE` conflicts with UPDATE/DELETE of consent and suspension rows. Under PostgreSQL READ COMMITTED, if revocation committed before lock acquisition, the transport RPC observes the revoked state and atomically marks the job cancelled, returning NULL. Stale/expired claims raise 42501. The Worker treats NULL as cancellation and does not call Resend.

The authorization linearization point is the locked eligible-row read in `begin_delivery_transport`. An update already holding the row lock serializes before the send authorization. If authorization wins first, revocation waits until its transaction commits; once the RPC completes, a newly committed revocation cannot recall an already-authorized in-flight HTTP request. A subsequent retry requires new current-consent authorization. This is the physical limitation of an external side effect and must be explained to operators; the design does not promise retroactive cancellation.

The existing early + post-recipient authorizations remain defense-in-depth, but the DB transport-initiation RPC is authoritative. A denied RPC never invokes the provider.

## Batch and terminal behavior

Both enqueue functions now exclude existing `(kind,user_id,delivery_key)` rows before `LIMIT`; `ON CONFLICT DO NOTHING` and the database uniqueness constraint remain the concurrent dedupe boundary. This lets multiple small batches progress instead of repeatedly selecting already-inserted rows.

`retry_delivery_job` already returns `false` when a fifth attempt is terminated; previously TypeScript treated it as an exception and counted a processing error. The worker now treats `false` as terminal `failed`, preserving the database's five-attempt bound.

## Migration workflow

The manual `supabase db push` workflow now runs `scripts/guard-supabase-migration-target.sh` before `supabase link` or push. The guard rejects the historical Production project `xaipiovflxomcbfwtwmu`, empty/malformed refs, and exits nonzero. Valid non-Production refs remain permitted. CI verifies the control, ordering, and real shell exit statuses. This is a temporary risk reduction, **not** reconciliation of Production migration history.

## Deployment and rollback

This branch must not be merged or deployed without a separately authorized plan. Migration 023 must be applied only after inspecting the *actual* Production schema and confirming 019–022 and live privileges, while Cron stays disabled and `DELIVERY_ENABLED=false`. No automatic `db push` is safe. Apply the migration before any Worker code enabling delivery; old Worker source expects a timestamp, so do not activate a mixed-version rollout until the worker and function behavior are coordinated. For rollback, disable delivery and Cron first. A function-level rollback must preserve authorization locking and ledger state, not restore the unsafe migration-021 function. Do not erase ledger history.

## Remaining gates

A current authorized Production Supabase connection is unavailable. Provider bounce/complaint evidence, multiple daily cycles, weekly curation, kill-switch exercise, authenticated Production regression, and final exact-head CI/deploy/smoke remain separate gates. This PR carries no Production evidence.
