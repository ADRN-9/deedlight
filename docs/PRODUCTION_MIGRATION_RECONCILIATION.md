# DeedLight Production migration-history reconciliation

**Historical investigation baseline:** C240 (archival record; not the current branch HEAD)  
**Repository:** ADRN-9/deedlight  
**Branch:** security/delivery-transport-consent-gates  
**Historical C240 source HEAD (archival):** 02468dd809a1f5922e354c654f2db186fe8e8ca4  
**Historical C240 source tree (archival):** 356f750ce7c116b72829ba28578701a1b4e24771  
**C247 verified test-source HEAD:** 56785783f6fd00421a05586d4132274b3345dbad  
**C247 verified test-source tree:** f815740d7ee35a65d56af65251dad6e2aa9701a8  
**PR:** #10 — OPEN / DRAFT / UNMERGED  
**Historical C240 date (UTC):** 2026-11-21  
**C247 verification date (UTC):** 2026-11-22  
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

The inspected tree contains 31 SQL migration files and 30 unique filename version prefixes. All files and Git blob SHAs are listed below. The table has one row per migration file; duplicate version prefixes do not merge distinct SQL files. Production status is UNKNOWN for every row because no live history or schema evidence was available. Independently identifiable schema effects within each file must also be reconciled and classified separately; a file-level label must not conceal partial application.

| Version | Migration file | Dependency / reconciliation note | Git blob SHA | Production classification |
|---|---|---|---|---|
| 202607210001 | 202607210001_initial_schema.sql | Foundational profiles, themes, daily_posts, offerings, reactions, reflections, reports, badges, saved_lights, completions, triggers, and pgcrypto. Requires Supabase Auth and Storage. | a244ab0df3e766b0f36e29a222b3160f9f74c502 | Ambiguous — no live evidence |
| 202607210002 | 202607210002_rls_policies.sql | Depends on 001 tables; enables RLS and creates initial member/admin and storage.objects policies. | f96b482c0d1cf396baae5b91d7c96112f7e88284 | Ambiguous — no live evidence |
| 202607220003 | 202607220003_sprint3_offerings_review.sql | Depends on initial Offering model; adds review projections/indexes/grants. Aggregate SQL bundle is not byte-identical. | 74e02f2e60b82cf07a6aac5f8cf57dcdb6fe1382 | Ambiguous — no live evidence |
| 202607260004 | 202607260004_sprint4_reactions.sql | Depends on reactions from 001 and policies from 002; replaces reaction count triggers/RPC behavior and policies. Aggregate bundle is not byte-identical. | c25dce46ecf69d082fcdbea2bb931b6acd9180fc | Ambiguous — no live evidence |
| 202607260005 | 202607260005_sprint5_moderation.sql | Depends on offerings/reports/reactions from 001 and RLS from 002/004; changes report aggregation and moderation policies. Aggregate bundle is not byte-identical. | b48b4b8b3eea9fb55b68068011fa1371559228c2 | Ambiguous — no live evidence |
| 202607260006 | 202607260006_sprint5_admin_edit_hide_hotfix.sql | Depends on Offering moderation policy baseline from 005; narrows member/admin update policy. Aggregate bundle is not byte-identical. | 9e163de5119c3813724341b7a9eabeba6fdc2970 | Ambiguous — no live evidence |
| 202607260007 | 202607260007_sprint6_daily_deedlight.sql | Depends on 001/002; extends the legacy daily_posts/daily_reflections model with scheduling/editorial/video-planning fields, constraints, and indexes. The aggregate bundle contains only an earlier/different daily_posts shape and omits the Sprint 6 additions/indexes. Shares its version prefix with the next file. | e0c2379255003b8c7bc85a1fab781e23051f5e47 | Ambiguous — duplicate version |
| 202607260007 | 202607260007_sprint7_pwa_daily_engagement.sql | Depends on initial Offering/Auth model; creates public.daily_lights and changes daily_reflections. The aggregate bundle has no CREATE/ALTER TABLE DDL for daily_lights, although later statements reference it. Shares version prefix with prior file. | 8b051cfce05ea75b1ee7a726864e2ad760f6fe5f | Ambiguous — duplicate version |
| 202607270008 | 202607270008_sprint8_short_video_studio.sql | Depends on Sprint 7 public.daily_lights; adds short-video metadata, status/visibility constraints, grants, and three indexes. Its video columns and indexes are absent from the aggregate bundle. | 5b583bd99562e14db554943d034c748ce302f5ee | Ambiguous — no live evidence |
| 202608060009 | 202608060009_sprint9_profiles_privacy.sql | Depends on profiles and offerings from 001; changes opt-in public identity, profile policies, and public projections. | 6594ce6daa0183944fcc548885d6514e8adb9436 | Ambiguous — no live evidence |
| 202608100010 | 202608100010_sprint9_2_community_identity_consistency.sql | Depends on 009 public identity projections and Auth profile bootstrap; replaces handle_new_user and community views. | 774708b7705d88a5a1e0da97e72a9d1b47c8884c | Ambiguous — no live evidence |
| 202608100011 | 202608100011_sprint9_3_moderation_aware_members.sql | Depends on profiles, offerings, and reflection policies; adds member_moderation_events and suspension-aware controls. | 1d1b7b844b88077351d2658af4be2b2db92eda97 | Ambiguous — no live evidence |
| 202608110012 | 202608110012_sprint10_1_daily_deed_completion.sql | SQL dependencies: daily_deed_completions from 001, daily_reflections.daily_post_id from Sprint 6 007, and daily_lights/daily_reflections.daily_light_id from Sprint 7 007. Both 007 bodies are required. | 0973f72e39ce07b41e053a20f1b781c394578877 | Ambiguous — no live evidence |
| 202608110013 | 202608110013_sprint10_2_saved_lights_gentle_rhythm.sql | SQL dependencies: saved_lights from 001 and daily_lights from Sprint 7 007. No SQL dependency on 012; the app-level gentle-rhythm experience consumes private completion records from 012. | 5fd2f4a796a8a1dfd6237ccf36d1ab62c1dc1714 | Ambiguous — no live evidence |
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

## File-level classification summary

| Required class | Migration files | Evidence-backed conclusion |
|---|---:|---|
| Verified applied and recorded | 0 | No Production history was readable. |
| Verified represented in schema but missing from history | 0 | No Production schema was readable. |
| Verified unapplied | 0 | No Production history or schema was readable. |
| Ambiguous / requires further evidence | 31 | All 31 repository files remain unclassified against Production. |

These counts are per migration file, not per unique version prefix: there are 31 files and 30 prefixes because two distinct files use 202607260007. The effect-level classification is also wholly unknown because no Production schema was readable. This does not mean none are applied; it means Production status is unknown.

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

### 4. SQL Editor bundle is not a verified full migration replay

supabase/run_in_sql_editor_all.sql is 7,136 lines, blob SHA 83725a196186f4fd913fab1cf5c9c02c9c6d822c. Byte-for-byte comparison against all 31 migration files found exact file content for 001, 002, and 009–030. The contents of migrations 003–008 were not byte-for-byte present. This bundle is therefore not a canonical byte-identical replay of the full migration directory.

**Do not treat run_in_sql_editor_all.sql as a verified full migration replay, a substitute for the individual migration files, or proof that any SQL was executed.** The source comparison below identifies concrete gaps in 007 and 008. It is a repository-content finding only: missing aggregate SQL effects do **not** prove those objects are absent from Production. They may have been applied manually, through a separate SQL Editor session, from another reviewed source, or by another deployment path. No Production schema was available to establish that.

#### 007 Sprint 6 — incomplete daily_posts representation

The Sprint 6 file (202607260007_sprint6_daily_deedlight.sql, blob e0c2379255003b8c7bc85a1fab781e23051f5e47) extends public.daily_posts and public.daily_reflections. The aggregate bundle's earlier public.daily_posts definition is a different shape: it uses date, theme_id, reflection, daily_action, and reflection_question, while the Sprint 6 migration adds a separate scheduled/editorial model. The bundle does not represent the Sprint 6 daily_posts additions as a complete effect set. Among the Sprint 6 additions not represented in the aggregate are scheduled_for (the bundle instead has date), kicker, theme, summary, body, small_deed, reflection_prompt, featured_offering_id, video_title, video_hook, video_script, video_caption, video_status, and archived_at. Overlapping names such as slug, title, status, image_url, and youtube_url do not establish equivalent definitions, defaults, constraints, or semantics.

