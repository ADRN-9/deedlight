-- DeedLight Production migration reconciliation: metadata-only read-only audit.
-- Run only through the approved, isolated evidence collector.
-- This script reads PostgreSQL catalogs and migration-history identifiers only.
-- It never reads application table rows, private reflections, emails, tokens, or webhook payloads.
-- Required collector-provided, non-secret connection metadata:
--   deedlight.expected_project_ref = xaipiovflxomcbfwtwmu
--   deedlight.repository_sha = exact 40-character Git SHA being audited
-- These custom settings are untrusted consistency labels, not authentication or proof of endpoint identity.
-- deedlight.authenticated_principal must equal the authenticated session_user; SQL independently
-- validates that login and the effective current_user. SECURITY DEFINER may change current_user;
-- SET ROLE is rejected. A superuser can still impersonate with SET SESSION AUTHORIZATION, so the
-- collector MUST connect directly as deedlight_catalog_auditor over independently verified TLS.

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';

DO $audit_preflight$
DECLARE
  v_project_ref text := pg_catalog.current_setting('deedlight.expected_project_ref', true);
  v_repository_sha text := pg_catalog.current_setting('deedlight.repository_sha', true);
  v_history_oid oid;
  v_catalog text;
  v_session_role_oid oid;
  v_effective_role_oid oid;
  v_authenticated_principal text := pg_catalog.current_setting('deedlight.authenticated_principal', true);
  v_role_setting text := pg_catalog.current_setting('role', true);
  v_relation record;
  v_privilege text;
  v_history_column_count integer;
  v_version_attnum smallint;
  v_history_index_count integer;
  v_unsafe_routine text;
  v_unsafe_setting text;
  v_unsafe_routine_oid oid;
  v_database_owner oid;
  v_unsafe_schema text;
