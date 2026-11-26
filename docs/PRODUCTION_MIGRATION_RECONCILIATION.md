# Cycle 390 — Sprint 6 / Migration 038 administrator fingerprint compatibility

**Verified starting HEAD:** `f95ccb9b7bb37eb625dace69e41d2655fb85025d`  
**PR #22:** OPEN / DRAFT / UNMERGED  
**PR #22 base:** PR #10 branch `security/delivery-transport-consent-gates` at `6a3660bbe2fd6beb2ddada43d5e77ff5ac9f3793`  
**Stack verification:** 223 commits ahead, 0 behind; merge base exactly equals PR #10 head.  
**Production:** NO-GO. No Production SQL, migration history, deploy, merge, or retarget operation was performed.

## Finding: exact source mismatch

The two historical Sprint 6/7 files sharing prefix `202607260007` are distinct and unchanged. Sprint 6 migration 007 explicitly replaces `public.is_admin()` with this SQL body:

```sql
select exists (
  select 1
  from public.profiles
  where user_id = auth.uid()
    and role = 'admin'
    and coalesce(is_suspended, false) = false
);
```

The initial schema migration 001 declares `profiles.is_suspended boolean not null default false`. Sprint 6's `coalesce(is_suspended, false) = false` therefore has the same truth table as the earlier migration 002 source `is_suspended = false` for every valid row under the schema's enforced NOT NULL constraint. It is not source-identical, however.

Historical evolution is explicit: migration 002 first defines the direct-equality body; migrations 004 and 005 each re-create the same body byte-for-byte (the same `85e6838c…` SHA-256); migration 006 does not redefine it; Sprint 6's `202607260007` is the only later replacement and introduces `coalesce(is_suspended, false)`; the distinct Sprint 7 `202607260007` does not define `is_admin()`. Migrations 009–011 and 036–038 do not redefine it either. Thus the last definition before 038 in the ordered aggregate is the Sprint 6 COALESCE variant, while 002/004/005 all carry the exact 038-approved source.\n\nMigration 038 intentionally fingerprints `pg_proc.prosrc`, not a normalized SQL AST or full `pg_get_functiondef`. Its approved `public.is_admin()` SHA-256 is `85e6838cf8feec05bcfe9e9051e5192bc8f0d42f7a53cb6c0450067d70bba74b`, which matches the migration 002 body. The Sprint 6 COALESCE body hashes to `4fb49052b2e525d8b355123d430df7e536a4da5207fd6ef3d21f3b2d770e98e0`. Consequently, after migrations 001–037 the Migration 038 preflight rejects the exact historical Sprint 6 helper as an unreviewed source. This is a deliberate exact-source mismatch, not an authorization failure or a difference in behavior while the NOT NULL invariant holds.

Migration 038 also requires `SECURITY DEFINER`, exactly `search_path=public`, and the existing public execution grant contract for `is_admin()`. Its checks are not weakened or changed by this work.

## Approved aggregate-only compatibility bridge

An explicit, separately pinned bootstrap artifact now sits after immutable migration 037 and immediately before immutable migration 038:

`supabase/bootstrap/migration_038_admin_compatibility.sql`

It is not a historical migration and is not added to the 39-file migration inventory. The aggregate generator pins its Git blob SHA-1 and includes it with provenance. Its preflight:
- requires `public.profiles`, `public.is_admin()`, and pgcrypto;
- requires the live `profiles.is_suspended` column to be catalog-verified NOT NULL and rejects any NULL row;
- requires the exact known Sprint 6 COALESCE `prosrc` hash, `SECURITY DEFINER`, and `search_path=public`;
- requires existing execute grants for anon, authenticated and service_role;
- fails closed on any unknown source, context, privilege, or schema state.

Only after all checks pass does it replace the helper body with the exact previously reviewed migration-002 source, preserving the same administrator predicate (`role = 'admin'` and `is_suspended = false`). It then verifies the exact Migration 038 source hash, definer/search_path and grants again. The NOT NULL precondition is essential: if the column were nullable, replacing COALESCE with direct equality would change NULL semantics and the bridge must not run.

This is deliberately not a rewrite of either 007 file, nor of migrations 036–038. The artifact is a deterministic aggregate bootstrap compatibility step. The generator inserts it only after version 037 and before version 038 and rejects artifact-byte drift. The source migrations remain immutable and independently pinned.

## PostgreSQL 16 regression coverage

The disposable PostgreSQL harness now executes the complete aggregate through Migration 038, then verifies:
- Migration 038 pagination functions and the 037 provider-integrity objects exist;
- all three bootstrap seed upserts have executed in their intended position;
- `profiles.is_suspended` remains NOT NULL;
- `public.is_admin()` has the exact 038 fingerprint and expected execute grants;
- an unsuspended admin is authorized, a suspended admin is denied, a normal member is denied, and an anonymous/no-subject request is denied;
- dropping NOT NULL causes the compatibility artifact to fail closed;
- an unexpected replacement `is_admin()` body causes the compatibility artifact to fail closed;
- restoring the exact Sprint 6 body allows the bridge to run reproducibly.

The inventory fixture suite additionally verifies that the compatibility artifact is included exactly once between synthetic 037 and 038 bodies and rejects any changed artifact blob. No SQL is parsed by splitting on semicolons.

## Decision and limitations

The incompatibility is safely resolvable for the aggregate's known schema path because migration 001 establishes `is_suspended NOT NULL`, Sprint 6 changes only the expression's NULL handling, and the bridge proves that invariant plus the exact known source and authorization context before replacing the function. The bridge does not silently accept an unknown function definition or nullable suspension state.

This does **not** establish that Production has the same schema, source body, column constraint, ACLs, or migration history. The aggregate's disposable PostgreSQL result is repository-level execution evidence only. Production remains NO-GO until separately authorized, read-only Production evidence establishes the schema and migration-history state and the outstanding delivery rollout gates are completed.

---

# Cycle 389 — Current repository inventory and SQL aggregate integrity

**Current source snapshot before Cycle 389 changes:** `afb63b53650222d901b0b32835678d138ac0761e`  
**Repository:** ADRN-9/deedlight  
**PR:** #22 — OPEN / DRAFT / UNMERGED  
**Branch:** security/private-daily-journey-admin-isolation-c408  
**Stack:** PR #22 targets PR #10's branch at `6a3660bbe2fd6beb2ddada43d5e77ff5ac9f3793`; comparison is 199 commits ahead / 0 behind with that exact merge base.  
**Current inventory:** 39 migration files; 38 unique version prefixes.  
**Current Production disposition:** all 39 migrations UNKNOWN; no Production execution or schema-equivalence claim is made.

> Historical C421/C410/C404 and earlier observations below are retained as historical snapshots. In particular, the old C421 count of 37 files / 36 prefixes and its 37 UNKNOWN classifications describes its then-current tree, not the Cycle 389 tree. The two additional migrations now present are 037 and 038.

## Current exact migration inventory

The pinned inventory is `supabase/migration-inventory.json`, whose own Git blob SHA-1 is pinned in the verifier as `95d514a0bd97ff448c9507252eb1f5e69a507442`. Each migration Git blob SHA-1 is the exact Git object hash of the original migration bytes. The complete inventory has 39 rows, 38 distinct 12-digit prefixes, and exactly one intentional duplicate group: both distinct `202607260007` files. No migration file was renamed, merged, or rewritten.

