# DeedLight Cycle 74 — Executed Adversarial PostgreSQL 16 and Webhook Security Ledger

**Task:** `DL-C74-POSTGRES-ADVERSARIAL-SECURITY-D01` / `1cd95cac4fb24652ac09b951020ee4ea`  
**Project:** DeedLight only. 2026-11-14.  
**Scope:** real disposable PostgreSQL and localhost signed-webhook testing; shared-branch writes, Production SQL, credentials, provider messages and cron prohibited.  
**Disposition:** isolated correction **CLOSED—VERIFIED**, shared-source integration **BLOCKED**, independent security acceptance **OPEN**, Production **NO-GO**.

## 1. Source and exact tested tree

- Repository `ADRN-9/deedlight`, PR #10 unmerged starting commit `c983e2ed8b93c935139c935343261570ecea6978`. Historical `main` `ce82b3fdf1a73510de70e3729a487d4ae00e66e3`.
- Cycle 73 evidence commit `a25a43a85d74a5a5b9d05309ad0840df8ddcd8cf`, full patch `evidence/deedlight-c73-integrated-security-d8700788/results/C73_COMPLETE_RESOLVED_INTEGRATION.patch`, SHA256 `864c3fae8df6b3c60fbcf17f0189e633ae1b1de54a01dde01738c545f53dc8d9`.
- Both final jobs independently checked exact PR #10 checkout, applied that original patch, and asserted C73 Git tree `dd4f8593fdb1b3032eb6cddd5f39e50ea9cb7682`.
- Only isolated source correction is **`supabase/migrations/202611130031_c74_legacy_lifecycle_guard.sql`**, staged *after* the validated C73 local tree; it does not modify authentic 025–030. Patch `results/pg/C74_POST_C73_CORRECTION.patch` (Git blob `254af5ad7b607565e1aad8a6cdc144053a38633a`) SHA256 **`71412f3345a34ba3e7ad1246cbfd0165b6d765fdbd719c97d045a6fae265a1fc`**, 4,245 bytes.
- **Final tested corrected Git tree: `a9981c2672b316a07904ad7f6b498cd22f206a5b`**. Both PostgreSQL and HTTP/Next jobs checked this exact tree, after copying the same reviewed 031 file into disposable app trees.
- Independently replayed 031 patch from exact local reconstructed C73 tree with `git apply --check`, staged, `git diff --cached --check` and `git write-tree`: exact `a9981c2672b316a07904ad7f6b498cd22f206a5b`, PASS. No shared application commit or PR merge exists.

## 2. Real defect and isolated remediation