BEGIN
  IF pg_catalog.current_setting('transaction_read_only') <> 'on' THEN
    RAISE EXCEPTION 'Audit must execute in a read-only transaction.';
  END IF;
  IF v_project_ref IS DISTINCT FROM 'xaipiovflxomcbfwtwmu' THEN
    RAISE EXCEPTION 'Missing or unexpected DeedLight Production project reference.';
  END IF;
  IF v_repository_sha IS NULL OR v_repository_sha !~ '^[0-9a-f]{40}$' THEN
    RAISE EXCEPTION 'Exact repository SHA is required as collector metadata.';
  END IF;
  -- session_user is the authenticated login principal; current_user may legitimately
  -- be a SECURITY DEFINER owner. Do not require those identities to be equal.
  IF session_user <> 'deedlight_catalog_auditor'
    OR v_authenticated_principal IS DISTINCT FROM session_user THEN
    RAISE EXCEPTION 'Authenticated collector principal is missing, malformed, or not authorized.';
  END IF;
  IF v_role_setting IS DISTINCT FROM 'none' THEN
    RAISE EXCEPTION 'SET ROLE is prohibited for the migration audit collector.';
  END IF;

  -- Resolve non-system migration history only after the authenticated login is trusted.
  v_history_oid := pg_catalog.to_regclass('supabase_migrations.schema_migrations');

  SELECT oid INTO v_session_role_oid
  FROM pg_catalog.pg_roles
  WHERE rolname = session_user;
  SELECT oid INTO v_effective_role_oid
  FROM pg_catalog.pg_roles
  WHERE rolname = current_user;
  IF v_session_role_oid IS NULL OR v_effective_role_oid IS NULL THEN
    RAISE EXCEPTION 'Authenticated or effective database role identity is unavailable.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE oid = v_session_role_oid AND rolcanlogin
      AND NOT rolsuper AND NOT rolcreaterole AND NOT rolcreatedb
      AND NOT rolreplication AND NOT rolbypassrls
      AND NOT rolinherit
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE oid = v_effective_role_oid
      AND NOT rolsuper AND NOT rolcreaterole AND NOT rolcreatedb
      AND NOT rolreplication AND NOT rolbypassrls
      AND NOT rolinherit
  ) THEN
    RAISE EXCEPTION 'Authenticated or effective role violates the NOINHERIT least-privilege identity contract.';
  END IF;
  FOREACH v_catalog IN ARRAY ARRAY[
    'pg_catalog.pg_class', 'pg_catalog.pg_attribute', 'pg_catalog.pg_attrdef',
    'pg_catalog.pg_proc', 'pg_catalog.pg_roles', 'pg_catalog.pg_auth_members',
    'pg_catalog.pg_namespace', 'pg_catalog.pg_language', 'pg_catalog.pg_policies',
    'pg_catalog.pg_constraint', 'pg_catalog.pg_indexes', 'pg_catalog.pg_trigger',
    'pg_catalog.pg_default_acl', 'pg_catalog.pg_extension', 'pg_catalog.pg_sequence',
    'pg_catalog.pg_index', 'pg_catalog.pg_depend', 'pg_catalog.pg_type', 'pg_catalog.pg_am', 'pg_catalog.pg_database'
  ] LOOP
    IF pg_catalog.to_regclass(v_catalog) IS NULL
      OR NOT pg_catalog.has_table_privilege(v_session_role_oid, pg_catalog.to_regclass(v_catalog), 'SELECT')
      OR NOT pg_catalog.has_table_privilege(v_effective_role_oid, pg_catalog.to_regclass(v_catalog), 'SELECT') THEN
      RAISE EXCEPTION 'Required catalog SELECT access unavailable to authenticated/effective principal: %', v_catalog;
    END IF;
  END LOOP;

  SELECT d.datdba INTO v_database_owner
  FROM pg_catalog.pg_database d
  WHERE d.datname = pg_catalog.current_database();
  IF v_database_owner IS NULL
    OR v_database_owner IN (v_session_role_oid, v_effective_role_oid) THEN
    RAISE EXCEPTION 'Collector role owns the current database.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_namespace n
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND n.nspname NOT LIKE 'pg_toast%'
      AND (n.nspowner IN (v_session_role_oid, v_effective_role_oid)
        OR pg_catalog.has_schema_privilege(v_session_role_oid, n.oid, 'CREATE')
        OR pg_catalog.has_schema_privilege(v_effective_role_oid, n.oid, 'CREATE'))
  ) THEN
    RAISE EXCEPTION 'Collector role owns an application schema or has schema CREATE privilege.';
  END IF;

  -- Application routines are not executable by the collector or PUBLIC.
  -- pg_proc OIDs cover functions, procedures, aggregates and window functions;
  -- ACL expansion uses PostgreSQL's built-in default ACL when proacl is NULL.
  SELECT p.oid, pg_catalog.format('%I.%I', n.nspname, p.proname)
  INTO v_unsafe_routine_oid, v_unsafe_routine
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
    AND n.nspname NOT LIKE 'pg_toast%'
    AND (
      EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(
          COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
        ) acl
        WHERE acl.privilege_type = 'EXECUTE'
          AND acl.grantee IN (0, v_session_role_oid, v_effective_role_oid)
      )
      OR pg_catalog.has_function_privilege(v_session_role_oid, p.oid, 'EXECUTE')
      OR pg_catalog.has_function_privilege(v_effective_role_oid, p.oid, 'EXECUTE')
    )
  ORDER BY p.oid
  LIMIT 1;
  IF v_unsafe_routine_oid IS NOT NULL THEN
    RAISE EXCEPTION 'Collector or PUBLIC has prohibited EXECUTE privilege on application routine % (OID %).',
      v_unsafe_routine, v_unsafe_routine_oid;
  END IF;

  -- Future routine defaults are checked globally and per schema. A NULL routine
  -- ACL is not treated as empty: PostgreSQL's acldefault('f', owner) grants PUBLIC EXECUTE.
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_default_acl d
    CROSS JOIN LATERAL pg_catalog.aclexplode(d.defaclacl) acl
    WHERE d.defaclobjtype = 'f'
      AND acl.privilege_type = 'EXECUTE'
      AND (
        acl.grantee = 0
        OR acl.grantee IN (v_session_role_oid, v_effective_role_oid)
      )
  ) THEN
    RAISE EXCEPTION 'Global or schema-specific default routine privileges expose prohibited EXECUTE or grant-option access.';
  END IF;

  -- pg_default_acl stores only altered defaults. When a routine-owner role has
  -- no global row, PostgreSQL's acldefault('f', owner) still grants PUBLIC EXECUTE.
  -- Check every role able to CREATE in an application schema, including superusers;
  -- pg_database_owner is a pseudo-role whose current database owner is checked by OID.
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles owner_role
    WHERE owner_role.rolname <> 'pg_database_owner'
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.pg_namespace n
        WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
          AND n.nspname NOT LIKE 'pg_toast%'
          AND (
            n.nspowner = owner_role.oid
            OR pg_catalog.has_schema_privilege(owner_role.oid, n.oid, 'CREATE')
          )
      )
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.aclexplode(COALESCE(
          (
            SELECT d.defaclacl
            FROM pg_catalog.pg_default_acl d
            WHERE d.defaclrole = owner_role.oid
              AND d.defaclnamespace = 0
              AND d.defaclobjtype = 'f'
          ),
          pg_catalog.acldefault('f', owner_role.oid)
        )) global_acl
        WHERE global_acl.privilege_type = 'EXECUTE'
          AND (
            global_acl.grantee = 0
            OR global_acl.grantee IN (v_session_role_oid, v_effective_role_oid)
          )
      )
  ) THEN
    RAISE EXCEPTION 'Implicit or configured global routine defaults expose prohibited PUBLIC or collector EXECUTE.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles r
    WHERE r.oid <> v_session_role_oid
      AND pg_catalog.pg_has_role(v_session_role_oid, r.oid, 'MEMBER')
  ) OR EXISTS (
    SELECT 1
    FROM pg_catalog.pg_roles r
    WHERE r.oid <> v_effective_role_oid
      AND pg_catalog.pg_has_role(v_effective_role_oid, r.oid, 'MEMBER')
  ) THEN
    RAISE EXCEPTION 'Authenticated or effective collector role has role membership.';
  END IF;

  -- Routine settings are a reviewed allowlist, not a raw pg_proc.proconfig export.
  -- Reject custom GUCs, noncanonical search paths and unsafe limits before serialization.
  SELECT pg_catalog.format('%I.%I', n.nspname, p.proname), parsed.setting_name
  INTO v_unsafe_routine, v_unsafe_setting
  FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    CROSS JOIN LATERAL pg_catalog.unnest(COALESCE(p.proconfig, ARRAY[]::text[])) cfg(setting)
    CROSS JOIN LATERAL (
      SELECT
        pg_catalog.split_part(cfg.setting, '=', 1) AS setting_name,
        CASE
          WHEN pg_catalog.split_part(cfg.setting, '=', 1) = 'search_path'
            THEN pg_catalog.btrim(pg_catalog.regexp_replace(cfg.setting, '^[^=]*=', ''), '"')
          ELSE pg_catalog.regexp_replace(cfg.setting, '^[^=]*=', '')
        END AS setting_value
    ) parsed
    LEFT JOIN LATERAL (
      SELECT pg_catalog.regexp_match(
        parsed.setting_value,
        '^([1-9][0-9]{0,8})(us|ms|s|min|h|d)?$',
        'i'
      ) AS parts
    ) timeout_value ON true
    LEFT JOIN LATERAL (
      SELECT pg_catalog.regexp_match(
        parsed.setting_value,
        '^([1-9][0-9]{0,9})(kb|mb|gb)?$',
        'i'
      ) AS parts
    ) temp_file_value ON true
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND n.nspname NOT LIKE 'pg_toast%'
      AND (
        position('=' IN cfg.setting) = 0
        OR NOT (
          (
            parsed.setting_name = 'search_path'
            AND parsed.setting_value ~ '^(pg_catalog|public|extensions|auth|storage)(, ?(pg_catalog|public|extensions|auth|storage))*(, ?pg_temp)?$'
            AND pg_catalog.cardinality(pg_catalog.string_to_array(pg_catalog.replace(parsed.setting_value, ' ', ''), ','))
              = pg_catalog.cardinality(ARRAY(
                SELECT DISTINCT schema_name
                FROM pg_catalog.unnest(pg_catalog.string_to_array(pg_catalog.replace(parsed.setting_value, ' ', ''), ',')) AS path_schemas(schema_name)
              ))
            AND NOT EXISTS (
              SELECT 1
              FROM pg_catalog.unnest(pg_catalog.string_to_array(pg_catalog.replace(parsed.setting_value, ' ', ''), ',')) WITH ORDINALITY path(schema_name, ordinal)
              WHERE (path.schema_name = 'pg_catalog' AND path.ordinal <> 1)
                OR (path.schema_name = 'pg_temp' AND path.ordinal <>
                  pg_catalog.cardinality(pg_catalog.string_to_array(pg_catalog.replace(parsed.setting_value, ' ', ''), ',')))
            )
            AND NOT EXISTS (
              SELECT 1
              FROM pg_catalog.unnest(pg_catalog.string_to_array(pg_catalog.replace(parsed.setting_value, ' ', ''), ',')) WITH ORDINALITY earlier(schema_name, ordinal)
              JOIN pg_catalog.unnest(pg_catalog.string_to_array(pg_catalog.replace(parsed.setting_value, ' ', ''), ',')) WITH ORDINALITY later(schema_name, ordinal)
                ON earlier.ordinal < later.ordinal
              WHERE pg_catalog.array_position(
                ARRAY['pg_catalog','public','extensions','auth','storage','pg_temp']::text[],
                earlier.schema_name
              ) >= pg_catalog.array_position(
                ARRAY['pg_catalog','public','extensions','auth','storage','pg_temp']::text[],
                later.schema_name
              )
            )
            AND NOT EXISTS (
              SELECT 1
              FROM pg_catalog.unnest(pg_catalog.string_to_array(pg_catalog.replace(parsed.setting_value, ' ', ''), ',')) path(schema_name)
              WHERE path.schema_name <> 'pg_temp'
                AND NOT EXISTS (
                  SELECT 1 FROM pg_catalog.pg_namespace path_ns
                  WHERE path_ns.nspname = path.schema_name
                )
            )
            AND NOT EXISTS (
              SELECT 1
              FROM pg_catalog.unnest(pg_catalog.string_to_array(pg_catalog.replace(parsed.setting_value, ' ', ''), ',')) path(schema_name)
              JOIN pg_catalog.pg_namespace path_ns ON path_ns.nspname = path.schema_name
              JOIN pg_catalog.pg_roles path_owner ON path_owner.oid = path_ns.nspowner
              WHERE path.schema_name <> 'pg_catalog'
                AND (
                  path_owner.rolcanlogin AND NOT path_owner.rolsuper
                  OR EXISTS (
                    SELECT 1
                    FROM pg_catalog.pg_roles owner_member
                    WHERE owner_member.rolcanlogin AND NOT owner_member.rolsuper
                      AND owner_member.oid <> (
                        SELECT database_owner.datdba
                        FROM pg_catalog.pg_database database_owner
                        WHERE database_owner.datname = pg_catalog.current_database()
                      )
                      AND pg_catalog.pg_has_role(owner_member.oid, path_owner.oid, 'MEMBER')
                  )
                  OR EXISTS (
                    SELECT 1
                    FROM pg_catalog.aclexplode(
                      COALESCE(path_ns.nspacl, pg_catalog.acldefault('n', path_ns.nspowner))
                    ) acl
                    WHERE acl.grantee = 0 AND acl.privilege_type = 'CREATE'
                  )
                  OR EXISTS (
                    SELECT 1
                    FROM pg_catalog.pg_roles creator
                    WHERE NOT creator.rolsuper
                      AND creator.oid <> path_ns.nspowner
                      AND creator.oid <> (
                        SELECT database_owner.datdba
                        FROM pg_catalog.pg_database database_owner
                        WHERE database_owner.datname = pg_catalog.current_database()
                      )
                      AND pg_catalog.has_schema_privilege(creator.oid, path_ns.oid, 'CREATE')
                      AND NOT pg_catalog.pg_has_role(creator.oid, path_ns.nspowner, 'MEMBER')
                  )
                )
            )
          )
          OR (parsed.setting_name = 'row_security' AND parsed.setting_value = 'on')
          OR (parsed.setting_name = 'default_transaction_read_only' AND parsed.setting_value = 'on')
          OR (
            parsed.setting_name IN (
              'statement_timeout', 'lock_timeout', 'idle_in_transaction_session_timeout'
            )
            AND timeout_value.parts IS NOT NULL
            AND timeout_value.parts[1]::numeric *
              CASE pg_catalog.lower(COALESCE(timeout_value.parts[2], 'ms'))
                WHEN 'us' THEN 0.001
                WHEN 'ms' THEN 1
                WHEN 's' THEN 1000
                WHEN 'min' THEN 60000
                WHEN 'h' THEN 3600000
                WHEN 'd' THEN 86400000
              END
              <= CASE parsed.setting_name
                WHEN 'statement_timeout' THEN 300000
                WHEN 'lock_timeout' THEN 30000
                WHEN 'idle_in_transaction_session_timeout' THEN 60000
              END
          )
          OR (
            parsed.setting_name = 'temp_file_limit'
            AND temp_file_value.parts IS NOT NULL
            AND temp_file_value.parts[1]::numeric *
              CASE pg_catalog.lower(COALESCE(temp_file_value.parts[2], 'b'))
                WHEN 'b' THEN 1
                WHEN 'kb' THEN 1024
                WHEN 'mb' THEN 1048576
                WHEN 'gb' THEN 1073741824
              END
              <= 1073741824
          )
        )
      )
  LIMIT 1;

  IF v_unsafe_routine IS NOT NULL THEN
    RAISE EXCEPTION 'Unexpected or unsafe routine configuration for % setting %; allowlisted settings only.',
      v_unsafe_routine, v_unsafe_setting;
  END IF;

  v_history_oid := pg_catalog.to_regclass('supabase_migrations.schema_migrations');
  IF v_history_oid IS NULL THEN
    RAISE EXCEPTION 'Required Supabase migration-history table is unavailable.';
  END IF;
  IF NOT pg_catalog.has_table_privilege(v_session_role_oid, v_history_oid, 'SELECT')
    OR NOT pg_catalog.has_table_privilege(v_effective_role_oid, v_history_oid, 'SELECT')
    OR (SELECT relowner FROM pg_catalog.pg_class WHERE oid = v_history_oid)
      IN (v_session_role_oid, v_effective_role_oid) THEN
    RAISE EXCEPTION 'Collector must have SELECT-only access to migration history without owning it.';
  END IF;
  FOREACH v_privilege IN ARRAY ARRAY['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
    IF pg_catalog.has_table_privilege(v_session_role_oid, v_history_oid, v_privilege)
      OR pg_catalog.has_table_privilege(v_effective_role_oid, v_history_oid, v_privilege) THEN
      RAISE EXCEPTION 'Collector has prohibited % access to migration history.', v_privilege;
    END IF;
  END LOOP;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = v_history_oid AND a.attnum > 0 AND NOT a.attisdropped
      AND (
        pg_catalog.has_column_privilege(v_session_role_oid, v_history_oid, a.attname, 'INSERT')
        OR pg_catalog.has_column_privilege(v_session_role_oid, v_history_oid, a.attname, 'UPDATE')
        OR pg_catalog.has_column_privilege(v_session_role_oid, v_history_oid, a.attname, 'REFERENCES')
        OR pg_catalog.has_column_privilege(v_effective_role_oid, v_history_oid, a.attname, 'INSERT')
        OR pg_catalog.has_column_privilege(v_effective_role_oid, v_history_oid, a.attname, 'UPDATE')
        OR pg_catalog.has_column_privilege(v_effective_role_oid, v_history_oid, a.attname, 'REFERENCES')
      )
  ) THEN
    RAISE EXCEPTION 'Collector has prohibited column-level write access to migration history.';
  END IF;

  SELECT pg_catalog.count(*)::integer INTO v_history_column_count
  FROM pg_catalog.pg_attribute
  WHERE attrelid = v_history_oid AND attnum > 0 AND NOT attisdropped;
  SELECT attnum INTO v_version_attnum
  FROM pg_catalog.pg_attribute
  WHERE attrelid = v_history_oid AND attname = 'version'
    AND attnum > 0 AND NOT attisdropped;
  IF v_history_column_count <> 3
    OR v_version_attnum IS NULL
    OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute a
      WHERE a.attrelid = v_history_oid AND a.attname = 'version'
        AND a.atttypid = 'pg_catalog.text'::regtype AND a.attnotnull
        AND a.attgenerated = '' AND a.attidentity = ''
    )
    OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute a
      WHERE a.attrelid = v_history_oid AND a.attname = 'name'
        AND a.atttypid = 'pg_catalog.text'::regtype AND NOT a.attnotnull
        AND a.attgenerated = '' AND a.attidentity = ''
    )
    OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_attribute a
      WHERE a.attrelid = v_history_oid AND a.attname = 'statements'
        AND a.atttypid = 'pg_catalog.text[]'::regtype AND NOT a.attnotnull
        AND a.attgenerated = '' AND a.attidentity = ''
    )
    OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_attrdef d
      WHERE d.adrelid = v_history_oid
    )
  THEN
    RAISE EXCEPTION 'Unsupported migration-history schema; expected exactly version text NOT NULL, name text NULL, statements text[] NULL.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint c
    WHERE c.conrelid = v_history_oid
      AND NOT (
        c.contype = 'p' AND c.conkey = ARRAY[v_version_attnum]::smallint[]
        AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred
      )
  ) OR (
    SELECT pg_catalog.count(*) FROM pg_catalog.pg_constraint c
    WHERE c.conrelid = v_history_oid
  ) <> 1 THEN
    RAISE EXCEPTION 'Unsupported migration-history constraints; require one validated non-deferrable primary key on version only.';
  END IF;

  SELECT pg_catalog.count(*)::integer INTO v_history_index_count
  FROM pg_catalog.pg_index
  WHERE indrelid = v_history_oid;
  IF v_history_index_count <> 1 OR NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class index_relation ON index_relation.oid = i.indexrelid
    JOIN pg_catalog.pg_am am ON am.oid = index_relation.relam
    JOIN pg_catalog.pg_constraint c ON c.conindid = i.indexrelid
      AND c.conrelid = i.indrelid AND c.contype = 'p'
    WHERE i.indrelid = v_history_oid
      AND index_relation.relkind = 'i'
      AND i.indisprimary AND i.indisunique AND i.indimmediate
      AND i.indisvalid AND i.indisready AND i.indislive
      AND i.indnkeyatts = 1 AND i.indnatts = 1
      AND i.indkey[0] = v_version_attnum
      AND i.indpred IS NULL AND i.indexprs IS NULL
      AND am.amname = 'btree'
  ) THEN
    RAISE EXCEPTION 'Unsupported migration-history indexes; require one valid, ready, live btree primary-key index on version.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
    WHERE c.oid = v_history_oid AND c.relkind = 'r'
      AND c.relpersistence = 'p' AND NOT c.relrowsecurity AND NOT c.relforcerowsecurity
  ) THEN
    RAISE EXCEPTION 'Migration-history table must be a permanent ordinary table without row-level security.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations h
    WHERE h.version !~ '^[0-9]{12}$'
      OR (h.name IS NOT NULL AND h.name !~ '^[A-Za-z0-9_-]+$')
  ) THEN
    RAISE EXCEPTION 'Migration-history contains invalid version or migration-name metadata.';
  END IF;

  IF NOT pg_catalog.has_database_privilege(v_session_role_oid, pg_catalog.current_database(), 'CONNECT')
    OR NOT pg_catalog.has_database_privilege(v_effective_role_oid, pg_catalog.current_database(), 'CONNECT') THEN
    RAISE EXCEPTION 'Collector requires database CONNECT privilege.';
  END IF;
  IF pg_catalog.has_database_privilege(v_session_role_oid, pg_catalog.current_database(), 'CREATE')
    OR pg_catalog.has_database_privilege(v_effective_role_oid, pg_catalog.current_database(), 'CREATE') THEN
    RAISE EXCEPTION 'Collector role has prohibited database CREATE privilege.';
  END IF;
  IF pg_catalog.has_database_privilege(v_session_role_oid, pg_catalog.current_database(), 'TEMP')
    OR pg_catalog.has_database_privilege(v_effective_role_oid, pg_catalog.current_database(), 'TEMP') THEN
    RAISE EXCEPTION 'Collector role has prohibited database TEMP privilege.';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_database d
    CROSS JOIN LATERAL pg_catalog.aclexplode(
      COALESCE(d.datacl, pg_catalog.acldefault('d', d.datdba))
    ) acl
    WHERE d.datname = pg_catalog.current_database()
      AND (
        acl.grantee = 0
        OR acl.grantee IN (v_session_role_oid, v_effective_role_oid)
      )
      AND acl.is_grantable
  ) THEN
    RAISE EXCEPTION 'PUBLIC or collector role has prohibited database grant-option privileges.';
  END IF;
  SELECT n.nspname INTO v_unsafe_schema
  FROM pg_catalog.pg_namespace n
  WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
    AND n.nspname NOT LIKE 'pg_toast%'
    AND n.nspname <> 'supabase_migrations'
    AND (
      pg_catalog.has_schema_privilege(v_session_role_oid, n.oid, 'USAGE')
      OR pg_catalog.has_schema_privilege(v_effective_role_oid, n.oid, 'USAGE')
    )
  ORDER BY n.oid
  LIMIT 1;
  IF v_unsafe_schema IS NOT NULL THEN
    RAISE EXCEPTION 'Collector role has prohibited USAGE on an application schema %.', v_unsafe_schema;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_namespace n
    WHERE n.nspname = 'supabase_migrations'
      AND pg_catalog.has_schema_privilege(v_session_role_oid, n.oid, 'USAGE')
      AND pg_catalog.has_schema_privilege(v_effective_role_oid, n.oid, 'USAGE')
  ) THEN
    RAISE EXCEPTION 'Collector requires USAGE on supabase_migrations schema.';
  END IF;

  -- This also rejects membership in pg_read_all_data, pg_write_all_data,
  -- pg_monitor, pg_read_all_settings, pg_read_server_files and service_role.
  FOR v_relation IN
    SELECT c.oid, c.relkind, c.relowner, n.nspname, c.relname
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND n.nspname NOT LIKE 'pg_toast%' AND c.oid <> v_history_oid
      AND c.relkind IN ('r','p','v','m','f','S')
  LOOP
    IF v_relation.relowner IN (v_session_role_oid, v_effective_role_oid) THEN
      RAISE EXCEPTION 'Collector owns application object %.%.', v_relation.nspname, v_relation.relname;
    END IF;
    IF v_relation.relkind = 'S' THEN
      FOREACH v_privilege IN ARRAY ARRAY['USAGE','SELECT','UPDATE'] LOOP
        IF pg_catalog.has_sequence_privilege(v_session_role_oid, v_relation.oid, v_privilege)
          OR pg_catalog.has_sequence_privilege(v_effective_role_oid, v_relation.oid, v_privilege) THEN
          RAISE EXCEPTION 'Collector has prohibited % access to application sequence %.%.',
            v_privilege, v_relation.nspname, v_relation.relname;
        END IF;
      END LOOP;
    ELSE
      FOREACH v_privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
        IF pg_catalog.has_table_privilege(v_session_role_oid, v_relation.oid, v_privilege)
          OR pg_catalog.has_table_privilege(v_effective_role_oid, v_relation.oid, v_privilege) THEN
          RAISE EXCEPTION 'Collector has prohibited % access to application relation %.%.',
            v_privilege, v_relation.nspname, v_relation.relname;
        END IF;
      END LOOP;
      FOREACH v_privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','REFERENCES'] LOOP
        IF pg_catalog.has_any_column_privilege(v_session_role_oid, v_relation.oid, v_privilege)
          OR pg_catalog.has_any_column_privilege(v_effective_role_oid, v_relation.oid, v_privilege) THEN
          RAISE EXCEPTION 'Collector has prohibited column-level % access to application relation %.%.',
            v_privilege, v_relation.nspname, v_relation.relname;
        END IF;
      END LOOP;
    END IF;
  END LOOP;
