# Cycle 22 — DeedLight isolated CI feasibility candidate

**Not a release candidate; no Production or main merge authority.** Created only under Level 2-authorized non-Production worker cycle 22.

## Exact source provenance
- Base is delivery PR #10 at `c983e2ed8b93c935139c935343261570ecea6978`.
- All 24 audit-file blobs are copied unchanged from audit PR #11 at `aed588d771dc04fda5e5c18d8611239ac926a513`.
- Independent combined tree commit `759da1ce0cf6a9a7ef7e50256164dae3edcc6624` contains PR #10 tree plus the 24 audit blob paths; it is not a merge of either PR to main.
- Only **four** audit-environment files differ from PR #11 for this test branch: `.github/workflows/deedlight-audit-fixtures.yml`, `security/audit-deedlight/proposed_ci.yml`, `security/audit-deedlight/run_disposable_fixture.sh`, and `security/audit-deedlight/MANIFEST.sha256`.
- The two workflow YAML files add this exact candidate branch to the test push trigger; the fixture runner *pins* its allowable GitHub ref to this exact candidate branch; the file integrity manifest is rehashed. SQL, JSON schema, 82-invariant inventory, assertion tool, fixture exceptions and all tests stay byte-identical to PR #11.
- Because the fixture runner and workflow changed (even only branch context), **Cycle 21's approval is not portable to this candidate.** Require fresh independent review at final SHA. The original PR #11 remains unchanged.

## Standard CI root cause confirmed in PR #11 run logs
- Baseline main lock: Next.js 16.3.6, body-parser 2.3.0, proxy-addr 2.0.7, @opennextjs/cloudflare 1.20.2, @opennextjs/aws 4.1.0, @node-minify/core 8.0.6, zod 4.4.3, glob 12.0.0; standard `npm audit --audit-level=high` on PR #11 reported 21 advisories (12 moderate, 7 high, 2 critical), including Next.js, body-parser, proxy-addr, sharp, source-map-js, undici, zod, glob/minimatch.
- Reviewed PR #10 lock: Next.js 16.4.6, body-parser 2.4.0, proxy-addr 2.0.8, @opennextjs/cloudflare 1.20.17, @opennextjs/aws 4.1.16, @node-minify/core 10.5.0, zod 4.6.7, glob 13.0.7, with existing guarded overrides. The candidate references **the same exact PR #10 package.json and package-lock.json blobs**.
- The old `scripts/test-gentle-delivery-transport.sql` used fixed `2026-10-26` claim times; by November 13 the claim authorization fails at line 96 rather than proving a delivery regression. PR #10 uses current UTC week/time in its tested 021 fixture and replaces the SQL job with `test-delivery-consent-gates.sql` plus synchronized revocation/transport concurrency, and adds 023/024 migration-order checks. Neither expiry nor authorization is bypassed.
- Unsuppressed advisory audit and all preexisting delivery, consent, suspension, idempotency, capacity and migration guards remain intact. No `npm audit fix --force` or test skip.

## Evidence and STOP gates
- Validated in **separate** workflows: `.github/workflows/pr-validation.yml` from PR #10, and `.github/workflows/deedlight-audit-fixtures.yml` from PR #11 (limited to this exact temporary test branch).
- Exact-head CI run IDs and findings must be supplied in the Cycle 22 handoff after CI completes. A red or cancelled workflow is NOT PASS. Synthetic PostgreSQL is not Production.
- Audit source SHA pin remains `c983e2ed8b93c935139c935343261570ecea6978`, and catalog source behavioral correspondence remains UNKNOWN where already documented; no rewrite of reviewed audit SQL.
- Before any formal integration proposal: record the full combined diff and conflicts, review temporary workflow/runner changes, independently validate final source, and plan clean merge history/rollback. Cycle 23 owns that work; this task cannot merge to main, deploy, inspect Production, enable delivery, or send emails.

## Governance and release
- Delivery PR #10 and audit PR #11 are draft and unmerged; independent formal approval and explicit merge authority are required.
- Cycle 12 delegation provenance and the earlier HOLD accounting discrepancy remain unresolved; Level 2's cycles 21–30 authorization does not erase earlier record gaps. Cycle 20 acceptance reconciliation is still required.
- Production Supabase project `xaipiovflxomcbfwtwmu` metadata access is blocked; migration history and 023/024 deployment are unverified; provider failures/bounces/complaints, Daily and Weekly rollout, kill-switch exercise, authenticated regression and final smoke remain outstanding; Issue #6 remains OPEN.
