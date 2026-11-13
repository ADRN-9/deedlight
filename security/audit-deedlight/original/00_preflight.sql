-- DeedLight Cycle 14 retry — design only, NOT authorized for Production execution.
-- Source: ADRN-9/deedlight @ c983e2ed8b93c935139c935343261570ecea6978
-- Catalog-only; no table rows, customer records, secrets or functions are executed.
-- Run as a separately authorized metadata-only role, review output and STOP
-- if the result is not VERIFIED. This does NOT prove Supabase project identity.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '15s';
SELECT pg_catalog.jsonb_build_object(
  'invariant', 'metadata_access_preflight',
  'source_sha', 'c983e2ed8b93c935139c935343261570ecea6978',
  'expected_project_ref', 'xaipiovflxomcbfwtwmu',
  'status', CASE WHEN
       pg_catalog.current_setting('transaction_read_only') = 'on'
   AND pg_catalog.has_table_privilege('pg_catalog.pg_class', 'SELECT')
   AND pg_catalog.has_table_privilege('pg_catalog.pg_attribute', 'SELECT')
   AND pg_catalog.has_table_privilege('pg_catalog.pg_proc', 'SELECT')
   AND pg_catalog.has_table_privilege('pg_catalog.pg_constraint', 'SELECT')
   AND pg_catalog.has_table_privilege('pg_catalog.pg_policy', 'SELECT')
   AND pg_catalog.has_table_privilege('pg_catalog.pg_namespace', 'SELECT')
   AND pg_catalog.to_regnamespace('public') IS NOT NULL
   AND pg_catalog.to_regnamespace('auth') IS NOT NULL
   AND pg_catalog.to_regrole('anon') IS NOT NULL
   AND pg_catalog.to_regrole('authenticated') IS NOT NULL
   AND pg_catalog.to_regrole('service_role') IS NOT NULL
  THEN 'VERIFIED' ELSE 'BLOCKED' END,
  'expected', 'READ ONLY; pg_catalog SELECT; public/auth namespaces; anon/authenticated/service_role role metadata',
  'actual', pg_catalog.jsonb_build_object(
    'read_only', pg_catalog.current_setting('transaction_read_only'),
    'catalog_proc_readable', pg_catalog.has_table_privilege('pg_catalog.pg_proc', 'SELECT'),
    'catalog_policy_readable', pg_catalog.has_table_privilege('pg_catalog.pg_policy', 'SELECT'),
    'public_namespace_present', pg_catalog.to_regnamespace('public') IS NOT NULL,
    'auth_namespace_present', pg_catalog.to_regnamespace('auth') IS NOT NULL,
    'expected_roles_present', pg_catalog.to_regrole('anon') IS NOT NULL
       AND pg_catalog.to_regrole('authenticated') IS NOT NULL
       AND pg_catalog.to_regrole('service_role') IS NOT NULL,
    'database_name', pg_catalog.current_database(),
    'server_version_num', pg_catalog.current_setting('server_version_num')
  ),
  'identity_proven', FALSE,
  'note', 'An operator must separately attest the connection belongs to the expected Supabase project.'
) AS audit_record;
ROLLBACK;
