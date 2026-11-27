# C556 — Category-specific migration effect contracts

## Scope and status

C556 separates source-declared SQL semantics from authenticated execution facts. The generic C555 effect tuple is retained only for catalog-representable schema/privilege/ownership/routine objects. Five domains now require typed contracts: data transformations, backfills, migration dependencies, preconditions and postconditions.

The 40-entry source-observation file is a conservative lexical inventory of pinned SQL source lines, not a PostgreSQL AST, approved migration mapping or execution record. It preserves exact inventory paths, Git blob SHA-1 values, line counts, source excerpts and explicit `unsupported` / `unknown` dispositions. It intentionally never asserts `none` from a missing regex match. A verifier checks every source excerpt against the pinned source file and refuses inventory drift.

## Category-specific contracts

All five contracts bind:
- `effect.sourcePath` to the exact inventory path and `blobSha1`.
- `contract.sourceRange` to an inclusive, in-bounds line interval.
- `contract.sourceStatementSha256` to SHA-256 of the normalized selected lines joined with LF.
- The effect's source range to a containing reviewed category coverage range.
- The effect's existing `fingerprint` to its separate live catalog representation. This catalog fingerprint is not the SQL source fingerprint.

### Data transformations

Required contract: operation (`INSERT_SELECT`, `UPDATE`, `DELETE`, `UPSERT`, `MERGE`), explicit source relation array, target relation, optional predicate and source statement binding. Predicate digest is recomputed from the exact predicate string. Relations are structured schema/relation pairs; flattened or ambiguous identities are rejected.

A lexical DML candidate is not automatically a transformation mapping. SQL statement boundaries, procedural bodies, dynamic SQL, CTEs and actual source/target relationships require PostgreSQL-aware parsing and review.

### Backfills

Required contract: target relation, predicate and digest, source range and source-statement digest, plus measurement. A measurement must be a non-negative integer row count with query digest, evidence digest, capture timestamp, execution ID and exact source blob SHA-1. The analyzer additionally requires a one-to-one matching record in `evidence.backfillMeasurements`; that array is included in the evidence digest and therefore bound by the collector/evidence approval chain.

A `not_measured` fixture can be structurally preserved by the adapter but is an analyzer acceptance blocker. SQL source alone cannot establish affected-row counts. No count is inferred or fabricated by C556.

### Migration dependencies

Required contract: dependency type (`foreign_key`, `view_source`, `routine_call`, `data_order`), structured from/to relation, prerequisite migration path and prerequisite blob SHA-1, source range and source-statement digest. The prerequisite must be a distinct member of the pinned inventory. A foreign-key reference does not itself identify the migration that created the referenced object; that association requires independent mapping review.

### Preconditions and postconditions

Required contract: predicate SQL and digest, explicit expected outcome (`true`, `false`, `zero_rows`, `nonzero_rows`), source range and digest, plus verification. Source-only `not_verified` evidence is structurally preserved by the adapter but is an analyzer acceptance blocker. Independently verified outcomes require evidence/query digests, capture timestamp, execution ID and the exact source blob. The analyzer requires matching records in `evidence.conditionVerifications`, also bound by the evidence digest.

## Acceptance boundary

The analyzer rejects malformed category contracts, source digest mismatches, missing or inconsistent measurements, invalid prerequisite source identity, missing condition outcomes, and evidence arrays that do not exactly match the approved mapping. An unsigned adapter candidate remains `UNSIGNED_NOT_ACCEPTED` / `NOT_ACCEPTED`.

A well-formed contract is not proof that SQL executed. A source observation is not a complete semantic mapping. A measurement record is not authenticated unless it is bound into the independently authenticated collector evidence package. The collector currently does not produce backfill measurement or condition verification projections, so the adapter emits empty arrays and cannot satisfy these categories for authenticated acceptance.

## C556 source observation coverage

`docs/c556-migration-source-observations.json` contains all 40 pinned source entries. The conservative scan found:

| Domain | Unsupported | Unknown |
|---|---:|---:|
| Transformations | 32 | 8 |
| Backfills | 32 | 8 |
| Dependencies | 15 | 25 |
| Preconditions | 39 | 1 |
| Postconditions | 39 | 1 |

These dispositions reflect lexical candidates and parser limitations, not an independently approved semantic mapping. The remaining work is a proper PostgreSQL-aware SQL parser/AST and source-specific reviewed mapping for every migration, with all unavailable execution semantics left unsupported/unknown.

## Historical execution and Migration 007

No authenticated historical execution timestamps, execution IDs, receipts, row counts or trust roots are created. The two distinct `202607260007` source files remain separately identified; a migration-history row for that version cannot identify which source body executed. Migration 039 and the complete 40-entry inventory remain pinned. Production migration history is unchanged.