The aggregate also omits the Sprint 6 named indexes:

- daily_posts_status_scheduled_idx
- daily_posts_featured_offering_idx
- daily_reflections_post_idx
- daily_reflections_user_idx

These are schema effects of the Sprint 6 file and must be checked individually against live catalog evidence; their absence from the bundle is not evidence that Production lacks them.

#### 007 Sprint 7 — daily_lights table DDL absent

The Sprint 7 file (202607260007_sprint7_pwa_daily_engagement.sql, blob 8b051cfce05ea75b1ee7a726864e2ad760f6fe5f) creates public.daily_lights, adds its columns/unique scheduled-date constraint, and configures its access policies; it also extends public.daily_reflections. The aggregate bundle contains zero CREATE TABLE public.daily_lights statements and zero ALTER TABLE public.daily_lights statements. It therefore does not provide the Sprint 7 table DDL or a verified substitute for its associated constraints, policies, and reflection changes.

This omission is particularly important because later SQL in the aggregate references public.daily_lights, including a foreign-key addition to public.daily_deed_completions around line 1501 and later queries/projections around lines 1589, 1630, 1768, and 2783. A clean replay of the aggregate can therefore fail when it reaches a reference to public.daily_lights if no earlier statement created that relation. No clean replay was executed in C242; this is a dependency conclusion from the checked-in SQL text.

#### 008 — short-video metadata and indexes absent

The Sprint 8 file (202607270008_sprint8_short_video_studio.sql, blob 5b583bd99562e14db554943d034c748ce302f5ee) alters public.daily_lights to add video_status, video_platform, video_hashtags, video_notes, video_asset_url, tiktok_url, instagram_url, short_video_public, and video_posted_at. It normalizes and constrains video_status, enforces the short_video_public default/not-null behavior, adds the daily_lights_video_status_check constraint, grants the intended table privileges, and creates three indexes:

- daily_lights_video_status_idx
- daily_lights_video_public_idx (partial index for public videos)
- daily_lights_video_posted_at_idx

The aggregate contains zero occurrences of these 008 column names and zero occurrences of the three named indexes. In particular, video_platform, video_hashtags, video_asset_url, and short_video_public are absent. The 008 column, constraint, grant, and index effects are not represented in the aggregate source.

#### Required reconciliation before any clean replay or history decision

1. Treat each of the two 007 files as a separate migration file despite their shared version prefix. Do not rename either file, guess which SQL body ran, or mark the shared version applied/reverted to resolve the collision.
2. Reconcile every missing/partial effect group from Sprint 6 007, Sprint 7 007, and 008 individually against the exact migration source and read-only Production catalog inventory. This includes columns and definitions/defaults, constraints, indexes, RLS policies, grants, triggers, and dependent objects.
3. Obtain retained SQL Editor execution history/audit logs, operator/timestamp details, and SQL hashes for any manual application of these files or the aggregate bundle. A copy of SQL is not an execution receipt.
4. Record any proven manual application as an evidence-backed schema/history discrepancy and obtain separate authorization before proposing any history-only repair or forward-only schema change.
5. Resolve the duplicate 007 mapping and missing prerequisites on a disposable database or restored clone before attempting a clean replay. Do not use the aggregate bundle as the replay authority.

Running SQL directly against a remote database can bypass Supabase CLI migration history unless history is separately reconciled. The bundle cannot prove application, non-application, or migration-history state.

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

Classification is performed at two linked levels:

1. **Individual migration file:** identify the full filename and Git blob SHA. Do not classify only a unique timestamp/version prefix or collapse two files that share one prefix.
2. **Individual schema effect:** within each file, classify each independently identifiable table, column, constraint, index, function, trigger, view, RLS policy, grant, extension, or data change. A file may be partially represented, partially applied, or contain drift; one overall file label must not hide mixed effect states.

Apply exactly one evidence-backed class to each file and each effect group:

- **Verified applied and recorded:** a remote history row exists and the live schema/function/security state matches the exact file and its effects. For a shared version prefix, the history row alone is insufficient to identify the file body.
- **Verified represented in schema but missing from history:** no remote history row exists, but all relevant effects match the exact file source, including functions, constraints, RLS, triggers, grants, and data-sensitive preconditions. This is only a candidate for later separately authorized history-only repair; it is not permission to run repair now.
- **Verified unapplied:** no history row exists, no effects are present, no partial state exists, and predecessor/data preconditions are satisfied. This is not permission to push now.
- **Ambiguous / requires further evidence:** partial effects, differing definitions/source, unverified manual edits, missing dependencies, duplicate version, contradictory history, or any uncertainty.

The file-level summary above counts 31 files, not 30 unique prefixes. Effect-level Production counts are not available because no Production schema was readable. For duplicate 202607260007, the two files and their schema effects must be independently reconciled; the shared timestamp cannot identify which SQL body was executed. Do not rename the files, guess the executed body, or repair migration history as a shortcut.

## Reconciliation plan after evidence is available

1. **Freeze:** keep the Production target guard, delivery kill switch, and Cron activation barriers intact. No push, repair, or manual DDL.
2. **Snapshot:** export remote history and schema evidence, retain audit records, capture a backup/PITR point, and verify project identity.
3. **Normalize inventory:** compare every local file and version prefix to remote history. Identify remote-only versions, local-only files, duplicate local prefixes, and files changed since execution.
4. **Resolve source ambiguity effect by effect:** compare both 007 files and 008 against the live Daily tables/columns, constraints, indexes, policies, grants, and SQL Editor/audit evidence. In particular, reconcile Sprint 6 daily_posts fields/indexes, Sprint 7 daily_lights DDL and reflection changes, and Sprint 8 video metadata/indexes. Verify 018/022 hotfixes and 023/024 source attestations and 027/029 function identity.
5. **Classify:** record the four status classes for each individual file and independently identifiable effect group, with reviewer and evidence reference. Never classify from filename, version prefix, code comments, aggregate SQL, or history alone.
6. **Design minimal reconciliation:** preserve already-applied schema and executed migration files. If represented but missing from history, prepare a separate reviewed history-only repair proposal after proof. If schema drift exists, create a forward-only migration preserving data. If genuinely unapplied, review dependencies and preconditions before any separate deployment approval.
7. **Test away from Production:** replay the individually reconciled migration sequence on an isolated disposable database or restored clone. Do not use run_in_sql_editor_all.sql as a verified full replay. Resolve the duplicate 007 mapping and missing 007/008 prerequisites before any clean replay. Verify schema, function source, RLS, grants, indexes, and application tests.
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

## C241 independent review acceptance

C241 independently accepted the repository-level migration reconciliation investigation and plan, subject to the documentation clarifications recorded in C242. The acceptance is limited to the quality/completeness of the repository investigation and its fail-closed next steps. It is not a statement about live Production state, does not classify any migration as applied/unapplied, and does not authorize a Production history or schema mutation. It is not a formal GitHub PR review submission or approval; the PR review endpoint remains a separate governance record.

## C242 documentation correction execution status

- Confirmed from repository source that Sprint 7 migration 007 creates public.daily_lights, while the aggregate bundle contains no CREATE TABLE or ALTER TABLE DDL for that relation.
- Confirmed the aggregate later references public.daily_lights, including a foreign-key addition around line 1501; a clean replay may fail if no earlier step supplied the table.
- Confirmed Sprint 8 migration 008's video metadata columns and three named indexes are absent from the aggregate bundle.
- Confirmed Sprint 6 migration 007's extended daily_posts fields and four named indexes are not fully represented in the aggregate bundle.
- Clarified that absence from the aggregate is repository-source evidence only and does not prove the corresponding objects are absent from Production.
- Changed classification guidance to apply to individual files and individual schema effects, not merely unique version prefixes.
- Preserved the duplicate 202607260007 restriction: no renaming, guessed execution mapping, history repair, or Production mutation.

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

## C245 — complete migration effect inventory and clean-replay analysis

