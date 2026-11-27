# DeedLight Production migration reconciliation ledger

**Status: NOT COLLECTED / UNCLASSIFIED for every migration.** This is a source-pinned semantic ledger and evidence plan, not a claim that any migration ran in Production.

- Repository: `ADRN-9/deedlight`
- Migration source baseline: `def0de7e33d57a05e2ee6e38e43796c24562b425`
- Inventory: `supabase/migration-inventory.json` (blob SHA-1 `95d514a0bd97ff448c9507252eb1f5e69a507442`)
- Files: 39; unique versions: 38; duplicate version: `202607260007` (two separate SQL files).
- Production database evidence: none collected; no Production connection/query made.

## Per-file semantic ledger

Each row is a distinct SQL file, including both Migration 007 files. Source references are exact file paths and line ranges in the pinned migration baseline. Function signatures below are the declarations in those files; later replacements are explicitly called out. The source fingerprint is the pinned Git blob SHA-1 from the migration inventory.

### 01. 202607210001 — Initial application schema

- **Source / fingerprint:** `supabase/migrations/202607210001_initial_schema.sql`, lines L13-L185 tables; L185-L203 signup; L207-L335 counter functions/triggers; L335-L360 public view; blob SHA-1 `a244ab0df3e766b0f36e29a222b3160f9f74c502`; 13648 bytes.
- **Schema and behavior:** Tables: `profiles`, `themes`, `daily_posts`, `offerings`, `reactions`, `reflections`, `reports`, `badges`, `user_badges`, `saved_lights`, `daily_deed_completions`; core identity/content columns, FKs and uniqueness for user/offering relationships. Indexes cover Offering status/published date, Bless score and owner; Saved Lights uniqueness for Offering and Daily Post. Triggers maintain `updated_at`, reaction/reflection/report counters. Functions: `public.set_updated_at()`, `public.handle_new_user()`, `public.handle_reaction_counts()`, `public.handle_reflection_counts()`, `public.handle_report_counts()`. `offerings_public` projection is created. Seed/signup and counter data writes are present; RLS is introduced by 002, not this file.
- **Preconditions / supersession:** Initial schema; no prior migration dependency. Verify `auth.users` FK target and `pgcrypto` availability. Superseded/extended by 002–018; do not infer current policy state from this baseline.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 02. 202607210002 — Core row-level security

- **Source / fingerprint:** `supabase/migrations/202607210002_rls_policies.sql`, lines L1-L15 helper; L16-L26 RLS flags; L28-L140 policies; L145-L181 storage bucket/policies; blob SHA-1 `f96b482c0d1cf396baae5b91d7c96112f7e88284`; 5885 bytes.
- **Schema and behavior:** Defines `public.is_admin()` and enables RLS on profiles, themes, daily_posts, offerings, reactions, reflections, reports, badges, user_badges, saved_lights and daily_deed_completions. Policies include public profile/theme/published-post reads, owner profile/reflection/reaction/report access, owner writes, and admin management; storage bucket plus `storage.objects` policies cover public media, Offering uploads, avatars and admin access.
- **Preconditions / supersession:** Requires 001 objects and Supabase Storage schema. Later 009, 011, 017, 035 and 036 replace or narrow selected policies; effective current policies must be read from `pg_policies`.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 03. 202607220003 — Offering review projection

- **Source / fingerprint:** `supabase/migrations/202607220003_sprint3_offerings_review.sql`, lines L4-L8 indexes; L10-L39 view and grant; blob SHA-1 `74e02f2e60b82cf07a6aac5f8cf57dcdb6fe1382`; 1064 bytes.
- **Schema and behavior:** Adds `offerings_status_created_idx` and `offerings_user_status_created_idx`; replaces `public.offerings_public` and grants SELECT to `anon` and `authenticated`. Projection is the public read boundary rather than a raw base-table grant.
- **Preconditions / supersession:** Requires 001 Offering schema. Supersedes the initial `offerings_public` view from 001; replaced again by 009/010.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 04. 202607260004 — Reaction semantics and rising projection

- **Source / fingerprint:** `supabase/migrations/202607260004_sprint4_reactions.sql`, lines L5-L9 grants; L12-L55 routines/counter changes; L57-L62 triggers; L67-L112 RLS/policies; L113-L147 rising view; blob SHA-1 `c25dce46ecf69d082fcdbea2bb931b6acd9180fc`; 4983 bytes.
- **Schema and behavior:** Grants schema usage and narrowly scoped Offering/reaction access, while granting service_role table access. Replaces `is_admin()` and `handle_reaction_counts()`, recalculates Offering counters, installs reaction count triggers, enables reaction RLS and replaces own/admin insert/delete/read policies. Adds `offerings_rising` view and read grant.
- **Preconditions / supersession:** Requires 001–003 reaction and Offering schema. Replaces 001/002 reaction helper/policies; 010 later replaces rising projection.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 05. 202607260005 — Moderation and report counting

- **Source / fingerprint:** `supabase/migrations/202607260005_sprint5_moderation.sql`, lines L5-L20 grants/indexes; L24-L39 admin helper; L42-L133 Offering/report policies; L134-L191 counter function/triggers/data; blob SHA-1 `b48b4b8b3eea9fb55b68068011fa1371559228c2`; 5775 bytes.
- **Schema and behavior:** Adds report status/Offering indexes and `offerings_open_report_count_idx`; grants authenticated report/Offering operations and service_role table access. Replaces `is_admin()` and `handle_report_counts()`, revises Offering and report RLS policies, adds counter triggers and reconciles existing report counters.
- **Preconditions / supersession:** Requires reports and Offering counter columns from 001. Supersedes 002 Offering/report policies and 001 report counter behavior; 011 adds member suspension context.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 06. 202607260006 — Admin edit/hide hotfix

