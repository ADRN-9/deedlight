# Deedlight outbound delivery rollout tracker

**Status: PRODUCTION NO-GO.** This tracker separates repository evidence from Production evidence. A green CI run does not prove live consent, provider, scheduler, ledger, or kill-switch behavior.

## Current code and review state

- Delivery-security branch: `security/delivery-transport-consent-gates`.
- Historical C225 independent-review target: HEAD `2d5d00371409a151c7c2ce23cb978b2eaa867e91`, tree `64253539093d9057a571c8a3103766292cf370ce`, base `ce82b3fdf1a73510de70e3729a487d4ae00e66e3`.
- Historical C234/C236 verification HEAD: `69fe2b9d766a448644736c3ae2174f3bffece36f`, tree `17a79801ed2effe0901dbcf78c41419ebc10a2f9`, parent `cb82b3b31311eef2a8f177ff22998b99c74371dc`.
- PR #10 remains OPEN, DRAFT, UNMERGED. C222 added SQL ACL assertions for the private provider lifecycle implementation; commit `2d5d00371409a151c7c2ce23cb978b2eaa867e91`.
- Migrations 028 and 029 are part of the reviewed delivery path. C226 adds migration 030 for database-authoritative provider idempotency timing and validated Resend receipts.
- C225 findings: HIGH — migration 029 trusted a matching signature without proving migration-027 implementation identity; MEDIUM — Worker-clock skew could underestimate provider idempotency age; MEDIUM — provider receipt IDs were accepted without format validation.
- C226 remediation: migration 029 pins the migration-027 PL/pgSQL source SHA-256 and verifies SECURITY DEFINER/search_path metadata; migration 030 moves retry/horizon decisions to PostgreSQL `clock_timestamp()`, checks persisted `transport_started_at`, and validates provider UUID receipts before the sent transition. C230 exact-head CI and C231 independent-review disposition are recorded below; these establish engineering acceptance only, not Production acceptance.
- Read-only GitHub inspection reports `main.protected=false` and no repository rulesets; main branch protection is therefore not established. Production Environment branch restrictions/required approvals and Production secret scoping remain unverified.
- No Production migration, provider send, webhook configuration, Cron activation, secret change, or kill-switch mutation is part of this work.

## C234 / C236 historical verification and governance baseline

- C234 independently retrieved the live branch ref, commit tree, and PR #10 description: branch and PR source HEAD both `69fe2b9d766a448644736c3ae2174f3bffece36f`; tree `17a79801ed2effe0901dbcf78c41419ebc10a2f9`; parent `cb82b3b31311eef2a8f177ff22998b99c74371dc`. The saved PR description was corrected to include the C231 disposition and current CI evidence. PR #10 remains OPEN / DRAFT / UNMERGED.
- Current branch-push validation #756 ([run 44946311015](https://github.com/ADRN-9/deedlight/actions/runs/44946311015)) completed SUCCESS, 7/7, and its job log checked out the branch ref at exact HEAD `69fe2b9d766a448644736c3ae2174f3bffece36f`.
- Current PR validation #757 ([run 44946317002](https://github.com/ADRN-9/deedlight/actions/runs/44946317002)) completed SUCCESS, 7/7. It checked out synthetic PR merge commit `e399431d4898706d3cabce61936e40707d3af81d`, with base `ce82b3fdf1a73510de70e3729a487d4ae00e66e3` and branch HEAD `69fe2b9d766a448644736c3ae2174f3bffece36f` as parents. This is merge-result integration validation, not direct branch-head validation.
- Both runs passed the seven CI jobs: Validate, Sprint 12.2 database behavior, delivery reliability database behavior, delivery migration-order database behavior, gentle delivery transport database behavior, Auth pgcrypto database behavior, and provider-webhook database behavior. Validate passed security checks, webhook/transport tests, ESLint, TypeScript, Next.js production build, Cloudflare packaging, and the configured high/critical npm audit threshold. The audit still reports **9 moderate** advisories; preserve them as tracked maintenance work.
- C236 repository metadata reports `permissions.admin=true` for the connected GitHub identity. Read-only main-branch metadata nevertheless reports `protected=false` and `protection.enabled=false`; the repository rulesets list is empty. The connected GitHub toolset exposes no branch-protection or ruleset write operation, so C236 made no governance changes.
- Production workflow reference inventory (names only; no secret values retrieved): `.github/workflows/supabase-migrations.yml` references `PRODUCTION_SUPABASE_ACCESS_TOKEN`, `PRODUCTION_SUPABASE_DB_PASSWORD`, and `PRODUCTION_SUPABASE_PROJECT_REF` as secrets, plus `PRODUCTION_MIGRATION_ENVIRONMENT_GUARD` as an Environment variable. The other two workflow files (`pr-validation.yml` and `vm-self-hosted.yml`) contain no `PRODUCTION_*` secret/variable references. These source references do not establish where values are configured. The connected GitHub toolset cannot enumerate Environment protection or secret scopes; Environment approvals, selected deployment branches, self-review prevention, and actual credential scopes remain UNVERIFIED.
- No branch-protection/ruleset, Environment, secret, credential, Production, migration, deployment, Cron, or PR approval settings were changed. Production remains NO-GO.

## C238 — provider webhook lifecycle reliability

