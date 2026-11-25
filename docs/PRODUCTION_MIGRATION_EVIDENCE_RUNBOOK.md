# DeedLight Production migration evidence collection runbook

**Read-only evidence preparation only.** No Production query has been run by this change. Do not use this runbook as authorization to connect to or mutate Production.

## Preconditions and separation of duties

- DBA/security owner authorizes a read-only audit window and identifies the exact Production project/endpoint through an independently trusted channel.
- Collector runs from a controlled, isolated host. Verify TLS certificate/hostname and expected Supabase project reference independently; the SQL-supplied project label is metadata, not endpoint authentication.
- Use a dedicated, non-owner collector role with direct grants only. The approved contract is: no superuser, role/database creation, replication or BYPASSRLS attributes; no membership, direct or inherited, in any other role (including every predefined `pg_*` role, especially `pg_read_all_data` and `pg_write_all_data`, and `service_role`); no database CREATE, application-schema CREATE, application table/view/foreign-table privileges (including column ACLs), application sequence USAGE/SELECT/UPDATE, or ownership of application objects/schemas.
- Grant SELECT only on the explicitly enumerated PostgreSQL catalogs/views required by the audit and SELECT on `supabase_migrations.schema_migrations`. The collector must not own the history table or have table/column write privileges on it. The SQL enforces these effective privileges before collection; a failed check is a hard stop, not a prompt to use a stronger role.
- Do not grant application table or sequence access to make catalog queries work. Catalog metadata is read through `pg_catalog`; the audit never needs to read application rows. The SQL transaction is a second control, not a substitute for the role contract.
- Credentials must come from an approved secret manager or an external `PGSERVICEFILE`/`PGPASSFILE` with restrictive filesystem permissions. Never put credentials, connection URIs, tokens or passwords in repository files, command arguments, shell history, CI logs or evidence artifacts.
- Record the exact repository SHA being audited (the package implementation commit is `6ca30f8ad1cb07184ded05770838c620ecf6d59c` before this remediation) and inventory blob SHA `95d514a0bd97ff448c9507252eb1f5e69a507442` in the collector receipt. A controlled runner must verify the checked-out commit and migration inventory before collection.
- Provide non-secret connection metadata through PostgreSQL custom settings:
  - `deedlight.expected_project_ref=xaipiovflxomcbfwtwmu`
  - `deedlight.repository_sha=<exact 40-character commit SHA>`
  These labels are not proof of endpoint identity. The collector must bind the actual TLS peer/host, provider project identity, repository SHA, SQL bundle digest, query output digest and UTC capture timestamp into a signed receipt.

## Execute only the read-only bundle

Use a supported psql client in a controlled environment with `ON_ERROR_STOP`, no user startup file, TLS verification required and a dedicated read-only database role. Example shape (not a credential-bearing command):

```sh
psql -X --no-psqlrc --set=ON_ERROR_STOP=1 \
  --dbname='service=deedlight-production-readonly' \
  --file=scripts/production-migration-readonly-audit.sql
```

The referenced service definition and password file must live outside the repository and be mounted by the secret manager. Configure the two non-secret custom GUC labels via the controlled connection profile/PGOPTIONS. Do not print connection settings. Do not run Supabase CLI link, db pull, db push, reset, migration, RPC or application queries as part of this audit.

The SQL starts a REPEATABLE READ READ ONLY transaction, sets bounded statement/lock timeouts, validates required project/SHA metadata, enforces the collector privilege contract, validates the supported migration-history schema (`version text`, `name text`, `statements text[]`), queries PostgreSQL catalogs plus explicit migration version/name/statement-count columns only, and ends with ROLLBACK. Whole-row JSON serialization is prohibited. Missing required history/catalog access or an unsupported history shape aborts collection. Missing catalog access must not be worked around by a more privileged browser/application role; escalate to the DBA for a separately approved direct read-only grant and rerun.

## PostgreSQL 16 disposable execution validation

The CI fixture `scripts/test-production-migration-readonly-audit-postgres16.sh` runs only against a disposable PostgreSQL 16 service with no Production connection or credentials. It exercises:
- approved catalog-only role success and explicit transaction rollback;
- predefined `pg_read_all_data` membership rejection;
- missing migration-history SELECT and missing catalog SELECT rejection;
- table-level, column-level and sequence privilege rejection;
- invalid project and repository metadata;
- an actual migration-history/index-inspection lock-timeout interruption, transaction abort and successful subsequent read-only retry.

The fixture creates synthetic roles, a synthetic history row and synthetic application objects. Never point this harness at Production. It does not validate the provider-specific endpoint identity or establish Production state.

## Evidence boundary and output handling

Permitted export content:
- database/server identity metadata and exact UTC capture time;
- schema object names, types, owners, column definitions/defaults, sequences and their ownership dependencies;
- function identity signatures, owners, SECURITY DEFINER flags, language, volatility and configuration (not function bodies);
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

The collector receipt should bind: actual endpoint/provider identity and TLS verification result; project ref; database name/server version/address metadata; role identity and verified effective privileges; exact repository commit SHA; inventory blob SHA-1; read-only SQL bundle SHA-256; transaction start/capture UTC timestamps; query completion timestamp; statement/query count; full result digest; output schema version; success/failure state; and collector identity/key ID. Sign using the independently provisioned collector key. Private signing material remains in KMS/HSM or controlled signing service and never enters this repository.

## No authorization to mutate

This package does not authorize migration-history reconciliation, schema changes, role grants, backup deletion, deployment, scheduler activation or any Production mutation. Before a future change, require a verified backup/PITR restore point, isolated restore rehearsal, independently approved migration-effect mapping, resolved Migration 007 ambiguity and explicit DBA/security change approval.