- **Source / fingerprint:** `supabase/migrations/202607260006_sprint5_admin_edit_hide_hotfix.sql`, lines L5-L19 preflight; L20-L47 Offering schema/grants/policy; L48-L77 public view/grant; blob SHA-1 `9e163de5119c3813724341b7a9eabeba6fdc2970`; 2008 bytes.
- **Schema and behavior:** Preflight checks required Offering shape, adds/adjusts Offering hidden-state columns/constraints, grants authenticated SELECT/INSERT/UPDATE and service_role access, replaces the Offering update policy and `offerings_public` view/grant to support admin editing/hiding without exposing hidden rows.
- **Preconditions / supersession:** Requires 001–005 Offering schema and admin helper. Replaces 005 Offering update policy and 003 public view semantics.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 07. 202607260007 — Migration 007 — Sprint 6 Daily Deedlight

- **Source / fingerprint:** `supabase/migrations/202607260007_sprint6_daily_deedlight.sql`, lines L7-L22 helper/ACL; L24-L105 Daily Posts; L108-L129 Daily Reflections; L131-L202 triggers/RLS/policies; L202-L238 seed/remaining policies; blob SHA-1 `e0c2379255003b8c7bc85a1fab781e23051f5e47`; 9545 bytes.
- **Schema and behavior:** Adds/extends `daily_posts` with slug, scheduled date/status, editorial copy, featured Offering, image/video metadata, publish/archive timestamps and creator; adds indexes and constraints. Adds `daily_reflections` with user/post FKs, reflection text, completion/mood/privacy and timestamps. Replaces `is_admin()`/`set_updated_at()`, adds timestamp triggers, RLS and public-published/admin Daily Post policies plus owner/admin reflection policies; grants browser CRUD and service_role access. Seeds a Daily Post.
- **Preconditions / supersession:** Requires 001 `offerings` and Supabase `auth.users`. Later 036 removes admin/browser access to private reflection content. Shares version 007 with the independent Sprint 7 file below.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 08. 202607260007 — Migration 007 — Sprint 7 PWA Daily Engagement

- **Source / fingerprint:** `supabase/migrations/202607260007_sprint7_pwa_daily_engagement.sql`, lines L5-L63 Daily Lights schema, existing-row updates and indexes; L65-L80 Daily Reflections create/extend; L82-L93 uniqueness constraint; L95-L153 RLS/policies/grants; blob SHA-1 `8b051cfce05ea75b1ee7a726864e2ad760f6fe5f`; 6279 bytes.
- **Schema and behavior:** Creates `daily_lights` with schedule/status/editorial/featured Offering/video/archive/creator fields; updates existing `daily_lights` rows to normalize status/kicker/title and `updated_at`, then applies defaults, a scheduled-date uniqueness constraint and related indexes. Creates `daily_reflections` if absent or adds the listed Daily Light/user/reflection/intention/timestamp columns when missing; adds the `(daily_light_id,user_id)` uniqueness constraint. This file does not UPDATE or backfill existing `daily_reflections` rows. Enables RLS and defines published Daily Light, admin editorial, and owner/admin reflection policies; grants authenticated writes and service_role access.
- **Preconditions / supersession:** Requires existing Offering/auth objects; overlaps and extends the Sprint 6 Daily/reflection model. This is a separate SQL body with a separate blob fingerprint despite sharing version 007; migration history version alone cannot identify which body ran.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 09. 202607270008 — Short-video Daily Light fields

- **Source / fingerprint:** `supabase/migrations/202607270008_sprint8_short_video_studio.sql`, lines L6-L34 column/default/data changes; L35-L47 indexes/grants; blob SHA-1 `5b583bd99562e14db554943d034c748ce302f5ee`; 1890 bytes.
- **Schema and behavior:** Extends `daily_lights` with video status, script/metadata and posted-time fields; updates existing rows/defaults and adds `daily_lights_video_status_idx`, `daily_lights_video_public_idx` and `daily_lights_video_posted_at_idx`. Grants public read, authenticated editorial writes and service_role access.
- **Preconditions / supersession:** Requires Sprint 7 `daily_lights`. Supersedes/extends the initial Daily Light video metadata from 007 Sprint 7.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 10. 202608060009 — Profile and Offering privacy projections

- **Source / fingerprint:** `supabase/migrations/202608060009_sprint9_profiles_privacy.sql`, lines L6-L44 profile columns/data/index; L47-L74 signup; L75-L110 profile policies/ACLs; L111-L168 profiles_public; L169-L238 offerings_public/Offering ACLs; blob SHA-1 `6594ce6daa0183944fcc548885d6514e8adb9436`; 6031 bytes.
- **Schema and behavior:** Adds/normalizes profile display-name/username/public-identity fields and unique lower-case username index; replaces signup profile creation. Replaces profile policies with owner-only base reads/updates, revokes anon/authenticated broad base-table privileges, grants narrowly selected columns, creates `profiles_public`, and rebuilds `offerings_public` with privacy/anonymous projections. Drops broad Offering read policy and tightens grants.
- **Preconditions / supersession:** Requires 001 profile/Offering schema. Supersedes 002 public profile read and earlier public Offering base-table grants/views; 010 refines projection identity.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 11. 202608100010 — Community identity consistency

- **Source / fingerprint:** `supabase/migrations/202608100010_sprint9_2_community_identity_consistency.sql`, lines L8-L35 signup; L36-L85 offerings_public; L86-L138 offerings_rising and grants; blob SHA-1 `774708b7705d88a5a1e0da97e72a9d1b47c8884c`; 3294 bytes.
- **Schema and behavior:** Replaces `handle_new_user()` to keep signup/profile identity normalized; replaces `offerings_public` and `offerings_rising` projections and resets view grants/revokes so public identity/anonymous Offering semantics stay consistent.
- **Preconditions / supersession:** Requires 009 privacy projections. Supersedes 009 view definitions and signup behavior; no new table or data backfill.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 12. 202608100011 — Moderation-aware member administration

