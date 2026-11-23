# C319 dependency security remediation

## Baseline evidence

The baseline was PR #10 at commit `cd5f96ddd72c7fb43cf01e45895fc0b5ed14abda`.

- Push validation run: [45086175416](https://github.com/ADRN-9/deedlight/actions/runs/45086175416)
- Audit job: `137405217917`
- Audit command: `npm audit --audit-level=high`
- Audit result: nine moderate-severity vulnerability findings.

The npm report contains **two distinct GitHub Security Advisories**, propagated through nine affected package nodes. The aggregate count is not nine separate GHSA identifiers.

## Findings and dispositions

| Reported package node | Baseline version | Dependency path | Disposition |
|---|---:|---|---|
| `glob` | 13.0.7 | `@opennextjs/cloudflare` → `glob` | Scoped override to 14.0.6 |
| `@opennextjs/cloudflare` | 1.20.17 | Direct development dependency; inherits vulnerable `glob` | Its `glob` child is overridden only within this adapter |
| `minimatch` | 10.2.5 | `glob` and TypeScript ESLint parser chains | Resolved to 11.0.9 |
| `typescript-eslint` | 8.65.0 | `eslint-config-next` → `typescript-eslint` | Override to 8.73.0 |
| `@typescript-eslint/typescript-estree` | 8.65.0 | TypeScript ESLint parser/tooling chain | Updated to 8.73.0 |
| `@typescript-eslint/parser` | 8.65.0 | `typescript-eslint` | Updated to 8.73.0 |
| `@typescript-eslint/type-utils` | 8.65.0 | `@typescript-eslint/eslint-plugin` | Updated to 8.73.0 |
| `@typescript-eslint/eslint-plugin` | 8.65.0 | `typescript-eslint` | Updated to 8.73.0 |
| `@typescript-eslint/utils` | 8.65.0 | TypeScript ESLint plugin/type-utils chain | Updated to 8.73.0 |

### Advisory details

- [GHSA-3g3m-2fjr-6pw4](https://github.com/advisories/GHSA-3g3m-2fjr-6pw4): glob versions 9.0.0 through 14.0.1 are affected; 14.0.2 is the first patched release. The lockfile now resolves glob 14.0.6. The override is scoped to `@opennextjs/cloudflare`; no global glob override is applied.
- [GHSA-g3hv-75wg-m249](https://github.com/advisories/GHSA-g3hv-75wg-m249): minimatch versions 7.0.0 through 11.0.0 are affected; 11.0.1 is patched. The lockfile now resolves minimatch 11.0.9. The `typescript-eslint` override moves the `@typescript-eslint` family to 8.73.0, whose `typescript-estree` dependency accepts minimatch ^11.0.1.

The six older nested `minimatch@3.1.5` copies remain unchanged because they are outside the affected advisory range. No broad override is applied to those legacy consumers.

## Dependency scope and runtime exposure

The two direct packages in the affected paths are `@opennextjs/cloudflare` and `eslint-config-next`, both direct development dependencies. The vulnerable packages and all nine reported package nodes are marked `dev: true` in the lockfile. None is a direct production dependency, and the inspected lockfile contains no affected production-runtime path.

This does not make the findings irrelevant: OpenNext runs during Cloudflare packaging, while the TypeScript ESLint packages are installed and used in the development/CI toolchain. The remediation therefore covers build and CI supply-chain exposure, not a demonstrated production request-path exploit.

## Compatibility and override scope

The pinned OpenNext Cloudflare 1.20.17 source uses the `glob` and `globSync` functions in its build, manifest-inlining, and cache-population paths. The override is limited to that adapter dependency rather than changing glob for unrelated consumers. The PR's Cloudflare packaging build is the compatibility gate for this major-version override.

The existing `source-map-js` and `miniflare@5.20261110.2-beta` / `undici` overrides are preserved. No delivery, webhook, authorization, privacy, or migration files are modified by this remediation.

## Executable regression protection

- `scripts/verify-dependency-remediation.mjs` checks the scoped overrides, patched package versions, all nine affected nodes' development-only classification, and absence of vulnerable glob/minimatch versions.
- PR validation runs that verifier after `npm ci`.
- The existing audit gate is strengthened from `--audit-level=high` to `--audit-level=moderate`; it is not weakened.
- A temporary lock-refresh workflow used `npm install --package-lock-only --ignore-scripts`, verified the dependency versions, and ran `npm audit --audit-level=moderate`. Run [45088294421](https://github.com/ADRN-9/deedlight/actions/runs/45088294421) completed successfully with `found 0 vulnerabilities`. The temporary workflow is removed after its artifact and evidence are captured.

Final acceptance still requires fresh push and pull-request validation against the exact final PR HEAD, including TypeScript, Next build, Cloudflare packaging, the strengthened audit gate, and existing delivery/database regression jobs. This document does not claim Production validation.
