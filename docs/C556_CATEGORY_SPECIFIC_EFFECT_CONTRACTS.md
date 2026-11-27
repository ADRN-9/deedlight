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

## C558 remediation notes

### Catalog boundary

The live PostgreSQL catalog is exactly the 11 collector-supported kinds: schemas, tables, sequences, columns, constraints, indexes, triggers, policies, routines, privileges and ownership. Transformations, backfills, migration dependencies, preconditions and postconditions are not PostgreSQL catalog object kinds. They remain separate mapping/evidence domains and are never flattened into catalog object identities or fingerprints. Analyzer classification compares only catalog effects to live catalog rows; unresolved lifecycle evidence is counted separately and keeps final acceptance blocked.

### Condition outcome evidence

A verified precondition/postcondition now carries an explicit `observedOutcome`, the exact predicate SHA-256, the pinned migration blob SHA-1, query/result digests, execution ID and canonical UTC capture timestamp. The observed outcome must be one of the supported unambiguous values and must equal the declared expected outcome. The signed evidence envelope must contain exactly one matching condition record; missing, duplicate, extra, malformed or contradictory records fail closed. A structurally valid source mapping or adapter candidate is still not authenticated: the evidence approval and collector attestation must independently sign the complete evidence payload.

### Why source-observation generation is not promoted to a semantic generator

The C556 observations are deliberately lexical candidates. A safe semantic generator cannot be built from line-oriented regular expressions because PostgreSQL SQL includes nested dollar-quoted function bodies, procedural control flow, dynamic SQL, CTEs, quoted identifiers, overloaded routines, trigger context, search-path resolution and statements spanning multiple lines. Regex-derived target names or predicates can be syntactically plausible yet semantically wrong. C558 therefore validates every stored excerpt against exact source blob identity and source line, and tightens transformation contracts to require a non-empty source relation set, a recognized operation that matches the pinned SQL range, and source/target relations present in that range. It does not automatically convert lexical candidates into approved mappings. A PostgreSQL-aware parser plus human semantic review is required before such a generator can safely emit complete transformation/dependency/backfill/lifecycle mappings.

## C568 test-remediation handover

- The category-confusion regression now constructs a valid, source-bound UPDATE transformation in the pinned Migration 004 source, verifies the adapter accepts that valid fixture, then changes only its category kind to `backfills` and asserts `MIGRATION_MAPPING_EFFECT_INVALID`. The adversarial input reaches the adapter.
- The transformation negative suite again includes the injection-style relation identifier `bad-name;drop`; it must be rejected by the existing strict SQL identifier contract. Identifier validation was not weakened.
- Database capture timestamps are checked at two distinct boundaries. The collector accepts only the SQL projection's canonical UTC millisecond lexical form (`YYYY-MM-DDTHH:mm:ss.SSSZ`), rejecting offsets, missing fractions and non-millisecond precision with `SQL_IDENTITY_PROJECTION_INVALID`. The adapter's calendar-semantic tests separately reject impossible dates and year zero with `COLLECTOR_CAPTURE_TIMESTAMP_INVALID`.
- Receipt timestamps retain their separate RFC3339 contract, including valid offsets and arbitrary fractional precision; the collector's stricter database-projection rule does not change receipt timestamp parsing or ordering.
- Analyzer negative cases continue to require `NOT_ACCEPTED`, all 40 structured lifecycle classifications and all required lifecycle arrays. Existing catalog-only authorization, `UNSIGNED_NOT_ACCEPTED`, SQL NULL distinctions, strict migration ordering and the 40-entry migration inventory (both Migration 007 sources and Migration 039) remain in scope.
- Repository-only implementation commits for C568 are recorded on PR #29. No Production database mutation, migration-history reconciliation, trust-root provisioning, evidence signing or PR merge was performed.
- Execution status at handover: no local repository checkout/shell is available in this session. GitHub's commit-workflow-run lookup and combined commit-status lookup returned no run/status for the latest checked head. Analyzer, adapter, collector, PostgreSQL 16 and offline evidence tests therefore remain **NOT EXECUTED / NOT VERIFIED**, not PASS. A fresh successful exact-head Actions run and per-job conclusions remain mandatory.
- Rollback: revert the C568 commits on `fix/c558-pr28-security-remediation`; no database rollback is needed.

