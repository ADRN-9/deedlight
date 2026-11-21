# Supabase CLI target security

## Purpose and current authorization state

Deedlight uses Supabase CLI **3.2.0**. The version is pinned in `config/supabase-cli.json`, installed at the same exact version in PR CI, and checked by every wrapper invocation.

`config/supabase-projects.json` is the sole repository allowlist for hosted non-Production database migrations. It contains the known Production project reference as an explicit deny and currently has an empty `approvedNonProductionProjectRefs` array.

The empty array is intentional. The current repository and its setup templates do not establish an authoritative staging or development project reference. Do not guess one, copy an arbitrary ref from a developer's machine, or add the Production ref. Until the project owner supplies and reviews authoritative non-Production refs, hosted migration and link wrappers fail closed. Local development remains available.

To authorize a non-Production project, the project owner must independently verify its identity and purpose, then add its exact 20-lowercase-letter ref to `approvedNonProductionProjectRefs` in a reviewed change. The Production ref must never be included.

## Supported commands

Install Supabase CLI 3.2.0 using the official installation instructions and verify `supabase --version` reports `3.2.0`. Start the local Supabase stack and apply migrations locally:

```bash
supabase start
npm run supabase:push
```

Reset only the local database:

```bash
npm run supabase:reset
```

For an approved non-Production project, after its reference has been added to the reviewed allowlist:

```bash
SUPABASE_PROJECT_REF=<approved-non-production-ref> npm run supabase:link
SUPABASE_PROJECT_REF=<approved-non-production-ref> npm run supabase:push:nonprod
```

The wrapper requires the exact target to be allowlisted, rejects the Production ref, checks the effective `SUPABASE_PROJECT_ID` (including Supabase project dotenv files), and requires `supabase/.temp/project-ref` to match. The link command verifies the linked identity after linking.

The non-Production push uses the CLI v3 explicit selector `--remote=<approved-ref>`. It first performs a non-mutating `--dry-run`, requires the CLI's resolved `Target:` line to identify exactly the approved ref, rechecks the allowlist and linked identity, and only then runs the same explicit remote command. The CLI's hosted-change confirmation remains interactive; the wrapper never supplies `--yes`.

No forwarded arguments are accepted by the wrappers. This prevents `npm run` arguments from replacing the approved target or adding alternate remote selectors.

## Local-only guarantees and destructive edge cases

- `npm run supabase:push` invokes only `supabase db push` with no remote selector.
- `npm run supabase:reset` invokes only `supabase db reset` with no remote selector.
- `supabase:reset` rejects every forwarded argument, including `--remote`, `--project-ref`, `--db-url`, `--linked`, `--yes`, and combinations such as `--yes --remote`.
- Local reset is still destructive to the local database. It recreates the local database and discards local schema/data changes not represented by migrations and seed files.
- The remote wrapper rejects a missing, malformed, empty, duplicate, Production-containing, or unauthorized allowlist; mismatched `SUPABASE_PROJECT_ID`; missing/malformed/mismatched linked identity; a CLI version mismatch; missing or ambiguous resolved-target output; and all forwarded arguments.

## Hosted migration confirmation boundary

Hosted non-Production migrations require the CLI's normal interactive confirmation. The wrapper rejects any caller-provided `SUPABASE_YES` variable for `supabase:push:nonprod`, including values such as `false` or an empty string. This is deliberately stricter than the CLI's truthiness parsing: the wrapper does not accept an ambient confirmation-bypass setting. The wrapper also removes `SUPABASE_YES` from the child environment used by hosted commands. It never adds `--yes`.

The CLI's captured `--version` and `--dry-run` calls use piped stdout/stderr so the resolved `Target:` line can be verified. The final mutating `db push` inherits stdin, stdout and stderr instead. Supabase CLI 3.2.0 determines prompt availability from whether stdout and stdin are TTYs; capturing stdout into a pipe makes `Output.interactive` false and blocks the prompt. Inheriting all three streams keeps the CLI confirmation visible and answerable. If the parent process itself is non-interactive, the CLI continues to fail closed rather than auto-confirming.

Local `supabase:push` and `supabase:reset` retain the caller's normal environment; the `SUPABASE_YES` restriction applies only to hosted migration mode. Local operations do not target hosted projects.


## Hosted wrapper state-mode boundary

Supabase CLI 3.2.0 supports an experimental stack project-state mode. The CLI selects it with `SUPABASE_EXPERIMENTAL_STACK=1` or `[experimental] stack = true`; `SUPABASE_EXPERIMENTAL_STACK=0` overrides the config back to legacy mode, while an unset or empty variable falls back to the config. In stack mode, the CLI reads the hosted link from `supabase/.link.json`, whose `project.ref` is the parent project and whose `active_branch.ref` is the actual linked target. Legacy mode reads `supabase/.temp/project-ref`.

