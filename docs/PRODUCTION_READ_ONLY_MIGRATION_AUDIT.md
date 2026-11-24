# DeedLight Production read-only migration audit packet

**Purpose:** Give the Production owner a repeatable, SELECT-only catalog and migration-history audit.  
**Repository:** ADRN-9/deedlight  
**Source branch:** security/private-daily-journey-admin-isolation-c408  
**Source snapshot inspected for Cycle 363:** acad78981312d40993d03ec8c22240239c62a36b  
**Source tree:** 6935200cefe484cfd16bba85e125966218261c79  
**Source migration inventory at the Cycle 363 baseline:** 39 SQL files; 38 unique version prefixes  
**Known Production project reference:** xaipiovflxomcbfwtwmu  
**Disposition:** PREPARED ONLY — no Production connection or query execution was performed; every Production migration classification remains UNKNOWN.

This packet complements [PRODUCTION_MIGRATION_RECONCILIATION.md](PRODUCTION_MIGRATION_RECONCILIATION.md). That document remains the authoritative 37-file source inventory, including each exact filename, Git blob SHA, source dependency, and source-level effect. This packet supplies the owner-facing read-only SQL procedure; it does not repeat the inventory or classify Production.

## 1. Safety boundary

Every SQL statement in this packet is a SELECT. The packet does not:

- Create, alter, drop, grant, revoke, set, repair, mark, or execute migrations.
- Insert, update, delete, truncate, or otherwise mutate any database object or row.
- Execute application functions, triggers, or migration SQL.
- Read application-member rows, auth.users, email addresses, provider events, credentials, tokens, delivery records, or private reflections.
- Establish whether any migration ran in Production.

Do not add statements from migration files or aggregate SQL bundles to this packet. Do not run supabase db push, migration repair, db reset, db pull, SQL Editor DDL, or history edits during this audit. Do not use a service-role key or a privileged application credential.

The catalog queries return object definitions, policy expressions, ACL metadata, role names, and schema structure. Treat the results as confidential operational evidence even though application-member data is intentionally excluded.

## 2. Verify the target before opening SQL Editor

A Production owner/operator must independently verify all of the following before running any query:

1. Open the Supabase Dashboard using the approved organization account.
2. Select the intended DeedLight Production project and verify the project reference in the dashboard URL is exactly **xaipiovflxomcbfwtwmu**.
3. Confirm the selected project is the Production project, not a preview, staging, local, or similarly named project. Compare the project name, reference, and approved environment record.
4. If using a direct database connection, verify its host/project reference against the same dashboard project. Do not paste a connection URI, password, access token, or key into the evidence packet or chat.
5. Use a dedicated database role with the minimum read-only permissions described below. Do not use postgres, service_role, supabase_admin, a service-role API key, or an account that can change schema/history.
6. Run Query 1 and confirm the connected database/role details and read-only posture. If the project reference cannot be confirmed independently, the role is elevated, or the connection is not enforced read-only, stop without running the remaining queries.

The SQL session cannot reliably attest the Supabase project reference by itself. The project-reference check is a deliberate dashboard/connection-identity check, not an inferred database name or hostname heuristic. A matching database name alone is insufficient.

## 3. Minimum database permissions

The owner/DBA should provision or select an already-approved audit identity with only:

- CONNECT to the target database.
- USAGE on the schemas whose metadata is being inspected: public, auth, storage, extensions (if present), and supabase_migrations (if present).
- SELECT on supabase_migrations.schema_migrations, if that relation exists.
- The normal read visibility of PostgreSQL system catalogs and information_schema required to inspect object metadata.

The audit identity does **not** need SELECT on application tables, access to auth.users, EXECUTE on DeedLight application RPCs, BYPASSRLS, superuser, CREATE on the database or schemas, CREATEROLE, CREATEDB, REPLICATION, service_role membership, or any migration/deployment capability. It must not inherit privileged roles. The role should be configured by the owner/DBA outside this packet; this packet contains no GRANT or role-management statements.

For the strictest execution boundary, use a connection whose transaction is enforced read-only by the database/connection profile. Query 1 reports transaction_read_only and relevant role flags. If transaction_read_only is off, do not proceed with this packet until the owner supplies an enforced read-only session. Do not try to enable read-only mode with a SET command in this packet.

## 4. Query sequence

Run the following SELECT statements individually, in order, from the verified Production read-only session. Preserve each query text with its result and execution timestamp. Do not combine this packet with other SQL.

### Query 1 — target database and audit-role identity

~~~sql
SELECT
  current_database() AS database_name,
  current_user AS connected_role,
  session_user AS session_role,
  inet_server_addr()::text AS server_address,
  inet_server_port() AS server_port,
  current_setting('server_version') AS server_version,
  current_setting('transaction_read_only') AS transaction_read_only,
  r.rolsuper AS is_superuser,
  r.rolcreatedb AS can_create_database,
  r.rolcreaterole AS can_create_roles,
  r.rolreplication AS can_replicate,
  r.rolbypassrls AS bypasses_rls,
  r.rolinherit AS inherits_role_privileges,
  has_database_privilege(current_user, current_database(), 'CREATE')
    AS can_create_in_database
FROM pg_catalog.pg_roles AS r
WHERE r.rolname = current_user;
~~~

Expected posture: transaction_read_only is on; all elevated role flags are false; can_create_in_database is false. Any contrary result is a stop condition. The server address/port and database name are supporting identity evidence, not substitutes for the manual project-reference check.

### Query 2 — role memberships visible to the audit identity

~~~sql
SELECT
  granted_role.rolname AS granted_role,
  pg_has_role(current_user, granted_role.oid, 'MEMBER') AS is_member,
  pg_has_role(current_user, granted_role.oid, 'USAGE') AS privileges_inherited
FROM pg_catalog.pg_roles AS granted_role
WHERE granted_role.rolname <> current_user
  AND pg_has_role(current_user, granted_role.oid, 'MEMBER')
ORDER BY granted_role.rolname;
~~~

This uses PostgreSQL's role-membership visibility function rather than reading the authentication membership catalog directly. It reports direct and inherited memberships visible to the current role. The audit identity must not be a member of service_role, postgres, supabase_admin, or another role with schema, data, credential, or migration authority. An empty result is expected for a dedicated standalone audit role.

### Query 3 — relevant PostgreSQL schemas and schema ACLs

~~~sql
SELECT
  namespace.nspname AS schema_name,
  pg_catalog.pg_get_userbyid(namespace.nspowner) AS schema_owner,
  namespace.nspacl::text AS schema_acl,
  has_schema_privilege(current_user, namespace.oid, 'USAGE') AS audit_role_has_usage,
  has_schema_privilege(current_user, namespace.oid, 'CREATE') AS audit_role_has_create
FROM pg_catalog.pg_namespace AS namespace
WHERE namespace.nspname = ANY (
  ARRAY['public', 'auth', 'storage', 'extensions', 'supabase_migrations']
)
ORDER BY namespace.nspname;
~~~

This reports only schema metadata and privileges. A missing schema is not evidence that a migration did not run; record the absence and continue only where the remaining query prerequisites exist.

### Query 4 — relations and row-level-security flags

~~~sql
SELECT
  namespace.nspname AS schema_name,
  relation.relname AS relation_name,
  CASE relation.relkind
    WHEN 'r' THEN 'table'
    WHEN 'p' THEN 'partitioned table'
    WHEN 'v' THEN 'view'
    WHEN 'm' THEN 'materialized view'
    WHEN 'f' THEN 'foreign table'
    WHEN 'S' THEN 'sequence'
    ELSE relation.relkind::text
  END AS relation_kind,
  pg_catalog.pg_get_userbyid(relation.relowner) AS relation_owner,
  relation.relpersistence AS persistence,
  relation.relrowsecurity AS rls_enabled,
  relation.relforcerowsecurity AS rls_forced
FROM pg_catalog.pg_class AS relation
JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = relation.relnamespace
WHERE namespace.nspname = ANY (
  ARRAY['public', 'auth', 'storage', 'extensions', 'supabase_migrations']
)
  AND relation.relkind IN ('r', 'p', 'v', 'm', 'f', 'S')
ORDER BY namespace.nspname, relation.relkind, relation.relname;
~~~

### Query 5 — columns, types, defaults, and nullability

~~~sql
SELECT
  namespace.nspname AS schema_name,
  relation.relname AS relation_name,
  attribute.attnum AS ordinal_position,
  attribute.attname AS column_name,
  pg_catalog.format_type(attribute.atttypid, attribute.atttypmod) AS data_type,
  attribute.attnotnull AS not_null,
  attribute.attidentity AS identity_kind,
  attribute.attgenerated AS generated_kind,
  pg_catalog.pg_get_expr(default_value.adbin, default_value.adrelid) AS default_expression
FROM pg_catalog.pg_attribute AS attribute
JOIN pg_catalog.pg_class AS relation
  ON relation.oid = attribute.attrelid
JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = relation.relnamespace
LEFT JOIN pg_catalog.pg_attrdef AS default_value
  ON default_value.adrelid = relation.oid
 AND default_value.adnum = attribute.attnum
WHERE namespace.nspname = ANY (
  ARRAY['public', 'auth', 'storage', 'extensions', 'supabase_migrations']
)
  AND relation.relkind IN ('r', 'p', 'v', 'm', 'f')
  AND attribute.attnum > 0
  AND NOT attribute.attisdropped
ORDER BY namespace.nspname, relation.relname, attribute.attnum;
~~~

### Query 6 — constraints and validation state

~~~sql
SELECT
  namespace.nspname AS schema_name,
  relation.relname AS relation_name,
  constraint_info.conname AS constraint_name,
  constraint_info.contype AS constraint_type,
  pg_catalog.pg_get_constraintdef(constraint_info.oid, true) AS definition,
  constraint_info.convalidated AS validated,
  constraint_info.condeferrable AS deferrable,
  constraint_info.condeferred AS initially_deferred
