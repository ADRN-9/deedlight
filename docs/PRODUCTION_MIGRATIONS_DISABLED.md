# Production Supabase migrations temporarily disabled

**Status:** Proposed by PR #13. After this PR is merged, the default branch will no longer contain a GitHub Actions Production migration workflow. Until the PR is merged, `main` still contains the legacy workflow; do not dispatch it or run Production migrations. The hotfix branch deletes that workflow until the repository's independent GitHub protections and historical Supabase migration reconciliation are complete.

## Why the workflow was removed

The legacy `.github/workflows/supabase-migrations.yml` exposed repository-level `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, and `SUPABASE_PROJECT_REF` to a manually dispatched workflow that ran `supabase link` and `supabase db push`. It had no independent Environment approval or deployment-branch boundary. The default `main` branch was reported as unprotected when this hotfix was prepared.

The workflow has therefore been removed rather than replaced with a branch-controlled check. No GitHub Actions workflow currently provides a Production migration path.

## Other workflow review

At the time of this hotfix, the repository contained three workflows:

- `pr-validation.yml` runs application/security/database tests with non-Production configuration. It does not reference Production migration secrets or invoke `supabase db push`.
- `vm-self-hosted.yml` runs a constrained feature-branch validation workflow. It explicitly checks that Supabase service-role, access-token, database-password, and project-ref environment variables are unset. It does not invoke `supabase db push`.
- `supabase-migrations.yml` was the only workflow referencing the repository-level Production migration credentials; it has been deleted.

This is a review of the checked-in workflow files, not a claim that repository/org secrets have been deleted or that runner environments have been independently audited.

## Conditions before Production migrations can be re-enabled

Do not restore a Production migration workflow or run Production `supabase db push` until all of the following have been completed and independently evidenced:

1. Protect `main` with appropriate required review and status-check rules.
2. Configure the GitHub Environment `production` to require approval by an independent reviewer, prevent self-review, and allow deployments only from protected `main`.
3. Move the required Production Supabase credentials into Environment-scoped secrets only, and remove repository/org-level copies of those credentials.
4. Independently verify the saved branch-protection, Environment approval, deployment-branch, and secret-scope settings.
5. Separately reconcile the historical Production schema with Supabase CLI migration history using evidence from the live schema. Do not blindly mark unverified migrations as applied.
6. Submit and review a narrowly scoped migration-workflow change that preserves both the pre-link target-project guard and post-link linked-project guard, and relies on the server-side Environment policy as the credential boundary.

Until those gates are met, Production migrations remain disabled. Non-Production database testing through isolated CI services may continue.

## Relationship to PR #10

PR #10 contains a proposed replacement workflow at the same path, `.github/workflows/supabase-migrations.yml`. This hotfix intentionally deletes that path on `main`. The two PRs are expected to conflict on that file. If PR #10 is rebased or otherwise updated after this hotfix, resolve the conflict by retaining the deletion until the administrator-owned protections and migration-history prerequisites above are independently complete. Do not restore the proposed workflow merely to make the conflict disappear.