**Repository evidence baseline (independently rechecked before this change):** repository ADRN-9/deedlight, repository ID 1308367373; branch security/delivery-transport-consent-gates; source HEAD d65da43a7fe3cebd17f2481a4c8fbb90faa3c17d; source tree e5d92f4e06504675d2145d5cdb976691a97eafa6; PR #10 OPEN / DRAFT / UNMERGED. The recursive Git tree is complete (not truncated) and contains 31 SQL files under supabase/migrations with 30 distinct filename version prefixes. The inventory below records Git blob identities and the SQL-declared repository effects, not proof of execution in Production.

### Per-file repository schema, data, dependency, and rollback inventory

Every entry is a separate migration file. Tables, columns, indexes, constraints, functions, triggers, views, policies, and grants below are read from the exact checked-in SQL file. "Runtime data" means effects of functions/triggers after deployment, not migration-time execution. Rollback notes identify risks, not a proposed rollback.

#### 202607210001 — 202607210001_initial_schema.sql
- **Git blob:** a244ab0df3e766b0f36e29a222b3160f9f74c502.
- **Tables and columns:** creates profiles (id, user_id, username, display_name, avatar_url, bio, country, role, is_verified, is_suspended, created_at, updated_at); themes (id, slug, name, description, icon_name, accent_color, created_at); daily_posts (id, date, slug, title, theme_id, reflection, daily_action, reflection_question, image_url, youtube_url, status, created_by, published_at, timestamps); offerings (identity/owner/theme/type/title/body/takeaway/media/anonymous/reflection/location/status/moderation fields, reaction/report counters, generated bless_score, publication and timestamps); reactions; reflections; reports; badges; user_badges; saved_lights; daily_deed_completions.
- **Indexes and constraints:** offerings_status_published_idx, offerings_bless_score_idx, offerings_user_id_idx, reactions_offering_id_idx, reactions_user_id_idx, saved_lights_unique_offering, saved_lights_unique_daily_post. Inline PK/FK/unique/check constraints enforce profile role, daily post status, Offering type/title/body/media/status/nonnegative counters, unique reaction per Offering/user/type, reflection body/status, report reason/status and at-least-one target, unique user badge, exactly one saved-light source, and unique completion by user/post/status.
- **Functions, triggers, views:** pgcrypto extension; set_updated_at, handle_new_user, handle_reaction_counts, handle_reflection_counts, handle_report_counts; timestamp triggers for profiles/daily_posts/offerings/reflections, Auth on_auth_user_created trigger, reaction insert/delete, reflection insert/update/delete, report insert/update/delete count triggers; initial offerings_public view.
- **Data and dependencies:** no one-time row backfill; future Auth signups create profiles and future reaction/reflection/report changes maintain denormalized Offering counters. Requires Supabase Auth and pgcrypto; foundational for every later public schema migration.
- **Rollback implications:** dropping foundational tables or extension-dependent functions destroys member content, private reflections, moderation records, saved items, and completion history. No destructive rollback is safe.

#### 202607210002 — 202607210002_rls_policies.sql
- **Git blob:** f96b482c0d1cf396baae5b91d7c96112f7e88284.
- **Tables and columns:** no table or column creation; enables RLS on profiles, themes, daily_posts, offerings, reactions, reflections, reports, badges, user_badges, saved_lights, and daily_deed_completions.
- **Indexes and constraints:** none.
- **Functions, triggers, policies, grants:** creates SECURITY DEFINER is_admin(). Adds profiles_public_read / profiles_own_update / profiles_admin_all; themes_public_read / themes_admin_all; daily_posts_public_published_read / daily_posts_admin_all; Offering public-approved, own-read, pending-insert, safe-status-update, and admin-all policies; reaction own insert/delete/read and admin-all; reflection public-visible/own-insert/own-update/admin-all; report own-insert/admin-all; badge and user-badge public-read/admin-all; saved_lights_own_all; daily_deed_completions_own_all. Inserts storage buckets daily-lights, offerings-media, profile-avatars, admin-assets (private), and share-cards; creates five storage.objects read/upload/update/admin policies.
- **Data and dependencies:** idempotent bucket inserts use ON CONFLICT DO NOTHING. Requires all 001 tables and Supabase Storage schema/objects.
- **Rollback implications:** removing or broadening RLS/policies can expose private data or permit unauthorized writes. Deleting buckets can orphan or destroy stored media. Policy removal is not an acceptable shortcut for later schema repair.

#### 202607220003 — 202607220003_sprint3_offerings_review.sql
- **Git blob:** 74e02f2e60b82cf07a6aac5f8cf57dcdb6fe1382.
- **Tables and columns:** no table/column changes.
- **Indexes and constraints:** offerings_status_created_idx and offerings_user_status_created_idx.
- **Functions, triggers, views, policies, grants:** replaces offerings_public projection and grants SELECT on that view to anon and authenticated; no function, trigger, or policy changes.
- **Data and dependencies:** no row backfill. Depends on 001 Offering schema and the 002 RLS baseline.
- **Rollback implications:** restoring an older public projection may re-expose fields or remove required moderation-safe projection behavior; dropping indexes can regress feed/review queries.

#### 202607260004 — 202607260004_sprint4_reactions.sql
- **Git blob:** c25dce46ecf69d082fcdbea2bb931b6acd9180fc.
- **Tables and columns:** changes behavior on reactions and offerings; no new columns/tables.
- **Indexes and constraints:** no new named index or constraint.
- **Functions, triggers, views, policies, grants:** replaces is_admin and handle_reaction_counts; recreates reactions_count_insert and reactions_count_delete triggers. Replaces reaction policies with reactions_select_own_or_admin, reactions_insert_own_on_approved, reactions_delete_own, reactions_admin_all. Creates/replaces offerings_rising and refreshes offerings_public. Grants public/authenticated reads to intended projections and authenticated reaction insert/delete; service_role receives schema/table authority.
- **Data and dependencies:** recomputes offerings reaction counters from reactions, so it is a real data update, not just DDL. Depends on 001 reactions/offerings and 002 RLS; uses the 003 Offering projection.
- **Rollback implications:** old trigger/function behavior can double-count or drift counters; restore would require recomputing counters and independently reviewing reaction RLS before changing it.

#### 202607260005 — 202607260005_sprint5_moderation.sql
- **Git blob:** b48b4b8b3eea9fb55b68068011fa1371559228c2.
- **Tables and columns:** changes offerings and reports behavior; no new columns/tables.
- **Indexes and constraints:** reports_status_created_idx, reports_offering_status_idx, offerings_open_report_count_idx.
- **Functions, triggers, views, policies, grants:** replaces is_admin and handle_report_counts; creates reports_count_insert/update/delete triggers. Replaces Offering select/insert/update policies and report select/insert/update/admin policies. Retains public/rising Offering projections and grants intended reads/writes; service_role receives table authority.
- **Data and dependencies:** recomputes offerings.open_report_count from reports and changes the ongoing report counter trigger behavior. Depends on 001 reports/offerings and 002/004 RLS and reaction behavior.
- **Rollback implications:** stale report counters can alter moderation/rising calculations. Reverting policies can allow unsafe Offering edits or report disclosure; any function rollback must be paired with a counter reconciliation.

#### 202607260006 — 202607260006_sprint5_admin_edit_hide_hotfix.sql
- **Git blob:** 9e163de5119c3813724341b7a9eabeba6fdc2970.
- **Tables and columns:** alters public.offerings; no new column.
- **Indexes and constraints:** a guarded DO block removes existing Offering status check constraints and adds offerings_status_check allowing draft, pending, approved, rejected, needs_edit, hidden.
- **Functions, triggers, views, policies, grants:** replaces offerings_update_own_or_admin policy, replaces offerings_public as a security_invoker view, and grants authenticated Offering SELECT/INSERT/UPDATE plus service_role authority and public projection SELECT.
- **Data and dependencies:** no migration-time row update. Depends on moderation policy/Offering baseline from 005.
- **Rollback implications:** reintroducing a narrower historical status check can fail on rows already using newer statuses. Changing security_invoker/view grants or the update policy can weaken public/member/admin boundaries.