FROM pg_catalog.pg_constraint AS constraint_info
JOIN pg_catalog.pg_class AS relation
  ON relation.oid = constraint_info.conrelid
JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = relation.relnamespace
WHERE namespace.nspname = ANY (
  ARRAY['public', 'auth', 'storage', 'extensions', 'supabase_migrations']
)
ORDER BY namespace.nspname, relation.relname, constraint_info.conname;
~~~

### Query 7 — indexes and exact index definitions

~~~sql
SELECT
  namespace.nspname AS schema_name,
  table_relation.relname AS table_name,
  index_relation.relname AS index_name,
  index_info.indisprimary AS is_primary,
  index_info.indisunique AS is_unique,
  index_info.indisvalid AS is_valid,
  pg_catalog.pg_get_indexdef(index_info.indexrelid) AS index_definition
FROM pg_catalog.pg_index AS index_info
JOIN pg_catalog.pg_class AS table_relation
  ON table_relation.oid = index_info.indrelid
JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = table_relation.relnamespace
JOIN pg_catalog.pg_class AS index_relation
  ON index_relation.oid = index_info.indexrelid
WHERE namespace.nspname = ANY (
  ARRAY['public', 'auth', 'storage', 'extensions', 'supabase_migrations']
)
ORDER BY namespace.nspname, table_relation.relname, index_relation.relname;
~~~

### Query 8 — functions and procedures (metadata only)

~~~sql
SELECT
  namespace.nspname AS schema_name,
  procedure.proname AS routine_name,
  procedure.prokind AS routine_kind,
  pg_catalog.pg_get_function_identity_arguments(procedure.oid) AS identity_arguments,
  pg_catalog.pg_get_function_result(procedure.oid) AS result_type,
  language.lanname AS language,
  procedure.prosecdef AS security_definer,
  procedure.provolatile AS volatility,
  procedure.proconfig AS function_settings,
  pg_catalog.pg_get_userbyid(procedure.proowner) AS routine_owner,
  procedure.proacl::text AS routine_acl,
  CASE
    WHEN namespace.nspname = 'public'
     AND procedure.proname = 'admin_get_member_context'
    THEN position(
      'daily_reflections' IN lower(pg_catalog.pg_get_functiondef(procedure.oid))
    ) > 0
    ELSE NULL
  END AS admin_context_definition_mentions_daily_reflections
FROM pg_catalog.pg_proc AS procedure
JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = procedure.pronamespace
JOIN pg_catalog.pg_language AS language
  ON language.oid = procedure.prolang
WHERE namespace.nspname = ANY (
  ARRAY['public', 'auth', 'storage', 'extensions', 'supabase_migrations']
)
  AND procedure.prokind IN ('f', 'p')
ORDER BY namespace.nspname, procedure.proname,
         pg_catalog.pg_get_function_identity_arguments(procedure.oid);
~~~

This query does not return function bodies. For admin_get_member_context it returns only a boolean indicating whether its direct definition text contains the identifier daily_reflections. It is not a transitive call-graph proof; retain independent source review and inspect the relevant function definition under the approved review process if a deeper code review is needed. Do not export arbitrary function bodies.


### Query 8A — exact SECURITY DEFINER ownership inventory (18 signatures)

This targeted query is the authoritative collection inventory for Cycle 363. It deliberately names every in-scope identity signature, rather than relying on function-name matching or a broad schema scan. It is metadata-only and returns one row per expected signature, including missing functions and unresolved owners. It does not return function bodies, member data, credentials, or provider payloads.

Run it on PostgreSQL 16 or newer. The membership query in 8B uses the per-membership INHERIT and SET options introduced in PostgreSQL 16. Query 1 must record the server version before proceeding.

```sql
WITH expected(signature) AS (
  VALUES
    ('public.is_admin()'),
    ('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)'),
    ('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)'),
    ('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)'),
    ('public.record_delivery_provider_event(text,text,text,text,text)'),
    ('public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)'),
    ('public._record_delivery_provider_integrity_conflict(text,text,text,text,text,text,text,timestamptz,text,text,text,text,text,timestamptz,text,text,text)'),
    ('public._record_delivery_provider_lifecycle_event_pre037_impl(text,text,text,text,timestamptz,text,text,text,text)'),
    ('public._record_delivery_provider_suppression_event_pre037_impl(text,text,text,text,text,text,timestamptz,timestamptz,text)'),
    ('public._deny_delivery_provider_integrity_audit_mutation()'),
    ('public.admin_list_delivery_provider_integrity_conflicts(text,integer)'),
    ('public.admin_list_delivery_provider_integrity_evidence(bigint,integer)'),
    ('public.admin_list_delivery_provider_integrity_history(bigint,integer)'),
    ('public.admin_resolve_delivery_provider_integrity_conflict(bigint,text)'),
    ('public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamptz,bigint)'),
    ('public.admin_get_delivery_provider_integrity_conflict(bigint)'),
    ('public.admin_list_delivery_provider_integrity_evidence_page(bigint,integer,timestamptz,bigint)'),
    ('public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)')
),
resolved AS (
  SELECT
    expected.signature AS expected_identity_signature,
    pg_catalog.to_regprocedure(expected.signature) AS function_oid
  FROM expected
)
SELECT
  resolved.expected_identity_signature,
  CASE
    WHEN procedure.oid IS NULL THEN 'MISSING_FUNCTION'
    WHEN owner_role.oid IS NULL
      OR pg_catalog.pg_get_userbyid(procedure.proowner) IS NULL
      THEN 'MISSING_OWNER_ROLE'
    WHEN procedure.prosecdef IS DISTINCT FROM true
      THEN 'NOT_SECURITY_DEFINER'
    ELSE 'PRESENT'
  END AS inventory_status,
  CASE WHEN procedure.oid IS NOT NULL THEN
    pg_catalog.format(
      '%I.%I(%s)',
      namespace.nspname,
      procedure.proname,
      pg_catalog.pg_get_function_identity_arguments(procedure.oid)
    )
  END AS catalog_identity_signature,
  procedure.prokind AS routine_kind,
  procedure.prosecdef AS security_definer,
  procedure.proconfig AS function_settings_search_path,
  procedure.proacl::text AS explicit_function_acl,
  CASE WHEN procedure.oid IS NOT NULL THEN
    COALESCE(
      procedure.proacl,
      pg_catalog.acldefault('f', procedure.proowner)
    )::text
  END AS effective_defaulted_function_acl,
  procedure.proowner AS owner_role_oid,
  pg_catalog.pg_get_userbyid(procedure.proowner) AS function_owner,
  owner_role.rolsuper AS owner_is_superuser,
  owner_role.rolinherit AS owner_role_inherits_memberships,
  owner_role.rolcreaterole AS owner_can_create_roles,
  owner_role.rolcreatedb AS owner_can_create_databases,
  owner_role.rolcanlogin AS owner_can_login,
  owner_role.rolreplication AS owner_can_replicate,
  owner_role.rolbypassrls AS owner_bypasses_rls
FROM resolved
LEFT JOIN pg_catalog.pg_proc AS procedure
  ON procedure.oid = resolved.function_oid
LEFT JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = procedure.pronamespace
LEFT JOIN pg_catalog.pg_roles AS owner_role
  ON owner_role.oid = procedure.proowner
ORDER BY resolved.expected_identity_signature;
```

Expected collection shape: exactly 18 rows. Every row must have inventory_status = PRESENT, security_definer = true, a non-NULL catalog identity signature, a non-NULL function_owner, and populated owner-role attributes. A missing signature, missing owner role, or non-SECURITY DEFINER result is a stop condition, not an invitation to omit the row. Do not infer or normalize owner names from CI, SQL Editor, or migration-runner identities.

The `function_settings_search_path` column is the exact `proconfig` setting array, not a reconstructed effective path. The ACL columns distinguish an explicitly stored ACL from PostgreSQL's default ACL when `proacl` is NULL. These are function ACLs, not role memberships.

### Query 8B — direct and transitive memberships of function owners

This query derives membership paths from the owner roles returned by Query 8A. It distinguishes membership existence from privileges available through inheritance and from the ability to SET ROLE. PostgreSQL evaluates the effective results with `pg_has_role`; the path columns expose each direct/transitive membership edge and its INHERIT/SET options.