- **Source / fingerprint:** `supabase/migrations/202608100011_sprint9_3_moderation_aware_members.sql`, lines L11-L50 moderation table/index/RLS/ACL; L51-L275 member list/context RPCs; L277-L369 suspension RPC/data writes; L370-L487 Offering/reflection policies; blob SHA-1 `1d1b7b844b88077351d2658af4be2b2db92eda97`; 12225 bytes.
- **Schema and behavior:** Creates `member_moderation_events` with member/actor/action/reason/timestamp fields, indexes, RLS and admin-only read policy; removes broad browser table access and grants service_role. Adds admin RPCs `public.admin_list_members(p_state text default 'all')`, `public.admin_get_member_context(p_member_user_id uuid)`, `public.set_member_suspension(p_member_user_id uuid, p_suspended boolean, p_reason text)`, with explicit EXECUTE ACLs. Suspension writes update `profiles` and append moderation events. Tightens Offering safe-update and reflection owner policies.
- **Preconditions / supersession:** Requires 009 profile privacy and 001 Offering/reflection schema. Replaces selected 002/005/009 policies. Suspension affects community mutation rights; unrelated private member data must remain intact.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 13. 202608110012 — Daily Deed completion model

- **Source / fingerprint:** `supabase/migrations/202608110012_sprint10_1_daily_deed_completion.sql`, lines L13-L59 completion schema/constraints/indexes; L65-L128 RLS/policies/grants; L134-L158 aggregate view/ACL; L164-L183 reflection schema constraint; L185-L187 notify/commit; blob SHA-1 `0973f72e39ce07b41e053a20f1b781c394578877`; 4462 bytes.
- **Schema and behavior:** Schema-only changes: adds nullable `daily_light_id` with FK, drops NOT NULL from `daily_post_id`, adds the source-presence CHECK, and creates the unique `(user_id,daily_light_id)` plus two supporting indexes. Replaces completion RLS policies and table grants, creates the security-barrier `daily_deed_completion_counts` aggregate view and grants SELECT. Also drops NOT NULL from `daily_reflections.daily_post_id` and adds the daily-source CHECK. No application-table INSERT, UPDATE or DELETE/backfill is performed by this migration; its effects are DDL, policy/ACL changes and view definition.
- **Preconditions / supersession:** Requires 001 completion table and 007 reflection model. Supersedes initial completion table policy assumptions; view is a public aggregate, not a reflection projection.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 14. 202608110013 — Saved Lights and gentle rhythm

- **Source / fingerprint:** `supabase/migrations/202608110013_sprint10_2_saved_lights_gentle_rhythm.sql`, lines L12-L46 column/constraint/index changes; L52-L105 policies; L108-L120 ACLs/notify; blob SHA-1 `5fd2f4a796a8a1dfd6237ccf36d1ab62c1dc1714`; 2769 bytes.
- **Schema and behavior:** Schema and authorization changes only: adds nullable `daily_light_id` with FK, drops the two legacy source constraints, adds `saved_lights_exactly_one_source`, and creates the partial unique `(user_id,daily_light_id)` index plus the user/created index. Replaces RLS policies and grants so saves remain owner-private; service_role retains server access. No existing `saved_lights` application rows are normalized or backfilled by this migration.
- **Preconditions / supersession:** Requires 001 saved_lights and 007 daily_lights. Supersedes initial Saved Lights constraints/policies; Journey/Saved Lights remain private.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 15. 202608120014 — Gentle reminder preferences

- **Source / fingerprint:** `supabase/migrations/202608120014_sprint10_3_gentle_reminder_preferences.sql`, lines L7-L26 table/trigger; L27-L89 RLS/policies; L90-L105 grants; blob SHA-1 `2af1a6a2aa5cffc6ef6d08849b6f71fab44a54d0`; 2523 bytes.
- **Schema and behavior:** Creates `daily_reminder_preferences` with member, enabled/time/timezone and timestamps; adds updated-at trigger, RLS and owner select/insert/update policies; revokes broad browser access and grants only member preference operations plus service_role server access.
- **Preconditions / supersession:** Requires authenticated profiles and `set_updated_at()` from 001/007. Establishes opt-in preference storage; later delivery migrations recheck consent before transport.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 16. 202608130015 — Weekly Goodness curation

- **Source / fingerprint:** `supabase/migrations/202608130015_sprint11_2_weekly_goodness.sql`, lines L12-L55 index/table/trigger/ACL; L56-L164 weekly query RPC; L165-L230 current feature RPC; L231-L297 curation RPC/data writes; blob SHA-1 `394c774032d8206c0b7a373640859c2a331667a9`; 8089 bytes.
- **Schema and behavior:** Adds reaction lookup index and `weekly_goodness_features` curation table/updated-at trigger. Defines `public.get_weekly_goodness(p_limit integer default 12)`, `public.get_current_weekly_goodness_feature()` and `public.set_weekly_goodness_feature(p_offering_id uuid)` with explicit ACLs. Curation function replaces feature rows through delete/insert/update semantics; no leaderboard is introduced.
- **Preconditions / supersession:** Requires Offering/reaction schema and admin helper. Replaces weekly feature state on curation; 019/021 later enqueue only when a curated weekly feature exists.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 17. 202608130016 — Invitations and newsletter foundation

- **Source / fingerprint:** `supabase/migrations/202608130016_sprint11_3_invitations_newsletter_foundation.sql`, lines L11-L108 tables/indexes/triggers/RLS/ACL/default backfill; L109-L361 invitation/newsletter RPCs; L362-L446 signup handler/triggers; blob SHA-1 `8d68ed19859e1a820af52a43c110a38b6a460d48`; 12951 bytes.
- **Schema and behavior:** Creates `invitation_links`, `invitation_acceptances`, `newsletter_preferences` with inviter/member/code/status/revocation and consent fields; adds lookup/member indexes, timestamps, RLS and narrow owner/service_role ACLs. Backfills newsletter preference defaults. Functions: `validate_invitation_code(text)`, `create_invitation_link()`, `revoke_invitation_link(uuid)`, `set_newsletter_preference(boolean)`, `record_invitation_acceptance(uuid,text)`, `handle_growth_signup()`. Auth signup triggers initialize growth/newsletter preferences.
- **Preconditions / supersession:** Requires profiles/auth.users and existing `set_updated_at()`. Newsletter and invitation attribution remain private; delivery opt-in is revocable.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 18. 202608130017 — Offering ownership and member removal

