-- DeedLight Cycle 67 — ISOLATED, UNAPPROVED successor to the C65 proposal.
-- PostgreSQL 16 target. NEVER run against Production.
-- Must be run on a disposable database in the SAME psql session, after an
-- independently reviewed authentic 025-028 inventory seeds
-- pg_temp.c67_reviewed_event_tables (schema_name, table_name, role_in_pipeline).
-- The reviewed source/manifest is NOT present in this assignment. Without it,
-- this migration intentionally fails closed before any persistent DDL.
-- Stops legacy acceptance and outbound transport; DOES NOT activate intake.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $c67_preflight$
DECLARE
  v_missing text;
BEGIN
  IF pg_catalog.to_regnamespace('deedlight_event_private') IS NULL
     OR pg_catalog.to_regclass('deedlight_event_private.provider_event_registry') IS NULL
     OR pg_catalog.to_regclass('deedlight_event_private.registry_control') IS NULL
     OR pg_catalog.to_regclass('deedlight_event_private.provider_event_quarantine') IS NULL
     OR pg_catalog.to_regprocedure('public.deedlight_reserve_provider_event(text,text,bytea,text,text)') IS NULL
     OR pg_catalog.to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') IS NULL
     OR pg_catalog.to_regclass('public.delivery_provider_identity_conflicts') IS NULL
     OR pg_catalog.to_regclass('deedlight_event_private.c65_legacy_veto_inventory') IS NOT NULL
     OR pg_catalog.to_regclass('deedlight_event_private.c67_legacy_veto_inventory') IS NOT NULL
     OR pg_catalog.to_regclass('pg_temp.c67_reviewed_event_tables') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'service_role')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'anon')
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'authenticated')
  THEN
    RAISE EXCEPTION 'C67 missing verified registry/024/025-028 inventory or required roles'
      USING ERRCODE = '55000';
  END IF;

  IF (SELECT accepting_new_events FROM deedlight_event_private.registry_control
      WHERE singleton = true) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'C67 requires registry to remain disabled'
      USING ERRCODE = '55000';
  END IF;

  -- Closed-world inventory is sourced from authenticated migration review, not
  -- inferred from fragile table names. The staging table is session-local and
  -- is dropped when the disposable psql session closes. It MUST list every processed, pending and conflict
  -- table, including public.delivery_provider_identity_conflicts.
  IF EXISTS (
      SELECT 1 FROM pg_temp.c67_reviewed_event_tables
      WHERE schema_name NOT IN ('public','delivery_private','deedlight_delivery_private')
         OR role_in_pipeline NOT IN ('processed','pending','identity_conflict')
         OR schema_name IS NULL OR table_name IS NULL
    ) OR (SELECT count(*) FROM pg_temp.c67_reviewed_event_tables) < 3
    OR (SELECT count(*) FROM pg_temp.c67_reviewed_event_tables
        WHERE role_in_pipeline = 'processed') < 1
    OR (SELECT count(*) FROM pg_temp.c67_reviewed_event_tables
        WHERE role_in_pipeline = 'pending') < 1
    OR (SELECT count(*) FROM pg_temp.c67_reviewed_event_tables
        WHERE role_in_pipeline = 'identity_conflict') < 1
    OR NOT EXISTS (
      SELECT 1 FROM pg_temp.c67_reviewed_event_tables
      WHERE schema_name = 'public'
        AND table_name = 'delivery_provider_identity_conflicts'
        AND role_in_pipeline = 'identity_conflict'
    )
  THEN
    RAISE EXCEPTION 'C67 requires complete explicit processed/pending/conflict inventory'
      USING ERRCODE = '55000';
  END IF;

  SELECT pg_catalog.format('%I.%I', t.schema_name, t.table_name)
    INTO v_missing
  FROM pg_temp.c67_reviewed_event_tables t
  LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = t.schema_name
  LEFT JOIN pg_catalog.pg_class c ON c.relnamespace = n.oid
       AND c.relname = t.table_name AND c.relkind = 'r'
  WHERE c.oid IS NULL
  ORDER BY t.schema_name,t.table_name LIMIT 1;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'C67 reviewed table missing or not ordinary table'
      USING ERRCODE = '55000';
  END IF;

  -- Detect plausible unreviewed acceptance tables by their exact data-column
  -- signature, NOT a name regular expression. False positives intentionally
  -- halt the migration for human source accounting.
  IF EXISTS (
      SELECT 1 FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid
           AND a.attname='event_id' AND a.attnum>0 AND NOT a.attisdropped
      WHERE c.relkind='r'
        AND n.nspname IN ('public','delivery_private','deedlight_delivery_private')
        AND EXISTS (
          SELECT 1 FROM pg_catalog.pg_attribute b
          WHERE b.attrelid=c.oid AND b.attname IN
            ('provider','provider_event_id','event_type','payload_sha256','provider_message_id')
            AND b.attnum>0 AND NOT b.attisdropped
        )
        AND NOT EXISTS (
          SELECT 1 FROM pg_temp.c67_reviewed_event_tables t
          WHERE t.schema_name=n.nspname AND t.table_name=c.relname
        )
    ) THEN
    RAISE EXCEPTION 'C67 found an unreviewed provider-event acceptance table'
      USING ERRCODE = '55000';
  END IF;

  -- The two known base and identity-bound RPC families MUST both exist in the
  -- authentic baseline. Do not silently drop the reviewer-discovered base RPC.
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='record_resend_webhook_event'
      AND p.prokind='f'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='record_resend_webhook_event_identity_bound'
      AND p.prokind='f'
  ) THEN
    RAISE EXCEPTION 'C67 authentic base/wrapper RPC signatures missing; no guesswork'
      USING ERRCODE = '55000';
  END IF;

  -- A service-role member of a legacy table's owning role could disable
  -- triggers directly. Fail closed rather than treat REVOKE as protection.
  IF EXISTS (
    SELECT 1 FROM pg_temp.c67_reviewed_event_tables t
    JOIN pg_catalog.pg_namespace n ON n.nspname=t.schema_name
    JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid AND c.relname=t.table_name
    WHERE pg_catalog.pg_has_role('service_role', c.relowner, 'MEMBER')
       OR pg_catalog.pg_has_role('anon', c.relowner, 'MEMBER')
       OR pg_catalog.pg_has_role('authenticated', c.relowner, 'MEMBER')
  ) THEN
    RAISE EXCEPTION 'C67 a caller can own/disable a legacy table protection'
      USING ERRCODE = '42501';
  END IF;