```sql
WITH RECURSIVE expected(signature) AS (
  VALUES
    ('public.is_admin()'),
    ('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)'),
    ('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)'),
    ('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)'),
    ('public.record_delivery_provider_event(text,text,text,text,text)'),
    ('public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)'),
    ('public._record_delivery_provider_integrity_conflict(text,text,text,text,text,text,text,timestamptz,text,text,text,text,text,timestamptz,text,text,text)'),
    ('public._record_delivery_provider_lifecycle_event_pre037_impl(text,text,text,text,timestamptz,text,text,text,text)'),
    ('public._record_delivery_provider_suppression_event_pre037_impl(text,text,text,text,text,text,timestamptz,timestamptz,text)'),
    ('public._deny_delivery_provider_integrity_audit_mutation()'),
    ('public.admin_list_delivery_provider_integrity_conflicts(text,integer)'),
    ('public.admin_list_delivery_provider_integrity_evidence(bigint,integer)'),
    ('public.admin_list_delivery_provider_integrity_history(bigint,integer)'),
    ('public.admin_resolve_delivery_provider_integrity_conflict(bigint,text)'),
    ('public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamptz,bigint)'),
    ('public.admin_get_delivery_provider_integrity_conflict(bigint)'),
    ('public.admin_list_delivery_provider_integrity_evidence_page(bigint,integer,timestamptz,bigint)'),
    ('public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)')
),
function_owners AS (
  SELECT DISTINCT
    procedure.proowner AS owner_oid,
    pg_catalog.pg_get_userbyid(procedure.proowner) AS function_owner
  FROM expected
  JOIN pg_catalog.pg_proc AS procedure
    ON procedure.oid = pg_catalog.to_regprocedure(expected.signature)
  WHERE procedure.prosecdef IS TRUE
),
membership_walk(
  owner_oid,
  function_owner,
  granted_role_oid,
  depth,
  role_path,
  inherit_path,
  set_path
) AS (
  SELECT
    function_owners.owner_oid,
    function_owners.function_owner,
    membership.roleid,
    1,
    ARRAY[function_owners.owner_oid, membership.roleid]::oid[],
    ARRAY[membership.inherit_option]::boolean[],
    ARRAY[membership.set_option]::boolean[]
  FROM function_owners
  JOIN pg_catalog.pg_auth_members AS membership
    ON membership.member = function_owners.owner_oid

  UNION ALL

  SELECT
    membership_walk.owner_oid,
    membership_walk.function_owner,
    membership.roleid,
    membership_walk.depth + 1,
    membership_walk.role_path || membership.roleid,
    membership_walk.inherit_path || membership.inherit_option,
    membership_walk.set_path || membership.set_option
  FROM membership_walk
  JOIN pg_catalog.pg_auth_members AS membership
    ON membership.member = membership_walk.granted_role_oid
  WHERE NOT membership.roleid = ANY(membership_walk.role_path)
)
SELECT
  membership_walk.function_owner,
  granted_role.rolname AS granted_role,
  membership_walk.depth,
  membership_walk.depth = 1 AS is_direct_membership,
  ARRAY(
    SELECT path_role.rolname
    FROM unnest(membership_walk.role_path) WITH ORDINALITY AS path(role_oid, position)
    JOIN pg_catalog.pg_roles AS path_role ON path_role.oid = path.role_oid
    ORDER BY path.position
  ) AS membership_path,
  ARRAY(
    SELECT pg_catalog.jsonb_build_object(
      'role', path_role.rolname,
      'rolsuper', path_role.rolsuper,
      'rolinherit', path_role.rolinherit,
      'rolcreaterole', path_role.rolcreaterole,
      'rolcreatedb', path_role.rolcreatedb,
      'rolcanlogin', path_role.rolcanlogin,
      'rolreplication', path_role.rolreplication,
      'rolbypassrls', path_role.rolbypassrls
    )
    FROM unnest(membership_walk.role_path) WITH ORDINALITY AS path(role_oid, position)
    JOIN pg_catalog.pg_roles AS path_role ON path_role.oid = path.role_oid
    ORDER BY path.position
  ) AS membership_path_role_attributes,
  membership_walk.inherit_path AS membership_edge_inherit_options,
  membership_walk.set_path AS membership_edge_set_options,
  pg_catalog.pg_has_role(
    membership_walk.owner_oid, membership_walk.granted_role_oid, 'MEMBER'
  ) AS owner_is_member,
  pg_catalog.pg_has_role(
    membership_walk.owner_oid, membership_walk.granted_role_oid, 'USAGE'
  ) AS owner_inherits_privileges,
  pg_catalog.pg_has_role(
    membership_walk.owner_oid, membership_walk.granted_role_oid, 'SET'
  ) AS owner_can_set_role,
  granted_role.rolsuper AS granted_role_is_superuser,
  granted_role.rolinherit AS granted_role_inherits_memberships,
  granted_role.rolcreaterole AS granted_role_can_create_roles,
  granted_role.rolcreatedb AS granted_role_can_create_databases,
  granted_role.rolcanlogin AS granted_role_can_login,
  granted_role.rolreplication AS granted_role_can_replicate,
  granted_role.rolbypassrls AS granted_role_bypasses_rls
FROM membership_walk
JOIN pg_catalog.pg_roles AS granted_role
  ON granted_role.oid = membership_walk.granted_role_oid
ORDER BY membership_walk.function_owner, membership_walk.depth, granted_role.rolname;
```

An owner with no memberships produces no rows; preserve that as an empty membership result, not as missing owner evidence. Retain every direct and transitive path, including multiple paths to the same granted role. Review privileged memberships even when `owner_inherits_privileges` is false, because `owner_can_set_role` may still be true. The per-edge options and effective `pg_has_role` results must be considered together. Query 1 describes the audit connection only; these owner-prefixed columns describe the actual function-owner roles.

### Cycle 363 — DBA collection and approval procedure

1. The Production owner/operator independently verifies that the selected Supabase Dashboard project reference is exactly `xaipiovflxomcbfwtwmu`. Do not use a project name alone or infer the target from a database hostname.
2. The DBA provides an approved, dedicated audit identity and an enforced read-only connection. Do not use `postgres`, `service_role`, `supabase_admin`, a service-role key, or an identity with migration/deployment authority.
3. Run Query 1 first. Confirm the database/project context through the independent dashboard check, confirm `transaction_read_only = on`, record the server version, and review the audit connection's own role attributes. Stop if the connection is not enforced read-only or has unexpected privilege.
4. Run Query 8A and Query 8B individually. Preserve the exact SQL, execution timestamps, project reference, query results, and row counts in the access-controlled Production evidence location. Do not paste credentials, connection URIs, or tokens into the report.
5. Confirm Query 8A returns exactly 18 rows and that every row reports PRESENT, SECURITY DEFINER true, a resolved function owner, search-path configuration, ACL, and owner role attributes. Investigate every missing or mismatched row; do not silently drop it.
6. Review Query 8B for direct and transitive privileged memberships, inherited privileges, and SET ROLE paths. Distinguish these findings from Query 1's audit-connection attributes and from CI or migration execution identities.
7. The Production DBA/security owner explicitly approves the per-signature expected owner mapping for all 18 functions, the acceptable owner-role attribute profile, and any permitted membership/SET ROLE paths. The four migration-038 administrator RPCs require an explicit owner decision; do not assume their owner from the identity that happened to run a migration.
8. Record the approver, approval timestamp, target project reference, evidence location, and exact per-signature mapping in the protected evidence record. Publish only the approval reference and non-sensitive disposition in the PR. No Production DDL is part of this collection procedure.

The collection queries are SELECT-only. They do not establish migration application status and must not be used to infer that migration 038 has or has not run. The owner contract must be approved before a later implementation adds expected-owner checks or owner-drift fixtures. Until then, migration 038 remains unchanged and no owner identity is hardcoded.

### Query 9 — trigger definitions and attachment points

~~~sql
SELECT
  namespace.nspname AS schema_name,
  relation.relname AS relation_name,
  trigger_info.tgname AS trigger_name,
  trigger_info.tgenabled AS enabled_state,
  trigger_info.tgisinternal AS is_internal,
  trigger_info.tgfoid::regprocedure::text AS trigger_function,
  pg_catalog.pg_get_triggerdef(trigger_info.oid, true) AS trigger_definition
FROM pg_catalog.pg_trigger AS trigger_info
JOIN pg_catalog.pg_class AS relation
  ON relation.oid = trigger_info.tgrelid
JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = relation.relnamespace
WHERE namespace.nspname = ANY (
  ARRAY['public', 'auth', 'storage', 'extensions', 'supabase_migrations']
)
ORDER BY namespace.nspname, relation.relname, trigger_info.tgname;
~~~

### Query 10 — RLS policies and expressions

~~~sql
SELECT
  policy.schemaname AS schema_name,
  policy.tablename AS table_name,
  policy.policyname AS policy_name,
  policy.permissive AS permissive_mode,
  policy.roles AS policy_roles,
  policy.cmd AS command,
  policy.qual AS using_expression,
  policy.with_check AS with_check_expression
FROM pg_catalog.pg_policies AS policy
WHERE policy.schemaname = ANY (
  ARRAY['public', 'auth', 'storage', 'extensions', 'supabase_migrations']
)
ORDER BY policy.schemaname, policy.tablename, policy.policyname;
~~~

### Query 11 — effective relation ACL entries

~~~sql
SELECT
  namespace.nspname AS schema_name,
  relation.relname AS relation_name,
  CASE
    WHEN acl_entry.grantee = 0 THEN 'PUBLIC'
    ELSE pg_catalog.pg_get_userbyid(acl_entry.grantee)
  END AS grantee,
  pg_catalog.pg_get_userbyid(acl_entry.grantor) AS grantor,
  acl_entry.privilege_type AS privilege,
  acl_entry.is_grantable AS grantable
FROM pg_catalog.pg_class AS relation
JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = relation.relnamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(
  COALESCE(relation.relacl, pg_catalog.acldefault('r', relation.relowner))
) AS acl_entry
WHERE namespace.nspname = ANY (
  ARRAY['public', 'auth', 'storage', 'extensions', 'supabase_migrations']
)
  AND relation.relkind IN ('r', 'p', 'v', 'm', 'f')
ORDER BY namespace.nspname, relation.relname, grantee, privilege;
~~~

### Query 12 — schema ACL entries

~~~sql
SELECT
  namespace.nspname AS schema_name,
  CASE
    WHEN acl_entry.grantee = 0 THEN 'PUBLIC'
    ELSE pg_catalog.pg_get_userbyid(acl_entry.grantee)
  END AS grantee,
  pg_catalog.pg_get_userbyid(acl_entry.grantor) AS grantor,
  acl_entry.privilege_type AS privilege,
  acl_entry.is_grantable AS grantable
FROM pg_catalog.pg_namespace AS namespace
CROSS JOIN LATERAL pg_catalog.aclexplode(
  COALESCE(namespace.nspacl, pg_catalog.acldefault('n', namespace.nspowner))
) AS acl_entry
WHERE namespace.nspname = ANY (
  ARRAY['public', 'auth', 'storage', 'extensions', 'supabase_migrations']
)
ORDER BY namespace.nspname, grantee, privilege;
~~~

### Query 13 — routine EXECUTE ACL entries

~~~sql
SELECT
  namespace.nspname AS schema_name,
  procedure.proname AS routine_name,
  pg_catalog.pg_get_function_identity_arguments(procedure.oid) AS identity_arguments,
  CASE
    WHEN acl_entry.grantee = 0 THEN 'PUBLIC'
    ELSE pg_catalog.pg_get_userbyid(acl_entry.grantee)
  END AS grantee,
  pg_catalog.pg_get_userbyid(acl_entry.grantor) AS grantor,
  acl_entry.privilege_type AS privilege,
  acl_entry.is_grantable AS grantable