- **Source / fingerprint:** `supabase/migrations/202608130017_sprint12_1_offering_ownership_engagement.sql`, lines L11-L20 columns/index; L21-L194 Offering/reaction policies/ACLs; L195-L330 update RPC; L331-L388 remove RPC; L389-L452 restore RPC; blob SHA-1 `bc23b12fe454c1f49b096fd2c7199e3a2aea5bb4`; 11901 bytes.
- **Schema and behavior:** Adds Offering owner-removal fields and `offerings_owner_removed_idx`; revises Offering/reaction policies and grants to allow owner edits/removal/restoration only through guarded RPCs. Defines `update_own_offering(uuid,text,text,text,text,text,text,boolean,boolean)`, `remove_own_offering(uuid)` and `restore_own_offering(uuid)`. RPCs update Offering visibility/removal state without destructive deletion.
- **Preconditions / supersession:** Requires existing Offering owner/status fields and moderation policy. Supersedes direct owner update assumptions from 005/006; 018 adds a critical historical precondition to removal.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 19. 202608140018 — Migration 018 owner-removal guard hotfix

- **Source / fingerprint:** `supabase/migrations/202608140018_sprint12_1_owner_removal_guard_hotfix.sql`, lines L8-L42 historical data preflight; L43-L52 constraints; L53-L125 guarded function/ACL; blob SHA-1 `0ea7eaf04d5c99e4c5a25893aae7694affdd44bc`; 2780 bytes.
- **Schema and behavior:** Preflight validates `public.offerings.owner_removed_at` and requires zero rows with `owner_removed_at IS NOT NULL` at migration execution time; adds hidden/removal consistency constraint and replaces `public.remove_own_offering(p_offering_id uuid)` with guarded state transitions and restricted EXECUTE ACL.
- **Preconditions / supersession:** Historical prerequisite is zero already-removed Offering rows at the exact execution point. A present-day zero count cannot prove that past precondition. Supersedes the 017 remove RPC; unresolved until contemporaneous pre-migration evidence exists.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 20. 202609230019 — Gentle delivery foundation

- **Source / fingerprint:** `supabase/migrations/202609230019_sprint12_2_gentle_delivery_foundation.sql`, lines L11-L93 preference setter/ledger schema; L94-L151 indexes/trigger/RLS; L152-L316 enqueue routines; L317-L580 claim/authorize/sent/failure routines; blob SHA-1 `1403b9324e786a2b724176875a70ffce92961d9b`; 15845 bytes.
- **Schema and behavior:** Replaces reminder preference setter and creates `delivery_ledger` with logical delivery identity, stream/member/schedule/state, attempts, claim/lease and provider receipt fields; adds ready/user indexes, updated-at trigger, RLS and service_role-only access. Adds `enqueue_due_daily_reminders(...)`, `enqueue_weekly_goodness_delivery(...)`, `claim_delivery_jobs(...)`, `authorize_delivery_job(uuid,uuid)`, `mark_delivery_sent(uuid,uuid,text)` and `mark_delivery_failed(uuid,uuid,text)` with narrow ACLs. Enqueue/claim/sent/failure routines write queue state.
- **Preconditions / supersession:** Requires 014 preferences and 015 Weekly Goodness. Establishes server-only queue foundation; subsequent 020–038 replace delivery functions and harden consent/provider behavior.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 21. 202609230020 — Delivery reliability hardening

- **Source / fingerprint:** `supabase/migrations/202609230020_delivery_reliability_hardening.sql`, lines L10-L99 preflight/ledger columns/data/index; L100-L205 claim; L206-L308 authorize; L309-L391 retry; L392-L492 sent/failure; blob SHA-1 `554615da3d15fc4c0d395691103d3be5676856fa`; 13642 bytes.
- **Schema and behavior:** Preflight validates legacy ledger shape, adds retry/lease/idempotency/attempt metadata and ready indexes, normalizes existing ledger state. Replaces `claim_delivery_jobs(now,limit)`, `authorize_delivery_job(uuid,uuid)`, `retry_delivery_job(uuid,uuid,timestamptz,text)`, `mark_delivery_sent(uuid,uuid,text)` and `mark_delivery_failed(uuid,uuid,text)`; applies bounded retries, claim expiry and state transitions with service_role-only EXECUTE grants.
- **Preconditions / supersession:** Requires 019 delivery_ledger. Supersedes 019 claim/authorization/sent/failure implementations; later 028–031 refine expiry and provider idempotency/suppression.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 22. 202609230021 — Gentle delivery transport boundary

- **Source / fingerprint:** `supabase/migrations/202609230021_gentle_delivery_transport.sql`, lines L6-L32 preflight/ledger transport column; L33-L74 transport RPC/ACL; L75-L123 curated weekly enqueue/ACL; blob SHA-1 `e50a06bd3a5ed386c54e789435c64b2bb4a54ab9`; 3417 bytes.
- **Schema and behavior:** Preflight checks ledger state; adds transport lifecycle state and defines `begin_delivery_transport(p_job_id uuid,p_claim_token uuid)` plus `enqueue_current_weekly_goodness_if_curated(p_now timestamptz default now(),p_limit integer default 5000)`. Updates ledger transport state and applies explicit server-only EXECUTE ACLs.
- **Preconditions / supersession:** Requires 019–020 ledger. Supersedes direct queue-to-send assumptions; 024/025 later replace transport signature with recipient identity checks.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 23. 202609240022 — Auth pgcrypto schema qualification

