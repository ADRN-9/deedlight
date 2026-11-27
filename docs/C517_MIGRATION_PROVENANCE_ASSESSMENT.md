# C517 — DeedLight migration provenance and Production reconciliation assessment

**Assessment source HEAD:** `aaefdd0c2e2e9cd533082081cc52d7bcb6a4d9af`  
**Repository:** `ADRN-9/deedlight`  
**Assessment branch:** `feat/production-evidence-collector-e1-e2`  
**PR #24:** OPEN; this assessment is based on its current head.  
**PR #24 base:** `docs/production-migration-readonly-evidence-c426` at `8c54344b5a8b8a4c9c268ff8326ad0f163cc5e45`  
**Inventory Git blob SHA-1:** `95d514a0bd97ff448c9507252eb1f5e69a507442`  
**Production disposition:** **NO-GO**. No Production connection, query, migration, history repair, deployment or credential operation was performed for this assessment.

## Executive result

The assessed PR #24 source tree contains **39 migration SQL files and 38 unique 12-digit version prefixes**. The only duplicate-version group is `202607260007`, containing two distinct source bodies with different Git blob hashes. The pinned inventory manifest matches the repository tree and its pinned Git blob.

**All 39 Production execution classifications remain UNKNOWN.** The repository proves file existence and source bytes; it does not supply authenticated Production migration-history rows, exact execution artifacts, or a verified live Production catalog snapshot.

The repository's PR #24 CI run validates inventory/aggregate generation and disposable PostgreSQL fixtures. Those results do not establish Production execution or live schema equivalence.

## Scope and HEAD selection

This assessment uses the current head of PR #24 because that is the active repository candidate containing the 39-file inventory, migration evidence tooling and latest reconciliation material. It is not the default branch snapshot:

| Ref | HEAD | Migration files visible |
|---|---|---:|
| PR #24 `feat/production-evidence-collector-e1-e2` | `aaefdd0c2e2e9cd533082081cc52d7bcb6a4d9af` | 39 |
| PR #23 base `docs/production-migration-readonly-evidence-c426` | `8c54344b5a8b8a4c9c268ff8326ad0f163cc5e45` | 39 |
| `main` | `ca111d9464ee5b167fc30eb1905513c115f3ebf6` | 23 |
| PR #25 security candidate | `0958d169160586f4e764267f79a9eb8d45791a4c` | 33 |

These are different source snapshots, not interchangeable evidence. The 39-file inventory below is specifically pinned to the PR #24 assessment HEAD and its manifest. Do not infer that main or PR #25 already contains the 39-file source tree.

## Complete 39-file migration inventory

Every listed file exists at the assessment HEAD and matches the Git blob SHA-1 pinned in `supabase/migration-inventory.json`. The final column is the Production classification, not a source-file validation result.

