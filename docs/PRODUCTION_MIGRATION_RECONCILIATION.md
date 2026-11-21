# DeedLight Production migration-history reconciliation

**Investigation:** C240  
**Repository:** ADRN-9/deedlight  
**Branch:** security/delivery-transport-consent-gates  
**Inspected source HEAD:** 02468dd809a1f5922e354c654f2db186fe8e8ca4  
**Inspected source tree:** 356f750ce7c116b72829ba28578701a1b4e24771  
**PR:** #10 — OPEN / DRAFT / UNMERGED  
**Date:** 2026-11-21  
**Disposition:** INCOMPLETE — Production read-only access not authorized

## Executive result

The Production Supabase project reference used by the repository guard is xaipiovflxomcbfwtwmu. The two connected Supabase accounts did not list that project. A direct read-only get_project request and a read-only list_migrations request for that reference both returned a permission error. A second get_project request through the other connected account also returned a permission error.

No Production migration-history rows, live schema objects, functions, policies, constraints, extensions, or audit records were retrieved. Therefore no Production migration can honestly be classified as applied, recorded, represented-but-unrecorded, or unapplied.

Repository-only inspection identifies important reconciliation risks and a migration-by-migration dependency plan. It does not establish Production state.

## Safety and access evidence

### Verified access attempts

- Listed projects through both connected Supabase accounts. Neither returned the Production reference xaipiovflxomcbfwtwmu.
- Called get_project for xaipiovflxomcbfwtwmu through the GiftPary supabase connection. The connector returned: MCP error -32600: You do not have permission to perform this action.
- Called list_migrations for xaipiovflxomcbfwtwmu through the same connection. The connector returned the same permission error.
- Called get_project for the same reference through the Primary connection. The connector returned the same permission error.
- No Production list_tables or SQL/catalog query was run after project access failed.
- No Production credential, password, token, provider key, or secret value was read or exposed.

### Exact missing authority

A project owner/administrator must grant the connected Supabase identity explicit read-only access to Production project xaipiovflxomcbfwtwmu, or provide an approved project-scoped read-only Supabase connection. The authority must permit migration-history listing and SELECT-only catalog inspection. It must not grant schema-write, migration-repair, service-role, or outbound-delivery authority.

If access is provided through a database connection, use a read-only database role. A privileged service-role or general administrator credential is not required for this investigation.

### Missing Production evidence

1. Exact rows in supabase_migrations.schema_migrations, including every remote-only version and capture time.
2. Schema-only inventory of public objects and customizations touching auth, storage, extensions, and other Supabase-managed schemas.
3. Definitions and metadata for functions, triggers, views, policies, constraints, indexes, grants, default privileges, and installed extensions.
4. Exact source fingerprints and comments for migration-023, migration-027, and migration-029 guard contracts.
5. Read-only counts needed for migration preconditions, especially active delivery claims and Offerings with owner_removed_at set.
6. Retained SQL Editor/audit/deployment history that could confirm the claimed 018 Production repair and 022 Auth hotfix.
7. Verified backup/PITR point and database identity before any later reconciliation decision.

An inaccessible migration-history table must not be interpreted as an empty history. Permission errors are not evidence of an absent project, absent schema, or absent migration.

## Repository inventory

The inspected tree contains 31 SQL migration files and 30 unique filename version prefixes. All files and Git blob SHAs are listed below. Production status is UNKNOWN for every row because no live history or schema evidence was available.

