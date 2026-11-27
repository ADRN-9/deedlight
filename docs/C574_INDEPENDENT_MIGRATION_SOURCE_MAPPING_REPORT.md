# C574 — Independent migration-source and semantic mapping report

**Status:** Source mapping artifact and executable provenance verifier authored; PostgreSQL semantic verification NOT IMPLEMENTED.  
**Repository:** `ADRN-9/deedlight`  
**Source commit inspected:** `2133cee1439287399740bf9794bbb0b4e793105c` (PR #29 head)  
**C573 architecture commit:** `98cb712a890b8809ac309727264927e9b4d7cc36`  
**Pinned inventory Git blob:** `4e63f31368d446e905f4f44565be73337c7188fb`

## 1. Decision and scope

C574 adds a 40-entry source-observation map and a fail-closed verifier. The artifact distinguishes migration version from exact source identity and records source construct families plus schema-qualified reference tokens. The tokens are explicitly unresolved lexical observations; they are not PostgreSQL object identities, AST nodes, or dependency edges.

This is not a PostgreSQL semantic parser, resolver, migration execution, catalog snapshot, or semantic approval. Every migration remains `NOT_ACCEPTED`; all five non-catalog lifecycle domains remain `UNKNOWN` for every entry.

## 2. Independent repository verification

At C574 start, GitHub PR API returned:

- PR #29 OPEN and UNMERGED.
- Head branch `fix/c558-pr28-security-remediation`.
- Head SHA `2133cee1439287399740bf9794bbb0b4e793105c`.
- Base SHA `0e5bf38f1fdd67300825ecdf29555aa1ff3674b7`.

The C573 architecture commit was independently fetched and matched `98cb712a890b8809ac309727264927e9b4d7cc36`; its document blob was `466d5f1a792baacdf68a85c279e11acdc7246fe4`. C573 is not part of PR #29's head.

The inventory at the inspected PR head contains 40 migration entries and 39 unique versions. The duplicate group is exactly the two distinct `202607260007` sources. Migration `202611260039_delivery_kind_scoped_claims.sql` is retained.

## 3. Delivered artifacts

- `docs/c574-migration-source-semantic-map.json` — exact 40-entry source map.
- `scripts/verify-c574-source-semantic-map.mjs` — verifies inventory binding, exact source Git blob SHA-1 and byte length, duplicate 007 identity, Migration 039, all five UNKNOWN dispositions, and no inferred dependency/execution edges.
- `scripts/test-c574-source-semantic-map.mjs` — executable Node test suite for mapping/provenance/security invariants and literal distinctions.
- `package.json` — adds `verify:c574-source-map` and `test:c574-source-map`.
- `.github/workflows/pr-validation.yml` — adds both C574 checks and expands PR base-branch coverage to `main`, `feat/**`, `docs/**`, and `fix/**`.

The map contains **40 source entries** and **372 qualified reference tokens**. The token extraction records names such as `public.delivery_ledger`, `public.claim_daily_delivery_jobs`, `auth.users`, `extensions.gen_random_bytes`, `storage.objects`, and PostgreSQL catalog references. These remain `UNRESOLVED_LEXICAL_REFERENCE` / `NOT_PERFORMED`; they may denote relations, routines, types, namespaces, catalog objects, or callable symbols. No object-kind resolution or overload resolution is claimed.

## 4. Complete source inventory coverage

The following table binds each mapping row to the exact inventory path, migration version, Git blob SHA-1, and byte length. The same version may have more than one source identity.

| Version | Source file | Git blob SHA-1 | Bytes | Qualified tokens | Source constructs observed (not semantic effects) |
|---|---|---|---:|---:|---|
| `202607210001` | `202607210001_initial_schema.sql` | `a244ab0df3e766b0f36e29a222b3160f9f74c502` | 13648 | 18 | extension_ddl, table_ddl, foreign_keys_and_constraints, indexes, trigger_ddl, plpgsql_routines, views, seed_or_projection_select |
| `202607210002` | `202607210002_rls_policies.sql` | `f96b482c0d1cf396baae5b91d7c96112f7e88284` | 5885 | 16 | sql_routines, row_level_security, policies, grants, storage_object_policies, storage_bucket_dml |
| `202607220003` | `202607220003_sprint3_offerings_review.sql` | `74e02f2e60b82cf07a6aac5f8cf57dcdb6fe1382` | 1064 | 4 | view_ddl, select_projection, joins, conditional_expression |
| `202607260004` | `202607260004_sprint4_reactions.sql` | `c25dce46ecf69d082fcdbea2bb931b6acd9180fc` | 4983 | 8 | table_ddl, indexes, trigger_ddl, plpgsql_routines, view_ddl, aggregate_query |
| `202607260005` | `202607260005_sprint5_moderation.sql` | `b48b4b8b3eea9fb55b68068011fa1371559228c2` | 5775 | 8 | table_ddl, indexes, trigger_ddl, plpgsql_routines, data_repair_update, view_ddl, constraints |
| `202607260006` | `202607260006_sprint5_admin_edit_hide_hotfix.sql` | `9e163de5119c3813724341b7a9eabeba6fdc2970` | 2008 | 6 | plpgsql_do_block, dynamic_sql_execute_format, table_ddl, grants, policies, view_ddl |
| `202607260007` | `202607260007_sprint6_daily_deedlight.sql` | `e0c2379255003b8c7bc85a1fab781e23051f5e47` | 9545 | 8 | extension_ddl, table_ddl, alter_table_ddl, constraints, indexes, trigger_ddl, plpgsql_routines, policies, grants, seed_insert_select |
| `202607260007` | `202607260007_sprint7_pwa_daily_engagement.sql` | `8b051cfce05ea75b1ee7a726864e2ad760f6fe5f` | 6279 | 6 | transaction_control, table_ddl, alter_table_ddl, constraints, policies, grants, data_repair_update |
| `202607270008` | `202607270008_sprint8_short_video_studio.sql` | `5b583bd99562e14db554943d034c748ce302f5ee` | 1890 | 1 | transaction_control, alter_table_ddl, constraints, indexes, grants |
| `202608060009` | `202608060009_sprint9_profiles_privacy.sql` | `6594ce6daa0183944fcc548885d6514e8adb9436` | 6031 | 8 | transaction_control, alter_table_ddl, data_repair_update, plpgsql_do_block, plpgsql_routines, policies, views, grants, revoke |
| `202608100010` | `202608100010_sprint9_2_community_identity_consistency.sql` | `774708b7705d88a5a1e0da97e72a9d1b47c8884c` | 3294 | 6 | transaction_control, plpgsql_routines, views, grants, revoke, notify |
| `202608100011` | `202608100011_sprint9_3_moderation_aware_members.sql` | `1d1b7b844b88077351d2658af4be2b2db92eda97` | 12225 | 12 | transaction_control, table_ddl, indexes, alter_table_ddl, policies, plpgsql_routines, data_mutation, grants, revoke, notify |
| `202608110012` | `202608110012_sprint10_1_daily_deed_completion.sql` | `0973f72e39ce07b41e053a20f1b781c394578877` | 4462 | 5 | transaction_control, alter_table_ddl, constraints, indexes, policies, views, data_repair_update, grants, revoke, plpgsql_do_block, notify |
| `202608110013` | `202608110013_sprint10_2_saved_lights_gentle_rhythm.sql` | `5fd2f4a796a8a1dfd6237ccf36d1ab62c1dc1714` | 2769 | 3 | transaction_control, alter_table_ddl, constraints, indexes, policies, grants, revoke, data_repair_update, notify |
| `202608120014` | `202608120014_sprint10_3_gentle_reminder_preferences.sql` | `2af1a6a2aa5cffc6ef6d08849b6f71fab44a54d0` | 2523 | 5 | transaction_control, table_ddl, trigger_ddl, plpgsql_routines, policies, grants, revoke, notify |
| `202608130015` | `202608130015_sprint11_2_weekly_goodness.sql` | `394c774032d8206c0b7a373640859c2a331667a9` | 8089 | 11 | transaction_control, table_ddl, indexes, trigger_ddl, plpgsql_routines, data_mutation, aggregate_query, grants, revoke, notify |
| `202608130016` | `202608130016_sprint11_3_invitations_newsletter_foundation.sql` | `8d68ed19859e1a820af52a43c110a38b6a460d48` | 12951 | 14 | transaction_control, extension_ddl, table_ddl, indexes, trigger_ddl, plpgsql_routines, policies, data_mutation, grants, revoke, notify |
| `202608130017` | `202608130017_sprint12_1_offering_ownership_engagement.sql` | `bc23b12fe454c1f49b096fd2c7199e3a2aea5bb4` | 11901 | 11 | transaction_control, alter_table_ddl, indexes, policies, plpgsql_routines, data_mutation, grants, revoke, notify |
| `202608140018` | `202608140018_sprint12_1_owner_removal_guard_hotfix.sql` | `0ea7eaf04d5c99e4c5a25893aae7694affdd44bc` | 2780 | 4 | transaction_control, plpgsql_do_block, catalog_preflight_queries, dynamic_sql_execute_format, alter_table_ddl, plpgsql_routines, data_mutation, grants, revoke, notify |
| `202609230019` | `202609230019_sprint12_2_gentle_delivery_foundation.sql` | `1403b9324e786a2b724176875a70ffce92961d9b` | 15845 | 16 | transaction_control, plpgsql_routines, table_ddl, indexes, trigger_ddl, policies, data_mutation, grants, revoke, notify |
| `202609230020` | `202609230020_delivery_reliability_hardening.sql` | `554615da3d15fc4c0d395691103d3be5676856fa` | 13642 | 13 | transaction_control, plpgsql_do_block, catalog_preflight_queries, alter_table_ddl, indexes, plpgsql_routines, data_mutation, grants, revoke, notify |
| `202609230021` | `202609230021_gentle_delivery_transport.sql` | `e50a06bd3a5ed386c54e789435c64b2bb4a54ab9` | 3417 | 7 | transaction_control, plpgsql_do_block, catalog_preflight_queries, alter_table_ddl, plpgsql_routines, data_mutation, grants, revoke, notify |
| `202609240022` | `202609240022_auth_pgcrypto_schema_qualification.sql` | `f42afb3474f80c7d95cf5b47023b82cf5a948d4d` | 1214 | 4 | transaction_control, plpgsql_do_block, catalog_preflight_queries, plpgsql_routines, dynamic_sql_risk_review, extension_reference, notify |
| `202611120023` | `202611120023_delivery_consent_linearization.sql` | `75f5086feab2cbda381066cb9094390190c3332f` | 9411 | 12 | transaction_control, plpgsql_do_block, catalog_preflight_queries, plpgsql_routines, data_mutation, grants, revoke, notify |
| `202611120024` | `202611120024_delivery_identity_lease_capacity.sql` | `240271fd75081c062627cfc3d40bdc0c5feda049` | 12329 | 14 | transaction_control, plpgsql_do_block, catalog_preflight_queries, plpgsql_routines, catalog_introspection, advisory_lock_calls, dynamic_sql_risk_review, data_mutation, grants, revoke, notify |
| `202611190025` | `202611190025_delivery_provider_webhooks.sql` | `e97c5c0ad645dfe43f11a88f01b030fa23dd5822` | 17132 | 14 | transaction_control, plpgsql_do_block, catalog_preflight_queries, table_ddl, indexes, plpgsql_routines, advisory_lock_calls, data_mutation, grants, revoke, notify |
| `202611190026` | `202611190026_delivery_provider_lifecycle.sql` | `6a06d780ad65babf2293a2746c68913758313af8` | 13857 | 6 | transaction_control, plpgsql_do_block, catalog_preflight_queries, table_ddl, constraints, indexes, plpgsql_routines, advisory_lock_calls, data_mutation, grants, revoke, notify |
| `202611200027` | `202611200027_delivery_provider_integrity.sql` | `a1469938ea13b5cb9d7cd883772bc60e4a058026` | 20879 | 7 | transaction_control, alter_table_ddl, constraints, indexes, plpgsql_routines, plpgsql_control_flow, advisory_lock_calls, data_mutation, grants, revoke, notify |
| `202611210028` | `202611210028_delivery_claim_lock_expiry.sql` | `09d1927fba81d711bb37d214609931d2da2173a1` | 9643 | 11 | transaction_control, plpgsql_do_block, catalog_preflight_queries, plpgsql_routines, data_mutation, advisory_lock_risk_review, grants, revoke, notify |
| `202611210029` | `202611210029_delivery_legacy_replay_guard.sql` | `872fc49ec47e49b17e96ecf6ccaf5c8eb0e6322a` | 7476 | 9 | transaction_control, plpgsql_do_block, catalog_introspection, catalog_preflight_queries, dynamic_sql_execute_format, plpgsql_routines, grants, revoke, notify |
| `202611210030` | `202611210030_delivery_idempotency_receipt_guard.sql` | `c5e3955c4e0dde708a8ffdc9c420807c4241fa32` | 12214 | 11 | transaction_control, plpgsql_do_block, catalog_introspection, catalog_preflight_queries, dynamic_sql_execute_format, plpgsql_routines, data_mutation, grants, revoke, notify |
| `202611220031` | `202611220031_delivery_final_recipient_suppression_gate.sql` | `26d69a0a4e73bc7cfd05814f3f6129bc199da02b` | 6477 | 11 | transaction_control, plpgsql_do_block, catalog_preflight_queries, plpgsql_routines, data_mutation, advisory_lock_calls, grants, revoke, notify |
| `202611220032` | `202611220032_resend_suppression_list_sync.sql` | `6a0c0193d85ece99335f8715a65243ac42617f97` | 14118 | 7 | transaction_control, alter_table_ddl, constraints, indexes, table_ddl, plpgsql_routines, data_mutation, advisory_lock_calls, grants, revoke, notify |
| `202611220033` | `202611220033_delivery_cross_stream_suppression_order.sql` | `1cd0c2db5415a37b9a31ed8ef7de54db9019a88f` | 4647 | 6 | transaction_control, plpgsql_do_block, catalog_preflight_queries, plpgsql_routines, data_mutation, advisory_lock_calls, grants, revoke, notify |
| `202611230034` | `202611230034_delivery_suppression_timestamp_order.sql` | `4ec8aa578ad851918f4c4b2535c476b4ceb40f1d` | 11255 | 7 | transaction_control, indexes, plpgsql_routines, data_mutation, advisory_lock_calls, grants, revoke, notify |
| `202611230035` | `202611230035_private_offering_base_table_rls.sql` | `3d0ce8dfd4abb88fccccd23c5ffb9c35f699c098` | 564 | 1 | transaction_control, policy_ddl |
| `202611230036` | `202611230036_private_daily_reflection_admin_isolation.sql` | `61a1fbf48b4557873ba6016e74fd3995bc62ba14` | 2042 | 2 | transaction_control, alter_table_ddl, policies, grants, revoke, notify |
| `202611240037` | `202611240037_delivery_provider_integrity_conflict_evidence.sql` | `ac0449b50a881e3a895ef40a8eee28bea95a6ec0` | 44182 | 24 | transaction_control, plpgsql_do_block, catalog_preflight_queries, table_ddl, constraints, indexes, plpgsql_routines, trigger_ddl, plpgsql_control_flow, advisory_lock_calls, data_mutation, grants, revoke, notify |
| `202611240038` | `202611240038_delivery_provider_integrity_lock_order_pagination.sql` | `38951751fc5abeb79b75c4e37e55da01262a18b8` | 43748 | 32 | transaction_control, plpgsql_do_block, catalog_introspection, catalog_preflight_queries, indexes, plpgsql_routines, dynamic_sql_execute_format, plpgsql_control_flow, advisory_lock_calls, grants, revoke, notify |
| `202611260039` | `202611260039_delivery_kind_scoped_claims.sql` | `39eba637aa9f93fa77855f82f3fcc27b580b25da` | 6177 | 4 | transaction_control, plpgsql_routines, data_mutation, grants, revoke, notify |

The executable verifier additionally reads the actual working-tree bytes and recomputes Git's blob SHA-1 (`blob <length>\0<bytes>`) before it accepts the source-map integrity check.

## 5. Supported candidate categories versus semantic status

Source construct families observed across the inventory include:

- Schema and relation declarations: CREATE/ALTER TABLE, constraints, foreign keys, indexes, extensions.
- Database routines: SQL functions, PL/pgSQL functions, trigger functions, function replacement and grants.
- Triggers, views, row-level-security policies, grants/revokes and storage-object policies.
- Data mutation statements: INSERT, UPDATE, DELETE, conflict handling and data-repair/backfill-shaped statements.
- Procedural constructs: DO blocks, PL/pgSQL control flow, catalog preflight queries and dynamic `EXECUTE format(...)` patterns.
- Transaction controls, advisory-lock calls, catalog introspection and PostgREST schema notifications.

These are source-observation labels only. They identify work that a future PostgreSQL AST parser and resolver must model. The map does not classify any construct as semantically verified or unsupported by a real parser.

## 6. Explicit unresolved / unsupported report

| Construct class | C574 disposition | Why it remains unresolved |
|---|---|---|
| CREATE/ALTER/DROP object statements | Source observed; semantic identity UNKNOWN | No PostgreSQL AST or catalog-aware resolution |
| Schema-qualified relation/routine/type tokens | Lexical token only | No object-kind, scope, overload or search_path resolution |
| SQL/PLpgSQL routine bodies | UNKNOWN | No PL/pgSQL parser or control-flow analysis |
| DO blocks and dynamic SQL | UNKNOWN | Runtime-generated SQL and identifier interpolation are not resolved |
| Catalog preflight checks (`to_regclass`, `to_regprocedure`) | Candidate prerequisite text only | Guard existence does not prove dependency execution or migration history |
| Data mutations and backfill-shaped statements | UNKNOWN | Source inspection does not prove execution, row set, predicate outcome or row count |
| Extension calls | UNKNOWN | Exact installed extension version and object semantics are not bound |
| Advisory locks and concurrency-sensitive code | UNKNOWN | No transaction/concurrency semantics modeled |
| RLS, grants and policy changes | UNKNOWN | No role/ACL catalog snapshot or effective privilege resolution |
| Migration ordering | Filename inventory order only | No independently authenticated historical execution order |

No dependency graph edges are emitted. Explicit preflight calls and references remain source tokens until a parser and resolver establish what is read, required, created or consumed. In particular, the two Migration 007 files remain ambiguous for historical execution sequence; neither the shared version nor inventory ordering resolves which source body ran.

## 7. SQL NULL, literal backslash-N and quoted-empty distinctions

The map binds exact source bytes using the inventory's Git blob identity and byte length. No source normalization or string rewriting is performed.

The regression suite uses three distinct fixture lexemes:

- `NULL` — SQL NULL keyword.
- `'\\N'` — a quoted string containing a backslash and N.
- `''` — a quoted empty string.

The test ensures these remain three distinct tokens. This is a fixture-level preservation test, not a claim that C574 parsed every SQL expression or established the occurrence of each form in Production history. The map does not assert that a quoted backslash-N literal occurs in the 40 migration files.

## 8. Authorization and trust invariants

- `catalog_only_v1` is unchanged.
- The existing eleven catalog-only kinds are not expanded.
- No non-catalog lifecycle category is accepted.
- Unsigned evidence rejection in the existing analyzer is untouched.
- No signed absence declaration is treated as semantic proof.
- Source digests, lexical observations, comments, preflight guards and pinned prerequisites do not prove execution or semantic correctness.
- No trust roots are provisioned and no approval signatures are minted.
- No Production migration history, schema, role, grant, extension, or delivery setting is changed.

Every entry explicitly carries `UNKNOWN` for `dataTransformations`, `backfills`, `dependencies`, `preconditions`, and `postconditions`.

## 9. C572 findings preserved

### F-01 — incomplete semantic diagnostics on trust failures

**Still unresolved in the existing reconciliation analyzer.** C574 does not change its trust-failure reporting. The new source-map verifier checks only the independent source-observation artifact; it does not fix or claim complete 40 × 5 lifecycle diagnostics on trust failure. This remains a separate security regression and must be fixed with dedicated adversarial tests before analyzer acceptance.

### PR-triggered merge-context validation gap

The inspected PR validation workflow previously had `pull_request.branches: [main]`, which did not cover PRs targeting stacked feature branches such as PR #29's feature base.

C574 updates the filter to `main`, `feat/**`, `docs/**`, and `fix/**`, and adds the C574 verification and regression steps. The workflow's `actions/checkout@v7` step does not override `ref`; on a pull_request event GitHub's default PR merge ref is used. This change is implemented in the branch but still requires an actual PR-triggered run to prove event selection, merge-context checkout SHA, and job conclusions.

## 10. Executable verification

Commands wired into package scripts and PR validation:

```sh
npm run verify:c574-source-map
npm run test:c574-source-map
```

The verifier checks:
- 40 exact inventory paths and 39 unique version values.
- Current working-tree bytes match the pinned Git blob SHA-1 and byte length.
- Both Migration 007 paths and distinct blob identities survive.
- Migration 039 remains present.
- All five lifecycle domains remain UNKNOWN for every entry.
- Lexical qualified tokens remain unresolved.
- No unverified dependency edges or historical execution order are emitted.
- Catalog authorization remains `catalog_only_v1`.
- SQL NULL, quoted backslash-N and quoted-empty fixture tokens remain distinct.

**Execution status:** C574 did not have a local repository shell or Node runtime; no local tests were executed. GitHub Actions PR Validation run **46043872285** (run #2152) was observed for PR #30 at head `56d6ceeb19bc7fe70044c2f60a6f73b180eb5ce3`. At evidence capture, both `Verify C574 exact-source semantic mapping inventory` and `C574 source mapping and literal distinction regressions` completed **SUCCESS**. The existing migration reconciliation analyzer adversarial test and TypeScript check also completed **SUCCESS**. The full workflow was still IN_PROGRESS: Next.js production build was running, Cloudflare packaging and dependency audit were pending, and several database jobs remained in progress. These are exact-head partial CI results, not a full workflow PASS. The report-update commit itself requires a fresh exact-head PR run.

## 11. Commit and CI evidence

C574 branch: `feat/c574-source-semantic-mapping`, created from C573 commit `98cb712a890b8809ac309727264927e9b4d7cc36`.

Commits authored:
- `e777c290fcf2b0646ea92a54546bca33b5327751` — 40-entry mapping artifact.
- `00a576e37516c654396c21d5a74a62e0acba616b` — fail-closed source map verifier.
- `73816b123f3ba358ad9ba8669a94de9eaf9888e7` — initial regression tests.
- `0f82db1ae23e42d415c13eeae8010b74e2789d95` and `5c0961ded06539ab655ab8cde54bc374c31a584d` — literal fixture correction.
- `9ca27096c887cc111cbdb39550d4aefe3fe5f238` — package commands.
- `401469b759728fa38b162018740fb19bed2bd37d` — stacked PR trigger and test steps.
- `2f7b3ce86a808fbcec559a6a30ca71823123eb3d` — clarify backslash-N observation scope.

GitHub file retrieval confirmed the artifact contains 40 entries, 39 unique versions, 372 qualified reference tokens, nonempty source construct observations for all entries, and UNKNOWN status for all five lifecycle domains. The branch compare from C573 showed the mapping, verifier, tests and CI/package changes as branch additions/changes. Local execution was unavailable. Partial exact-head PR Actions evidence is available: run 46043872285 / #2152 for commit 56d6ceeb19bc7fe70044c2f60a6f73b180eb5ce3; the two C574 steps, analyzer adversarial suite, and TypeScript check passed, while the overall run remained in progress at evidence capture.

## 12. Remaining blockers and next actions

1. Obtain an exact current Production PostgreSQL major/version using authorized read-only evidence.
2. Select and pin a PostgreSQL-major-matched parser and canonical AST serializer.
3. Implement AST parsing for every migration source and explicit unsupported-node reporting.
4. Resolve qualified and unqualified references against a point-in-time catalog snapshot, including role, search_path, extensions and overloads.
5. Analyze PL/pgSQL control flow and dynamic SQL conservatively; unresolved branches stay UNKNOWN.
6. Establish dependencies from resolved AST and object identities; keep historical execution sequence UNKNOWN without independent execution evidence.
7. Implement a dedicated, separately provisioned semantic approval role only after independent trust-policy review.
8. Fix F-01 in the analyzer and test complete diagnostics on every trust-failure path.
9. Open a PR targeting an eligible base branch and capture exact PR merge-ref workflow evidence.
10. Run exact-head Node tests and the existing migration security regression suite in CI.

**Final status:** Source mapping artifact implemented and repository-committed. Provenance verifier and regression tests implemented but not executed. Semantic parsing/resolution remains NOT IMPLEMENTED. Production migration history and PR #29 remain untouched and unmerged. Production readiness is not claimed.