#### 202607260007 — 202607260007_sprint6_daily_deedlight.sql
- **Git blob:** e0c2379255003b8c7bc85a1fab781e23051f5e47.
- **Tables and columns:** extends public.daily_posts with slug, scheduled_for, status, kicker, title, theme, summary, body, small_deed, reflection_prompt, featured_offering_id, image_url, video_title, video_hook, video_script, video_caption, youtube_url, video_status, published_at, archived_at, created_by, created_at, updated_at. Creates public.daily_reflections with user_id, daily_post_id, reflection_text, did_today_deed, mood_label, is_private, and timestamps.
- **Indexes and constraints:** daily_posts_status_scheduled_idx, daily_posts_featured_offering_idx, daily_reflections_post_idx, daily_reflections_user_idx; daily_posts_status_check, daily_posts_video_status_check, daily_posts_slug_unique, daily_reflections_unique_user_post.
- **Functions, triggers, policies, grants:** uses is_admin and replaces set_updated_at; creates daily post/reflection updated-at triggers. RLS policies: daily_posts_public_read_published, daily_posts_admin_all, daily_reflections_select_own_or_admin, daily_reflections_insert_own, daily_reflections_update_own, daily_reflections_delete_admin. Grants public/authenticated daily-post SELECT, authenticated daily-post/reflection CRUD, service_role full table authority.
- **Data and dependencies:** depends on 001 daily_posts/offerings/Auth and 002 RLS. Seeds one editable/published daily post only when daily_posts is empty. Its CREATE TABLE IF NOT EXISTS for daily_posts is normally a no-op after 001; the ALTER statements supply the later editorial fields.
- **Rollback implications:** deleting daily_posts or daily_reflections destroys editorial content and private reflections. Removing the seed row or its effects without identifying its provenance can damage a manually curated Daily Deedlight.

#### 202607260007 — 202607260007_sprint7_pwa_daily_engagement.sql
- **Git blob:** 8b051cfce05ea75b1ee7a726864e2ad760f6fe5f.
- **Tables and columns:** creates public.daily_lights with id, scheduled_date, status, kicker, title, theme, summary, small_deed, reflection_prompt, featured_offering_id, video_title, video_hook, video_script, archived_at, created_by, and timestamps. Extends/creates public.daily_reflections with daily_light_id, user_id, reflection, intention, and timestamps.
- **Indexes and constraints:** daily_lights_scheduled_date_unique and daily_reflections_daily_light_user_unique.
- **Functions, triggers, policies, grants:** no function/trigger creation. RLS policies: daily lights public read published, admin insert/update/delete; daily reflections select own/admin, insert own, update own/admin. Grants anon/authenticated SELECT daily_lights, authenticated Daily Lights write, authenticated reflection SELECT/INSERT/UPDATE, service_role full authority.
- **Data and dependencies:** depends on 001 offerings/Auth. It normalizes null daily_lights status/kicker/title and adds unique schedule constraints. It overlaps Sprint 6 on daily_reflections; its CREATE TABLE IF NOT EXISTS does not guarantee the other migration's daily_post_id column exists.
- **Rollback implications:** dropping daily_lights or shared daily_reflections can destroy Daily content and private intentions/reflections. Never treat the duplicate version as a single interchangeable migration.

#### 202607270008 — 202607270008_sprint8_short_video_studio.sql
- **Git blob:** 5b583bd99562e14db554943d034c748ce302f5ee.
- **Tables and columns:** alters public.daily_lights to add video_status, video_platform, video_hashtags, video_notes, video_asset_url, tiktok_url, instagram_url, short_video_public, video_posted_at.
- **Indexes and constraints:** daily_lights_video_status_idx, daily_lights_video_public_idx (partial on public videos), daily_lights_video_posted_at_idx; daily_lights_video_status_check for not_started/planned/scripted/recorded/posted/archived; video_status and short_video_public defaults/not-null.
- **Functions, triggers, policies, grants:** no function/trigger/policy changes; reasserts table grants for anon/authenticated/service_role.
- **Data and dependencies:** updates null video_status to not_started. Requires the Sprint 7 daily_lights table.
- **Rollback implications:** removing video columns loses production planning/publishing metadata and public visibility settings. The aggregate SQL bundle does not contain this migration's columns or indexes.

#### 202608060009 — 202608060009_sprint9_profiles_privacy.sql
- **Git blob:** 6594ce6daa0183944fcc548885d6514e8adb9436.
- **Tables and columns:** adds profiles.is_public (false), show_contribution_stats (true), default_offering_anonymous (false); tightens username nullability/format.
- **Indexes and constraints:** drops legacy username uniqueness, adds profiles_username_format_check and profiles_username_lower_key unique index on lower(username).
- **Functions, triggers, views, policies, grants:** replaces handle_new_user; creates profiles_own_read and profiles_own_update; replaces offerings_public and creates security-barrier profiles_public; revokes broad profile privileges and grants narrowly scoped authenticated column updates plus public-view SELECT.
- **Data and dependencies:** fills missing/blank usernames with generated member-* identifiers and lowercases/trims existing usernames. Depends on 001 profiles/Auth and pgcrypto; it changes existing member identity values.
- **Rollback implications:** username normalization is not losslessly reversible. Reverting profile/public views or grants can expose private profile fields or break opt-in identity privacy.

#### 202608100010 — 202608100010_sprint9_2_community_identity_consistency.sql
- **Git blob:** 774708b7705d88a5a1e0da97e72a9d1b47c8884c.
- **Tables and columns:** no table/column changes.
- **Indexes and constraints:** none.
- **Functions, triggers, views, policies, grants:** replaces handle_new_user; replaces security-barrier offerings_public and offerings_rising projections; revokes direct anon SELECT on public.offerings and grants SELECT on the intended public views. No new trigger or RLS policy.
- **Data and dependencies:** no migration-time row backfill. Depends on 009 profile identity and public projection contract.
- **Rollback implications:** restoring old views/direct base-table access can leak private Offering identity or reintroduce inconsistent anonymous/profile projections.

#### 202608100011 — 202608100011_sprint9_3_moderation_aware_members.sql
- **Git blob:** 1d1b7b844b88077351d2658af4be2b2db92eda97.
- **Tables and columns:** creates member_moderation_events(id, member_user_id, actor_user_id, action, reason, created_at), with suspended/restored action and bounded reason checks.
- **Indexes and constraints:** member_moderation_events_member_created_idx and member_moderation_events_actor_created_idx.
- **Functions, triggers, policies, grants:** RLS admin-select-only event policy; service_role-only table access. Creates admin_list_members, admin_get_member_context, set_member_suspension. Replaces Offering update and reflection insert/update policies to enforce suspension-aware community mutations. Grants controlled function EXECUTE to authenticated with internal admin checks.
- **Data and dependencies:** no migration-time backfill; set_member_suspension updates profiles.is_suspended and appends an audit event at runtime. Depends on profiles/offerings/reflections from 001 and moderation/security policy baseline 002/005.
- **Rollback implications:** dropping moderation events destroys suspension audit history; removing suspension-aware policies or function checks restores community mutation to suspended members.

#### 202608110012 — 202608110012_sprint10_1_daily_deed_completion.sql
- **Git blob:** 0973f72e39ce07b41e053a20f1b781c394578877.
- **Tables and columns:** adds daily_deed_completions.daily_light_id referencing daily_lights; makes daily_post_id nullable; makes daily_reflections.daily_post_id nullable.
- **Indexes and constraints:** daily_deed_completions_has_source and daily_reflections_has_daily_source require at least one Daily Post/Daily Light source; daily_deed_completions_user_light_unique, daily_deed_completions_light_created_idx, daily_deed_completions_user_created_idx.
- **Functions, triggers, views, policies, grants:** own-select, own-insert-published, own-delete completion policies; creates security-barrier daily_deed_completion_counts and grants SELECT to anon/authenticated/service_role; removes broad direct table privileges and grants authenticated SELECT/INSERT/DELETE.
- **Data and dependencies:** no migration-time source backfill. Requires 001 daily_deed_completions, Sprint 6 daily_post_id, Sprint 7 daily_lights/daily_light_id and daily_reflections. The source XOR constraints must be reconciled with actual rows before application.
- **Rollback implications:** dropping the new source columns/indexes or restoring NOT NULL can strand Daily Light completion/reflection records. Completion counts are member activity data and must not be deleted.

