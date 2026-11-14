# DeedLight dependency remediation disposition — Cycle 70

**Status: OPEN. No dependency changes or lockfile were committed. No clean npm audit is claimed.**

## Exact baseline

At failed CI head `cf41a564ff1810aa1c8a592dfb147e5141ec963c`:

- `package.json` Git blob: `76cbb9f2cb84dcd8c316ef99efff7a052e573782`.
- `package-lock.json` Git blob: `78f4d841ec05dfda5b0b405478ab33dc75efba20` (npm lockfile v3).
- Direct pinned `next: 16.3.6`, plus many root dependencies using the mutable `latest` specifier. `npm ci` faithfully installs the *resolved* vulnerable versions in the lockfile, not new package releases.
- Resolved `@opennextjs/cloudflare@1.20.2`, `wrangler@4.137.0`, `miniflare@5.20260921.0-alpha`, React `19.2.8`, and `eslint-config-next@16.2.11`.

## Staged candidate changes — proposed, not validated

1. Pin `next` to a security-patched **16.4.6** candidate (the affected CI audit reported this as a proposed fix), and update related Next lint/config dependencies only after testing. The observed OpenNext adapter `1.20.2` declares `next >=15.5.21 <16 || >=16.2.11`, so this target fits the stated peer range; **peer-range compatibility is not a build pass**.
2. Pin `zod` to a patched **4.6.7** candidate (advisory fixes versions `>=4.6.6`), and run the app's validator/security tests.
3. Evaluate `wrangler@4.162.0` candidate and its Miniflare/Undici/Sharp chain. `@opennextjs/cloudflare@1.20.2` declares `wrangler ^4.86.0`; the candidate satisfies the peer range but needs an actual OpenNext package build and Cloudflare compatibility checks.
4. Update the reachable transitive packages where manifest-compatible: Express `body-parser` and `proxy-addr`, PostCSS/Tailwind's `source-map-js`. Use normal dependency-resolution with a regenerated npm lockfile; do **not** inject unverified overrides.
5. Address moderate `@node-minify/core -> glob@9.3.5` and nested `minimatch` through a compatible upstream adapter change, not by disabling the audit.
6. Replace broad `latest` root specifications with explicit pinned, reviewed versions and lockfile consistency for reproducible CI.

## Required validation before accepting any dependency upgrade

```bash
npm install --package-lock-only
npm ci
npm audit --audit-level=high
node --test scripts/test-delivery-transport.mjs
npx tsc --noEmit
npm run build
npx opennextjs-cloudflare build
```

Then run the entire PR Validation and disposable database workflows on **one exact combined candidate SHA** and compare output. Stop on any high/critical advisory. Confirm Cloudflare adapter and Next changes are compatible rather than assuming the peer range suffices.

## Current hard limitations

This isolated environment cannot reach the npm registry (`ENOTFOUND/EAI_AGAIN` network resolution), and a full repository checkout/lockfile is not available locally. Only the authenticated GitHub API lockfile inspection and the *previous real CI audit* were executed. A fresh local lockfile-based npm audit and build **were not run**. No dependency patch was fabricated and no security gate was weakened.
