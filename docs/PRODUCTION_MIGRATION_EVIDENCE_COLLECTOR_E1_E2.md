# DeedLight Production migration evidence collector — E1/E2

**Scope:** architecture contract and a narrowly scoped, read-only collector runtime. This package does not provision Production credentials, connect to Production, sign receipts, write to immutable storage, reconcile migrations, or authorize any database mutation.

## Component boundaries

    Independent operator-approved endpoint profile
           | (external file + separately pinned SHA-256)
           v
    Collector CLI
      |-- repository/inventory/SQL digest verifier
      |-- endpoint/project profile verifier
      |-- libpq direct-login TLS client (verify-full)
      |-- fixed approved SQL bundle executor
      |-- CSV completeness + transaction rollback verifier
      |-- canonical result digest + unsigned receipt
           |
           +--> restricted local evidence directory (0600 files, 0700 directory)

    Future E3 signing service/KMS/HSM (not implemented)
           ^
           | unsigned receipt digest only
    Future E4 immutable evidence store (not implemented)
           ^
    Future independent verifier (separate trust boundary; not implemented)

The collector is not a signing authority, migration runner, SQL proxy, web endpoint, or general-purpose database client. It has no API for arbitrary SQL. Its only SQL input is the repository-pinned approved audit bundle.

## Threat model

| Threat | Control | Fail-closed result |
|---|---|---|
| Superuser impersonation / role switching | Direct login as deedlight_catalog_auditor; SQL preflight validates session_user, current_user, memberships and effective privileges | SQL execution fails |
| Wrong endpoint / project substitution | External endpoint profile SHA-256 pinned independently; exact project reference and expected Supabase hostname | Profile rejected |
| TLS interception / wrong certificate | libpq sslmode=verify-full and explicit external CA root | Connection fails |
| Inherited PGHOSTADDR, service, PGOPTIONS, password or SSL overrides | Child process receives a new allowlisted environment; no inherited PG* variables | Overrides have no effect |
| SQL bundle replacement | Exact Git blob SHA-1 and pinned SHA-256; inventory blob also pinned | Collection stops before connecting |
| Arbitrary SQL / migration attempt | Fixed path, fixed digest, no user-supplied SQL argument, no shell execution | No alternate SQL path |
| Partial output / truncated ACL projection | CSV parser, final transaction marker, mandatory database_acl_v1 projection, count equality, bounded output | Evidence rejected and buffers cleared |
| Interrupted execution | Process timeout, psql ON_ERROR_STOP, explicit post-bundle transaction-state check | No receipt emitted |
| Application-data exposure | Existing SQL allowlist and direct-login role restrictions; no application-row queries | Database permission denial or collection failure |
| Receipt/evidence substitution | SHA-256 of raw evidence and canonical parsed records bound into receipt | Evidence verification fails |
| Credential or evidence leakage | Passfile path only; no password argument/env; stderr suppressed; generic error codes; private output files | No secret-bearing diagnostics |

### Trust assumptions

- The endpoint profile file and DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256 arrive through independently controlled operator configuration. A profile and its digest supplied by the same untrusted source are not independent.
- The CA file is external to the repository. Its SHA-256 is independently pinned with DEEDLIGHT_COLLECTOR_TLS_CA_SHA256, separately from the endpoint-profile digest. The collector opens the CA with O_NOFOLLOW, verifies ownership and private parent-directory/file permissions, holds the descriptor throughout collection, and rechecks path inode and descriptor digest before receipt creation. Replacement and in-place tampering fail closed. TLS uses libpq hostname verification (verify-full); a SQL GUC is never accepted as endpoint proof.
- The production profile is fixed to project xaipiovflxomcbfwtwmu, host db.xaipiovflxomcbfwtwmu.supabase.co, database postgres, port 5432 and login deedlight_catalog_auditor. The disposable CI database name is accepted only when GitHub CI and the explicit fixture authorization are both present; it is not a Production mode.
- The passfile must be a regular, non-symlink file with no group/other permission bits (normally mode 0600). The collector never reads or prints its contents.
- A successful collection is not an accepted migration classification. E2 emits an explicitly unsigned receipt; E3 signing, E4 immutable storage and independent verification remain mandatory.

## Receipt schema v1

Schema: schemas/production-migration-collection-receipt-v1.schema.json.

The verifier checks every required field and nested object against the complete v1 receipt schema and rejects unexpected fields. The receipt binds project and endpoint identity, explicit successful TLS chain and hostname verification, TLS mode and independently pinned CA digest, exact repository commit, migration inventory blob, exact SQL bundle SHA-256, authenticated login, read-only/repeatable-read transaction and rollback verification, timestamps, result record count, full database_acl_v1 row count, canonical result digest, and raw evidence file digest.

Receipt state is always UNSIGNED_NOT_ACCEPTED. signing.keyId and signing.signature are null. The collector does not claim a trusted signature, durable retention, or acceptance.

