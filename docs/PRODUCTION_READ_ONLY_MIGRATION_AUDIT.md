# DeedLight Production read-only migration audit packet

**Purpose:** Give the Production owner a repeatable, SELECT-only catalog and migration-history audit.  
**Repository:** ADRN-9/deedlight  
**Source branch:** security/private-daily-journey-admin-isolation-c408  
**Source snapshot inspected:** c4be798d1a4e0d6e4799085b818572038028d0bb  
**Source tree:** 782ebae456df6190b0d347bb01ad917ed30220fd  
**Source migration inventory:** 37 files; 36 unique version prefixes  
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
**Reviewed PR #22 HEAD:** c939d4a24293342deb6161eab2f28fb66765a237  
**Reviewed branch tree:** e321be2b406043b01c4ed4dd4cda003c54dbdd0e

The packet remains a prepared procedure; it was not executed against Production.

The currently connected Supabase integrations were checked for the target project reference `xaipiovflxomcbfwtwmu`:

- `list_projects` through both connected accounts did not return the target project.
- `get_project`, `list_migrations`, and `list_tables` were each attempted against the exact target project through both accounts. All attempts were denied with `MCP error -32600: You do not have permission to perform this action`.
- A SELECT-only database identity and migration-history-presence query through `execute_sql` was attempted through both accounts. Both attempts were denied with the same permission error; no SQL ran and no database result was returned.

**Evidence consequence:** no Production database identity was established, and no Production migration-history, schema/constraint, RLS/grant, function/trigger, duplicate-007 execution, or migration-036 application evidence was collected. A permission denial is not evidence of an empty history, absent schema, absent migration, or non-execution.

**Exact missing dependency:** the Production owner/administrator must grant an existing connected identity project-scoped read-only access to project `xaipiovflxomcbfwtwmu`, or provide an approved dedicated read-only PostgreSQL connection after independently verifying the Production project reference. Use the least-privilege role and enforced read-only session defined in Sections 2–3 above. Do not grant service-role, administrator, migration, schema-write, credential-management, or outbound-delivery authority for this audit.

No credentials were requested, transmitted, or modified. No Production connection was established. No query in Sections 4–6 was executed. No Production data, schema, migration history, migration, scheduler, provider, or delivery setting was read or changed.

The previous C404 denial record and the C247 disposable PostgreSQL/Supabase CLI evidence remain historical evidence with their existing scope; this access attempt does not duplicate or upgrade those results to Production evidence.