#### 202608110013 — 202608110013_sprint10_2_saved_lights_gentle_rhythm.sql
- **Git blob:** 5fd2f4a796a8a1dfd6237ccf36d1ab62c1dc1714.
- **Tables and columns:** adds saved_lights.daily_light_id referencing daily_lights.
- **Indexes and constraints:** replaces legacy saved_lights_check/exactly-one-source with saved_lights_exactly_one_source across offering_id/daily_post_id/daily_light_id; adds saved_lights_unique_daily_light and saved_lights_user_created_idx.
- **Functions, triggers, policies, grants:** replaces broad saved_lights_own_all with saved_lights_select_own, saved_lights_insert_own_published_daily_light, saved_lights_delete_own; authenticated gets SELECT/INSERT/DELETE only, no UPDATE. No new function/trigger.
- **Data and dependencies:** no migration-time row backfill. Direct SQL dependencies are saved_lights from 001 and daily_lights from Sprint 7 007. Migration 013 does not reference daily_deed_completions or objects created by 012, so 012 is not a SQL prerequisite. The product-level gentle-rhythm/Journey experience is related to the private completion records created/extended by 012; that is an application/data relationship, not a DDL dependency. Saves remain private and immutable.
- **Rollback implications:** dropping daily_light_id or reverting the XOR check can orphan/delete saved Daily Lights or permit malformed multi-source saves.

#### 202608120014 — 202608120014_sprint10_3_gentle_reminder_preferences.sql
- **Git blob:** 2af1a6a2aa5cffc6ef6d08849b6f71fab44a54d0.
- **Tables and columns:** creates daily_reminder_preferences(user_id, daily_enabled default false, reminder_time default 08:00, timezone default UTC, created_at, updated_at); timezone has length/character validation.
- **Indexes and constraints:** user_id primary key/FK to auth.users; timezone check.
- **Functions, triggers, policies, grants:** daily_reminder_preferences_set_updated_at trigger using set_updated_at; own SELECT/INSERT/UPDATE policies; authenticated receives those table privileges and service_role full privileges.
- **Data and dependencies:** no migration-time preference backfill; opt-in is false by default. Depends on auth.users and set_updated_at from 001.
- **Rollback implications:** dropping preferences loses explicit opt-in/timezone choices; broadening grants can expose private consent settings.

#### 202608130015 — 202608130015_sprint11_2_weekly_goodness.sql
- **Git blob:** 394c774032d8206c0b7a373640859c2a331667a9.
- **Tables and columns:** creates weekly_goodness_features(week_start, offering_id, selected_by, created_at, updated_at); Monday-only week_start check and Offering/Auth FKs.
- **Indexes and constraints:** reactions_created_offering_type_idx; weekly_goodness_features week_start primary key and Monday check.
- **Functions, triggers, policies, grants:** weekly_goodness_features_set_updated_at trigger; no browser-facing table policy; table privileges revoked from public/anon/authenticated and granted to service_role. Creates get_weekly_goodness(limit), get_current_weekly_goodness_feature(), set_weekly_goodness_feature(uuid) with narrow EXECUTE grants.
- **Data and dependencies:** no migration-time curation insert. set_weekly_goodness_feature performs replacement/upsert at runtime. Depends on 001 offerings/profiles, 004 reactions, and set_updated_at.
- **Rollback implications:** dropping weekly curation deletes editorial history; exposing the base table can allow unreviewed public curation.

#### 202608130016 — 202608130016_sprint11_3_invitations_newsletter_foundation.sql
- **Git blob:** 8d68ed19859e1a820af52a43c110a38b6a460d48.
- **Tables and columns:** creates invitation_links(id, inviter_user_id, code, accepted_count, expires_at, revoked_at, timestamps), invitation_acceptances(id, invitation_id, invited_user_id, accepted_at), newsletter_preferences(user_id, weekly_enabled default false, consented_at, unsubscribed_at, consent_source, timestamps).
- **Indexes and constraints:** invitation_links_inviter_created_idx, invitation_links_active_lookup_idx, invitation_acceptances_invitation_idx; unique invitation code and invited user; nonnegative accepted_count, bounded code, expiry-after-created, consent_source check.
- **Functions, triggers, policies, grants:** invitation_links and newsletter_preferences updated-at triggers; own-link and own-newsletter SELECT policies; acceptance table service_role only. Functions validate_invitation_code, create_invitation_link, revoke_invitation_link, set_newsletter_preference, record_invitation_acceptance, handle_growth_signup. Auth triggers on_auth_user_growth_insert and on_auth_user_growth_email_confirmed. Explicit table/function privilege revocation and narrow RPC grants.
- **Data and dependencies:** inserts newsletter_preferences with weekly_enabled=false for existing Auth users missing a row; this is a consent-safe disabled default, not consent. Signup/email-confirmation triggers and invitation RPCs write future rows. Depends on auth.users, profiles, pgcrypto, and set_updated_at.
- **Rollback implications:** dropping tables destroys invitation attribution, acceptance records, unsubscribe/consent timestamps and source. Do not backfill opt-in or reconstruct consent from signup alone.

#### 202608130017 — 202608130017_sprint12_1_offering_ownership_engagement.sql
- **Git blob:** bc23b12fe454c1f49b096fd2c7199e3a2aea5bb4.
- **Tables and columns:** adds offerings.owner_removed_at.
- **Indexes and constraints:** partial offerings_owner_removed_idx on owner and owner_removed_at where removed.
- **Functions, policies, grants:** tightens Offering insert/update policies; adds saved_lights_insert_own_published_source and approved-Offering reaction insertion policy. Creates update_own_offering, remove_own_offering, restore_own_offering with restricted EXECUTE grants.
- **Data and dependencies:** no migration-time backfill. Runtime edit updates Offering fields; remove soft-hides and timestamps owner removal; restore returns eligible content to pending moderation. Depends on offerings/reactions/saved_lights from 001, moderation rules 005/011 and saved-light model 013.
- **Rollback implications:** deleting owner_removed_at or bypassing soft-removal loses member control/auditability; never hard-delete Offering data to simulate a rollback.

#### 202608140018 — 202608140018_sprint12_1_owner_removal_guard_hotfix.sql
- **Git blob:** 0ea7eaf04d5c99e4c5a25893aae7694affdd44bc.
- **Tables and columns:** no new table/column/index.
- **Indexes and constraints:** replaces offerings_owner_removed_hidden check constraint.
- **Functions, grants:** replaces remove_own_offering(uuid) and revokes broad EXECUTE before granting authenticated EXECUTE.
- **Data and dependencies:** guarded preflight requires 017's owner_removed_at and remove_own_offering(uuid), and zero rows already owner-removed; replaces behavior but does not prove its own execution. Depends directly on 017. Header says it records a narrow Production repair, which remains an unverified repository assertion.
- **Rollback implications:** do not rerun blindly; the zero-row precondition can fail on real member records. Restoring the previous function/check can weaken the hidden-state invariant.

#### 202609230019 — 202609230019_sprint12_2_gentle_delivery_foundation.sql
- **Git blob:** 1403b9324e786a2b724176875a70ffce92961d9b.
- **Tables and columns:** creates delivery_ledger(id, user_id, kind, delivery_key, state, scheduled_for, claim_token, claimed_at, sent_at, failed_at, cancelled_at, provider_result_id, error_code, created_at, updated_at); unique (kind,user_id,delivery_key) and bounded kind/key/state/provider/error checks.
- **Indexes and constraints:** delivery_ledger_ready_idx and delivery_ledger_user_idx.
- **Functions, triggers, policies, grants:** delivery_ledger_set_updated_at trigger; RLS enabled with no browser access; service_role-only table privileges. Creates set_daily_reminder_preference, enqueue_due_daily_reminders, enqueue_weekly_goodness_delivery, claim_delivery_jobs, authorize_delivery_job, mark_delivery_sent, mark_delivery_failed; RPC execution is service_role-only except member preference setter.
- **Data and dependencies:** no migration-time ledger rows; functions enqueue/claim/authorize/update rows at runtime. Removes direct authenticated insert/update on reminder preferences so consent changes go through RPC. Depends on preferences 014, weekly curation 015, newsletter preferences 016, profiles and auth.users. Does not activate Cron or provider delivery.
- **Rollback implications:** dropping ledger destroys delivery audit/idempotency state; restoring direct preference writes weakens the narrow consent boundary.