END
$c67_preflight$;

-- Metadata only: original rows are not touched and recipient identifiers are
-- not copied. This private audit inventory is immutable evidence of installed
-- physical vetoes; it is NOT a permission allowlist for intake.
CREATE TABLE deedlight_event_private.c67_legacy_veto_inventory (
  schema_name text NOT NULL,
  table_name text NOT NULL,
  role_in_pipeline text NOT NULL,
  installed_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  PRIMARY KEY (schema_name, table_name)
);
REVOKE ALL ON deedlight_event_private.c67_legacy_veto_inventory
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE deedlight_event_private.c67_retired_rpc_inventory (
  signature text PRIMARY KEY,
  owner_role text NOT NULL,
  security_definer boolean NOT NULL,
  source_md5 text NOT NULL,
  service_role_execute_before boolean NOT NULL,
  anon_execute_before boolean NOT NULL,
  authenticated_execute_before boolean NOT NULL,
  dependent_objects_before integer NOT NULL,
  search_path_setting text,
  retired_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp()
);
REVOKE ALL ON deedlight_event_private.c67_retired_rpc_inventory
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION deedlight_event_private.c67_reject_legacy_event_write()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $c67_reject$
BEGIN
  RAISE EXCEPTION 'Legacy provider-event acceptance disabled pending reviewed registry migration'
    USING ERRCODE = '55000';
  RETURN NULL;
END
$c67_reject$;
REVOKE ALL ON FUNCTION deedlight_event_private.c67_reject_legacy_event_write()
  FROM PUBLIC, anon, authenticated, service_role;

DO $c67_install$
DECLARE r record;
BEGIN
  -- No pattern discovery: every table is explicitly attested and verified.
  FOR r IN SELECT schema_name,table_name,role_in_pipeline
           FROM pg_temp.c67_reviewed_event_tables ORDER BY 1,2 LOOP
    EXECUTE pg_catalog.format(
      'CREATE TRIGGER c67_deny_legacy_event_dml BEFORE INSERT OR UPDATE OR DELETE ON %I.%I FOR EACH ROW EXECUTE FUNCTION deedlight_event_private.c67_reject_legacy_event_write()',
      r.schema_name,r.table_name);
    EXECUTE pg_catalog.format(
      'ALTER TABLE %I.%I ENABLE ALWAYS TRIGGER c67_deny_legacy_event_dml',
      r.schema_name,r.table_name);
    EXECUTE pg_catalog.format(
      'CREATE TRIGGER c67_deny_legacy_event_truncate BEFORE TRUNCATE ON %I.%I FOR EACH STATEMENT EXECUTE FUNCTION deedlight_event_private.c67_reject_legacy_event_write()',
      r.schema_name,r.table_name);
    EXECUTE pg_catalog.format(
      'ALTER TABLE %I.%I ENABLE ALWAYS TRIGGER c67_deny_legacy_event_truncate',
      r.schema_name,r.table_name);
    EXECUTE pg_catalog.format(
      'REVOKE ALL ON TABLE %I.%I FROM PUBLIC, anon, authenticated, service_role',
      r.schema_name,r.table_name);
    INSERT INTO deedlight_event_private.c67_legacy_veto_inventory
      (schema_name,table_name,role_in_pipeline)
    VALUES (r.schema_name,r.table_name,r.role_in_pipeline);
  END LOOP;
END
$c67_install$;

