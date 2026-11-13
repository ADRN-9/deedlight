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

## Cycle 7: migration prerequisite and issue-wide Weekly ceiling

Migration 023 now adds three schema-local function comments attesting its
reviewed daily-exclusion, weekly-exclusion, and locked-consent contracts.
Migration 024 refuses to run unless those exact markers exist **and** the
live PostgreSQL function definitions retain the relevant reviewed behavior.
This is independent of Supabase CLI migration history and works with
an otherwise proven live schema. The 021 -> 024 negative test must error
before creating the recipient-bound RPC; 021 -> 023 -> 024 succeeds.
If 023 was previously applied without the attestations, block 024 until
an independently reviewed schema audit explicitly reconciles its behavior.
No automatic migration-history repair or Production push is authorized.

A Weekly issue has a hard ceiling of **5,000 distinct logical ledger rows**,
regardless of queued, claimed, sent, cancelled, or failed state. Rows are never
deleted or discounted to regain capacity. Both direct service-role
`enqueue_weekly_goodness_delivery` and its curated-issue wrapper use the same
transaction-scoped advisory lock keyed by ISO week-start date and require
READ COMMITTED isolation. The next SQL statement after lock acquisition
observes the prior committed invocation's rows. At most 5,001 candidate
identities are sampled; if all currently eligible new opt-ins cannot fit the
remaining issue capacity **and** the caller's p_limit, the RPC raises
SQLSTATE 54000 before insertion. The policy is intentionally all-or-nothing
for each invocation, not a silent partial batch.

**Eligibility cutoff:** a current committed preference/identity snapshot is
taken after acquiring the per-issue lock. Members opting in after that
snapshot are considered by a later invocation. If the issue is full, that
later invocation explicitly errors; it never reports all opt-ins scheduled.
Revocation after enqueue is checked again at transport; cancelled and failed
logical rows still occupy their issue-wide slots. The curated wrapper returns
zero when no issue is curated; a curated but over-capacity issue errors.
Operator monitoring must surface SQLSTATE 54000; no provider send is performed
by enqueue functions. Manual privileged inserts that bypass these RPCs remain
an out-of-band risk; disallow them by operational policy.

A synchronized two-session test proves that when 4,999 rows exist and a
single later opt-in becomes eligible, concurrent invocations return one and
zero, respectively; a subsequent sixth-thousandth member is denied.
The CI negative migration-order test confirms transaction rollback after
the missing-023 preflight.

## Cycle 9 — exact prerequisite contracts and Weekly observability

Migration 024 pins the built-in `md5(pg_proc.prosrc)` digest of the three
reviewed migration-023 PL/pgSQL bodies. Unlike `pg_get_functiondef`,
`prosrc` retains the stored source body verbatim, independent of server
formatting. The repository security verifier recalculates hashes from 023
source and compares them with 024. Security-definer, volatility and
search_path metadata remain prerequisites. PostgreSQL built-in `md5`
requires no pgcrypto extension. A synchronized CI migration-order test
replaces a meaningful suspension predicate while keeping the existing
migration-023 comment and recognizable SQL fragments. Drifted 023 -> 024
fails atomically; authentic 023 -> 024 succeeds.

The Weekly RPC emits SQLSTATE 54000 with a fixed non-sensitive DETAIL marker
`deedlight:weekly-issue-capacity:v1`. The server-only Supabase adapter
requires exact SQLSTATE, message, and detail before classifying an error as
`weekly_capacity_exceeded`. Ordinary database failures are reported as
`weekly_enqueue_database_error`. Cloudflare logs only the stable internal
code and the UTC Monday of the affected issue, with no raw provider/database
payloads, member identifiers or recipient data. Both cases still reject the
scheduler invocation before claim or external transport. Existing 5,000-row
issue-wide capacity, consent, retry and idempotency controls remain unchanged.

Production remains blocked pending authorized schema inspection, historical
migration reconciliation, safe application of 023/024, independent review,
and staged scheduler/provider/kill-switch evidence. Do not use Production
`supabase db push`, restore the unbound transport RPC, or treat CI as
Production proof.