| Version | Migration file | Dependency / reconciliation note | Git blob SHA | Production classification |
|---|---|---|---|---|
| 202607210001 | 202607210001_initial_schema.sql | Foundational profiles, themes, daily_posts, offerings, reactions, reflections, reports, badges, saved_lights, completions, triggers, and pgcrypto. Requires Supabase Auth and Storage. | a244ab0df3e766b0f36e29a222b3160f9f74c502 | Ambiguous — no live evidence |
| 202607210002 | 202607210002_rls_policies.sql | Depends on 001 tables; enables RLS and creates initial member/admin and storage.objects policies. | f96b482c0d1cf396baae5b91d7c96112f7e88284 | Ambiguous — no live evidence |
| 202607220003 | 202607220003_sprint3_offerings_review.sql | Depends on initial Offering model; adds review projections/indexes/grants. Aggregate SQL bundle is not byte-identical. | 74e02f2e60b82cf07a6aac5f8cf57dcdb6fe1382 | Ambiguous — no live evidence |
| 202607260004 | 202607260004_sprint4_reactions.sql | Depends on reactions from 001 and policies from 002; replaces reaction count triggers/RPC behavior and policies. Aggregate bundle is not byte-identical. | c25dce46ecf69d082fcdbea2bb931b6acd9180fc | Ambiguous — no live evidence |
| 202607260005 | 202607260005_sprint5_moderation.sql | Depends on offerings/reports/reactions from 001 and RLS from 002/004; changes report aggregation and moderation policies. Aggregate bundle is not byte-identical. | b48b4b8b3eea9fb55b68068011fa1371559228c2 | Ambiguous — no live evidence |
| 202607260006 | 202607260006_sprint5_admin_edit_hide_hotfix.sql | Depends on Offering moderation policy baseline from 005; narrows member/admin update policy. Aggregate bundle is not byte-identical. | 9e163de5119c3813724341b7a9eabeba6fdc2970 | Ambiguous — no live evidence |
| 202607260007 | 202607260007_sprint6_daily_deedlight.sql | Depends on 001/002; extends legacy Daily Post/Reflection model. Shares its version prefix with the next file. | e0c2379255003b8c7bc85a1fab781e23051f5e47 | Ambiguous — duplicate version |
| 202607260007 | 202607260007_sprint7_pwa_daily_engagement.sql | Depends on initial Offering/Auth model; introduces Daily Lights and another Daily Reflection shape. Shares version prefix with prior file and overlaps public.daily_reflections. | 8b051cfce05ea75b1ee7a726864e2ad760f6fe5f | Ambiguous — duplicate version |
| 202607270008 | 202607270008_sprint8_short_video_studio.sql | Depends on daily_lights from the Sprint 7 007 file; adds video metadata/indexes. Aggregate bundle is not byte-identical. | 5b583bd99562e14db554943d034c748ce302f5ee | Ambiguous — no live evidence |
| 202608060009 | 202608060009_sprint9_profiles_privacy.sql | Depends on profiles and offerings from 001; changes opt-in public identity, profile policies, and public projections. | 6594ce6daa0183944fcc548885d6514e8adb9436 | Ambiguous — no live evidence |
| 202608100010 | 202608100010_sprint9_2_community_identity_consistency.sql | Depends on 009 public identity projections and Auth profile bootstrap; replaces handle_new_user and community views. | 774708b7705d88a5a1e0da97e72a9d1b47c8884c | Ambiguous — no live evidence |
| 202608100011 | 202608100011_sprint9_3_moderation_aware_members.sql | Depends on profiles, offerings, and reflection policies; adds member_moderation_events and suspension-aware controls. | 1d1b7b844b88077351d2658af4be2b2db92eda97 | Ambiguous — no live evidence |
| 202608110012 | 202608110012_sprint10_1_daily_deed_completion.sql | Depends on daily_deed_completions from 001 and Daily Lights from 007; bridges completion counts and private reflection state. | 0973f72e39ce07b41e053a20f1b781c394578877 | Ambiguous — no live evidence |
| 202608110013 | 202608110013_sprint10_2_saved_lights_gentle_rhythm.sql | Depends on saved_lights from 001, Daily Lights from 007, and completion behavior from 012; changes private saves and derived rhythm. | 5fd2f4a796a8a1dfd6237ccf36d1ab62c1dc1714 | Ambiguous — no live evidence |
| 202608120014 | 202608120014_sprint10_3_gentle_reminder_preferences.sql | Depends on auth.users and profiles; creates private opt-in daily_reminder_preferences. | 2af1a6a2aa5cffc6ef6d08849b6f71fab44a54d0 | Ambiguous — no live evidence |
| 202608130015 | 202608130015_sprint11_2_weekly_goodness.sql | Depends on reactions and profiles; adds weekly_goodness_features and curated Weekly Goodness functions. | 394c774032d8206c0b7a373640859c2a331667a9 | Ambiguous — no live evidence |
| 202608130016 | 202608130016_sprint11_3_invitations_newsletter_foundation.sql | Depends on auth.users, profiles, and pgcrypto; creates private invitation attribution and newsletter_preferences. | 8d68ed19859e1a820af52a43c110a38b6a460d48 | Ambiguous — no live evidence |
| 202608130017 | 202608130017_sprint12_1_offering_ownership_engagement.sql | Depends on offerings, profiles, reactions, and saved_lights; adds owner removal/edit flows and private Offering saves. | bc23b12fe454c1f49b096fd2c7199e3a2aea5bb4 | Ambiguous — no live evidence |
| 202608140018 | 202608140018_sprint12_1_owner_removal_guard_hotfix.sql | Depends on 017: requires owner_removed_at and remove_own_offering(uuid). Source comment says it records a narrow Production repair applied after 017. Preflight requires zero currently owner-removed Offerings. | 0ea7eaf04d5c99e4c5a25893aae7694affdd44bc | Ambiguous — repo claim only |
| 202609230019 | 202609230019_sprint12_2_gentle_delivery_foundation.sql | Depends on 014 daily preferences, 015 Weekly features, 016 newsletter preferences, profiles, and auth.users; creates delivery_ledger and transport-neutral RPCs. No Cron/provider activation. | 1403b9324e786a2b724176875a70ffce92961d9b | Ambiguous — no live evidence |
| 202609230020 | 202609230020_delivery_reliability_hardening.sql | Depends on 019 ledger and baseline RPCs; adds bounded claims/retries. Preflight rejects partial application and live claimed jobs. | 554615da3d15fc4c0d395691103d3be5676856fa | Ambiguous — no live evidence |
| 202609230021 | 202609230021_gentle_delivery_transport.sql | Depends on 020 retry RPC and claim_expires_at; adds transport_started_at and transport/Weekly helpers. Preflight rejects partial application. | e50a06bd3a5ed386c54e789435c64b2bb4a54ab9 | Ambiguous — no live evidence |
| 202609240022 | 202609240022_auth_pgcrypto_schema_qualification.sql | Auth hotfix independent of delivery chain; requires extensions.gen_random_bytes(integer) and replaces handle_new_user with schema-qualified pgcrypto. Header labels it a Production Auth hotfix. | f42afb3474f80c7d95cf5b47023b82cf5a948d4d | Ambiguous — header is not execution proof |
| 202611120023 | 202611120023_delivery_consent_linearization.sql | Requires 019–021 baseline plus profiles, daily_reminder_preferences, newsletter_preferences, weekly_goodness_features. Replaces enqueue/transport functions and writes source-attestation comments. | 75f5086feab2cbda381066cb9094390190c3332f | Ambiguous — no live evidence |
| 202611120024 | 202611120024_delivery_identity_lease_capacity.sql | Requires exact 023 functions, comments, and source hashes; introduces recipient-bound transport and Weekly capacity guards. | 240271fd75081c062627cfc3d40bdc0c5feda049 | Ambiguous — no live evidence |
| 202611190025 | 202611190025_delivery_provider_webhooks.sql | Requires 024 recipient-bound transport, ledger, auth.users, and enqueue RPCs; creates provider events/suppressions and suppression-aware transport authorization. | e97c5c0ad645dfe43f11a88f01b030fa23dd5822 | Ambiguous — no live evidence |
| 202611190026 | 202611190026_delivery_provider_lifecycle.sql | Requires 025 provider events and base event RPC; adds lifecycle timestamps, failure classification, and lifecycle projection. | 6a06d780ad65babf2293a2746c68913758313af8 | Ambiguous — no live evidence |
| 202611200027 | 202611200027_delivery_provider_integrity.sql | Extends 025/026 event and lifecycle tables, adds integrity anomaly storage, and replaces lifecycle persistence. Migration 029 pins its function source identity. | a1469938ea13b5cb9d7cd883772bc60e4a058026 | Ambiguous — no live evidence |
| 202611210028 | 202611210028_delivery_claim_lock_expiry.sql | Requires 020 authorization/retry/sent/failed RPCs; replaces lock-wait-sensitive transitions using clock_timestamp(). | 09d1927fba81d711bb37d214609931d2da2173a1 | Ambiguous — no live evidence |
| 202611210029 | 202611210029_delivery_legacy_replay_guard.sql | Requires exact 027 RPC overloads, pgcrypto, function metadata, migration comment, and pinned SHA-256 source hash; renames implementation and restricts fingerprint-less replays. | 872fc49ec47e49b17e96ecf6ccaf5c8eb0e6322a | Ambiguous — no live evidence |
| 202611210030 | 202611210030_delivery_idempotency_receipt_guard.sql | Requires 024 recipient-bound transport, 028 transitions, and delivery_ledger.transport_started_at; adds database-authoritative idempotency timing and validates Resend receipt UUIDs. | 42c227cc1c36b2889e88d9bee1432e6fc6829d41 | Ambiguous — no live evidence |

