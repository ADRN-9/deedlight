-- DeedLight Production migration reconciliation: metadata-only read-only audit.
-- Run only through the approved, isolated evidence collector.
-- This script reads PostgreSQL catalogs and migration-history identifiers only.
-- It never reads application table rows, private reflections, emails, tokens, or webhook payloads.
-- Required collector-provided, non-secret connection metadata:
--   deedlight.expected_project_ref = xaipiovflxomcbfwtwmu
--   deedlight.repository_sha = exact 40-character Git SHA being audited
-- These custom settings are provenance labels, not authentication or proof of endpoint identity.
-- The collector MUST independently verify the TLS endpoint/host and bind this output to its receipt.

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';

DO $audit_preflight$
DECLARE
  v_project_ref text := current_setting('deedlight.expected_project_ref', true);
  v_repository_sha text := current_setting('deedlight.repository_sha', true);
  v_history_oid oid := to_regclass('supabase_migrations.schema_migrations');
BEGIN
  IF current_setting('transaction_read_only') <> 'on' THEN
    RAISE EXCEPTION 'Audit must execute in a read-only transaction.';
  END IF;
  IF v_project_ref IS DISTINCT FROM 'xaipiovflxomcbfwtwmu' THEN
    RAISE EXCEPTION 'Missing or unexpected DeedLight Production project reference.';
  END IF;
  IF v_repository_sha IS NULL OR v_repository_sha !~ '^[0-9a-f]{40}$' THEN
    RAISE EXCEPTION 'Exact repository SHA is required as collector metadata.';
  END IF;
  IF v_history_oid IS NULL THEN
    RAISE EXCEPTION 'Required Supabase migration-history table is unavailable.';
  END IF;
  IF NOT has_table_privilege(current_user, v_history_oid, 'SELECT') THEN
    RAISE EXCEPTION 'Collector cannot read the Supabase migration-history table.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute
    WHERE attrelid = v_history_oid AND attname = 'version'
      AND attnum > 0 AND NOT attisdropped
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute
    WHERE attrelid = v_history_oid AND attname = 'statements'
      AND attnum > 0 AND NOT attisdropped
  ) THEN
    RAISE EXCEPTION 'Migration-history table does not match the expected version/statements contract.';
  END IF;
END
$audit_preflight$;

-- 01. Capture identity and time. Endpoint/TLS verification is performed independently by the collector.
SELECT
  current_setting('deedlight.expected_project_ref') AS expected_project_ref,
  current_setting('deedlight.repository_sha') AS repository_sha,
  current_database() AS database_name,
  current_user AS current_role,
  session_user AS session_role,
  current_setting('server_version') AS server_version,
  inet_server_addr()::text AS server_address,
  inet_server_port() AS server_port,
  to_char(clock_timestamp() AT TIME ZONE 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS captured_at_utc,
  current_setting('transaction_read_only') AS transaction_read_only;

-- 02. Relation, view and column inventory; no application rows are selected.
SELECT
  n.nspname AS schema_name,
  c.relname AS relation_name,
  c.relkind AS relation_kind,
  pg_catalog.pg_get_userbyid(c.relowner) AS owner_name,
  c.relpersistence AS persistence,
  c.relrowsecurity AS row_security_enabled,
  c.relforcerowsecurity AS row_security_forced,
  a.attnum AS ordinal_position,
  a.attname AS column_name,
  pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
  a.attnotnull AS not_null,
  pg_catalog.pg_get_expr(ad.adbin, ad.adrelid) AS default_expression,
  CASE WHEN c.relkind IN ('v', 'm')
    THEN pg_catalog.pg_get_viewdef(c.oid, true) END AS view_definition
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_attribute a
  ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
LEFT JOIN pg_catalog.pg_attrdef ad
  ON ad.adrelid = c.oid AND ad.adnum = a.attnum
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg_toast%'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
ORDER BY n.nspname, c.relname, a.attnum;

-- 03. Function/procedure identity, owner and SECURITY DEFINER status. Function bodies are excluded.
SELECT
  n.nspname AS schema_name,
  p.proname AS routine_name,
  p.prokind AS routine_kind,
  pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
  pg_catalog.pg_get_function_result(p.oid) AS result_type,
  l.lanname AS language_name,
  pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,
  p.prosecdef AS security_definer,
  p.proleakproof AS leakproof,
  p.provolatile AS volatility,
  p.proconfig AS routine_settings
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
JOIN pg_catalog.pg_language l ON l.oid = p.prolang
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname NOT LIKE 'pg_toast%'
ORDER BY n.nspname, p.proname, identity_arguments;

-- 04. Relation ACLs, including column ACLs and explicit/default ACL expansion.
SELECT
  'relation' AS acl_scope,
  n.nspname AS schema_name,
  c.relname AS object_name,
  NULL::text AS column_name,
  CASE WHEN x.grantee = 0 THEN 'PUBLIC'
       ELSE pg_catalog.pg_get_userbyid(x.grantee) END AS grantee,
  pg_catalog.pg_get_userbyid(x.grantor) AS grantor,
  x.privilege_type,
  x.is_grantable
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(
  COALESCE(c.relacl, pg_catalog.acldefault('r', c.relowner))
) x
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
UNION ALL
SELECT
  'column' AS acl_scope,
  n.nspname,
  c.relname,
  a.attname,
  CASE WHEN x.grantee = 0 THEN 'PUBLIC'
       ELSE pg_catalog.pg_get_userbyid(x.grantee) END,
  pg_catalog.pg_get_userbyid(x.grantor),
  x.privilege_type,
  x.is_grantable
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) x
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL
ORDER BY 2, 3, 1, 4, 5, 7;

