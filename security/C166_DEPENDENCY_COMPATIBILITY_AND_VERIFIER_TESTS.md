# C166 — OpenNext dependency compatibility and verifier regression tests

**Repository:** `ADRN-9/deedlight`  
**PR:** #11 — keep open, draft and unmerged  
**Baseline head:** `fda28e0f2faf6c738b01f78a152316a14b69fd02`  
**Production:** NO-GO; no Production connection or mutation performed.

## OpenNext compatibility determination

As checked on 2026-11-19, no verified upstream `@opennextjs/cloudflare` release removes the `glob@14.0.2` major-version override:

- Latest upstream release is `@opennextjs/cloudflare@1.20.17`: https://github.com/opennextjs/opennextjs-cloudflare/releases/tag/%40opennextjs/cloudflare%401.20.17
- Upstream package metadata at tree `68fc728f141a1d9b2aa2ff7a79d4f12a9d1a896f` still uses the `glob` workspace catalog: https://github.com/opennextjs/opennextjs-cloudflare/blob/68fc728f141a1d9b2aa2ff7a79d4f12a9d1a896f/packages/cloudflare/package.json
- The same upstream tree's `pnpm-workspace.yaml` defines `glob: ^13.0.6`: https://github.com/opennextjs/opennextjs-cloudflare/blob/68fc728f141a1d9b2aa2ff7a79d4f12a9d1a896f/pnpm-workspace.yaml
- The release's dependency range does not admit glob 14.0.2.
- GHSA-3g3m-2fjr-6pw4 affects glob `>=9.0.0 <=14.0.1` and identifies `14.0.2` as patched: https://github.com/advisories/GHSA-3g3m-2fjr-6pw4. The published affected range includes glob 13.x, so selecting the newest compatible 13.x version is not a remediation.

The upstream Cloudflare adapter currently uses `glob`, `globSync` and `globSync(..., { withFileTypes: true })` in its build/cache/manifest paths. The C165 exact-head Cloudflare packaging build passed with the scoped 14.0.2 override. That is evidence for the current application build, not a formal upstream compatibility guarantee.

## Decision and risk

Retain the existing narrowly scoped override:

```json
"@opennextjs/cloudflare": {
  "glob": "14.0.2"
}
```

Do not replace it with a vulnerable glob 13.x version, suppress the advisory, weaken npm audit, downgrade OpenNext, or introduce an unreviewed local patch. This remains an explicit semver compatibility exception until upstream publishes a release whose dependency range admits a patched glob version.

Preferred resolution path:
1. Open/track an upstream OpenNext dependency update to a patched compatible glob release.
2. Upgrade Deedlight to that upstream release.
3. Remove the scoped override and regenerate the lockfile.
4. Require zero moderate-or-higher audit findings plus exact-head TypeScript, Next.js build, Cloudflare packaging and application/database CI before accepting the change.

A maintained OpenNext fork or an independently patched glob 13 backport is a possible fallback only if upstream cannot ship promptly; either adds ongoing patch provenance and compatibility maintenance and is not adopted here.

## Verifier regression tests

Added `scripts/test-dependency-security.mjs`, using Node's built-in test runner and isolated temporary package/lockfile fixtures. It proves:
- the verifier accepts the currently patched stable dependency versions;
- prerelease `glob` versions are rejected;
- prerelease `minimatch` versions are rejected;
- prerelease `typescript-eslint` versions are rejected;
- prerelease `@typescript-eslint/typescript-estree` versions are rejected.

Added package command `npm run test:dependency-security` and a dedicated PR Validation step. The tests exercise the actual verifier in a child Node process; they do not duplicate its version-parsing implementation.

## Scope and safety

No dependency versions or lockfile entries are changed in C166. No migration, PostgreSQL fixture, migration-history evidence, audit manifest, Production credential, deployment, provider-send or Cron configuration is modified. PR #10 and PR #12 remain out of scope.
