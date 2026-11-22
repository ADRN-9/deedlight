# Production Supabase migrations temporarily disabled

**Status:** Proposed by PR #13. This PR removes the legacy Production migration workflow from the default branch. Until an authorized maintainer merges PR #13, \`main\` still contains that workflow. **Do not dispatch it or run Production migrations.** No replacement migration executor is included in this PR.

## Why the workflow was removed

The legacy \`.github/workflows/supabase-migrations.yml\` exposes repository-level secret names \`SUPABASE_ACCESS_TOKEN\`, \`SUPABASE_DB_PASSWORD\`, and \`SUPABASE_PROJECT_REF\` to a manually dispatched workflow. It uses \`supabase/setup-cli@v1\` with floating \`version: latest\`, then directly runs:

\`\`\`sh
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase db push
\`\`\`

There is no explicit target authorization before linking, no linked-project identity check before mutation, no pinned CLI version, no protected-main gate, and no GitHub Environment approval/deployment-branch boundary. A workflow-level \`workflow_dispatch\` trigger is not an authorization boundary. The workflow is removed rather than merely hiding its dispatch trigger or replacing it with an unverified guarded path.

## Exact workflow inventory and search

The current \`main\` tree at \`ce82b3fdf1a73510de70e3729a487d4ae00e66e3\` contains exactly these three files under \`.github/workflows/\`:

| Workflow | Trigger | Supabase migration behavior |
|---|---|---|
| \`pr-validation.yml\` | \`push\` (non-main) and \`pull_request\` to main | No \`workflow_dispatch\`, Supabase CLI setup, Supabase secrets, \`supabase link\`, or \`supabase db push\`. CI uses non-Production placeholders and asserts Production credentials are absent. |
| \`vm-self-hosted.yml\` | \`workflow_dispatch\` | Manual validation only. It requires a fixed feature-branch name and asserts Supabase service-role, access-token, DB-password, and project-ref variables are empty. It has no Supabase CLI setup, \`supabase link\`, or \`supabase db push\`. |
| \`supabase-migrations.yml\` | \`workflow_dispatch\` | The only current checked-in privileged migration path. It reads the three legacy Supabase secret names and runs \`supabase link\` followed by \`supabase db push\`. It is deleted by this PR. |

The \`.github/workflows/\` directory listing returned exactly those three files. The workflow-file scan found no other checked-in workflow with a Supabase migration command or equivalent privileged migration execution path. The PR branch tree contains only \`pr-validation.yml\` and \`vm-self-hosted.yml\` under \`.github/workflows/\`; the unsafe migration workflow is absent.

This is a review of checked-in workflow files. It does **not** prove that repository/org secrets have been removed, that runner environments are clean, or that external automation outside this repository does not exist.

## Repository protection and Production Environment evidence

Fresh inspection of GitHub repository metadata at C206:

- Default branch: \`main\`, SHA \`ce82b3fdf1a73510de70e3729a487d4ae00e66e3\`.
- Branch metadata reports \`protected: false\`.
- Repository rulesets endpoint returns an empty array (\`[]\`).
- Direct \`branches/main/protection\` read returns HTTP 403, \`Resource not accessible by integration\`. The connection cannot inspect detailed branch-protection rules. The branch metadata and empty ruleset result nevertheless establish that GitHub does not currently report \`main\` as protected.
- The GitHub connection does not expose the repository Environment settings endpoint or secret-administration APIs. Environment existence, required reviewers, self-review prevention, deployment-branch restrictions, and credential scopes therefore **cannot be verified** here. No claim is made that an Environment named \`production\` exists or is protected.

The PR #10 candidate is not an accepted replacement. It remains **OPEN, DRAFT, UNMERGED** at \`95fb79152243f9581647eae961f3c35cf5d1043b\`, on \`security/delivery-transport-consent-gates\`. Its workflow has an \`environment: production\` binding, a \`github.ref_protected\` condition and a sentinel-variable check, plus a pre-link Production-deny guard and a post-link linked-project check. However:

1. It installs Supabase CLI with \`version: latest\`, not a verified pinned version.
2. Its target guard accepts any syntactically valid 20-character non-Production ref; it does not consult an approved non-Production project allowlist.
3. The Environment's server-side reviewer, self-review, deployment-branch and secret-scope settings cannot be verified. Workflow YAML and a sentinel do not prove those server-side controls.
4. It does not enforce an evidence-backed Production migration-history acceptance gate. PR #10's own remediation notes treat historical migration reconciliation as a separate unresolved prerequisite.
5. It is not merged to \`main\` and does not currently provide an active default-branch migration process.

Accordingly, do not restore the PR #10 workflow by resolving its path conflict. Keep the deletion until a separately reviewed replacement satisfies every gate below. Preserve the empty \`approvedNonProductionProjectRefs\` allowlist and explicit Production project exclusion in the existing security work; this retirement PR does not change those policies or PR #15.

## Required administrator-only actions before any replacement

Responsible owner: the GitHub repository owner/administrator for \`ADRN-9/deedlight\` (repository owner account \`ADRN-9\`). If a future audit discovers organization-level credential copies, an organization owner must handle those separately. These are administrator operations and were **not** performed by this PR.

1. **Protect \`main\`** in repository Settings → Branches. Require pull requests, at least one approval from someone other than the author, dismissal of stale approvals, resolution of review conversations, and successful current PR Validation checks before merge. Disable force-pushes and branch deletion. Re-read the saved settings after applying them.
2. **Configure Environment \`production\`** in Settings → Environments (create it if absent). Require approval by at least one independent reviewer, enable prevention of self-review, and restrict deployments to selected branches with only protected \`main\` allowed. Do not treat a job-level \`if: github.ref_protected\` condition as a substitute for this server-side policy.
3. **Scope credentials only to that Environment** if/when a replacement is independently accepted. The intended Environment-only variable is \`PRODUCTION_MIGRATION_ENVIRONMENT_GUARD=production-environment-protected\`; intended Environment-only secret names are \`PRODUCTION_SUPABASE_ACCESS_TOKEN\`, \`PRODUCTION_SUPABASE_DB_PASSWORD\`, and \`PRODUCTION_SUPABASE_PROJECT_REF\`. Remove/revoke repository- or organization-level copies of both the legacy \`SUPABASE_*\` names and any \`PRODUCTION_SUPABASE_*\` duplicates. Do not place Production credentials in repository-level secrets.
4. **Independently verify** branch protection, Environment reviewers, self-review prevention, deployment branch restrictions, and exact secret/variable scopes using an administrator-authorized view. Record evidence without exposing secret values.
5. **Reconcile migration history separately** against the proven live Production schema and \`supabase_migrations.schema_migrations\` history. Require a reviewed reconciliation record that identifies each migration and its live-schema evidence. Do not blindly mark unverified migrations applied, run a reset, or infer live Production state from CI.
6. Only after the above, submit a new narrowly scoped migration workflow with a verified **pinned** Supabase CLI version, explicit allowlist authorization (the currently approved Non-Production list remains empty), a pre-link target guard, a post-link linked-project identity guard, server-side Environment controls, and a machine-enforced migration-history acceptance gate.

Until these administrator and technical gates are independently evidenced, Production migrations remain disabled. Non-Production database behavior tests using isolated CI services may continue.

## CI evidence

The PR #13 workflow-deletion head before the C206 documentation refresh was \`64ed94976fb952a160c45cf793e9c647ac34d8f2\` (tree \`b62d9e33312969e8ecb4c119d4e1627256591e0b\`). Both [PR Validation run 44877087042](https://github.com/ADRN-9/deedlight/actions/runs/44877087042) and [push validation run 44877083297](https://github.com/ADRN-9/deedlight/actions/runs/44877083297) failed at that exact SHA, with 3/5 jobs passing.

The C206 documentation commit \`d11f38540e5a0ad80aba923355d17dee0dd62cfc\` (tree \`bee480b0fa519d764a3ea9773bda8b3564208c78\`) was also tested at exact head:

- [PR Validation run 44901467035](https://github.com/ADRN-9/deedlight/actions/runs/44901467035): **FAILURE**, 3/5 jobs passed.
- [Push validation run 44901462535](https://github.com/ADRN-9/deedlight/actions/runs/44901462535): **FAILURE**, 3/5 jobs passed.
- Both runs checked out the exact \`d11f38540e5a0ad80aba923355d17dee0dd62cfc\` head.
- \`auth_pgcrypto_database_behavior\`, \`delivery_reliability_database_behavior\`, and \`sprint12_2_database_behavior\` passed.
- \`gentle_delivery_transport_database_behavior\` failed at \`scripts/test-gentle-delivery-transport.sql:96\` with \`Delivery claim is not authorized.\`
- \`validate\` failed at \`npm audit --audit-level=high\`: **21 vulnerabilities (12 moderate, 7 high, 2 critical)**. Diff integrity, all listed security assertion steps, and the fake transport behavior step passed; TypeScript, Next.js build, and Cloudflare packaging were skipped after the audit failure.

The failing SQL fixture and \`package-lock.json\` have identical blob SHAs on \`main\` and the PR branch. These are existing validation blockers outside the workflow-deletion/documentation scope. They remain real blockers and are not hidden or waived. No successful exact-head CI is claimed.

## Rollback and recovery expectations

This PR changes no application runtime, database schema/data, credentials, Environment settings, or deployment configuration. It deletes one manually dispatched workflow and adds documentation.

- If the PR is not merged, no rollback is needed; \`main\` remains unchanged and the unsafe workflow remains a live risk. Do not dispatch it.
- If the PR is merged, **do not revert the deletion merely to restore migration execution**. The safe operational state is that Production migration execution remains unavailable until the administrator and migration-history gates above pass.
- If an urgent migration is required, use a separately reviewed and approved replacement workflow meeting every gate above. Do not manually run the old \`supabase link\` / \`supabase db push\` sequence, use \`supabase db reset\`, or restore the unguarded workflow as an emergency shortcut.
- A documentation-only correction may be reverted independently. Restoring any Production migration capability requires a new security-reviewed change and fresh exact-head CI; it is not an automatic rollback of this deletion.

## Scope and safety

No PR was approved or merged. No workflow was dispatched. No Production database operation, migration, reset, deployment, credential change, repository privilege change, or GitHub Environment change was performed. PR #10 and PR #15 were not modified. Production remains **NO-GO** pending independent acceptance and all required release gates.


## C275 — Migration deployment governance investigation (2026-11-22)

This section supersedes earlier snapshot metadata in this document where branch heads, pull-request states, CLI release information, or CI evidence have since changed. It is a governance plan and evidence record, not Production authorization.

### Repository and pull-request snapshot

- Default branch: `main`, exact HEAD `ce82b3fdf1a73510de70e3729a487d4ae00e66e3`, tree `f7ada8719e9e9f4212f3bc53ae9ebb6b012554cc`.
- GitHub branch metadata reports `protected: false`; the branch protection object reports `enabled: false` and required-check enforcement `off`. The repository rulesets endpoint returns `[]`.
- The detailed branch-protection read returned HTTP 403 (Resource not accessible by integration). The Environments endpoint is not exposed by the connected GitHub integration. Therefore the saved branch-rule details and Production Environment configuration are **not inspectable here**. No claim is made that a Production Environment is absent or present, or that its reviewers, self-review setting, deployment branches, or secret scopes are configured.
- Repository metadata reports admin permission for the connected GitHub identity, but the available integration does not expose branch-protection or Environment administration writes. No administrator setting was changed.
- All requested PRs remain open and unmerged; no submitted GitHub PR reviews were found:

| PR | Current head | State | Base |
|---|---|---|---|
| #10 — delivery consent and Production migration workflow | `9072f3b8824ec9618849def1c0832000cd130474` | OPEN / DRAFT | main |
| #11 — metadata audit and disposable PostgreSQL fixtures | `f5ed62e4417921c8bee1a376fed8bac35897e809` | OPEN / DRAFT | main |
| #13 — disable legacy Production migration workflow | `cff11e6e19b3e1d360b8f38fafbf8a26b3782504` (pre-C277 HEAD; tree `3e91c407e20525f9c380575f18e6b336dd525a49`) | OPEN / READY | main |
| #15 — Supabase CLI target security | `1ce6213d1077a64d2a04d49949bb8302e243902a` | OPEN / READY | main |

All four PRs report mergeable. Preserve their existing branches and bases; this investigation does not retarget, merge, close, or rewrite any PR.

### Migration workflow and CLI findings

The current `main` workflow `.github/workflows/supabase-migrations.yml` is manually dispatched. It installs `supabase/setup-cli@v1` with floating `version: latest`, then runs `supabase link --project-ref "$SUPABASE_PROJECT_REF"` followed by `supabase db push`, using repository secret references `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, and `SUPABASE_PROJECT_REF`. It declares no `environment: production`, no Environment approval, no explicit Production target authorization, no migration-history acceptance check, and no backup/restore gate. The actual values and scopes of those secrets are not visible.

