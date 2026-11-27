# C543 — Collector-to-analyzer adapter contract

## Purpose

`scripts/adapt-production-migration-evidence.mjs` converts the 19 validated CSV projections emitted by `collect-production-migration-evidence.mjs` into an analyzer schema-version-2 **candidate**. It does not authenticate or accept evidence.

## Invocation

```sh
node scripts/adapt-production-migration-evidence.mjs \
  --receipt receipt.json \
  --csv evidence.csv \
  [--mapping independently-reviewed-mapping.json] \
  --output candidate.json
```

The inventory and receipt schema are loaded from their pinned repository paths. The output file is created exclusively with mode 0600; an existing output path is not overwritten.

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

These digests are not interchangeable. The adapter verifies the actual inventory and schema bytes and checks receipt claims against independent pins.

## Normalization

- The exact 19 projection identities, headers and order are required.
- Collector CSV parsing validates projection cardinality, row widths, transaction closure, rollback, history rows and database ACL rows.
- Adapter validation checks typed row structure for relation, routine, ACL, role, membership, policy, constraint, index, trigger, sequence and extension projections.
- Migration history is ordered by version. Empty CSV cells become SQL NULL; literal `NULL` and literal `\\N` remain strings. Statement counts accept only canonical nonnegative integers or SQL NULL.
- Migration-history structure is checked by column identity and type, not physical column order.
- The analyzer capture timestamp is the collector receipt completion time; the database query timestamp is preserved separately as `databaseCaptureTimestamp` because the database host and collector runner clocks must not be assumed synchronized. The migration mapping is optional for candidate generation. If supplied, it must cover the exact 40-entry pinned inventory, without duplicate paths or malformed effects/coverage.
- Catalog objects use SHA-256 over canonical JSON of their normalized source rows.

## Explicit incompleteness

The collector does not provide evidence for data transformations, backfills, dependencies, preconditions or postconditions. Accordingly, the candidate sets `catalog.complete=false` and only lists the 11 directly projected catalog dimensions. It does not fabricate the missing five dimensions.

The analyzer also requires authenticated `collectorAuthority`, distinct signed evidence/mapping/collector approvals, and independently provisioned trust roots. The adapter intentionally emits none of these. Its output always states `UNSIGNED_NOT_ACCEPTED` and `NOT_ACCEPTED`.

## Privilege evidence

The complete `catalog_only_v1`-related raw role, role-membership, ACL and database-ACL projections are preserved under `databaseAuthorityCandidate`. This is explicitly unauthenticated candidate data, not an analyzer `collectorAuthority` assertion.

## PostgreSQL 16 integration

The existing disposable PostgreSQL 16 collector integration invokes this adapter against the actual collector output and asserts that the result remains unsigned and incomplete. No Production credentials, signing keys, migrations, Cron settings or delivery settings are used.