| Version | Exact filename | Git blob SHA-1 |
|---|---|---|
| 202607210001 | `202607210001_initial_schema.sql` | `a244ab0df3e766b0f36e29a222b3160f9f74c502` |
| 202607210002 | `202607210002_rls_policies.sql` | `f96b482c0d1cf396baae5b91d7c96112f7e88284` |
| 202607220003 | `202607220003_sprint3_offerings_review.sql` | `74e02f2e60b82cf07a6aac5f8cf57dcdb6fe1382` |
| 202607260004 | `202607260004_sprint4_reactions.sql` | `c25dce46ecf69d082fcdbea2bb931b6acd9180fc` |
| 202607260005 | `202607260005_sprint5_moderation.sql` | `b48b4b8b3eea9fb55b68068011fa1371559228c2` |
| 202607260006 | `202607260006_sprint5_admin_edit_hide_hotfix.sql` | `9e163de5119c3813724341b7a9eabeba6fdc2970` |
| 202607260007 | `202607260007_sprint6_daily_deedlight.sql` | `e0c2379255003b8c7bc85a1fab781e23051f5e47` |
| 202607260007 | `202607260007_sprint7_pwa_daily_engagement.sql` | `8b051cfce05ea75b1ee7a726864e2ad760f6fe5f` |
| 202607270008 | `202607270008_sprint8_short_video_studio.sql` | `5b583bd99562e14db554943d034c748ce302f5ee` |
| 202608060009 | `202608060009_sprint9_profiles_privacy.sql` | `6594ce6daa0183944fcc548885d6514e8adb9436` |
| 202608100010 | `202608100010_sprint9_2_community_identity_consistency.sql` | `774708b7705d88a5a1e0da97e72a9d1b47c8884c` |
| 202608100011 | `202608100011_sprint9_3_moderation_aware_members.sql` | `1d1b7b844b88077351d2658af4be2b2db92eda97` |
| 202608110012 | `202608110012_sprint10_1_daily_deed_completion.sql` | `0973f72e39ce07b41e053a20f1b781c394578877` |
| 202608110013 | `202608110013_sprint10_2_saved_lights_gentle_rhythm.sql` | `5fd2f4a796a8a1dfd6237ccf36d1ab62c1dc1714` |
| 202608120014 | `202608120014_sprint10_3_gentle_reminder_preferences.sql` | `2af1a6a2aa5cffc6ef6d08849b6f71fab44a54d0` |
| 202608130015 | `202608130015_sprint11_2_weekly_goodness.sql` | `394c774032d8206c0b7a373640859c2a331667a9` |
| 202608130016 | `202608130016_sprint11_3_invitations_newsletter_foundation.sql` | `8d68ed19859e1a820af52a43c110a38b6a460d48` |
| 202608130017 | `202608130017_sprint12_1_offering_ownership_engagement.sql` | `bc23b12fe454c1f49b096fd2c7199e3a2aea5bb4` |
| 202608140018 | `202608140018_sprint12_1_owner_removal_guard_hotfix.sql` | `0ea7eaf04d5c99e4c5a25893aae7694affdd44bc` |
| 202609230019 | `202609230019_sprint12_2_gentle_delivery_foundation.sql` | `1403b9324e786a2b724176875a70ffce92961d9b` |
| 202609230020 | `202609230020_delivery_reliability_hardening.sql` | `554615da3d15fc4c0d395691103d3be5676856fa` |
| 202609230021 | `202609230021_gentle_delivery_transport.sql` | `e50a06bd3a5ed386c54e789435c64b2bb4a54ab9` |
| 202609240022 | `202609240022_auth_pgcrypto_schema_qualification.sql` | `f42afb3474f80c7d95cf5b47023b82cf5a948d4d` |
| 202611120023 | `202611120023_delivery_consent_linearization.sql` | `75f5086feab2cbda381066cb9094390190c3332f` |
| 202611120024 | `202611120024_delivery_identity_lease_capacity.sql` | `240271fd75081c062627cfc3d40bdc0c5feda049` |
| 202611190025 | `202611190025_delivery_provider_webhooks.sql` | `e97c5c0ad645dfe43f11a88f01b030fa23dd5822` |
| 202611190026 | `202611190026_delivery_provider_lifecycle.sql` | `6a06d780ad65babf2293a2746c68913758313af8` |
| 202611200027 | `202611200027_delivery_provider_integrity.sql` | `a1469938ea13b5cb9d7cd883772bc60e4a058026` |
| 202611210028 | `202611210028_delivery_claim_lock_expiry.sql` | `09d1927fba81d711bb37d214609931d2da2173a1` |
| 202611210029 | `202611210029_delivery_legacy_replay_guard.sql` | `872fc49ec47e49b17e96ecf6ccaf5c8eb0e6322a` |
| 202611210030 | `202611210030_delivery_idempotency_receipt_guard.sql` | `c5e3955c4e0dde708a8ffdc9c420807c4241fa32` |
| 202611220031 | `202611220031_delivery_final_recipient_suppression_gate.sql` | `26d69a0a4e73bc7cfd05814f3f6129bc199da02b` |
| 202611220032 | `202611220032_resend_suppression_list_sync.sql` | `6a0c0193d85ece99335f8715a65243ac42617f97` |
| 202611220033 | `202611220033_delivery_cross_stream_suppression_order.sql` | `1cd0c2db5415a37b9a31ed8ef7de54db9019a88f` |
| 202611230034 | `202611230034_delivery_suppression_timestamp_order.sql` | `4ec8aa578ad851918f4c4b2535c476b4ceb40f1d` |
| 202611230035 | `202611230035_private_offering_base_table_rls.sql` | `3d0ce8dfd4abb88fccccd23c5ffb9c35f699c098` |
| 202611230036 | `202611230036_private_daily_reflection_admin_isolation.sql` | `61a1fbf48b4557873ba6016e74fd3995bc62ba14` |
| 202611240037 | `202611240037_delivery_provider_integrity_conflict_evidence.sql` | `ac0449b50a881e3a895ef40a8eee28bea95a6ec0` |
| 202611240038 | `202611240038_delivery_provider_integrity_lock_order_pagination.sql` | `38951751fc5abeb79b75c4e37e55da01262a18b8` |

Bootstrap seed: `supabase/seed.sql`, Git blob SHA-1 `e85554aed1553dec407e83966a1b0093f5d1e9a3`, 2574 bytes, exactly three idempotent upserts (themes, daily_posts, badges).

## SQL Editor aggregate execution order and compatibility

The previous aggregate contained complete byte-identical bodies for 001, 002 and 009–038, plus the seed artifact, but omitted the complete original bodies of 003, 004, 005, 006, both distinct 007 migrations, and 008. Those seven bodies are now restored from their pinned source files.

The deterministic aggregate order is:
1. All 39 migration sources in lexicographic filename order.
2. The bootstrap seed is deliberately executed immediately after 001 and 002, before 003–038. Those initial migrations create the themes, daily_posts and badges tables required by the three seed upserts.
3. Seed-before-007 is also a compatibility requirement: Sprint 6 migration 007 conditionally inserts its fallback daily post only when `daily_posts` is empty. The initial schema's `daily_posts.date` is NOT NULL without a default, while that fallback INSERT does not provide `date`; the seed's daily_posts upsert ensures the table is nonempty so the fallback INSERT is skipped. Do not move the seed after 007 or run the bodies in an arbitrary order.
4. Sprint 7 migration 007 creates `daily_lights` and extends `daily_reflections`; 008 depends on the Sprint 7 007 body. Migration 012 depends on both 007 bodies (the Sprint 6 `daily_post_id` and Sprint 7 `daily_light_id` models). The two 007 files must remain independent and execute in filename order.

The aggregate now has a deterministic source-provenance header with each migration filename, Git blob SHA-1 and byte length, an inventory blob identifier, and explicit migration/seed section markers. The source SQL bytes are included verbatim; the generator does not split SQL on semicolons or rewrite migration contents. The committed aggregate is verified byte-for-byte against generator output.

## Migration 037 and 038 dependencies and effects

**037 — `202611240037_delivery_provider_integrity_conflict_evidence.sql`** (blob `ac0449b50a881e3a895ef40a8eee28bea95a6ec0`):
- Depends on the delivery provider event, lifecycle and integrity model introduced by 025–027, including recipient correlation and the lifecycle/suppression RPC contracts.
- Creates durable `delivery_provider_integrity_cases`, `delivery_provider_integrity_conflict_evidence`, and `delivery_provider_integrity_conflict_history` tables with indexes, RLS and restricted mutation paths.
- Backfills only recoverable historical anomaly markers, labels legacy evidence honestly, and preserves fingerprint-less legacy conflicts as separate evidence when identity cannot be established.
- Adds recipient-scoped conflict recording, lifecycle/suppression wrappers and administrator list/resolve operations. It uses recipient-then-provider-ID transaction locking to serialize event identity and evidence.

**038 — `202611240038_delivery_provider_integrity_lock_order_pagination.sql`** (blob `38951751fc5abeb79b75c4e37e55da01262a18b8`):
- Depends on 037's durable cases/evidence/history tables and wrapper functions, and the provider event/suppression ordering contracts from 027 and 032–034.
- Adds keyset pagination indexes and replaces the conflict/evidence/history list interfaces with bounded keyset pages, exact filtered totals and continuation cursors; adds direct conflict retrieval independent of list pagination.
- Reasserts recipient-then-provider-ID lock ordering and the service-only provider mutation ACLs, and adds explicit function provenance comments. The migration's preflights abort on unexpected source, ACL or configuration drift.