## Canonical serialization and digest

1. psql emits RFC 4180 CSV with headers for every result set. The approved SQL orders each projection explicitly.
2. Decode UTF-8 without normalizing quoted content. Parse RFC4180 quoting and escaped quotes; preserve embedded CR/LF and empty leading, middle and trailing fields. Reject bare CR outside quoted fields, NUL, malformed quotes, invalid characters after a closing quote, unterminated quotes, empty output and malformed/incomplete mandatory projections.
3. Canonical JSON serializes arrays in original order, objects with lexicographically sorted keys, and strings using JSON escaping. No locale-sensitive sorting or numeric coercion is performed on SQL cells.
4. canonicalResultSha256 = SHA256(UTF8(canonicalJson(resultRecords))), excluding only the final collector transaction-close marker header/value.
5. evidenceFileSha256 = SHA256(raw UTF-8 CSV bytes). Both digests are placed in the receipt. The receipt file itself can be hashed by the later signing/storage stage.
6. The mandatory database_acl_v1 header must equal the exact eleven-column SQL projection in order; missing, duplicate, reordered or unexpected columns fail closed. Every row has exact width and validated field representations. Database, owner and grantor OIDs are positive PostgreSQL uint32 values; grantee OID zero maps exactly to PUBLIC. ACL duplicate identity is (grantee OID, grantor OID, privilege type), independent of grantability.
7. A final same-session query must prove the read-only transaction has ended (transaction_read_only = off) and no transaction ID was assigned. The SQL bundle's explicit ROLLBACK is mandatory. Missing marker or false result invalidates collection.

## Failure-state contract

| Condition | Result |
|---|---|
| Invalid profile, profile digest or project/host mismatch | ENDPOINT_IDENTITY_MISMATCH / profile-specific error |
| Wrong CA, hostname, or TLS peer | SQL_EXECUTION_FAILED; no receipt |
| SQL/inventory digest mismatch | SQL_BUNDLE_*_MISMATCH / MIGRATION_INVENTORY_PIN_MISMATCH |
| Missing credential file or unsafe permissions | PASSWORD_FILE_INVALID |
| Login/role/privilege preflight fails | SQL_EXECUTION_FAILED |
| psql timeout, disconnect, interruption or nonzero exit | COLLECTION_TIMEOUT or SQL_EXECUTION_FAILED |
| Missing/invalid CSV or ACL projection | Specific SQL_RESULT_* / DATABASE_ACL_* error |
| Rollback marker missing/false | TRANSACTION_* error |
| Output directory already exists or is inside repository | OUTPUT_DIRECTORY_ALREADY_EXISTS / EVIDENCE_OUTPUT_MUST_BE_EXTERNAL |
| Evidence/receipt digest mismatch during verification | EVIDENCE_DIGEST_MISMATCH / RECEIPT_RESULT_BINDING_MISMATCH |

Failure output contains only a stable error code. No psql stderr, connection URI, password, SQL result or raw catalog evidence is printed. Partial buffers are cleared. No receipt is emitted for an unsuccessful collection.

## Operator profile

The external JSON profile has exactly these fields:

    {
      "schemaVersion": 1,
      "projectRef": "xaipiovflxomcbfwtwmu",
      "host": "db.xaipiovflxomcbfwtwmu.supabase.co",
      "port": 5432,
      "database": "postgres",
      "username": "deedlight_catalog_auditor",
      "tlsRootCertPath": "/secure/config/supabase-ca.crt",
      "passwordFilePath": "/secure/config/.pgpass"
    }

The profile file itself must be outside the repository and mode 0600. Set DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256 to its independently provisioned SHA-256 and DEEDLIGHT_COLLECTOR_TLS_CA_SHA256 to the separately provisioned SHA-256 of the exact CA certificate file. Never derive either pin from an untrusted profile during collection. The passfile must be external, regular, non-symlink and mode 0600. The CA file must be external. The output directory must not exist and must be outside the repository.

Example invocation (no credential material in arguments):

    DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256=<independently-pinned-sha256> \
      node scripts/collect-production-migration-evidence.mjs \
      --profile /secure/config/collector-endpoint.json \
      --output /secure/evidence/run-<unique-id>

Do not run this against Production until the Production owner, DBA, security owner and key custodian separately approve the operation. This implementation is a code artifact, not authorization to collect.

## Validation

- node --test scripts/test-production-evidence-collector.mjs: deterministic unit/adversarial tests.
- bash scripts/test-production-evidence-collector-postgres16.sh: disposable PostgreSQL 16, local CA/server certificates, direct-login and hostile-environment integration. This harness must never receive Production credentials or endpoints.
- CI invokes both test suites in a separate PostgreSQL 16 job. No Production secrets are available to that job.

## Explicitly out of scope (E3–E5)

No KMS/HSM signing, real key provisioning/rotation, immutable storage, retention policy, Production deployment, Production collection, or independent signed-receipt verifier is implemented here.