DO $c67_retire$
DECLARE r record;
BEGIN
  -- Retire wrapper first; it may call base. RESTRICT fails atomically on
  -- dependent SQL objects. No CASCADE, no source/privilege guessing.
  FOR r IN
    SELECT p.oid::pg_catalog.regprocedure AS signature,
      pg_catalog.pg_get_userbyid(p.proowner) AS owner_role,
      p.prosecdef AS security_definer,
      pg_catalog.md5(p.prosrc) AS source_md5,
      pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE') AS service_can_execute,
      pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE') AS anon_can_execute,
      pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_can_execute,
      (SELECT count(*)::integer FROM pg_catalog.pg_depend d
        WHERE d.refclassid='pg_catalog.pg_proc'::pg_catalog.regclass
          AND d.refobjid=p.oid) AS dependent_objects,
      (SELECT conf.setting FROM pg_catalog.unnest(p.proconfig) AS conf(setting)
        WHERE conf.setting LIKE 'search_path=%' LIMIT 1) AS source_search_path
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('record_resend_webhook_event_identity_bound','record_resend_webhook_event')
      AND p.prokind='f'
    ORDER BY CASE WHEN p.proname='record_resend_webhook_event_identity_bound'
      THEN 0 ELSE 1 END, p.oid
  LOOP
    INSERT INTO deedlight_event_private.c67_retired_rpc_inventory
      (signature,owner_role,security_definer,source_md5,
       service_role_execute_before,anon_execute_before,
       authenticated_execute_before,dependent_objects_before,search_path_setting)
    VALUES (r.signature::text,r.owner_role,r.security_definer,r.source_md5,
       r.service_can_execute,r.anon_can_execute,r.authenticated_can_execute,
       r.dependent_objects,r.source_search_path);
    EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',r.signature);
    EXECUTE pg_catalog.format('DROP FUNCTION %s RESTRICT',r.signature);
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN ('record_resend_webhook_event_identity_bound','record_resend_webhook_event')
  ) THEN
    RAISE EXCEPTION 'C67 legacy webhook RPC family remains' USING ERRCODE='55000';
  END IF;

  -- Stop-only transport boundary: an unprocessed bounce or complaint must
  -- NOT remain eligible for an outbound provider send while webhook intake
  -- and suppression are disabled. Existing consent/lease functions stay intact.
  REVOKE EXECUTE ON FUNCTION public.begin_delivery_transport(uuid,uuid,text)
    FROM PUBLIC, anon, authenticated, service_role;

  IF pg_catalog.has_function_privilege('service_role',
      'public.begin_delivery_transport(uuid,uuid,text)','EXECUTE')
     OR pg_catalog.has_function_privilege('anon',
      'public.begin_delivery_transport(uuid,uuid,text)','EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated',
      'public.begin_delivery_transport(uuid,uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'C67 outbound transport permission not closed'
      USING ERRCODE='42501';
  END IF;
END
$c67_retire$;

-- Prevent a subsequent routine UPDATE from enabling intake before a separately
-- reviewed cutover migration. Only an authorized migration that explicitly
-- removes this veto may re-enable event registration.
CREATE FUNCTION deedlight_event_private.c67_reject_registry_activation()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $activation$
BEGIN
  IF NEW.accepting_new_events IS TRUE THEN
    RAISE EXCEPTION 'C67 registry intake activation requires independent cutover review'
      USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END
$activation$;
REVOKE ALL ON FUNCTION deedlight_event_private.c67_reject_registry_activation()
  FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER c67_registry_activation_veto
  BEFORE UPDATE OF accepting_new_events
  ON deedlight_event_private.registry_control
  FOR EACH ROW
  EXECUTE FUNCTION deedlight_event_private.c67_reject_registry_activation();
ALTER TABLE deedlight_event_private.registry_control
  ENABLE ALWAYS TRIGGER c67_registry_activation_veto;

DO $c67_assert$
DECLARE r record; v_installed integer;
BEGIN
  IF (SELECT accepting_new_events FROM deedlight_event_private.registry_control
      WHERE singleton = true) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'C67 registry activation detected' USING ERRCODE='55000';
  END IF;
  SELECT count(*) INTO v_installed FROM deedlight_event_private.c67_legacy_veto_inventory;
  IF v_installed IS DISTINCT FROM (SELECT count(*) FROM pg_temp.c67_reviewed_event_tables) THEN
    RAISE EXCEPTION 'C67 not all reviewed legacy tables physically protected'
      USING ERRCODE='55000';
  END IF;
  FOR r IN
    SELECT t.schema_name,t.table_name
    FROM pg_temp.c67_reviewed_event_tables t
    JOIN pg_catalog.pg_namespace n ON n.nspname=t.schema_name
    JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid AND c.relname=t.table_name
  LOOP
    IF NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_trigger tr
       JOIN pg_catalog.pg_class c ON c.oid=tr.tgrelid
       JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname=r.schema_name AND c.relname=r.table_name
         AND tr.tgname='c67_deny_legacy_event_dml' AND tr.tgenabled='A'
    ) OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_trigger tr
       JOIN pg_catalog.pg_class c ON c.oid=tr.tgrelid
       JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname=r.schema_name AND c.relname=r.table_name
         AND tr.tgname='c67_deny_legacy_event_truncate' AND tr.tgenabled='A'
    ) THEN
      RAISE EXCEPTION 'C67 missing always-on physical event write veto'
        USING ERRCODE='55000';
    END IF;
  END LOOP;
END
$c67_assert$;
COMMIT;
