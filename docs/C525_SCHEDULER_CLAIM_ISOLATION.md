# C525 — Scheduler Claim Isolation Remediation

**Project:** DeedLight  
**Repository:** `ADRN-9/deedlight`  
**PR:** [#24](https://github.com/ADRN-9/deedlight/pull/24) — OPEN / UNMERGED  
**Work branch:** `feat/production-evidence-collector-e1-e2`  
**Implementation HEAD at report preparation:** `a9008193f65dc7a2723de0f4fea95b14b06082fd`  
**New migration:** `202611260039_delivery_kind_scoped_claims.sql`  
**Migration blob:** `39eba637aa9f93fa77855f82f3fcc27b580b25da` (6,177 bytes)  
**Migration inventory:** 40 files, 39 unique version prefixes, duplicate 007 pair preserved  
**Inventory Git blob:** `4e63f31368d446e905f4f44565be73337c7188fb`

## 1. Finding and source baseline

The refreshed PR #24 baseline was `13c33f5ecd992dc735fdf6edff0fa4d41c74e79a`.

The scheduler had two application schedule kinds but both paths called `runtime.claim(limit)`; the Supabase runtime used the unrestricted `claim_delivery_jobs(p_limit)` RPC. The SQL implementation selected queued/expired rows without filtering `delivery_ledger.kind`. Therefore, the Weekly application feature gate did not provide database-level isolation against a Daily claim path.

## 2. Database remediation

Migration `202611260039_delivery_kind_scoped_claims.sql` adds two distinct RPCs:

| RPC | Literal allowed kind |
|---|---|
| `public.claim_daily_delivery_jobs(integer)` | `daily_reminder` |
| `public.claim_weekly_delivery_jobs(integer)` | `weekly_newsletter` |

Each function independently applies the literal kind predicate to:
- retry-exhaustion/expired-lease terminalization;
- eligible queued and expired-lease selection, before ordering and batch limiting;
- the final UPDATE from the locked candidate set.

Both RPCs preserve five-minute claim leases, unique fresh claim tokens, bounded five-attempt behavior, expired-lease reclaim and retry-exhaustion terminalization. Database time is used for claim and expiry timestamps; the Worker cannot supply a claim timestamp.

The historical unrestricted `claim_delivery_jobs(timestamptz, integer)` function is retained for historical migration/test provenance but execution is revoked from `PUBLIC`, `anon`, `authenticated` and `service_role`. Only the two kind-specific RPCs are granted to `service_role`.

The new functions use `SECURITY INVOKER`, not `SECURITY DEFINER`. This avoids adding new privileged function ownership requirements; the existing `service_role` ledger privileges and RLS-bypass role are used. No new generic kind-selecting helper exists.

## 3. Application and scheduler defense in depth

- `lib/delivery/scheduler.ts` derives an expected `DeliveryKind` from the exact Cron schedule and requests that kind explicitly.
- `lib/delivery/supabase-runtime.ts` maps Daily and Weekly to separate RPC names.
- Every returned row is validated against the requested kind; a cross-kind response fails closed.
- The scheduler independently checks all returned jobs before processing.
- `DELIVERY_ENABLED=false` remains the first global stop.
- `WEEKLY_DELIVERY_ENABLED === "true"` remains an explicit separate opt-in, checked before Supabase runtime construction.
- Current-consent authorization, recipient resolution, claim expiry/stale-token validation, provider idempotency and transport authorization remain in the existing pipeline.

## 4. Adversarial regression coverage

Added `scripts/test-delivery-kind-claims.sql`, run after migration 039 by `scripts/test-delivery-migration-order.sh`. It creates synthetic Daily and Weekly queued, expired-lease and retry-exhausted jobs and asserts:

- Daily claim returns only Daily rows and does not claim, requeue, terminalize or otherwise mutate Weekly rows.
- Weekly claim returns only Weekly rows and does not mutate Daily rows.
- Expired leases are reclaimed only for the requested kind.
- Retry-exhaustion cleanup is scoped to the requested kind.
- Null, zero and oversized batch limits fail with SQLSTATE 22023.
- The generic unrestricted RPC is not executable by `service_role`.
- Kind-specific RPCs are `SECURITY INVOKER`, are executable by `service_role`, and are not executable by browser roles.
- No generic kind-selecting helper exists.
- A stale pre-reclaim token remains rejected.

Added runtime tests in `scripts/test-delivery-transport.mjs` for exact RPC routing, mismatched returned job kinds, and invalid runtime kind rejection.

Added `scripts/verify-delivery-kind-claims.mjs` and wired it into full PR validation. It verifies the literal SQL kind predicates, privilege grants, legacy RPC revocation, runtime result checks, kill-switch ordering, Weekly opt-in ordering, SQL test coverage and aggregate migration inclusion.

## 5. Migration provenance and evidence tooling

The new migration is pinned in `supabase/migration-inventory.json`, and `supabase/run_in_sql_editor_all.sql` is updated byte-for-byte to the deterministic generator output.

Because the collector and reconciliation analyzer pin the inventory blob, the following active artifacts were updated to the new inventory SHA-1:
- migration inventory/aggregate verifier;
- Production migration evidence collector and receipt schema;
- collector and evidence-package fixtures;
- migration reconciliation analyzer and adversarial fixtures;
- Production migration evidence runbook.

The older C517 provenance assessment and original reconciliation ledger remain historical snapshots; their original baseline hashes are not rewritten. The current inventory and C525 supplemental source delta are recorded separately.

## 6. CI execution status

The final code commit at report preparation is `a9008193f65dc7a2723de0f4fea95b14b06082fd`.

- Earlier run `45916208693` exposed two draft issues: the Weekly fixture counted a pre-existing same-kind fixture row, and the aggregate had one extra newline. Both were corrected.
- Earlier run `45916602103` exposed stale 39/38 assumptions in the signed migration reconciliation analyzer fixtures after inventory growth. The analyzer, receipt pin and tests were updated to 40/39.
- Run `45917143724` was created for exact HEAD `a9008193f65dc7a2723de0f4fea95b14b06082fd`; it was still pending when this report was prepared. Therefore no final exact-HEAD CI pass is claimed here.

Required final checks are the PR Validation workflow, including the migration-order PostgreSQL behavior test with migration 039, migration inventory/aggregate verification, migration reconciliation adversarial tests, new claim-isolation verifier, existing security assertions, TypeScript, Next.js build, Cloudflare package and dependency audit.

## 7. Production boundary and remaining risks

- No Production migration was executed.
- No Production migration-history record was edited or marked applied.
- No Production credential, database, provider, Cron, kill-switch or delivery configuration was changed.
- No email or external provider request was sent.
- No PR was merged and no scheduler was activated.

The two claim RPCs enforce kind isolation for application claim calls. The existing `service_role` remains a privileged database principal with direct ledger privileges; a compromised service-role credential could bypass RPC-level scheduling discipline by issuing direct table mutations. That pre-existing privileged-role trust boundary is not represented as eliminated by this migration.

PR #25's independent-review dependency remains outstanding. C524's successful CI is not independent security approval. No C524 review is treated as approval of this C525 change.

**Acceptance status:** implementation committed; final exact-HEAD CI and independent review remain required before this remediation can be considered fully validated. No Production rollout is authorized by this work.
