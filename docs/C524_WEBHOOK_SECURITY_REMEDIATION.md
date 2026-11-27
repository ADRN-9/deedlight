# C524 — webhook dependency and network-isolation remediation

## Scope and disposition

Repository: `ADRN-9/deedlight`  
Pull request: [#25](https://github.com/ADRN-9/deedlight/pull/25) — keep OPEN / UNMERGED  
Baseline candidate: `0958d169160586f4e764267f79a9eb8d45791a4c`  
Base: `e7f0898b52e4e58b807d1c14a134684e740e5295`

This report covers the nine moderate npm audit vulnerability instances, their two underlying GitHub advisories, the compatible lockfile remediation, and the webhook test isolation boundary. No Production credentials, database, provider settings, scheduler, or delivery state were changed.

## Advisory inventory

The baseline exact-head workflow reported nine moderate vulnerability instances. They were two distinct advisories affecting nine package nodes in the dependency graph; all nine were development/build-tool dependencies (`dev: true` in the lockfile), not direct application runtime dependencies.

| # | Affected package node | Baseline version | Advisory | Disposition |
|---:|---|---:|---|---|
| 1 | `@opennextjs/cloudflare` | 1.20.17 | GHSA-3g3m-2fjr-6pw4 (through glob) | Updated to 1.20.19 |
| 2 | `glob` | 13.0.7 | GHSA-3g3m-2fjr-6pw4 | Updated to 14.0.6 |
| 3 | `minimatch` | 10.2.5 | GHSA-g3hv-75wg-m249 | Updated to 11.0.9 |
| 4 | `typescript-eslint` | 8.65.0 | GHSA-g3hv-75wg-m249 (transitive) | Updated to 8.74.0 |
| 5 | `@typescript-eslint/eslint-plugin` | 8.65.0 | GHSA-g3hv-75wg-m249 (transitive) | Updated to 8.74.0 |
| 6 | `@typescript-eslint/parser` | 8.65.0 | GHSA-g3hv-75wg-m249 (transitive) | Updated to 8.74.0 |
| 7 | `@typescript-eslint/type-utils` | 8.65.0 | GHSA-g3hv-75wg-m249 (transitive) | Updated to 8.74.0 |
| 8 | `@typescript-eslint/utils` | 8.65.0 | GHSA-g3hv-75wg-m249 (transitive) | Updated to 8.74.0 |
| 9 | `@typescript-eslint/typescript-estree` | 8.65.0 | GHSA-g3hv-75wg-m249 (transitive) | Updated to 8.74.0 |

Affected dependency paths:

- `@opennextjs/cloudflare@1.20.17 → glob@13.0.7` (glob advisory).
- `glob@13.0.7 → minimatch@10.2.5` (minimatch advisory).
- `eslint-config-next → typescript-eslint@8.65.0 → @typescript-eslint/{eslint-plugin,parser,type-utils,utils,typescript-estree}@8.65.0 → minimatch@10.2.5` (minimatch advisory; type-utils is also reached through eslint-plugin).

The glob advisory covers glob 9.0.0 through 14.0.1 and identifies 14.0.2 as the minimum fixed release. The minimatch advisory covers 7.0.0 through versions below 11.0.1 and identifies 11.0.1 as fixed. The upstream OpenNext 1.20.19 changelog explicitly records its glob 14 migration to remove the vulnerable minimatch 10 chain. TypeScript ESLint 8.74.0 declares `minimatch: ^11.0.1` in `typescript-estree`.

## Changes and reproducibility

- Manifest update commit: `8c702ec170f9e43546ab345e8a6c96a1c6b00cc6` — pin `@opennextjs/cloudflare` to 1.20.19.
- Lockfile refresh commit: `4e330d17d62eb4aa13175d90dd9fd045ff5eb7c9` — generated on GitHub Actions with Node 24/npm 11 using `npm install --package-lock-only --ignore-scripts` and `npm update --package-lock-only typescript-eslint --ignore-scripts`.
- Resulting lock versions: OpenNext 1.20.19, glob 14.0.6, minimatch 11.0.9, typescript-eslint 8.74.0 and all `@typescript-eslint/*` packages 8.74.0.
- The package manifest was checked unchanged during lock refresh. The resulting lockfile is committed; it was not hand-edited.
- npm audit JSON from the refreshed lock reports: info 0, low 0, moderate 0, high 0, critical 0, total 0.

## Webhook network isolation

The existing webhook tests and privacy assertions remain in place:

- C73 Svix signature, timestamp/replay and provider-event regressions.
- Exported Next.js `POST` route instrumentation with mocked verifier and privileged Supabase client; each invalid destination returns 503 with zero verifier, privileged-client, RPC and outbound-network counters.
- Process-local interception for Fetch, TCP/net sockets, TLS, HTTP/HTTPS, HTTP/2, DNS callback and promise APIs, UDP and WebSocket where provided by Node.
- Synthetic recipient and raw-payload canaries remain absent from captured logs and response bodies.

The temporary C524 GitHub Actions workflow also tested a kernel network namespace. On Ubuntu GitHub Actions, `sudo unshare --net --mount-proc` was available. A direct TCP connection attempt to 1.1.1.1:443 inside that namespace failed with `ENETUNREACH`; both webhook isolation tests then passed inside the same namespace.

This establishes kernel network-namespace isolation for the tested CI job, not a general assertion about every hosted runner or Production runtime. The temporary workflow is removed after evidence capture; the permanent targeted and full PR workflows continue to run the process-local API-denial, exported-route, Svix and privacy regressions. Re-run the C524 OS-namespace probe if the runner image or isolation environment changes.

## CI evidence

- Baseline audit: C507 run 45908996323, exact baseline SHA `0958d169160586f4e764267f79a9eb8d45791a4c`; the audit reported nine moderate instances.
- Dependency lock refresh and zero-advisory audit: C524 run 45914403038; artifact 15161263694.
- OS network namespace, direct egress-denial probe, webhook tests and zero-advisory audit: C524 run 45914752342; artifact 15161189729; candidate SHA `0242a07ac54a2d1a87193fc2bda6d8f92e0b9679`.
- On that candidate, targeted C507 runs 45914630328 and 45914752379 and Full PR Validation run 45914752345 completed successfully. (The later run at 45914752379 was still in progress when this report was first drafted; final exact-head results are to be added after the temporary workflow is removed.)

The temporary workflow is intentionally bounded to this branch, has no Production secrets, installs with lifecycle scripts disabled for the lock refresh, records the audit artifact, and is removed after evidence collection.

## Remaining risks and blockers

- PR #25 still requires independent formal security review by a qualified non-author with repository review permissions. The author-authored `COMMENTED` review is not approval; see the C523 nomination request in the PR discussion.
- The advisory remediation is confirmed by a clean npm audit on the regenerated lockfile. Exact-head full CI must remain green after temporary-workflow cleanup.
- OS-level isolation was demonstrated in the GitHub Actions test job only. It is not a Production egress-control claim.
- Production provider replay, bounce/complaint, scheduler, kill-switch and smoke gates remain separate. No Production operations were performed.
- PR #25 remains OPEN / UNMERGED. Do not merge or change Production as part of C524.
