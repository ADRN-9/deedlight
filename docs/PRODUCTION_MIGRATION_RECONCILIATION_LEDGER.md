# DeedLight Production migration reconciliation ledger

**Status: NOT COLLECTED — no Production connection or query was made.** This is a source-pinned evidence planning ledger, not a statement that any migration is applied, absent, or Production-matched.

- Repository: `ADRN-9/deedlight`
- Source HEAD: `def0de7e33d57a05e2ee6e38e43796c24562b425`
- Inventory path: `supabase/migration-inventory.json`
- Inventory blob SHA-1: `95d514a0bd97ff448c9507252eb1f5e69a507442`
- Declared migration count: 39
- Declared unique version count: 38
- Intentional duplicate version: `202607260007` (two independent SQL files)
- Production evidence: none
- Every row below remains **NOT COLLECTED / UNCLASSIFIED** until backed by signed read-only Production evidence and independent semantic review.

## Per-migration ledger

| # | Version | Source file | Pinned Git blob SHA-1 | Bytes | Source-reviewed effect families | Additional evidence requirement | Production status |
|---:|---|---|---|---:|---|---|---|
| 01 | `202607210001` | `202607210001_initial_schema.sql` | `a244ab0df3e766b0f36e29a222b3160f9f74c502` | 13648 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 02 | `202607210002` | `202607210002_rls_policies.sql` | `f96b482c0d1cf396baae5b91d7c96112f7e88284` | 5885 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 03 | `202607220003` | `202607220003_sprint3_offerings_review.sql` | `74e02f2e60b82cf07a6aac5f8cf57dcdb6fe1382` | 1064 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 04 | `202607260004` | `202607260004_sprint4_reactions.sql` | `c25dce46ecf69d082fcdbea2bb931b6acd9180fc` | 4983 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 05 | `202607260005` | `202607260005_sprint5_moderation.sql` | `b48b4b8b3eea9fb55b68068011fa1371559228c2` | 5775 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 06 | `202607260006` | `202607260006_sprint5_admin_edit_hide_hotfix.sql` | `9e163de5119c3813724341b7a9eabeba6fdc2970` | 2008 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 07 | `202607260007` | `202607260007_sprint6_daily_deedlight.sql` | `e0c2379255003b8c7bc85a1fab781e23051f5e47` | 9545 | Source-reviewed SQL effects; see pinned migration source. | Duplicate version 007 (Sprint 6). Must remain independently identified; history row cannot prove both files. | NOT COLLECTED |
| 08 | `202607260007` | `202607260007_sprint7_pwa_daily_engagement.sql` | `8b051cfce05ea75b1ee7a726864e2ad760f6fe5f` | 6279 | Source-reviewed SQL effects; see pinned migration source. | Duplicate version 007 (Sprint 7). Must remain independently identified; history row cannot prove both files. | NOT COLLECTED |
| 09 | `202607270008` | `202607270008_sprint8_short_video_studio.sql` | `5b583bd99562e14db554943d034c748ce302f5ee` | 1890 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 10 | `202608060009` | `202608060009_sprint9_profiles_privacy.sql` | `6594ce6daa0183944fcc548885d6514e8adb9436` | 6031 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 11 | `202608100010` | `202608100010_sprint9_2_community_identity_consistency.sql` | `774708b7705d88a5a1e0da97e72a9d1b47c8884c` | 3294 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 12 | `202608100011` | `202608100011_sprint9_3_moderation_aware_members.sql` | `1d1b7b844b88077351d2658af4be2b2db92eda97` | 12225 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 13 | `202608110012` | `202608110012_sprint10_1_daily_deed_completion.sql` | `0973f72e39ce07b41e053a20f1b781c394578877` | 4462 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 14 | `202608110013` | `202608110013_sprint10_2_saved_lights_gentle_rhythm.sql` | `5fd2f4a796a8a1dfd6237ccf36d1ab62c1dc1714` | 2769 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 15 | `202608120014` | `202608120014_sprint10_3_gentle_reminder_preferences.sql` | `2af1a6a2aa5cffc6ef6d08849b6f71fab44a54d0` | 2523 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 16 | `202608130015` | `202608130015_sprint11_2_weekly_goodness.sql` | `394c774032d8206c0b7a373640859c2a331667a9` | 8089 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 17 | `202608130016` | `202608130016_sprint11_3_invitations_newsletter_foundation.sql` | `8d68ed19859e1a820af52a43c110a38b6a460d48` | 12951 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 18 | `202608130017` | `202608130017_sprint12_1_offering_ownership_engagement.sql` | `bc23b12fe454c1f49b096fd2c7199e3a2aea5bb4` | 11901 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 19 | `202608140018` | `202608140018_sprint12_1_owner_removal_guard_hotfix.sql` | `0ea7eaf04d5c99e4c5a25893aae7694affdd44bc` | 2780 | Source-reviewed SQL effects; see pinned migration source. | Special prerequisite: verify the historical owner_removed_at population is zero at the exact migration point, plus owner-removal/moderation state and constraint/function behavior. Source preflight aborts if any rows are already owner-removed. | NOT COLLECTED |
| 20 | `202609230019` | `202609230019_sprint12_2_gentle_delivery_foundation.sql` | `1403b9324e786a2b724176875a70ffce92961d9b` | 15845 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 21 | `202609230020` | `202609230020_delivery_reliability_hardening.sql` | `554615da3d15fc4c0d395691103d3be5676856fa` | 13642 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 22 | `202609230021` | `202609230021_gentle_delivery_transport.sql` | `e50a06bd3a5ed386c54e789435c64b2bb4a54ab9` | 3417 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 23 | `202609240022` | `202609240022_auth_pgcrypto_schema_qualification.sql` | `f42afb3474f80c7d95cf5b47023b82cf5a948d4d` | 1214 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 24 | `202611120023` | `202611120023_delivery_consent_linearization.sql` | `75f5086feab2cbda381066cb9094390190c3332f` | 9411 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 25 | `202611120024` | `202611120024_delivery_identity_lease_capacity.sql` | `240271fd75081c062627cfc3d40bdc0c5feda049` | 12329 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 26 | `202611190025` | `202611190025_delivery_provider_webhooks.sql` | `e97c5c0ad645dfe43f11a88f01b030fa23dd5822` | 17132 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 27 | `202611190026` | `202611190026_delivery_provider_lifecycle.sql` | `6a06d780ad65babf2293a2746c68913758313af8` | 13857 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 28 | `202611200027` | `202611200027_delivery_provider_integrity.sql` | `a1469938ea13b5cb9d7cd883772bc60e4a058026` | 20879 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 29 | `202611210028` | `202611210028_delivery_claim_lock_expiry.sql` | `09d1927fba81d711bb37d214609931d2da2173a1` | 9643 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 30 | `202611210029` | `202611210029_delivery_legacy_replay_guard.sql` | `872fc49ec47e49b17e96ecf6ccaf5c8eb0e6322a` | 7476 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 31 | `202611210030` | `202611210030_delivery_idempotency_receipt_guard.sql` | `c5e3955c4e0dde708a8ffdc9c420807c4241fa32` | 12214 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 32 | `202611220031` | `202611220031_delivery_final_recipient_suppression_gate.sql` | `26d69a0a4e73bc7cfd05814f3f6129bc199da02b` | 6477 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 33 | `202611220032` | `202611220032_resend_suppression_list_sync.sql` | `6a0c0193d85ece99335f8715a65243ac42617f97` | 14118 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 34 | `202611220033` | `202611220033_delivery_cross_stream_suppression_order.sql` | `1cd0c2db5415a37b9a31ed8ef7de54db9019a88f` | 4647 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 35 | `202611230034` | `202611230034_delivery_suppression_timestamp_order.sql` | `4ec8aa578ad851918f4c4b2535c476b4ceb40f1d` | 11255 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 36 | `202611230035` | `202611230035_private_offering_base_table_rls.sql` | `3d0ce8dfd4abb88fccccd23c5ffb9c35f699c098` | 564 | Source-reviewed SQL effects; see pinned migration source. | Compare source-linked effects against catalog fingerprints, ACL/RLS/ownership evidence, execution identity and capture time. | NOT COLLECTED |
| 37 | `202611230036` | `202611230036_private_daily_reflection_admin_isolation.sql` | `61a1fbf48b4557873ba6016e74fd3995bc62ba14` | 2042 | Source-reviewed SQL effects; see pinned migration source. | Privacy gate: prove daily_reflections RLS enabled; owner-only SELECT/INSERT/UPDATE; no admin bypass; no browser DELETE; service_role boundary preserved; no reflection contents in evidence. | NOT COLLECTED |
| 38 | `202611240037` | `202611240037_delivery_provider_integrity_conflict_evidence.sql` | `ac0449b50a881e3a895ef40a8eee28bea95a6ec0` | 44182 | Source-reviewed SQL effects; see pinned migration source. | Provider-integrity gate: prove private case/evidence/history tables, RLS, immutable evidence/history triggers, ACLs, legacy anomaly backfill counts and no raw webhook payload storage. Recipient emails are sensitive; export metadata/fingerprints only. | NOT COLLECTED |
| 39 | `202611240038` | `202611240038_delivery_provider_integrity_lock_order_pagination.sql` | `38951751fc5abeb79b75c4e37e55da01262a18b8` | 43748 | Source-reviewed SQL effects; see pinned migration source. | Provider-integrity gate: prove lock ordering, advisory lock behavior, function signatures/SECURITY DEFINER/search_path, service_role-only provider ingestion and authenticated admin-only paginated RPCs; no evidence row payloads. | NOT COLLECTED |