## Classification summary

| Required class | Count | Evidence-backed conclusion |
|---|---:|---|
| Verified applied and recorded | 0 | No Production history was readable. |
| Verified represented in schema but missing from history | 0 | No Production schema was readable. |
| Verified unapplied | 0 | No Production history or schema was readable. |
| Ambiguous / requires further evidence | 31 | All repository migrations remain unclassified against Production. |

This does not mean none are applied. It means Production status is unknown.

## High-priority reconciliation findings

### 1. Duplicate migration version 202607260007

Two different migration files share the same version prefix:

- 202607260007_sprint6_daily_deedlight.sql — blob e0c2379255003b8c7bc85a1fab781e23051f5e47
- 202607260007_sprint7_pwa_daily_engagement.sql — blob 8b051cfce05ea75b1ee7a726864e2ad760f6fe5f

They are not interchangeable. The first extends the legacy Daily Post/Reflection model; the second introduces Daily Lights and another Daily Reflection shape. The second overlaps public.daily_reflections created by the first.

Supabase migration history compares timestamps, not migration contents. One history timestamp cannot identify which of these two SQL bodies was executed. Resolve this before any migration push or history repair.

Do not rename either file, edit an executed migration, mark either version applied/reverted, or infer which ran until remote history, schema objects, and manual execution evidence are reviewed. If renumbering is required, preserve the executed file/version and move only a proven-unapplied migration to a new unique timestamp in a separate reviewed change. If both bodies were manually applied, record that as schema state rather than inventing two history rows for one version.