- **Source / fingerprint:** `supabase/migrations/202609240022_auth_pgcrypto_schema_qualification.sql`, lines L13-L20 preflight; L21-L48 signup function; blob SHA-1 `f42afb3474f80c7d95cf5b47023b82cf5a948d4d`; 1214 bytes.
- **Schema and behavior:** Preflight verifies the extension/function shape and replaces `public.handle_new_user()` to use schema-qualified pgcrypto functions, preventing search_path-dependent extension resolution during signup.
- **Preconditions / supersession:** Requires pgcrypto installed in its expected schema and existing profiles/auth signup trigger. Supersedes signup implementation from 009/010.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 24. 202611120023 — Delivery consent linearization

- **Source / fingerprint:** `supabase/migrations/202611120023_delivery_consent_linearization.sql`, lines L5-L25 preflight; L26-L100 daily enqueue; L101-L181 weekly enqueue; L182-L297 transport authorization; blob SHA-1 `75f5086feab2cbda381066cb9094390190c3332f`; 9411 bytes.
- **Schema and behavior:** Preflight validates delivery function targets; replaces daily/weekly enqueue and `begin_delivery_transport(uuid,uuid)` so current consent is checked in the transaction that linearizes transport authorization. Queue inserts and ledger state updates remain server-only with explicit EXECUTE ACLs.
- **Preconditions / supersession:** Requires 019–021 functions and current preference tables. Supersedes earlier enqueue/transport functions; queue claims alone are not send authorization.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 25. 202611120024 — Delivery identity and lease capacity

- **Source / fingerprint:** `supabase/migrations/202611120024_delivery_identity_lease_capacity.sql`, lines L3-L62 preflight; L63-L169 identity-bound transport; L170-L283 weekly enqueue; L284-L328 curated weekly enqueue; blob SHA-1 `240271fd75081c062627cfc3d40bdc0c5feda049`; 12329 bytes.
- **Schema and behavior:** Preflight checks the existing transport routine; replaces `begin_delivery_transport(uuid,uuid,text)` with expected recipient identity, updates lease/transport state and reworks weekly enqueue/curation functions. Functions: `enqueue_weekly_goodness_delivery(date,timestamptz,integer)` and `enqueue_current_weekly_goodness_if_curated(timestamptz,integer)`; ACLs remain service-only.
- **Preconditions / supersession:** Requires 023 consent-linearized transport. Supersedes two-argument transport signature and prior weekly enqueue implementations; recipient identity must be revalidated immediately before send.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 26. 202611190025 — Provider webhook foundation

- **Source / fingerprint:** `supabase/migrations/202611190025_delivery_provider_webhooks.sql`, lines L6-L67 provider tables/index/RLS/ACL; L68-L169 event RPC; L170-L361 enqueue routines; L362-L493 expected-email transport; blob SHA-1 `e97c5c0ad645dfe43f11a88f01b030fa23dd5822`; 17132 bytes.
- **Schema and behavior:** Preflight validates provider schema; creates `delivery_provider_events` and `delivery_provider_suppressions` with provider/event/recipient identifiers, event type and suppression fields; adds event lookup index, RLS and revoked browser ACLs. Adds `record_delivery_provider_event(text,text,text,text,text)` and replaces daily/weekly enqueue and expected-email transport routines. Provider events/suppressions and ledger are written by service-role RPCs.
- **Preconditions / supersession:** Requires 024 provider-aware transport and delivery ledger. Supersedes 024 enqueue/transport functions; recipient email and provider event contents are private and excluded from evidence exports.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 27. 202611190026 — Provider lifecycle normalization

- **Source / fingerprint:** `supabase/migrations/202611190026_delivery_provider_lifecycle.sql`, lines L13-L48 event constraints; L49-L103 lifecycle table/index/RLS; L104-L367 lifecycle RPC; L368-L406 event wrapper; blob SHA-1 `6a06d780ad65babf2293a2746c68913758313af8`; 13857 bytes.
- **Schema and behavior:** Adds provider event constraints and `delivery_provider_lifecycle` with lifecycle ordering/state fields, indexes, RLS and restricted ACLs. Defines `record_delivery_provider_lifecycle_event(...)` and replaces provider event wrapper; inserts lifecycle, suppression and event records while normalizing bounce/complaint/delivery states.
- **Preconditions / supersession:** Requires 025 provider event/suppression tables. Supersedes 025 event semantics and introduces ordered lifecycle records; 027 adds anomaly capture.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 28. 202611200027 — Provider integrity anomaly model

- **Source / fingerprint:** `supabase/migrations/202611200027_delivery_provider_integrity.sql`, lines L5-L89 constraints/anomaly table/index/RLS; L90-L483 lifecycle logic; L484-L569 overloads; L570-L608 provider event wrapper; blob SHA-1 `a1469938ea13b5cb9d7cd883772bc60e4a058026`; 20879 bytes.
- **Schema and behavior:** Adds provider event/lifecycle consistency constraints and `delivery_provider_integrity_anomalies` with dedupe index, RLS and revoked browser ACLs. Replaces `public.record_delivery_provider_lifecycle_event(p_event_id text,p_event_type text,p_provider_email_id text,p_recipient_email text,p_provider_created_at timestamptz,p_bounce_type text,p_failure_class text,p_suppression_reason text,p_payload_fingerprint text)` and its 8-argument and 7-argument overloads; replaces `public.record_delivery_provider_event(p_event_id text,p_event_type text,p_provider_email_id text,p_recipient_email text,p_bounce_type text default null)`. Writes anomaly/lifecycle/suppression rows and hardens routine ACLs/comments.
- **Preconditions / supersession:** Requires 025–026 provider schema. Supersedes 026 lifecycle/event functions; anomaly payloads/recipient emails are sensitive. 037 later replaces anomaly-first handling with case/evidence/history.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 29. 202611210028 — Delivery claim lock expiry