- Independently retrieved the branch and PR #10 at starting HEAD `33af18e3557be3c28e7fba79e2195257d8e22e28`, tree `a3063ed1a6748b16c9a31ea1652f5aac2385ef6b`; PR #10 was OPEN / DRAFT / UNMERGED.
- Existing webhook implementation and test inventory reviewed: `app/api/webhooks/resend/route.ts`, `lib/delivery/resend-webhook.ts`, route/parser tests, SQL lifecycle/suppression tests, synchronized provider-webhook concurrency tests, verifier, migrations 025–030, and this rollout contract.
- Existing automated coverage already exercises raw-body Svix HMAC and timestamp checks, bounded bodies, all seven lifecycle events, permanent/transient/unknown bounce behavior, complaints, provider suppression, complaint precedence, duplicate event IDs, full-body fingerprint conflicts, provider-email-ID recipient binding, out-of-order events, contradictory terminal outcomes, RLS/ACLs, no queue mutation, batch exclusion, final transport authorization, and suppression/transport lock ordering.
- Focused gap fixed: the route now wraps Supabase client creation and lifecycle RPC execution in a no-log exception boundary. Unexpected thrown client/network errors return an empty-body HTTP 503, preserving provider retry behavior without leaking provider/database details. The route regression suite simulates a rejected database fetch and asserts the 503 response.
- Implementation commit: `6521703d024779846017497900b9fd8e5d68928f`; tree `2eb7bba022ebcb2bed85290d27f680eb979007f3`; parent `33af18e3557be3c28e7fba79e2195257d8e22e28`. Changed only `app/api/webhooks/resend/route.ts` and `scripts/test-delivery-webhook-route.mjs`.
- Exact-head branch-push validation #760 ([run 44950453015](https://github.com/ADRN-9/deedlight/actions/runs/44950453015)): **SUCCESS, 7/7** at exact branch HEAD `6521703d024779846017497900b9fd8e5d68928f`. Its Validate log confirms the new `returns 503 when the database transport rejects before a response` test passed; security assertions, webhook parser/route behavior, ESLint, TypeScript, Next.js build, Cloudflare packaging, and high/critical npm audit gate passed. The audit still reports **9 moderate** advisories.
- Exact-head PR validation #761 ([run 44950459277](https://github.com/ADRN-9/deedlight/actions/runs/44950459277)): **SUCCESS, 7/7**. The PR job checked out synthetic merge commit `4d5b40f3cb0fba346625fd618db7fe27ed0ea25e`, whose tree is `2eb7bba022ebcb2bed85290d27f680eb979007f3` and whose parents are base `ce82b3fdf1a73510de70e3729a487d4ae00e66e3` and source HEAD `6521703d024779846017497900b9fd8e5d68928f`. This is merge-result integration validation, not a second direct branch-head checkout.
- Migrations 025–030 were not modified. Current blob SHAs remain: 025 `e97c5c0ad645dfe43f11a88f01b030fa23dd5822`; 026 `6a06d780ad65babf2293a2746c68913758313af8`; 027 `a1469938ea13b5cb9d7cd883772bc60e4a058026`; 028 `09d1927fba81d711bb37d214609931d2da2173a1`; 029 `872fc49ec47e49b17e96ecf6ccaf5c8eb0e6322a`; 030 `42c227cc1c36b2889e88d9bee1432e6fc6829d41`. The migration-027 source fingerprint pin in 029 and the database-authoritative timing/receipt checks in 030 remain intact.
- CI uses synthetic fixtures and local PostgreSQL only. No real Resend send, Production webhook configuration, Production database mutation, Cron activation, or kill-switch mutation was performed. Live provider failure/bounce/complaint evidence remains absent; Production stays NO-GO.
- C238 rechecked governance: repository metadata reports `permissions.admin=true`, but `main.protected=false`, `protection.enabled=false`, and the repository rulesets list is empty. The available GitHub integration exposes no branch-protection/ruleset write operation. Environment deployment restrictions, required reviewers/self-review prevention, and actual secret scopes remain UNVERIFIED.
- Workflow reference inventory (names only; no values retrieved): only `.github/workflows/supabase-migrations.yml` references `secrets.PRODUCTION_SUPABASE_ACCESS_TOKEN`, `secrets.PRODUCTION_SUPABASE_DB_PASSWORD`, `secrets.PRODUCTION_SUPABASE_PROJECT_REF`, and `vars.PRODUCTION_MIGRATION_ENVIRONMENT_GUARD`. `pr-validation.yml` and `vm-self-hosted.yml` have no Production secret/variable references. These code references do not prove storage scope. The administrator-only actions and evidence requirements remain in the Human-only GitHub governance blocker below.
- PR #10 remains OPEN / DRAFT / UNMERGED. No approval, merge, Production operation, or Weekly scheduling was performed.

## Rollout order and gates