| Version | Exact migration file | Git blob SHA-1 | Production |
|---|---|---|---|
| 202607210001 | `202607210001_initial_schema.sql` | `a244ab0df3e766b0f36e29a222b3160f9f74c502` | UNKNOWN |
| 202607210002 | `202607210002_rls_policies.sql` | `f96b482c0d1cf396baae5b91d7c96112f7e88284` | UNKNOWN |
| 202607220003 | `202607220003_sprint3_offerings_review.sql` | `74e02f2e60b82cf07a6aac5f8cf57dcdb6fe1382` | UNKNOWN |
| 202607260004 | `202607260004_sprint4_reactions.sql` | `c25dce46ecf69d082fcdbea2bb931b6acd9180fc` | UNKNOWN |
| 202607260005 | `202607260005_sprint5_moderation.sql` | `b48b4b8b3eea9fb55b68068011fa1371559228c2` | UNKNOWN |
| 202607260006 | `202607260006_sprint5_admin_edit_hide_hotfix.sql` | `9e163de5119c3813724341b7a9eabeba6fdc2970` | UNKNOWN |
| 202607260007 | `202607260007_sprint6_daily_deedlight.sql` | `e0c2379255003b8c7bc85a1fab781e23051f5e47` | UNKNOWN |
| 202607260007 | `202607260007_sprint7_pwa_daily_engagement.sql` | `8b051cfce05ea75b1ee7a726864e2ad760f6fe5f` | UNKNOWN |
| 202607270008 | `202607270008_sprint8_short_video_studio.sql` | `5b583bd99562e14db554943d034c748ce302f5ee` | UNKNOWN |
| 202608060009 | `202608060009_sprint9_profiles_privacy.sql` | `6594ce6daa0183944fcc548885d6514e8adb9436` | UNKNOWN |
| 202608100010 | `202608100010_sprint9_2_community_identity_consistency.sql` | `774708b7705d88a5a1e0da97e72a9d1b47c8884c` | UNKNOWN |
| 202608100011 | `202608100011_sprint9_3_moderation_aware_members.sql` | `1d1b7b844b88077351d2658af4be2b2db92eda97` | UNKNOWN |
| 202608110012 | `202608110012_sprint10_1_daily_deed_completion.sql` | `0973f72e39ce07b41e053a20f1b781c394578877` | UNKNOWN |
| 202608110013 | `202608110013_sprint10_2_saved_lights_gentle_rhythm.sql` | `5fd2f4a796a8a1dfd6237ccf36d1ab62c1dc1714` | UNKNOWN |
| 202608120014 | `202608120014_sprint10_3_gentle_reminder_preferences.sql` | `2af1a6a2aa5cffc6ef6d08849b6f71fab44a54d0` | UNKNOWN |
| 202608130015 | `202608130015_sprint11_2_weekly_goodness.sql` | `394c774032d8206c0b7a373640859c2a331667a9` | UNKNOWN |
| 202608130016 | `202608130016_sprint11_3_invitations_newsletter_foundation.sql` | `8d68ed19859e1a820af52a43c110a38b6a460d48` | UNKNOWN |
| 202608130017 | `202608130017_sprint12_1_offering_ownership_engagement.sql` | `bc23b12fe454c1f49b096fd2c7199e3a2aea5bb4` | UNKNOWN |
| 202608140018 | `202608140018_sprint12_1_owner_removal_guard_hotfix.sql` | `0ea7eaf04d5c99e4c5a25893aae7694affdd44bc` | UNKNOWN |
| 202609230019 | `202609230019_sprint12_2_gentle_delivery_foundation.sql` | `1403b9324e786a2b724176875a70ffce92961d9b` | UNKNOWN |
| 202609230020 | `202609230020_delivery_reliability_hardening.sql` | `554615da3d15fc4c0d395691103d3be5676856fa` | UNKNOWN |
| 202609230021 | `202609230021_gentle_delivery_transport.sql` | `e50a06bd3a5ed386c54e789435c64b2bb4a54ab9` | UNKNOWN |
| 202609240022 | `202609240022_auth_pgcrypto_schema_qualification.sql` | `f42afb3474f80c7d95cf5b47023b82cf5a948d4d` | UNKNOWN |
| 202611120023 | `202611120023_delivery_consent_linearization.sql` | `75f5086feab2cbda381066cb9094390190c3332f` | UNKNOWN |
| 202611120024 | `202611120024_delivery_identity_lease_capacity.sql` | `240271fd75081c062627cfc3d40bdc0c5feda049` | UNKNOWN |
| 202611190025 | `202611190025_delivery_provider_webhooks.sql` | `e97c5c0ad645dfe43f11a88f01b030fa23dd5822` | UNKNOWN |
| 202611190026 | `202611190026_delivery_provider_lifecycle.sql` | `6a06d780ad65babf2293a2746c68913758313af8` | UNKNOWN |
| 202611200027 | `202611200027_delivery_provider_integrity.sql` | `a1469938ea13b5cb9d7cd883772bc60e4a058026` | UNKNOWN |
| 202611210028 | `202611210028_delivery_claim_lock_expiry.sql` | `09d1927fba81d711bb37d214609931d2da2173a1` | UNKNOWN |
| 202611210029 | `202611210029_delivery_legacy_replay_guard.sql` | `872fc49ec47e49b17e96ecf6ccaf5c8eb0e6322a` | UNKNOWN |
| 202611210030 | `202611210030_delivery_idempotency_receipt_guard.sql` | `c5e3955c4e0dde708a8ffdc9c420807c4241fa32` | UNKNOWN |
| 202611220031 | `202611220031_delivery_final_recipient_suppression_gate.sql` | `26d69a0a4e73bc7cfd05814f3f6129bc199da02b` | UNKNOWN |
| 202611220032 | `202611220032_resend_suppression_list_sync.sql` | `6a0c0193d85ece99335f8715a65243ac42617f97` | UNKNOWN |
| 202611220033 | `202611220033_delivery_cross_stream_suppression_order.sql` | `1cd0c2db5415a37b9a31ed8ef7de54db9019a88f` | UNKNOWN |
| 202611230034 | `202611230034_delivery_suppression_timestamp_order.sql` | `4ec8aa578ad851918f4c4b2535c476b4ceb40f1d` | UNKNOWN |
| 202611230035 | `202611230035_private_offering_base_table_rls.sql` | `3d0ce8dfd4abb88fccccd23c5ffb9c35f699c098` | UNKNOWN |
| 202611230036 | `202611230036_private_daily_reflection_admin_isolation.sql` | `61a1fbf48b4557873ba6016e74fd3995bc62ba14` | UNKNOWN |
| 202611240037 | `202611240037_delivery_provider_integrity_conflict_evidence.sql` | `ac0449b50a881e3a895ef40a8eee28bea95a6ec0` | UNKNOWN |
| 202611240038 | `202611240038_delivery_provider_integrity_lock_order_pagination.sql` | `38951751fc5abeb79b75c4e37e55da01262a18b8` | UNKNOWN |