END
$audit_preflight$;

-- 01. Capture identity and time. Endpoint/TLS verification is performed independently by the collector.
SELECT
  pg_catalog.current_setting('deedlight.expected_project_ref') AS expected_project_ref,
  pg_catalog.current_setting('deedlight.repository_sha') AS repository_sha,
  pg_catalog.current_database() AS database_name,
  current_user AS current_role,
  session_user AS session_role,
  pg_catalog.current_setting('server_version') AS server_version,
  pg_catalog.inet_server_addr()::text AS server_address,
  pg_catalog.inet_server_port() AS server_port,
  pg_catalog.to_char(pg_catalog.clock_timestamp() AT TIME ZONE 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS captured_at_utc,
  pg_catalog.current_setting('transaction_read_only') AS transaction_read_only;

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
  COALESCE((
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'name', pg_catalog.split_part(cfg.setting, '=', 1),
        'value', CASE
          WHEN pg_catalog.split_part(cfg.setting, '=', 1) = 'search_path'
            THEN pg_catalog.btrim(pg_catalog.regexp_replace(cfg.setting, '^[^=]*=', ''), '"')
          ELSE pg_catalog.regexp_replace(cfg.setting, '^[^=]*=', '')
        END
      )
      ORDER BY pg_catalog.split_part(cfg.setting, '=', 1),
        CASE
          WHEN pg_catalog.split_part(cfg.setting, '=', 1) = 'search_path'
            THEN pg_catalog.btrim(pg_catalog.regexp_replace(cfg.setting, '^[^=]*=', ''), '"')
          ELSE pg_catalog.regexp_replace(cfg.setting, '^[^=]*=', '')
        END
    )
    FROM pg_catalog.unnest(COALESCE(p.proconfig, ARRAY[]::text[])) cfg(setting)
  ), '[]'::jsonb) AS routine_settings
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
  r.rolvaliduntil
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