The root `package.json` on main does not install Supabase CLI as a package. The migration workflow installs it at runtime using `latest`; therefore the current main workflow has no reproducible CLI version.

The official latest stable Supabase CLI release inspected on 2026-11-22 is **v3.2.0**, published 2026-11-16. PR #15 is the existing candidate pin: it pins `supabase/setup-cli` to action commit `1dedf2c611547ede7232d26866dd3c56ab903bbb`, sets `version: 3.2.0` in `config/supabase-cli.json`, and checks `supabase --version` against that file in CI and its wrappers. PR #15's `config/supabase-projects.json` records Production ref `xaipiovflxomcbfwtwmu` as an explicit deny and leaves `approvedNonProductionProjectRefs` empty. Its hosted wrappers deliberately reject Production and verify a non-Production allowlist, linked identity, CLI version, and CLI-resolved dry-run target. Keep that Production deny and empty non-Production allowlist intact.

**CLI v3 target semantics matter:** database commands now target the local stack by default. A hosted push must use an explicit `--remote=<project-ref>`; the CLI's dry-run prints a `Target:` line and can show the migrations without applying them. Therefore both the legacy main workflow and PR #10's current candidate workflow, which call `supabase db push` without `--remote`, do not express an explicit hosted target under current CLI v3 semantics. Their floating `latest` version makes that behavior non-reproducible as well. Do not treat PR #10's `environment: production`, sentinel variable, pre-link guard, or post-link identity check as a complete migration executor: it still floats the CLI, omits the explicit remote selector, and has no accepted migration-history or backup preflight.

