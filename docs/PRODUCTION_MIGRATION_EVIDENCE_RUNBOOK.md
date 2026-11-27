# DeedLight Production migration evidence collection runbook

**Read-only evidence preparation only.** No Production query has been run by this change. Do not use this runbook as authorization to connect to or mutate Production.

## Preconditions and separation of duties

- DBA/security owner authorizes a read-only audit window and identifies the exact Production project/endpoint through an independently trusted channel.
- Collector runs from a controlled, isolated host. Verify TLS certificate/hostname and expected Supabase project reference independently; the SQL-supplied project label is metadata, not endpoint authentication.
- Authenticate directly as the dedicated login role `deedlight_catalog_auditor`; do not connect as `postgres`, a superuser, or another login and then use `SET SESSION AUTHORIZATION` to impersonate the collector. The audit requires `session_user = deedlight_catalog_auditor` and validates the authenticated principal independently from the effective `current_user`. The effective role may differ only in a legitimate `SECURITY DEFINER` execution context; `SET ROLE` is rejected. Both authenticated and effective roles must be non-privileged and have no direct or inherited memberships. This intentionally avoids a brittle `session_user = current_user` check.
- The custom GUC `deedlight.authenticated_principal` must equal the actual `session_user`; it is an untrusted consistency label, not authentication. A spoofed or missing label fails closed. PostgreSQL cannot reveal whether a superuser previously used `SET SESSION AUTHORIZATION` to impersonate another role, so the collector must authenticate directly through the independently verified TLS endpoint as the dedicated non-superuser login. Never run this bundle through a superuser session.
- The approved role has no superuser, role/database creation, replication or BYPASSRLS attributes; no membership, direct or inherited, in any other role (including every predefined `pg_*` role, especially `pg_read_all_data` and `pg_write_all_data`, and `service_role`); no database CREATE, application-schema CREATE, application table/view/foreign-table privileges (including column ACLs), application sequence USAGE/SELECT/UPDATE, or ownership of application schemas and relations (ordinary/partitioned tables, views, materialized views, foreign tables and sequences). Routine ownership is inventoried but is not an authorization rejection criterion; standalone type ownership is not inventoried or enforced.
- Grant SELECT only on the explicitly enumerated PostgreSQL catalogs/views required by the audit (including `pg_catalog.pg_database`) and SELECT on `supabase_migrations.schema_migrations`. The collector must not own the history table or have table/column write privileges on it. The SQL enforces these effective privileges before collection; a failed check is a hard stop, not a prompt to use a stronger role.
- Do not grant application table or sequence access to make catalog queries work. Catalog metadata is read through `pg_catalog`; the audit never needs to read application rows. The SQL transaction is a second control, not a substitute for the role contract.
- Credentials must come from an approved secret manager or an external `PGSERVICEFILE`/`PGPASSFILE` with restrictive filesystem permissions. Never put credentials, connection URIs, tokens or passwords in repository files, command arguments, shell history, CI logs or evidence artifacts.
- Record the exact repository SHA checked out at collection time and inventory blob SHA `a18cf2c65eb595ecd143fbaa16e2d81badf8d1f8` in the collector receipt. Never copy a historical commit SHA from this runbook; a controlled runner must verify the checked-out commit and migration inventory before collection.
- Provide non-secret connection metadata through PostgreSQL custom settings:
  - `deedlight.expected_project_ref=xaipiovflxomcbfwtwmu`
  - `deedlight.repository_sha=<exact 40-character commit SHA>`
  - `deedlight.authenticated_principal=deedlight_catalog_auditor`
  The authenticated-principal GUC is compared with `session_user` but is not itself an authentication factor. These labels are not proof of endpoint identity. The collector must bind the actual TLS peer/host, provider project identity, authenticated and effective role identities, repository SHA, SQL bundle digest, query output digest and UTC capture timestamp into a signed receipt.

## Approved collector privilege matrix (C460)

The collector contract is intentionally narrower than a generic read-only role. The following matrix is normative; missing, inherited, defaulted or implicit privileges are evaluated as effective PostgreSQL privileges and cause collection to stop when they violate the policy.