FROM pg_catalog.pg_proc AS procedure
JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = procedure.pronamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(
  COALESCE(procedure.proacl, pg_catalog.acldefault('f', procedure.proowner))
) AS acl_entry
WHERE namespace.nspname = ANY (
  ARRAY['public', 'auth', 'storage', 'extensions', 'supabase_migrations']
)
  AND procedure.prokind IN ('f', 'p')
ORDER BY namespace.nspname, procedure.proname, identity_arguments,
         grantee, privilege;
~~~

### Query 14 — default privileges affecting relevant schemas

~~~sql
SELECT
  CASE
    WHEN default_acl.defaclnamespace = 0 THEN '(all schemas)'
    ELSE namespace.nspname
  END AS schema_scope,
  pg_catalog.pg_get_userbyid(default_acl.defaclrole) AS object_creator_role,
  default_acl.defaclobjtype AS object_type,
  CASE
    WHEN acl_entry.grantee = 0 THEN 'PUBLIC'
    ELSE pg_catalog.pg_get_userbyid(acl_entry.grantee)
  END AS grantee,
  acl_entry.privilege_type AS privilege,
  acl_entry.is_grantable AS grantable
FROM pg_catalog.pg_default_acl AS default_acl
LEFT JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = default_acl.defaclnamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(default_acl.defaclacl) AS acl_entry
WHERE default_acl.defaclnamespace = 0
   OR namespace.nspname = ANY (
     ARRAY['public', 'auth', 'storage', 'extensions', 'supabase_migrations']
   )
ORDER BY schema_scope, object_creator_role, object_type, grantee, privilege;
~~~

### Query 15 — installed extensions and their namespaces

~~~sql
SELECT
  extension.extname AS extension_name,
  extension.extversion AS extension_version,
  namespace.nspname AS extension_schema,
  extension.extrelocatable AS relocatable,
  pg_catalog.pg_get_userbyid(extension.extowner) AS extension_owner
FROM pg_catalog.pg_extension AS extension
JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = extension.extnamespace
ORDER BY extension.extname;
~~~

### Query 16 — migration-history relation existence

~~~sql
SELECT
  to_regclass('supabase_migrations.schema_migrations') AS migration_history_relation;
~~~

If Query 16 returns NULL, do not run Queries 17 or 18. Record the relation as not visible/not found for this audit identity, not proof that no migrations ran. Permission visibility and historical/manual execution records must be investigated by the owner; Production classifications remain UNKNOWN.

### Query 17 — migration-history rows (only after Query 16 confirms the relation)

~~~sql
SELECT
  to_jsonb(migration_row) ->> 'version' AS version,
  to_jsonb(migration_row) ->> 'name' AS migration_name,
  to_jsonb(migration_row) ->> 'created_at' AS recorded_at
FROM supabase_migrations.schema_migrations AS migration_row
ORDER BY version, migration_name, recorded_at;
~~~

This intentionally does not return a statements/body column. Query 5 and Query 6 include the schema, columns, and constraints of the history table. Preserve all returned rows, including repeated/conflicting versions. A missing row does not prove non-execution because SQL Editor/manual execution may not have written migration history.

### Query 18 — exact history records for duplicate version 007

~~~sql
SELECT
  to_jsonb(migration_row) ->> 'version' AS version,
  to_jsonb(migration_row) ->> 'name' AS migration_name,
  to_jsonb(migration_row) ->> 'created_at' AS recorded_at
FROM supabase_migrations.schema_migrations AS migration_row
WHERE to_jsonb(migration_row) ->> 'version' = '202607260007'
ORDER BY migration_name, recorded_at;
~~~

A single history row for 202607260007 cannot identify which of the two source SQL bodies ran, and cannot prove both ran. Two history rows may be impossible under a unique version key, but any observed result must be preserved exactly rather than normalized.

## 5. Focused evidence for the duplicate 007 collision

The current source inventory contains two distinct files with version prefix 202607260007:

| Source body | Exact source filename | Git blob SHA |
|---|---|---|
| Sprint 6 | 202607260007_sprint6_daily_deedlight.sql | e0c2379255003b8c7bc85a1fab781e23051f5e47 |
| Sprint 7 | 202607260007_sprint7_pwa_daily_engagement.sql | 8b051cfce05ea75b1ee7a726864e2ad760f6fe5f |

Their source-level signatures differ:

- Sprint 6 creates/extends the legacy daily_posts and daily_reflections shape, including daily_post_id, reflection_text, did_today_deed, mood_label, is_private, the daily_reflections_unique_user_post constraint, timestamp triggers, and underscore-named administrator-readable reflection policies.
- Sprint 7 creates daily_lights and adds daily_light_id, user_id, reflection, intention, the daily_reflections_daily_light_user_unique constraint, and space-named administrator-readable reflection policies.
- Migration 008 requires daily_lights from Sprint 7.
- Migration 012 depends on both 007 bodies and later changes daily_reflections.daily_post_id to nullable while adding daily_reflections_has_daily_source. Therefore current nullability of daily_post_id cannot identify whether Sprint 6 ran.
- Migration 013 depends on daily_lights and saved_lights; it has no direct SQL dependency on 012.

Queries 4–7, 9–10, and 17–18 provide the metadata needed to compare current object shape and history. In particular, filter their results for public.daily_posts, public.daily_lights, public.daily_reflections, public.daily_deed_completions, and public.saved_lights.

The retained isolated PostgreSQL/Supabase CLI tests recorded two order-sensitive cases: Sprint 6 then Sprint 7 reaches schema execution but collides on the second 202607260007 history insert (SQLSTATE 23505); Sprint 7 then Sprint 6 fails because daily_reflections.daily_post_id is absent (SQLSTATE 42703), rolling back Sprint 6's transaction. These are disposable-database results, not Production evidence.

Do not infer the execution identity of either 007 file from the version row, a subset of current columns, a constraint name, or a successful CI run. Resolve the collision only with full object-level evidence plus retained Production SQL Editor/deployment/audit records and independent review.

## 6. Focused verification of migration 036 effects

Migration 036 source blob is 61a1fbf48b4557873ba6016e74fd3995bc62ba14 for 202611230036_private_daily_reflection_admin_isolation.sql. It is a policy/ACL correction on public.daily_reflections; it has no SQL dependency on migration 035 or the delivery chain.

Use the results from Queries 4, 5, 6, 8, 9, 10, 11, and 13 to verify the following live effects:

1. public.daily_reflections exists and RLS is enabled.
2. The active SELECT policy is owner-only: authenticated members can select rows only where user_id = auth.uid(). No surviving permissive administrator-readable SELECT policy may remain under either historical naming variant.
3. The INSERT policy checks user_id = auth.uid().
4. The UPDATE policy applies user_id = auth.uid() to both USING and WITH CHECK.
5. No administrator DELETE policy remains; no browser DELETE policy or table DELETE grant exists.
6. The effective relation ACL has no PUBLIC or anon table privileges. authenticated has SELECT, INSERT, UPDATE only. service_role retains the trusted server-side grant.
7. The direct definition of public.admin_get_member_context does not mention daily_reflections; the source migration 011 intentionally excludes reflection content from that moderation projection.
8. The admin moderation projection remains narrow. This catalog packet does not execute the RPC or return member context.

### Query 19 — effective daily_reflections privileges by browser/server role

Run only if Query 4 confirms public.daily_reflections exists.

~~~sql
SELECT
  role_info.rolname AS role_name,
  has_table_privilege(role_info.oid, relation.oid, 'SELECT') AS can_select,
  has_table_privilege(role_info.oid, relation.oid, 'INSERT') AS can_insert,
  has_table_privilege(role_info.oid, relation.oid, 'UPDATE') AS can_update,
  has_table_privilege(role_info.oid, relation.oid, 'DELETE') AS can_delete,
  has_table_privilege(role_info.oid, relation.oid, 'TRUNCATE') AS can_truncate,
  has_table_privilege(role_info.oid, relation.oid, 'REFERENCES') AS can_reference,
  has_table_privilege(role_info.oid, relation.oid, 'TRIGGER') AS can_create_trigger
FROM pg_catalog.pg_roles AS role_info
CROSS JOIN pg_catalog.pg_class AS relation
JOIN pg_catalog.pg_namespace AS namespace
  ON namespace.oid = relation.relnamespace
WHERE role_info.rolname IN ('anon', 'authenticated', 'service_role')
  AND namespace.nspname = 'public'
  AND relation.relname = 'daily_reflections'
ORDER BY role_info.rolname;
~~~

The expected effective table privileges are:

| Role | SELECT | INSERT | UPDATE | DELETE |
|---|---:|---:|---:|---:|
| anon | false | false | false | false |
| authenticated | true | true | true | false |
| service_role | true | true | true | true |

The ACL expansion query is also required because it exposes PUBLIC grants and grant options. The expected table ACL for service_role is the migration's trusted ALL grant; do not interpret that grant as permission for browser clients. If role names are absent or results differ, stop and escalate. Do not repair the ACL during this audit.

The owner-only RLS policy is what prevents an administrator using the authenticated browser role from reading another member's reflection. The fact that authenticated has SELECT/UPDATE at the table ACL layer is expected and is not itself a cross-member authorization failure. The policy expressions and effective role privileges must be reviewed together.

## 7. Secure evidence capture and source comparison

For each query, preserve:

- Exact query text and packet version.
- UTC execution timestamp and SQL Editor/query-run identifier, if supplied by the platform.
- Confirmed project reference, database name, server version, host/port metadata, and audit role. Store endpoint metadata only in the restricted evidence location.
- Raw result export and row count, with no manual alteration. Record when a query is unavailable or permission-denied.
- The identity of the Production owner/operator who confirmed the target and the independent reviewer who later assesses the evidence.