**FAILED before correction:** [Actions 43628859450](https://github.com/ADRN-9/deedlight/actions/runs/43628859450), PostgreSQL job `132550749716`: `C74 DEFECT: processed event ID accepted into pending table`. The original 030 `c73_registry_guard` checked authoritative event metadata but did **not** disallow inserting an already-processed `svix_event_id` into the separate pending table. Matching metadata could recreate contradictory physical lifecycle rows while one registry row existed.

**Migration 031 fixed this without weakening the original migration:** preflights expected 030 graph and existing `ENABLE ALWAYS` triggers; installs private `SECURITY DEFINER` function with `SET search_path=pg_catalog,pg_temp`; revokes all browser/service EXECUTE; installs `ENABLE ALWAYS BEFORE INSERT` guards on the exact `public.delivery_provider_events`, `public.delivery_provider_pending_events`, and `public.delivery_provider_identity_conflicts` tables. Pending may be projected only while registry state is pending and the ID is absent from processed/conflict projections. Processed may be projected while registry is pending/processed for the existing atomic 027 promotion protocol but never after conflict; conflict projection requires registry state `identity_conflict`. This preserves the preexisting 030 UPDATE/DELETE/TRUNCATE denials and legitimate pending promotion.

**Post-correction negative actually executed:** source fixture `vectors/postgres-security.sql` inserts an identical processed event into pending under database owner privilege and **requires SQLSTATE 42501**; passed. It also probes three fixed SECURITY DEFINER search paths, `ENABLE ALWAYS` trigger catalog, browser-role denial, and revoked legacy webhook entry points. An owner can temporarily bypass a trigger, so historical collision tests separately examine the enablement fence; this is not a claim that a DB superuser is untrusted.

## 3. Exact executable CI evidence — all PASS

- Core actual tests: [Actions 43629746763](https://github.com/ADRN-9/deedlight/actions/runs/43629746763), both `postgres` and `http_build` SUCCESS.
- Extended history/bounce tests: [Actions 43630060751](https://github.com/ADRN-9/deedlight/actions/runs/43630060751), both SUCCESS.
- Final fully published run: [Actions 43630242801](https://github.com/ADRN-9/deedlight/actions/runs/43630242801), source commit `b7741f7a2512fc3a1ee5aa17fab299b2e91dfc86`, **postgres SUCCESS / http_build SUCCESS / publish_evidence SUCCESS**.
- Final evidence publication commit `017343fa12671eb4b70886a7712f25cd98ae52ee`. The manifest `results/SHA256SUMS.txt` (Git blob `12de0fc011ac92e2b6970884bc52c1b44e1f0003`) lists **33 artifact files**. `sha256sum --strict --check` passed in publishing CI; the raw artifacts, negative logs, execution scripts, patch and resultant tree are independently retrievable in GitHub evidence-only files.
- GitHub service: `postgres:16`, actual server `16.16 (Debian 16.16-1.pgdg13+1)`. Node `24` in application job.
- Boundaries: `DELIVERY_ENABLED=false`, synthetic `.test` recipients, synthetic keyring, mock database client for local HTTP route, no real provider or Production endpoint. Jobs check absence of privileged secrets/config before execution.

### Executed PostgreSQL order

1. `psql -X -v ON_ERROR_STOP=1 -d deedlight_c74_adversarial -f scripts/test-c73-integrated-provider-security.sql` — authentic synthetic fixture through 019–024 and ordered 025, 026, 027, 028, 029 and 030.
2. `psql -X -v ON_ERROR_STOP=1 -d deedlight_c74_adversarial -f supabase/migrations/202611130031_c74_legacy_lifecycle_guard.sql` — compile and apply C74 post-030 correction.
3. `psql -X -v ON_ERROR_STOP=1 -d deedlight_c74_adversarial -f ../evidence-src/evidence/deedlight-c74-postgres-adversarial/vectors/postgres-security.sql` — catalog, ACL/RLS-adjacent privilege assertions, illegitimate event reentry, pending suppression, current final-send authorization and two-key rotation.
4. `bash ../evidence-src/evidence/deedlight-c74-postgres-adversarial/vectors/concurrency.sh` — **two real parallel psql sessions**: duplicate signed ID with immutable metadata, changed-payload conflict quarantine, complaint recipient-lock held against separate final-send transaction, transaction abort/rollback then successful retry. Holds use 3s and 4s to create an actual lock wait.
5. `psql -X -v ON_ERROR_STOP=1 -d deedlight_c74_adversarial -f ../evidence-src/evidence/deedlight-c74-postgres-adversarial/vectors/history-bounce.sql` — inject a legacy cross-table collision **only in a transaction with explicit temporary trigger disable**, verify registry enablement rejects with 55000, ROLLBACK all test mutation; then synthetic transient/permanent bounce, late delivery, complaint escalation, duplicated complaint, provider suppression, and denied Weekly claim for previously Daily-suppressed recipient.

Original C73 fixture verified valid and expired/stale claims, Daily/Weekly claim-kind separation, current consent revocation, identity-bound mark-sent, pending promotion, no callable legacy webhook wrapper, and default stopped delivery. C74 adds adversarial concurrency and lifecycle verification; C73's source tests were not misrepresented as new independent reviews.

**Important test-design corrections retained with evidence:** earlier fixtures used invalid Daily key/timestamp and attempted direct reads under restricted `service_role`, which failed closed as designed; tests now use authentic timezone/midnight keys and separate owner introspection. Concurrent duplicate events use identical immutable `event_at`; a different event timestamp rightfully fails the 027 duplicate-content check. These were synthetic-fixture problems, not reasons to weaken runtime authorization.

### Executed route HTTP and application commands

- `npm ci` (lockfile pinned to C73); `node --test scripts/test-c73-provider-webhook.mjs` (6 SDK-level tests).
- `node ../evidence-src/evidence/deedlight-c74-postgres-adversarial/vectors/route-http.mjs` — 13 **actual localhost HTTP** requests via a minimal synthetic server adapter into the production `POST` route export with the genuine `svix@2.10.0` verifier, raw signed bytes and an intercepted `@supabase/supabase-js` client; NO external RPC/provider requests. Valid signed delivered 200, pending 202, exact replay 200, quarantined 200, DB error 503; altered signed payload/missing signature/expired timestamp/unsupported type/multiple recipients/unclassified bounce all 400; too-large body 413; missing privileged config 503. Verify exact payload SHA sent to mocked narrow RPC; no raw secret or recipient in responses.
- `node scripts/verify-c73-security.mjs`, `node scripts/verify-delivery-consent-gates.mjs`, `node --test scripts/test-delivery-transport.mjs` — PASS.
- `npm audit --audit-level=high`, `npx tsc --noEmit`, `npm run build`, `npx opennextjs-cloudflare build` — all PASS. No skip of high/critical auditing.

**What the HTTP test does *not* prove:** deployed Next.js/Cloudflare HTTP routing, real Supabase PostgREST transaction, actual Resend endpoint delivery, or real signed Resend provider events. HTTP adapter is local and DB client synthetic. No Production smoke or kill-switch drill was performed.

## 4. Durable suppression, recipient HMAC and event identity findings

- Processed `svix_event_id` cannot be inserted into pending after 031; pending/processed/conflict projection entry points require compatible registry states. Old service/browser execute grants, private tables and unauthorized triggers were probed fail-closed.
- Concurrent duplicate requests committed one registry identity and one pending row; a modified signed payload resulted in one quarantined registry identity. Interrupted transaction completely rolled back reservation, followed by successful retry.
- `email.suppressed` received before message association was stored pending and then promoted during mark-sent, retaining `provider_suppressed=true` and `pending_unmatched=true`. No later Daily final-send was allowed.
- Synthetic key rotation kept version 1 as legacy while version 2 became active under the explicit maintenance lock; both normalized fingerprints were computed, suppression on the old fingerprint remained authoritative, and later transport was denied.
- Concurrent complaint committed while second worker waited on recipient state; final-send rejected without changing `transport_started_at`. No external send occurred. Current consent and claim token still required.
- Transient bounce recorded without a permanent hold, permanent bounce suppressed the recipient, out-of-order success did not clear suppression, complaint upgraded to spam complaint, repeated complaint was idempotent, `email.suppressed` applied provider hold, and Weekly dispatch remained denied after earlier Daily lifecycle events.
- Historical collision simulation made same `svix_event_id` appear in processed and pending, then tested rejected registry re-enablement. It was explicitly rolled back and is NOT evidence about unknown live Production historical records.

## 5. Dependencies, residual risk, owner and reviewer blockers

- Full package install resolved `svix@2.10.0`, `wrangler@4.162.0`, `miniflare@5.20261113.0-beta` with `undici@7.30.1`, `@opennextjs/cloudflare@1.20.17`; `@dotenvx/dotenvx@2.38.2` additionally resolves `undici@6.29.1`.
- **9 moderate, 0 high, 0 critical** audit entries. GHSA-3g3m-2fjr-6pw4 (`glob` AbortSignal traversal) and GHSA-g3hv-75wg-m249 (`minimatch` amplification) reach `@opennextjs/cloudflare` and typescript-eslint tooling dependencies. Existing PR #10 version-specific Miniflare override for older beta release does not match current Miniflare; retain audit, inspect actual nested dependencies, do not apply a forced unsafe downgrade or silently accept exposure.
- **OPEN:** Some direct-definer and catalog vectors have tests; no exhaustive attack proof, multi-process provider delivery, actual webhook provider signature corpus, invalid app-supplied fingerprint path, concurrent cross-key event acceptance under active rotation, crash after external HTTP accept, or resolved Production schema history. Current database authorization and provider HTTP remain separate transactions; idempotency keys and retry horizon require further incident testing.
- **BLOCKED:** exclusive source-ownership/fencing lease for historical tasks `0159431db94e4027be73df92a95b1151`, `f57a50fc0c0b40f5a725a30449dd9c13`, interrupted C70 `8106d405aed14e0ebc0c936d4bcc7c1a`, and uncertain Reviewer `24efa58f2e554120aedb6a0f25f76ba8`. Silence/recovery markers and branch inactivity are not clearance. Manager must retrieve authoritative assignment/session states, fence competing writers, and issue a single recorded exclusive lease with exact branch/start SHA and fencing epoch. Do not duplicate the lost Reviewer assignment.
- **BLOCKED:** Production Supabase migration history not reconciled; neither 025–031 is approved as installed Production schema. No normal `supabase db push`.
- **NOT TESTED:** Production delivery, provider failure/bounce/complaint via live Resend, Daily-first Cron multiple cycles, Production kill switch exercise/re-enable, staged Weekly Cron, authenticated Production regression, final Production smoke. No completion tag, Issue #6 closure, PR #10/#11 merge, Cron, Production SQL or deploy occurred.

## 6. Precise independent Reviewer and Cycle 75 handoff

1. Obtain coordinator fencing and Reviewer terminal-state recovery. Review exact diff of only new 031 against immutable C73 tree; ensure newly installed `ENABLE ALWAYS` triggers do not impede 027's legitimate pending->processed transaction under concurrency. No shared code until exclusive lease.
2. Independently fetch and SHA-check the C73 full patch (SHA256 above) and C74 031 patch (SHA256 above). In a disposable PR #10 clone, apply C73 patch, assert `git write-tree=dd4f8593fdb1b3032eb6cddd5f39e50ea9cb7682`, create a LOCAL-ONLY commit to establish baseline, apply C74 031 patch, assert `git write-tree=a9981c2672b316a07904ad7f6b498cd22f206a5b`. Do not push this commit without authority.
3. Reproduce exact PostgreSQL order above on an approved disposable `postgres:16`, with synthetic data only and `ON_ERROR_STOP=1`. Review whether competing INSERT, UPDATE, DELETE, TRUNCATE and SECURITY DEFINER entry paths cannot bypass event ID state. Specifically test historic collisions with real fixture data safely, not only the temporary trigger-disable simulation.
4. Independently exercise both opposing lock orders (provider first and transport first), simultaneous pending promotion, cross-key rotation/recipient canonicalization, recipient mismatch, event replay, provider error ambiguity, exhausted retry horizon and strict kill switch. Confirm service_role cannot directly query private state and every negative fails for the intended SQLSTATE, not an unrelated permissions or syntax error.
5. Run exact-tree application CI incl. route-level signed HTTP, TypeScript, Next, Cloudflare and unsuppressed dependency audit. Require formal independent security review, explicit moderate-risk decision or upstream fixes, Production schema-history reconciliation and staged operator rollout approval **before** touching Production.

**C74 classification:** corrected isolated source and true PG16/adversarial concurrency, webhook HTTP harness, build and high/critical audit **CLOSED—VERIFIED**; moderate findings, broader security acceptance **OPEN**; shared-source exclusive ownership and migration-history reconciliation **BLOCKED**; actual provider/Production benchmark **NOT TESTED**. **MERGE NO-GO / PRODUCTION NO-GO**.

C74 is complete as a **nonproduction verification and isolated corrective handoff**, not a Production release milestone.
