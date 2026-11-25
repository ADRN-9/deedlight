# DeedLight Production migration evidence collection runbook

**Read-only evidence preparation only.** No Production query has been run by this change. Do not use this runbook as authorization to connect to or mutate Production.

## Preconditions and separation of duties

- DBA/security owner authorizes a read-only audit window and identifies the exact Production project/endpoint through an independently trusted channel.
- Collector runs from a controlled, isolated host. Verify TLS certificate/hostname and expected Supabase project reference independently; the SQL-supplied project label is metadata, not endpoint authentication.
- Authenticate directly as the dedicated login role `deedlight_catalog_auditor`; do not connect as `postgres`, a superuser, or another login and then use `SET SESSION AUTHORIZATION` to impersonate the collector. The audit requires `session_user = deedlight_catalog_auditor` and validates the authenticated principal independently from the effective `current_user`. The effective role may differ only in a legitimate `SECURITY DEFINER` execution context; `SET ROLE` is rejected. Both authenticated and effective roles must be non-privileged and have no direct or inherited memberships. This intentionally avoids a brittle `session_user = current_user` check.
- The custom GUC `deedlight.authenticated_principal` must equal the actual `session_user`; it is an untrusted consistency label, not authentication. A spoofed or missing label fails closed. PostgreSQL cannot reveal whether a superuser previously used `SET SESSION AUTHORIZATION` to impersonate another role, so the collector must authenticate directly through the independently verified TLS endpoint as the dedicated non-superuser login. Never run this bundle through a superuser session.
- The approved role has no superuser, role/database creation, replication or BYPASSRLS attributes; no membership, direct or inherited, in any other role (including every predefined `pg_*` role, especially `pg_read_all_data` and `pg_write_all_data`, and `service_role`); no database CREATE, application-schema CREATE, application table/view/foreign-table privileges (including column ACLs), application sequence USAGE/SELECT/UPDATE, or ownership of application schemas and relations (ordinary/partitioned tables, views, materialized views, foreign tables and sequences). Routine ownership is inventoried but is not an authorization rejection criterion; standalone type ownership is not inventoried or enforced.
- Grant SELECT only on the explicitly enumerated PostgreSQL catalogs/views required by the audit and SELECT on `supabase_migrations.schema_migrations`. The collector must not own the history table or have table/column write privileges on it. The SQL enforces these effective privileges before collection; a failed check is a hard stop, not a prompt to use a stronger role.
- Do not grant application table or sequence access to make catalog queries work. Catalog metadata is read through `pg_catalog`; the audit never needs to read application rows. The SQL transaction is a second control, not a substitute for the role contract.
- Credentials must come from an approved secret manager or an external `PGSERVICEFILE`/`PGPASSFILE` with restrictive filesystem permissions. Never put credentials, connection URIs, tokens or passwords in repository files, command arguments, shell history, CI logs or evidence artifacts.
- Record the exact repository SHA checked out at collection time and inventory blob SHA `95d514a0bd97ff448c9507252eb1f5e69a507442` in the collector receipt. Never copy a historical commit SHA from this runbook; a controlled runner must verify the checked-out commit and migration inventory before collection.
- Provide non-secret connection metadata through PostgreSQL custom settings:
  - `deedlight.expected_project_ref=xaipiovflxomcbfwtwmu`
  - `deedlight.repository_sha=<exact 40-character commit SHA>`
  - `deedlight.authenticated_principal=deedlight_catalog_auditor`
  The authenticated-principal GUC is compared with `session_user` but is not itself an authentication factor. These labels are not proof of endpoint identity. The collector must bind the actual TLS peer/host, provider project identity, authenticated and effective role identities, repository SHA, SQL bundle digest, query output digest and UTC capture timestamp into a signed receipt.

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
- missing migration-history SELECT and missing catalog SELECT rejection;
- table-level, column-level and sequence privilege rejection;
- invalid project and repository metadata;
- malformed history schemas (extra columns, wrong PostgreSQL types/nullability, missing primary key, unexpected indexes and invalid migration metadata);
- custom-GUC disclosure and unsafe `search_path` rejection, plus deterministic allowlisted routine-setting serialization;
- direct/nested role switching, nested inheritance of both `pg_read_all_data` and application-table SELECT, predefined privileged-role membership, privileged-login `SET ROLE` impersonation rejection, and an explicit successful `SET SESSION AUTHORIZATION` limitation demonstration; spoofed/missing/malformed principal context, revoked LOGIN/catalog/history authorization, and legitimate plus privileged-owner SECURITY DEFINER execution;
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

Write outputs to an encrypted, access-controlled evidence store outside the repository. Do not upload raw exports as public CI artifacts or commit them. Compute a cryptographic digest over the complete permitted result set and include it in the signed collector receipt. Redact host-specific data if the evidence sharing policy requires it, while retaining a protected exact endpoint identity in the signed receipt.

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

## No authorization to mutate

This package does not authorize migration-history reconciliation, schema changes, role grants, backup deletion, deployment, scheduler activation or any Production mutation. Before a future change, require a verified backup/PITR restore point, isolated restore rehearsal, independently approved migration-effect mapping, resolved Migration 007 ambiguity and explicit DBA/security change approval.