- **Source / fingerprint:** `supabase/migrations/202611210028_delivery_claim_lock_expiry.sql`, lines L5-L15 preflight; L16-L85 authorize; L86-L139 retry; L140-L176 sent; L177-L216 failed; blob SHA-1 `09d1927fba81d711bb37d214609931d2da2173a1`; 9643 bytes.
- **Schema and behavior:** Replaces `authorize_delivery_job(uuid,uuid)`, `retry_delivery_job(uuid,uuid,timestamptz,text)`, `mark_delivery_sent(uuid,uuid,text)` and `mark_delivery_failed(uuid,uuid,text)` to enforce current claim token/lease expiry and fail closed on stale claims; all four functions explicitly revoke browser/PUBLIC EXECUTE and grant service_role only.
- **Preconditions / supersession:** Requires 020 reliability ledger fields. Supersedes 020 lifecycle transitions; stale claim tokens must not authorize sends or state changes.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 30. 202611210029 — Legacy provider replay guard

- **Source / fingerprint:** `supabase/migrations/202611210029_delivery_legacy_replay_guard.sql`, lines L5-L58 preflight/legacy rename; L59-L125 wrapper; L126-L175 ACL/comment controls; blob SHA-1 `872fc49ec47e49b17e96ecf6ccaf5c8eb0e6322a`; 7476 bytes.
- **Schema and behavior:** Preflight validates and renames the prior provider lifecycle implementation to a private legacy routine, then installs a guarded wrapper `record_delivery_provider_lifecycle_event(...)` and reasserts routine ACLs/comments so legacy replay paths cannot bypass the newer provider ordering/integrity path.
- **Preconditions / supersession:** Requires 027 lifecycle overloads and 028 claim guards. Supersedes direct legacy lifecycle entrypoint; exact rename and ACL state must be verified.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 31. 202611210030 — Delivery idempotency receipt guard

- **Source / fingerprint:** `supabase/migrations/202611210030_delivery_idempotency_receipt_guard.sql`, lines L3-L93 preflight; L94-L123 idempotency RPC; L124-L183 retry overloads; L184-L215 sent/ACL; blob SHA-1 `c5e3955c4e0dde708a8ffdc9c420807c4241fa32`; 12214 bytes.
- **Schema and behavior:** Preflight validates idempotency metadata; adds `authorize_delivery_idempotency_window(uuid,uuid)`, replaces retry overloads and `mark_delivery_sent(uuid,uuid,text)` so ambiguous prior provider outcomes and retry windows transition to failed/queued only under stable receipt rules. ACLs are service_role-only.
- **Preconditions / supersession:** Requires 028 lease-expiry behavior. Supersedes earlier retry/sent functions; provider receipt state and bounded safe retry horizon must match.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 32. 202611220031 — Final recipient suppression gate

- **Source / fingerprint:** `supabase/migrations/202611220031_delivery_final_recipient_suppression_gate.sql`, lines L5-L20 preflight; L21-L177 authorization/suppression/state transitions; L178-L189 ACL; blob SHA-1 `26d69a0a4e73bc7cfd05814f3f6129bc199da02b`; 6477 bytes.
- **Schema and behavior:** Preflight checks suppression prerequisites; replaces `authorize_delivery_idempotency_window(p_job_id uuid,p_claim_token uuid,p_expected_email text)` to bind the final send decision to recipient identity and current provider suppression state; updates delivery ledger failure/state fields and restricts EXECUTE.
- **Preconditions / supersession:** Requires 030 idempotency receipt guard and provider suppression tables. Supersedes two-argument authorization; recipient suppression is checked at final transport boundary.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 33. 202611220032 — Resend suppression-list synchronization

- **Source / fingerprint:** `supabase/migrations/202611220032_resend_suppression_list_sync.sql`, lines L5-L74 provider constraints/index; L75-L99 suppression state table/RLS/ACL; L100-L373 suppression event routine and state writes; L374-L391 ACL; blob SHA-1 `6a0c0193d85ece99335f8715a65243ac42617f97`; 14118 bytes.
- **Schema and behavior:** Adds provider event/suppression identity constraints and `delivery_provider_suppression_state` with RLS, index and revoked browser access. Defines `record_delivery_provider_suppression_event(...)`; updates event/anomaly/lifecycle/state/suppression records and deletes stale suppression rows under source-order rules; service-only EXECUTE.
- **Preconditions / supersession:** Requires 027 anomaly and 026 lifecycle structures. Supersedes prior generic suppression ingestion; 033/034 refine cross-stream ordering and timestamps.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 34. 202611220033 — Cross-stream suppression ordering

- **Source / fingerprint:** `supabase/migrations/202611220033_delivery_cross_stream_suppression_order.sql`, lines L5-L17 preflight; L18-L111 lifecycle/suppression ordering; L112-L130 ACL/comment; blob SHA-1 `1cd0c2db5415a37b9a31ed8ef7de54db9019a88f`; 4647 bytes.
- **Schema and behavior:** Preflight validates lifecycle ordering and replaces `record_delivery_provider_lifecycle_event(...)` to reconcile suppression events across event/lifecycle streams and remove stale suppression entries in deterministic source order; retains service-only ACL.
- **Preconditions / supersession:** Requires 032 suppression state and lifecycle structures. Supersedes 032 ordering semantics; 034 later changes timestamp tie-breaking.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 35. 202611230034 — Suppression timestamp ordering

- **Source / fingerprint:** `supabase/migrations/202611230034_delivery_suppression_timestamp_order.sql`, lines L5-L9 index; L10-L299 suppression routine and event/anomaly/state writes; L300-L317 ACL/comments; blob SHA-1 `4ec8aa578ad851918f4c4b2535c476b4ceb40f1d`; 11255 bytes.
- **Schema and behavior:** Adds `delivery_provider_events_generic_suppression_order_idx` and replaces `record_delivery_provider_suppression_event(...)` to compare provider/source timestamps, preserve deterministic suppression state, insert anomaly evidence and delete only superseded suppression rows; reasserts service-only ACL.
- **Preconditions / supersession:** Requires 032–033 event/lifecycle/suppression tables. Supersedes 032/033 timestamp ordering behavior; current ordering must be checked against index and routine definition.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 36. 202611230035 — Private Offering base-table RLS