### 2. Migration 018 records a claimed Production repair

The 018 header says it records a narrow Production repair applied after 017. The SQL requires owner_removed_at, remove_own_offering(uuid), and zero rows currently owner-removed. It then replaces the offerings_owner_removed_hidden constraint and remove_own_offering function.

This is a repository claim, not proof of current database state or history. Before classifying 018, inspect the column, exact check constraint, full function definition, SECURITY DEFINER/search_path metadata, execute grants, and count of owner-removed Offerings. If the repair is present but history is absent, preserve it and consider history-only reconciliation only after separate authorization. Do not rerun 018 blindly: its zero-row precondition can abort on live owner-removed records.

### 3. Migration 022 is a Production Auth hotfix

The 022 header labels the file Production Auth hotfix and requires extensions.gen_random_bytes(integer). It replaces public.handle_new_user() so Auth user creation uses a schema-qualified pgcrypto function.

The header identifies the reason, not the actual execution date, exact live function body, extension schema, trigger state, or history row. Verify the extension namespace, trigger on auth.users, function body, search_path, SECURITY DEFINER metadata, and privileges before classifying it. Do not restore the pre-hotfix function as a rollback.

### 4. SQL Editor bundle is not an execution record or complete canonical mirror

supabase/run_in_sql_editor_all.sql is 7,136 lines, blob SHA 83725a196186f4fd913fab1cf5c9c02c9c6d822c.

Byte-for-byte comparison against all 31 migration files found exact file content for 001, 002, and 009–030. The contents of migrations 003–008 were not byte-for-byte present. This does not prove their SQL effects are absent; it means the aggregate is not a canonical byte-identical copy of those seven migrations.

The bundle makes a SQL Editor/manual execution path plausible, but no execution record was obtained. Running SQL directly against a remote database bypasses Supabase CLI migration history unless history is separately reconciled. The bundle cannot prove application or migration-history state.

### 5. Migration-specific source/state guards

- 020 rejects a missing 019 baseline, partial prior application, and live claimed jobs.
- 021 requires 020 and refuses pre-existing transport_started_at / transport functions.
- 023 requires the 019–021 baseline and records comments that act as source attestations.
- 024 checks 023 function comments and source hashes. Expected MD5 values:
  - enqueue_due_daily_reminders(timestamptz,integer): ad0b49bdc5d6ea94bbc2a73fa40985ac
  - enqueue_weekly_goodness_delivery(date,timestamptz,integer): d13eed60e2cf6413d0dd3e0531f5cf77
  - begin_delivery_transport(uuid,uuid): a5f2ba15937ab66bbdd71d3e6d175c2d
- 025 requires the reviewed 024 recipient-bound transport baseline.
- 026 requires the 025 provider events table and base RPC.
- 027 extends 025/026 lifecycle tables. Its exact implementation identity is checked by 029.
- 028 requires the reviewed 020 reliability RPCs and replaces lock-sensitive transitions.
- 029 requires expected 027 function overloads, SECURITY DEFINER/search_path metadata, migration comment, pgcrypto, and SHA-256 source fingerprint:
  8dbfc65b93677f9928114561d372dad69f16c9c746dadf80551c662161ba3ed5
  It refuses an existing private implementation with unknown origin.