| Area | Approved policy | Enforcement |
|---|---|---|
| Application routine EXECUTE | Deny PUBLIC, direct and inherited execution for every application function, procedure, aggregate, window function and overload | Enumerate pg_proc by OID; expand proacl using acldefault('f', proowner) when NULL; check has_function_privilege for authenticated and effective roles |
| Future PUBLIC routine EXECUTE defaults | Deny globally and per schema | Inspect pg_default_acl routine entries (defaclobjtype = 'f') and reject PUBLIC EXECUTE or collector-targeted grants/grant options |
| SECURITY DEFINER execution | No routine exceptions without explicit approval | Effective-role and OID-based EXECUTE checks apply equally; any reachable application routine is rejected |
| Database CONNECT | Allow and require for both authenticated and effective roles | has_database_privilege(..., 'CONNECT') |
| Database CREATE | Deny | Effective privilege check |
| Database TEMP | Deny, including PUBLIC/default ACL exposure | Effective privilege check; a NULL datacl is expanded with acldefault('d', datdba) |
| Database ownership | Deny | Reject pg_database.datdba matching either collector role |
| Database grant options | Deny grantable database ACL edges to PUBLIC or either collector role | Expand explicit/default database ACL and reject `is_grantable` when `grantee = 0` (PUBLIC) or either collector OID; PostgreSQL itself rejects granting grant options to PUBLIC, and the disposable test verifies that rejection |
| Application schema USAGE | Deny | Effective schema privilege check for every non-system schema except supabase_migrations |
| supabase_migrations schema USAGE | Allow and require | Effective privilege check for both roles; migration-history SELECT remains separately required |
| Application schema ownership | Deny | Reject ownership by authenticated or effective collector role |
| PostgreSQL system catalogs | Preserve only the enumerated required catalog access, including `pg_database` | Existing catalog SELECT preflight explicitly requires SELECT on `pg_database` for authenticated and effective principals |

Database ACL evidence is emitted as the `database_acl_v1` projection for every row in `pg_database`, including template databases. It records the database OID/name and connection/template flags; owner OID/name; whether the original `datacl` was NULL; whether edges came from the built-in default ACL or an explicit ACL; and every expanded ACL edge with grantee/grantor OIDs and names, explicit `PUBLIC` identification, privilege type and grant-option flag. A NULL `datacl` is expanded with `acldefault('d', datdba)`; an explicit empty ACL remains distinguishable from NULL. JSONB keys are canonical, ACL edges are ordered by grantee OID, grantor OID, privilege type and grantability, and database rows by OID/name. This complete projection is mandatory input to the canonical result digest and signed receipt; excluding it invalidates the evidence receipt.

PostgreSQL does not permit `WITH GRANT OPTION` when the grantee is `PUBLIC`. The audit nevertheless explicitly rejects a PUBLIC (`grantee = 0`) grant-option ACL edge as a defensive invariant if an impossible/corrupt catalog state were ever observed. The PostgreSQL 16 regression attempts the prohibited GRANT and asserts the server rejects it; it does not fabricate an impossible ACL row.

PostgreSQL's built-in defaults are security-relevant. A NULL routine ACL is not an empty ACL: acldefault('f', owner) includes the default PUBLIC EXECUTE grant. A NULL database ACL is not empty either: acldefault('d', owner) supplies built-in database privileges, including PUBLIC CONNECT and TEMP. The audit evaluates effective privilege functions as well as ACL entries, so absent catalog ACL rows are never interpreted as proof that a privilege is absent. In the disposable PostgreSQL 16 baseline, PUBLIC TEMP and PUBLIC application-schema USAGE are explicitly revoked and global PUBLIC routine EXECUTE defaults are revoked before the approved positive case.

Application routine exceptions are not implied by ownership, SECURITY DEFINER status, overload identity or an ACL omission. A new exception requires explicit DBA/security approval and a separately reviewed change to this policy and its adversarial fixtures.

Global routine defaults must also be evaluated when pg_default_acl has no global row for an owner role: PostgreSQL then uses acldefault('f', owner), which includes PUBLIC EXECUTE. The audit checks that implicit default for every role that owns or can CREATE in an application schema, as well as all explicit global and schema-specific rows. The pg_database_owner pseudo-role is represented by the actual current database owner, whose schema-creation capability and default ACL are checked separately.

