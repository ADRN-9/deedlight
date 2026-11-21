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

## npm scripts are not a Production authorization boundary

These wrappers are defense in depth for normal developer workflows, not an authorization boundary against a user who can execute arbitrary commands. A user can invoke the Supabase CLI directly, edit local files, or change their shell environment. Do not put Production credentials in a developer shell, `.env` file, repository secret, or local Supabase configuration.

Production authorization must remain enforced independently through protected GitHub branches, a Production Environment with independent required reviewers and self-review prevention, branch restrictions, and Production credentials scoped only to that Environment. The Production migration workflow must not be restored until those administrative protections are independently verified and the migration-history reconciliation gate is complete.

The legacy `.github/workflows/supabase-migrations.yml` remains present in the current `main` tree and must not be used. Its removal is tracked separately; this remediation does not change or restore it.

## Rollback

Reverting the remediation commit restores the prior npm script definitions and setup instructions. It does not run a migration or reset, change Supabase credentials, alter GitHub Environment settings, or modify Production. If the wrapper fails closed, use the local CLI directly only for local development; do not bypass the wrapper for hosted targets.
