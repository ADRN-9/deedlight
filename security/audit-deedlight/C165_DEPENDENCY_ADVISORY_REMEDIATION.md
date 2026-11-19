# C165 — PR #11 dependency advisory remediation

**Repository:** `ADRN-9/deedlight`  
**PR:** #11 — dependency and migration-history audit remediation  
**Starting PR head:** `e8234bca50c6989a0716c28516511b914fc2494d`  
**Production status:** No Production connection, migration, deployment, provider send or scheduler action was performed.

## Current dependency findings

The exact-head PR Validation audit reported **9 moderate findings** across two distinct GitHub advisories:

- `GHSA-3g3m-2fjr-6pw4` — `glob` AbortSignal cancellation can reject while background directory traversal continues. Affected versions: `>=9.0.0 <=14.0.1`; patched in `14.0.2`.
- `GHSA-g3hv-75wg-m249` — `minimatch` globparts amplification can cause excessive preprocessing CPU/memory. Affected versions: `>=7.0.0 <11.0.1`; patched in `11.0.1`.

The original lockfile had two vulnerable installed package nodes:
- `node_modules/glob@13.0.7`, pulled by `@opennextjs/cloudflare@1.20.17` (`glob: ^13.0.6`), and depending on `minimatch: ^10.2.2`.
- `node_modules/minimatch@10.2.5`, shared by that glob node and `@typescript-eslint/typescript-estree@8.65.0`.

The additional `minimatch@3.1.5` copies under ESLint plugins/config packages are outside the advisory's affected range and are not vulnerable to this advisory. The nine npm audit findings are dependency-path findings, not nine separate GHSA records.

The lint chain was `eslint-config-next@16.2.11` → `typescript-eslint@8.65.0` → `@typescript-eslint` parser/plugin/utils/type-utils/typescript-estree packages → `minimatch@10.2.5`.

## Minimal candidate remediation

- Added direct development dependency `typescript-eslint@8.73.0`. This is within `eslint-config-next`'s declared `^8.46.0` range. Its `@typescript-eslint/typescript-estree@8.73.0` dependency declares `minimatch: ^11.0.1`.
- Added a **scoped** npm override only for `@opennextjs/cloudflare`'s `glob` dependency: `14.0.2`. The adapter currently declares `glob: ^13.0.6`, so this override is a major-version compatibility exception rather than a semver-satisfying update. It is not a global glob override.
- The candidate lockfile resolves `glob@14.0.2`, `minimatch@11.0.9`, and `typescript-eslint@8.73.0`. The unaffected `minimatch@3.1.5` copies remain at their existing compatible version.
- No advisory suppression, `npm audit` threshold reduction, `--force` downgrade, or OpenNext Cloudflare downgrade was used.

OpenNext's published implementation imports and uses only the `glob()` and `globSync()` APIs with `cwd`, `absolute`, `windowsPathsNoEscape`, `ignore`, and `nodir` options. Those APIs/options remain available in glob 14.0.2. The compatibility exception must nevertheless be validated by the repository's actual Next.js and Cloudflare packaging builds and should be removed when OpenNext publishes a compatible patched dependency range.

## Candidate CI evidence

The isolated branch `security/deedlight-deps-c165-candidate` generated the lockfile using Node `22.13.0` and npm `10.9.0`.

Candidate workflow: [44501157601](https://github.com/ADRN-9/deedlight/actions/runs/44501157601).

- `npm ci`: PASS.
- `npm audit --audit-level=moderate`: PASS; zero vulnerabilities.
- `npm ls glob minimatch typescript-eslint --all`: PASS; confirms `glob@14.0.2` (overridden), `minimatch@11.0.9`, `typescript-eslint@8.73.0`, and unaffected `minimatch@3.1.5` copies.
- Candidate lockfile commit: `d364403d278b3e745d137f09acd00b0e1cb6f6f8`.

This isolated candidate run did not execute the full application build. Exact-head PR Validation must still prove TypeScript, Next.js build, Cloudflare packaging, all database behavior jobs, and the moderate-or-higher npm audit on the PR branch.

## Automated regression guard

`scripts/verify-dependency-security.mjs` checks every lockfile package path for the two vulnerable ranges, asserts patched minimum versions for glob/minimatch/TypeScript ESLint, and verifies the scoped OpenNext override matches the resolved lockfile version. PR Validation runs this guard and `npm audit --audit-level=moderate`.

## Remaining compatibility and operational notes

The glob override is intentionally limited to the OpenNext adapter because the upstream semver range excludes the patched major. CI build success is necessary evidence, but a future OpenNext update should be reviewed for a native patched `glob` dependency so the override can be removed. The dependency fix does not authorize merge or Production deployment. PR #11 remains draft and unmerged; PRs #10 and #12 remain unchanged.