## Remaining external infrastructure dependencies (not delivered by C460)

The SQL policy and disposable CI fixtures do not create or prove the Production collector infrastructure. The following dependencies remain open:

- A controlled, isolated collector runtime that connects directly as the dedicated non-superuser login; no superuser impersonation or browser-side collection.
- Independent TLS certificate-chain and hostname verification, plus independent confirmation of the expected Supabase project and endpoint. SQL GUC labels remain untrusted metadata.
- Production provisioning and DBA verification of the dedicated collector role against the approved matrix, including removal of inherited memberships, PUBLIC TEMP, application-schema USAGE, routine EXECUTE and unsafe default ACLs.
- An approved secret manager or locked-down external PGSERVICEFILE/PGPASSFILE for the database credential. No credential material belongs in Git, command arguments, chat or evidence logs.
- A KMS/HSM or controlled signing service for collector receipts, with key identity and rotation controls. No independent signing implementation or key is established by this change.
- An immutable evidence store and operational retention/access controls for signed receipts, query digests, CI/deployment references and failure diagnostics.
- Production operational validation: exact commit and SQL bundle digest, verified TLS peer, authenticated/effective identities, live effective privileges, read-only transaction, result digest, UTC capture time and signed receipt.

These dependencies are NOT ESTABLISHED by the PostgreSQL 16 disposable test. No Production connection, credential access, TLS verification, KMS/HSM signing, deployment or Production collection was performed in C460.

## Execute only the read-only bundle

Use a supported psql client in a controlled environment with `ON_ERROR_STOP`, no user startup file, TLS verification required and a dedicated read-only database role. Example shape (not a credential-bearing command):

```sh
psql -X --no-psqlrc --set=ON_ERROR_STOP=1 \
  --dbname='service=deedlight-production-readonly' \
  --file=scripts/production-migration-readonly-audit.sql
```

The referenced service definition and password file must live outside the repository and be mounted by the secret manager. Configure the three non-secret custom GUC labels via the controlled connection profile/PGOPTIONS. Do not print connection settings. Do not run Supabase CLI link, db pull, db push, reset, migration, RPC or application queries as part of this audit.

The SQL starts a REPEATABLE READ READ ONLY transaction, sets bounded statement/lock timeouts, validates project/SHA/principal context, rejects `SET ROLE`, validates both authenticated and effective role attributes/memberships, and enforces the collector privilege contract. It validates the exact supported migration-history shape: precisely three active columns (`version text NOT NULL`, `name text NULL`, `statements text[] NULL`), no defaults/generated/identity columns, one validated non-deferrable primary key on `version`, and one valid/ready/live btree primary-key index with no additional constraints or indexes. The table must be permanent, ordinary and without RLS; version metadata must be 12 digits and optional migration names must match the reviewed identifier syntax. Other history shapes abort collection pending an explicit compatibility review. Whole-row JSON serialization is prohibited.

Routine `proconfig` is not exported wholesale. Only the reviewed `search_path`, `row_security`, `default_transaction_read_only`, statement/lock/idle timeouts and `temp_file_limit` settings are accepted, with deterministic sorted JSON serialization. Search paths must use unique schemas in canonical `pg_catalog`, `public`, `extensions`, `auth`, `storage` order (omitting unused entries is allowed), with optional `pg_temp` strictly last. Explicit `pg_catalog` must be first. Every non-system path schema must exist, have no PUBLIC CREATE grant, be owned by a non-login trusted role, and have no untrusted login principals with CREATE through direct grants or role membership. `row_security` and `default_transaction_read_only` must be `on`. Statement timeout is capped at 5 minutes, lock timeout at 30 seconds, idle-in-transaction timeout at 60 seconds, and `temp_file_limit` must be positive and at most 1 GiB; unlimited and zero values are rejected. Any custom GUC or unexpected value aborts collection before routine metadata is emitted.

Missing required history/catalog access or an unsupported history shape aborts collection. Missing catalog access must not be worked around by a more privileged browser/application role; escalate to the DBA for a separately approved direct read-only grant and rerun.

