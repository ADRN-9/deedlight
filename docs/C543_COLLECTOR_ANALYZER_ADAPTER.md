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

## PR #23 versus PR #26 security contract

The actual PR #23 analyzer requires:
- `privilegeContractVersion: catalog_only_v1`.
- Exact `requiredAccessSummary`: `DATABASE_CONNECT`, `SYSTEM_CATALOG_SELECT`, `MIGRATION_HISTORY_SCHEMA_USAGE`, `MIGRATION_HISTORY_SELECT`.
- Database `CONNECT` only.
- `USAGE` only on `supabase_migrations`; no application-schema `USAGE`.
- `SELECT` only on `supabase_migrations.schema_migrations`; no application-data table or column `SELECT`.
- Explicit `scope` on every schema, object and column privilege row.
- Exact column-level privilege coverage, zero role memberships and zero owned application schemas.

PR #23 is independently divergent from PR #26. Its pinned migration inventory SHA-1 is `95d514a0bd97ff448c9507252eb1f5e69a507442`, whereas PR #26 pins `4e63f31368d446e905f4f44565be73337c7188fb`. PR #23 also currently normalizes literal `NULL` and literal `\\N` migration names to SQL NULL and rejects empty names; that is incompatible with the C544 CSV-preservation contract and requires a separately controlled analyzer correction.\n\nThe PR #26 analyzer at the refreshed C543 base is not equivalent. It requires a flattened `effectivePrivileges` set, uses scope-less schema privilege rows, and its object-privilege expectation permits `SELECT` for every table object. Those assumptions do not preserve PR #23's application-data denial boundary. Do not treat PR #26 analyzer acceptance as PR #23 security acceptance or silently weaken PR #23.

The adapter emits a separately labelled, unauthenticated `databaseAuthorityCandidate` with the PR #23 scoped privilege shape. Executable tests assert the exact summary, database CONNECT, migration-schema USAGE, migration-history table/column SELECT, and application-data table/column denial. This candidate is not a signed `collectorAuthority`.

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