## Evidence categories — do not conflate them

| Evidence category | What is available in this repository | What it proves |
|---|---|---|
| Migration file existence | 39 files at the assessment HEAD; pinned manifest and per-file Git blob hashes | Exact source files exist in this Git tree |
| Migration-history entries | No authenticated Production export is present. The collector SQL selects `version`, `name`, and `cardinality(statements)` from `supabase_migrations.schema_migrations` only | No Production history row is established by repository evidence |
| Actual SQL execution | Disposable PostgreSQL/Supabase CLI tests, source history and documentation; no authenticated Production deployment/SQL Editor execution record supplied | CI execution is fixture-only; no Production execution is established |
| Verified live Production schema | No Production catalog snapshot, signed evidence envelope or verified live-schema export is present | No live Production schema equivalence is established |

The audit SQL explicitly says the Supabase history table does not establish the executed source hash, actor, wall-clock execution time, external execution ID or retained deployment/SQL Editor record. A history row, even if later collected, is not by itself proof that the current SQL bytes ran or that all side effects completed.

The repository has a generated SQL Editor aggregate, `supabase/run_in_sql_editor_all.sql`, whose source generator validates the exact 39-file manifest and includes the separately pinned `supabase/bootstrap/migration_038_admin_compatibility.sql` after migration 037 and the three-upsert seed after the second migration. The aggregate is a deterministic source bundle, **not a Production schema snapshot or execution receipt**. The compatibility bootstrap is not a 40th migration and is not part of the 39-file inventory.

## Findings requiring explicit handling

### Duplicate version 007

The two 007 files are independent SQL bodies with different Git blob hashes. A single primary-keyed `schema_migrations.version='202607260007'` row cannot prove which source body ran, nor that both ran.

The exact-head PR #24 CI run `45896308928` passed the disposable PostgreSQL/Supabase CLI 3.2.0 duplicate-version regression. It demonstrated two failure paths:
- Sprint 6 then Sprint 7: SQLSTATE `23505`, duplicate primary key on `schema_migrations.version`.
- Sprint 7 then Sprint 6: SQLSTATE `42703`, missing `daily_reflections.daily_post_id` when Sprint 6 is applied second.

Thus normal `supabase db push` is not safe with both same-version files in the migration directory. This is fixture evidence about CLI behavior, not evidence of which body Production executed.

**Required resolution:** obtain authoritative historical deployment/SQL Editor artifacts and compare exact effects. Preserve both original files and hashes. Do not rename or rewrite either historical source as a shortcut. After the executed body and live effects are established, prepare a reviewed forward-only unique-version migration for any genuinely missing effects, and separately design a supported history/file-layout transition for the duplicate. Validate clean-database replay and a restored Production clone before enabling normal pushes.

