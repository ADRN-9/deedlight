-- DeedLight Cycle 14 retry — catalog-only audit DESIGN; never run in Production
-- without a separate operator authorization and VERIFIED 00_preflight result.
-- Does not SELECT any table data, migration-history rows, or secrets.
-- Source SHA: c983e2ed8b93c935139c935343261570ecea6978
-- Every output row uses invariant, status, expected, actual, source_sha.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '20s';
WITH
params AS (
 SELECT 'c983e2ed8b93c935139c935343261570ecea6978'::text AS source_sha
),
-- The expected schema object inventory comes from migrations 019-024.
expected_rel(schema_name, rel_name) AS (VALUES
 ('auth','users'), ('public','profiles'),
 ('public','daily_reminder_preferences'), ('public','newsletter_preferences'),
 ('public','weekly_goodness_features'), ('public','delivery_ledger')
),
rel AS (
 SELECT e.schema_name, e.rel_name, c.oid, c.relkind, c.relrowsecurity,
        c.relforcerowsecurity
 FROM expected_rel e
 LEFT JOIN pg_catalog.pg_namespace n ON n.nspname=e.schema_name
 LEFT JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid
      AND c.relname=e.rel_name AND c.relkind IN ('r','p')
),
object_results AS (
 SELECT 'relation:'||schema_name||'.'||rel_name AS invariant,
  CASE WHEN oid IS NULL THEN 'FAILED' ELSE 'VERIFIED' END::text AS status,
  'required relational object (ordinary or partitioned table)'::text AS expected,
  pg_catalog.jsonb_build_object('present',oid IS NOT NULL,'relation_kind',relkind) AS actual
 FROM rel
),
expected_col(schema_name, rel_name, col_name, expected_type, required_not_null) AS (VALUES
 ('public','delivery_ledger','id','uuid',true),
 ('public','delivery_ledger','user_id','uuid',true),
 ('public','delivery_ledger','kind','text',true),
 ('public','delivery_ledger','delivery_key','text',true),
 ('public','delivery_ledger','state','text',true),
 ('public','delivery_ledger','scheduled_for','timestamp with time zone',true),
 ('public','delivery_ledger','claim_token','uuid',false),
 ('public','delivery_ledger','claimed_at','timestamp with time zone',false),
 ('public','delivery_ledger','sent_at','timestamp with time zone',false),
 ('public','delivery_ledger','failed_at','timestamp with time zone',false),
 ('public','delivery_ledger','cancelled_at','timestamp with time zone',false),
 ('public','delivery_ledger','provider_result_id','text',false),
 ('public','delivery_ledger','error_code','text',false),
 ('public','delivery_ledger','created_at','timestamp with time zone',true),
 ('public','delivery_ledger','updated_at','timestamp with time zone',true),
 ('public','delivery_ledger','claim_expires_at','timestamp with time zone',false),
 ('public','delivery_ledger','attempt_count','integer',true),
 ('public','delivery_ledger','last_attempt_at','timestamp with time zone',false),
 ('public','delivery_ledger','next_attempt_at','timestamp with time zone',false),
 ('public','delivery_ledger','transport_started_at','timestamp with time zone',false),
 ('public','daily_reminder_preferences','daily_enabled','boolean',false),
 ('public','newsletter_preferences','weekly_enabled','boolean',false),
 ('public','newsletter_preferences','consented_at','timestamp with time zone',false),
 ('public','profiles','is_suspended','boolean',false),
 ('auth','users','email_confirmed_at','timestamp with time zone',false)
),
column_results AS (
 SELECT 'column:'||e.schema_name||'.'||e.rel_name||'.'||e.col_name AS invariant,
  CASE WHEN a.attnum IS NOT NULL AND
     pg_catalog.format_type(a.atttypid,a.atttypmod)=e.expected_type AND
     (NOT e.required_not_null OR a.attnotnull)
   THEN 'VERIFIED' ELSE 'FAILED' END::text AS status,
  e.expected_type || CASE WHEN e.required_not_null THEN ' NOT NULL' ELSE '' END AS expected,
  pg_catalog.jsonb_build_object('present',a.attnum IS NOT NULL,
   'type',CASE WHEN a.attnum IS NOT NULL THEN pg_catalog.format_type(a.atttypid,a.atttypmod) ELSE NULL END,
   'not_null',a.attnotnull) AS actual
 FROM expected_col e
 LEFT JOIN rel r ON r.schema_name=e.schema_name AND r.rel_name=e.rel_name
 LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid=r.oid AND a.attname=e.col_name
    AND a.attnum>0 AND NOT a.attisdropped
),
expected_constraints(con_name, expected_type) AS (VALUES
 ('delivery_ledger_attempt_count_check','c'),
 ('delivery_ledger_claim_lease_check','c')
),
constraint_results AS (
 SELECT 'constraint:public.delivery_ledger.'||e.con_name AS invariant,
  CASE WHEN con.oid IS NOT NULL AND con.convalidated AND con.contype=e.expected_type::"char"
       THEN 'VERIFIED' ELSE 'FAILED' END::text AS status,
  'validated CHECK constraint present; expression requires independent reviewed comparison'::text AS expected,
  pg_catalog.jsonb_build_object('present',con.oid IS NOT NULL,'validated',con.convalidated,
    'definition_md5',CASE WHEN con.oid IS NOT NULL THEN pg_catalog.md5(pg_catalog.pg_get_constraintdef(con.oid,true)) ELSE NULL END) AS actual
 FROM expected_constraints e
 LEFT JOIN rel r ON r.schema_name='public' AND r.rel_name='delivery_ledger'
 LEFT JOIN pg_catalog.pg_constraint con ON con.conrelid=r.oid AND con.conname=e.con_name
),
unique_results AS (
 SELECT 'constraint:public.delivery_ledger.logical_unique'::text AS invariant,
  CASE WHEN EXISTS (
   SELECT 1 FROM pg_catalog.pg_constraint con
   JOIN pg_catalog.pg_class c ON c.oid=con.conrelid
   JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname='delivery_ledger'
     AND con.contype='u' AND con.convalidated
     AND (SELECT pg_catalog.array_agg(a.attname ORDER BY k.ordinality)
          FROM pg_catalog.unnest(con.conkey) WITH ORDINALITY AS k(attnum,ordinality)
          JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attnum=k.attnum)
       = ARRAY['kind','user_id','delivery_key']::name[]
  ) THEN 'VERIFIED' ELSE 'FAILED' END::text AS status,
  'UNIQUE(kind,user_id,delivery_key) validated'::text AS expected,
  pg_catalog.jsonb_build_object('column_order','kind,user_id,delivery_key',
    'matching_constraint_present',EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint con
      JOIN rel r ON con.conrelid=r.oid WHERE r.schema_name='public'
       AND r.rel_name='delivery_ledger' AND con.contype='u' AND con.convalidated
       AND (SELECT pg_catalog.array_agg(a.attname ORDER BY k.ordinality)
            FROM pg_catalog.unnest(con.conkey) WITH ORDINALITY AS k(attnum,ordinality)
            JOIN pg_catalog.pg_attribute a ON a.attrelid=r.oid AND a.attnum=k.attnum)
         = ARRAY['kind','user_id','delivery_key']::name[]
    )) AS actual
),
-- Structural identity of the primary key, without looking at ledger rows.
primary_key_results AS (
 SELECT 'constraint:public.delivery_ledger.primary_id'::text AS invariant,
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint con
    JOIN rel r ON con.conrelid=r.oid
    WHERE r.schema_name='public' AND r.rel_name='delivery_ledger'
      AND con.contype='p' AND con.convalidated
      AND (SELECT pg_catalog.array_agg(a.attname ORDER BY k.ordinality)
           FROM pg_catalog.unnest(con.conkey) WITH ORDINALITY AS k(attnum,ordinality)
           JOIN pg_catalog.pg_attribute a ON a.attrelid=r.oid AND a.attnum=k.attnum)
         = ARRAY['id']::name[]
  ) THEN 'VERIFIED' ELSE 'FAILED' END::text AS status,
  'PRIMARY KEY(id) validated'::text AS expected,
  pg_catalog.jsonb_build_object('required_column','id','matching_constraint_present', EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint con
    JOIN rel r ON con.conrelid=r.oid
    WHERE r.schema_name='public' AND r.rel_name='delivery_ledger'
      AND con.contype='p' AND con.convalidated
      AND (SELECT pg_catalog.array_agg(a.attname ORDER BY k.ordinality)
           FROM pg_catalog.unnest(con.conkey) WITH ORDINALITY AS k(attnum,ordinality)
           JOIN pg_catalog.pg_attribute a ON a.attrelid=r.oid AND a.attnum=k.attnum)
         = ARRAY['id']::name[]
  )) AS actual
),
-- Some original CHECK constraints were generated without stable names.
-- Their definitions require a reviewed PG-major-specific digest manifest.
constraint_definition_results AS (
 SELECT 'constraint_definition:public.delivery_ledger.'||con.conname AS invariant,
  'UNKNOWN'::text AS status,
  'review expression against the approved source migration contract'::text AS expected,
  pg_catalog.jsonb_build_object('type',con.contype,'validated',con.convalidated,
   'definition_md5',pg_catalog.md5(pg_catalog.pg_get_constraintdef(con.oid,true))) AS actual
 FROM pg_catalog.pg_constraint con
 JOIN rel r ON r.oid=con.conrelid
 WHERE r.schema_name='public' AND r.rel_name='delivery_ledger'
   AND con.contype='c'
),
rls_results AS (
 SELECT 'rls:'||r.schema_name||'.'||r.rel_name AS invariant,
  CASE WHEN r.oid IS NULL OR NOT coalesce(r.relrowsecurity,false)
       THEN 'FAILED' ELSE 'VERIFIED' END::text AS status,
  'RLS enabled (policy definitions separately reviewed)'::text AS expected,
  pg_catalog.jsonb_build_object('present',r.oid IS NOT NULL,'rls_enabled',r.relrowsecurity,
    'force_rls',r.relforcerowsecurity) AS actual
 FROM rel r WHERE r.schema_name='public'
),
-- Policy metadata only. Never emit raw policy expressions: hashes require
-- comparison against an independently reviewed PostgreSQL-major manifest.
policy_results AS (
 SELECT 'policy:'||r.schema_name||'.'||r.rel_name||'.'||p.polname AS invariant,
  'UNKNOWN'::text AS status,
  'policy expression digest awaiting approved canonical reference'::text AS expected,
  pg_catalog.jsonb_build_object('command',p.polcmd,'permissive',p.polpermissive,
   'using_md5',pg_catalog.md5(coalesce(pg_catalog.pg_get_expr(p.polqual,p.polrelid,true),'')),
   'check_md5',pg_catalog.md5(coalesce(pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid,true),''))) AS actual
 FROM rel r JOIN pg_catalog.pg_policy p ON p.polrelid=r.oid
 WHERE r.schema_name='public'
),
-- Current policy inventory is observable but without an approved manifest its
-- completeness/semantics cannot be established from catalogs alone.
policy_inventory_results AS (
 SELECT 'policy_inventory:'||r.schema_name||'.'||r.rel_name AS invariant,
   CASE WHEN r.oid IS NULL THEN 'FAILED' ELSE 'UNKNOWN' END::text AS status,
   'compare policy names, roles and expression fingerprints with reviewed source'::text AS expected,
   pg_catalog.jsonb_build_object('relation_present',r.oid IS NOT NULL,
      'policy_count',count(p.oid)) AS actual
 FROM rel r LEFT JOIN pg_catalog.pg_policy p ON p.polrelid=r.oid
 WHERE r.schema_name='public'
 GROUP BY r.schema_name,r.rel_name,r.oid
),
-- Effective service-role function access also requires schema USAGE.
rpc_schema_usage_results AS (
 SELECT 'rpc_schema_usage:public'::text AS invariant,
   CASE WHEN pg_catalog.to_regrole('service_role') IS NULL THEN 'BLOCKED'
        WHEN pg_catalog.to_regnamespace('public') IS NULL THEN 'FAILED'
        WHEN pg_catalog.has_schema_privilege(
          pg_catalog.to_regrole('service_role')::oid,
          pg_catalog.to_regnamespace('public')::oid,'USAGE') THEN 'VERIFIED'
        ELSE 'FAILED' END::text AS status,
   'service_role has effective USAGE on schema public'::text AS expected,
   pg_catalog.jsonb_build_object('public_present',pg_catalog.to_regnamespace('public') IS NOT NULL,
     'service_role_present',pg_catalog.to_regrole('service_role') IS NOT NULL) AS actual
),
-- Function body fingerprints are taken from exact reviewed source at the PR HEAD.
-- MD5 is used for accidental drift detection, NOT adversarial attestation.
expected_function(signature, body_md5, expected_path, access_policy) AS (VALUES
 ('public.handle_new_user()','9a83c77b3884fb460921a4d804995a60','search_path=public, auth','trigger'),
 ('public.enqueue_due_daily_reminders(timestamptz,integer)','ad0b49bdc5d6ea94bbc2a73fa40985ac','search_path=public, auth, pg_temp','service'),
 ('public.enqueue_weekly_goodness_delivery(date,timestamptz,integer)','9931260c74c424258c3cc8096d787843','search_path=public, auth, pg_temp','service'),
 ('public.enqueue_current_weekly_goodness_if_curated(timestamptz,integer)','c0baddf0ce310590e1a1409d7f04796c','search_path=public, auth, pg_temp','service'),
 ('public.begin_delivery_transport(uuid,uuid,text)','3ad794d71a48441f8c58249ed092d77b','search_path=public, auth, pg_temp','service'),
 ('public.claim_delivery_jobs(timestamptz,integer)','4530ea866b0af2ab45c698f2aa289619','search_path=public, auth, pg_temp','service'),
 ('public.authorize_delivery_job(uuid,uuid)','b7ee2eaedfccff6945b6f4348f962f3d','search_path=public, auth, pg_temp','service'),
 ('public.retry_delivery_job(uuid,uuid,timestamptz,text)','b1bb5ccb9109247a9517a5efe922a8b5','search_path=public, auth, pg_temp','service'),
 ('public.mark_delivery_sent(uuid,uuid,text)','e0cd94c428f7528276484af351d6abd0','search_path=public, auth, pg_temp','service'),
 ('public.mark_delivery_failed(uuid,uuid,text)','7caf1ec918ee6511e381319ed0e60e38','search_path=public, auth, pg_temp','service')
),
function_meta AS (
 SELECT e.*, p.oid, pg_catalog.md5(p.prosrc) AS actual_md5,
        p.prosecdef, p.provolatile, p.proconfig, l.lanname
 FROM expected_function e
 LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature)
 LEFT JOIN pg_catalog.pg_language l ON l.oid=p.prolang
),
function_results AS (
 SELECT 'function:'||signature AS invariant,
  CASE WHEN oid IS NULL OR actual_md5 IS DISTINCT FROM body_md5
    OR prosecdef IS DISTINCT FROM true OR provolatile IS DISTINCT FROM 'v'::"char"
    OR lanname IS DISTINCT FROM 'plpgsql'
    OR NOT (coalesce(proconfig,ARRAY[]::text[]) @> ARRAY[expected_path])
    THEN 'FAILED' ELSE 'VERIFIED' END::text AS status,
  'exists; source MD5='||body_md5||'; SECURITY DEFINER VOLATILE PL/pgSQL; '||expected_path AS expected,
  pg_catalog.jsonb_build_object('present',oid IS NOT NULL,'body_md5',actual_md5,
   'security_definer',prosecdef,'volatility',provolatile,'language',lanname,
   'path_match',coalesce(proconfig,ARRAY[]::text[]) @> ARRAY[expected_path]) AS actual
 FROM function_meta
),
function_acl_results AS (
 SELECT 'rpc_acl:'||signature AS invariant,
  CASE WHEN pg_catalog.to_regrole('service_role') IS NULL
      OR pg_catalog.to_regrole('authenticated') IS NULL OR pg_catalog.to_regrole('anon') IS NULL
      THEN 'BLOCKED'
   WHEN oid IS NULL THEN 'FAILED'
   WHEN pg_catalog.has_function_privilege(pg_catalog.to_regrole('service_role')::oid,oid,'EXECUTE')
    AND NOT pg_catalog.has_function_privilege(pg_catalog.to_regrole('anon')::oid,oid,'EXECUTE')
    AND NOT pg_catalog.has_function_privilege(pg_catalog.to_regrole('authenticated')::oid,oid,'EXECUTE')
      THEN 'VERIFIED' ELSE 'FAILED' END::text AS status,
  'effective EXECUTE: service_role=YES, anon=NO, authenticated=NO'::text AS expected,
  pg_catalog.jsonb_build_object(
    'service_role',CASE WHEN oid IS NOT NULL AND pg_catalog.to_regrole('service_role') IS NOT NULL
       THEN pg_catalog.has_function_privilege(pg_catalog.to_regrole('service_role')::oid,oid,'EXECUTE') ELSE NULL END,
    'anon',CASE WHEN oid IS NOT NULL AND pg_catalog.to_regrole('anon') IS NOT NULL
       THEN pg_catalog.has_function_privilege(pg_catalog.to_regrole('anon')::oid,oid,'EXECUTE') ELSE NULL END,
    'authenticated',CASE WHEN oid IS NOT NULL AND pg_catalog.to_regrole('authenticated') IS NOT NULL
       THEN pg_catalog.has_function_privilege(pg_catalog.to_regrole('authenticated')::oid,oid,'EXECUTE') ELSE NULL END) AS actual
 FROM function_meta WHERE access_policy='service'
),
-- The member preference setter is intentionally authenticated-callable.
preference_function_results AS (
 SELECT 'function:public.set_daily_reminder_preference(boolean,time without time zone,text)'::text AS invariant,
  CASE WHEN p.oid IS NULL THEN 'FAILED'
       WHEN p.prosecdef AND p.provolatile='v' AND
         coalesce(p.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=public, auth, pg_temp']
         AND pg_catalog.has_function_privilege(pg_catalog.to_regrole('authenticated')::oid,p.oid,'EXECUTE')
         AND NOT pg_catalog.has_function_privilege(pg_catalog.to_regrole('anon')::oid,p.oid,'EXECUTE')
       THEN 'VERIFIED' ELSE 'FAILED' END::text AS status,
  'SECURITY DEFINER, authenticated callable, anon denied; function body not pinned here'::text AS expected,
  pg_catalog.jsonb_build_object('present',p.oid IS NOT NULL,'security_definer',p.prosecdef,
    'body_md5',pg_catalog.md5(p.prosrc)) AS actual
 FROM (SELECT pg_catalog.to_regprocedure('public.set_daily_reminder_preference(boolean,time without time zone,text)') AS oid) f
 LEFT JOIN pg_catalog.pg_proc p ON p.oid=f.oid
),
legacy_results AS (
 SELECT 'legacy_rpc:public.begin_delivery_transport(uuid,uuid)'::text AS invariant,
  CASE WHEN pg_catalog.to_regprocedure('public.begin_delivery_transport(uuid,uuid)') IS NULL
    THEN 'VERIFIED' ELSE 'FAILED' END::text AS status,
  'legacy two-argument privileged transport RPC absent after 024'::text AS expected,
  pg_catalog.jsonb_build_object('present',pg_catalog.to_regprocedure('public.begin_delivery_transport(uuid,uuid)') IS NOT NULL) AS actual
),
extra_transport_results AS (
 SELECT 'legacy_rpc:unexpected_transport_overloads'::text AS invariant,
  CASE WHEN count(*)=0 THEN 'VERIFIED' ELSE 'FAILED' END::text AS status,
  'no begin_delivery_transport overload other than (uuid,uuid,text)'::text AS expected,
  pg_catalog.jsonb_build_object('unexpected_overload_count',count(*)) AS actual
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='begin_delivery_transport'
 AND p.oid IS DISTINCT FROM pg_catalog.to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)')
),
ledger_acl_results AS (
 SELECT 'table_acl:public.delivery_ledger'::text AS invariant,
 CASE WHEN pg_catalog.to_regrole('service_role') IS NULL
    OR pg_catalog.to_regrole('authenticated') IS NULL OR pg_catalog.to_regrole('anon') IS NULL
     THEN 'BLOCKED'
 WHEN r.oid IS NULL THEN 'FAILED'
 WHEN NOT pg_catalog.has_table_privilege(pg_catalog.to_regrole('anon')::oid,r.oid,'SELECT,INSERT,UPDATE,DELETE')
  AND NOT pg_catalog.has_table_privilege(pg_catalog.to_regrole('authenticated')::oid,r.oid,'SELECT,INSERT,UPDATE,DELETE')
  AND pg_catalog.has_table_privilege(pg_catalog.to_regrole('service_role')::oid,r.oid,'SELECT')
     THEN 'VERIFIED' ELSE 'FAILED' END::text AS status,
 'anon/authenticated: no direct SELECT/INSERT/UPDATE/DELETE; service_role: SELECT'::text AS expected,
 pg_catalog.jsonb_build_object('ledger_present',r.oid IS NOT NULL) AS actual
 FROM rel r WHERE r.schema_name='public' AND r.rel_name='delivery_ledger'
),
prereq_023 AS (
 SELECT 'migration_023:pre_024_exact_function_contract'::text AS invariant,
 CASE
  WHEN pg_catalog.to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') IS NOT NULL
   AND pg_catalog.to_regprocedure('public.begin_delivery_transport(uuid,uuid)') IS NULL THEN 'UNKNOWN'
  WHEN pg_catalog.to_regprocedure('public.begin_delivery_transport(uuid,uuid)') IS NOT NULL
   AND pg_catalog.to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') IS NULL
   AND (SELECT pg_catalog.md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.enqueue_due_daily_reminders(timestamptz,integer)'))='ad0b49bdc5d6ea94bbc2a73fa40985ac'
   AND (SELECT pg_catalog.md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.enqueue_weekly_goodness_delivery(date,timestamptz,integer)'))='d13eed60e2cf6413d0dd3e0531f5cf77'
   AND (SELECT pg_catalog.md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.begin_delivery_transport(uuid,uuid)'))='a5f2ba15937ab66bbdd71d3e6d175c2d'
   AND coalesce(pg_catalog.obj_description(pg_catalog.to_regprocedure('public.enqueue_due_daily_reminders(timestamptz,integer)'), 'pg_proc'),'')='deedlight:023:daily-exclusion-before-limit:v1'
   AND coalesce(pg_catalog.obj_description(pg_catalog.to_regprocedure('public.enqueue_weekly_goodness_delivery(date,timestamptz,integer)'), 'pg_proc'),'')='deedlight:023:weekly-exclusion-before-limit:v1'
   AND coalesce(pg_catalog.obj_description(pg_catalog.to_regprocedure('public.begin_delivery_transport(uuid,uuid)'), 'pg_proc'),'')='deedlight:023:locked-consent-before-transport:v1'
   THEN 'VERIFIED'
  ELSE 'FAILED'
 END::text AS status,
 'pre-024: all 3 migration-023 body hashes+markers; post-024: replaced/deleted intermediates cannot be verified live'::text AS expected,
 pg_catalog.jsonb_build_object('legacy_transport_present',pg_catalog.to_regprocedure('public.begin_delivery_transport(uuid,uuid)') IS NOT NULL,
   'recipient_bound_transport_present',pg_catalog.to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') IS NOT NULL) AS actual
),
history_results AS (
 SELECT 'migration_history:catalog_object'::text AS invariant,
  CASE WHEN pg_catalog.to_regclass('supabase_migrations.schema_migrations') IS NULL
    THEN 'UNKNOWN' ELSE 'VERIFIED' END::text AS status,
  'migration tracking relation may exist; contents NOT queried by catalog-only audit'::text AS expected,
  pg_catalog.jsonb_build_object('relation_present',pg_catalog.to_regclass('supabase_migrations.schema_migrations') IS NOT NULL) AS actual
 UNION ALL
 SELECT 'migration_history:recorded_versions'::text, 'UNKNOWN'::text,
  'version rows require separate read-only metadata-table authorization'::text,
  pg_catalog.jsonb_build_object('queried',false)
 UNION ALL
 SELECT 'production_identity:independent_project_reference'::text, 'BLOCKED'::text,
  'authorized external attestation that connection belongs to xaipiovflxomcbfwtwmu'::text,
  pg_catalog.jsonb_build_object('database_name',pg_catalog.current_database(),
     'server_version_num',pg_catalog.current_setting('server_version_num'),
     'project_identity_established',false)
 UNION ALL
 SELECT 'schema_history:019_to_024_application_provenance'::text,'UNKNOWN'::text,
  'catalog current state cannot prove historical migration order or CLI history'::text,
  pg_catalog.jsonb_build_object('catalog_only',true)
),
report AS (
 SELECT * FROM object_results UNION ALL SELECT * FROM column_results
 UNION ALL SELECT * FROM constraint_results UNION ALL SELECT * FROM unique_results
 UNION ALL SELECT * FROM primary_key_results UNION ALL SELECT * FROM constraint_definition_results
 UNION ALL SELECT * FROM rls_results UNION ALL SELECT * FROM policy_results
 UNION ALL SELECT * FROM policy_inventory_results UNION ALL SELECT * FROM rpc_schema_usage_results
 UNION ALL SELECT * FROM function_results UNION ALL SELECT * FROM function_acl_results
 UNION ALL SELECT * FROM preference_function_results UNION ALL SELECT * FROM legacy_results
 UNION ALL SELECT * FROM extra_transport_results UNION ALL SELECT * FROM ledger_acl_results
 UNION ALL SELECT * FROM prereq_023 UNION ALL SELECT * FROM history_results
)
SELECT pg_catalog.jsonb_build_object(
 'source_sha',params.source_sha,
 'invariant',r.invariant,
 'status',r.status,
 'expected',r.expected,
 'actual',r.actual
) AS audit_record
FROM report r CROSS JOIN params
ORDER BY r.invariant;
ROLLBACK;