#### 202609230020 — 202609230020_delivery_reliability_hardening.sql
- **Git blob:** 554615da3d15fc4c0d395691103d3be5676856fa.
- **Tables and columns:** extends delivery_ledger with claim_expires_at, attempt_count default 0, last_attempt_at, next_attempt_at.
- **Indexes and constraints:** delivery_ledger_retry_ready_idx; attempt_count 0–5 and claim lease/state consistency checks.
- **Functions, grants:** replaces claim_delivery_jobs, authorize_delivery_job, adds retry_delivery_job, replaces mark_delivery_sent and mark_delivery_failed; service_role-only EXECUTE.
- **Data and dependencies:** preflight refuses live claimed jobs. Migration clears claim_token and claim_expires_at for rows whose state is not claimed; it does not reset active claimed jobs. Depends on 019 ledger and RPC baseline.
- **Rollback implications:** removing expiry/retry metadata or restoring older RPCs can resurrect stale claims, unbounded retries or duplicate sends. Never clear live claims to force the migration.

#### 202609230021 — 202609230021_gentle_delivery_transport.sql
- **Git blob:** e50a06bd3a5ed386c54e789435c64b2bb4a54ab9.
- **Tables and columns:** adds delivery_ledger.transport_started_at.
- **Indexes and constraints:** none.
- **Functions, grants:** creates begin_delivery_transport(uuid,uuid) and enqueue_current_weekly_goodness_if_curated(timestamptz,integer), service_role-only.
- **Data and dependencies:** no migration-time backfill; runtime function records transport start and permits Weekly enqueue only for curated content. Depends on 020 lease/retry behavior and 015 weekly curation.
- **Rollback implications:** dropping transport_started_at loses evidence needed for safe idempotency horizons and retry decisions.

#### 202609240022 — 202609240022_auth_pgcrypto_schema_qualification.sql
- **Git blob:** f42afb3474f80c7d95cf5b47023b82cf5a948d4d.
- **Tables and columns:** none.
- **Indexes and constraints:** none.
- **Functions, triggers, policies, grants:** replaces public.handle_new_user() to call schema-qualified extensions.gen_random_bytes; no trigger recreation or explicit grant change in this file.
- **Data and dependencies:** future Auth profile bootstrap uses the qualified pgcrypto function; no migration-time row update. Requires pgcrypto installed in extensions and existing profile bootstrap. Header labels this a Production Auth hotfix but is not execution evidence.
- **Rollback implications:** restoring an unqualified function may fail under a restricted search_path and break new-user profile creation.

#### 202611120023 — 202611120023_delivery_consent_linearization.sql
- **Git blob:** 75f5086feab2cbda381066cb9094390190c3332f.
- **Tables and columns:** no table/column changes.
- **Indexes and constraints:** none.
- **Functions, comments, grants:** replaces enqueue_due_daily_reminders, enqueue_weekly_goodness_delivery and begin_delivery_transport; adds function comments deedlight:023:daily-exclusion-before-limit:v1, deedlight:023:weekly-exclusion-before-limit:v1 and deedlight:023:locked-consent-before-transport:v1; service_role-only EXECUTE.
- **Data and dependencies:** no migration-time row update. Rechecks consent/profile state at the relevant queue/transport boundary and serializes the final authorization. Depends on 019–021, 014/016 consent tables, 015 weekly curation, profiles and Auth.
- **Rollback implications:** reverting to earlier function bodies reintroduces consent/revocation races. Comments and exact source are preflight evidence for 024, not proof of Production execution.

#### 202611120024 — 202611120024_delivery_identity_lease_capacity.sql
- **Git blob:** 240271fd75081c062627cfc3d40bdc0c5feda049.
- **Tables and columns:** no new table/column/index.
- **Functions, constraints, grants:** preflight checks 023 comments, exact MD5 source fingerprints, SECURITY DEFINER, volatility, search_path and PL/pgSQL metadata. Replaces two-argument begin_delivery_transport with recipient-bound three-argument begin_delivery_transport(uuid,uuid,text), explicitly drops the old two-argument entry point, replaces enqueue_weekly_goodness_delivery and enqueue_current_weekly_goodness_if_curated; service_role-only EXECUTE.
- **Data and dependencies:** no migration-time row backfill. Runtime locks/checks confirmed Auth email identity and applies Weekly capacity limits. Requires exact reviewed 023 source, 019–021 ledger/RPCs, Auth and weekly curation.
- **Rollback implications:** restoring the two-argument transport path bypasses recipient identity binding; never bypass a failed source fingerprint or recreate the old overload without a new reviewed design.

#### 202611190025 — 202611190025_delivery_provider_webhooks.sql
- **Git blob:** e97c5c0ad645dfe43f11a88f01b030fa23dd5822.
- **Tables and columns:** creates delivery_provider_events(event_id, event_type, provider_email_id, recipient_email, bounce_type, received_at) and delivery_provider_suppressions(recipient_email, reason, provider_event_id, created_at, updated_at).
- **Indexes and constraints:** delivery_provider_events_email_id_idx; event ID/type/provider ID/email normalization/bounce type and bounce-event consistency checks; suppression reason enum and FK to provider event.
- **Functions, RLS, grants:** RLS enabled; direct table privileges revoked from public, anon, authenticated and service_role. Creates record_delivery_provider_event and replaces daily/weekly enqueue and begin_delivery_transport to enforce provider suppression before send; only narrow service_role RPC execution is granted.
- **Data and dependencies:** no migration-time provider rows; webhook RPCs write event and suppression records and future authorization checks them. Depends on 024 recipient-bound transport and 019 ledger.
- **Rollback implications:** deleting events/suppressions or restoring transport without suppression checks can re-enable delivery to bounced/complaining recipients and destroy provider audit evidence.

#### 202611190026 — 202611190026_delivery_provider_lifecycle.sql
- **Git blob:** 6a06d780ad65babf2293a2746c68913758313af8.
- **Tables and columns:** adds delivery_provider_events.provider_created_at and failure_class; creates delivery_provider_lifecycle(provider_email_id, status, status_rank, provider_created_at, received_at, event_id, failure_class, timestamps).
- **Indexes and constraints:** delivery_provider_lifecycle_status_idx; expands event types to sent/delivered/delayed/bounced/complained/suppressed/failed; checks provider timestamp exceptions, failure classification and lifecycle status/rank consistency.
- **Functions, RLS, grants:** RLS enabled on lifecycle; direct table privileges revoked including service_role. Creates record_delivery_provider_lifecycle_event and replaces record_delivery_provider_event; narrow service_role EXECUTE and function comment deedlight:026:provider-lifecycle-idempotent-monotonic:v1.
- **Data and dependencies:** no lifecycle backfill is declared; new lifecycle rows are written by webhook RPCs. Existing historical event rows may legitimately lack provider_created_at only for bounced/complained/suppressed according to the new check. Depends on 025.
- **Rollback implications:** dropping lifecycle removes provider event progression history; loosening status-rank monotonicity can permit stale provider events to overwrite newer outcomes.

#### 202611200027 — 202611200027_delivery_provider_integrity.sql
- **Git blob:** a1469938ea13b5cb9d7cd883772bc60e4a058026.
- **Tables and columns:** adds delivery_provider_events.suppression_reason and payload_fingerprint; creates delivery_provider_integrity_anomalies(event_id, related_event_id, anomaly_type, detected_at).
- **Indexes and constraints:** suppression reason check, 64-lowercase-hex payload fingerprint check, lifecycle status/rank extended with integrity_anomaly rank 80; anomaly self-reference check and unique dedupe index delivery_provider_integrity_anomalies_dedupe_idx.
- **Functions, RLS, grants:** anomaly table RLS enabled and all direct privileges revoked; replaces 9-, 8- and 7-argument record_delivery_provider_lifecycle_event overloads plus record_delivery_provider_event. Function comments attest the reviewed 027 implementation. RPCs remain service_role-only.
- **Data and dependencies:** no migration-time row backfill. Runtime signed-webhook handling records fingerprints, suppression reasons, duplicate/conflicting event anomalies and monotonic lifecycle outcomes. Depends on 025/026. The exact 9-argument function source is fingerprinted by 029.
- **Rollback implications:** dropping anomaly/fingerprint evidence weakens duplicate-event detection and forensic review; restoring older lifecycle functions can erase integrity anomaly semantics.

