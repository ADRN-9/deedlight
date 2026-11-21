# C213 — Dependency, lint, and navigation remediation

Status: implementation and CI evidence captured. Production remains NO-GO. This document extends the C211 dependency audit record without rewriting its historical baseline.

## Changes

- Replaced the removed Next.js `next lint` command with `eslint .`.
- Added `eslint.config.mjs` using `eslint-config-next/core-web-vitals` and `eslint-config-next/typescript`, plus explicit generated/build output ignores.
- Added `npm run lint` to pull-request validation. No additional lint package was introduced; the lockfile already resolves ESLint 9.39.5 and `eslint-config-next` 16.4.6.
- Corrected lint findings rather than disabling recommended rule sets: typed admin count queries; removed unused imports/variables; replaced obsolete generated-worker `@ts-ignore` directives with described `@ts-expect-error`; removed effect-based prop synchronization by remounting stateful controls on server-prop changes; read the browser timezone with `useSyncExternalStore`; documented the request-time invitation-expiry check with a one-line rule exception.
- Centralized root navigation identity in `getRootNavigationContext`. `PublicHeader` receives the verified user and `AdminFloatingLink` receives only the derived admin-visibility boolean. The root layout performs one `auth.getUser()` and one profile lookup instead of separate header/admin lookups.
- The navigation helper fails closed: missing Supabase configuration or failed authentication produces guest navigation; a failed profile lookup preserves the authenticated header but hides the Admin link. Admin route authorization remains in the existing server-side guards; this UI context does not grant access.
- The root layout calls `connection()` before reading the request cookie context. This makes the existing request-time rendering requirement explicit without setting a global `fetchCache` or weakening session checks.

## OpenNext Cloudflare 1.20.18 review

