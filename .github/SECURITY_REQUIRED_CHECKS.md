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


## C107: Workflow-run provenance and evidence ownership

The eleven prerequisite jobs write a deterministic receipt.json in addition to the
preexisting SHA/tree, PASS and test-specific artifacts. Required receipt keys:
version=1, repository, workflow, job, run_id, run_attempt, source_sha,
source_tree, artifact_name. The artifact name is
release-evidence-<job>-run-<GITHUB_RUN_ID>-attempt-<GITHUB_RUN_ATTEMPT>.
All names are stable job IDs and attempt-scoped; artifacts are never overwritten.

The aggregator uses GitHub's trusted GITHUB_RUN_ID and GITHUB_RUN_ATTEMPT
contexts and a read-only GitHub Actions token scoped to the metadata step. It
queries the attempts/{attempt} run object, the attempts/{attempt}/jobs endpoint,
and the complete run's artifacts registry. The metadata endpoint response is
not a producer-written attestation. It must confirm the exact SHA, attempt,
all eleven successful job records, expected test steps and upload steps,
artifact names/IDs/digests, run identity and creation timestamps compatible
with the individual producing job window. The downloaded evidence directories,
receipts and inspected content must agree with these platform records.

The gate requires precisely eleven matching release-evidence artifacts in the
run-level registry. Retained attempt-1 artifacts cause an attempt-2 rerun to
fail closed: a same-run rerun cannot rely on old results and cannot silently
replace previous evidence. Use a fresh workflow run rather than deleting old
evidence without separate authorization. Rerunning a failed job within the
same run is deliberately not an approved shortcut. This sacrifices easy
workflow reattempts to avoid false acceptance from retained artifacts.

The API does **not** identify the producer job of an artifact cryptographically.
The current check establishes a matching expected artifact name, current
attempt-specific job status, platform artifact workflow_run, creation window,
producer canonical receipt and content, but cannot prove a malicious job with
the same run's privileges did not upload an artifact on another job's behalf.
The CI runner and mutable PR-controlled source are not a secure attestation
root. Required main protection, CODEOWNERS approvals for workflows/security
scripts, and registered trusted GitHub Actions checks remain independent
administrator gates.

The aggregator verifies exact required race files and PASS-marked JSON for
all Daily/Weekly claim, suppression and provider/consent races; validated
signed webhook test counts, synthetic real-provider-calls=0 and C77 provider
key fencing; and computes hashes for every inspected required file. The
provider fixture name is c77-post033.log. All prior 64 SQL/19 application
tests and the earlier ten tamper tests remain mandatory, with additional
provenance, identity, artifact-mixing, malformed metadata and missing-content
adversarial probes, including a passing current-attempt positive control.

Action pins verified against upstream GitHub tag refs on the C107 assignment:
- checkout v7 => 3d3c42e5aac5ba805825da76410c181273ba90b1
- setup-node v7 => 949feb2413d6458794dcd2491c4babbbce0c15c1
- upload-artifact v4 => ea165f8d65b6e75b540449e92b4886f43607fa02
- download-artifact v4 => d3f86a106a0bac45b974a628896c90dbdf5c8093

These pins cover PR Validation only; historical branch-specific and
manual/Production workflows are not silently changed in this cycle.
The gate job alone receives actions:read and contents:read permissions. All
other jobs retain contents:read. Never use pull_request_target on untrusted
application code. No Production deployment, provider sends, or migration
history changes are authorized by these CI controls.

## C144 — Migration 034 application/schema compatibility

The validate job now checks the four-way legacy/corrected application versus pre/post-034 database matrix using exact main and C103 Git objects. It verifies the corrected member-safe Offering projection, distinct owner_feedback/moderation_note contracts, authorized admin RPC, C101 preflight/postcheck and owner-only Journey policies. It also asserts the exact historical blob identities of both 202607260007 migrations and migration 034. The aggregate release gate requires the named C144 compatibility step to succeed.

The guard is source-contract evidence, not a live database or Supabase CLI migration-history test. The disposable PostgreSQL 16 job still applies the exact SQL chain with psql. Duplicate version 202607260007 remains a known CLI blocker; neither historical file is renamed or edited. Production remains NO-GO until live schema/history, cutover approvals and all exact-head checks are verified.