#### 202611210028 — 202611210028_delivery_claim_lock_expiry.sql
- **Git blob:** 09d1927fba81d711bb37d214609931d2da2173a1.
- **Tables and columns:** no table/column/index changes.
- **Functions, grants:** replaces authorize_delivery_job, retry_delivery_job, mark_delivery_sent and mark_delivery_failed using clock_timestamp() and strict claim-token/expiry checks under row-lock contention; revokes public/anon/authenticated EXECUTE and grants service_role only.
- **Data and dependencies:** no migration-time row update. Depends on 020 delivery ledger claim/retry functions.
- **Rollback implications:** reverting to transaction-start timestamps can let a lease appear valid after lock wait or permit stale-token transitions.

#### 202611210029 — 202611210029_delivery_legacy_replay_guard.sql
- **Git blob:** 872fc49ec47e49b17e96ecf6ccaf5c8eb0e6322a.
- **Tables and columns:** no table/column/index changes.
- **Functions, grants, comments:** preflight requires 027's 9/8/7-argument lifecycle RPCs, base provider event RPC, PL/pgSQL, SECURITY DEFINER, exact search_path, migration comment, pgcrypto and SHA-256 source fingerprint 8dbfc65b93677f9928114561d372dad69f16c9c746dadf80551c662161ba3ed5. Renames the 9-argument public function to _record_delivery_provider_lifecycle_event_fingerprinted_impl, revokes all privileges including service_role on the private implementation, and installs a canonical public fingerprint-enforcing wrapper plus legacy replay-only entry points. Public RPC grants remain service_role-only.
- **Data and dependencies:** no migration-time row update. Requires exact 027 function source and no pre-existing private implementation of unknown origin.
- **Rollback implications:** function rename/overload/ACL state is security-critical. Restoring fingerprint-less public entry points can admit unverified new provider events; never manually recreate the old function name without exact source and privilege review.

#### 202611210030 — 202611210030_delivery_idempotency_receipt_guard.sql
- **Git blob:** 42c227cc1c36b2889e88d9bee1432e6fc6829d41.
- **Tables and columns:** no table/column/index changes.
- **Functions, grants, comments:** preflight requires recipient-bound begin_delivery_transport(uuid,uuid,text), retry_delivery_job(uuid,uuid,timestamptz,text), mark_delivery_sent and delivery_ledger.transport_started_at. Creates service_role-only authorize_delivery_idempotency_window(uuid,uuid); replaces retry_delivery_job overloads and mark_delivery_sent with database-authoritative retry timing, claim/consent reauthorization, provider idempotency horizon enforcement and Resend receipt validation. Comments attest migration-030 contracts.
- **Data and dependencies:** no migration-time row update; runtime may terminally fail expired/ambiguous claimed jobs and records validated provider receipt IDs. Depends on 021 transport_started_at, 024 recipient-bound transport and 028 lock-safe transitions.
- **Rollback implications:** reverting the horizon or receipt validation can re-enable duplicate sends or accept unverified provider outcomes. Preserve terminal delivery ledger evidence.

### Duplicate-version and migration-order findings

1. **Duplicate 202607260007 is a real two-file collision, not a duplicate-content pair.** Sprint 6 blob e0c2379255003b8c7bc85a1fab781e23051f5e47 extends daily_posts and creates daily_reflections with daily_post_id; Sprint 7 blob 8b051cfce05ea75b1ee7a726864e2ad760f6fe5f creates daily_lights and a different daily_reflections shape with daily_light_id. Supabase migration history is version/timestamp keyed and cannot use one 202607260007 history row to identify both SQL bodies. Do not rename, reorder to conceal, mark applied/reverted, or infer which body ran.
2. **The two 007 files have an order-sensitive CREATE TABLE IF NOT EXISTS interaction.** If Sprint 6 creates daily_reflections first, Sprint 7 can add daily_light_id and its Daily Light uniqueness contract. If Sprint 7 creates daily_reflections first, Sprint 6's CREATE TABLE IF NOT EXISTS is skipped and its later ALTER statements do not add daily_post_id; migration 012 later expects daily_reflections.daily_post_id and can fail. This order hazard must be proven on an isolated PostgreSQL database using both permutations; no such full 007 replay is claimed here.
3. **008 depends on Sprint 7 daily_lights.** Migration 012 depends on both Daily Post and Daily Light source columns and the relevant tables. Migration 013 depends on saved_lights plus daily_lights. These are not safely replayable by treating the aggregate SQL bundle as canonical.
4. **The existing supabase/run_in_sql_editor_all.sql is not a full migration replay.** Prior source comparison found exact file content only for 001, 002 and 009–030; 003–008 are not byte-identically represented. It omits Sprint 6 additions/indexes, Sprint 7 daily_lights DDL and Sprint 8 video columns/indexes while later aggregate statements reference daily_lights. This is repository-source evidence only and says nothing about live Production presence/absence.
5. **Later guarded migrations have exact prerequisites:** 018 needs 017 and zero owner-removed rows; 020 rejects live claimed jobs; 023 needs the 019–021 baseline; 024 checks exact 023 comments/source hashes/security metadata; 025 needs recipient-bound 024 transport; 026 needs 025; 027 needs 025/026; 028 replaces 020 functions; 029 pins exact 027 function source/metadata and pgcrypto; 030 needs 021/024/028 state. A successful migration filename/history row alone does not prove these schema contracts.
6. **Automated migration-order coverage is not a complete historical replay.** The existing scripts/test-delivery-migration-order.sh covers the 021→023→024 consent attestation path, 025→027→029 source-identity guard, and 030 idempotency behavior. C247 adds scripts/test-duplicate-migration-007.sh, which executes both 007 orders through Supabase CLI 3.2.0 on disposable PostgreSQL 16, then verifies 008/012/013 dependencies. It does not prove a clean replay of all 31 migrations or any Production state.
7. **CREATE TABLE IF NOT EXISTS is not a schema attestation.** It can silently skip creation when a same-named table exists with a different column/constraint shape. Reconciliation must compare each effect and definition, not just object existence.

### Production classification and evidence required

- The repository inventory is 31 files / 30 version prefixes. **Production classification remains UNKNOWN for all 31 files and for every independently identifiable effect group.** Zero files are verified applied-and-recorded, zero represented-but-unrecorded, and zero verified unapplied; these zeros mean no classification evidence, not that nothing is installed.
- Existing Supabase access attempts for project xaipiovflxomcbfwtwmu were denied. No Production migration-history rows, catalog definitions, function source, RLS, grants, extension placement, SQL Editor audit records or Production counts have been retrieved.
- Required next evidence: authorized read-only project/database identity and timestamp; complete supabase_migrations.schema_migrations rows; public plus relevant auth/storage/extensions catalog inventories; columns/defaults/nullability; constraints and validation state; indexes and definitions; function definitions/identity args/SECURITY DEFINER/search_path/language/comments/source hashes; trigger definitions/enabled state; policy roles/commands/USING/WITH CHECK; table/function/schema/default privileges; extension namespace/version; relevant data counts (owner_removed_at rows and delivery claimed jobs); retained SQL Editor/audit/deployment records for 018, 022, 007/008 and aggregate bundle; immutable backup/PITR identity and tested restore evidence.
- The two 007 files and their effects must be independently classified. A single 202607260007 history row is not proof of either body. The 018/022 file headers are repository assertions, not execution receipts.
- Preserve the Production migration-target guard, delivery kill switch and Cron barriers. No db push, db pull, db reset, migration repair, remote SQL, manual DDL, credential access, scheduler/deployment mutation or delivery enablement is authorized by this inventory.

### C245 execution status and independent-review handoff

- Independently verified repository ID, branch, HEAD/tree and PR #10 before editing. Recursively inventoried all 31 migration blobs from the exact branch tree; the recursive tree was not truncated.
- Added per-file object/data/dependency/rollback notes and explicit 007/008/012/013 clean-replay hazards. No SQL migration, Supabase configuration, workflow, credential or Production resource was changed.
- The independent review should specifically verify the two 007 bodies and blob SHAs, the daily_reflections CREATE TABLE IF NOT EXISTS order hazard, the required 012 daily_post_id dependency, and the proposed disposable-database test matrix. Do not use Production to resolve replay ambiguity.
- This is repository-source documentation only. Production migration reconciliation remains BLOCKED pending authorized read-only access and independent evidence review. Production remains NO-GO.

## C247 — duplicate 007 execution-order and Supabase CLI verification