Candidate evidence: [C213 OpenNext adoption run 44916860601](https://github.com/ADRN-9/deedlight/actions/runs/44916860601), artifact `c213-open-next-inspection` (14711958480).

The candidate lockfile was compared against exact C211 commit `715a1a8f755e5f393e53130f66ab4266351335e7`:

| Package-lock measure | C211 | Candidate |
|---|---:|---:|
| Package records (including root) | 812 | 764 |
| Added package records | — | 15 |
| Removed package records | — | 63 |
| Changed package records | — | 135 |
| Unchanged package records | — | 613 |

The root lockfile metadata record also changed. Excluding that root record, exactly 213 package records were affected. All 213 are development dependencies; no production dependency package version changed.

The reviewed changes are confined to the OpenNext/build-tooling graph, including OpenNext AWS, AWS SDK/Smithy, Node Minify, esbuild platform binaries, ast-grep platform binaries, dotenvx, and related Express packages. Notable updates include:

- `@opennextjs/cloudflare` 1.20.2 → 1.20.18
- `@opennextjs/aws` 4.1.0 → 4.2.0
- `@node-minify/core` 8.0.6 → 10.5.0
- `esbuild` 0.25.4 → 0.28.2
- `glob` 12.0.0 → 13.0.7
- `minimatch` 10.2.5 → 10.2.6

Adapter peer requirements are Next `>=15.5.29 <16 || >=16.4.5` and Wrangler `^4.148.0`. Deedlight resolves Next 16.4.6 and Wrangler 4.166.0. The candidate clean install, TypeScript check, Next production build, and Cloudflare packaging all passed.

### Remaining audit findings

The candidate full audit reports **3 moderate, 0 high, 0 critical**. The production-only audit reports **0 vulnerabilities**. The unchanged audit gates passed: `npm audit --audit-level=high` and `npm audit --omit=dev --audit-level=low`.

The remaining findings are the adapter itself and its transitive `glob` / `minimatch` path:

- GHSA-3g3m-2fjr-6pw4 — glob AbortSignal cancellation bypass.
- GHSA-g3hv-75wg-m249 — minimatch globparts amplification denial of service.

npm only offers `@opennextjs/cloudflare@0.3.0` as a fix, which is a breaking major downgrade. C213 does not apply forced overrides, suppress advisories, or weaken audit thresholds. The residual findings are development/build-time dependencies; they are not represented as fixed.

## Floating direct dependencies

Twelve direct declarations still use `latest`. Their current lock-resolved versions are:

| Package | Locked version |
|---|---:|
| `@supabase/ssr` | 0.12.3 |
| `@supabase/supabase-js` | 2.110.8 |
| `lucide-react` | 1.25.0 |
| `react` / `react-dom` | 19.2.8 |
| `@tailwindcss/postcss` / `tailwindcss` | 4.3.3 |
| `@types/node` | 26.1.1 |
| `@types/react` | 19.2.17 |
| `@types/react-dom` | 19.2.3 |
| `eslint` | 9.39.5 |
| `typescript` | 6.0.3 |

`npm ci` remains reproducible against the committed lockfile, but future lockfile regeneration can float these declarations. Recommended follow-up: replace each `latest` with its reviewed exact lock-resolved version, regenerate `package-lock.json` atomically, and make one coherent dependency PR. Keep Next and `eslint-config-next` aligned, React and React DOM aligned, and Tailwind/PostCSS aligned. Use scheduled dependency-update PRs with full audit, lint, build, and database CI; do not bulk-upgrade unrelated groups.

## Build warnings and rendering

The C213 build emitted no `PublicHeader auth check failed` or `Dynamic server usage` warnings. The route manifest remains request-time rendered for the application routes (the manifest file remains static), consistent with the existing cookie-dependent navigation requirement. The navigation refactor removes the duplicate auth lookup; it does not make private pages public or change server authorization.

Other non-blocking toolchain warnings remain:

- Node reports `MODULE_TYPELESS_PACKAGE_JSON` for `lib/delivery/config.ts`.
- Transitive tooling reports deprecated `punycode` and legacy `url.parse()` use. The latter is a Node deprecation/security warning, not an npm audit finding; trace and upgrade the upstream dependency rather than applying an unreviewed override.
- The temporary C213 inspection workflow was removed from the final tree after collecting its artifact.

## Browser/E2E coverage gap

The repository has delivery/database behavior scripts but no discovered Playwright, Cypress, Jest, or Vitest browser suite. The CI results do not prove rendered browser journeys. Follow-up E2E coverage should include:

1. Anonymous and authenticated navigation, sign-in/out, and session refresh.
2. Admin-link visibility for database admins, regular members, and suspended admins, plus direct-route denial for unauthorized users.
3. Missing Supabase configuration and auth/profile lookup failures, verifying guest fallback and fail-closed admin visibility.
4. Private Saved Lights, Bless/Inspired/Did too state, optimistic rollback, and refresh behavior.
5. Anonymous Offering projections and absence of author identifiers/private Journey data in public responses.
6. Reminder timezone hydration, persisted preference behavior, suspended-member restrictions, keyboard navigation, and mobile layout.

## Validation evidence

- [C213 OpenNext candidate run 44916860601](https://github.com/ADRN-9/deedlight/actions/runs/44916860601): clean `npm ci`, full and production JSON audits, unchanged audit gates, ESLint, 11/11 delivery tests, TypeScript, Next build, and Cloudflare packaging all passed on the candidate lock graph.
- [PR Validation run 44916860532](https://github.com/ADRN-9/deedlight/actions/runs/44916860532): all five jobs passed, including security assertions, all four PostgreSQL behavior jobs, lint, delivery behavior, audit thresholds, TypeScript, Next build, and Cloudflare packaging.
- The candidate workflow committed the reviewed `package.json` / `package-lock.json` update as `fa0b18a5daccda5be0d27437e1c439f7d1bd2f99`. The final PR head must receive a fresh exact-head PR Validation run after this lockfile commit and documentation update.

No historical migrations, Production data, credentials, scheduler settings, or Production resources were modified. No approval, merge, or deployment was performed. Production remains **NO-GO**.