## C570 — PostgreSQL semantic-verification acceptance boundary

### What the current implementation proves

- The inventory pins the exact 40 migration source files and their Git blob identities. Source-range SHA-256 values prove that a reviewed excerpt has not changed relative to those bytes.
- The adapter validates the shape of category-specific declarations. Its transformation operation/relation checks are lexical consistency checks only; they are not a PostgreSQL parser, AST, name resolver or proof of statement semantics.
- A dependency contract can prove that a prerequisite path and blob belong to the pinned inventory. That does not prove that the SQL creates or consumes the declared relation edge, nor that the prerequisite is the migration that semantically establishes it.
- A backfill measurement record can be checked for structure and consistency with the signed evidence payload. A row count, query digest, result digest and execution ID without independently verifiable query/result evidence do not establish that the stated PostgreSQL operation ran or produced that count.
- The live catalog collector remains restricted to the eleven catalog kinds. It does not attest transformations, backfills, dependencies, preconditions or postconditions.

### Fail-closed acceptance behavior

The analyzer now treats all five non-catalog domains as requiring independent semantic verification, even when a mapping marks a domain `none`. A signed `none` disposition is still a mapping assertion; it cannot prove the absence of an effect. The report exposes `semanticVerification.status = UNKNOWN`, the required categories, per-migration `semanticVerificationRequiredCategories`, and explicit blockers. These blockers contribute to `unresolvedLifecycleEvidence` and prevent final `ACCEPTED` status.

The current trust-root roles and evidence pipeline do not provide a separately verifiable PostgreSQL semantic-analysis approval, AST artifact, or independently inspectable backfill/condition execution result. Therefore no transformation, backfill, dependency, precondition or postcondition declaration can currently clear this acceptance boundary. Matching source digests, regex/lexical checks, signed mapping assertions, pinned prerequisite identities, or self-consistent digest fields are not substitutes.

### What remains UNKNOWN

- Complete PostgreSQL parse trees and semantic resolution for all 40 migration files.
- Dynamic SQL and PL/pgSQL control-flow effects, including statements constructed at runtime.
- Independently reviewed source/target transformation meaning and actual dependency edges.
- Whether a declared backfill ran, its exact predicate and affected-row count, and the independently verified result set.
- Whether preconditions/postconditions were executed against the intended database snapshot and returned the declared outcome.
- Semantic proof that a non-catalog domain has no effect when a mapping says `none`.

A future acceptance path needs a PostgreSQL-aware parser and reviewed semantic mapping, plus a separately authorized semantic approval bound to exact source blobs and parser output. Backfills and condition outcomes additionally need a narrow read-only execution collector that retains verifiable query/result artifacts, binds the exact project, source, query, execution and capture, and is independently attested. These capabilities are not claimed to exist in C570. No regex-based AST substitute is introduced.

The catalog-only authorization boundary and eleven catalog kinds are unchanged. Production database state and migration history are unchanged. Production acceptance remains **NO-GO**.

### C570 implementation record

- Analyzer hardening commit: `5748e38c4f32999ae9e73ae908a0c86611a73eb6`.
- Adversarial analyzer tests: `83e839e470fb1f1803051dcb63fc92832e2b68a2`, with fixture correction `1467f515df2a82986a04b061a88677eb1f7e5e6d`.
- This handover update: `9276a9b6f9ce3aaddcf7396b039ef84124d16e9c`; semantic status remains UNKNOWN on trust failures: `4b13c73e1cc532cded988c354b8fc8608aacb44a`.
- Latest inspected branch head before this documentation update: `4b13c73e1cc532cded988c354b8fc8608aacb44a`; PR #29 remains open and unmerged.
- Test execution was unavailable because this session has no local repository shell. No analyzer, adapter, collector, PostgreSQL integration, offline evidence, lint, TypeScript, Next build or Cloudflare package test is represented as passing.
- Exact-head GitHub commit-workflow-run and combined-status lookups returned empty results for that code head. Workflow run ID and per-job conclusions are unavailable.
- No Production database mutation, migration-history reconciliation, trust-root provisioning, evidence signing or PR merge was performed.