SELECT
  n.nspname AS schema_name,
  tbl.relname AS table_name,
  idx.relname AS index_name,
  i.indisunique AS is_unique,
  i.indisprimary AS is_primary,
  i.indisexclusion AS is_exclusion,
  i.indisvalid AS is_valid,
  i.indisready AS is_ready,
  i.indislive AS is_live,
  i.indisreplident AS is_replica_identity,
  i.indnullsnotdistinct AS nulls_not_distinct,
  pg_catalog.pg_get_indexdef(i.indexrelid) AS index_definition
FROM pg_catalog.pg_index i
JOIN pg_catalog.pg_class idx ON idx.oid = i.indexrelid
JOIN pg_catalog.pg_class tbl ON tbl.oid = i.indrelid
JOIN pg_catalog.pg_namespace n ON n.oid = tbl.relnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, tbl.relname, idx.relname;

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

-- Sequence definitions, ownership dependencies and ACLs.
SELECT
  n.nspname AS schema_name,
  seqrel.relname AS sequence_name,
  pg_catalog.pg_get_userbyid(seqrel.relowner) AS owner_name,
  pg_catalog.format_type(s.seqtypid, NULL) AS sequence_data_type,
  s.seqstart AS start_value,
  s.seqincrement AS increment_by,
  s.seqmin AS minimum_value,
  s.seqmax AS maximum_value,
  s.seqcache AS cache_size,
  s.seqcycle AS cycles,
  owner_ns.nspname AS owned_table_schema,
  owner_tbl.relname AS owned_table_name,
  owner_col.attname AS owned_column_name
