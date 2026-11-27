# C544 — Collector provenance, nullability and privilege compatibility

## Provenance bindings

- SQL `identity_v1.database_name` must equal receipt `endpoint.database`.
- SQL `identity_v1.repository_sha` must equal receipt `source.repositoryCommitSha`.
- SQL project identity, receipt project identity and the pinned DeedLight project reference must match.
- The collector's explicitly authorized disposable PostgreSQL database is classified as `test`; it is never labelled `production`. The approved Production database `postgres` is labelled `production`.
- Database capture time is retained separately from collector receipt completion time.

These are consistency checks, not authentication or proof of execution authority.

## CSV nullability

Migration-history SQL encodes SQL NULL names as `__DEEDLIGHT_SQL_NULL_V1__`; the SQL preflight rejects a real migration name equal to that reserved marker. Literal `NULL`, literal `\\N`, and an empty string remain distinct values. The collector parser also retains a reserved internal sentinel for quoted-empty CSV cells during canonical result validation, then restores actual empty strings in candidate normalization.

The PostgreSQL 16 fixture exercises the distinct migration-name values through the real collector and adapter.

## Projection validation

All 19 projection identities, exact headers, fixed order, cardinality and row widths are validated. Only the explicit `EMPTY_PROJECTION_ALLOWLIST` may have zero rows. Whole-block reordering, missing/duplicate/unexpected projections and malformed row structures fail closed.

The collector role must exist exactly once in `roles_v1`, satisfy the least-privilege role flags, and have no role memberships. ACL rows are checked against PostgreSQL privilege sets, duplicate identities and grant options are rejected, and schema/object/column privilege scopes are checked.

The `extensions_v1` projection is retained and validated, but the current analyzer catalog schema has no `extensions` kind. It is exposed as `PRESERVED_NOT_NORMALIZED`; catalog completeness remains false.

## C545 — PR #23 catalog-only security contract compatibility

PR #26's reconciliation analyzer now enforces the same strict privilege contract used by PR #23. This is a compatibility correction to the analyzer, not a relaxation of the security policy.

The executable `validateCollectorPrivilegeEvidence` contract requires:

- `privilegeContractVersion: catalog_only_v1`.
- Exact `requiredAccessSummary`: `DATABASE_CONNECT`, `SYSTEM_CATALOG_SELECT`, `MIGRATION_HISTORY_SCHEMA_USAGE`, `MIGRATION_HISTORY_SELECT`.
- Database privileges exactly `["CONNECT"]` and catalog privileges exactly `["SELECT"]`.
- An exact schema identity set from the catalog inventory. Only `supabase_migrations` may have `scope: migration_history` and `["USAGE"]`; every application-data schema must have an empty privilege list.
- An exact table/sequence/routine identity set. Only `supabase_migrations.schema_migrations` may have `scope: migration_history` and `["SELECT"]`; every application-data object must have an empty privilege list, and routines cannot receive execution privileges.
- An exact column identity set, with one privilege row per inventoried column. Schema, relation and column names remain separate structured fields from the catalog projection; migration-history scope is assigned only when `schema === "supabase_migrations"` and `relation === "schema_migrations"`. Dotted/quoted identifier text is never parsed to infer scope. Only those exact relation columns may carry `["SELECT"]`; all application-data columns must have an empty privilege list.
- Migration-history rows are independently checked by the analyzer for strictly ascending 12-digit versions. Reordered, duplicate, malformed and non-monotonic rows fail closed; adapter ordering is not treated as proof.

## C547 — F-06 dotted-identifier and F-07 history-order corrections

F-06: the collector's `relations_v1` projection already returns `schema_name`, `relation_name` and `column_name` as separate database fields. The adapter now carries those fields separately into every column catalog object and column-privilege row. The analyzer validates exact structured tuple coverage and derives migration-history scope only from the exact pair `schema === "supabase_migrations"` and `relation === "schema_migrations"`. It never parses or prefix-matches the dotted display identity to decide privilege scope. A dotted/quoted schema or relation that serializes with a `supabase_migrations.schema_migrations.` prefix remains application data and cannot receive SELECT.