Store the packet and outputs only in the Production owner's approved access-controlled evidence location. Do not attach raw catalog output to a public issue, public PR, chat, or broad team channel. Do not include connection strings, passwords, access tokens, service-role keys, JWT secrets, application-member rows, or private reflections. If an output unexpectedly contains member data or a secret, stop, restrict access, and follow the organization's incident/data-handling process rather than sharing it.

Compare the results with the exact 37-row inventory in PRODUCTION_MIGRATION_RECONCILIATION.md at source HEAD c4be798d1a4e0d6e4799085b818572038028d0bb and tree 782ebae456df6190b0d347bb01ad917ed30220fd. The inventory has 36 unique filename version prefixes because of the two separate 007 files. For each source file/blob, map every expected table, column, constraint, index, function, trigger, view, policy, grant, extension, and schema effect to the corresponding catalog result. Record missing, additional, or differing objects individually; do not hide partial drift behind a single file-level status.

For 007, map the Sprint 6 and Sprint 7 signatures separately and correlate them with preserved SQL Editor history, deployment logs, and approved change records. For 036, compare the exact policy expressions and effective ACLs, not only policy names or the presence of the migration-history version.

The aggregate SQL Editor bundle is not a migration execution record and is not a byte-for-byte replay of every early migration. A matching aggregate fingerprint or a version row alone is insufficient to identify a migration body.

## 8. Classification and stop conditions

**Current state remains UNKNOWN for all 37 files and every independently identifiable Production effect.** This packet was authored from repository source and has not been run against Production. Do not update classifications based on source, disposable PostgreSQL tests, CI, or this document.

After the owner collects the evidence, the reconciliation owner and independent database/security reviewer must jointly assess the complete history, catalogs, audit records, and source effect matrix. Until then:

- Do not classify a migration as applied, recorded-but-unverified, represented-but-unrecorded, or unapplied.
- Do not mark either 007 body as applied based on the shared version alone.
- Do not infer absence from missing history or permission-denied results.
- Do not apply migration 036, repair migration history, or resume normal Production supabase db push.
- Keep Production NO-GO and retain existing delivery/scheduler controls.

Stop immediately if the target reference is uncertain, transaction_read_only is off, the audit role has elevated/inherited authority, any query requires a write privilege, catalog/history access is incomplete, or query output includes application-member data or credentials. Escalate to the Production owner; do not broaden permissions or improvise a fallback.

## 9. Execution record for this packet

- Repository inspection and source inventory comparison: performed through GitHub read-only APIs.
- SQL packet authoring: performed; all authored query blocks are SELECT statements.
- Production connection or SQL execution: **not performed**.
- Credentials, role grants, migration history, schema, scheduler, or delivery settings: **not accessed or changed**.
- Independent security/database acceptance: **not performed**.
- Production migration classifications: **37 UNKNOWN; Production NO-GO**.


## Cycle 342 — read-only access attempt record

**Review date:** 2026-11-23  
**Implementation HEAD inspected before Cycle 342 documentation-only evidence commits:** c939d4a24293342deb6161eab2f28fb66765a237  
**Implementation tree inspected:** e321be2b406043b01c4ed4dd4cda003c54dbdd0e

The packet remains a prepared procedure; it was not executed against Production.

The currently connected Supabase integrations were checked for the target project reference `xaipiovflxomcbfwtwmu`:

- `list_projects` through both connected accounts did not return the target project.
- `get_project`, `list_migrations`, and `list_tables` were each attempted against the exact target project through both accounts. All attempts were denied with `MCP error -32600: You do not have permission to perform this action`.
- A SELECT-only database identity and migration-history-presence query through `execute_sql` was attempted through both accounts. Both attempts were denied with the same permission error; no SQL ran and no database result was returned.

**Evidence consequence:** no Production database identity was established, and no Production migration-history, schema/constraint, RLS/grant, function/trigger, duplicate-007 execution, or migration-036 application evidence was collected. A permission denial is not evidence of an empty history, absent schema, absent migration, or non-execution.

**Exact missing dependency:** the Production owner/administrator must grant an existing connected identity project-scoped read-only access to project `xaipiovflxomcbfwtwmu`, or provide an approved dedicated read-only PostgreSQL connection after independently verifying the Production project reference. Use the least-privilege role and enforced read-only session defined in Sections 2–3 above. Do not grant service-role, administrator, migration, schema-write, credential-management, or outbound-delivery authority for this audit.

No credentials were requested, transmitted, or modified. No Production connection was established. No query in Sections 4–6 was executed. No Production data, schema, migration history, migration, scheduler, provider, or delivery setting was read or changed.