FROM pg_catalog.pg_class seqrel
JOIN pg_catalog.pg_namespace n ON n.oid = seqrel.relnamespace
JOIN pg_catalog.pg_sequence s ON s.seqrelid = seqrel.oid
LEFT JOIN pg_catalog.pg_depend d
  ON d.classid = 'pg_catalog.pg_class'::regclass
  AND d.objid = seqrel.oid
  AND d.refclassid = 'pg_catalog.pg_class'::regclass
  AND d.deptype IN ('a','i')
  AND d.refobjsubid > 0
LEFT JOIN pg_catalog.pg_class owner_tbl ON owner_tbl.oid = d.refobjid
LEFT JOIN pg_catalog.pg_namespace owner_ns ON owner_ns.oid = owner_tbl.relnamespace
LEFT JOIN pg_catalog.pg_attribute owner_col
  ON owner_col.attrelid = owner_tbl.oid AND owner_col.attnum = d.refobjsubid
WHERE seqrel.relkind = 'S'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, seqrel.relname;

SELECT
  n.nspname AS schema_name,
  c.relname AS sequence_name,
  pg_catalog.pg_get_userbyid(c.relowner) AS owner_name,
  CASE WHEN x.grantee = 0 THEN 'PUBLIC'
       ELSE pg_catalog.pg_get_userbyid(x.grantee) END AS grantee,
  pg_catalog.pg_get_userbyid(x.grantor) AS grantor,
  x.privilege_type,
  x.is_grantable
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(
  COALESCE(c.relacl, pg_catalog.acldefault('S', c.relowner))
) x
WHERE c.relkind = 'S'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, c.relname, grantee, x.privilege_type;

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
WHERE a.attrelid = pg_catalog.to_regclass('supabase_migrations.schema_migrations')
  AND a.attnum > 0
  AND NOT a.attisdropped
