# DeedLight Cycle 72 — Isolated PR #10 + Cycle 70 integration rehearsal

**Assignment:** `DL-C72-PR10-C70-CI-INTEGRATION-D01` / task `62bf07c1336e488f884e890cb75c4b57`  
**Date:** 2026-11-14 (UTC)  
**Source ownership:** **BLOCKED — NO EXCLUSIVE LEASE PROVEN**. No shared application source was modified or pushed.  
**Release:** **MERGE NO-GO / PRODUCTION NO-GO**.

## 1. Exact source and immutable result

- Repository: `ADRN-9/deedlight`; shared `main` `ce82b3fdf1a73510de70e3729a487d4ae00e66e3`.
- PR #10 application baseline: `c983e2ed8b93c935139c935343261570ecea6978`, still a draft unmerged PR.
- Cycle 70 successful CI candidate: `60301d44176186b33a812a972016751629fd792f`, historical exact-head run [43619104996](https://github.com/ADRN-9/deedlight/actions/runs/43619104996).
- Corrected Cycle 70 SQL blob: `e92c138cedef5ad7d4b2411e7c00cab7f225c5e8`; PR #10 old SQL blob: `5c6442a4b7ac0f8b115113d5cdaa647c8ecad3d1`.
- PR #11 audit source: `aed588d771dc04fda5e5c18d8611239ac926a513`, separate draft unmerged PR.
- Independently verified Cycle 71 recovery ledger: `df549c60b3ae78367465183e90b755f6c4fce884`.
- Result of isolated ephemeral PR #10 checkout, source `git write-tree`: **`d0a91a2d623b248d82588736c394fe252e0b7927`**. No application integration commit exists and no exclusive writer was granted.
- Full reproducible `git diff --cached --binary` patch: `results/C72_PR10_C70_INTEGRATION.patch`, SHA-256 **`f1b77f2d339a939e996be7806d59f6885f7b2fd837130f8cc23436d26e6605ad`**.
- Exactly THREE affected application paths: `scripts/test-gentle-delivery-transport.sql`, `package.json`, `package-lock.json`. The ephemeral script refuses any other changed file. It independently replays the patch onto a second PR #10 detached worktree, verifies `git apply --check` and compares the `git write-tree` hash byte-for-byte.

## 2. Actual executed CI and PostgreSQL results

**Authoritative final rehearsal:** [GitHub Actions 43622868815](https://github.com/ADRN-9/deedlight/actions/runs/43622868815) against evidence-only workflow input commit `bd454685276d55c2df0055bb8632ad3d7c5f80dd`. Both jobs **SUCCESS**: `rehearsal` and `publish_evidence_only`. The run was an isolated checkout of PR #10 plus patch, **not exact-head PR Validation on an application integration commit**.

An earlier [run 43622516760](https://github.com/ADRN-9/deedlight/actions/runs/43622516760) achieved the **same application and PostgreSQL PASS** but had a separate **publication failure**: `git diff --cached --check` applied to raw PostgreSQL and build logs with intentional terminal whitespace. That was fixed only for evidence publication. The actual source diff still passes `git diff --cached --check` in the ephemeral app checkout and independently applies cleanly. The final run reproduces the same patch SHA and source tree SHA as the earlier run.

**Real tests performed (synthetic-only PostgreSQL 16.16, Node 24 in GitHub Actions):**

| Category | Executed checks | Result |
|---|---|---|
| Static security | Sprint 12.1, Sprint 12.2, delivery reliability, gentle transport, PR #10 consent/migration guards, auth pgcrypto | PASS |
| Application delivery | `node --test scripts/test-delivery-transport.mjs` | PASS |
| Dependencies | `npm install --package-lock-only --save-exact --save-dev wrangler@4.162.0 --ignore-scripts`; `npm ci`; unsuppressed `npm audit --audit-level=high` | PASS |
| TypeScript | `npx tsc --noEmit` | PASS |
| Next | `npm run build` | PASS |
| Cloudflare | `npx opennextjs-cloudflare build` | PASS |
| PostgreSQL Sprint 12.2 | `scripts/test-sprint12-2-delivery.sql` in its own disposable database | PASS |
| PostgreSQL reliability | `scripts/test-delivery-reliability-terminals.sql` in its own disposable database | PASS |
| PostgreSQL gentle transport, consent, 023/024 | `scripts/test-delivery-consent-gates.sql` in its own disposable database | PASS |
| Concurrent claims, consent, capacity | `bash scripts/test-delivery-consent-concurrency.sh` | PASS |
| PostgreSQL auth | `scripts/test-auth-pgcrypto-schema-qualification.sql` | PASS |
| PostgreSQL migration-order positive/negative | `bash scripts/test-delivery-migration-order.sh` | PASS |
| PR #11 separate immutable tooling | manifest SHA-256 verification; two static checkers; 20 Python unit tests | PASS |
| Patch integrity | `git diff --check`, `git apply --check`, replay, exact Git tree hash | PASS |

All CI tests run with `DELIVERY_ENABLED=false` and non-Production Next/Supabase public placeholders. PostgreSQL service is disposable; no Production credentials, provider requests, cron or database mutation were made.

**Negative security regressions executed:** genuine expired claims and stale token 42501 denial on authorization/transport, current consent revocation after claim, suspension, recipient changed after early authorization, expired lease while waiting for consent lock, concurrent revocation/transport order, 5,001 Weekly overflow denial with atomic rollback and 5,000 idempotent capacity, migration 024 refusal absent authentic 023/when 023 source drifted, correct 023->024 upgrade, browser RPC denial, stable transport start. These are evidenced by actual SQL and concurrency script logs under `results/`.

**Scope not proved:** migration 025's strict Daily/Weekly **claim** isolation, 026–028 event/suppression/keyring behavior, C61 global registry, Cycle 69 bypass containment, authenticated webhook, actual provider idempotency, Production kill switch and staged cron. Those are NOT TESTED, not inferred from old 021/024 fixtures.

## 3. Dependency reconciliation and security inventory

PR #10 already pins `next=16.4.6`, `zod=4.6.7`, `@opennextjs/cloudflare=1.20.17` and protects Supabase link/push with shell guard scripts. C70's manifest cannot be copied wholesale, since it would undo these guards and its lockfile is for another root manifest. Instead, the rehearsal retains PR #10's manifest verbatim except `wrangler: latest` becomes `wrangler: 4.162.0`; npm regenerates the corresponding lockfile in the disposable checkout. The preserved PR #10 `source-map-js` and version-scoped `miniflare` overrides are required by its existing executable security assertion; no new unreviewed overrides or forced downgrades are introduced. Both `npm ci` and the real Next/Cloudflare builds pass.

- Final installed packages include Next 16.4.6, Zod 4.6.7, Wrangler 4.162.0, OpenNext 1.20.17, Miniflare 5.20261113.0-beta and Sharp 0.35.5.
- Final `npm audit` result: **0 low, 9 moderate, 0 high, 0 critical**. This is **NOT a clean zero-finding audit**.
- GHSA-3g3m-2fjr-6pw4: moderate `glob@13.0.7` cancellation/traversal issue; impacts `@opennextjs/cloudflare` through dependency chain.
- GHSA-g3hv-75wg-m249: moderate `minimatch@10.2.5` amplification/DoS issue; impacts `@typescript-eslint/typescript-estree`, parser, ESLint plugin/utilities, and their dependents.
- The nine are affected npm package entries, **two original advisory families**, not nine different GHSA IDs. Both exposures are largely development/tooling paths, but untrusted input reachability and whether bundled at runtime were NOT TESTED. The non-breaking upgrade path is **OPEN / UPSTREAM DEPENDENCY BLOCKER**; accepting these temporarily requires independent recorded risk authorization, not silence or `--force`.
- **Follow-up needed:** PR #10's existing override for `miniflare@5.20261110.2-beta -> undici@7.30.2` is **version-specific and currently inert** for the new `miniflare@5.20261113.0-beta`. The actual nested `node_modules/miniflare/node_modules/undici` resolves `7.30.1` and passed the live high/critical audit. The current PR #10 static verifier checks override text presence, not effective resolved dependency. Cycle 73 must add a resolved-lockfile security assertion and revisit the obsolete override with reviewer approval. Never claim the old override protects a different Miniflare version.

## 4. PR #11 audit compatibility

PR #11's metadata-only SQL audits PostgreSQL catalogs under read-only transactions and does not inspect private member/provider data; its offline audit package manifest and 20 static unit tests pass unchanged against the pinned PR #11 commit. The separate PR #11 PostgreSQL ten-case workflow previously passed at its own source in run [43436800968](https://github.com/ADRN-9/deedlight/actions/runs/43436800968); that run **did not** exercise this new PR #10+C70 rehearsal.

Do **not** blindly copy PR #11's runner into the integrated app. Its disposable database runner deliberately requires an exact source SHA `c983e2ed8b93c935139c935343261570ecea6978` and a specific audit branch name; changing them without reviewing its entire hash manifest and 82 invariants would weaken its trust assumptions. Metadata-only audit adoption requires a dedicated reviewed update. Full ten-case PR #11 PostgreSQL matrix against this C72 tree is **NOT TESTED**.

## 5. Migration compatibility with authentic 025–028

No migrations were changed in this patch. PR #10's 023/024 canonical source hashes were asserted before test, and their positive/negative PostgreSQL ordering behaviors passed. The transport fixture runs intentionally against 021 **before** migration 023/024 upgrades, so its two-argument RPC probes do not reintroduce a retired overload.

- Authentic proposal 025 (SHA256 `93f990990b2112e1ee4f049e5d9b9495ffd4d17e43159a9bf6146953d1ae9fc9`) requires changing the application gateway from unscoped `claim_delivery_jobs(timestamptz,integer)` to the kind-scoped three-argument RPC, and proving Daily/Weekly isolation with new negative fixtures.
- 026 (SHA256 `d1f2812f343c799e42583f57265bc967cbeab98ca5400d4206e5bddc559be137`) adds submissions, event records, suppression and recipient-sent path.
- 027 (SHA256 `3d30d188b867ab45e70befb5bbc2f69c5c94e594d29efb5d2758ecc7c7e1b81e`) adds pending events and suppression serialization.
- 028 (SHA256 `d0e85b338a6b96fea5fcc8121369cd2dc20faab0cc8183ee01139a0015c0d391`) adds authoritative recipient-key binding, transport intents and conflict handling.
- These four are authentic **isolated proposals** from evidence commit `f4bffa2d24f5241012b99f673eaaa39ac1dc2907`, not approved integrated migrations, and were not executed in C72. C61 provider-event registry and C69 emergency hard-stop are separate unresolved security tasks and must **not** be incorporated as a side effect of this CI-only rehearsal.

## 6. Provenance, publication and reproduction

Source input files under `inputs/` are immutable C70 SQL and the exact CI rehearsal script. Generated results are under `results/`, with 44 archived files: patch, manifest, regenerated lockfile, 43-entry `SHA256SUMS.txt`, PostgreSQL and app checks, original audit JSON, raw test logs, final tree and source identities. The production-like job executed in ephemeral checked-out directories and never committed/pushed application code.

- Passing final workflow: [43622868815](https://github.com/ADRN-9/deedlight/actions/runs/43622868815).
- Uploaded final GitHub artifact ZIP SHA256: `af5d3bae25c446f4955532aab9cd280ee21e0cc1fe5c1bcbc1df2dfac4c86091`; independently downloaded and verified **43/43 manifest entries**.
- Published patch Git blob: `4da8a55f402bcc2fda25dae3f63fef904294a515`, sha256 `f1b77f2d339a939e996be7806d59f6885f7b2fd837130f8cc23436d26e6605ad`.
- Published manifest `package.json` Git blob: `c23b175282856e2e54ffafd21e548bd80118f928`; generated `package-lock.json` blob `5ed3a66134cac5e5222bfe6f4da0abbd5209691e`. These were independently matched to the first CI artifact.
- Result source tree `d0a91a2d623b248d82588736c394fe252e0b7927` is **not a Git commit**.
- Paths and SHA256 entries are relative to `results/`.

For review (in an authorized isolated workspace, NEVER Production), check out PR #10 **exactly**, fetch the evidence patch from the immutable evidence commit, then:

```bash
git checkout --detach c983e2ed8b93c935139c935343261570ecea6978
git apply --check C72_PR10_C70_INTEGRATION.patch
git apply C72_PR10_C70_INTEGRATION.patch
git diff --check
git add -- package.json package-lock.json scripts/test-gentle-delivery-transport.sql
test "$(git write-tree)" = "d0a91a2d623b248d82588736c394fe252e0b7927"
npm ci
npm audit --audit-level=high
node scripts/verify-delivery-consent-gates.mjs
node --test scripts/test-delivery-transport.mjs
npx tsc --noEmit
npm run build
npx opennextjs-cloudflare build
```

For actual PostgreSQL execution, use only the separate approved GitHub-hosted disposable `postgres:16` job: create one synthetic database per listed `results/test-commands.log` fixture, run with `psql -X -v ON_ERROR_STOP=1` and the pinned source. Never point fixture scripts or `supabase db push` to Production. Full instructions and exact commands are in the archived `inputs/rehearse.sh` and `WORKFLOW_REFERENCE.yml`.

## 7. Source ownership and exact Cycle 73 dependency

**BLOCKED:** no authoritative coordinator clearance/fencing is accessible for earlier Developer writers `0159431db94e4027be73df92a95b1151`, `f57a50fc0c0b40f5a725a30449dd9c13`, or interrupted C70 task `8106d405aed14e0ebc0c936d4bcc7c1a`. Reviewer heartbeat incident `24efa58f2e554120aedb6a0f25f76ba8` remains unverified. Recovery markers and quiet GitHub branches are not leases.

**Exact action:** Level 2 coordinator must retrieve authoritative active-worker state, fence/revoke competing source writers, separately establish Reviewer terminal status, and issue one recorded exclusive integration lease naming Developer, repository, PR #10 exact starting SHA, new integration branch namespace, issuance/expiration, fencing epoch and reviewer gate. Until then no shared-source commit.

**Cycle 73 after clearance:** create one new approved integration branch from `c983e2ed8b93c935139c935343261570ecea6978`, apply and verify exactly the C72 patch and `d0a91a2d623b248d82588736c394fe252e0b7927` tree, obtain true exact-head CI on the integration commit, then stage authentic 025–028 **one by one** with kind-scoped gateway and independent PostgreSQL negative-security tests. Reconcile C61 global event identity and C69 stop-only bypass findings in a separately reviewed functional webhook/suppression track. Update PR #11's source/branch guards only through reviewed audit changes. Require Reviewer approval, dependency-risk disposition, CI, Production migration-history reconciliation and operator-governed staged rollout before any Production mutation.

**Final classification:** C72 isolated patch, source tree, PostgreSQL behavior, security, npm audit gate, TypeScript, Next and Cloudflare **CLOSED—VERIFIED (isolated)**; nine moderate findings and stale override verifier **OPEN**; exclusive source ownership and integrated source commit **BLOCKED**; post-024 025–028 webhook/suppression/identity behavior, full new PR11 PG matrix and Production rollout **NOT TESTED**. **MERGE NO-GO / PRODUCTION NO-GO**.

No PR merges, no shared application-source writes, no Production migrations/history, credentials, Worker deploy, Cron, email send, completion tag, or Issue #6 closure. 