F-07: `validateMigrationHistoryRows` now enforces strict ascending order while independently rejecting duplicate versions, malformed/unrecognized versions and non-monotonic rows. This is analyzer-side validation over normalized rows; a sorted adapter result is not an authorization substitute.

Adversarial tests cover dotted schema and relation names whose flattened identifiers imitate the migration-history prefix, unauthorized SELECT on those columns, malformed structured evidence, row swaps and non-monotonic history order. The exact catalog-only privilege contract and unsigned candidate boundary remain unchanged.
- Explicit scope on every schema, object and column privilege row. Missing, duplicated, unexpected, malformed, incomplete or broadened evidence is rejected. The legacy flattened `effectivePrivileges` representation is explicitly rejected.

The adapter's `databaseAuthorityCandidate` now has this same scoped representation. The adapter test passes that candidate and its catalog inventory directly to the analyzer's exported validator. Separate signed-fixture tests exercise the analyzer's trust path and adversarially broaden database, schema, table and column privileges, alter the required-access summary or contract version, remove or duplicate column rows, and reintroduce the legacy flattened privilege field. These checks fail closed.

### Inventory boundary — deliberately not copied from PR #23

PR #23's source inventory is 39 entries with Git blob SHA-1 `95d514a0bd97ff448c9507252eb1f5e69a507442`. PR #26 retains its existing 40-entry inventory with Git blob SHA-1 `4e63f31368d446e905f4f44565be73337c7188fb`. The latter retains both distinct Migration 007 source files, includes Migration 039 (`202611260039_delivery_kind_scoped_claims.sql`), and preserves nondecreasing version ordering. Do not replace the PR #26 inventory with PR #23's older 39-entry manifest merely to align analyzer logic.

### Authentication boundary

The adapter emits `databaseAuthorityCandidate` as an unsigned, unauthenticated candidate. It does not emit `collectorAuthority`, signed query-execution provenance, or authenticated analyzer acceptance. A successful structural privilege-contract validation is not a signature, not an authorization decision, and not Production evidence acceptance. Independent evidence, migration-mapping and collector approvals with provisioned trust roots remain prerequisites.

### Remaining limitations

Data transformations, backfills, dependencies, preconditions and postconditions are not projected by the collector. Extensions remain preserved but unmapped because the analyzer catalog schema has no `extensions` kind. The candidate remains `UNSIGNED_NOT_ACCEPTED` / `NOT_ACCEPTED`; no evidence is signed and no Production reconciliation is authorized.
## Fingerprint boundaries

| Input | Contract |
|---|---|
| Migration inventory | Git blob SHA-1 |
| SQL bundle | Git blob SHA-1 and raw-file SHA-256 |
| Receipt schema | Independently pinned Git blob SHA-1 and raw-file SHA-256 |
| Receipt | Canonical JSON SHA-256 |
| CSV evidence | Raw-byte SHA-256 |
| Collector result | Collector-defined canonical result SHA-256 |
| Normalized analyzer candidate | Canonical JSON SHA-256 |

These digests are not interchangeable.

## Remaining incompleteness and trust

Data transformations, backfills, dependencies, preconditions and postconditions are not projected. Extensions remain unmapped. A reviewed 40-entry migration mapping and independent evidence, mapping and collector approvals with provisioned trust roots remain prerequisites. The candidate always remains `UNSIGNED_NOT_ACCEPTED` / `NOT_ACCEPTED`.

## Invocation

```sh
node scripts/adapt-production-migration-evidence.mjs \
  --receipt receipt.json \
  --csv evidence.csv \
  [--mapping independently-reviewed-mapping.json] \
  --output candidate.json
```

The output file is created exclusively with mode 0600; an existing output path is not overwritten.


## C555 — deterministic migration-effect coverage

Each of the nine effect domains is mandatory for every inventory entry: schema, privileges, ownership, routines, data transformations, backfills, dependencies, preconditions and postconditions. Each domain has exactly one explicit disposition:

- `effects`: one or more typed effects are required.
- `none`: an affirmative reviewed finding that the pinned source range contains no effect in that domain.
- `unsupported`: the source structure cannot currently be normalized safely. This is an explicit acceptance blocker.
- `unknown`: the source semantics or evidence cannot be determined. This is an explicit acceptance blocker.