-- 05. Schema ACLs.
SELECT
  n.nspname AS schema_name,
  pg_catalog.pg_get_userbyid(n.nspowner) AS owner_name,
  CASE WHEN x.grantee = 0 THEN 'PUBLIC'
       ELSE pg_catalog.pg_get_userbyid(x.grantee) END AS grantee,
  pg_catalog.pg_get_userbyid(x.grantor) AS grantor,
  x.privilege_type,
  x.is_grantable
FROM pg_catalog.pg_namespace n
CROSS JOIN LATERAL pg_catalog.aclexplode(
  COALESCE(n.nspacl, pg_catalog.acldefault('n', n.nspowner))
) x
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, grantee, x.privilege_type;

-- 06. Routine ACLs, including EXECUTE grants and grant options.
SELECT
  n.nspname AS schema_name,
  p.proname AS routine_name,
  pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
  CASE WHEN x.grantee = 0 THEN 'PUBLIC'
       ELSE pg_catalog.pg_get_userbyid(x.grantee) END AS grantee,
  pg_catalog.pg_get_userbyid(x.grantor) AS grantor,
  x.privilege_type,
  x.is_grantable
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(
  COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
) x
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, p.proname, identity_arguments, grantee;

-- 07. Role attributes and inherited/direct membership edges.
SELECT
  r.rolname,
  r.rolcanlogin,
  r.rolsuper,
  r.rolcreatedb,
  r.rolcreaterole,
  r.rolreplication,
  r.rolbypassrls,
  r.rolinherit,
  r.rolconnlimit,
  r.rolvaliduntil,
  r.rolconfig
FROM pg_catalog.pg_roles r
ORDER BY r.rolname;

SELECT
  parent.rolname AS granted_role,
  member.rolname AS member_role,
  grantor.rolname AS grantor_role,
  m.admin_option,
  m.inherit_option,
  m.set_option
FROM pg_catalog.pg_auth_members m
JOIN pg_catalog.pg_roles parent ON parent.oid = m.roleid
JOIN pg_catalog.pg_roles member ON member.oid = m.member
JOIN pg_catalog.pg_roles grantor ON grantor.oid = m.grantor
ORDER BY parent.rolname, member.rolname;

-- 08. RLS policy definitions and command/role boundaries.
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_catalog.pg_policies
ORDER BY schemaname, tablename, policyname;

-- 09. Constraints, indexes and non-internal triggers.
SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  con.conname AS constraint_name,
  con.contype AS constraint_type,
  con.convalidated AS validated,
  con.condeferrable AS deferrable,
  con.condeferred AS initially_deferred,
  pg_catalog.pg_get_constraintdef(con.oid, true) AS definition
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, c.relname, con.conname;

SELECT schemaname, tablename, indexname, tablespace, indexdef
FROM pg_catalog.pg_indexes
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schemaname, tablename, indexname;

SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  t.tgname AS trigger_name,
  t.tgenabled AS enabled_state,
  t.tgisinternal AS internal_trigger,
  pg_catalog.pg_get_triggerdef(t.oid, true) AS definition
FROM pg_catalog.pg_trigger t
JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND NOT t.tgisinternal
ORDER BY n.nspname, c.relname, t.tgname;

-- 10. Default privileges, preserving owner/schema/object-kind and each ACL edge.
SELECT
  pg_catalog.pg_get_userbyid(d.defaclrole) AS owner_role,
  COALESCE(n.nspname, '<all schemas>') AS schema_name,
  d.defaclobjtype AS object_kind,
  CASE WHEN x.grantee = 0 THEN 'PUBLIC'
       ELSE pg_catalog.pg_get_userbyid(x.grantee) END AS grantee,
  pg_catalog.pg_get_userbyid(x.grantor) AS grantor,
  x.privilege_type,
  x.is_grantable
FROM pg_catalog.pg_default_acl d
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = d.defaclnamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(d.defaclacl) x
ORDER BY owner_role, schema_name, object_kind, grantee, x.privilege_type;

-- 11. Installed extensions and their schema/owner/version.
SELECT
  e.extname,
  e.extversion,
  n.nspname AS schema_name,
  pg_catalog.pg_get_userbyid(e.extowner) AS owner_name
FROM pg_catalog.pg_extension e
JOIN pg_catalog.pg_namespace n ON n.oid = e.extnamespace
ORDER BY e.extname;

-- 12. Supabase migration-history table structure (names/types only).
SELECT
  a.attnum AS ordinal_position,
  a.attname AS column_name,
  pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
  a.attnotnull AS not_null
FROM pg_catalog.pg_attribute a
WHERE a.attrelid = to_regclass('supabase_migrations.schema_migrations')
  AND a.attnum > 0
  AND NOT a.attisdropped
ORDER BY a.attnum;

-- 13. Migration-history identifiers only. Never export statements or application data.
SELECT
  to_jsonb(h)->>'version' AS version,
  to_jsonb(h)->>'name' AS migration_name,
  CASE
    WHEN jsonb_typeof(to_jsonb(h)->'statements') = 'array'
      THEN jsonb_array_length(to_jsonb(h)->'statements')
    ELSE NULL
  END AS recorded_statement_count
FROM supabase_migrations.schema_migrations h
ORDER BY to_jsonb(h)->>'version', to_jsonb(h)->>'name';

-- The collector captures the result digest and commits its own signed receipt outside this database.
-- Roll back the read-only snapshot explicitly; no database state is changed.
ROLLBACK;
