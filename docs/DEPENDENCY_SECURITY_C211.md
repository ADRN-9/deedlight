# C211 — Dependency security remediation

**Repository:** `ADRN-9/deedlight`  
**Baseline:** `main` at `ce82b3fdf1a73510de70e3729a487d4ae00e66e3`  
**Audit date:** 2026-11-21  
**PR:** [#16 — Remediate dependency audit findings](https://github.com/ADRN-9/deedlight/pull/16)

## Executive result

The baseline full dependency audit reported **21 vulnerable package entries: 2 critical, 7 high, 12 moderate**. The baseline production-only graph reported **4 entries: 1 critical and 3 high**.

The targeted remediation now reports:

| Audit | Baseline | Remediated |
|---|---:|---:|
| Full dependency graph — critical | 2 | 0 |
| Full dependency graph — high | 7 | 0 |
| Full dependency graph — moderate | 12 | 5 |
| Production-only graph — critical/high/moderate | 4 | 0 |

The full audit remains non-zero because five moderate build-tooling package entries remain. They are not suppressed or described as fixed. The existing CI gate `npm audit --audit-level=high` is preserved and passes; a production-only gate, `npm audit --omit=dev --audit-level=low`, also passes.

## Audit evidence and reproducibility

- Baseline full audit and dependency-path capture: [GitHub Actions run 44910232228](https://github.com/ADRN-9/deedlight/actions/runs/44910232228), artifact `c211-complete-dependency-audit` (ID `14708834245`).
- Final targeted lockfile generation, `npm ci`, full JSON audit, production-only JSON audit and both audit gates: [GitHub Actions run 44911709818](https://github.com/ADRN-9/deedlight/actions/runs/44911709818), artifact `c211-final-dependency-evidence` (ID `14710082857`).
- The baseline evidence includes `npm audit --json`, `npm audit --omit=dev --json`, `npm ls --all --json`, and `npm explain --json` paths for each vulnerable package entry.
- The final evidence includes the resulting `package.json`, `package-lock.json`, full audit JSON and production-only audit JSON.

Both baseline and final lockfiles use lockfile version 3. Final `npm ci` completed successfully. The final audit counts are 5 moderate, 0 high, 0 critical; the production-only audit counts are all zero.

## Critical and high findings

The npm counts are package-entry severity counts. Next.js aggregates multiple advisories into one critical package entry; its record also contains high-severity advisories.

| Package | Baseline version | Role and dependency path | Severity / advisory | Affected range | Selected fix |
|---|---:|---|---|---|---:|
| `next` | 16.3.6 | Direct production dependency | Critical: GHSA-2464-fhr4-w9xw and GHSA-673q-mjm6-r5xr. Also high: GHSA-cjq9-62q9-8jv4 and GHSA-p3m5-59mp-jv5r. | Package range 16.0.0–16.4.4; the two critical advisories affect versions through 16.4.0. | 16.4.6 |
| `proxy-addr` | 2.0.7 | Transitive dev dependency: `express@5.2.1` → `@opennextjs/aws@4.1.0` → `@opennextjs/cloudflare@1.20.2`. | Critical: GHSA-jqcg-44mw-7w3h (IPv4-mapped IPv6 trust-subnet spoofing). | >=1.1.0 <2.0.8 | 2.0.8 |
| `body-parser` | 2.3.0 | Transitive dev dependency through the same Express/OpenNext path. | High: GHSA-27r3-jxmh-p828 (DoS with trailing bytes after a compressed request body). | >=2.0.0 <2.4.0 | 2.4.0 |
| `miniflare` | 5.20260921.0-alpha | Transitive dev dependency: `wrangler@4.137.0` → `miniflare`; also reached through Wrangler's OpenNext peer path. | High aggregate finding inherited through vulnerable `sharp` and `undici`. | 4.20250508.3–5.20261006.0-alpha | 5.20261119.0-beta through Wrangler 4.166.0 |
| `sharp` | 0.35.4 | Transitive dependency of Next.js and Miniflare; present in the production-only graph. | High: GHSA-wq5f-xc86-pv6w (librsvg dependency CVE-2026-96889). | <0.35.5 | 0.35.5 |
| `source-map-js` | 1.2.1 | Transitive dependency through `postcss`/Next.js and Tailwind PostCSS; present in the production-only graph. | High: GHSA-68fv-2mgg-jv7q (event-loop DoS through indexed source-map offsets). | >=1.0.0 <1.2.2 | 1.2.4 |
| `undici` | 7.29.0 | Transitive dev dependency: `miniflare` → `wrangler`. | High aggregate finding. High advisories include GHSA-rfgv-xxqx-mfg5, GHSA-w293-vg96-wgc3, GHSA-xjj6-f33q-929c, GHSA-4w7w-5xrc-9h26, GHSA-2m5v-pch6-74hx and GHSA-qrxm-fqhp-jwvm. | Individual advisories affect versions below 7.29.1 or 7.30.1. | 7.30.2 |
| `wrangler` | 4.137.0 | Direct dev dependency; inherits the Miniflare finding. | High aggregate finding. | 4.16.0–4.148.0 | 4.166.0 |
| `zod` | 4.4.3 | Direct production dependency. | High: GHSA-mrhx-c7xc-m3w5 (memory exhaustion with oversized constrained collections). | <4.6.6 | 4.6.7 |

### Dependency-path notes

- The two critical package entries are direct Next.js and transitive proxy-addr.
- The seven high package entries are body-parser, miniflare, sharp, source-map-js, undici, wrangler and zod.
- The Next.js package entry also contains two high advisories; npm reports the package at its highest severity, critical.
- `sharp` and `source-map-js` were present in the baseline production-only graph. The final production-only audit has zero findings.
- `miniflare` is updated as part of Wrangler's published dependency tree. Wrangler 4.166.0 resolves Miniflare 5.20261119.0-beta, sharp 0.35.5 and undici 7.30.2. No direct Miniflare override was introduced.

## Moderate baseline findings and remaining risk

The other baseline moderate entries were also identified. The compatible TypeScript-ESLint and qs updates are included in the final lockfile; five moderate package entries remain:

| Remaining package entry | Baseline version / path | Advisory and affected range | Available fix and disposition |
|---|---|---|---|
| `@node-minify/core` | 8.0.6, through `@opennextjs/aws@4.1.0` → `@opennextjs/cloudflare@1.20.2` | Inherited glob advisory GHSA-3g3m-2fjr-6pw4; affected 8.0.6 or 9.0.1–9.0.2. | 10.5.0 is available through OpenNext AWS 4.2.0, but is outside the current parent's `^8.0.6` range. Not force-overridden. |
| `@opennextjs/aws` | 4.1.0, transitive from OpenNext Cloudflare. | Moderate range <=4.1.15, inherited through `@node-minify/core`. | 4.2.0 resolves this package entry, but requires the newer adapter dependency tree. The adapter update was excluded from this minimal high/critical remediation. |
| `@opennextjs/cloudflare` | 1.20.2, direct dev dependency. | Inherited through OpenNext AWS and glob. | npm's automatic fix proposes 0.3.0, a breaking major downgrade. The current 1.20.2 adapter is pinned rather than downgraded. |
| `glob` | 9.3.5 under node-minify and 12.0.0 under OpenNext Cloudflare. | GHSA-3g3m-2fjr-6pw4; >=9.0.0 <=14.0.1. | Patched 14.0.2 is outside the current parent ranges. No unsupported major override was added. |
| `minimatch` | 8.0.7 under glob 9 and 10.2.5 under glob 12. | GHSA-g3hv-75wg-m249; >=7.0.0 <11.0.1. | Patched 11.0.1 is outside the current parent ranges. No unsupported major override was added. |

These five entries are development/build-tooling dependencies, not findings in the final production-only graph. The residual risk is build-time denial of service if affected glob/minimatch behavior is exercised with attacker-controlled patterns or directory trees. This is not represented as zero risk; revisit when the supported OpenNext dependency path permits patched glob >=14.0.2 and minimatch >=11.0.1 without a breaking adapter downgrade.

Other moderate baseline packages fixed in the targeted lockfile include:

- `@typescript-eslint/eslint-plugin`, `parser`, `type-utils`, `typescript-estree`, `utils` and `typescript-eslint`: 8.65.0 → 8.73.0 (affected through 8.72.2).
- `qs`: 6.16.0 → 6.17.1 (affected through 6.16.0; patched from 6.16.1).

## Implemented changes

Direct manifest pins:

- `next`: 16.3.6 → 16.4.6.
- `zod`: 4.4.3 → 4.6.7.
- `wrangler`: 4.137.0 → 4.166.0.
- `eslint-config-next`: 16.2.11 → 16.4.6, aligned with Next.js 16.4.6.
- `@opennextjs/cloudflare` is pinned at its existing locked version 1.20.2 to prevent an unreviewed `latest` tag drift; it was not upgraded or downgraded.

Compatible transitive updates:

- `body-parser` 2.4.0; `proxy-addr` 2.0.8; `qs` 6.17.1.
- `sharp` 0.35.5; `source-map-js` 1.2.4; `undici` 7.30.2.
- `miniflare` 5.20261119.0-beta and `workerd` 1.20261119.1 through Wrangler.
- TypeScript-ESLint packages 8.73.0.

The final targeted lockfile changes 117 package entries against the baseline (797 baseline package entries; 812 final entries). The changes are concentrated in Next/SWC, Wrangler/Miniflare/Workerd, sharp platform binaries and the affected compatible transitive packages. This is materially smaller than the earlier broad candidate that refreshed 300+ package entries.

No `npm audit fix --force`, unsupported major-version override, advisory suppression, audit-threshold weakening, or application-code change was used. No application regression test was needed for behavior changes because the implementation changes only dependencies; the existing CI TypeScript, Next.js build, Cloudflare packaging, security and database behavior jobs provide compatibility regression coverage.

## CI and operational scope

- The existing full-graph `npm audit --audit-level=high` gate is unchanged.
- A separate `npm audit --omit=dev --audit-level=low` gate was added.
- Final dependency evidence run 44911709818 verifies `npm ci`, zero high/critical findings and zero production-only findings.
- The final PR head must also pass the repository's existing TypeScript, Next.js production build, Cloudflare packaging, security assertions and all database behavior jobs; exact-head CI evidence is linked from PR #16.
- PR #10 outbound-delivery work, PR #13 legacy Production migration workflow retirement, PR #14 database fixture correction and PR #15 Production exclusion/empty Non-Production allowlist are preserved. PR #16 remains stacked on PR #14.
- The temporary audit workflow is removed after evidence capture.
- No PR was approved or merged. No Production migrations, deployments, resets, Cron activation, provider operations, credential changes or secret modifications were performed.

Production remains **NO-GO**.
