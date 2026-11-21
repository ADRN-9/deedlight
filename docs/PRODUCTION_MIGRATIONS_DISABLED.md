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