### Isolated runner and scope

- Source/test branch HEAD before this documentation update: 56785783f6fd00421a05586d4132274b3345dbad; tree f815740d7ee35a65d56af65251dad6e2aa9701a8. The branch was independently rechecked before edits.
- Added scripts/test-duplicate-migration-007.sh and extended the existing delivery_migration_order_database_behavior job. The job provisions an isolated PostgreSQL 16 service (observed server version 16.16) and installs Supabase CLI 3.2.0 with supabase/setup-cli@v1.
- The script copies both historical SQL bodies verbatim into temporary CLI projects. The reverse-order test uses temporary harness-only suffixes to force the reverse tie order; neither repository migration filename nor SQL content is renamed, reordered, or edited.
- Each CLI test uses its own disposable database and a minimal Auth/profile/Offering fixture. The test does not link a Supabase project, use a Production URL, or touch Production migration history.

### Actual Supabase CLI 3.2.0 results

**Sprint 6 007 → Sprint 7 007**

- CLI logs show it applying both files in order: 202607260007_sprint6_daily_deedlight.sql, then 202607260007_sprint7_pwa_daily_engagement.sql. The CLI does not reject the duplicate local version before executing the bodies.
- Both SQL bodies complete. The subsequent migration-history insert for the second file fails:
  - SQLSTATE: 23505 (unique_violation).
  - Constraint: schema_migrations_pkey.
  - Key: version 202607260007 already exists.
  - CLI statement number: 53.
  - Exact failing statement: INSERT INTO supabase_migrations.schema_migrations(version, name, statements) VALUES($1, $2, $3).
- Resulting database state: exactly one history row remains for 202607260007, with name sprint6_daily_deedlight; both Sprint 6 and Sprint 7 schema effects are present. The test asserts all 12 expected daily_reflections columns, both unique constraints, both Sprint 6 reflection indexes, both Sprint 6 update triggers, and all seven combined Sprint 6/Sprint 7 reflection policies.
- This is not an all-or-nothing rollback of the second file. Sprint 7 contains explicit BEGIN/COMMIT. Supabase CLI 3.2.0 executes a migration containing authored transaction control sequentially and records history only after the authored statements succeed. Sprint 7 commits before the CLI attempts the duplicate history insert, so its complete SQL body remains applied even though db push exits non-zero.

**Sprint 7 007 → Sprint 6 007**

- CLI logs show it applying the Sprint 7 body first and then attempting Sprint 6.
- Sprint 6 fails at the first use of the absent legacy source column:
  - SQLSTATE: 42703 (undefined_column).
  - CLI statement number: 37.
  - Exact failing statement: create index if not exists daily_reflections_post_idx on public.daily_reflections (daily_post_id).
  - PostgreSQL error: column "daily_post_id" does not exist.
- Resulting database state: exactly one history row remains for 202607260007, with the Sprint 7 harness filename as its name. The entire failed Sprint 6 migration is rolled back by the CLI's implicit per-file transaction. The test verifies that daily_posts and set_updated_at() do not remain, and that no Sprint 6 reflection columns, unique constraint, indexes, trigger, or policies survive.
- The surviving Sprint 7 daily_reflections table has id, daily_light_id, user_id, reflection, intention, created_at, updated_at; the daily_light/user unique constraint; and three Sprint 7 reflection policies. Both user_id and daily_light_id remain nullable. daily_post_id, reflection_text, did_today_deed, mood_label and is_private are absent.
- The source of the failure is the interaction of CREATE TABLE IF NOT EXISTS with the incompatible table shape. Sprint 7 creates daily_reflections without daily_post_id. Sprint 6's CREATE TABLE IF NOT EXISTS is skipped; its subsequent ALTER statements do not add daily_post_id and do not issue ALTER COLUMN user_id SET NOT NULL. The index statement therefore fails immediately, and the CLI rolls back all preceding Sprint 6 DDL.
- The missing Sprint 6 contract is broader than the one missing column: daily_reflections_unique_user_post, daily_reflections_post_idx, daily_reflections_user_idx, set_daily_reflections_updated_at, and the four Sprint 6 reflection policies are absent. The surviving Sprint 7 unique constraint does not restore Sprint 6's non-null user_id contract; PostgreSQL unique constraints permit multiple rows with NULL key values. Even a manual addition of daily_post_id alone would not make Sprint 6 enforce user_id NOT NULL, because that migration has no later nullability alteration for user_id.
- Migration 012 later requires daily_reflections.daily_post_id to exist before it can drop NOT NULL and add daily_reflections_has_daily_source. A Sprint 7-only state therefore cannot satisfy migration 012's SQL prerequisites.

### 008, 012, and 013 dependency tests

- PostgreSQL 16.16 positive sequence passed: Sprint 6 007 → Sprint 7 007 → 008 → 012 → 013.
- The test verifies Sprint 8's nine video-planning columns, status constraint and three indexes on daily_lights.
- It verifies migration 012's completion daily_light_id, nullable daily_post_id, source constraint, three indexes, three RLS policies and daily_deed_completion_counts view. It also verifies the daily_reflections source constraint, nullable daily_post_id, combined Sprint 6/Sprint 7 columns, constraints, indexes, update trigger and seven policies.
- It verifies migration 013's saved_lights.daily_light_id, exactly-one-source constraint, unique/index definitions, three RLS policies, and absence of authenticated UPDATE privilege.
- A second isolated replay applies 008, then 013, then 012. Migration 013 succeeds before 012; 012 subsequently installs the completion-source contract. This confirms that 013's direct SQL dependencies are saved_lights (001) and daily_lights (Sprint 7 007), not daily_deed_completions or migration 012. The phrase "gentle rhythm" describes an application-level relationship to private completion records; it is not a migration dependency.
- Migration 012, by contrast, has direct SQL dependencies on daily_deed_completions from 001, daily_reflections.daily_post_id from Sprint 6 007, and daily_lights plus daily_reflections.daily_light_id from Sprint 7 007. Both duplicate 007 bodies are prerequisites for 012. Migration 008 requires daily_lights from Sprint 7; it does not require Sprint 6's reflection table.

### CI evidence and limitations

- Branch-push validation #774: run 44965336520, SUCCESS, 7/7 jobs. Validate checked out exact branch HEAD 56785783f6fd00421a05586d4132274b3345dbad.
- PR integration validation #775: run 44965340590, SUCCESS, 7/7 jobs. Validate checked out synthetic merge commit 2a67ee7a686a6397925e85a9ccdc65dafcd49ac6, tree f815740d7ee35a65d56af65251dad6e2aa9701a8, parents ce82b3fdf1a73510de70e3729a487d4ae00e66e3 and 56785783f6fd00421a05586d4132274b3345dbad.
- The seven jobs in each run are validate, delivery_provider_webhook_database_behavior, delivery_migration_order_database_behavior, auth_pgcrypto_database_behavior, delivery_reliability_database_behavior, sprint12_2_database_behavior, and gentle_delivery_transport_database_behavior. All seven passed in both runs. The new duplicate-007 regression executes inside the existing migration-order job; the workflow remains seven jobs.
- The first harness attempt used db.major_version=16 in the temporary CLI config; CLI 3.2.0 rejected that config before running migrations. The harness config was corrected to target the external disposable PostgreSQL URL without setting a local-stack major_version. The subsequent #774/#775 runs passed. No Production SQL was run in either attempt.
- These results establish repository SQL behavior and the pinned CLI runner behavior only. They do not establish which migration body was executed in Production, the live schema shape, or the content of Production migration history.

### C247 handoff and Production disposition

- Do not rename or reorder the historical 007 files, mark either version applied/reverted, or use the isolated test result as evidence of Production execution.
- Next independent review should verify the new script and CI logs, especially the asymmetric transaction behavior (Sprint 7 commits before duplicate history insertion; Sprint 6 rolls back on SQLSTATE 42703) and the nullability/constraint gaps in the Sprint 7-first state.
- Production migration classification remains UNKNOWN for every file and effect group. Authorized read-only Production migration history, live catalog definitions, and retained SQL Editor/audit/deployment evidence are still required to determine which 007 body or bodies were actually applied.
- No Production migration history, schema, credentials, deployment configuration, scheduler, Cron, delivery setting, or external provider was changed. Production remains NO-GO.