There is also a documented **moderate CLI-binary availability advisory**: the pinned v3.2.0 source resolves bundled `smol-toml@1.8.0`, affected by GHSA-r4xh-jqrq-34v2 (quadratic-time TOML parsing; fixed upstream in 1.9.0). PR #15's own `smol-toml@1.9.1` fixes its wrapper parser, not the separate copy bundled inside the CLI binary. Keep v3.2.0 as the currently verified stable pin rather than guessing a newer release, but treat this as an explicit residual risk: never expose Production credentials to an untrusted PR/checkout, and update the CLI pin only after an official patched CLI release is verified with fresh exact-head CI.

References:
- Supabase CLI v3 behavior: https://supabase.com/changelog/supabase-cli-v3
- Supabase CLI v3.2.0 release: https://github.com/supabase/cli/releases/tag/v3.2.0
- CLI db push and dry-run reference: https://supabase.com/docs/reference/cli/supabase-db-push
- GHSA-r4xh-jqrq-34v2: https://github.com/squirrelchat/smol-toml/security/advisories/GHSA-r4xh-jqrq-34v2

### Required main-branch rules and independent review

The repository owner/administrator must create an **active ruleset for `main`** (or equivalent branch protection) with no routine bypass actors and the following requirements:

1. Require pull requests; prohibit direct pushes, force-pushes, and branch deletion. Enforce the rules for administrators too.
2. Require **two independent approving reviews** for changes to `supabase/**`, `.github/workflows/**`, `scripts/supabase-cli*`, `config/supabase-*`, and Production migration/reconciliation documents. At least one reviewer must be the designated database/migration owner and another must be an independent security reviewer. For other main changes, require at least one approval from someone other than the author.
3. Require Code Owner review for the paths above; add a CODEOWNERS mapping to a maintained database/security reviewer team. The PR author cannot satisfy either approval.
4. Dismiss stale approvals after new commits, require approval of the latest push, require all review conversations resolved, and require the PR branch to be up to date (or use a merge queue with equivalent guarantees).
5. Require all current PR Validation job checks from the main workflow, with GitHub Actions as the expected source:
   - `validate`
   - `sprint12_2_database_behavior`
   - `delivery_reliability_database_behavior`
   - `gentle_delivery_transport_database_behavior`
   - `auth_pgcrypto_database_behavior`

   The check names above are the current five job IDs in main's `pr-validation.yml`; they are not a claim that they currently pass. Once the provider-webhook and migration-order jobs proposed on PR #10 are merged into the default-branch workflow, require `delivery_provider_webhook_database_behavior` and `delivery_migration_order_database_behavior` too. Before any Production migration workflow can be enabled, add a dedicated required `production_migration_preflight` check that validates the approved Production baseline and exact planned migration set. Do not configure a required check that does not yet exist.