The mapping must bind the exact inventory path and Git blob SHA-1. Each category has a non-empty rationale and one or more ordered, non-overlapping, in-bounds source line ranges. Effect records have strict category-specific kinds, unique kind/identity pairs across the entire migration, non-empty descriptions and SHA-256 fingerprints. Effects cannot be attached to `none`, `unsupported` or `unknown`; an `effects` disposition cannot be empty. The analyzer checks ranges against the actual pinned source file line count. A mapping with no deterministic effects, an unsupported/unknown category, malformed source ranges or malformed effects cannot pass analyzer trust validation.

These are deterministic structural and catalog-consistency checks, not proof that a historical SQL statement executed. The effect fingerprint is compared with the current catalog object fingerprint during classification; this comparison establishes representation only, not source execution, actor, timestamp or execution identity.

## C555 — analyzer acceptance-path integration gap and safe resolution

The adapter deliberately emits only an unsigned candidate. Its `evidence` object does not contain `collectorAuthority`; its `databaseAuthorityCandidate` is an unauthenticated catalog-only privilege summary. The analyzer's acceptance path requires a separate `collectorAuthority` object whose execution receipt binds project, exact query-bundle fingerprint, collector identity, capture time, execution ID, statement count, start/completion timestamps, result digest and the exact database-authority projection. It also requires three distinct Ed25519 signatures (evidence approver, mapping approver and collector), independently provisioned trust roots, and signatures over the exact evidence/mapping digests.

Therefore calling `validateCollectorPrivilegeEvidence` successfully is only a structural privilege-contract check. It does not exercise or satisfy authenticated analyzer acceptance. The current adapter-to-analyzer test must assert this rejection explicitly.

A safe future integration must be a separate, narrow composition step: accept the adapter candidate plus independently generated and authenticated collector execution receipt, independently reviewed mapping, and the three signed approvals; verify that the collector receipt binds the exact receipt/CSV/query/result/candidate digests; then compose the analyzer evidence envelope without changing any candidate field. The adapter must never mint execution IDs, timestamps, collectorAuthority, approvals, signatures or trust roots. Until that contract and an independently authenticated execution source exist, the only safe result is `UNSIGNED_NOT_ACCEPTED` / `NOT_ACCEPTED`.

There is a second acceptance limitation: current classifications deliberately return `Schema represented but history ambiguous`, `Partial or drifted` or `Unknown`; they never infer historical execution or verified non-execution from present catalog state and the version/name/statement-count migration-history table. Consequently a fully trusted envelope alone cannot make the present Production reconciliation acceptable. Before an acceptance-capable release, an authoritative, independently authenticated historical execution source and a fail-closed policy for ambiguous duplicate version `202607260007` must be specified and tested. Do not populate timestamps or execution identifiers from current catalog state, adapter capture time or operator recollection.

## C555 — PR #23 / #24 conflict-aware integration plan

The live changed-file lists overlap in five paths: `.github/workflows/pr-validation.yml`, `docs/PRODUCTION_MIGRATION_EVIDENCE_RUNBOOK.md`, `docs/PRODUCTION_MIGRATION_RECONCILIATION_LEDGER.md`, `scripts/reconcile-migration-evidence.mjs` and `scripts/test-reconcile-migration-evidence.mjs`.

1. Keep PR #26 based on PR #24 until a reviewed integration branch is prepared; do not overwrite either divergent head or manufacture merge ancestry.
2. Reconcile PR #23's catalog-only authorization and migration-history nullability/ordering corrections into the integration base with focused file-level merges. Preserve PR #24's collector E1/E2, receipt schema, TLS and exact output contract.
3. Preserve PR #26's structured column identity checks, strict ascending history order, catalog-only privilege validator, 40-entry inventory, both distinct Migration 007 sources and Migration 039.
4. Resolve workflow changes by combining required jobs and triggers rather than selecting one complete workflow version. Retain push validation for feature branches and the correct pull-request base filters.
5. Merge the reconciliation ledger/runbook sections semantically; preserve the 40-entry source inventory and do not import PR #23's older 39-entry inventory.
6. Run focused migration inventory, analyzer, adapter and PostgreSQL 16 integration suites on the final integration SHA; then require fresh exact-head CI and independent review before any merge decision.

No PR base, history, migration SQL or Production migration state is changed by this plan.