| Gate | Required evidence | Current disposition |
|---|---|---|
| Delivery security in CI | Exact-head assertions, fake transport, PostgreSQL behavior and concurrency tests | C238 implementation HEAD `6521703d024779846017497900b9fd8e5d68928f`: branch run #760 `44950453015` and PR run #761 `44950459277` both SUCCESS, 7/7; C231 independent reviewer disposition ACCEPT. CI/reviewer acceptance is not Production acceptance. |
| Provider failure lifecycle | Signed event intake; bounce, complaint, suppression, failure classification and validated Resend receipt UUIDs | C238 exact-head branch/PR CI #760/#761 passes synthetic webhook, suppression, concurrency and receipt tests; live provider evidence absent |
| Duplicate and conflicting events | Event-ID idempotency, payload fingerprint conflicts, provider-ID recipient binding, terminal-outcome anomalies | PostgreSQL and synchronized concurrency fixtures exist; Production unverified |
| Consent before each send | Fresh preference/profile/Auth-email/curated-issue locks in final transport RPC; denial means zero provider calls | PostgreSQL CI proves post-transport-start consent revocation returns `cancelled` / `authorization_revoked` and clears the claim; Production revocation test not run |
| Retry and ambiguous outcomes | Five-minute DB-timed retry, five-attempt cap, stable provider key, DB-clock 23-hour horizon, stale-token rejection | C230 exact-head PostgreSQL CI passes negative two-hour Worker clock skew, 24-hour/1-second expiry, receipt validation and DB-authoritative horizon; Production provider ambiguity evidence absent |
| Daily scheduler | Explicit approval, staged Cron, multiple healthy cycles and ledger/provider reconciliation | NOT ACTIVATED / NOT VERIFIED in C208 |
| Kill switch | Exercise \`DELIVERY_ENABLED=false\`, prove no new enqueue/claim/send, then safe re-enable | NOT EXERCISED in C208 |
| Weekly Goodness | Daily accepted first; explicit curation, 5,000 logical-row cap, separate Cron only after Daily evidence | HELD; no Weekly activation |
| Production regression | Authenticated/unauthenticated journeys, privacy, moderation, DB and Cloudflare checks | NOT RUN in C208 |
| Release | Exact-head CI, authorized deploy, Production smoke, rollout approval | BLOCKED |

## Delivery safety invariants

1. \`DELIVERY_ENABLED\` must remain disabled until a separately approved staged rollout.
2. Daily delivery precedes Weekly Goodness. Weekly stays inactive until multiple healthy Daily cycles, kill-switch behavior, and safe re-enablement are evidenced.
3. Every external attempt must pass current database authorization immediately before transport. Consent, suspension, current confirmed recipient identity, claim token and live lease are checked together. A claim token alone never grants send authority.
4. Resend uses one stable idempotency key per logical ledger job. PostgreSQL calculates retries from persisted first-transport evidence and its own clock; the Worker cannot extend the safe horizon. Ambiguous outcomes fail closed after the 23-hour boundary.
5. Provider webhook events cannot enqueue, claim, retry, or mutate the delivery ledger. Conflicting events remain private integrity anomalies; they never overwrite original evidence or project contradictory terminal outcomes as success.
6. Permanent/unknown bounce, complaint, and provider suppression block subsequent attempts. Transient bounce remains observable but does not suppress.
7. Recipient addresses, provider diagnostics, raw webhook bodies, claim tokens, and service credentials remain private/server-side.
8. Suppression is never cleared automatically. Any manual correction requires independent review and evidence that the address is safe to contact.

## Provider setup — human-only

An authorized operator must create the Resend webhook endpoint, subscribe to the seven supported lifecycle events, store \`RESEND_WEBHOOK_SECRET\` only as a server-side Cloudflare secret, and verify the endpoint is associated with the same Resend account used for outbound delivery. Do not copy the signing secret into source control, client configuration, chat, or logs. Provider test events must be deliberately authorized and must not be used to send real member messages without separate approval.

## Human-only GitHub governance blocker

**Responsible administrator:** the ADRN-9 repository owner (or a delegated GitHub organization/repository administrator with Environment administration rights). A named human approver must be designated before the Production gate can close; no administrator identity is inferred here.

Read-only repository evidence currently shows `main.protected=false` and an empty repository rulesets list. Production Environment branch restrictions, required reviewers, the `Prevent self-review` setting, and secret scopes were not available for independent verification.

The administrator must complete these settings manually:

1. Protect `main`: require PR review and required CI checks, disallow force-push and branch deletion, and require the approved review policy.
2. Restrict the Production Environment to deployments from protected `main` only.
3. Require independent Production Environment approval and enable `Prevent self-review`.
4. Keep Production credentials only in the Production Environment secret store. Remove duplicate Production credentials at repository and organization scope; never expose secret values in evidence.
5. Prevent PR authors from satisfying their own review requirement.

Evidence required to close this blocker: read-only branch/ruleset API output showing `main.protected=true` and required checks/reviews; Environment settings export or screenshots showing protected-main-only deployment, required independent reviewers and self-review prevention; and secret-name/scope inventory proving Production secrets exist only at Environment scope (values redacted). The repository owner/admin must attest the configuration and identify the independent approver.

## Production prerequisites and rollback

Before any migration or activation, independently inspect the live Production schema and reconcile historical Supabase migration history. Do not use normal \`supabase db push\`, mark unknown migrations applied, or reset Production based on repository state.

Rollback is operational and fail-closed: disable new outbound work, remove future Cron triggers, allow already-authorized requests to drain, and reconcile ledger/provider outcomes. Preserve queue and suppression history. Keep the inbound provider webhook available while outbound delivery is disabled; it is a safety intake path, not an outbound activation. Never restore an obsolete consent-bypassing RPC or clear suppression state to make delivery resume.

## C208 evidence ledger

- Pre-C208 exact-head PR #10 validation: [44875441190](https://github.com/ADRN-9/deedlight/actions/runs/44875441190), 7/7 PASS at \`95fb79152243f9581647eae961f3c35cf5d1043b\`.
- Pre-C208 exact-head push validation: [44875436665](https://github.com/ADRN-9/deedlight/actions/runs/44875436665), 7/7 PASS at the same SHA.
- C208 provider-payload compatibility source/test head: `06ca8cf1e21215645bd70dd93f178cd954196929` (tree `fe5e4f98a084d56ee2594fed231b3e8f0d5388f3`). Exact-head [push run 44903890652](https://github.com/ADRN-9/deedlight/actions/runs/44903890652) and [PR run 44903895136](https://github.com/ADRN-9/deedlight/actions/runs/44903895136) both completed **7/7 PASS** at that SHA. All database behavior jobs, provider webhook/concurrency tests, transport revocation races, TypeScript, Next build, Cloudflare packaging, and dependency audit passed.
- No live Production provider, ledger, Cron, consent-revocation, or kill-switch evidence is claimed.

## C226 remediation evidence ledger

- C225 reviewed target: `2d5d00371409a151c7c2ce23cb978b2eaa867e91`, tree `64253539093d9057a571c8a3103766292cf370ce`.
- C222 SQL ACL regression: `scripts/test-delivery-provider-webhooks.sql` asserts effective privileges for `anon`, `authenticated`, and `service_role`, including the renamed private implementation and legacy RPC overloads.
- Historical C222 exact-head validation: [push run 44929835404](https://github.com/ADRN-9/deedlight/actions/runs/44929835404) and [PR run 44929840101](https://github.com/ADRN-9/deedlight/actions/runs/44929840101), both 7/7 PASS at C222 HEAD.
- C226 migration 029 identity regression: migration-order test mutates the migration-027 implementation without changing its signature/security metadata, expects migration 029 to reject and roll back, then restores the original and proves the positive migration path plus 5/7/8-argument historical replay.
- C226 migration 030 regression: isolated PostgreSQL tests cover Worker clock two hours behind, skew beyond the 23-hour safety horizon, expired 24-hour provider retention, pre-send fail-closed behavior, invalid/whitespace/control-character receipt IDs, and missing transport-start evidence.
- C230 exact-head CI: PASS at HEAD `cb82b3b31311eef2a8f177ff22998b99c74371dc`, tree `9415f9da3fe366f1923cd576e70a83db13912e2e`. Branch Push Validation #754 ([44944676676](https://github.com/ADRN-9/deedlight/actions/runs/44944676676)) completed SUCCESS, 7/7 jobs; its `validate`, migration-order, delivery reliability, gentle transport, provider webhook, Sprint 12.2 and Auth pgcrypto jobs all passed. PR Validation #755 ([44944681070](https://github.com/ADRN-9/deedlight/actions/runs/44944681070)) completed SUCCESS, 7/7 jobs. Its validation jobs checked out synthetic merge commit `008e57c534ec24b6de882053635bf9fc0d5b735f`; treat this as PR merge-ref integration evidence, while #754 is the exact branch-HEAD run.
- C230 migration 029 PostgreSQL regression: PASS — deliberate migration-027 function-source drift is rejected, migration rollback is atomic, and the positive migration path plus historical 5/7/8-argument replay compatibility pass. Exact job: Push run #754 `delivery_migration_order_database_behavior` (job `136969257779`).
- C230 migration 030 PostgreSQL regression: PASS — DB-authoritative idempotency horizon, negative Worker clock skew (Worker clock two hours behind), expired 24-hour provider retention (`24 hours 1 second`), provider receipt validation, and consent revocation after transport start all pass. The consent fixture reports `result cancelled, state cancelled, error authorization_revoked`; the assertion also requires the claim token and expiry to be cleared. Exact job: Push run #754 job `136969257779`.
- C230 aggregate SQL parity: PASS — `scripts/verify-delivery-reliability.mjs` confirms the canonical migration, migration 028, and migration 030 are mirrored verbatim in `supabase/run_in_sql_editor_all.sql`. Independent file comparison at the reviewed HEAD also confirms both migration 029 and migration 030 contents occur verbatim in the aggregate. Migration 029 blob SHA `872fc49ec47e49b17e96ecf6ccaf5c8eb0e6322a`; migration 030 blob SHA `42c227cc1c36b2889e88d9bee1432e6fc6829d41`; aggregate blob SHA `83725a196186f4fd913fab1cf5c9c02c9c6d822c`.
- C230 security/validation: PASS — migration 030 return-type and method-specific adapter assertions, final DB authorization ordering, consent cancellation, expired/unknown authorization fail-closed checks, TypeScript, Next.js production build, Cloudflare packaging, and ESLint (changed delivery-security files) passed in Push run #754. `npm audit --audit-level=high` passed; it still reports **9 moderate-severity advisories**, retained as tracked dependency-maintenance work. The CI job ran with `DELIVERY_ENABLED=false`, non-Production URLs, and no Production API credentials.
- C231 independent review disposition: **ACCEPT**, as reported in the Manager's C232 handoff. C234 independently verified that the saved PR #10 description now contains a C231 section explicitly identifying ACCEPT as an independent engineering disposition and stating that it is not formal GitHub approval. The GitHub PR reviews endpoint still returns zero submitted reviews; no formal GitHub approval is claimed. The description entry is explanatory status, not a review artifact, merge, or Production authorization.
- Engineering acceptance is distinct from Production acceptance. PR #10 remains OPEN / DRAFT / UNMERGED. No Production deployment, database mutation, provider operation, Cron activation, kill-switch exercise, credential change, approval, or merge is evidenced by these CI runs.
- Dependency maintenance: preserve the **9 moderate** npm advisories as tracked maintenance work. The configured high/critical audit gate passed; do not suppress the moderate findings or apply forced breaking dependency changes as part of this tracker update.
- Administrative blockers: main branch protection is not established (`main.protected=false`; repository rulesets list empty). Production Environment deployment restrictions and independent approval/self-review controls are unverified. Production secret scoping (Environment-only versus repository/organization scope) is unverified.
- Production remains **NO-GO**. Outstanding rollout gates: Daily Cron staged activation; multiple healthy Daily cycles; live provider failure, bounce and complaint handling; Production `DELIVERY_ENABLED=false` kill-switch exercise; safe re-enablement; curated Weekly Cron after Daily acceptance; authenticated Production regression; Supabase migration-history/live-schema reconciliation; authorized Production deployment; and final Production smoke tests. Do not close the rollout tracker or create a `sprint-*-complete` tag until all applicable gates are evidenced.
- Human-only GitHub governance and all Production rollout gates remain open. Production remains NO-GO.


## C240 — Historical baseline (archival evidence; not current branch HEAD)

- Inspected branch HEAD 02468dd809a1f5922e354c654f2db186fe8e8ca4, tree 356f750ce7c116b72829ba28578701a1b4e24771; PR #10 remains OPEN / DRAFT / UNMERGED.
- The Production project ref in the repository guard is xaipiovflxomcbfwtwmu. Both connected Supabase account project inventories omitted this ref. Read-only get_project through both accounts and list_migrations through the GiftPary supabase connection returned permission denied. No Production history or schema data was obtained.
- Repository inventory: 31 SQL migration files, 30 unique version prefixes. Two distinct files collide on version 202607260007: Sprint 6 Daily Deedlight and Sprint 7 PWA Daily Engagement. Supabase CLI compares migration timestamps only, so a history row cannot identify which body was applied. Do not rename, repair, or push until live schema/history and manual execution evidence resolve this.
- Migration 018 explicitly describes itself as recording a narrow Production repair after 017; its preflight requires owner_removed_at, remove_own_offering(uuid), and zero owner-removed rows. Migration 022 is labeled a Production Auth hotfix. These are repository assertions, not verified live state.
- supabase/run_in_sql_editor_all.sql (blob 83725a196186f4fd913fab1cf5c9c02c9c6d822c) was compared against all 31 migration files: exact content for 001, 002, and 009–030; not byte-identical for 003–008. It is not an execution record.
- Migrations 020–030 contain important schema/source preflight checks, including 023 function attestations, 024 source hashes, 029's 027 implementation fingerprint, and 030's dependency on 024/028. These must be verified from live catalog state before classification.
- Current tree has no supabase/config.toml. The migration workflow installs supabase/setup-cli@v1 with version latest and runs supabase db push without --remote/--yes; current CLI v3 defaults database commands to local and requires explicit hosted target/confirmation. The Production target guard also intentionally rejects the Production ref. No workflow change was made.
- New evidence-backed investigation and migration-by-migration plan: docs/PRODUCTION_MIGRATION_RECONCILIATION.md. It records all 31 filenames and blob SHAs, dependencies, four-way classification (all Production states currently unknown), source-attestation gates, required read-only inventory, and forward-only rollback/data-protection plan.
- No Production db push, migration repair, db pull, db reset, manual DDL, history edit, or secret access occurred. No migration SQL changed. Production remains NO-GO until the project owner grants scoped read-only Production access and the complete live history/schema/audit inventory is independently reviewed.


## C241 — independent review acceptance and reconciliation follow-ups

- C241 independently accepted the repository-level Production migration reconciliation investigation and plan, subject to the focused source-coverage clarifications recorded in C242. This is an engineering acceptance of the investigation/documentation scope only; it is not a formal GitHub PR review, Production schema finding, or authorization to mutate Production. The PR reviews endpoint has no submitted formal review.
- The acceptance follow-up requires the SQL Editor aggregate bundle to be described as incomplete, not as a verified full migration replay. Missing aggregate SQL effects do not prove that Production lacks the corresponding objects.
- Keep Production migration state unclassified until authorized read-only Production history/schema evidence and relevant SQL Editor execution/audit records are available.

## C242 — 007/008 aggregate SQL representation corrections

- Verified repository branch starting HEAD 685df1c58bd5907cf1a2ddcd73c8abfbb338086e; PR #10 was OPEN / DRAFT / UNMERGED before the documentation-only update.
- Sprint 7 file 202607260007_sprint7_pwa_daily_engagement.sql (blob 8b051cfce05ea75b1ee7a726864e2ad760f6fe5f) creates public.daily_lights. The aggregate supabase/run_in_sql_editor_all.sql (blob 83725a196186f4fd913fab1cf5c9c02c9c6d822c) contains no CREATE TABLE public.daily_lights or ALTER TABLE public.daily_lights statement, although later aggregate SQL references the relation, including a foreign-key addition around line 1501 and later queries/projections. A clean aggregate replay can therefore fail if no earlier statement creates that table. No replay was executed.
- Sprint 8 file 202607270008_sprint8_short_video_studio.sql (blob 5b583bd99562e14db554943d034c748ce302f5ee) adds video_status, video_platform, video_hashtags, video_notes, video_asset_url, tiktok_url, instagram_url, short_video_public, and video_posted_at, the video status constraint/normalization and grants, plus daily_lights_video_status_idx, daily_lights_video_public_idx, and daily_lights_video_posted_at_idx. The aggregate has zero occurrences of those columns/index names.
- Sprint 6 file 202607260007_sprint6_daily_deedlight.sql (blob e0c2379255003b8c7bc85a1fab781e23051f5e47) extends daily_posts with the scheduling/editorial/video fields and adds daily_posts_status_scheduled_idx, daily_posts_featured_offering_idx, daily_reflections_post_idx, and daily_reflections_user_idx. The aggregate's daily_posts definition uses an earlier/different shape (date, theme_id, reflection, daily_action, reflection_question) and does not include the Sprint 6 additions/indexes as a complete effect set.
- The reconciliation document now lists the individual 007/008 effect gaps, the replay dependency risk, and the requirement to compare each effect with read-only live catalog evidence and SQL Editor execution records. It explicitly prohibits treating the aggregate as a verified full migration replay.
- Classification is clarified at both migration-file and independently identifiable schema-effect level. The 31-file/30-prefix distinction remains; the two 007 files remain separate and ambiguous. Do not rename either file, infer which body executed, or repair migration history.
- Missing aggregate effects are not Production evidence: they do not establish whether any object exists or is absent in Production. No Production access escalation, credential change, database query/mutation, migration repair, db push, deployment, Cron change, or delivery enablement occurred. Keep outbound delivery disabled and Production NO-GO.
- Required follow-up: obtain authorized read-only Production history/catalog access and retained SQL Editor/audit records; reconcile 007 Sprint 6, 007 Sprint 7, and 008 effects individually; independently review any proposed future history/schema operation.


## C242 exact-head CI evidence (job accounting corrected in C244)

- **Branch-push validation #766:** [run 44956495277](https://github.com/ADRN-9/deedlight/actions/runs/44956495277) completed **SUCCESS, 7/7 jobs**. Its `validate` job checked out the exact branch HEAD `a85f165587cd10e4f20c1a45986b2e8130d3d7e4`.
- **PR integration validation #767:** [run 44956500758](https://github.com/ADRN-9/deedlight/actions/runs/44956500758) completed **SUCCESS, 7/7 jobs**. Its `validate` job checked out synthetic merge commit `98d4aa1f84cb5bca98c7a77c70d6452afeecc452`, tree `556e9c8d7ab65b93580ab92bae587e537fa9e17a`, with base `ce82b3fdf1a73510de70e3729a487d4ae00e66e3` and branch HEAD `a85f165587cd10e4f20c1a45986b2e8130d3d7e4` as parents.
- The seven workflow jobs in **each** run were exactly:
  1. `validate`
  2. `delivery_provider_webhook_database_behavior`
  3. `delivery_migration_order_database_behavior`
  4. `auth_pgcrypto_database_behavior`
  5. `delivery_reliability_database_behavior`
  6. `sprint12_2_database_behavior`
  7. `gentle_delivery_transport_database_behavior`
- Security assertion suites are steps within the `validate` job; they are **not** a separate eighth workflow job. The Validate steps also include lint/type/build/package and the configured dependency-audit checks.
- These run types are distinct: #766 validates the pushed branch commit directly; #767 validates the PR integration merge result. Both completed successfully with all seven jobs successful.
- These CI runs are non-Production engineering evidence only. They do not establish Production schema, provider, scheduler, deployment, or outbound-delivery readiness.

## C244 — CI evidence presentation correction

- Corrected the C242 CI evidence presentation to enumerate the seven actual workflow jobs by their exact GitHub job names.
- Explicitly recorded that security assertions are steps within `validate`, not an independent eighth job.
- Preserved the C241/C242 migration findings, the branch-push versus PR-integration distinction, the exact #766/#767 run references, and all Production NO-GO restrictions.
- Documentation-only correction. No migration, database, Production, credential, scheduler, deployment, Cron, or delivery setting was changed. No PR approval or merge was performed.
## C245 — migration reconciliation inventory expansion

- Independently reverified repository ADRN-9/deedlight (ID 1308367373), branch security/delivery-transport-consent-gates, source HEAD d65da43a7fe3cebd17f2481a4c8fbb90faa3c17d and tree e5d92f4e06504675d2145d5cdb976691a97eafa6 before documentation changes. PR #10 remained OPEN / DRAFT / UNMERGED.
- Rechecked the complete recursive tree: 31 SQL migration files and 30 unique filename version prefixes. The reconciliation document now records each file's Git blob SHA and declared tables/columns, indexes, constraints, functions, triggers, views, RLS policies, grants, data effects, dependencies and rollback risks.
- Explicitly documented the two distinct 202607260007 files and the CREATE TABLE IF NOT EXISTS order hazard: Sprint 7 first can leave daily_reflections.daily_post_id absent, which migration 012 expects. Also recorded 008→012/013 prerequisites and the limits of the existing migration-order test.
- Production status remains UNKNOWN for all 31 files and all effect groups. Existing Production project access remains unauthorized; repository SQL, migration headers and the aggregate SQL bundle are not evidence of live Production execution.
- No migration SQL, migration history, Production schema, credentials, deployment, scheduler, Cron, delivery setting, or Supabase configuration was changed. No history repair, push, reset, remote SQL, approval or merge occurred.
- Next independent review focus: duplicate 007 mapping and effect-level reconciliation; prove both 007 order permutations and the 008/012/013 dependency path on a disposable PostgreSQL database before considering any later migration plan. Production remains NO-GO.

## C247 — duplicate 007 executable regression and reconciliation correction

- Test source commit: 56785783f6fd00421a05586d4132274b3345dbad (tree f815740d7ee35a65d56af65251dad6e2aa9701a8). Added scripts/test-duplicate-migration-007.sh and extended the existing PostgreSQL 16 migration-order CI job. Both historical migration files remain unchanged.
- Supabase CLI 3.2.0 was executed against isolated PostgreSQL 16.16 databases. Sprint 6 → Sprint 7 applies both SQL bodies, then fails inserting the second 202607260007 history row with SQLSTATE 23505 at statement 53 (schema_migrations primary-key collision). The first history row identifies Sprint 6, while both bodies' DDL remains present because Sprint 7's explicit COMMIT precedes the CLI history insert.
- Sprint 7 → Sprint 6 fails with SQLSTATE 42703 at statement 37: create index if not exists daily_reflections_post_idx on public.daily_reflections (daily_post_id). The CLI's implicit transaction rolls the entire failed Sprint 6 file back. Only Sprint 7's state and history row remain.
- The reverse-order state has no daily_post_id, Sprint 6 reflection fields, Sprint 6 unique user/post constraint, reflection indexes, update trigger, or Sprint 6 policies. Sprint 7 user_id and daily_light_id remain nullable. Even a one-column manual repair would not make Sprint 6 enforce user_id NOT NULL.
- PostgreSQL 16.16 sequence Sprint 6 007 → Sprint 7 007 → 008 → 012 → 013 passed. A second sequence 008 → 013 → 012 also passed, proving migration 013 has no SQL dependency on 012. Its SQL dependencies are saved_lights from 001 and daily_lights from Sprint 7; its gentle-rhythm relationship to private completions is application-level. Migration 012 requires daily_deed_completions from 001 and both Sprint 6 daily_post_id and Sprint 7 daily_light_id reflection/Daily Light effects.
- **Branch-push #774:** run 44965336520 — SUCCESS, 7/7 jobs, Validate exact checkout 56785783f6fd00421a05586d4132274b3345dbad.
- **PR integration #775:** run 44965340590 — SUCCESS, 7/7 jobs, Validate synthetic merge checkout 2a67ee7a686a6397925e85a9ccdc65dafcd49ac6, tree f815740d7ee35a65d56af65251dad6e2aa9701a8, parents ce82b3fdf1a73510de70e3729a487d4ae00e66e3 and 56785783f6fd00421a05586d4132274b3345dbad.
- Each run completed the same seven jobs: validate, delivery_provider_webhook_database_behavior, delivery_migration_order_database_behavior, auth_pgcrypto_database_behavior, delivery_reliability_database_behavior, sprint12_2_database_behavior, gentle_delivery_transport_database_behavior. All passed. The regression is a step in the existing migration-order job, not an eighth job.
- Initial test attempt #772 failed before migration execution because the temporary CLI config set an unsupported local major_version=16. The config was corrected; #774/#775 then passed. This was a harness configuration issue, not a migration result.
- C247 evidence is repository/isolated-runner evidence only. Production migration history and live schema remain unobserved. No Production SQL, migration-history repair, credential/configuration change, deploy, Cron, scheduler, or delivery mutation occurred. Production remains NO-GO.
- Independent review focus: inspect the two 007 files and the new regression assertions; verify the explicit transaction boundary on Sprint 7, default CLI transaction on Sprint 6, and the missing NOT NULL/unique/index/trigger/policy contracts in the Sprint 7-first state. Production reconciliation still requires authorized read-only history, full catalog definitions, and retained manual-execution/audit evidence.

### Final exact-head validation before this evidence addendum

- Branch-push #778, run 44965914853, completed SUCCESS with 7/7 jobs. Validate checked out exact branch HEAD c73902feb46768dd76044f63d2908d6ab746e74a, tree 1b7bd9b2bf526ab04be4daba2cba9ce2b19ed2d6.
- PR integration #779, run 44965919311, completed SUCCESS with 7/7 jobs. Validate checked out synthetic merge commit 94af4082989f98eff0390ec2fce8d6bfaae2ffe1, tree 1b7bd9b2bf526ab04be4daba2cba9ce2b19ed2d6; parents ce82b3fdf1a73510de70e3729a487d4ae00e66e3 and c73902feb46768dd76044f63d2908d6ab746e74a.
- Each run passed all seven jobs: validate, delivery_provider_webhook_database_behavior, delivery_migration_order_database_behavior, auth_pgcrypto_database_behavior, delivery_reliability_database_behavior, sprint12_2_database_behavior, and gentle_delivery_transport_database_behavior.


## C268 — Production migration reconciliation recheck

- \`main\` remains \`ce82b3fdf1a73510de70e3729a487d4ae00e66e3\` (23 migration files / 22 version prefixes). PR #10's candidate branch was \`9072f3b8824ec9618849def1c0832000cd130474\` (31 files / 30 prefixes; migrations 023–030 candidate-only).
- Duplicate 007 remains unresolved. C268's connected Supabase read-only project/history access was denied/unavailable; no Production SQL was run. All 31 candidate migration files/effect groups remain Production UNKNOWN. No Production operation occurred.

## C269 — independent-review handoff: unresolved security/release topics

The exact C269 review artifact was not found in accessible PR #10 review/comment records or available ChatGPT Spaces. The three named handoff topics are retained without inventing additional review detail or acceptance:

- **Provider suppression / transport-start linearization:** migrations 021/027 remain the historical baseline. PR #17's candidate migration 031 and PR #18's concurrency matrix are open, draft, stacked on PR #10, and unmerged. They are not accepted Production behavior. No C270 semantics change.
- **Suspended-member Offering removal:** \`remove_own_offering(uuid)\` in migrations 017/018 is \`SECURITY DEFINER\` and checks actor/ownership/moderation state but does not explicitly require \`profiles.is_suspended=false\`; the restore path does. This remains an executable-security test/design gap. No C270 semantics change.
- **Main migration workflow protection / CLI targeting:** main is unprotected and its current privileged workflow uses floating Supabase CLI \`latest\` followed by \`link\`/\`db push\` without a verified protected Environment/explicit target. PR #13 proposes workflow retirement and PR #15 CLI target allowlisting; both remain open/unmerged and were not modified.

## C270 — duplicate-007 audit harness safety

- Added pre-destructive GitHub Actions/repository/job/event checks, \`DELIVERY_ENABLED=false\` enforcement, a strict libpq environment allowlist, and an explicit read-only local PostgreSQL identity/version preflight. No \`DROP\`/\`CREATE\` or cleanup trap can run before that preflight passes.
- Added mocked-command regressions for remote \`PGHOST\`, \`PGHOSTADDR\`, service-file/service-name, database, port, options, passfile, session-target, and SSL overrides. The tests assert no \`psql\`, \`dropdb\`, \`createdb\`, or Supabase CLI command is invoked for rejected targets. The exact local CI allowlist is also exercised with fake commands.
- Pinned the duplicate-migration job service to \`postgres:16.16\`; runtime numeric version must equal \`160016\`.
- This work is stacked as a new child PR on PR #10. PR #10 and its dependent PRs #17/#18 are not moved or rewritten. PR #13/#15 are not duplicated or modified. No Production access, migration repair, \`db push\`, deployment, Cron, scheduler, provider, or delivery mutation occurred. Production remains NO-GO.
- Implementation-head branch-push [run #823](https://github.com/ADRN-9/deedlight/actions/runs/44994368931) — **SUCCESS, 7/7 jobs**, exact HEAD `0118cec92899c3a4beaf6da6a1c281923cdc40ca`, tree `40f49ac9c0703d27e9290408212d0d77a3ba8b53`. Migration-order job `137122110374` confirmed the actual `postgres:16.16` service, PostgreSQL 16.16, numeric `server_version_num=160016`, Supabase CLI 3.2.0, all 11 remote/overridden libpq rejection cases, local fake-target acceptance, expected duplicate-007 SQLSTATEs 23505/42703, and both dependency paths. All seven workflow jobs passed, including Validate (security assertions, TypeScript, Next build, Cloudflare packaging and high-severity audit).
- Earlier failed attempts were retained and corrected: #821 (44994072068) caught a malformed grep assertion; #822 (44994190850) caught the missing CLI version assignment. Neither performed Production operations.
- Exact branch-push [run #824](https://github.com/ADRN-9/deedlight/actions/runs/44994612851) validated the preceding documentation-addendum HEAD `b4eeaf4eeb26ecea654e4d98fee83b6ffbbd2594` (tree `8a705b606fac4e68fe354b2236331277036c37e4`) with **7/7 jobs PASS**. PR #19 is stacked on PR #10's branch, so the workflow's `pull_request: branches: [main]` filter does not generate a PR integration run; branch-push validation is the available exact-head evidence. This subsequent documentation-only evidence commit is followed by its own branch-push validation.

## C271 — Docker-bound PostgreSQL target verification

- Resumed the existing C270 branch/PR without recreating it. C270 starting HEAD `efb343b1d246e30d8c5156e9214d5ff94a1c02a0` had successful branch-push run #825 (7/7); it did not yet bind backend identity to Docker metadata.
- Commit `1fffd212dc02df7844494316023ef4fd071b090a` binds the expected `job.services.postgres.id` to Docker inspect metadata and requires matching ID, exact image `postgres:16.16`, running state, one network, and a valid IPv4 address. It compares this independent address with `host(inet_server_addr())` before cleanup traps or destructive database commands.
- Added mocked Docker + PostgreSQL regression coverage for missing ID, wrong image, stopped container, multiple networks, missing/malformed address, unexpected container ID, and a mismatched backend address. Mismatch proof allows only `docker inspect` and read-only `psql`; no database mutation or Supabase CLI call.
- Exact implementation-head branch-push [run #828](https://github.com/ADRN-9/deedlight/actions/runs/44996643648): **SUCCESS, 7/7 jobs**, HEAD `1fffd212dc02df7844494316023ef4fd071b090a`. Migration-order job `137128980344` confirmed the Docker service address and PostgreSQL backend address both `172.18.0.2`, actual PostgreSQL 16.16, `server_version_num=160016`, Supabase CLI 3.2.0, and all mocked Docker/DB regressions.
- #826 (`44995978909`) failed on a safety-script syntax error; #827 (`44996259161`) caught the `/32` suffix in PostgreSQL's inet text representation. The `host(inet_server_addr())` correction passed in #828. These diagnostics did not access Production.
- PR #19 targets PR #10's branch. Compare is `ahead 8 / behind 0`, merge base equals PR #10's current head, and GitHub reports the PR mergeable. The workflow's `pull_request` filter only includes `main`; a native PR-event run would require changing the shared base workflow or retargeting PR #19. Neither is safe for this stacked PR relationship. Branch-push validation checks the same tree because PR #19 already includes its base; no native PR integration run is claimed.
- Existing PR #10/#17/#18 relationships remain unchanged. PR #13/#15 are untouched. PR #19 remains draft/unmerged. Production remains NO-GO; no Production access, SQL, migration repair, push, deployment, scheduler, Cron, provider or delivery mutation occurred.
- The documentation evidence commit and its final exact-head branch-push validation are recorded in the following C271 addendum.