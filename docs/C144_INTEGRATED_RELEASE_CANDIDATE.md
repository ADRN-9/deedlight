# DeedLight C144 — Integrated release candidate and migration 034 compatibility

## Candidate identity and source ownership

Repository: ADRN-9/deedlight  
Integration branch: work/deedlight-c144-integrated-release-20261118  
Starting commit: 40626848e8bc8354edcaf0099b26a18a90af4166  
Starting tree: 99e0e847e0e477c6e78d5510a3ca32d9402c4cad  
Main baseline: ce82b3fdf1a73510de70e3729a487d4ae00e66e3

The source history is linear and already integrated:

| Candidate | Commit | Relationship |
|---|---|---|
| C103 | 136e467927269196a97d028feb6f00987f30b257 | Ancestor |
| C105 | 4029f0c69833efb42d3fd4950dfb18958d0bafb9 | Two commits after C103 |
| C107 | 40626848e8bc8354edcaf0099b26a18a90af4166 | Two commits after C105 |

C107 contains C103 and C105. The new C144 branch is isolated from these shared candidate branches. The authenticated GitHub account matches the authors of the inspected candidate commits; neither candidate branch is the head of an open PR. GitHub does not expose an active-agent lock, so concurrent external work cannot be ruled out. No shared branch was modified.

PR #10 remains open/draft at c983e2ed8b93c935139c935343261570ecea6978. PR #11 remains open/draft at aed588d771dc04fda5e5c18d8611239ac926a513. Neither is merged or included by this assignment.

## Integrated source changes already present

C103 supplies:
- Member-facing Offering projection without staff-only moderation_note or open_report_count.
- Separate owner_feedback and internal moderation_note handling.
- Database-authorized admin_list_offerings RPC usage.
- Owner Journey and Offering actions through narrow RPCs.
- C101 migration 034 and 64 PostgreSQL privacy assertions.
- C103 server-action and owner-render tests (19 cases).

C105 supplies:
- .github/SECURITY_REQUIRED_CHECKS.md.
- Required security-check inventory and release gate checks.
- Exact privacy/action inventory verification.

C107 supplies:
- Attempt-specific producer receipts.
- GitHub run/attempt/job/artifact metadata verification.
- Strict rejection of missing, stale, duplicated, mixed-attempt or mismatched evidence.
- Expanded tamper tests and a mandatory release_security_gate aggregate.

C105/C107 changes are already in the C107 ancestor chain; they were not cherry-picked or rewritten.

## Four-way migration 034 compatibility matrix

| Application | Database | Disposition | Reason |
|---|---|---|---|
| Existing pre-C103 application | Existing pre-034 schema | Historically compatible, privacy-defective | The old Offering queries select adminOfferingColumns directly, including moderation_note and open_report_count. The historical broad Offering SELECT policy permits the old query shape, but exposes staff-only fields and the legacy approved/own Offering row surface too broadly. |
| Corrected C103/C107 application | Pre-034 schema | Incompatible; do not release | The corrected owner projection requires owner_feedback, which does not yet exist. Corrected admin reads call admin_list_offerings, which migration 034 creates. |
| Existing pre-C103 application | Post-034 schema | Incompatible; do not release | Migration 034 revokes authenticated SELECT on moderation_note and open_report_count and removes the broad offerings_select_public_or_own policy. The old admin/member table queries still request those private columns directly. |
| Corrected C103/C107 application | Post-034 schema | Intended release combination | The owner projection selects owner_feedback but not internal notes/report counts; authorized admin reads use admin_list_offerings; migration 034 enforces restricted Offering columns and owner-only Journey policies. |

### Executable compatibility guard

scripts/test-c144-migration-034-compatibility.mjs reads the exact main and C103 Git objects, verifies the four source contracts, checks the C101 preflight/postcheck and owner/admin separation, and confirms the duplicate 007 migration files and migration 034 retain their exact historical blob identities. It is wired into PR Validation and the aggregate gate's mandatory validate-step list.