### Migration 018 — historical prerequisite

Migration 018 checks that `public.offerings.owner_removed_at` and `public.remove_own_offering(uuid)` exist and that the count of Offerings with `owner_removed_at IS NOT NULL` is zero **at the exact migration execution point**. It then adds a consistency constraint and replaces the guarded removal RPC.

A present-day zero count cannot prove the historical precondition. Required evidence is the contemporaneous preflight result plus exact execution record/timestamp and associated deployment/SQL Editor log or equivalent immutable artifact. Without it, Migration 018 and its prerequisite remain UNKNOWN.

### Migration 037 — timestamp and backfill completeness

Migration 037 preflights the exact 033/034 provider RPC comments and prerequisite objects, then creates private case/evidence/history tables and wrappers. Its legacy backfill:
- groups case keys by `(recipient_email, anomaly_type)`;
- joins anomaly rows to known provider events and to the stored event identified by `coalesce(related_event_id,event_id)`;
- inserts cases and legacy evidence with `ON CONFLICT DO NOTHING`;
- does not declare expected row counts or a completion assertion in the migration itself;
- excludes orphaned anomalies and rows missing either required event join.

The migration's execution timestamp is not supplied by `schema_migrations`. The repository includes a separate human-controlled DBA-only aggregate audit, `scripts/production-migration-037-backfill-aggregate-audit.sql`, which compares current source anomaly/event rows to current legacy evidence and emits aggregate counts only. It explicitly does not prove migration execution provenance. Since anomalies/events can change after migration time, a current comparison alone cannot reconstruct the historical eligible set or prove completeness at the original execution point.

The PR #24 CI job `migration_037_backfill_database_behavior` passed against a disposable PostgreSQL 16 fixture. Its tests cover read-only/DBA authorization, aggregate-only output, incomplete and inconsistent fixture detection, and unauthorized access. This is a test of the audit's behavior, not a Production backfill receipt.

**Required resolution:** obtain the independently authenticated Migration 037 execution timestamp and actor/execution identity from authoritative logs; provide contemporaneous pre/post aggregate evidence or a restorable point-in-time snapshot that bounds the source anomaly/event set; run the DBA-only aggregate audit only in an explicitly approved read-only window; preserve only approved aggregate output, never row contents, recipient emails, event IDs or payloads. If historical source rows cannot be reconstructed, completeness remains UNKNOWN.

## Repository snapshots, history records, fixtures and documentation

- `supabase/migration-inventory.json` pins 39 source paths, 38 unique versions and the intentional 007 duplicate pair. Its Git blob SHA-1 at this HEAD is exactly `95d514a0bd97ff448c9507252eb1f5e69a507442`.
- `scripts/verify-migration-inventory-aggregate.mjs` checks actual directory contents, source blob hashes/byte lengths, inventory blob hash, duplicate policy, seed and generated aggregate. It does not connect to Production.
- `scripts/production-migration-readonly-audit.sql` is a SELECT-only catalog/history audit with a narrow direct-login collector role contract. Its history projection is only three database facts: version, name, statement count.
- `scripts/test-production-migration-readonly-audit-postgres16-fixture.sql` creates a synthetic `supabase_migrations.schema_migrations` table and inserts a synthetic `202611240038` row. This is not a copied Production history record.
- `scripts/test-duplicate-migration-007.sh` tests the Supabase CLI collision and both ordering outcomes against disposable databases.
- `scripts/test-migration-037-backfill-audit-postgres16-fixture.sql` and its runner use synthetic provider events/anomalies and a disposable database.
- `docs/PRODUCTION_MIGRATION_RECONCILIATION_LEDGER.md` states all 39 entries are NOT COLLECTED / UNCLASSIFIED and records the 007/018/037 cautions. Its source-baseline SHA is historical (`def0de7e33d57a05e2ee6e38e43796c24562b425`), although its inventory blob pin matches the assessed inventory.
- `docs/PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md` contains an older Cycle 363 snapshot that refers to a 37-file inventory. Treat that count and its linked historical inventory statement as stale; the current assessed PR #24 inventory is 39 files.
- `docs/PRODUCTION_MIGRATION_RECONCILIATION.md` contains historical Cycle 390 source context. It is not a current Production evidence report.
- `docs/PRODUCTION_MIGRATION_EVIDENCE_RUNBOOK.md` and `docs/PRODUCTION_MIGRATION_EVIDENCE_COLLECTOR_E1_E2.md` define the read-only collection and trust boundaries. The collector package explicitly does not connect to Production by itself, sign receipts, provide immutable storage, or accept migration classifications.