The previous C404 denial record and the C247 disposable PostgreSQL/Supabase CLI evidence remain historical evidence with their existing scope; this access attempt does not duplicate or upgrade those results to Production evidence.\n\nThe two Cycle 342 evidence-document commits were subsequently validated by exact-head push run [45193172482](https://github.com/ADRN-9/deedlight/actions/runs/45193172482), SUCCESS, 8/8 jobs, at documentation-only branch HEAD `45346482af0ffbb5fa8e3ce29feb6bbf5c937f39`. This validates the documentation-only update, not Production state.


---

## Cycle 378 — Production ownership evidence acceptance checklist

**Status: NOT RECEIVED / NOT VERIFIED / NOT APPROVED.** This section defines the evidence gate; it does not attest that Production queries have run. No Production connection, SQL execution, schema change, migration-history operation, role mutation, or credential access was performed for this cycle.

The ownership evidence is a separate acceptance gate from the general migration-history audit. Do not infer ownership from the repository's synthetic PostgreSQL fixtures or from the historical source snapshot at the top of this document.

### A. Provenance and collection controls

The evidence custodian must retain all of the following before any owner mapping is considered:

- [ ] Exact Production Supabase project reference independently verified in the dashboard as `xaipiovflxomcbfwtwmu`; include a protected evidence reference to the dashboard/environment record, not a credential or connection string.
- [ ] Collection timestamp in ISO 8601 with timezone, collector's full name and role, and the approved read-only audit identity.
- [ ] PostgreSQL server version recorded by Query 1; it must be PostgreSQL 16 or newer for the membership edge options in Query 8B.
- [ ] Query 1 proves the connection is read-only and the audit identity is not superuser, CREATEROLE, CREATEDB, REPLICATION, BYPASSRLS, CREATE-capable, or a member of privileged roles. Stop if the least-privilege boundary is not proven.
- [ ] Exact Query 8A and Query 8B text/version used, with a SHA-256 digest or immutable repository commit reference.
- [ ] Original, unedited result exports stored in an approved access-controlled evidence location. Record immutable object/version IDs and cryptographic hashes in the approval record. Do not attach credentials, connection URIs, member data, provider payloads, or tokens.
- [ ] Result row counts, export format, export timestamp, and collector attestation retained separately from the export itself.
- [ ] Evidence retention and access policy identified; access restricted to the named DBA, security approvers and authorized reviewers.

A screenshot alone is not sufficient. Screenshots may supplement, but never replace, complete machine-readable result exports and their row counts.

### B. Query 8A acceptance — exactly 18 functions

- [ ] Query 8A completed successfully against the independently verified Production target.
- [ ] Exactly **18 rows** returned — not 17, 19, or an inferred count from a truncated display.
- [ ] All 18 `expected_identity_signature` values match the exact documented inventory, one each, with no duplicate, missing or unexpected signature.
- [ ] Every row has `inventory_status = PRESENT`, `security_definer = true`, a non-NULL catalog identity signature, and a resolvable owner role.
- [ ] For every function, retain the exact `function_owner`, owner OID, `owner_is_superuser`, `owner_role_inherits_memberships`, `owner_can_create_roles`, `owner_can_create_databases`, `owner_can_login`, `owner_can_replicate`, and `owner_bypasses_rls` values.
- [ ] Retain `function_settings_search_path`, `explicit_function_acl`, and `effective_defaulted_function_acl` for each function; do not conflate function ACLs with role memberships.
- [ ] Any missing function, missing owner, non-SECURITY-DEFINER function, NULL/unavailable owner attribute, unexpected signature or export truncation is a hard rejection.

The accepted inventory must be keyed by the full exact identity signature, not by function name alone. No owner value may be inferred from a migration author, CI role, SQL Editor role, application role, or prior environment.

### C. Query 8B acceptance — complete membership graph

- [ ] Query 8B completed successfully, with the exact query text/version retained.
- [ ] Preserve the complete, untruncated result. The SQL Editor preview, first page, copied visible rows or partial CSV is not sufficient.
- [ ] Record the exact returned row count and prove the export contains every row.
- [ ] For every owner found in Query 8A, retain every direct and transitive membership path returned by Query 8B, including multiple distinct paths to the same granted role.
- [ ] Preserve `function_owner`, `granted_role`, `depth`, `is_direct_membership`, `membership_path`, `membership_edge_inherit_options`, `membership_edge_set_options`, `owner_is_member`, `owner_inherits_privileges`, and `owner_can_set_role`.
- [ ] Preserve every returned granted-role attribute: superuser, inherit, create-role, create-database, login, replication and bypass-RLS.
- [ ] Review each path edge and every role node, not only the final granted role. A non-inheriting edge does not establish that SET ROLE is unavailable.
- [ ] Reconcile every Query 8B `function_owner` to the distinct owner set from all 18 Query 8A rows. Query 8B is keyed by distinct owner roles; it is not expected to repeat one membership graph per function.
- [ ] Retain all rows even when multiple paths lead to the same role. Do not deduplicate paths by owner/granted-role pair.

**Required interpretation of an empty Query 8B result:** Query 8B naturally returns zero rows when no function-owner role has any direct or transitive memberships. A successful, complete execution with an independently verified row count of zero is valid evidence of an empty owner-membership graph. It is not missing evidence and must not be silently replaced by an assumed default. The collector must explicitly attest: (1) Query 8A passed the exact 18-row acceptance gate; (2) Query 8B executed successfully against the same verified database/session; (3) the complete export contains zero data rows and the query tool reports successful completion; (4) all distinct Query 8A owners were reconciled; and (5) the result is intentionally interpreted as no membership paths for those owners. A failed query, unavailable result, empty clipboard, blank screenshot, truncated export, or missing owner reconciliation is **UNKNOWN**, never an accepted empty result. Preserve a zero-row export/manifest and execution metadata so that emptiness is auditable.

### D. Explicit owner and membership approvals

No global or blanket approval is sufficient. The authorized approvers must approve **each of the 18 exact signatures**, even where multiple functions share the same owner.

For each signature, the approval register must contain:

- [ ] Exact identity signature and observed owner role name.
- [ ] All Query 8A owner attributes and the exact approved value for each attribute.
- [ ] Explicit decision: APPROVE or REJECT this owner for this exact function signature.
- [ ] DBA approver's full name, organizational role, approval timestamp with timezone, and durable approval reference.
- [ ] Security approver's full name, organizational role, approval timestamp with timezone, and durable approval reference.
- [ ] Linkage to immutable Query 8A evidence object/version and hash.

For each distinct owner role, separately approve its complete Query 8B membership graph:

- [ ] Every permitted direct and transitive path, in exact role order.
- [ ] Every edge's INHERIT and SET option.
- [ ] Effective MEMBER, inherited privilege/USAGE, and SET results.
- [ ] All role attributes on each membership path.
- [ ] Explicit decision on an empty membership graph, where applicable.
- [ ] Any disallowed path or privileged membership, with rejection rationale.
- [ ] Named DBA and security approvers, their roles, approval timestamps/timezones, and protected evidence references.

An owner or path is not approved because an approver approved another function with the same owner. The register must make the per-signature approval explicit and separately identify the shared owner-role membership approval. Approval must be affirmative and recorded; silence, missing names, chat-only acknowledgement, or an undocumented verbal statement is not approval.

### E. Acceptance decision and fail-closed rules

The evidence custodian and independent reviewer must sign a final completeness decision:

- [ ] 18/18 exact Query 8A signatures accepted.
- [ ] Query 8B complete and reconciled, including explicit accepted-empty interpretation if row count is zero.
- [ ] 18/18 explicit owner decisions approved by both named approvers.
- [ ] Every distinct owner membership graph explicitly approved by both named approvers.
- [ ] No unresolved privileged owner attributes, privileged membership paths, unapproved role flags, missing evidence, or ambiguous query outcomes.
- [ ] Evidence hashes and immutable protected references verified by a reviewer other than the collector.
- [ ] Independent security acceptance and Production DBA acceptance recorded.

Any unchecked item means **OWNERSHIP EVIDENCE NOT ACCEPTED**. Do not author an expected-owner baseline, modify migration 038, apply a migration, or run an enforcement deployment until all gates are satisfied. A subsequent source change still requires independent review and exact-head CI. This checklist does not authorize Production operations.

### F. Cycle 378 collection status

| Evidence item | Status |
|---|---|
| Production target independently connected | NOT PERFORMED |
| Production Query 8A (18 rows) | NOT RECEIVED |
| Production Query 8B complete output | NOT RECEIVED |
| Query 8B empty-result attestation | NOT RECEIVED |
| Per-function owner approvals (18/18) | NOT RECEIVED |
| Per-owner membership approvals | NOT RECEIVED |
| Named DBA/security approvers and timestamps | NOT RECEIVED |
| Protected evidence references and hashes | NOT RECEIVED |
| Independent acceptance | NOT PERFORMED |

**Disposition: OUTSTANDING. Production remains NO-GO.** The absence of authorized evidence is not evidence that the Production ownership graph is empty or safe.


---

## Cycle 380 — Production ownership evidence acquisition result

**Collection date:** 2026-11-24  
**Collection time:** 2026-11-24T13:22:00-08:00 (21:22:00Z), recorded from the task session's supplied local clock  
**Collector:** DeedLight engineering agent, Cycle 380  
**Disposition:** ACCESS NOT AUTHORIZED / EVIDENCE NOT COLLECTED / PRODUCTION NO-GO

### 1. Supabase connector discovery

The available connected Supabase accounts were inspected using the read-only project-list operation:

| Connected account | Projects returned | DeedLight Production project found |
|---|---|---|
| Primary | `vxsgfzybbwitmkgovkjx` — HelpMeToHoliday-Staging (INACTIVE) | No |
| GiftPary supabase | `vnvpqullsrbyztkcyvzw` — admin@giftparty.org's Project (INACTIVE); `yrlzzsfgfpabdcypwvvk` — giftparty-staging (ACTIVE_HEALTHY) | No |

The previously documented DeedLight Production project reference is `xaipiovflxomcbfwtwmu`. It was not present in either connected account's project list.

A read-only project metadata lookup for `xaipiovflxomcbfwtwmu` was then attempted through each connected account. Both calls returned an explicit permission error: `MCP error -32600: You do not have permission to perform this action`.

### 2. Database access and evidence status

- [x] Connected Supabase account/project discovery attempted.
- [x] DeedLight Production project reference compared against both account project lists.
- [x] Read-only project metadata lookup attempted against both available account links.
- [x] Both metadata lookups explicitly denied for lack of permission.
- [ ] Authorized read-only Production DBA session established.
- [ ] Production read-only identity and its privilege restrictions verified.
- [ ] Production Query 8A executed and exported.
- [ ] Production Query 8B executed and exported.
- [ ] Exact 18-row Query 8A inventory verified.
- [ ] Every distinct owner reconciled against complete Query 8B membership output.
- [ ] Named DBA/security approvals collected for every owner, attribute and membership path.
- [ ] Immutable protected evidence references, hashes and approval timestamps collected.

**No Production SQL was executed.** In particular, `execute_sql` was not called against the Production project. The connector's available links do not establish authorized Production DBA access, and the explicit metadata permission denials preclude treating the project as accessible. No attempt was made to elevate permissions, switch identities, use another project, or obtain credentials.

The connector's project lists and metadata-denial responses are access-discovery evidence only. They are not Query 8A/8B evidence, do not establish the live schema, and do not establish an empty membership graph. No Query 8B output exists for this cycle; its state remains **NOT COLLECTED / UNKNOWN**, not zero rows.

### 3. Ownership approval status

No Production owner, role attribute or membership path can be approved from the available evidence. Consequently:

- Expected owner mapping: NOT ESTABLISHED.
- Approved owner attributes: NOT ESTABLISHED.
- Permitted direct/transitive membership paths: NOT ESTABLISHED.
- Explicit empty-graph approvals: NOT ESTABLISHED.
- Named Production DBA/security approvers and approval timestamps: NOT RECEIVED.
- Protected Production evidence references and cryptographic hashes: NOT RECEIVED.

The Cycle 378 acceptance checklist and future enforcement design remain the governing procedure. Synthetic PostgreSQL fixture identities remain test-only and must not be used as Production expectations.

### 4. GitHub preservation and exact-head evidence

Independently rechecked during Cycle 380:

- PR #22 remains OPEN / DRAFT / UNMERGED.
- Branch: `security/private-daily-journey-admin-isolation-c408`.
- HEAD remains `356decbc866fa156c8177b76d5b52c349a90138f`.
- Base: `security/delivery-transport-consent-gates` at `6a3660bbe2fd6beb2ddada43d5e77ff5ac9f3793`.
- Ancestry: 146 ahead, 0 behind.
- Exact-head workflow [45488857461](https://github.com/ADRN-9/deedlight/actions/runs/45488857461) remains completed SUCCESS on that exact SHA.
- Formal submitted reviews: 0.
- Audit checklist blob at starting HEAD: `0118d4c915a01e37a54e5c4c8bd31e69fe12c76d`.
- Enforcement design blob at starting HEAD: `2bfc80c2b2e65e9007c7bad4335d62822206b68a`.
- Migration 038 blob at starting HEAD: `38951751fc5abeb79b75c4e37e55da01262a18b8`.

No changes to migration 038, ownership tests, enforcement implementation, Production database, deployment or PR merge state were made for this evidence-acquisition cycle. The only repository change for Cycle 380 is this audit-status record.

### 5. Cycle 381 handoff and readiness decision

**Implementation readiness: BLOCKED — no authorized Production database access or authoritative ownership evidence.**

The next prerequisite is an explicitly authorized, least-privilege read-only Production DBA connection to project `xaipiovflxomcbfwtwmu`, or delivery by an authorized DBA of the complete, provenance-preserving Query 8A and Query 8B exports plus the privilege attestation and approvals. A project reference alone, an inaccessible connector, a staging database, or a synthetic fixture is not a substitute.

Once authorized access or evidence is supplied:
1. Verify target project identity and read-only session/role privileges before querying.
2. Collect exact Query 8A and Query 8B with complete exports and collection metadata.
3. Require exactly 18 exact Query 8A signatures and reconcile all distinct owners against all complete Query 8B paths and edge options.
4. Preserve a successful, explicitly attested zero-row Query 8B result if that is what the query returns; treat all failed, missing or partial results as UNKNOWN.
5. Obtain named DBA and security approvals for every signature-to-owner mapping, owner attribute, membership path and effective privilege, with timestamps/timezones and protected evidence references.
6. Have an independent reviewer verify provenance, completeness, hashes and approval coverage before authoring any expected-owner manifest.

Until every gate passes, do not implement expected-owner enforcement, modify migration 038, perform Production database operations, deploy or merge. Keep PR #22 OPEN / DRAFT / UNMERGED and Production NO-GO.


---

## Cycle 381 — Repository, migration and PR-governance reconciliation

**Verification date:** 2026-11-24  
**Verified repository:** `ADRN-9/deedlight`  
**Disposition:** REPOSITORY EVIDENCE RECOVERED; PRODUCTION OWNERSHIP EVIDENCE STILL BLOCKED

### 1. Recovered Cycle 380 execution evidence

Cycle 380's repository change is present in GitHub:

- Commit: [`f2e9bd71334a7413528088de27d4e6b1e15d3a3e`](https://github.com/ADRN-9/deedlight/commit/f2e9bd71334a7413528088de27d4e6b1e15d3a3e)
- Parent: `356decbc866fa156c8177b76d5b52c349a90138f`
- Commit message: `docs(security): record production ownership access blocker`
- Changed file: `docs/PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md` (Cycle 380 access-denial and evidence-gap record).
- Exact-head CI: [run 45490578964](https://github.com/ADRN-9/deedlight/actions/runs/45490578964), completed SUCCESS on exact SHA `f2e9bd71334a7413528088de27d4e6b1e15d3a3e`, all nine jobs successful.

This independently confirms the Cycle 380 repository work and its exact-head CI. The earlier Cycle 380 final response reported the CI as in progress because that was its last observation; GitHub now records it as completed SUCCESS.

### 2. Current PR #22 and ancestry

- PR #22: OPEN / DRAFT / UNMERGED.
- Head branch: `security/private-daily-journey-admin-isolation-c408`.
- Current verified HEAD before this Cycle 381 documentation update: `f2e9bd71334a7413528088de27d4e6b1e15d3a3e`.
- Base branch: `security/delivery-transport-consent-gates`.
- Base SHA: `6a3660bbe2fd6beb2ddada43d5e77ff5ac9f3793`.
- GitHub compare: 147 commits ahead, 0 behind; merge base equals the base SHA.
- PR metadata and paginated changed-file listing both report 30 changed files (before this Cycle 381 documentation update).

The live branch ref resolves to the same HEAD SHA as PR #22. No branch movement or force-push was observed.

### 3. Reconciliation of the historical Cycle 376/378/380 references

The reported commits are real and lie on the current PR #22 line:

- `5e4f6559a02f9e9772caf4b67ce1ae635eb15f74`: “docs(security): record final cycle 376 exact-head CI”.
- `356decbc866fa156c8177b76d5b52c349a90138f`: “docs(security): design approved function owner enforcement”; its parent is `d7a38f92e0367062698355e0ccb406fe1761b0a3`.
- `f2e9bd71334a7413528088de27d4e6b1e15d3a3e`: Cycle 380 access-blocker record; its parent is exactly `356decbc866fa156c8177b76d5b52c349a90138f`.

GitHub compare from `5e4f6559a02f9e9772caf4b67ce1ae635eb15f74` to `356decbc866fa156c8177b76d5b52c349a90138f` reports 2 commits ahead, 0 behind, and two documentation changes: the owner-enforcement design was added and the Production audit checklist was extended. This is consistent with the recorded cycle progression; these are successive revisions, not conflicting current HEAD claims.

### 4. Migration 038 integrity

Path: `supabase/migrations/202611240038_delivery_provider_integrity_lock_order_pagination.sql`

GitHub returned the same file blob SHA at all three relevant PR #22 revisions:

- `5e4f6559a02f9e9772caf4b67ce1ae635eb15f74`
- `356decbc866fa156c8177b76d5b52c349a90138f`
- `f2e9bd71334a7413528088de27d4e6b1e15d3a3e`

Blob SHA at each: `38951751fc5abeb79b75c4e37e55da01262a18b8`; file size returned: 43,748 bytes. The path-specific GitHub commit history returns nine commits touching this file; the latest listed path commit is `8220d3953a3b7f906fb52dd1946d4be450d5cc7d` (“fix(db): stabilize provider integrity case pagination”, 2026-11-24T16:58:36Z). The three later documentation checkpoints retain the same blob. Thus migration 038 was not modified by Cycle 380 or the present Cycle 381 repository verification.

**Important scope distinction:** GitHub returned NOT FOUND for this path at PR #22's base SHA `6a3660bbe2fd6beb2ddada43d5e77ff5ac9f3793`. The migration is part of PR #22's diff relative to PR #10's branch; it is not present at that base. “Unchanged” here means unchanged across the cited PR #22 checkpoints, not that the migration is already part of PR #10 or Production. No Production application is inferred.

### 5. PR #10 / #11 / #22 governance and merge targets

The live PR metadata establishes three different branch relationships:

| PR | Head | Base / target | State |
|---|---|---|---|
| #10 | `security/delivery-transport-consent-gates` at `6a3660bbe2fd6beb2ddada43d5e77ff5ac9f3793` | `main` at `ce82b3fdf1a73510de70e3729a487d4ae00e66e3` | OPEN / DRAFT / UNMERGED |
| #11 | `security/deedlight-audit-fixtures-c18` at `f5ed62e4417921c8bee1a376fed8bac35897e809` | `main` at `ce82b3fdf1a73510de70e3729a487d4ae00e66e3` | OPEN / DRAFT / UNMERGED |
| #22 | `security/private-daily-journey-admin-isolation-c408` at current PR HEAD | `security/delivery-transport-consent-gates` at PR #10's exact head | OPEN / DRAFT / UNMERGED |

PR #10's head is PR #22's base, and PR #22's compare reports that exact base as its merge base. PR #22 is therefore stacked on PR #10's branch, not currently targeted directly at `main`.

PR #11 is a separate audit-fixture branch targeting `main`; it is not PR #22's base and is not an ancestor in the PR #22 base relationship. Its metadata and scope do not confer Production authorization or satisfy the missing Query 8A/8B evidence requirement.

**Governance conclusion:** the repository's current declared targets are authoritative for this inspection: PR #10 and PR #11 target `main`; PR #22 targets PR #10's head branch. No PR is merged, and all three remain draft. Do not retarget, merge, or infer that one draft is approved based solely on these references. Any later sequencing or retargeting requires explicit maintainer/Manager authorization and the applicable reviews. No merge was performed.

### 6. Production DBA access recheck and outstanding dependencies

Cycle 381 repeated Supabase project discovery on both available account links. The returned projects remain unrelated staging projects; neither list contains `xaipiovflxomcbfwtwmu`. Read-only metadata lookup against that Production reference again returned explicit permission denial on both links (`MCP error -32600: You do not have permission to perform this action`).

No authorized read-only Production DBA session is available through these connections. No Production SQL was run. Query 8A and Query 8B remain NOT COLLECTED. The Query 8B membership graph remains UNKNOWN, not empty. The exact 18 signatures, complete direct/transitive membership graph, INHERIT/SET/effective privilege evidence, owner approvals, named DBA/security approvers, timestamps and protected evidence references all remain outstanding.

### 7. Independent work that can proceed without Production identity assumptions

Repository-only work may continue on PR #22 without changing migration 038 or claiming Production readiness:

- Maintain and independently review PostgreSQL behavior fixtures and security-definer ownership audit test coverage.
- Verify that the existing ownership audit rejects unexpected privileged owners/role attributes and membership paths in test fixtures, while keeping fixture identities explicitly non-Production.
- Review documentation and test coverage for completeness, fail-closed behavior, and exact-head CI.
- Continue non-Production code review of Daily Journey administrator isolation and provider-integrity administration.

Expected-owner enforcement bound to Production identities, any Production role changes or migration execution, Production deployment, and merge/rollout remain blocked pending authoritative evidence and approvals.

### 8. Cycle 382 handoff

1. Keep PR #22 OPEN / DRAFT / UNMERGED and preserve its stacked relationship to PR #10 unless an authorized maintainer explicitly changes sequencing.
2. Keep PR #10 and PR #11 OPEN / DRAFT / UNMERGED; both currently target `main`.
3. Keep migration 038 unchanged; its blob is `38951751fc5abeb79b75c4e37e55da01262a18b8` at the Cycle 380 HEAD and earlier Cycle 376/378 checkpoints.
4. Continue repository-only test/review work that does not require guessing Production owners.
5. Obtain an authorized least-privilege Production DBA connection or complete signed-off Query 8A/8B evidence, then independently verify provenance, completeness and approvals before any expected-owner enforcement implementation.
6. Maintain Production NO-GO. Do not deploy, merge, run Production SQL, or modify migration 038 as part of this handoff.


---

## Cycle 382 — access recheck and manifest-validator readiness

**Verification date:** 2026-11-24  
**Repository branch:** `security/private-daily-journey-admin-isolation-c408`  
**Production target:** `xaipiovflxomcbfwtwmu`  
**Disposition:** Production ownership evidence BLOCKED; repository-only manifest validation mechanics added.

### 1. Supabase access investigation

Both Supabase account connections were rechecked using organization listing, project listing and exact Production project metadata lookup.

- Neither connection's organization membership result includes the organization owning DeedLight Production project `xaipiovflxomcbfwtwmu`.
- Neither project listing includes `xaipiovflxomcbfwtwmu`.
- Direct `get_project` lookup for that exact project reference returns `MCP error -32600: You do not have permission to perform this action` on both connections.
- The visible projects on these connections are not the DeedLight Production target. Their existence does not confer access to this target.
- No authorized read-only database session or Production SQL execution capability was established.

**Precise missing authorization:** a human-controlled DeedLight Production organization/project administrator or DBA must grant the designated evidence collector access to the correct Supabase organization/project and provide an explicitly authorized least-privilege read-only PostgreSQL connection capable of reading the required system catalog metadata. The current connected principals lack organization/project visibility and the project metadata permission. No credential, role elevation, service-role key, or database password was supplied or inferred.

The DBA authorization must specify the exact project reference, named collector, read-only scope, allowed catalog/query scope, time window, and evidence-retention destination. The database role must be able to inspect the function catalog and all owner-role and membership metadata needed by Query 8A/8B without permitting DDL, role mutation, grants/revokes, application data access, or writes. If ordinary project metadata membership is not sufficient for complete catalog visibility, the DBA must provide a separately controlled read-only database identity with the necessary catalog visibility. Do not attempt to work around the permission denial.

### 2. Exact outstanding Query 8A/8B evidence

**Query 8A — not collected:** the complete, successful result for all 18 exact SECURITY DEFINER identity signatures, including resolved catalog signature, function OID, owner role name/OID, SECURITY DEFINER state, role attribute tuple, and relevant function configuration. It must prove all 18 are present and uniquely resolved.

**Query 8B — not collected:** complete direct and transitive membership paths for every distinct owner returned by Query 8A, with exact edge INHERIT and SET options, effective MEMBER/USAGE/SET semantics, and relevant attributes for every reachable role. The output must be complete and untruncated and reconcile to every distinct Query 8A owner. A zero-row result is valid only when the query succeeds, all owners were included, completeness is attested, and the DBA/security approvers explicitly approve each empty owner graph.

**Required provenance and approvals:** exact Production project identity attestation; query text/version and SHA-256; collection timestamp with timezone; collector and DBA identities; raw result SHA-256; immutable protected evidence references; row counts and truncation/completeness attestation; complete distinct-owner reconciliation; and explicit DBA plus independent security approval for every function-to-owner mapping, every owner attribute tuple, and every owner's full membership graph. Query outputs and approvals must remain in the approved protected evidence store, not ordinary repository files or chat.

### 3. Executable manifest validation mechanics

Cycle 382 added:

- `scripts/verify-production-function-owner-manifest.mjs`
- `scripts/test-production-function-owner-manifest.mjs`
- A fixture-only test step in `.github/workflows/pr-validation.yml`.

The validator requires exact coverage of the 18 audited signatures, complete evidence metadata, distinct-owner reconciliation, explicit owner attributes, complete membership paths/edge options/effective privilege values, and independent DBA/security approval records bound to the exact project, Query 8A/8B hashes, and exact policy-value digests. It rejects missing/partial/duplicate/extra mappings and unknown membership graphs. It does not auto-discover or adopt live owners.

The fixture tests use clearly synthetic fixture identities solely to test mechanics. No Production owner manifest or approval document is checked in. The validator is a structural completeness and policy-value binding gate only: it does not authenticate human signatures, retrieve/re-hash protected external artifacts, or compare live Production catalogs. Those limitations are documented in the technical design and must be resolved by protected-evidence custody and a later separately reviewed read-only catalog verifier. Passing fixture tests is not Production ownership evidence.

### 4. Cycle 383 handoff

1. Verify exact-head CI for the validator/test/workflow commits; record all nine job results and exact SHA.
2. Review the validator and negative fixture coverage, including its structural-only trust boundary.
3. Obtain explicit human DBA authorization for the exact project and named read-only evidence collector; provision least-privilege catalog access through the owning organization/project administrator.
4. Collect Query 8A and Query 8B from the verified Production target only after authorization. Preserve raw outputs, query hashes, timestamps, provenance and immutable references.
5. Reconcile every distinct owner and membership path and obtain explicit DBA/security approvals before populating any Production manifest.
6. Keep migration 038 unchanged; keep PR #22 OPEN / DRAFT / UNMERGED and stacked on PR #10. No retarget, merge, Production SQL mutation, deployment or rollout.
7. Production ownership enforcement and release remain NO-GO until evidence, approvals, independent review and all applicable release gates pass.


---

## Cycle 384 — approval integrity hardening and evidence verification

**Repository-only implementation. Production status remains NO-GO.** Starting HEAD for this cycle was `7e010a9483759dc4dcfd9a79d296087811570547`. No Production database operation, secret retrieval, approval issuance, owner change, deployment, merge, or migration 038 modification occurred.

### New artifacts and CI

- `scripts/verify-production-owner-approval-bundle.mjs`: Ed25519 signed approval, trust-root, evidence-byte and provenance verifier; local-only artifact handling; CLI and exported verification function.
- `scripts/test-production-owner-approval-bundle.mjs`: disposable fixture suite using ephemeral Ed25519 keypairs generated at test runtime. The fixture identities and keys are not Production identities or trust anchors.
- `.github/workflows/pr-validation.yml`: the ownership-audit job now runs the cryptographic approval/evidence fixture suite, in addition to the prior structural manifest fixture suite and actual disposable PostgreSQL 16 ownership audit.

### Verified design requirements implemented in code

1. Every individual approval binds its own policy version, exact Production project, complete canonical manifest SHA-256, actual Query 8A/8B result SHA-256 values, exact policy-value digest, scope, subject, owner role, identity, key ID, decision, nonce, timestamp, and expiration.
2. Ed25519 signatures are verified against a separately supplied trusted key registry. Key-to-identity binding, active identity, asserted DBA/security role, key validity, key revocation and approval revocation are checked. Unsupported algorithms or missing active keys fail closed.
3. The exact approvals artifact bytes, both SQL query files and both raw query-result files are checked against a SHA-256 index in the out-of-band trusted registry. Actual Query 8A/8B result bytes are parsed and reconciled against the manifest; the SQL bytes are hashed and checked for the required inventory structure.
4. Evidence metadata requires exact project, query ID/version, execution ID, timestamp, PostgreSQL 16+ server version, trusted collector, trusted read-only execution principal, read-only transaction/role attestations, successful/complete/untruncated state, actual row counts, SQL hashes and raw-result hashes.
5. Query 8A must contain exactly the 18 expected signatures, all PRESENT and SECURITY DEFINER, with complete owner attributes. Query 8B owner coverage must equal the distinct Query 8A owner set, and each actual membership path, intermediate role attributes, edge INHERIT/SET options, and effective MEMBER/USAGE/SET values must match the manifest.
6. An empty Query 8B result is accepted only as an actual empty result file with a successful zero-row attestation bound to execution ID, query/result hashes, collector, timestamp, complete owner coverage, and a reason. Missing or incomplete results are not empty graphs.
7. Duplicate IDs, cross-manifest substitution, invalid signatures, expired/not-yet-valid approvals, revoked keys/approvals, and already-consumed approval IDs are rejected.
8. Artifact references are local normalized relative paths only. No URL fetching, DNS, network access, or arbitrary remote-reference resolution exists. Path traversal, absolute paths, symlinks, non-regular files, non-canonical JSON, and files over 25 MiB are rejected.

The trusted registry is an explicit out-of-band trust anchor. It must be delivered and protected independently from the repository and evidence bundle. A cryptographic signature proves control of a key, not legal identity; a human authority must authenticate approvers and approve their identity-to-role assignments. The verifier does not mutate the consumed-ID registry; the authority must atomically record consumed approval IDs after a separately approved acceptance event. These boundaries are documented in `docs/PRODUCTION_FUNCTION_OWNER_ENFORCEMENT_DESIGN.md`.

### Production authority dependency — exact blocker

No human-authorized Production/security trust authority or trusted key registry was made available in Cycle 384. The required human-controlled dependency is:

- Production organization/project administrator and security owner to authenticate named DBA and security approvers;
- explicit identity-to-role assignments and approved Ed25519 public keys, with key validity, rotation and revocation policy;
- named evidence collector, trusted collector identity and DBA-approved read-only PostgreSQL execution principal;
- independently delivered protected trust-root registry and protected artifact store with write-controlled hash index;
- a trusted revocation and consumed-approval ledger owner/process.

No public keys, identities, Production approvals, owner mappings, or trust root were fabricated or committed. The previous Cycle 382 Supabase investigation found both connected account links lacked access to project `xaipiovflxomcbfwtwmu`; Cycle 384 did not acquire new access or execute Production SQL.

### Query 8A/8B status

- Query 8A: NOT COLLECTED from Production; exact 18-row owner inventory and attributes remain outstanding.
- Query 8B: NOT COLLECTED from Production; complete owner membership paths, every intermediate role attribute, edge options and effective privileges remain outstanding.
- Query 8B zero rows: only a future successful, complete, all-owner execution with actual empty result bytes and explicit bound attestation may represent an empty graph.
- Live catalog comparison: a separate read-only bidirectional design is recorded in the owner-enforcement design document. It compares expected and actual function signatures/owners/attributes and both directions of the complete membership graph; it is not implemented as a Production operation in this cycle.

### Severity-ranked findings disposition

| Severity | Finding | Disposition |
|---|---|---|
| P0 | No authenticated Production DBA/security trust authority or trusted key registry | BLOCKED — human authority required |
| P0 | No authorized Query 8A/8B Production evidence | BLOCKED — read-only DBA access required |
| P1 | Global one-time approval consumption requires external trusted ledger maintenance | Designed; verifier rejects already-consumed IDs; authority operation outstanding |
| P1 | Live bidirectional Production catalog comparison | Design documented; implementation deferred until evidence exists |
| P2 | Trust-root authenticity and delivery are outside repository verifier | Explicit out-of-band trust boundary documented |

### Cycle 385 handoff

1. Verify exact-head CI and inspect every job result for the final commit.
2. Obtain human-controlled identity proofing, approver role authorization, trusted public keys, collector/read-only principal authorization, and protected trust-root delivery.
3. Obtain exact Production Query 8A/8B bytes and SQL, complete provenance, and independently approved evidence custody.
4. Review and verify signed approval artifacts against the complete manifest digest and actual evidence bytes.
5. Build the separate read-only bidirectional catalog comparison only after accepted Production evidence exists.
6. Keep migration 038 unchanged, PR #22 OPEN / DRAFT / UNMERGED and stacked on PR #10. No Production SQL, ownership mutation, deployment, merge or retarget.


### Cycle 384 CI correction note

The first cryptographic-suite CI attempt reached the existing structural validator and exposed missing legacy evidence metadata (`ref` and `collectedAt`) in the new disposable fixtures. The fixtures were corrected to satisfy the existing evidence contract; no production validator requirement was weakened. A later code review also removed a CLI-supplied clock override so Production expiry checks always use the current system time, added trusted read-only execution-principal allowlisting and nonce replay rejection, and retained the API clock injection solely for deterministic test cases. The exact final SHA and workflow result must be recorded after the final documentation commit.