- **Source / fingerprint:** `supabase/migrations/202611230035_private_offering_base_table_rls.sql`, lines L1-L16 policy drops; blob SHA-1 `3d0ce8dfd4abb88fccccd23c5ffb9c35f699c098`; 564 bytes.
- **Schema and behavior:** Drops broad/public SELECT policies `offerings_select_public_or_own` and `offerings_public_approved_read` from `public.offerings`; does not delete Offering data or replace the public projection. Effective public access must flow through the intended projection and explicit grants.
- **Preconditions / supersession:** Requires the 009/010 Offering projection and existing base-table policies. Supersedes broad public base-table reads; 036 is separate reflection privacy boundary.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 37. 202611230036 — Private Daily Reflection admin isolation

- **Source / fingerprint:** `supabase/migrations/202611230036_private_daily_reflection_admin_isolation.sql`, lines L7-L65 RLS/policy replacement; L66-L82 privilege revokes/grants; blob SHA-1 `61a1fbf48b4557873ba6016e74fd3995bc62ba14`; 2042 bytes.
- **Schema and behavior:** Enables/retains RLS on `daily_reflections`, removes owner-or-admin/admin policies and creates owner-only SELECT/INSERT/UPDATE policies. Revokes broad privileges, grants authenticated SELECT/INSERT/UPDATE only as intended, removes browser DELETE and admin bypass; service_role retains server-only access.
- **Preconditions / supersession:** Requires 007 daily_reflections schema. Supersedes 007 admin reflection access and earlier 011 reflection policy amendments. Reflection contents are never evidence export material.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 38. 202611240037 — Provider conflict evidence and resolution history

- **Source / fingerprint:** `supabase/migrations/202611240037_delivery_provider_integrity_conflict_evidence.sql`, lines L7-L50 preflight; L51-L211 tables/indexes/RLS/ACL; L212-L301 immutable function/triggers and legacy backfill; L302-L482 conflict capture; L483-L921 provider wrappers; L922-L1166 admin review/resolution RPCs; blob SHA-1 `ac0449b50a881e3a895ef40a8eee28bea95a6ec0`; 44182 bytes.
- **Schema and behavior:** Preflight checks existing provider anomaly/lifecycle objects. Creates `delivery_provider_integrity_cases`, `delivery_provider_integrity_conflict_evidence`, `delivery_provider_integrity_conflict_history`, ordered/fingerprint indexes, RLS and revoked browser ACLs. Adds immutable evidence/history trigger function and triggers. Functions include `_deny_delivery_provider_integrity_audit_mutation()`, `_record_delivery_provider_integrity_conflict(p_recipient_email text,p_event_id text,p_related_event_id text,p_anomaly_type text,p_event_type text,p_provider_email_id text,p_provider_suppression_id text,p_provider_created_at timestamptz,p_bounce_type text,p_failure_class text,p_suppression_reason text,p_suppression_origin text,p_suppression_source_id text,p_suppression_created_at timestamptz,p_payload_fingerprint text,p_stored_event_id text,p_stored_recipient_email text)`, lifecycle/suppression wrappers, `admin_list_delivery_provider_integrity_conflicts(p_state text default 'open',p_limit integer default 100)`, `admin_list_delivery_provider_integrity_evidence(p_conflict_id bigint,p_limit integer default 100)`, `admin_list_delivery_provider_integrity_history(p_conflict_id bigint,p_limit integer default 100)`, `admin_resolve_delivery_provider_integrity_conflict(p_conflict_id bigint,p_resolution_note text)`. Backfill source semantics: inserts one case per grouped `(recipient_email, anomaly_type)` from anomaly rows joined to known provider events, with first/last detection timestamps; `ON CONFLICT (recipient_email, anomaly_type) DO NOTHING`. Then inserts evidence rows for anomaly records that join to the created case and a stored provider event (`coalesce(related_event_id,event_id)`), marking `evidence_source='legacy_anomaly_backfill'`; `ON CONFLICT DO NOTHING`. The SQL contains no expected row counts or completeness assertion. Orphaned anomalies or rows lacking either event join are excluded by the joins. Historical counts, skipped rows, conflicts and completeness remain unverified without contemporaneous execution evidence; do not infer them from current tables. Writes immutable history on later resolution; admin RPCs are explicitly gated.
- **Preconditions / supersession:** Requires 027 anomaly and 032 suppression state. Supersedes anomaly-only integrity representation with case/evidence/history. Recipient email, raw payload, notes and member identifiers must never be exported.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

### 39. 202611240038 — Provider lock ordering and paginated review

- **Source / fingerprint:** `supabase/migrations/202611240038_delivery_provider_integrity_lock_order_pagination.sql`, lines L5-L148 preflight/cursor indexes; L149-L641 lock-order/provider function replacements; L642-L967 paginated/admin RPCs; L968-L1030 ACLs; blob SHA-1 `38951751fc5abeb79b75c4e37e55da01262a18b8`; 43748 bytes.
- **Schema and behavior:** Preflight validates case/evidence/history shape; adds cursor/order indexes for cases and reopened history. Replaces provider lifecycle/event/suppression functions with a consistent lock order and defines keyset-paginated admin RPCs: `admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamptz,bigint)`, `admin_get_delivery_provider_integrity_conflict(bigint)`, `admin_list_delivery_provider_integrity_evidence_page(bigint,integer,timestamptz,bigint)`, `admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)`. Explicitly restricts provider ingestion to service_role and admin review RPCs to authenticated admin paths.
- **Preconditions / supersession:** Requires 037 case/evidence/history tables and RPCs. Supersedes 037 provider ingestion and non-paginated admin review routines; lock order, cursor index validity and ACLs must be verified.
- **Production classification:** `NOT COLLECTED / UNCLASSIFIED` — requires signed catalog/history evidence and independent source-effect review.

