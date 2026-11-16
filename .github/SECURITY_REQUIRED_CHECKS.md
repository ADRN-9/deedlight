# DeedLight — C105 security required-check manifest

Repository: ADRN-9/deedlight. Source ancestor C103: 136e467927269196a97d028feb6f00987f30b257 (tree 0f2894e678082e1410ac10374d7adfe9a3660134).

## Stable PR check identities

All 12 jobs below belong to .github/workflows/pr-validation.yml (PR Validation). The workflow runs for pull_request targeting main and non-main push, uses only contents: read permissions, and has no deployment steps. A GitHub check may be displayed with a workflow-name prefix; record the actual context in a test PR.

| Job/check ID | Exact coverage | Required outcome |
| --- | --- | --- |
| validate | Static consent/delivery assertions, TS, Next build, Cloudflare package, high/critical npm audit | success, source receipt |
| sprint12_2_database_behavior | Sprint 12.2 SQL | success, source receipt |
| delivery_reliability_database_behavior | Delivery reliability SQL | success, source receipt |
| gentle_delivery_transport_database_behavior | Consent SQL and concurrency race | success, source receipt |
| auth_pgcrypto_database_behavior | Auth/pgcrypto SQL | success, source receipt |
| delivery_migration_order_database_behavior | 023/024 ordering and rollback | success, source receipt |
| release_privacy_pg16 | All 64 named C83/C101 cases, actual full 001–034 PG16 installation | success, case inventory and logs |
| release_action_privacy | All 19 named C103 actual server-action/UI tests | success, exact TAP inventory and logs |
| release_provider_pg16 | 019–033 synthetic provider/registry and C77 post033 checks | success, PG16 logs and receipts |
| release_consent_races | Daily/Weekly claim isolation and provider/recipient concurrency races | success, preserved race logs |
| release_webhook_http | Signed webhook, provider contract and synthetic HTTP route | success, PG16 and Node logs |
| release_security_gate | Aggregates all 11 jobs and downloaded artifacts | success only if every dependency succeeds and 11 artifacts have correct SHA/tree, PASS receipt, complete evidence and 64/19 inventory. Runs 10 negative self-tests. |

Every prerequisite must produce its own unique release-evidence-* artifact and exact commit/tree receipt. The final aggregator runs with always(), rejects all missing, failed, skipped, cancelled and neutral dependent jobs and mismatched source evidence. Missing evidence fails the gate. Cancellation of the whole workflow can prevent the gate itself from running; a required absent check must block merging.

## GitHub administrator handoff — NOT PERFORMED

1. Resolve Cloudflare automatic Production promotion before any merge. Disable/fence automatic default-branch deployment under separately approved release control.
2. Protect main, and restrict edits to all workflow definitions, security test/verification scripts and migrations using CODEOWNERS and mandatory review/rulesets. The release gate cannot defend against malicious PR changes to itself without branch protection.
3. Open a safe nonproduction PR against main and inspect the exact observed check-run name of release_security_gate. Register that context as required, explicitly bound to the verified github-actions producer (historically App ID 15368), and require current head/merge checks. Optionally require each of the 11 dependency check contexts as defense in depth.
4. Verify mandatory enforcement using safe intentionally failed, missing, and cancelled PR checks; confirm merges remain blocked. Record check-run identities, source SHA/tree, CI attempts, artifacts and reviewer decisions.
5. Repeat this review whenever workflow/job names, migrations, Node, database or build procedures change.

## Preserved risks and boundaries

C101 and C103 branch-specific evidence workflows retain historical push triggers but have no main-targeted pull_request trigger in the C105 candidate; no historical branches are rewritten. Original 64 privacy assertions, 19 action tests and the C101 migration are untouched. Historical PR11 findings (including failures, unknown and blocked cases) remain unresolved; post033 compatibility PASS does not relabel them. Nine moderate dependencies remain pending risk disposition. Historical duplicate 202607260007 and inaccessible Production Supabase schema/history remain unresolved.

Workflow checkout uses ephemeral read-only GitHub credentials and synthetic PostgreSQL 16 and provider records, no pull_request_target, no Production secrets, no external send, no Cron, no Cloudflare deployment. Real Supabase/Auth/Storage HTTP, Production rollout, backup/restore, rollback, monitoring and kill switch remain unproven. Branch protections not enabled by this change. Production NO-GO; DELIVERY_ENABLED remains false.