6. Keep the bypass list empty. Record the saved ruleset ID, enforcement mode, required contexts, review count, CODEOWNERS path, and verification timestamp in the rollout tracker.

For Production migration code, the two PR approvals are separate from the operational deployment approval. Reviewers must inspect the actual SQL, migration order, data-loss/lock risks, target guard, CLI version, backup plan, and rollback plan. A passing CI run is not a review or Production authorization.

### Production Environment and credential boundary

The repository owner/administrator must create or verify GitHub Environment `production` and configure:

- Required reviewer(s) from a maintained database/security reviewer team; no author/self approval.
- Prevent self-review.
- Deployment branches restricted to **protected `main` only**; no feature branches, tags, or wildcard refs.
- Production credentials stored only as Environment secrets, never repository- or organization-wide secrets. Remove/revoke legacy `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, and `SUPABASE_PROJECT_REF` copies at repository/org scope; rotate any token/password whose prior scope cannot be established.
- Use least-privilege, project-scoped Supabase access. Keep `PRODUCTION_MIGRATION_ENVIRONMENT_GUARD` as an Environment-only variable. Keep the target ref Environment-scoped (prefer a variable because the ref is an identifier, not a credential) and independently compare it to the reviewed Production target. Keep only `PRODUCTION_SUPABASE_ACCESS_TOKEN` and `PRODUCTION_SUPABASE_DB_PASSWORD` as secrets if the eventual executor needs them.
- Capture administrator evidence of the saved reviewer list, self-review prevention, branch restrictions, Environment secret/variable names and scopes, and any bypass settings. Never record secret values.

GitHub's native Environment required-reviewer list allows up to six users/teams, but **only one listed reviewer needs to approve**. Therefore use two independent PR approvals for the code review requirement and a separate Environment approval for the deployment decision. If policy requires two Environment approvals specifically, native required reviewers alone do not provide that quorum; add a custom deployment protection rule or another independently enforced approval gate.

The workflow must bind the job to `environment: production` and assert protected main and the expected Environment sentinel as defense in depth. These YAML checks do not substitute for the server-side Environment settings. Environment approval must occur before the job receives Production credentials.

Reference: https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments

### Production target verification and fail-closed execution contract

No Production executor is approved by this investigation. A future separately reviewed executor must satisfy all of the following before any mutating command:

1. Verify the Production project reference independently with the Supabase project owner/admin using the dashboard or an authorized read-only project lookup. The repository's current candidate ref is `xaipiovflxomcbfwtwmu`; do not treat the file alone as proof of live target identity.
2. Require `GITHUB_REF=refs/heads/main`, `GITHUB_REF_PROTECTED=true`, the exact `production` Environment, the Environment sentinel, and the Environment-scoped target value. Missing, malformed, conflicting, or unexpected values stop the job.
3. Install the verified pinned CLI and assert its exact `supabase --version`. Do not use `latest`. Pin the setup action to a full commit SHA.
4. Use explicit `supabase migration list --remote=<expected-ref>` and `supabase db push --dry-run --remote=<expected-ref>`. Capture stdout and stderr; require the CLI-resolved `Target:` line to match the exact expected project. Compare the dry-run's migration set to the approved manifest. A missing, extra, ambiguous, or unparseable target or migration entry stops execution.
5. Immediately before mutation, reload the approved target and baseline, recheck the CLI version and environment identity, and run the same explicit target command. The mutation must use the same `--remote=<expected-ref>`; never fall back to the linked project or local default. Do not accept `--db-url`, `--linked`, alternate refs, `--include-all`, `--include-seed`, forwarded arguments, or a mutable local project link as a substitute for the explicit target.
6. CLI v3 requires `--yes` for non-interactive CI hosted changes. If the final workflow uses it, pass it only as an explicit argument inside the already Environment-approved Production job, after the target and migration preflight succeed. Never use a caller-controlled `SUPABASE_YES` variable, never pass `--yes` from a pull-request job, and never allow it to bypass Environment approval.
7. If any guard, dry-run, database identity check, or authorization lookup fails or becomes uncertain, do not call the mutating command. Do not retry against a fallback target. Record only redacted evidence; never log access tokens, database passwords, or connection strings.

The PR #15 wrappers are intentionally Non-Production-only and explicitly reject the Production ref. Do not add Production to their allowlist or weaken that policy. A Production executor must be a separate, independently reviewed path with its own protected Environment and baseline gate.

### Migration-history acceptance preflight

Production migration history remains **UNKNOWN**. The 31-file / 30-prefix inventory is a **PR #10 candidate inventory**, pinned to PR #10 source HEAD `9072f3b8824ec9618849def1c0832000cd130474` and its exact tree `e911e1b806e08fc80954526917c7a44796b741ba`; it is not the current `main` or PR #13 inventory. The live `main` HEAD `ce82b3fdf1a73510de70e3729a487d4ae00e66e3` (tree `f7ada8719e9e9f4212f3bc53ae9ebb6b012554cc`) and live pre-C277 PR #13 HEAD `cff11e6e19b3e1d360b8f38fafbf8a26b3782504` (tree `3e91c407e20525f9c380575f18e6b336dd525a49`) each contain 23 migration files and 22 distinct version prefixes. The eight later files `202611120023` through `202611210030` are present in the PR #10 candidate tree but absent from current `main` and PR #13. The 31-row inventory table is in `docs/PRODUCTION_MIGRATION_RECONCILIATION.md` at the PR #10 source commit (blob `9152f79c3bf6466ef443f0c72ad79c126b348284`); its file list and blob SHAs match that candidate tree. The two distinct candidate files sharing prefix `202607260007` remain a reconciliation hazard. None of these repository inventories is evidence of Production application state. The PR #10 reconciliation record reports that its 31 candidate files remain unclassified against Production; no Production `supabase_migrations.schema_migrations` rows or catalog evidence were retrieved because the connected Supabase accounts lacked permission for project `xaipiovflxomcbfwtwmu`. CI duplicate-007 tests and partial dependency-order tests are not a complete 31-file replay and do not prove Production state.

Before any Production push, the Supabase owner/admin must grant a project-scoped **read-only** identity permission to list migration history and perform SELECT-only catalog inspection, or supply equivalent independently verifiable evidence. Capture:

- Exact project/database identity, project ref, branch/environment, Postgres version, UTC timestamp, read-only principal, and evidence provenance.
- Every row in `supabase_migrations.schema_migrations` (version, name, statements and timestamps/available metadata), including remote-only versions.
- A complete relevant catalog inventory: schemas, relations, columns/defaults/nullability, constraints and validation state, indexes/definitions, functions/identity arguments/security/search_path/source hashes, triggers/enabled state, RLS policies, grants/default privileges, extension versions/namespaces, and relevant data counts.
- Retained SQL Editor/manual-execution records, deployment logs, and prior repair records for migrations 007/008, 018, 022, and the aggregate SQL bundle.
- A per-file and per-effect comparison of repository migration content (blob SHA and SQL/effect fingerprint) against live schema/history and manual changes.

Create a reviewed, machine-readable Production migration baseline in a separate change. It must bind the exact Production ref, source commit/tree, snapshot timestamp, every migration file/version/blob SHA, each classification (`applied-and-recorded`, `applied-but-unrecorded`, `unapplied`, `partial`, or `ambiguous`), evidence references, and two reviewer identities. CI must fail if the baseline is missing/stale, a file/version/hash changes, a classification is partial/ambiguous, a duplicate version is unresolved, or the live read-only preflight differs from the approved snapshot.

No migration may be silently marked applied or reverted. Use `migration repair` only after the exact migration's live effects and execution history have been independently proven and a separately approved repair plan identifies the exact version. Never use `--include-all`, `db reset`, or blind repair to get past a mismatch. Require a complete clean replay of the accepted migration sequence on a disposable Production-equivalent PostgreSQL/Supabase fixture, including the duplicate-007 resolution and all dependencies, before considering the Production baseline accepted.

Only when every migration/effect is classified, the 007 collision is resolved with evidence, the baseline is independently approved, and the CLI dry-run matches the explicitly approved migration set may a separately authorized Production push be considered.

### Backup, restore, and rollback expectations

Before each approved Production migration window:

- Verify the actual Supabase plan, backup configuration, retention, most recent completed backup, and latest restorable point. Do not assume the project has PITR or a particular retention period. Supabase documents daily backup retention of 7 days on Pro, 14 on Team, and up to 30 on Enterprise; PITR is an add-on and has a different recovery-point model.
- Where the approved recovery objective requires it, enable/verify PITR through a separate owner-approved operation. Record the latest restorable timestamp and the agreed RPO/RTO.
- Take a pre-change logical backup of the required database/schema/data to encrypted, access-controlled off-site storage, record its checksum and immutable backup identifier, and test restore into an isolated project before the window. Do not put raw Production dumps in Git, workflow logs, or ordinary GitHub Actions artifacts.
- Confirm whether the change touches Supabase Storage objects: database backups include Storage metadata but **not** the stored objects. Back up affected object content separately. Daily backups also omit custom-role passwords, which must be reset after a restore.
- Record the migration commit, exact target, planned migration list, backup/PITR identifier, operator, independent approver, workflow run, start/end timestamps, and redacted result.

Rollback is not an automatic reverse migration. Each migration must document whether it is reversible, forward-fix-only, or requires point-in-time restore; include data-preservation and validation steps. Prefer a reviewed forward corrective migration when safe. If restoration is required, stop further deployments and outbound delivery, preserve current evidence, obtain separate Production-owner approval, and restore to a **new project first** for validation where feasible. Restoring in place can make the project inaccessible during the operation and replaces later state; choose the restore point with explicit data-loss approval. No automatic rollback may run after an ambiguous provider/database outcome.

References:
- Supabase backups and restore behavior: https://supabase.com/docs/guides/platform/backups
- Supabase CLI db push dry-run: https://supabase.com/docs/reference/cli/supabase-db-push

### Exact administrator actions and current blockers

Repository owner/administrator (`ADRN-9`) must, in order:

1. Apply and independently verify the `main` ruleset and required checks above; save the ruleset ID and settings evidence.
2. Create/configure `production` Environment; set reviewer, prevent self-review, restrict deployments to protected `main`, and capture settings evidence.
3. Inventory repository/org secret names and scopes, remove/revoke legacy copies, rotate credentials with unknown prior scope, and create only the least-privilege Environment-scoped credentials needed by a later approved executor.
4. Verify the exact Production project ref with the Supabase owner/admin and provide read-only migration-history/catalog access. Do not grant write, service-role, migration-repair, or delivery authority for this evidence step.
5. Complete the migration baseline, duplicate-007 decision, full replay, backup/restore evidence, and independent reviews.
6. Only after all prior gates pass, propose a separate replacement migration workflow with explicit `--remote`, target verification, migration-history preflight, backup evidence, protected Environment approval, exact pinned CLI, and rollback plan. Do not resurrect the legacy workflow or merge PR #10 as-is.

CI evidence at this snapshot:
- PR #13 exact head `ae04e009c4242abd5db1d66d41e65a003e8f73c2`, PR Validation run #631 (`44901634490`): **FAILURE, 3/5 jobs passed**. `validate` failed `npm audit --audit-level=high` with 21 findings (12 moderate, 7 high, 2 critical), so TypeScript, Next.js build, and Cloudflare packaging were skipped. `gentle_delivery_transport_database_behavior` failed at `scripts/test-gentle-delivery-transport.sql:96` with `Delivery claim is not authorized.`; the other three database jobs passed. Branch-push run #630 also failed. Do not describe PR #13 CI as green.
- PR #15 exact head `1ce6213d1077a64d2a04d49949bb8302e243902a`, PR Validation run #627 (`44899977780`): **SUCCESS, 5/5 jobs passed**. This includes pinned CLI setup/version verification, Supabase CLI target security tests, dependency verification and moderate audit, TypeScript, Next.js build, Cloudflare packaging, and all four database behavior jobs. This is branch-only evidence; PR #15 remains unmerged.
- No formal submitted GitHub reviews were found for PRs #10, #11, #13, or #15.

No Production database was queried or changed during C275. No workflow was dispatched, no credential was read or changed, no Environment/branch-protection setting was changed, no migration or repair was run, and no PR was approved or merged. Production remains **NO-GO**.

### C275 documentation rollback

This C275 change is documentation-only on the existing PR #13 branch. If its wording is incorrect, revert only the C275 addendum in a new commit on that branch. Do not reset or force-push, do not restore the legacy migration workflow, and do not change database, credentials, Environment, or deployment state.

## C277 — Governance review corrections (2026-11-22)

This correction supersedes the stale PR #13 metadata and the inventory wording in C275. It records repository evidence and governance requirements only; it does not authorize a Production migration or any administrator operation.

### Exact revision and migration-inventory provenance

The live refs were re-read before this change:

| Ref | Exact commit | Exact tree | SQL migration files | Distinct filename version prefixes |
|---|---|---|---:|---:|
| PR #10 candidate source | `9072f3b8824ec9618849def1c0832000cd130474` | `e911e1b806e08fc80954526917c7a44796b741ba` | 31 | 30 |
| `main` | `ce82b3fdf1a73510de70e3729a487d4ae00e66e3` | `f7ada8719e9e9f4212f3bc53ae9ebb6b012554cc` | 23 | 22 |
| PR #13 before C277 | `cff11e6e19b3e1d360b8f38fafbf8a26b3782504` | `3e91c407e20525f9c380575f18e6b336dd525a49` | 23 | 22 |

All three recursive Git tree responses were complete (`truncated: false`). PR #13's current pre-change tree has the same 23 migration paths and file blobs as `main`. The PR #10 candidate tree adds the eight later migrations `202611120023` through `202611210030`, which are absent from both current `main` and PR #13. Its 31 SQL files include two different files with version prefix `202607260007`.

The 31-row table in `docs/PRODUCTION_MIGRATION_RECONCILIATION.md` is present at PR #10 source commit `9072f3b8824ec9618849def1c0832000cd130474` (tree `e911e1b806e08fc80954526917c7a44796b741ba`; document blob `9152f79c3bf6466ef443f0c72ad79c126b348284`). Its 31 paths and Git blob SHAs match that exact candidate tree. The document's C247 test-source metadata is historical provenance for earlier test work; it does not replace the exact PR #10 commit/tree pin for this candidate inventory.

Do not describe the 31-file candidate inventory as current `main` or PR #13. The current default-branch and PR #13 inventory is 23 files / 22 prefixes. Neither inventory proves which migrations are present in Production. All Production migration status remains UNKNOWN until independently authorized read-only Production evidence is collected and classified.

### Independent review: CODEOWNERS and team membership

The earlier C275 proposal for two approvals plus CODEOWNERS review is necessary but **does not guarantee one database-team approval and one security-team approval**. Native CODEOWNERS approval is an owner-review requirement, not a per-team approval quorum. Two required approvals can both come from members of the same team; requested team reviewers do not prove that the actual approving users belong to distinct required teams.

Before a Production-sensitive PR can merge, add an independently enforced required check using either a GitHub App/ruleset integration or a trusted base-branch workflow that reads only GitHub PR/review/team-membership metadata. If using `pull_request_target`, it must not check out, execute, import, or otherwise trust PR-head code; use least-privilege read-only permissions and fail closed when reviewer/team membership cannot be verified. Bind the required check to the trusted GitHub Actions/App source.

The check must verify all of the following against the current PR head and latest push:

1. Two distinct, current approving users other than the PR author.
2. At least one approver is a current member of the designated database/migration review team.
3. A different approver is a current member of the designated security review team.
4. Neither approval was invalidated by a later commit, dismissal, or changed review state.
5. Team membership and reviewer identity are read successfully; API errors, inaccessible teams, ambiguous membership, or missing evidence fail the check.

Keep the two-review requirement, CODEOWNERS requirement, stale-review dismissal, latest-push approval, and resolved-conversation requirement. Do not claim that those native settings alone enforce the database/security split.

### Production Environment: exact branch and author exclusion

Configure the `production` Environment deployment branch policy as **Selected branches and tags**, with the one exact allowed branch name `main`. Do not choose the broader **Protected branches only** policy: it would allow any branch that happens to be protected, not only `main`. Do not add wildcards, tags, release branches, or feature branches. Retain the workflow's defense-in-depth checks for `GITHUB_REF=refs/heads/main` and `GITHUB_REF_PROTECTED=true`; they do not replace the server-side Environment policy.

The native Environment **Prevent self-review** setting prevents the person who initiated a deployment from approving that same deployment. It does **not** guarantee that the PR/change author is excluded if a different person initiated the workflow. Therefore explicitly require the change author to be different from the Production deployment approver. Enforce this with a trusted deployment protection rule/check that reads the deployment's originating PR/commit author and approval identity and fails closed if they match or cannot be established. Keep Environment approval before any Production secret is exposed to the job. Native required reviewers still provide an at-least-one-reviewer gate, not a two-reviewer quorum.

### Supabase PAT scope does not constrain database-password privileges

A project-scoped Supabase Personal Access Token (PAT) limits the Supabase Management API operations available to that token. It does **not** narrow the PostgreSQL privileges of the database role authenticated by `SUPABASE_DB_PASSWORD`. The CLI's PAT and the database password are separate credentials and separate authorization planes.

Before any future Production migration executor is approved, independently identify the PostgreSQL role authenticated by the password and inspect its role memberships, superuser/bypass-RLS attributes, object ownership, schema/database privileges, and ability to create/alter/drop objects. Do not infer database least privilege from a PAT's project scope. Prefer a dedicated migration principal with the minimum DDL and migration-history privileges actually required. If the CLI or migration contents require a broad owner/postgres role, document that privilege explicitly, restrict credential availability to the approved protected Environment and approved workflow, and obtain a separate risk acceptance; if the effective DB privileges cannot be established, fail closed and do not migrate. Never place either credential in PR jobs or expose it to untrusted checkouts.

### Pending administrator actions — no completion evidence yet

The following are explicitly **PENDING**, not completed:

| Action | Current evidence | Status |
|---|---|---|
| Retire the legacy migration workflow from the default branch | `main` still contains `.github/workflows/supabase-migrations.yml` (blob `c47dfc061bb25ea4d9266e7e110ffdb2bb9665e3`). PR #13 deletes it, but PR #13 remains open and unmerged. | PENDING |
| Inspect repository and organization secret names/scopes | The connected GitHub integration does not expose secret-administration APIs; no administrator evidence was supplied. No secret values were read. | PENDING |
| Rotate/revoke legacy credentials after scope inspection | No credential was read, rotated, revoked, or replaced in this task. No administrator evidence of rotation exists. | PENDING |

The PR #13 branch's removal of the workflow is a proposed repository change only. It has not disabled the workflow on `main`; do not describe legacy workflow retirement as complete until the deletion is merged through the required review/CI process and the resulting default-branch state is verified. Repository/organization secret scope inspection and any required credential rotation must be performed by an authorized administrator, with evidence limited to secret names, scopes, timestamps, and rotation confirmation—not values. If scopes cannot be established, rotate through the authorized secret owner rather than assuming the credentials were Environment-scoped.

No repository/organization secret was inspected or changed in C277. No credential was rotated or revoked. No branch protection or Environment setting was changed.

### Existing migration, backup, restore, and rollback safeguards retained

C277 changes documentation only. It does not alter or waive the C275 requirements for a complete read-only Production history/catalog evidence set, file/effect-level classifications, duplicate-007 resolution, independently reviewed baseline, disposable full replay, explicit remote-target verification, pre-migration backup and restore testing, Storage object backup where applicable, RPO/RTO, or a migration-specific forward-fix/restore plan. Ambiguous, partial, unparseable, or unverified Production state continues to block migration. No blind `migration repair`, `--include-all`, `db reset`, fallback target, or automatic rollback is authorized.

### C277 execution boundary

- Existing PR #13 base remains `main`; no branch recreation, retarget, force-push, merge, or approval was performed.
- PR #10 remains a separate open draft and is used only as the pinned candidate inventory source described above.
- No Production database access, SQL, migration execution, deployment, Cron activation, delivery activation, or outbound send occurred.
- No GitHub administrator settings or credentials were changed.
- Production remains **NO-GO**.

C277 rollback is documentation-only: revert the C277 documentation commit or remove only this C277 section and its two C277 corrections in a new commit on the existing PR #13 branch. Do not reset/force-push, restore the legacy workflow, change administrator settings, or alter Production.


### C277 exact-head CI evidence

The governance correction content commit was `ee38e78ce674ce9c4b0bd86f44bd521fa4e3c5a4`, tree `045d34b3b66119f3865f90216ef0386dd9889aef`, parent `cff11e6e19b3e1d360b8f38fafbf8a26b3782504`. Its only changed file was `docs/PRODUCTION_MIGRATIONS_DISABLED.md`; no SQL, workflow, application code, package manifest, or lockfile was changed by this commit.

Fresh exact-head runs against that commit:
- Push run #839 (`45006550188`): **FAILURE, 3/5 jobs passed**.
- Pull-request run #840 (`45006554626`): **FAILURE, 3/5 jobs passed**.

Both runs checked out exact HEAD `ee38e78ce674ce9c4b0bd86f44bd521fa4e3c5a4`. In each run, `sprint12_2_database_behavior`, `delivery_reliability_database_behavior`, and `auth_pgcrypto_database_behavior` passed. `gentle_delivery_transport_database_behavior` failed at `scripts/test-gentle-delivery-transport.sql:96` with `Delivery claim is not authorized.`. `validate` failed `npm audit --audit-level=high` with 21 findings (12 moderate, 7 high, 2 critical); TypeScript, Next.js production build, and Cloudflare packaging did not run after the audit gate failed.

These are inherited blockers, not regressions introduced by the documentation change: parent-HEAD C275 runs #837 (`45004272339`) and #838 (`45004278926`) on `cff11e6e19b3e1d360b8f38fafbf8a26b3782504` failed the same two jobs with the same audit counts and the same SQL authorization error. Do not report TypeScript, Next.js build, or Cloudflare packaging as passing; those checks were skipped. Exact-head CI is **not green**.