## Mandatory cross-file evidence gates

### Duplicate Migration 007

The Sprint 6 file `202607260007_sprint6_daily_deedlight.sql` (blob `e0c2379255003b8c7bc85a1fab781e23051f5e47`) and Sprint 7 file `202607260007_sprint7_pwa_daily_engagement.sql` (blob `8b051cfce05ea75b1ee7a726864e2ad760f6fe5f`) are independent SQL bodies sharing one version. A single `version=202607260007` history row cannot identify which body ran, nor prove both. Keep both ledger entries separate and Unknown until contemporaneous execution artifacts and independent catalog/data-effect corroboration resolve the ambiguity. Never mark either Production-matched from version alone.

### Migration 018 historical prerequisite

`202608140018_sprint12_1_owner_removal_guard_hotfix.sql` preflights the existence of `public.offerings.owner_removed_at` and requires `count(*) WHERE owner_removed_at IS NOT NULL = 0` at the actual migration execution point before adding the hidden/removal constraint and replacing `remove_own_offering(uuid)`. Evidence must be contemporaneous with execution. A current zero count cannot retroactively prove the prerequisite. If no contemporaneous snapshot/log exists, classify the prerequisite Unknown.

### Migrations 035–038 privacy/provider boundaries

- 035 removes broad public Offering base-table read policies; verify effective anon/authenticated ACLs, RLS flags, `offerings_public` definition and grants.
- 036 requires owner-only `daily_reflections` SELECT/INSERT/UPDATE, no admin bypass, no browser DELETE and service_role-only server access. Never export reflection values or identifiers.
- 037 requires private case/evidence/history tables, RLS, immutable audit triggers, unique fingerprint and ordering indexes, and narrowly gated capture/resolution RPCs. Its SQL backfill selects only anomaly rows satisfying both provider-event joins and uses conflict suppression; the migration contains no expected row counts or completeness assertion. Historical inserted/skipped/conflicting counts and completeness remain unverified without contemporaneous execution evidence. Recipient emails, payloads and resolution notes remain private.
- 038 requires lock-order consistency, cursor indexes, valid/ready/live index state, service_role-only provider ingestion and authenticated-admin-only paginated review RPCs. Never export row contents.

## Historical transformations and backfills

For each migration with data writes, the reviewer must map the exact SQL statement and predicate, affected relation/columns, insert/update/delete semantics, transaction scope, conflict handling, expected aggregate count, precondition and postcondition. Explicitly review: initial counter/seed writes (001, 004, 005, 007); Daily Light/reflection normalization (007 Sprint 7, 008); profile/username normalization (009); member suspension/audit writes (011); completion/Saved Light defaults and uniqueness (012–013); newsletter preference defaults and signup triggers (016); Offering ownership/removal state (017–018); delivery ledger state normalization and retry/lease transitions (019–024, 028–031); provider event/lifecycle/suppression transitions (025–034); legacy anomaly-to-case/evidence backfill (037), whose expected/actual counts and completeness are not stated by the source and remain unverified. Current state alone does not prove historical execution predicates.

No customer row contents may be exported. Use only approved aggregate counts and non-reversible, keyed aggregate fingerprints in the isolated evidence store; never commit member identifiers, emails, reflection content, provider payloads or low-entropy hashes.

## Backup and isolated restore gate

Before any future Production reconciliation mutation: (1) DBA records a supported PITR/backup restore point and immutable provider identifier; (2) restore into a segregated, access-controlled, network-isolated non-Production project with matching PostgreSQL/Supabase major version and extensions; (3) verify restore completion, schema/catalog parity, migration history, representative application invariants and delivery-disabled state; (4) capture redacted logs/digests without secrets or customer data; (5) obtain independent DBA/security approval and rollback plan. Backup existence alone is insufficient; restore verification is mandatory. This PR authorizes no Production migration-history edit or forward migration.

## Classification rules

Allowed states: Applied and verified; Schema represented but history ambiguous; Verified unapplied; Partial or drifted; Unknown. Every migration starts Unknown. A catalog fingerprint alone does not prove the SQL file executed; a history row alone does not prove every effect. Require exact source blob, signed read-only catalog snapshot, exact history identity, independently reviewed semantic map, execution identity/time where available, and migration-specific pre/postconditions. Migration 007 ambiguity is never auto-resolved; Migration 018 remains Unknown without contemporaneous prerequisite evidence.

## C525 supplemental source delta — Migration 039 (not Production evidence)

This section extends the historical C517 39-file baseline above without rewriting its original source fingerprints or classifications.

- Current branch inventory: `supabase/migration-inventory.json`, blob SHA-1 `4e63f31368d446e905f4f44565be73337c7188fb`.
- Current inventory size: 40 distinct SQL files, 39 unique version prefixes; the historical duplicate 007 pair remains unchanged.
- New source: `supabase/migrations/202611260039_delivery_kind_scoped_claims.sql`.
- Source blob SHA-1: `39eba637aa9f93fa77855f82f3fcc27b580b25da`; 6,177 bytes.
- Semantics: introduces service-role invoker RPCs for Daily `daily_reminder` and Weekly `weekly_newsletter` claims. Each uses literal kind predicates in lease-expiry cleanup, candidate selection and final row update; the old unrestricted claim RPC is revoked from application roles.
- The SQL Editor aggregate and pinned inventory are updated to include this exact source.

**Production classification remains NOT COLLECTED / UNCLASSIFIED.** Migration 039 has not been applied to Production, no Production migration-history record has been changed, and no Production catalog/history evidence has been collected for this migration. Do not infer execution from source presence, CI execution or SQL aggregate inclusion. Future reconciliation requires the same signed read-only catalog/history evidence and independent semantic review as every other migration.