The Deedlight hosted wrappers deliberately support only legacy identity. They fail closed before invoking Supabase CLI when:
- `SUPABASE_EXPERIMENTAL_STACK` is present in the environment, including `1`, `0`, empty, or invalid values;
- `SUPABASE_WORKDIR` is present and could redirect the CLI to a different checkout;
- `supabase/.link.json` exists, even if a matching legacy `.temp/project-ref` also exists;
- the selected `supabase/config.json`, `config.jsonc`, or `config.toml` enables `experimental.stack`, or uses a dynamic environment reference for it.

Literal `experimental.stack = false` remains supported. The stack-mode check is repeated after the dry-run target check and immediately before the mutating hosted push, so a newly written stack link or changed project config cannot be masked by a stale legacy link. Stack-mode linked identity is intentionally not interpreted or trusted by this wrapper; use the Supabase CLI's stack-aware workflow separately. The Production deny reference and empty Non-Production allowlist are unchanged.

The implementation follows the pinned CLI's state-mode and link-file behavior:
- https://github.com/supabase/cli/blob/v3.2.0/apps/cli/src/shared/config/project-state-mode.ts
- https://github.com/supabase/cli/blob/v3.2.0/apps/cli/src/shared/config/experimental-feature.ts
- https://github.com/supabase/cli/blob/v3.2.0/apps/cli/src/shared/config/link-snapshot.ts
- https://github.com/supabase/cli/blob/v3.2.0/apps/cli/src/shared/config/project-link.ts
- https://github.com/supabase/cli/blob/v3.2.0/packages/config/src/paths.ts

### Structured TOML parsing and configuration precedence

The stack-mode guard no longer scans TOML text. It parses the selected document with `smol-toml@1.9.1`, using the same `parse(source)` API and TOML value semantics used by Supabase CLI 3.2.0's `@supabase/config` package. The later compatible parser patch is intentional: CLI 3.2.0's source lock resolves `smol-toml@1.8.0`, while the wrapper pins 1.9.1 as a development-only dependency to include the upstream parser's denial-of-service fix without adding it to the Deedlight runtime dependency graph. The parser is configured with `unsafeKeyBehaviour: "throw"`.

The guard inspects only the decoded top-level `experimental.stack` property. This correctly handles standard tables, inline tables (including nested values), and escaped quoted keys. The value must be a literal TOML boolean; strings, dynamic `env(...)` values, malformed TOML, duplicate keys, and malformed `experimental` values fail closed. The same literal-boolean requirement applies to JSON and JSONC. No unstructured TOML text matching remains.

Configuration discovery matches Supabase CLI 3.2.0 precedence: `config.json` first, then `config.jsonc`, then `config.toml`. Only the first existing file is parsed. A malformed selected file is an error; the guard never falls back to a lower-priority file.

The Supabase CLI security suite now has **44 tests**. C204 adds the exact C201 inline-table reproducer (experimental = { pgdelta = { stack = false }, stack = true }), a nested-only pgdelta.stack = true case with top-level experimental.stack = false, and two preflight-race regressions. The race shims respectively introduce stack-enabled TOML configuration and create supabase/.link.json after dry-run; both assert that the hosted mutation invocation is never reached. The earlier allowlist and legacy linked-identity race tests remain.


### Inherited Supabase CLI 3.2.0 parser availability advisory

The pinned Supabase CLI v3.2.0 source has packages/config/package.json declaring smol-toml: ^1.8.0, and its checked-in pnpm-lock.yaml resolves that dependency to **1.8.0**. Version 1.8.0 is affected by **GHSA-r4xh-jqrq-34v2** (CWE-407, CVSS 5.3 Moderate; no CVE assigned). The defect is quadratic-time parsing: parseKey searches the remainder of the whole TOML document for a dotted-key separator on each key/table line, even when the current line has no dotted key. Ordinary valid flat-key documents can therefore take O(n²) CPU. Attacker-controlled input can synchronously stall the parser process/event loop and impair CLI or CI availability. The advisory's example reports roughly 14 seconds to parse a 2.8 MB valid document. The advisory identifies versions <=1.8.0 as affected and **1.9.0** as patched.

This is an availability issue, not evidence of code execution, data disclosure, or database mutation. Exploitation requires the vulnerable parser to process attacker-controlled TOML. In this project the relevant boundary is a checked-out supabase/config.toml being parsed by the pinned CLI during a CLI operation; a malicious contribution or untrusted checkout can make that config attacker-controlled in a developer/CI workflow. The risk is conditional on the CLI actually parsing the file. The repository wrapper's smol-toml@1.9.1 development dependency fixes the wrapper's own stack-mode parser only; it does **not** replace the separately bundled smol-toml@1.8.0 inside the Supabase CLI 3.2.0 binary. A clean application npm audit is not proof that the downloaded CLI binary is free of this advisory.