## PostgreSQL 16 disposable execution validation

The CI fixture `scripts/test-production-migration-readonly-audit-postgres16.sh` runs only against a disposable PostgreSQL 16 service with no Production connection or credentials. It exercises:
- approved catalog-only role success and explicit transaction rollback;
- predefined `pg_read_all_data` membership rejection;
- SECURITY DEFINER private-data exfiltration using a synthetic fixture value; PUBLIC/direct/inherited EXECUTE rejection by routine OID, including overloaded functions, procedures, aggregates and window functions; global and schema-specific future EXECUTE default rejection;
- database CONNECT requirement, CREATE/TEMP/ownership/grant-option rejection, PostgreSQL's rejection of an attempted PUBLIC `WITH GRANT OPTION` grant, deterministic all-database `pg_database.datacl` evidence (including NULL/default expansion, PUBLIC, grantors and grantability), application-schema USAGE/ownership rejection, and cleanup/recovery after each rejected collection;
- missing migration-history SELECT and missing catalog SELECT rejection;
- table-level, column-level and sequence privilege rejection;
- invalid project and repository metadata;
- malformed history schemas (extra columns, wrong PostgreSQL types/nullability, missing primary key, unexpected indexes and invalid migration metadata);
- custom-GUC disclosure, canonical and duplicate `search_path` rejection, explicit `pg_catalog` ordering, missing/untrusted schema rejection, PUBLIC/direct/inherited CREATE privilege rejection, unsafe `row_security` and `default_transaction_read_only` rejection, unlimited/excessive timeout and `temp_file_limit` rejection, plus deterministic allowlisted routine-setting serialization;
- direct/nested role switching, nested inheritance of both `pg_read_all_data` and application-table SELECT, predefined privileged-role membership, privileged-login `SET ROLE` impersonation rejection, and an explicit successful `SET SESSION AUTHORIZATION` limitation demonstration; spoofed/missing/malformed principal context, revoked LOGIN/catalog/history authorization, and legitimate plus privileged-owner SECURITY DEFINER execution, including rejection of an unsupported `SET ROLE` context. The SECURITY DEFINER fixture mirrors the audit's authenticated/effective identity and membership checks, with static parity assertions to prevent drift;
- an actual lock-timeout interruption and recovery; and
- abrupt client termination while a transaction holds a table lock and uncommitted marker row, proving backend termination, rollback, lock release, no stale authentication context and successful subsequent collection.

The fixture creates synthetic roles, a synthetic history row and synthetic application objects. Its approved positive path authenticates over the PostgreSQL connection directly as `deedlight_catalog_auditor`; it does not use superuser `SET SESSION AUTHORIZATION`. A separate superuser login attempts `SET ROLE deedlight_catalog_auditor` and must be rejected because the authenticated `session_user` remains the superuser. A distinct, explicitly labeled limitation test then demonstrates that a superuser can use `SET SESSION AUTHORIZATION deedlight_catalog_auditor` to make both SQL-visible identity fields appear to be the collector and pass the SQL audit. That test is expected to succeed only to prove the limit of SQL-level verification; it is not an approved authentication path and must never be used by a real collector. The fixture also grants `pg_read_all_data` and an application-table SELECT privilege to a nested member role and verifies that inherited membership is rejected. Fixture passwords are generated at runtime and are not stored in the repository. Never point this harness at Production. It does not validate the provider-specific endpoint identity or establish Production state.

## Evidence boundary and output handling

Permitted export content:
- database/server identity metadata and exact UTC capture time;
- schema object names, types, owners, column definitions/defaults, sequences and their ownership dependencies;
- function identity signatures, owners, SECURITY DEFINER flags, language, volatility and only the reviewed allowlisted configuration (not function bodies or arbitrary custom GUC values);
- ACL edges, grants/revokes, role attributes/memberships and default privileges;
- RLS flags and policy expressions;
- constraints, index definitions plus validity/readiness/liveness/uniqueness flags, trigger definitions;
- installed extension names/versions/schemas/owners;
- migration-history table structure and migration version/name/statement counts only.