- 030 requires 024 recipient-bound transport, 028 transitions, and delivery_ledger.transport_started_at.

These are schema/source gates, not migration-history evidence. Compare exact live function source and metadata before any decision.

## Migration workflow readiness

### Production guard

scripts/guard-supabase-migration-target.sh explicitly rejects xaipiovflxomcbfwtwmu because Production migration history is unreconciled and db push is forbidden. scripts/guard-supabase-linked-project.sh additionally requires the local linked-project marker to match the approved non-Production target.

Keep this guard in place during the investigation.

### Supabase CLI v3 target semantics

The current .github/workflows/supabase-migrations.yml uses supabase/setup-cli@v1 with version latest, then runs supabase db push without --remote or --yes. Current Supabase CLI v3 documentation states database commands target the local stack by default; hosted db push requires --remote and hosted confirmation (or --yes in non-interactive automation). The November 4, 2026 changelog says setup-cli installs v3 by default.

The current workflow is not evidence of a Production push and is not ready to be reactivated as a hosted migration path without explicit CLI-version/target/confirmation review. It also requires protected main and a Production Environment guard, while the migration-target guard intentionally rejects the Production project ref. No workflow or secret changes were made.

### Missing committed Supabase config

The inspected tree contains supabase/migrations, supabase/run_in_sql_editor_all.sql, and supabase/seed.sql, but no supabase/config.toml or config.jsonc. Supabase CLI documentation says supabase init creates config.toml and linking uses the local project configuration. Confirm the intended config before future CLI reconciliation. No config was created in this investigation.

## Authorized read-only evidence collection plan

When the project owner grants read-only access, capture the following before classifying any migration:

1. Record the exact Production project ref, database identity, server version, branch/environment, UTC timestamp, and read-only principal used.
2. Retrieve migration history with Supabase MCP list_migrations or current CLI read-only command:
   ~~~bash
   supabase migration list --remote=xaipiovflxomcbfwtwmu
   ~~~
   Preserve the full raw output and compare every local/remote version. Do not use migration repair.
3. Capture a schema-only dump of public using a read-only database principal:
   ~~~bash
   supabase db dump --remote=xaipiovflxomcbfwtwmu --schema public --file /tmp/deedlight-production-public-schema.sql
   ~~~
   The CLI dump excludes Supabase-managed schemas such as auth, storage, and extension schemas by default. Supplement it with SELECT-only catalog inventory for the custom Auth trigger, extension placement, storage policies, and managed-schema customizations.
4. Use only simple catalog SELECTs in a read-only transaction to inventory:
   - supabase_migrations.schema_migrations versions;
   - pg_class/pg_namespace tables, views, materialized views, indexes, sequences, and object comments;
   - pg_proc/pg_language function identity arguments, pg_get_functiondef, prosrc fingerprints, prosecdef, proconfig, and function comments;
   - pg_trigger definitions and enabled state;
   - pg_policies roles, command, USING, and WITH CHECK expressions;
   - pg_constraint definitions and validation state;
   - pg_extension namespace/version;
   - table/function/schema privileges and default privileges.
5. Capture targeted read-only counts for migration preconditions: active delivery claims before 020; owner_removed_at rows before 018; and existence/source fingerprints required by 023–030.
6. Obtain retained SQL Editor/audit/deployment records for the claimed 018 Production repair, 022 Auth hotfix, and any use of run_in_sql_editor_all.sql. Record timestamps, operator identity, and SQL hashes where available.
7. Capture an immutable backup/PITR point and verify a tested restore path before any later reconciliation decision.

Do not use db pull, supabase pull, db push, db reset, migration repair, or any command that writes remote migration history/schema during evidence gathering. In CLI v3, db pull and supabase pull can update remote migration history; they are not read-only inventory commands.

## Classification rules

For each unique migration version, apply exactly one evidence-backed classification:

- **Verified applied and recorded:** a remote history row exists and live schema/function/security state matches the exact migration and required follow-on changes.
- **Verified represented in schema but missing from history:** no remote history row exists, but all relevant SQL effects match exact migration source, including functions, constraints, RLS, triggers, grants, and data-sensitive preconditions. This is only a candidate for later separately authorized history-only repair; it is not permission to run repair now.
- **Verified unapplied:** no history row exists, no SQL effects are present, no partial state exists, and predecessor/data preconditions are satisfied. This is not permission to push now.
- **Ambiguous / requires further evidence:** partial objects, differing function source, unverified manual edits, missing dependencies, duplicate version, contradictory history, or any uncertainty.