The upstream upgrade path is for Supabase CLI to refresh the @supabase/config lockfile resolution to smol-toml@1.9.0 or later (prefer a current patched release such as 1.9.1), validate CLI compatibility, and publish a new official CLI release. Once that release exists and its exact binary/version is verified, Deedlight can update config/supabase-cli.json and the matching pinned CI installer together. **No newer Supabase CLI release has been verified for this task, so the pinned CLI remains 3.2.0; do not guess or install a prerelease/untested CLI version.** Until upstream ships and Deedlight validates a fixed CLI, avoid running the pinned CLI against untrusted TOML checkouts, especially in environments holding credentials; keep CI credentials absent as the current workflow requires. The residual CLI-binary availability risk remains an explicit security-review item.

Advisory: https://github.com/squirrelchat/smol-toml/security/advisories/GHSA-r4xh-jqrq-34v2
Supabase CLI 3.2.0 dependency manifest: https://github.com/supabase/cli/blob/v3.2.0/packages/config/package.json
Supabase CLI 3.2.0 dependency lock: https://github.com/supabase/cli/blob/v3.2.0/pnpm-lock.yaml

## Separate legacy Production migration workflow blocker

The current `main` snapshot still contains `.github/workflows/supabase-migrations.yml`. It is manually dispatchable, installs Supabase CLI `latest`, then runs `supabase link --project-ref "$SUPABASE_PROJECT_REF"` and `supabase db push` using repository secrets for the access token, database password, and project ref. The workflow file does not declare a protected GitHub `environment:` or a required approval gate. The secret values are not visible to this inspection, so their target cannot be independently established; treat this as a Production-capable operational hazard until the owner verifies otherwise.

PR #13 previously proposed removing the legacy workflow, but it remains separate and unmerged. PR #15 is still open and unmerged; its branch-only wrappers do not protect `main` or neutralize this workflow. Do not dispatch it. The workflow removal/disablement, Production Environment protections, branch restrictions, credential scoping, and migration-history reconciliation must be addressed as a separate approved operational change. This C202 parser fix does not modify `main`, alter the workflow, or perform any migration.

## npm scripts are not a Production authorization boundary

These wrappers are defense in depth for normal developer workflows, not an authorization boundary against a user who can execute arbitrary commands. A user can invoke the Supabase CLI directly, edit local files, or change their shell environment. Do not put Production credentials in a developer shell, `.env` file, repository secret, or local Supabase configuration.

Production authorization must remain enforced independently through protected GitHub branches, a Production Environment with independent required reviewers and self-review prevention, branch restrictions, and Production credentials scoped only to that Environment. The Production migration workflow must not be restored until those administrative protections are independently verified and the migration-history reconciliation gate is complete.

The legacy `.github/workflows/supabase-migrations.yml` remains present in the current `main` tree and must not be used. Its removal is tracked separately; this remediation does not change or restore it.


## Confirmation and dependency CI evidence

The hosted CLI environment is built by `createHostedCliEnvironment`, which removes `SUPABASE_YES` even when given contaminated input. The hosted migration path separately rejects a caller-provided value before any CLI invocation. A regression test directly exercises the sanitization helper.

The CLI wrapper's final hosted push inherits stdin, stdout and stderr. The security suite now uses Python's standard-library `pty` module to start the wrapper in a real pseudo-terminal with a terminal-aware CLI shim. The test verifies that the confirmation prompt reaches the terminal, that an operator response is read, and that the mutation shim records execution only after an affirmative response. A companion non-TTY test verifies the CLI shim refuses the hosted mutation and leaves its marker absent. This is a wrapper/TTY integration test with a safe CLI shim, not a live Supabase project operation.

Dependency audit findings were traced to vulnerable Next.js, Zod, body-parser, proxy-addr, qs, sharp, source-map-js, undici, glob and minimatch resolutions. PR #11's dependency-only package/lock update resolves these advisories in its exact-head CI run. Its lockfile changes 289 package entries, so the update is intentionally limited to package.json, package-lock.json and the dependency verifier/tests; its unrelated audit fixture and schema changes are not imported.

The PR #11 lockfile also moves the transitive Miniflare dependency from `5.20260921.0-alpha` to `5.20261110.2-beta`; both are pre-release versions. The scoped `undici@7.30.2` override is attached to that exact Miniflare beta. This is an inherited pre-release build-tool dependency, not a new application runtime API. It is not covered by the C166 stable-version verifier and remains an explicit maintenance risk to review when Wrangler/OpenNext publish a stable compatible dependency set.

The OpenNext-scoped `glob@14.0.2` override remains a major-version compatibility exception: OpenNext 1.20.17 declares `glob ^13.0.6`, while the patched version is 14.0.2. The C166 review found the adapter uses the compatible `glob`, `globSync` and `withFileTypes` API surface, and the PR #11 Cloudflare build passed. This is evidence for the current build, not a formal upstream semver guarantee. Keep the exception narrow and remove it once upstream supports a patched compatible major.

## Rollback

Reverting the remediation commit restores the prior npm script definitions and setup instructions. It does not run a migration or reset, change Supabase credentials, alter GitHub Environment settings, or modify Production. If the wrapper fails closed, use the local CLI directly only for local development; do not bypass the wrapper for hosted targets.