ORDER BY a.attnum;

-- 13. Migration-history identifiers only. Never export statements or application data.
SELECT
  h.version::text AS version,
  h.name::text AS migration_name,
  pg_catalog.cardinality(h.statements) AS recorded_statement_count
FROM supabase_migrations.schema_migrations AS h
ORDER BY h.version, h.name;

-- 14. Complete database ACL evidence. Emit every database, including templates,
-- preserving the original NULL/non-NULL datacl state while expanding built-in defaults.
-- This projection is a mandatory input to the canonical result digest; omitting it invalidates the evidence receipt.
-- JSONB object keys are canonical and ACL edges are explicitly ordered for stable digests.
SELECT
  'database_acl_v1' AS evidence_projection,
  d.oid AS database_oid,
  d.datname AS database_name,
  d.datallowconn AS allows_connections,
  d.datistemplate AS is_template,
  d.datdba AS owner_oid,
  owner_role.rolname AS owner_name,
  (d.datacl IS NULL) AS datacl_was_null,
  CASE WHEN d.datacl IS NULL THEN 'built_in_default' ELSE 'explicit' END AS acl_expansion_source,
  COALESCE(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'grantee_oid', acl.grantee,
        'grantee_name', CASE
          WHEN acl.grantee = 0 THEN 'PUBLIC'
          ELSE grantee_role.rolname
        END,
        'grantor_oid', acl.grantor,
        'grantor_name', grantor_role.rolname,
        'privilege_type', acl.privilege_type,
        'is_grantable', acl.is_grantable
      )
      ORDER BY acl.grantee, acl.grantor, acl.privilege_type, acl.is_grantable
    ) FILTER (WHERE acl.grantee IS NOT NULL),
    '[]'::jsonb
  ) AS expanded_acl_edges
FROM pg_catalog.pg_database d
JOIN pg_catalog.pg_roles owner_role ON owner_role.oid = d.datdba
LEFT JOIN LATERAL pg_catalog.aclexplode(
  COALESCE(d.datacl, pg_catalog.acldefault('d', d.datdba))
) acl ON true
LEFT JOIN pg_catalog.pg_roles grantee_role ON grantee_role.oid = acl.grantee
LEFT JOIN pg_catalog.pg_roles grantor_role ON grantor_role.oid = acl.grantor
GROUP BY d.oid, d.datname, d.datallowconn, d.datistemplate,
  d.datdba, owner_role.rolname, d.datacl
ORDER BY d.oid, d.datname;

-- The collector captures the result digest and commits its own signed receipt outside this database.
-- Roll back the read-only snapshot explicitly; no database state is changed.
ROLLBACK;