## CI evidence — exact assessment HEAD

[PR #24 Full PR Validation run 45896308928](https://github.com/ADRN-9/deedlight/actions/runs/45896308928) completed **SUCCESS** for exact source HEAD `aaefdd0c2e2e9cd533082081cc52d7bcb6a4d9af`. All 12 jobs passed, including:
- `validate` — migration inventory output: 39 files / 38 unique versions; duplicate 007 pair preserved; seed 3 upserts; deterministic aggregate generated and checked;
- `delivery_migration_order_database_behavior` — disposable CLI duplicate-version and replay behavior;
- `migration_037_backfill_database_behavior` — disposable PostgreSQL 16 Migration 037 audit fixture;
- `production_evidence_collector_postgres16` — disposable collector integration fixture;
- the other delivery, privacy, webhook, auth/pgcrypto, ownership and database-behavior jobs.

This is repository/CI validation only. The collector receipt remains explicitly `UNSIGNED_NOT_ACCEPTED`; the CI fixtures use synthetic identities/data and no Production credentials.

## DBA / Supabase administrator dependency register

| Owner | Required evidence or action | Acceptance condition | Current status |
|---|---|---|---|
| Production owner / Supabase administrator | Independently confirm the exact DeedLight Production project reference and endpoint using the Dashboard and trusted environment record | Project reference `xaipiovflxomcbfwtwmu` and endpoint identity match; never infer from a SQL GUC alone | NOT PROVIDED |
| DBA / security owner | Approve a bounded read-only collection window and dedicated direct-login `deedlight_catalog_auditor` principal | Direct TLS login; non-superuser/non-owner; no inherited memberships, app-row access or unsafe effective privileges; read-only transaction | NOT PROVIDED |
| DBA | Execute the approved read-only catalog/history collector on the verified endpoint | Complete catalog, exact history export, effective privilege evidence, query digest and transaction rollback proof | NOT COLLECTED |
| DBA / deployment operator | Supply authoritative historical migration execution records (CI deploy logs, Supabase migration logs, SQL Editor audit logs or equivalent immutable records) | Bind each claimed execution to exact file/source hash where available, actor, timestamp, execution identity and target project | NOT PROVIDED |
| DBA / deployment operator | Resolve Migration 007 source ambiguity | Establish which 007 body ran, and whether any effects from the other body were applied separately; one history row is insufficient | UNKNOWN |
| DBA | Supply Migration 018 contemporaneous preflight evidence | Prove `owner_removed_at IS NOT NULL` count was zero at execution time, not merely now | NOT PROVIDED |
| DBA / provider-integrity operator | Supply Migration 037 execution timestamp/identity and contemporaneous backfill evidence | Establish the historical anomaly/event set and prove case/evidence completeness, or explicitly retain UNKNOWN if unrecoverable | NOT PROVIDED |
| DBA / key custodian | Provision endpoint profile, CA root, passfile and collector environment outside Git; independently pin endpoint-profile and CA digests | Exact TLS verify-full endpoint, private files, secret-manager delivery; no credentials in repo/chat/logs | NOT PROVIDED |
| Collector/key custodian | Provide E3 signing service/KMS/HSM and trusted collector identity | Signed collector attestation bound to exact evidence/query bundle/capture; key lifecycle and revocation controls | NOT IMPLEMENTED |
| Independent evidence approver | Sign exact Production evidence digest | Distinct trusted Ed25519 identity/key, valid claims and expiry | NOT PROVIDED |
| Independent migration-mapping reviewer | Review all 39 SQL files across all nine effect domains and sign mapping digest | Complete source-linked schema, ACL, ownership, routines, transformations, backfills, dependencies, preconditions and postconditions map | NOT PROVIDED |
| Independent evidence custodian | Provide E4 immutable evidence store and retention/access controls | Signed receipts, raw evidence digests and audit trail retained outside repository | NOT IMPLEMENTED |
| DBA / application owner | Produce backup/PITR restore point and restore into isolated non-Production project | Restore verified; schema/history parity and representative app invariants checked; delivery disabled | NOT PROVIDED |
| DBA / security approver | Approve explicit reconciliation change plan and rollback window | All source ambiguities resolved or scoped; independent approval; no blind history repair | NOT PROVIDED |

## Safe reconciliation proposal and rollback gates

1. **Keep Production migration writes frozen.** Do not run `supabase db push`, `supabase migration repair`, SQL Editor DDL, `db reset`, or history-table writes while evidence is incomplete. Do not mark migrations applied based on filenames, CI, aggregate SQL, or current catalog objects.
2. **Collect read-only evidence first.** After owner/DBA prerequisites are satisfied, use the pinned collector at a reviewed exact commit. Verify endpoint/TLS independently, authenticate directly as the dedicated read-only role, export complete catalog and history projections, and retain raw evidence outside Git. Do not use the collector identity for the Migration 037 private-row aggregate audit.
3. **Obtain independent trust and mapping.** Complete the 39-entry/nine-domain semantic map and obtain separate evidence-approver, mapping-approver and collector attestations. The current E2 receipt is unsigned and cannot be accepted.
4. **Resolve 007, 018 and 037 explicitly.** Preserve UNKNOWN if authoritative execution records or contemporaneous preconditions/backfill evidence cannot be recovered. Do not coerce ambiguity into Applied and verified.
5. **Restore to an isolated clone.** Verify a supported PITR/backup restore point, restore into a network-isolated non-Production project with matching Supabase/PostgreSQL major version and extensions, then compare catalog, history, data invariants and delivery-disabled state. Exercise the proposed migration layout and CLI push only on this clone.
6. **Prepare a reviewed forward-only migration plan.** Keep original historical migration files immutable. For any missing effects, create a new unique-version forward migration after semantic review and clone rehearsal. Design the duplicate-007 layout/history transition separately; normal `db push` must remain disabled until a clean clone and restored clone both prove the same deterministic sequence.
7. **Approve and execute only under a separate change authorization.** DBA, security owner and independent reviewer approve the exact history/schema delta, backup restore point, expected row/object counts, monitoring and rollback window. The current C517 assessment authorizes none of those operations.

**Rollback:** Prefer restoration to the verified pre-change PITR point or isolated-clone rehearsal. Do not invent reverse SQL for historical data transformations, backfills, constraints or provider state. A history-only repair is not a schema rollback and must have a separately captured before-state, exact intended row delta, transactional/operational rollback plan and explicit DBA approval. Stop on any unexpected count, object fingerprint, privilege, index validity or postcondition; leave the system fail-closed rather than retrying a partially understood repair.

## Final classification and blockers

- Source inventory: **PASS — 39 files / 38 unique versions; 007 duplicate preserved**.
- Source file existence and Git blob integrity: **PASS in repository CI**.
- CI fixtures: **PASS on assessment HEAD**; they are not Production evidence.
- Recorded Production history: **NOT COLLECTED**.
- Actual Production SQL execution: **UNKNOWN for all 39**.
- Verified live Production schema: **NOT COLLECTED**.
- Migration 007: **UNKNOWN — duplicate source/version ambiguity**.
- Migration 018: **UNKNOWN — contemporaneous zero-row precondition and execution unverified**.
- Migration 037: **UNKNOWN — execution timestamp and historical backfill completeness unverified**.
- Normal Production `supabase db push`: **NOT APPROVED**.
- Production reconciliation: **NOT AUTHORIZED / NO-GO**.

PR #25 remains a separate outstanding security-acceptance blocker: it is still OPEN / UNMERGED, and its only recorded review is author-authored `COMMENTED`, not independent approval. C517 does not alter or resolve PR #25.