These are source-level dependencies and effects. The existence of either file or its inclusion in the SQL Editor aggregate does not prove Production application.

## Duplicate-007 migration-history limitation

Supabase CLI migration history is keyed by the 12-digit version prefix. Two distinct migration files share `202607260007`, so one history row cannot independently attest that both SQL bodies ran. The SQL aggregate can execute both bodies in deterministic order, but it does not reconcile the CLI's timestamp-keyed history or prove which body a historical row represents. The existing duplicate-007 CLI/order regression remains relevant. Do not rename, consolidate, delete, or blindly mark either migration applied; do not run Production `supabase db push`. A human-approved reconciliation design against the proven live schema and authorized read-only migration history remains required.

## Aggregate and inventory verifier contract

`scripts/verify-migration-inventory-aggregate.mjs` checks:
- exact expected file count, exact filenames, unique version count and the sole approved duplicate group;
- each source's Git blob SHA-1 and byte length, plus missing, unexpected, renamed and modified files;
- the pinned seed blob and exactly three INSERT / ON CONFLICT upserts;
- deterministic aggregate generation from immutable source bytes and the maintained seed artifact;
- exact byte-for-byte equality between generated output and `supabase/run_in_sql_editor_all.sql`.

The companion Node test suite includes positive and negative fixtures for missing, modified, renamed and unexpected migration files; the independently preserved 007 pair; missing/duplicated aggregate bodies; 037/038 modification; reversed order; truncated source and inventory; missing/duplicated seed data; and unexpected SQL. SQL is treated as bytes; tests do not parse it by splitting semicolons.

The CI database harness uses a disposable PostgreSQL 16 instance with a minimal test-only Supabase compatibility surface. It is not a Production clone and cannot establish Production schema equivalence, migration history, or application status.

## Cycle 389 verification evidence and remaining execution blocker