For duplicate 202607260007, timestamps alone cannot determine which SQL file was applied. Schema inspection and historical execution evidence are mandatory.

## Reconciliation plan after evidence is available

1. **Freeze:** keep the Production target guard, delivery kill switch, and Cron activation barriers intact. No push, repair, or manual DDL.
2. **Snapshot:** export remote history and schema evidence, retain audit records, capture a backup/PITR point, and verify project identity.
3. **Normalize inventory:** compare every local timestamp to remote history. Identify remote-only versions, local-only versions, duplicate local versions, and files changed since execution.
4. **Resolve source ambiguity:** reconcile 007 from live Daily tables/columns and SQL Editor evidence. Verify 018/022 hotfixes. Verify 023/024 source attestations and 027/029 function identity.
5. **Classify:** fill the four status classes with reviewer and evidence reference for every row. Never classify from filename, code comments, aggregate SQL, or history alone.
6. **Design minimal reconciliation:** preserve already-applied schema and executed migration files. If represented but missing from history, prepare a separate reviewed history-only repair proposal after proof. If schema drift exists, create a forward-only migration preserving data. If genuinely unapplied, review dependencies and preconditions before any separate deployment approval.
7. **Test away from Production:** replay the reconciled sequence on an isolated disposable database or restored clone. Verify schema, function source, RLS, grants, and application tests. Resolve duplicate 007 before using the directory for fresh reset/push.
8. **Approval gate:** only after independent review may an authorized administrator approve a separately scoped Production history/schema operation. C240 grants no such approval.

## Rollback and data-protection considerations

- Migration history repair changes only the tracking table: applied inserts a record; reverted deletes one. It does not apply or reverse SQL. It is a privileged history mutation, not schema rollback. No such operation is authorized here.
- Do not delete/recreate public tables to force alignment. Preserve profiles, Offerings, reflections, Saved Lights, invitations, newsletter consent, moderation history, delivery ledger, provider events, suppressions, and integrity anomalies.
- Prefer forward-only compensating migrations for schema drift. Do not reverse privacy/RLS, moderation, consent, suppression, or idempotency guards to make migration history appear clean.
- Before any future 018 operation, inspect owner_removed_at data and the exact constraint/function; its preflight requires zero currently owner-removed Offerings.
- Before any future 020 operation, inspect live claimed delivery jobs; its preflight refuses live claimed jobs.
- Before any future 024/029 operation, verify exact function bodies, comments, pgcrypto namespace, security metadata, and expected source fingerprints. Do not bypass a failed fingerprint gate.
- Before any delivery migration operation, keep outbound delivery disabled and scheduling inactive; do not alter queue rows/claims as a shortcut.
- Take and verify a recoverable backup before any approved Production mutation. A history-row repair is not a substitute for backup.

## C240 execution status

- Repository HEAD/tree independently retrieved and preserved.
- All 31 migration files inventoried with blob SHAs and dependency notes.
- Duplicate 007 version identified.
- 018 Production repair claim and 022 Production Auth hotfix header recorded as repository assertions, not live facts.
- Aggregate SQL bundle compared against all migration files.
- Migration preflight/source-attestation gates 020–030 inventoried.
- Supabase Production project lookup and migration-history retrieval attempted read-only; both denied by account authorization.
- No Production schema/history query, migration push, migration repair, db pull, db reset, manual DDL, or secret retrieval performed.
- No migration file, Supabase config, or Production resource changed.
- Documentation-only changes require CI validation against the resulting exact HEAD.

## Official Supabase references consulted

- CLI migration list: https://supabase.com/docs/reference/cli/supabase-migration-list
- CLI migration repair: https://supabase.com/docs/reference/cli/supabase-migration-repair
- Database migrations and history/schema sync: https://supabase.com/docs/guides/deployment/database-migrations
- CLI local/remote workflow and config: https://supabase.com/docs/guides/local-development/cli-workflows
- CLI v3 target/confirmation breaking change: https://supabase.com/changelog/supabase-cli-v3
- CLI db dump scope: https://supabase.com/docs/reference/cli/supabase-db-dump

**Final disposition: Production migration reconciliation remains BLOCKED pending authorized read-only access. Production remains NO-GO.**