## Cross-cutting evidence required for every migration

1. Exact source path and Git blob SHA-1 match against this pinned inventory; capture exact repository commit and migration-inventory blob.
2. Complete, independently reviewed effect mapping for all nine domains: schema, privileges, ownership, routines, data transformations, backfills, dependencies, preconditions and postconditions. Every effect and explicit no-effect disposition must cite line ranges in the exact source file.
3. Compare source-linked object fingerprints with the read-only catalog snapshot: tables/views/columns, constraints, indexes, triggers, routines, ownership, SECURITY DEFINER/search_path, RLS, grants/revokes, role memberships, default privileges and extensions.
4. Prove history row uniqueness, exact version/name, source identity where available, executor and execution timestamp. Bind history and catalog exports to one collector receipt and capture time.
5. Classify only with the analyzer's established states: Applied and verified; Schema represented but history ambiguous; Verified unapplied; Partial or drifted; Unknown. Do not promote Unknown or ambiguous to an affirmative state.
6. A schema fingerprint match alone does not prove source execution. A history row alone does not prove all expected effects. The two must agree under the signed mapping.

## Mandatory ambiguity and sensitive migration checks

### Duplicate Migration 007

The two files `202607260007_sprint6_daily_deedlight.sql` and `202607260007_sprint7_pwa_daily_engagement.sql` have distinct pinned blob hashes and share one version. Keep both rows separate. Any matching history version is ambiguous as to which SQL body ran; it cannot prove both. Preserve both as unresolved until independently corroborated by catalog/data evidence and explicit DBA history review. Never mark either as Production-matched solely from the shared version.

