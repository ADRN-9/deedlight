# DeedLight C145 — Dependency and delivery transport remediation

## Scope and source ownership

Repository: ADRN-9/deedlight  
C144 base commit: \`aaa9722b8ed72577bfe5c77d6e69a4b4e12cad12\`  
C144 base tree: \`a2a36ae68df4ba3eee02976e79e95bc36da73f86\`  
C144 validation run: \`44446939382\` (success)  
C145 branch: \`work/deedlight-c145-dependency-transport-20261118\`

C145 was created from the verified C144 branch head. The C144 branch, main and PR #11 were not modified. PR #11 remains open/draft at \`aed588d771dc04fda5e5c18d8611239ac926a513\`; it has 24 changed files, no submitted reviews and no review threads. PR #10 and PR #11 were not merged.

The validated C145 implementation commit is \`386c2da60601920f6981c0f30f134e8f10ee0d02\`, tree \`111b5c7f7ce26cbc3f26d1e86bbb2355b9c9a6fa\`. It is five commits ahead of C144, with no divergence.

## Dependency audit

A fresh \`npm audit --json --audit-level=high\` ran on the exact C145 source in GitHub Actions run \`44455464527\`, attempt 1. The machine-readable report is retained in the validate artifact and is checked by both \`scripts/verify-dependency-audit.mjs\` and the release evidence aggregator.

Result:

| Severity | Count |
|---|---:|
| Critical | 0 |
| High | 0 |
| Moderate | 9 |
| Low | 0 |
| Info | 0 |

The nine moderate advisories affect transitive \`glob\`, \`minimatch\` and \`@typescript-eslint\` packages, including:
- GHSA-3g3m-2fjr-6pw4 — glob AbortSignal cancellation bypass.
- GHSA-g3hv-75wg-m249 — minimatch globparts amplification.

The audit reports a proposed OpenNext remediation that installs \`@opennextjs/cloudflare@0.3.0\`, a breaking major downgrade from the current 1.x package line. C145 deliberately does not apply that forced downgrade. No package.json or package-lock.json changes were necessary to remediate high/critical advisories because none were reported. The moderate advisories remain explicitly disclosed for a separately reviewed dependency-upgrade task; this is not a claim of zero advisories.

The previous C144 audit also reported nine moderate and zero high/critical advisories. C145 adds retained JSON evidence and a machine-verifiable gate requiring the report and zero high/critical counts.

## Expired-lease positive-path fixture correction

The C76 cross-kind concurrency fixture previously set \`claim_expires_at\` using \`clock_timestamp() - interval '1 second'\`, then attempted reclaim with \`claim_delivery_jobs(..., now(), ...)\`. Those expressions use different clocks: transaction-stable \`now()\` may predate the wall-clock expiry value, making the expired lease not yet expired relative to the supplied claim timestamp. The positive reclaim test was therefore timing-dependent.

C145 now:
1. Uses \`now() - interval '1 second'\` to expire the fixture against the same transaction-stable timestamp passed to the claim RPC.
2. Proves a Weekly worker cannot reclaim the Daily lease.
3. Proves the Daily worker rotates the claim token without changing the logical delivery key.
4. Verifies the reclaimed row is a live second-attempt lease.
5. Positively authorizes the fresh token with \`authorize_delivery_job\`.
6. Continues to reject the old token at the recipient-bound transport gate.
7. Requires the new \`reclaimed_lease_positive_path\` marker in the release security aggregator.

The disposable PostgreSQL evidence in artifact \`release-evidence-release_consent_races-run-44455464527-attempt-1\` contains:
\`"reclaimed_lease_positive_path": "pass"\`,
\`"expired_lease_kind_isolation": "pass"\` and
\`"stale_claim_token_rejected": "pass"\`.

## Delivery transport and provider invariants verified

No production transport code was changed because exact-source inspection and the C145 CI evidence show these controls are already present:

- \`processClaimedDelivery\` authorizes before recipient resolution and re-authorizes after resolution immediately before \`beginTransport\`.
- The database recipient-bound final-send RPC locks consent/profile/Auth identity rows and checks the current consent, suspension, claim token and \`clock_timestamp()\` lease immediately before returning a transport authorization.
- Resend uses stable \`deedlight/{kind}/{jobId}\` idempotency keys.
- Provider event IDs are unique. Exact event replay is returned as duplicate; reuse of an event ID with different authenticated content is rejected.
- Claim retries are bounded to five attempts; the fifth expired attempt becomes terminal \`retry_exhausted\`.
- Ambiguous provider outcomes are not blindly resent after the 23-hour provider idempotency safety window.

Exact-run evidence:
- \`release_consent_races\`: C76/C77 two-session claim, lease, consent-revocation and provider-event races.
- \`release_provider_pg16\`: disposable PostgreSQL 16 provider classification, identity-conflict, suppression and post-033 checks.
- \`release_webhook_http\`: signed webhook verification, synthetic HTTP routing, duplicate event identity and bounce/complaint suppression.
- \`validate\`: transport behavior tests, TypeScript, Next.js build, Cloudflare package and dependency audit.

The webhook evidence includes exact duplicate HTTP delivery remaining one provider identity, permanent bounce blocking Daily and Weekly sends, complaint escalation to durable spam hold, and suppression removal not releasing an existing complaint hold. All provider tests use synthetic identities and no real provider calls.

## C145 CI acceptance

GitHub Actions run \`44455464527\`, attempt 1, validated the exact implementation commit and tree above.

All 12 jobs completed successfully, including the current-attempt \`release_security_gate\`. The aggregate reported:

\`RELEASE_SECURITY_GATE_PASS 11/11 current-attempt GitHub jobs and artifacts; 64/64 SQL, 19/19 application, provider/webhook/race contracts verified\`.

Key artifact IDs and SHA-256 digests:
- Validate / audit: \`14497631743\` — \`c515efb46a749d7ba121956dc776b767d7fff19dac52261f1febbc211587fc82\`.
- Consent and lease races: \`14497471932\` — \`e06b637c33201146640e02510417264794403c9d34074070dfa5e4305b136626\`.
- Provider PostgreSQL: \`14497761335\` — \`cb695c5025ece113212807c2ef1e2ab7aab63e27b207875d08f0e93cb4068a44\`.
- Webhook HTTP: \`14497885853\` — \`55f90a99bad27f8f9100dec1161607acf508058d63cde142fdc983bc37c41eaf\`.

The first C145 run failed at the static source assertion because it still expected the legacy plain-text npm audit command. The assertion was corrected to accept the new machine-readable command while still requiring a high-severity audit. That interrupted run was not treated as acceptance; run \`44455464527\` is the successful exact-head run.

## Changed files

- \`.github/workflows/pr-validation.yml\` — retain machine-readable npm audit JSON and summary in the validate artifact.
- \`scripts/verify-dependency-audit.mjs\` — fail closed on malformed reports or any high/critical count.
- \`scripts/verify-release-security-gate.mjs\` — require and validate the audit evidence; require the lease positive-path marker.
- \`scripts/test-c76-cross-kind-concurrency.sh\` — deterministic expired-lease clock and fresh-token positive authorization.
- \`scripts/verify-delivery-consent-gates.mjs\` — update the static workflow assertion for JSON audit mode.

No dependency manifest, lockfile, application transport implementation or database migration changed.

## Blockers and release disposition

- Nine moderate dependency advisories remain; no high/critical advisories are present. A compatible remediation for the OpenNext/glob advisory needs a deliberate upgrade path rather than npm's suggested breaking downgrade.
- C144 migration 034 / duplicate \`202607260007\` reconciliation remains a separate release blocker.
- Production Supabase schema/history, PostgREST behavior, scheduler operation, provider delivery, kill-switch exercise and Production smoke remain unverified by this C145 task.
- No Production credentials were used. No Production migration, \`supabase db push\`, deployment, scheduler activation or external provider send was performed.

Production remains NO-GO.

## Recommended C146

Address the moderate dependency advisories in a dedicated compatibility change: inspect the OpenNext package's supported glob range, upgrade \`@typescript-eslint\` within compatible semver bounds where possible, avoid forced major downgrades, and run the full exact-head TypeScript, Next.js, Cloudflare and security gate. In parallel, continue the separately controlled Production migration-history reconciliation; do not combine it with unapproved Production mutation.