**Implementation/test HEAD:** `3897bb47544af9e6c1454cba06d5bed3efff5357`  
**Exact-head GitHub Actions:** [run 45510421319](https://github.com/ADRN-9/deedlight/actions/runs/45510421319) — SUCCESS, 10/10 jobs.  
**Migration inventory:** 39/39 files; 38 unique prefixes; the two distinct 007 files are independently pinned.  
**Bootstrap seed:** exact pinned blob; three upserts with conflict handling.  
**Generated SQL aggregate:** exact byte-for-byte match; 390,310 bytes; SHA-256 `242e86a11c1c7af2eadb064621f0dd3068b9f51cfc7fd542d45b0ba5e8560e4a`.  
**Negative fixture suite:** 18 tests, 18 passed, 0 failed.  
**Disposable PostgreSQL 16 harness:** the 001–037 source sequence and all three bootstrap upserts executed; migration 038 rejected the aggregate and its transaction rollback was verified.

### Confirmed source incompatibility blocking full aggregate execution

The disposable PostgreSQL test exposed a real, fail-closed incompatibility; it is not a harness bootstrap issue:

- Migration 038's immutable preflight pins `public.is_admin()` source SHA-256 `85e6838cf8feec05bcfe9e9051e5192bc8f0d42f7a53cb6c0450067d70bba74b`, corresponding to the function body that tests `is_suspended = false`.
- Sprint 6 migration `202607260007_sprint6_daily_deedlight.sql` replaces that function with a body using `coalesce(is_suspended, false) = false`.
- No later migration before 038 restores the expected source. Migration 038 therefore raises `Migration 038 rejected unreviewed function source for public.is_admin().` and aborts before its own changes.
- The CI harness confirms that 037's cases/evidence/history tables and the three seed upserts exist after the failure, and that 038's paginated function was not committed by the aborted transaction.

The two source files are protected by the task instructions and remain unchanged. Do not weaken 038's preflight, edit either 007, insert an unapproved SQL patch into the aggregate, or report full aggregate execution as PASS. The aggregate is complete and byte-verifiable, but its full disposable execution is **BLOCKED by the historical 007/038 source-fingerprint conflict**. A separate, reviewed migration-compatibility decision is required before this aggregate can execute end-to-end. The expected-failure database harness makes this blocker executable and visible in CI instead of silently bypassing it.

### Production disposition

All 39 migrations remain **UNKNOWN** for Production application. This repository-only inventory, aggregate verification and disposable PostgreSQL run do not establish live schema equivalence, applied migration history, or Production behavior. The duplicate `202607260007` version-history ambiguity remains unresolved. Production read-only migration/catalog evidence and a human-approved reconciliation remain prerequisites. No Production SQL, `supabase db push`, migration-history repair, deployment, or merge was performed.

---

# DeedLight Production migration-history reconciliation

**Authoritative source inventory snapshot:** C421 synchronization tree (the C410 reviewer and Production evidence below remains historical)  
**Repository:** ADRN-9/deedlight  
**PR:** #22 — OPEN / DRAFT / UNMERGED  
**Branch:** security/private-daily-journey-admin-isolation-c408  
**Source HEAD inspected for the C421 inventory refresh:** c5bf9d205934e089d310fbc6677ddc5014314689  
**Source tree:** ed49efef679ae00b28f22e458256ae26671ada96  
**PR base:** security/delivery-transport-consent-gates at 6a3660bbe2fd6beb2ddada43d5e77ff5ac9f3793 (current base HEAD after synchronization)  
**Snapshot date:** 2026-11-24  
**Inventory:** 37 migration files; 36 unique filename version prefixes  
**Disposition:** INCOMPLETE — Production read-only access unavailable; every migration and schema effect remains UNKNOWN

> This C421 section is the authoritative source inventory for the synchronization tree above. Historical C404/C240/C245/C247/C410 sections retained below describe earlier evidence snapshots. Do not use their older HEAD/tree references as current branch state.

## C491 — SQL migration-history contract and trust-root revocation semantics

Section 13 now emits analyzer-native aliases: `version`, `name`, and quoted `recordedStatementCount`. The PostgreSQL 16 integration test extracts and executes that exact SELECT from `production-migration-readonly-audit.sql`, captures its actual tabular result, normalizes the three values, and validates the resulting `history.rows` against the same validator used by the reconciliation analyzer. The adapter rejects missing columns, extra columns, malformed counts, unsafe numeric values and duplicate version rows (the audited history table requires a primary key on version); SQL NULL statement counts remain explicit JSON nulls. It adds no execution ID, actor, timestamp, source hash or other provenance.

An active Ed25519 trust-root entry must explicitly contain `revokedAt: null`. An absent property is invalid. Any non-null value must be a canonical UTC timestamp in years 0001–9999 and is treated as revoked; malformed strings, empty strings, booleans, numbers, objects, arrays and year-zero timestamps are rejected. This is intentionally strict: null means active; a valid timestamp means revoked; every other representation means untrusted. A revoked key remains unusable regardless of timestamp age.

These checks are enforced in analyzer code, adversarial unit tests and the PostgreSQL 16 actual-query integration path. They do not change Production migration state or establish Production execution provenance.

## C489 — migration-history facts versus independent execution provenance

The read-only audit section 13 exports exactly three database facts per supabase_migrations.schema_migrations row using analyzer-native fields: version, name, and recordedStatementCount (a quoted SQL identifier). These values describe the history table. They do not prove which SQL bytes executed, who executed them, the execution timestamp, a unique execution identifier, or whether a matching source file was run manually outside Supabase CLI.

The repository and supplied evidence currently identify no authenticated authoritative external Production execution-provenance source. No verified Production SQL Editor audit record, deployment execution receipt, platform audit event, or immutable runner receipt is available and cryptographically bound to the project, migration version, exact source blob SHA-1, actor, timestamp and execution identity. CI logs and disposable PostgreSQL runs are not Production execution records. Migration filenames, version prefixes, statement counts, catalog effects, Git commit history and migration-history rows must never be used to synthesize missing execution IDs, actors, timestamps or source hashes.

The reconciliation contract is therefore deliberately fail-closed:

- Accept section 13 fields only as version, name, and recordedStatementCount. Extra executedAt, executedBy, executionId, or sourceBlobSha1 fields in a purported database-history row are rejected as fabricated/unsupported provenance.
- Candidate externalExecutionProvenance records are untrusted input. Their timestamps are validated, including year-zero rejection, but any supplied candidate records remain unverified because no authenticated authoritative source is configured.
- A matching catalog plus a migration-history row is classified Schema represented but history ambiguous, never Applied and verified.
- Absence of both a history row and current catalog effects remains UNKNOWN, not Verified unapplied: it cannot exclude manual, partial, reverted or historical execution without authoritative external evidence.
- Duplicate version 202607260007 remains ambiguous for both distinct SQL bodies even if a matching history row exists.
- Only a future independently authenticated, project-bound external execution record that binds the exact source blob, actor, timestamp and execution identity may justify stronger execution-provenance claims. No such source is configured by this change.

The existing Production access limitation remains unchanged. Obtain authorized read-only Production evidence and an independently verifiable external execution record before changing any classification. Do not repair or mutate Production migration history to compensate for missing provenance.

## C421 synchronization addendum

PR #22 was synchronized with the latest PR #10 branch using a normal two-parent merge commit. The merge commit is `c5bf9d205934e089d310fbc6677ddc5014314689` (tree `ed49efef679ae00b28f22e458256ae26671ada96`); parents are prior PR #22 HEAD `ff53e43e9cee7da4189d0d06b576934589f6bfcb` and PR #10 HEAD `6a3660bbe2fd6beb2ddada43d5e77ff5ac9f3793`. PR #10's single commit beyond the shared base adds only `docs/DELIVERY_RELIABILITY_AUDIT_CYCLE_344.md` (blob `cd02f4ed6548faf84057e1e7c7406ab597778ee2`). No conflicting paths were found; migration 036 and its blob `61a1fbf48b4557873ba6016e74fd3995bc62ba14` are unchanged.

The complete recursive synchronization tree is not truncated and contains 37 numbered migration files and 36 unique version prefixes. All 37 filename/blob rows in the inventory below were compared against that tree; there are zero mismatches, missing entries or extra entries. The two distinct `202607260007` files remain unchanged. No migration 037 was created. All 37 Production classifications and every independently identifiable Production effect remain UNKNOWN. The synchronization and inventory refresh are repository-only evidence, not Production application evidence.

## Executive result

The recursive Git tree at c5bf9d205934e089d310fbc6677ddc5014314689 (tree ed49efef679ae00b28f22e458256ae26671ada96) was complete (not truncated) and contains 37 files under supabase/migrations matching the numbered SQL migration naming pattern. The files contain 36 unique version prefixes because two distinct files share version 202607260007:

- 202607260007_sprint6_daily_deedlight.sql — blob e0c2379255003b8c7bc85a1fab781e23051f5e47
- 202607260007_sprint7_pwa_daily_engagement.sql — blob 8b051cfce05ea75b1ee7a726864e2ad760f6fe5f

They are separate SQL bodies, not aliases or duplicate copies. Keep both source files unchanged. The collision means a timestamp-keyed Supabase migration history cannot unambiguously record both bodies as separate migration versions. Existing isolated PostgreSQL/Supabase CLI evidence shows order-sensitive behavior; see the retained C247 archive below.

The repository source establishes what the candidate migrations intend to change. It does not establish what has run in Production. No new authorized Production history, catalog, SQL Editor audit, or deployment evidence was collected for C421. Accordingly, all 37 file-level classifications and every independently identifiable effect-level classification remain UNKNOWN. Git presence, comments claiming a Production hotfix, aggregate SQL text, successful disposable-database tests, and CI are not Production execution evidence.

The PR #22 source integration snapshot is c5bf9d205934e089d310fbc6677ddc5014314689 (tree ed49efef679ae00b28f22e458256ae26671ada96), a normal merge commit with previous PR #22 HEAD ff53e43e9cee7da4189d0d06b576934589f6bfcb and PR #10 HEAD 6a3660bbe2fd6beb2ddada43d5e77ff5ac9f3793 as parents. PR #22 is OPEN / DRAFT / UNMERGED; its base is security/delivery-transport-consent-gates at 6a3660bbe2fd6beb2ddada43d5e77ff5ac9f3793 (the PR #10 HEAD merged into this branch). Historical C408 implementation CI run 45174106399 passed 8/8 jobs on the earlier implementation HEAD 6d0e8fcc397a61bb7aaf0c1858b1147c5f81dae1; it does not validate the C421 synchronization commit or the subsequent documentation refresh. The PR review endpoint returned zero submitted reviews at the C410 snapshot; a separate post-synchronization query also returned zero, so independent security acceptance is not established. No migration SQL, Production database, migration history, credentials, scheduler, provider, deployment, or delivery setting was changed for C421.

## Production access and human-only dependency

The Production project reference used by the repository guard is xaipiovflxomcbfwtwmu. The last recorded C404 read-only get_project, list_migrations and list_tables attempts were denied for the connected identities. Neither the C410 documentation snapshot nor C421 attempted new Production access. These historical denials establish lack of access for those identities at that time, not absence of the project or schema.

**Human-only prerequisite:** a Production project owner/administrator must either (a) grant an existing connected identity project-scoped read-only access sufficient to list migration history and inspect catalogs, or (b) provide an approved, dedicated read-only PostgreSQL connection for project xaipiovflxomcbfwtwmu. The database role must be SELECT-only for migration history and relevant catalogs. It must not have schema-write, migration-repair, service-role, credential-management, or outbound-delivery authority. Do not request or expose a service-role key for this audit.

Until that prerequisite is met, no Production migration may be classified as applied, recorded-but-unverified, represented-but-unrecorded, or unapplied. Permission denied must never be interpreted as an empty migration history.

## Current migration inventory — one row per file

The Git blob SHA is the exact blob returned by the complete recursive Git tree at C421 synchronization HEAD c5bf9d205934e089d310fbc6677ddc5014314689 (tree ed49efef679ae00b28f22e458256ae26671ada96). Dependencies below are source-level prerequisites inferred from the migration SQL and established migration-order tests; they are not claims about Production execution order. All Production classifications are UNKNOWN.

| Version | Exact migration filename | Git blob SHA | Source dependencies | Source-level changes and identifiable effects | Production |
|---|---|---|---|---|---|
| 202607210001 | 202607210001_initial_schema.sql | a244ab0df3e766b0f36e29a222b3160f9f74c502 | Foundation; Supabase Auth and pgcrypto. | Creates profiles, themes, daily_posts, offerings, reactions, reflections, reports, badges, user_badges, saved_lights, daily_deed_completions; bootstrap/count functions, triggers and indexes. | UNKNOWN |
| 202607210002 | 202607210002_rls_policies.sql | f96b482c0d1cf396baae5b91d7c96112f7e88284 | 001; core tables and storage.objects. | Creates is_admin(); enables RLS and initial member/admin/public policies on core tables and storage objects. | UNKNOWN |
| 202607220003 | 202607220003_sprint3_offerings_review.sql | 74e02f2e60b82cf07a6aac5f8cf57dcdb6fe1382 | 001–002; offerings and grants/RLS. | Adds Offering review indexes; creates offerings_public view and public projection grants. | UNKNOWN |
| 202607260004 | 202607260004_sprint4_reactions.sql | c25dce46ecf69d082fcdbea2bb931b6acd9180fc | 001–003; reactions, offerings, is_admin. | Replaces reaction-count function/triggers and reaction RLS policies; adjusts grants; creates/replaces offerings_rising view. | UNKNOWN |
| 202607260005 | 202607260005_sprint5_moderation.sql | b48b4b8b3eea9fb55b68068011fa1371559228c2 | 001–004; offerings, reactions, reports and RLS. | Adds moderation indexes; replaces Offering/report policies, is_admin and report-count function/triggers; adjusts grants. | UNKNOWN |
| 202607260006 | 202607260006_sprint5_admin_edit_hide_hotfix.sql | 9e163de5119c3813724341b7a9eabeba6fdc2970 | 005; Offering moderation policies and public view. | Preflights and narrows Offering update policy; replaces offerings_public projection and grants. | UNKNOWN |
| 202607260007 | 202607260007_sprint6_daily_deedlight.sql | e0c2379255003b8c7bc85a1fab781e23051f5e47 | 001–002; daily_posts, daily_reflections, offerings, Auth. | Extends daily_posts with editorial/scheduling/video fields, constraints/indexes; creates/extends daily_reflections with private reflection/deed fields. Duplicate version 007. | UNKNOWN |
| 202607260007 | 202607260007_sprint7_pwa_daily_engagement.sql | 8b051cfce05ea75b1ee7a726864e2ad760f6fe5f | 001–002; offerings/Auth; creates daily_lights used by 008/012/013. | Creates daily_lights; extends daily_reflections with daily_light_id/user_id/reflection/intention; RLS/policies/grants/triggers. Duplicate version 007; explicit transaction boundary. | UNKNOWN |
| 202607270008 | 202607270008_sprint8_short_video_studio.sql | 5b583bd99562e14db554943d034c748ce302f5ee | Sprint 7 body of 007; daily_lights. | Adds video metadata/status/visibility columns, checks, grants and three daily_lights video indexes. | UNKNOWN |
| 202608060009 | 202608060009_sprint9_profiles_privacy.sql | 6594ce6daa0183944fcc548885d6514e8adb9436 | 001–006; profiles, offerings, public views and Auth bootstrap. | Changes profile privacy/identity fields and policies; replaces handle_new_user/offerings_public; creates profiles_public; narrows grants. | UNKNOWN |
| 202608100010 | 202608100010_sprint9_2_community_identity_consistency.sql | 774708b7705d88a5a1e0da97e72a9d1b47c8884c | 009; profiles_public/offerings_public and auth.users. | Replaces handle_new_user and offerings_public/offerings_rising views; adjusts projection grants. | UNKNOWN |
| 202608100011 | 202608100011_sprint9_3_moderation_aware_members.sql | 1d1b7b844b88077351d2658af4be2b2db92eda97 | 001, 005, 009–010; profiles, offerings, reflections. | Creates member_moderation_events, indexes/RLS and admin member/context/suspension RPCs; updates Offering/reflection policies. | UNKNOWN |
| 202608110012 | 202608110012_sprint10_1_daily_deed_completion.sql | 0973f72e39ce07b41e053a20f1b781c394578877 | 001 plus BOTH 007 files: Sprint 6 daily_post_id and Sprint 7 daily_light_id; daily_lights. | Extends daily_deed_completions/daily_reflections; adds constraints/indexes/RLS/policies/grants and daily_deed_completion_counts view. | UNKNOWN |
| 202608110013 | 202608110013_sprint10_2_saved_lights_gentle_rhythm.sql | 5fd2f4a796a8a1dfd6237ccf36d1ab62c1dc1714 | 001 and Sprint 7 007; saved_lights/daily_lights. No SQL dependency on 012. | Extends Saved Lights to Daily Lights/Offerings; changes source constraints, unique/index definitions, owner policies and grants. | UNKNOWN |
| 202608120014 | 202608120014_sprint10_3_gentle_reminder_preferences.sql | 2af1a6a2aa5cffc6ef6d08849b6f71fab44a54d0 | 001/009; profiles and auth.users. | Creates private daily_reminder_preferences, updated_at trigger, RLS/policies and owner-only grants. | UNKNOWN |
| 202608130015 | 202608130015_sprint11_2_weekly_goodness.sql | 394c774032d8206c0b7a373640859c2a331667a9 | 001/004/009; reactions and profiles. | Adds reaction index and weekly_goodness_features table/trigger; weekly discovery/current-feature/curation RPCs and ACLs. | UNKNOWN |
| 202608130016 | 202608130016_sprint11_3_invitations_newsletter_foundation.sql | 8d68ed19859e1a820af52a43c110a38b6a460d48 | 001/009, pgcrypto, auth.users. | Creates invitation_links, private invitation_acceptances, newsletter_preferences; indexes, RLS, Auth growth triggers and invitation/newsletter RPCs. | UNKNOWN |
| 202608130017 | 202608130017_sprint12_1_offering_ownership_engagement.sql | bc23b12fe454c1f49b096fd2c7199e3a2aea5bb4 | 001/004/009–010; offerings, reactions, profiles and Saved Lights. | Adds Offering owner-removal metadata/index; extends private Saved Lights to approved Offerings; tightens policies and creates owner edit/remove/restore RPCs. | UNKNOWN |
| 202608140018 | 202608140018_sprint12_1_owner_removal_guard_hotfix.sql | 0ea7eaf04d5c99e4c5a25893aae7694affdd44bc | 017; offerings.owner_removed_at and remove_own_offering(uuid). | Preflights expected state; replaces hidden-state constraint and remove_own_offering guard. Source comment claims Production repair but is not execution proof. | UNKNOWN |
| 202609230019 | 202609230019_sprint12_2_gentle_delivery_foundation.sql | 1403b9324e786a2b724176875a70ffce92961d9b | 014–016; profiles, reminder/newsletter preferences, Weekly curation and Auth. | Creates delivery_ledger, indexes/RLS/trigger and enqueue/claim/authorize/sent/failed RPCs; no scheduler/provider activation. | UNKNOWN |
| 202609230020 | 202609230020_delivery_reliability_hardening.sql | 554615da3d15fc4c0d395691103d3be5676856fa | 019; delivery_ledger and baseline RPCs. | Adds retry/claim-expiry state and index; replaces claim, authorization, retry, sent and failed transitions with bounded retries and preflight checks. | UNKNOWN |
| 202609230021 | 202609230021_gentle_delivery_transport.sql | e50a06bd3a5ed386c54e789435c64b2bb4a54ab9 | 020; retry RPC, claim_expires_at and delivery_ledger. | Adds transport_started_at, begin_delivery_transport and curated Weekly enqueue helper; guarded preflight. | UNKNOWN |
| 202609240022 | 202609240022_auth_pgcrypto_schema_qualification.sql | f42afb3474f80c7d95cf5b47023b82cf5a948d4d | 001/009 Auth bootstrap and pgcrypto in extensions schema; independent of delivery chain. | Replaces handle_new_user with extensions-qualified pgcrypto call. Header calls it a Production Auth hotfix; header is not execution proof. | UNKNOWN |
| 202611120023 | 202611120023_delivery_consent_linearization.sql | 75f5086feab2cbda381066cb9094390190c3332f | 019–021; profiles, reminder/newsletter preferences, weekly_goodness_features and Auth. | Replaces daily/weekly enqueue and final transport RPCs; consent/profile/Auth row locks and source-contract attestations. | UNKNOWN |
| 202611120024 | 202611120024_delivery_identity_lease_capacity.sql | 240271fd75081c062627cfc3d40bdc0c5feda049 | Exact 023 function contracts/comments; delivery ledger, profiles and Auth email. | Replaces begin_delivery_transport with recipient-bound lease authorization; adds current-email identity check and serialized Weekly capacity/curation helper. | UNKNOWN |
| 202611190025 | 202611190025_delivery_provider_webhooks.sql | e97c5c0ad645dfe43f11a88f01b030fa23dd5822 | 024; ledger, Auth, recipient-bound transport and enqueue RPCs. | Creates private delivery_provider_events/delivery_provider_suppressions with RLS/ACLs; provider-event RPC and suppression-aware enqueue/final transport gates. | UNKNOWN |
| 202611190026 | 202611190026_delivery_provider_lifecycle.sql | 6a06d780ad65babf2293a2746c68913758313af8 | 025; provider events/suppressions and provider-ID recipient correlation. | Extends event types/columns; creates private delivery_provider_lifecycle/index; adds lifecycle RPC and wraps legacy event entry point. | UNKNOWN |
| 202611200027 | 202611200027_delivery_provider_integrity.sql | a1469938ea13b5cb9d7cd883772bc60e4a058026 | 025–026; provider event/lifecycle tables and RPCs. | Extends event/lifecycle metadata/checks; creates delivery_provider_integrity_anomalies with dedupe index/RLS; replaces lifecycle RPCs and records conflicts. | UNKNOWN |
| 202611210028 | 202611210028_delivery_claim_lock_expiry.sql | 09d1927fba81d711bb37d214609931d2da2173a1 | 020; delivery_ledger and transition RPC contracts. | Replaces authorize/retry/sent/failed RPCs to recheck expiry after lock waits using database wall clock; reasserts service-only ACLs. | UNKNOWN |
| 202611210029 | 202611210029_delivery_legacy_replay_guard.sql | 872fc49ec47e49b17e96ecf6ccaf5c8eb0e6322a | 027 exact RPC source/metadata fingerprint and pgcrypto; provider event tables. | Pins 027 implementation identity; renames fingerprinted implementation to private helper and restricts fingerprint-less RPC to historical compatible replays. | UNKNOWN |
| 202611210030 | 202611210030_delivery_idempotency_receipt_guard.sql | c5e3955c4e0dde708a8ffdc9c420807c4241fa32 | 024 recipient-bound gate, 028 transitions and ledger.transport_started_at. | Adds DB-authoritative idempotency-window authorization; replaces retry/sent RPCs; validates provider receipts and fails closed after retry horizon. | UNKNOWN |
| 202611220031 | 202611220031_delivery_final_recipient_suppression_gate.sql | 26d69a0a4e73bc7cfd05814f3f6129bc199da02b | 030; 025 suppressions, 014/016 preferences, profiles, Auth and 024 transport. | Replaces authorize_delivery_idempotency_window(uuid,uuid) with (uuid,uuid,text); binds expected recipient and rechecks consent, suspension, confirmed Auth email, suppression, lease and horizon before send. | UNKNOWN |
| 202611220032 | 202611220032_resend_suppression_list_sync.sql | 6a0c0193d85ece99335f8715a65243ac42617f97 | 025–027; provider events/suppressions and integrity anomalies. | Extends event metadata/checks; creates delivery_provider_suppression_state with unique provider suppression ID; adds suppression-event RPC and timestamp/origin projection for bounce/complaint/manual events. | UNKNOWN |
| 202611220033 | 202611220033_delivery_cross_stream_suppression_order.sql | 1cd0c2db5415a37b9a31ed8ef7de54db9019a88f | 032 suppression state and private 029 lifecycle implementation; 025–027 provider objects. | Replaces lifecycle RPC to reconcile email.suppressed events with Resend suppression-list state using provider timestamps and shared ordering. | UNKNOWN |
| 202611230034 | 202611230034_delivery_suppression_timestamp_order.sql | 4ec8aa578ad851918f4c4b2535c476b4ceb40f1d | 032–033; provider events, suppression state, integrity anomalies and lifecycle projection. | Adds generic-suppression timestamp-order index and replaces suppression-event RPC; older/equal/unknown lifecycle evidence blocks stale manual removal; complaint/permanent-bounce holds remain. | UNKNOWN |
| 202611230035 | 202611230035_private_offering_base_table_rls.sql | 3d0ce8dfd4abb88fccccd23c5ffb9c35f699c098 | 001 offerings table, 002 RLS, stale public-read policies from 002/005; public views remain separate. | Drops stale offerings_select_public_or_own and offerings_public_approved_read base-table policies; preserves owner/admin access and offerings_public projection. | UNKNOWN |
| 202611230036 | 202611230036_private_daily_reflection_admin_isolation.sql | 61a1fbf48b4557873ba6016e74fd3995bc62ba14 | Both 007 bodies: Sprint 6 creates daily_reflections; Sprint 7 adds Daily Light fields and the second admin-readable policy-name variant. Supabase Auth auth.uid() and public/anon/authenticated/service_role roles. No SQL dependency on 035 or the delivery chain. | Enables RLS; removes both historical admin-readable SELECT policy variants and admin-enabled UPDATE/DELETE policy variants; recreates owner-only SELECT/INSERT/UPDATE; revokes PUBLIC/anon/authenticated table privileges then grants authenticated SELECT/INSERT/UPDATE; retains service_role-only trusted server capability. | UNKNOWN |

## Version collision and dependency hazards

### Duplicate version 202607260007

The two 007 files are distinct, independently hashed SQL bodies. Sprint 6 alters the legacy daily_posts/daily_reflections model; Sprint 7 creates daily_lights and changes daily_reflections in a separate body. A unique version key cannot separately attest both. A row named for one body does not prove the other body ran.

The retained C247 isolated PostgreSQL/Supabase CLI 3.2.0 tests recorded:

- Sprint 6 then Sprint 7: both SQL bodies reach schema execution, then migration-history insertion fails with SQLSTATE 23505 on the duplicate version key.
- Sprint 7 then Sprint 6: Sprint 6 fails with SQLSTATE 42703 because daily_reflections.daily_post_id is absent; its transaction rolls back.
- The tested valid sequence for downstream dependencies is Sprint 6 007, Sprint 7 007, 008, 012, 013. The alternative 008, 013, 012 sequence also passed; 013 has no SQL dependency on 012.

These are disposable-database results only. They do not identify which 007 body ran in Production. Do not rename either file, collapse the two rows, infer execution from the migration-history version, or run normal Production db push while the collision remains unresolved.

### Downstream dependency chain

- 008 requires Sprint 7's daily_lights.
- 012 requires both 007 bodies: daily_post_id from Sprint 6 and daily_light_id from Sprint 7, plus daily_deed_completions from 001.
- 013 requires saved_lights from 001 and daily_lights from Sprint 7; no direct SQL dependency on 012.
- 018 is a guarded replacement of the 017 owner-removal constraint/RPC. Its header says it records a Production repair, but that statement is not evidence that the repair executed.
- 019–021 establish the delivery ledger, bounded retries and transport boundary. They do not activate a scheduler or provider.
- 023 requires the reviewed 019–021 baseline and exact consent/curation functions. 024 checks 023's source-level attestations and replaces recipient identity/lease behavior.
- 025–027 establish provider events, suppression, lifecycle and integrity projections. 028 hardens delivery transitions; 029 pins the 027 implementation identity; 030 requires 024/028 and transport-start state.
- 031 requires the 030 pre-send gate and replaces it with a final recipient-bound suppression/consent check.
- 032 creates provider suppression-list state; 033 reconciles cross-stream lifecycle ordering against 032; 034 corrects provider timestamp ordering; 035 removes stale public-read policies from the Offering base table. 036 is a separate privacy correction on daily_reflections: it depends on the table and both legacy policy-name variants from the two 007 bodies, not on 035; it replaces administrator-readable reflection policies with owner-only browser access while retaining the trusted service_role capability. Migration 011's admin_get_member_context source explicitly avoids querying daily_reflections.

The dependency graph must be verified against actual live definitions and data before any history or schema operation. A matching object name is insufficient: columns, nullability, constraints, index predicates, function bodies, argument identity, security attributes, ACLs, policies, triggers, and data preconditions are part of the effect.

## Production classification rules

Classify each migration file and each independently identifiable effect separately:

1. **Applied and recorded:** the exact live schema/data effects match the intended source and an authoritative migration-history row and execution record corroborate them.
2. **Schema represented, history absent or ambiguous:** every intended effect is proven live, but history is absent/ambiguous or a manual SQL Editor execution is documented. This is not automatically safe to mark applied.
3. **Unapplied:** authoritative history and catalog/audit evidence jointly prove the effects are absent and no partial/manual execution occurred.
4. **Partial, drifted, conflicting or unknown:** any effect is missing, altered, conflicting, unverified, or cannot be mapped to a unique source body. Stop; do not push or repair history.

Current counts: 0 verified applied-and-recorded; 0 verified schema-present/history-missing; 0 verified unapplied; 37 UNKNOWN at file level. Effect-level counts are also UNKNOWN. This is an evidence limitation, not a claim that Production has zero objects.

## Required live evidence before reconciliation

The owner-facing SELECT-only query packet is [PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md](PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md). It verifies target identity, catalog metadata, migration history, the duplicate 007 collision, and migration 036 policy/ACL effects without reading application-member rows. The packet is preparation only; it does not change any Production classification from UNKNOWN.

Obtain a timestamped, read-only evidence package for the exact project reference and database identity:

- Complete rows and schema definition for supabase_migrations.schema_migrations, including all versions, names/statements if present, ordering, timestamps and any duplicate/conflicting records. Preserve raw output and query text.
- Full schema-only catalog inventory for public and relevant Supabase-managed schemas: relations, columns/types/defaults/nullability, constraints, indexes and predicates, sequences, extensions and extension schemas.
- Full definitions and metadata for functions/procedures: identity arguments, return types, language, prosrc/source fingerprint, owner, SECURITY DEFINER, search_path/configuration, volatility, comments, dependencies and EXECUTE ACLs.
- Trigger definitions and attachment points; view definitions and security options; RLS enabled/forced flags; every policy expression and role; table/schema grants and default privileges.
- Data-level preconditions/effects where relevant: owner_removed_at rows and moderation states; migration-specific seed/curation rows; delivery ledger counts and active claims; provider suppression/event/lifecycle/anomaly records. Recipient identifiers must remain redacted.
- Supabase SQL Editor history, dashboard query logs, deployment logs and approved change records that could establish manual execution of 018, 022, or any other migration.
- Source and SQL Editor aggregate bundle fingerprints. The aggregate supabase/run_in_sql_editor_all.sql is not a migration execution record and historical snapshots show it is not a byte-for-byte replay of every early migration.
- Verified backup/PITR availability, restore point, retention and a rehearsed restore plan before any future Production mutation.

- For migration 036, compare the exact live daily_reflections policy set and effective table ACLs for PUBLIC, anon, authenticated and service_role; verify member-only SELECT/INSERT/UPDATE, absence of browser DELETE, and that admin_get_member_context does not expose reflection content.

Never infer success from a version row alone when the corresponding source body is uncertain. Never infer non-execution from a missing history row when manual SQL Editor execution is possible.

## Migration-by-migration catalog comparison

For each row in the inventory, create an effect checklist keyed by migration filename and blob SHA. At minimum compare:

- Tables: existence, owner, columns, types, defaults, nullability, generated/identity attributes, constraints, partitioning and RLS flags.
- Indexes: exact definition, uniqueness, key order, predicate, included columns and validity.
- Functions: exact identity signature, return type, body fingerprint, owner, language, SECURITY DEFINER, search_path, configuration, comments and ACLs.
- Triggers: exact event, timing, orientation, enabled state and function binding.
- Views: exact definition, output columns, security options and grants.
- Policies: exact policy name, command, roles, USING/WITH CHECK expressions and permissive/restrictive mode.
- Extensions: installed version, schema and required functions.
- Data effects: exact predicates and row-level conditions; compare counts and protected samples without exporting personal data.
- Migration history: compare each history record to the exact source inventory and available execution evidence. For 007, require object-level mapping plus retained execution evidence; the shared version prefix cannot prove both files.

A file-level result must not conceal partial effects. If one function or policy differs, classify that effect as drifted/unknown even if the rest of the file matches.

## Safe forward-only reconciliation strategy

1. **Freeze and identify.** Do not run supabase db push, migration repair, db reset, db pull, SQL Editor DDL, or manual history edits. Confirm project reference/database identity from the authorized read-only session. Keep DELIVERY_ENABLED=false and schedulers paused under existing rollout governance.
2. **Capture before state.** Export and preserve raw migration history, schema/catalog evidence, audit records, source hashes, query text and timestamps. Redact recipient/member data. Obtain a verified backup/PITR restore point and confirm an independent operator can restore it.
3. **Build the effect matrix.** Map every file/blob to every table, column, constraint, index, function, trigger, view, policy, grant and data effect. For 007, map Sprint 6 and Sprint 7 separately and reconcile the history collision using exact catalog evidence and SQL Editor/deployment records.
4. **Review discrepancies independently.** Have an independent database/security reviewer approve the source-to-live mapping, duplicate-version resolution, proposed changes, locking plan, rollback/restore plan and operational window. No author self-acceptance.
5. **Prefer additive forward fixes.** If a verified effect is missing or drifted, design a new forward-only migration with explicit preflight checks, idempotency only where semantically safe, data-preserving behavior, ACL/RLS assertions and disposable PostgreSQL regression coverage. Do not rewrite historical migration files or silently edit old migration history.
6. **History-only repair is exceptional.** A history repair is permissible only after every effect of the exact migration body is independently proven present, all manual execution records are reconciled, the 007 ambiguity is resolved, a backup/restore point exists, and the independent reviewer plus Production owner approve. Never mark an unverified migration applied merely to make db push pass.
7. **Stage and verify.** Test the exact candidate on a Production-like restored copy, compare pre/post catalogs and data invariants, then use the approved change window and migration lock. Capture command, actor, target identity, start/end times, output, resulting history and catalog fingerprints.
8. **Close only with evidence.** Re-read the complete history and affected catalogs after the change. Any mismatch or unexpected row/object leaves reconciliation open and Production NO-GO.

## Backup, locking, restoration and stop conditions

- Require a fresh, verified backup/PITR point and tested restore procedure. Record the restore point and expected recovery point objective before scheduling a change.
- Use one approved migration operator and a deployment/migration lock so no competing db push, SQL Editor DDL, deploy or manual migration can run concurrently. Keep scheduler and outbound delivery disabled; reconcile active delivery claims before touching delivery objects.
- Preserve all existing data. Prefer forward repair. Do not roll back by dropping tables, functions, policies or constraints if doing so can destroy member/private data or delivery evidence.
- If a migration fails after partial non-transactional effects, stop immediately, capture actual state/logs, and have the DBA choose forward repair versus approved restore. Do not blindly rerun.
- Stop if project identity is uncertain; access is not read-only; history and catalog disagree; either 007 body cannot be identified; a required function fingerprint differs; a preflight reports unexpected data/active claims; backup/PITR cannot be verified; locks cannot be held; provider outcomes are ambiguous; or the proposed action could send email or alter consent.
- Any restore that could lose post-backup member data requires explicit Production-owner approval and a documented data-loss/recovery decision. Never restore or mutate Production as part of this documentation task.

## Current evidence boundaries

| Evidence class | Established | Not established |
|---|---|---|
| Repository source | Exact PR #22 HEAD/tree, 37 filenames, 36 prefixes, exact blob SHA per file, source dependencies/effects including migration 036 | Whether any file/effect exists in Production |
| Disposable PostgreSQL/CLI | C247 duplicate-007 ordering and downstream dependency behavior; PR #22 privacy authorization PostgreSQL behavior job 137690786519 | Production schema/history, manual SQL Editor execution, real provider behavior |
| CI | PR #22 exact source HEAD push run 45174106399 completed SUCCESS, 8/8 jobs, including privacy authorization database behavior | Independent security acceptance, Production deployment, scheduler, email sends, kill-switch behavior |
| Supabase connector | Connected identities could not read Production project/history/catalog | Project absence, empty history, missing schema or non-execution |
| Human authorization | Exact need for owner-provided scoped read-only access | Any permission grant or Production access currently exists |

## C404 documentation execution scope (historical)

This update changes only docs/PRODUCTION_MIGRATION_RECONCILIATION.md and docs/DELIVERY_ROLLOUT_TRACKER.md. It does not change migration SQL, aggregate SQL, application code, CI workflows, credentials, Supabase configuration, Production schema/history, scheduler, provider, Cron, or delivery settings. PR #11 and PR #19 remain untouched. The source baseline inspected before the documentation commit is c256a1e959f42d0a66b47ad16b3aef3b4705f11e; the resulting fast-forward commit is recorded in the C404 execution handoff.

## C410 documentation execution scope

This update is limited to docs/PRODUCTION_MIGRATION_RECONCILIATION.md and docs/DELIVERY_ROLLOUT_TRACKER.md. It does not alter migration SQL, aggregate SQL, application code, CI workflows, credentials, Supabase configuration, Production schema/history, scheduler, provider, Cron, or delivery settings.

- Remote source baseline: branch security/private-daily-journey-admin-isolation-c408, HEAD 6d0e8fcc397a61bb7aaf0c1858b1147c5f81dae1, tree 1d8cc21b2e3a51826b593fae3fca106cc829e3d7. The complete recursive tree contains 37 numbered SQL migrations and 36 unique version prefixes. The duplicate 202607260007 bodies remain distinct and unchanged.
- Migration 036 blob: 61a1fbf48b4557873ba6016e74fd3995bc62ba14. Its source requires the daily_reflections table and both historical admin-readable policy naming variants introduced by the two 007 bodies. It enforces owner-only browser SELECT/INSERT/UPDATE, removes browser DELETE access and retains the trusted service_role grant. It has no SQL dependency on migration 035 or the delivery migrations.
- At the initial source inspection, PR #22 was OPEN / DRAFT / UNMERGED with implementation HEAD 6d0e8fcc397a61bb7aaf0c1858b1147c5f81dae1 and base security/delivery-transport-consent-gates at cfe05475dbe7822f96be639fd2c777a6062aedc4. Its four then-current files were docs/SPRINT_10_1_DAILY_DEED_COMPLETION.md, scripts/test-privacy-authorization-database.sh, scripts/test-privacy-authorization-database.sql, and migration 036. C410 added docs/PRODUCTION_MIGRATION_RECONCILIATION.md and docs/DELIVERY_ROLLOUT_TRACKER.md to the same PR branch, so the current PR diff contains six files. PR #22 remains OPEN / DRAFT / UNMERGED and was not merged.
- Exact-head CI: [run 45174106399](https://github.com/ADRN-9/deedlight/actions/runs/45174106399), event push, branch security/private-daily-journey-admin-isolation-c408, head 6d0e8fcc397a61bb7aaf0c1858b1147c5f81dae1, SUCCESS 8/8. Jobs: validate (137690786472), delivery_migration_order_database_behavior (137690786170), privacy_authorization_database_behavior (137690786519), auth_pgcrypto_database_behavior (137690786551), sprint12_2_database_behavior (137690786579), gentle_delivery_transport_database_behavior (137690786720), delivery_provider_webhook_database_behavior (137690786804), and delivery_reliability_database_behavior (137690786847). The privacy job passed on disposable PostgreSQL. This is source/CI evidence only.
- PR #22's formal review endpoint returned zero submitted reviews. Independent security acceptance remains outstanding; developer implementation and CI are not independent approval.
- No Production migration is classified as applied, absent, or partially applied. All 37 files and independently identifiable effects remain UNKNOWN. Production remains NO-GO pending authorized read-only history/catalog/audit evidence, independent review, and the broader rollout gates.
- GitHub's remote ref/tree API exposes committed repository state, not a local working tree. No claim is made about uncommitted local changes; only the remote branch HEAD and committed tree were inspected.
- PRs #10, #11 and #19 were inspected read-only and remain OPEN / DRAFT / UNMERGED; none was modified. No PR was merged and no Production operation was performed.

## Historical evidence archive

The following retained C240/C241/C242/C245/C247 material is preserved for provenance. Its branch heads, blob hashes, CI references and 31-file inventory describe earlier source snapshots; the C404 inventory above supersedes them for current PR #10 source.

## Historical C241 — reported engineering acceptance (archival; not current formal review)

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

## Historical C245 — 31-file inventory at its recorded source HEAD (superseded)

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

## Historical C247 — duplicate 007 execution-order and Supabase CLI verification

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

### Final exact-head validation before this evidence addendum

- Branch-push #778, run 44965914853, completed SUCCESS with 7/7 jobs. Validate checked out exact branch HEAD c73902feb46768dd76044f63d2908d6ab746e74a, tree 1b7bd9b2bf526ab04be4daba2cba9ce2b19ed2d6.
- PR integration #779, run 44965919311, completed SUCCESS with 7/7 jobs. Validate checked out synthetic merge commit 94af4082989f98eff0390ec2fce8d6bfaae2ffe1, tree 1b7bd9b2bf526ab04be4daba2cba9ce2b19ed2d6; parents ce82b3fdf1a73510de70e3729a487d4ae00e66e3 and c73902feb46768dd76044f63d2908d6ab746e74a.
- Each run passed all seven jobs: validate, delivery_provider_webhook_database_behavior, delivery_migration_order_database_behavior, auth_pgcrypto_database_behavior, delivery_reliability_database_behavior, sprint12_2_database_behavior, and gentle_delivery_transport_database_behavior.


## Cycle 342 — Production audit recovery and current-head inventory verification

**Review date:** 2026-11-23  
**Implementation HEAD inspected before Cycle 342 documentation-only evidence commits:** c939d4a24293342deb6161eab2f28fb66765a237  
**Implementation tree inspected:** e321be2b406043b01c4ed4dd4cda003c54dbdd0e  
**Matrix blob before this addendum:** 7027543f0c8215dbabf804bb6ca235609f9e6f50

### Current source inventory verification

The complete recursive Git tree at the current PR #22 HEAD was inspected and was not truncated. It contains 37 numbered migration SQL files and 36 unique version prefixes. The 37 rows in the matrix above were compared against that exact tree:

- Exact filename and Git blob SHA matched for all 37 rows.
- Missing matrix rows: 0.
- Unlisted migration files: 0.
- Filename/blob mismatches: 0.
- Production classifications: 37 UNKNOWN.

The existing 37-row matrix is therefore retained rather than duplicated. Its dependency and effect descriptions remain source-level analysis; they do not establish Production execution. The two 202607260007 files remain separate source bodies with separate blob identities.

### Current authorized-access attempt

The connected Supabase integrations were checked for the repository-recorded Production project reference `xaipiovflxomcbfwtwmu`.

- `list_projects` was read through both currently connected Supabase accounts; neither returned the target project reference.
- `get_project`, `list_migrations`, and `list_tables` were attempted against the exact target project using both connected accounts. Each was denied with the connector response `MCP error -32600: You do not have permission to perform this action`.
- A strictly SELECT-only identity/history-presence query through `execute_sql` was attempted against the same project using both accounts. Both attempts were denied with the same permission error; no SQL result was returned.
- No Production migration history, schema/catalog result, policy/grant result, function/trigger result, or migration-036 application result was obtained.

These denials establish that the currently connected identities do not have the required access. They do **not** establish that the Production project is absent, that migration history is empty, that an object is missing, or that a migration did not execute.

### Recovered prior evidence — scope and limits

- Historical C404 documentation records earlier denied `get_project`, `list_migrations`, and `list_tables` attempts. The current Cycle 342 checks independently reproduce the permission boundary; they do not replace owner authorization.
- C247's isolated duplicate-007 verification is retained in CI. Branch-push run [44965336520](https://github.com/ADRN-9/deedlight/actions/runs/44965336520) and PR-validation run [44965340590](https://github.com/ADRN-9/deedlight/actions/runs/44965340590) passed their seven-job workflows. The migration-order jobs [137033022850](https://github.com/ADRN-9/deedlight/actions/runs/44965336520/job/137033022850) and [137033014594](https://github.com/ADRN-9/deedlight/actions/runs/44965340590/job/137033014594) ran Supabase CLI 3.2.0 against disposable PostgreSQL 16.16. Sprint 6 007 then Sprint 7 007 reached schema execution but failed history insertion with SQLSTATE 23505; Sprint 7 then Sprint 6 failed on missing `daily_post_id` with SQLSTATE 42703; the tested Sprint 6 + Sprint 7 + 008 + 012 + 013 sequence passed. These results establish isolated replay behavior only.
- PR #22 implementation exact-head push run [45185173965](https://github.com/ADRN-9/deedlight/actions/runs/45185173965) passed 8/8 jobs on HEAD `c939d4a24293342deb6161eab2f28fb66765a237`. Its privacy authorization database job [137728788900](https://github.com/ADRN-9/deedlight/actions/runs/45185173965/job/137728788900) applied migration 036 and passed the authorization assertions on disposable PostgreSQL. This is not Production application evidence.

The two Cycle 342 evidence-document commits were then validated by exact-head push run [45193172482](https://github.com/ADRN-9/deedlight/actions/runs/45193172482), SUCCESS, 8/8 jobs, at documentation-only branch HEAD `45346482af0ffbb5fa8e3ce29feb6bbf5c937f39`. This confirms the documentation update did not break CI; it does not add Production evidence.\n\n### Outstanding authorization and evidence requirements

A Production project owner/administrator must either grant an existing connected identity project-scoped read-only access to the exact project or provide an approved dedicated read-only PostgreSQL connection. Before any catalog query, independently verify the project reference and Production environment. The database role must be enforced read-only and limited to CONNECT, required schema USAGE, SELECT on migration history, and normal catalog visibility. It must not inherit service-role, administrator, migration, schema-write, credential-management, or outbound-delivery authority.

Until that access is supplied and the evidence is independently reviewed, the following remain UNKNOWN:

- All 37 file-level Production migration classifications and all independently identifiable effects.
- Which duplicate 007 body or bodies were executed in Production, and their execution order.
- Production migration-history rows for 007 and all other versions.
- Production schema, columns, constraints, indexes, RLS policies, table/schema/function/default grants, functions, and triggers.
- Whether migration 036 has been applied and whether its owner-only RLS/ACL effects are active.

Do not use `supabase db push`, `db pull`, `db reset`, migration repair, manual DDL, or any history mutation to resolve this evidence gap. Do not request or place credentials in repository files, PR comments, or chat. Production remains NO-GO.