The duplicate migration version remains unresolved. This guard preserves the two historical files and prevents silent renaming or content edits; it does not claim Supabase CLI compatibility or repair migration history.

## Coordinated deployment boundary

There is no safe rolling deployment sequence using only the existing and corrected application versions: each application version is incompatible with one of the two database states. Production must remain gated during the schema/application cutover.

1. Obtain independently verified Production schema/history evidence, a current backup/restore point, and an approved maintenance window.
2. Confirm the exact C101 preflight state against the live schema; do not infer it from a historical snapshot.
3. Stop or gate member/admin application traffic and background access that could use the old schema contract.
4. Apply migration 034 through the separately reviewed, explicitly authorized migration procedure. Do not use normal Production supabase db push while history is unreconciled.
5. Deploy the corrected application built from the exact reviewed C144 release commit.
6. Verify public/anonymous projections, owner feedback visibility, internal moderation-note denial, administrator moderation, Journey isolation, and suspended-member behavior against the actual Production database and PostgREST.
7. Reopen traffic only after both schema and application identities are verified.

If migration 034 fails before commit, its transaction should roll back; investigate the preflight mismatch and retry only after review. If migration 034 commits but application deployment fails, keep traffic gated and forward-deploy a corrected compatible application. Do not restore the old application against the post-034 schema. A database restore is a separately approved recovery operation and must be coordinated with application version and data-loss assessment.

## Validation and evidence status

The existing C103 run 43801578493 (attempt 2) was independently inspected: PostgreSQL 16.16, 64/64 SQL privacy scenarios passed, 0 failed, with a 19-case application suite in the release workflow design. That run is tied to C103, not C144.

C144 adds a CI source-contract guard to the C107 release validation path. The C144 commit must receive its own fresh PR Validation run. Do not reuse C103/C105/C107 artifacts as C144 acceptance evidence.

The full C107 release gate requires:
- TypeScript, Next.js production build and Cloudflare package.
- PostgreSQL 16 installation of the exact 001–034 migration chain and 64 privacy assertions.
- 19 application privacy/action tests.
- Provider, consent-race and webhook evidence.
- Exact source SHA/tree and attempt-specific GitHub artifact provenance.

The disposable PostgreSQL workflow applies sorted SQL files with psql. This validates the schema/application behavior on the fixture, but it does not validate Supabase CLI migration history. Duplicate version 202607260007 still prevents treating normal CLI migration ordering as reconciled.

## Changed files in C144

- .github/workflows/pr-validation.yml — full-history checkout and mandatory compatibility guard.
- scripts/verify-release-security-gate.mjs — require the new validation step in the aggregate.
- scripts/test-c144-migration-034-compatibility.mjs — four-way source-contract and historical migration identity guard.
- .github/SECURITY_REQUIRED_CHECKS.md — C144 gate and compatibility notes.
- docs/C144_INTEGRATED_RELEASE_CANDIDATE.md — this integration and release report.

No application source or historical migration is modified by C144.

## Blockers and release disposition

- Production Supabase project xaipiovflxomcbfwtwmu was not accessible to the available read-only Supabase connection during C143. Current live schema and migration history remain unverified.
- Duplicate 202607260007 prevents a clean Supabase CLI migration-history reconciliation. Do not rename or edit either historical migration until Production effects are proven.
- Branch protection, required-check enforcement, CODEOWNERS, Cloudflare promotion fencing and Production cutover remain independent administrator/release gates.
- No Production migration, db push, deployment, scheduler activation or external send is authorized or performed here.

Production disposition: NO-GO.

## Recommended C145

Run the new C144 CI and review its exact commit/tree and artifact evidence. Then obtain Production read-only schema/history evidence and design a forward-only duplicate-prefix reconciliation that preserves historical migration identities. Do not proceed to Production mutation until the migration plan, C101 preflight, maintenance-window cutover and rollback/forward-recovery approvals are complete.