Never export application table rows, reflection text, member/profile/invitation/newsletter data, email addresses, access tokens, webhook payloads, provider diagnostics, private Offering content or delivery-recipient data. Migrations 037–038 create tables containing recipient emails and resolution notes; audit those tables' schema/ACL/RLS metadata only. Never select those rows.

Write outputs to an encrypted, access-controlled evidence store outside the repository. Do not upload raw exports as public CI artifacts or commit them. Compute a cryptographic digest over the complete permitted result set, including the entire ordered `database_acl_v1` projection for every database, and include it in the signed collector receipt. The collector must fail closed if this projection is missing, truncated or omitted from the digest input. Redact host-specific data if the evidence sharing policy requires it, while retaining a protected exact endpoint identity in the signed receipt.

## Fail-closed conditions

Stop and classify the collection as failed/Unknown if:
- TLS hostname/certificate or provider project identity cannot be independently confirmed;
- expected project reference or exact repository SHA is missing/mismatched;
- read-only transaction is not active;
- migration history table is absent, unreadable or lacks required columns;
- required catalog views cannot be read completely;
- query timeout, disconnect, partial output or collector signing failure occurs;
- output includes unexpected application data or secrets;
- the SQL bundle or inventory blob differs from the pinned SHA.

Do not retry through a more privileged identity without a new DBA/security approval. Preserve the failure record without secrets.

## Required signed receipt

The collector receipt should bind: actual endpoint/provider identity and TLS verification result; project ref; database name/server version/address metadata; authenticated session principal, effective role, role-switch state and verified effective privileges; exact repository commit SHA; inventory blob SHA-1; read-only SQL bundle SHA-256; transaction start/capture UTC timestamps; query completion timestamp; statement/query count; full result digest; output schema version; success/failure state; and collector identity/key ID. Sign using the independently provisioned collector key. Private signing material remains in KMS/HSM or controlled signing service and never enters this repository.

On CI failure, the disposable harness prints and retains sanitized synthetic PostgreSQL client/backend logs in the runner temporary directory; the workflow uploads those diagnostics as a failure-only artifact. These logs contain only fixture identities and synthetic values.

## Historical migration classifications\n\nMigration 007, Migration 018 and Migration 037 remain **NOT ESTABLISHED** for Production. This collector policy and its disposable fixtures do not prove historical execution, prerequisites, backfill completeness or live Production state. Do not mark any of these migrations applied or Production-matched based on this work.\n\n## No authorization to mutate

This package does not authorize migration-history reconciliation, schema changes, role grants, backup deletion, deployment, scheduler activation or any Production mutation. Before a future change, require a verified backup/PITR restore point, isolated restore rehearsal, independently approved migration-effect mapping, resolved Migration 007 ambiguity and explicit DBA/security change approval.


## Collector security review remediation — F-01 through F-06

The PR #24 collector implementation now enforces the following additional controls. These are source-level contracts; their runtime status is established only by the exact-head CI run and its retained logs.

- **F-01 — TLS trust-anchor integrity:** Set `DEEDLIGHT_COLLECTOR_TLS_CA_SHA256` to a separately provisioned SHA-256 for the exact CA certificate file. It is independent of `DEEDLIGHT_COLLECTOR_ENDPOINT_PROFILE_SHA256`; never calculate either expected pin from the untrusted profile during collection. The CA parent directory must be owned by the collector OS user and mode 0700; the regular CA file must be owned by that user and have no group/other permissions (normally 0600). The collector opens it with no-follow semantics, checks the independently pinned digest, retains the original descriptor, snapshots those pinned bytes into a private 0700 directory/0600 file used by libpq, and checks the original path inode and descriptor digest again before receipt creation. A replacement or in-place modification fails closed.
- **F-02 — ACL projection completeness:** The mandatory `database_acl_v1` CSV header is exactly, and in order: `evidence_projection`, `database_count`, `database_oid`, `database_name`, `allows_connections`, `is_template`, `owner_oid`, `owner_name`, `datacl_was_null`, `acl_expansion_source`, `expanded_acl_edges`. Missing, duplicate, reordered or unexpected columns, wrong row widths, and malformed field representations invalidate collection.
- **F-03 — PostgreSQL OIDs:** Database, owner and grantor OIDs must be positive canonical decimal values within uint32 (1–4294967295). Grantee OID may be zero only for PUBLIC, represented by the exact name `PUBLIC`; nonzero grantee OIDs may not use that name. ACL JSON accepts canonical decimal strings or safe integer JSON numbers only.
- **F-04 — ACL logical uniqueness:** Duplicate ACL identity is (grantee OID, grantor OID, privilege type). Grantability does not create a distinct logical edge. SQL ordering remains deterministic by grantee, grantor, privilege type and grantability.
- **F-05 — CSV parsing:** CRLF record delimiters are accepted; bare CR outside quoted fields is rejected. CR/LF inside quoted fields is preserved exactly. Empty leading, middle and trailing cells, escaped quotes, malformed quoting and characters after a closing quote have explicit regression coverage.
- **F-06 — receipt verification:** `verifyReceiptAndEvidence` validates every required top-level and nested receipt field, exact object keys, field types/constants, timestamps, hashes, byte length and the explicitly unsigned/not-accepted signing state before checking raw and canonical evidence bindings. It does not accept signed or accepted receipts.

