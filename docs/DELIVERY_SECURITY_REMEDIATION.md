# Delivery Security Remediation — Cycle 3

Base: `ce82b3fdf1a73510de70e3729a487d4ae00e66e3`.

## Authority and concurrency

Migration 023 replaces the two enqueue functions and `begin_delivery_transport`, without editing historically applied migrations. The service-role-only transport RPC locks the claimed ledger row, validates claim state/token/lease, then takes `FOR SHARE` locks on the current relevant consent, active profile and (weekly) confirmed Auth user / curated feature rows. `FOR SHARE` conflicts with UPDATE/DELETE of consent and suspension rows. Under PostgreSQL READ COMMITTED, if revocation committed before lock acquisition, the transport RPC observes the revoked state and atomically marks the job cancelled, returning NULL. Stale/expired claims raise 42501. The Worker treats NULL as cancellation and does not call Resend.

The authorization linearization point is the locked eligible-row read in `begin_delivery_transport`. An update already holding the row lock serializes before the send authorization. If authorization wins first, revocation waits until its transaction commits; once the RPC completes, a newly committed revocation cannot recall an already-authorized in-flight HTTP request. A subsequent retry requires new current-consent authorization. This is the physical limitation of an external side effect and must be explained to operators; the design does not promise retroactive cancellation.

The synchronized PostgreSQL regression proves both orders: revocation-first denies transport, and transport-first holds consent locks until its DB authorization transaction commits. No provider send is performed in these tests.

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

## Cycle 5: identity and capacity corrections

Migration 024 changes the database transport RPC contract from two arguments to
three by requiring the expected confirmed recipient email. The old two-argument RPC
is dropped, not left as a bypass. The email is carried only in a service-role
request parameter, compared to the currently locked Supabase Auth user row, and
never stored in the ledger, repository, or browser-visible data. A changed email
returns NULL (cancelled), and the worker makes zero provider calls.

The claim expiration is checked with clock_timestamp() both after eligibility
locks and in the final transport-start UPDATE, so a lease expiring during lock
contention fails SQLSTATE 42501. The prior now() transaction timestamp was stale.

Weekly has an explicit fail-closed over-capacity gate: exceeding the 5,000
configured recipient limit raises SQLSTATE 54000 and rolls back all enqueueing.
CI creates 5,001 synthetic opted-in users to prove no partial work, then
tests 5,000 unique jobs and repeat-call idempotency. Operators must review
capacity before activating Weekly. This is not permission to increase Cron.

Project npm link/push scripts and manual workflow now verify both the approved
non-Production target and linked Supabase project identity. The raw CLI invoked
outside these scripts remains an out-of-band operator risk and is prohibited
against Production until migration-history reconciliation.

The two-argument RPC is removed on migration 024. Apply migration 023 then 024
in a guarded, approved, *disabled* Production rollout before deploying the new
Worker. Any older Worker fails closed until its RPC arguments are upgraded.
No old insecure RPC may be restored by rollback.

## Dependency security remediation

Source dependency upgrades: Next 16.3.6 -> 16.4.6; Zod 4.4.3 -> 4.6.7;
OpenNext Cloudflare 1.20.2 -> 1.20.17, bringing AWS adapter 4.1.16,
Wrangler 4.161.0, sharp 0.35.5, body-parser 2.4.0, proxy-addr 2.0.8,
qs 6.17.1 and patched undici branches. A narrowly scoped, semver-compatible
`source-map-js ^1.2.2` override resolves advisory GHSA-68fv-2mgg-jv7q,
which otherwise remains at 1.2.1 in the lockfile.

Remaining moderate findings in glob/minimatch originate from supported
OpenNext/TypeScript ESLint upstream constraints; forcing glob 14/minimatch 11
across major peer ranges is not justified without upstream compatibility.
The unsuppressed `npm audit --audit-level=high` continues as the CI gate.
See exact-head CI and npm lockfile for final evidence.

### Undici patch floor

The lockfile's Miniflare 5.20261110.2-beta originally pinned undici 7.30.1.
Upstream GHSA-mqg3-3v4r-cm32 (high, shared redirect-cache disclosure)
affects that exact version; 7.30.2 is the published patch. A narrowly
scoped parent-version override requests undici 7.30.2 only for Miniflare,
rather than replacing the separate 6.x Undici package or forcing a major.
Remove this override once an audited Wrangler/Miniflare release carries the fix.