### Migration 018 historical data prerequisite

The source contains a preflight that requires `public.offerings.owner_removed_at` to exist and requires the count of rows with `owner_removed_at IS NOT NULL` to be exactly zero before adding the hidden-state constraint and replacing `remove_own_offering(uuid)`. Evidence must establish the prerequisite at the migration's actual execution point, not merely current state. If no contemporaneous pre-migration snapshot exists, the historical prerequisite remains Unknown; a current zero count cannot retroactively prove it. Also review owner-vs-moderator hidden/rejected semantics and exact function ACL.

### Migrations 035–036: privacy boundaries

- 035 removes stale public-read policies from the `offerings` base table while preserving intended owner/admin paths and public projection surfaces. Verify effective anon/authenticated access, view definitions and grants.
- 036 makes `daily_reflections` owner-only for browser SELECT/INSERT/UPDATE, removes admin reflection access and browser DELETE, and retains server-only service_role capability. Verify both RLS flags and all effective policies/ACLs. Do not export reflection text, IDs linked to members, or other customer-private values.

### Migrations 037–038: provider integrity

- 037 creates recipient-scoped integrity cases, normalized conflict evidence and resolution history; adds immutable audit triggers; performs a legacy anomaly backfill; wraps provider lifecycle/suppression RPCs and adds admin review RPCs. Verify table owners, RLS, constraints, unique indexes, immutable triggers, effective ACLs, backfill counts and RPC security settings. Recipient email fields are personal data: do not export case/evidence rows or email addresses. Use counts and non-reversible aggregate fingerprints only.
- 038 hardens global lock ordering and keyset pagination, replaces provider ingestion wrappers, and adds authenticated admin-only conflict/evidence/history page RPCs. Verify exact function identity signatures, owners, SECURITY DEFINER, fixed search_path, service_role-only provider write access, authenticated admin gates and pagination indexes. Do not export payloads, recipient emails, notes or member identifiers.

## Historical transformations and backfills

For every migration with data writes, identify the exact source statement, selection predicate, update/insert/delete semantics, transaction boundaries, conflict behavior, expected row-count range and postcondition. In particular review:
- initial/counter updates and seed rows;
- profile/username normalization and privacy projection changes;
- moderation suspension/audit writes;
- completion/saved-light/reminder preference defaults;
- weekly feature curation;
- invitation/newsletter defaults and signup-trigger side effects;
- Offering ownership/removal updates and Migration 018 prerequisite;
- delivery ledger state transitions, webhook/lifecycle/suppression data changes;
- Migration 037 legacy anomaly backfill and immutable history creation.

Do not query private row contents for this evidence package. Use aggregate counts and salted/keyed digests generated by the controlled collector only where approved; never place reversible customer identifiers or low-entropy hashes in repository evidence.

## Backup and isolated restore gate

Before any future reconciliation mutation (not part of this package):
1. DBA verifies an existing supported PITR/backup restore point and records its provider-side immutable identifier and timestamp outside the repository.
2. Restore into a segregated, access-controlled, network-isolated non-Production project with equivalent Postgres/Supabase major version and required extensions.
3. Verify restore completion, schema/catalog parity, migration history, representative application invariants and delivery-disabled state. Test backup recoverability, not merely backup existence.
4. Capture restore logs and evidence digests with secrets, connection strings, customer data and provider tokens redacted.
5. Obtain independent DBA/security approval of the restore rehearsal and rollback plan before any Production change.
6. No Production migration-history edits or forward migrations are authorized by this ledger.

## Classification rule

Every migration starts at `NOT COLLECTED / UNCLASSIFIED`. A human reviewer may update status only after inspecting the signed collector result, independently reviewed semantic mapping, source fingerprint, exact history identity and required pre/postconditions. Migration 007 ambiguity is never auto-resolved. Migration 018 remains Unknown without contemporaneous prerequisite evidence. Migrations 036–038 require explicit privacy/provider-integrity acceptance.