Required regression commands (CI is the primary validation machine):

```sh
node --test scripts/test-production-evidence-collector.mjs
bash scripts/test-production-evidence-collector-postgres16.sh
```

The PostgreSQL 16 harness uses disposable local identities and local certificates only. It must never receive Production credentials or endpoints. The migration analyzer and repository security assertions are required in the same exact-HEAD PR Validation workflow. A green unit suite alone does not establish the PostgreSQL 16 integration or the exact-HEAD CI gate.


## Follow-up hardening — F-01 resource lifecycle and F-06 RFC3339

- Immediately after `loadProfile` returns successfully, collection enters a cleanup-protected scope. Output-parent resolution, output-path authorization, existing-directory checks, directory creation, psql execution, evidence validation and receipt writes all run inside that scope. Every exit closes the CA descriptor and removes its private trust-anchor snapshot. Partial output is removed on failure.
- Snapshot creation hashes the exact bytes read from the pinned descriptor against the independently provisioned CA digest, writes those bytes into the private 0700/0600 snapshot, and hashes the bytes read back from that snapshot against the same pin. Snapshot initialization failures remove the partially created temporary directory and close the descriptor.
- Receipt timestamps now use strict RFC3339 syntax plus Gregorian calendar validation: month/day bounds, leap-year rules, hour/minute/second bounds and timezone offset ranges are checked before Date parsing/comparison. Impossible dates are not accepted merely because a date parser normalizes them.
- Regression cases cover output-directory validation cleanup, simulated snapshot-write failure, copied-snapshot digest binding, February 31, non-leap February 29, valid leap-year February 29, invalid clock fields and invalid offsets.
- **Supported receipt timestamp profile (C482/C484):** timestamps use a DeedLight-specific restricted RFC3339 profile, not full RFC3339 compatibility. The JSON Schema pattern enforces years 0001–9999, lexical date/time fields, seconds 00–59, optional arbitrary-length fractional digits and bounded numeric offsets; it rejects leap seconds (:60) and unknown offset (-00:00). Generic `format: date-time` alone is insufficient. Mandatory semantic verification additionally validates actual Gregorian dates and leap years, timezone ranges and exact UTC ordering at arbitrary fractional precision. It rejects completion-before-start and accepts equivalent instants expressed with different offsets. Schema-only validation must never authorize receipt acceptance or signing.

- **F-06 DeedLight timestamp contract:** the receipt JSON Schema explicitly describes and lexically enforces both `execution.startedAt` and `execution.completedAt`. Its pattern preserves arbitrary fractional digits, rejects seconds `60` and `-00:00`, and bounds clock/offset syntax. `format: date-time` is an additional annotation, not the complete contract. The schema cannot prove Gregorian month/day combinations or cross-field ordering. `verifyReceiptAndEvidence` is therefore the mandatory semantic gate before acceptance or future signing: it validates Gregorian/leap-year dates and timezone ranges, compares exact instants at arbitrary fractional precision, rejects completion-before-start and verifies evidence bindings. Schema-only validation must never authorize signing or acceptance; equivalent instants expressed with different offsets are accepted.
