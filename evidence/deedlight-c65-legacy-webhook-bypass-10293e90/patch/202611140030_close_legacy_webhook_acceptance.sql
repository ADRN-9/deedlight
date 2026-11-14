-- DeedLight C65 ISOLATED post-029 hard-stop patch. Reviewed source 025-028
-- is unavailable: this migration MUST NOT be activated in Production.
-- Disables webhook acceptance and physically vetoes discovered legacy event writes.
-- It deliberately does not enable the C61 registry or mark history reconciled.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $preflight$
BEGIN
  IF pg_catalog.to_regclass('deedlight_event_private.provider_event_registry') IS NULL
    OR pg_catalog.to_regclass('deedlight_event_private.registry_control') IS NULL
    OR pg_catalog.to_regclass('deedlight_event_private.provider_event_quarantine') IS NULL
    OR pg_catalog.to_regprocedure('public.deedlight_reserve_provider_event(text,text,bytea,text,text)') IS NULL
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'service_role')
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'anon')
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'authenticated')
  THEN
    RAISE EXCEPTION 'C65 requires verified C61 registry and DB role prerequisites'
      USING ERRCODE = '55000';
  END IF;
  IF (SELECT accepting_new_events FROM deedlight_event_private.registry_control
      WHERE singleton = true) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'C65 refuses an active or missing registry-control row'
      USING ERRCODE = '55000';
  END IF;
  IF pg_catalog.to_regclass('deedlight_event_private.c65_legacy_veto_inventory') IS NOT NULL THEN
    RAISE EXCEPTION 'C65 already or partially installed; review before proceeding'
      USING ERRCODE = '55000';
  END IF;
END
$preflight$;

-- Purely internal evidence of the physical write barrier. Not a bypass list.
CREATE TABLE deedlight_event_private.c65_legacy_veto_inventory (
  schema_name text NOT NULL,
  table_name text NOT NULL,
  installed_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  PRIMARY KEY (schema_name, table_name)
);
REVOKE ALL ON deedlight_event_private.c65_legacy_veto_inventory
  FROM PUBLIC, anon, authenticated, service_role;

-- Trigger fires even when a SECURITY DEFINER RPC performs DML. This is
-- critical: REVOKE EXECUTE alone cannot stop definer-to-definer call chains.
CREATE FUNCTION deedlight_event_private.c65_deny_legacy_event_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $deny$
BEGIN
  RAISE EXCEPTION 'Legacy webhook lifecycle writes are closed; use reconciled registry only'
    USING ERRCODE = '55000';
  RETURN NULL;
END
$deny$;
REVOKE ALL ON FUNCTION deedlight_event_private.c65_deny_legacy_event_write()
  FROM PUBLIC, anon, authenticated, service_role;

DO $close$
DECLARE
  r record;
  v_tables integer := 0;
  v_rpcs integer := 0;
BEGIN
  -- DISCOVERY ONLY, not a final reviewed inventory. Any unrecognized legacy
  -- table naming scheme remains a blocker to enabling the registry.
  FOR r IN
    SELECT n.nspname, c.relname
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind IN ('r', 'p')
      AND n.nspname IN ('public', 'delivery_private', 'deedlight_delivery_private')
      AND c.relname ~* '(resend.*event|webhook.*event|provider.*event|unmatched.*event|event.*quarant|event.*conflict)'
      AND c.relname <> 'provider_event_registry'
    ORDER BY n.nspname, c.relname
  LOOP
    EXECUTE pg_catalog.format(
      'CREATE TRIGGER c65_reject_legacy_event_write BEFORE INSERT OR UPDATE OR DELETE ON %I.%I FOR EACH ROW EXECUTE FUNCTION deedlight_event_private.c65_deny_legacy_event_write()',
      r.nspname, r.relname);
    EXECUTE pg_catalog.format('ALTER TABLE %I.%I ENABLE ALWAYS TRIGGER c65_reject_legacy_event_write', r.nspname, r.relname);
    EXECUTE pg_catalog.format('REVOKE ALL ON TABLE %I.%I FROM PUBLIC, anon, authenticated, service_role', r.nspname, r.relname);
    INSERT INTO deedlight_event_private.c65_legacy_veto_inventory(schema_name, table_name)
      VALUES (r.nspname, r.relname);
    v_tables := v_tables + 1;
  END LOOP;
  IF v_tables = 0 THEN
    RAISE EXCEPTION 'No legacy event tables discovered; refuse unreviewed migration'
      USING ERRCODE = '55000';
  END IF;

  -- Drop every overload of the HIGH-severity legacy acceptance function.
  -- RESTRICT fails atomically if another SQL object depends on it, forcing
  -- explicit review instead of CASCADE or an unproven security wrapper.
  FOR r IN
    SELECT p.oid::pg_catalog.regprocedure AS signature
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'record_resend_webhook_event_identity_bound'
      AND p.prokind = 'f'
    ORDER BY p.oid
  LOOP
    EXECUTE pg_catalog.format('DROP FUNCTION %s RESTRICT', r.signature);
    v_rpcs := v_rpcs + 1;
  END LOOP;
  IF v_rpcs = 0 THEN
    RAISE EXCEPTION 'Expected legacy acceptance RPC absent; source 025-028 requires reconciliation'
      USING ERRCODE = '55000';
  END IF;

  -- Refuse extra *obviously named* acceptance routines. This is only a
  -- conservative catalog tripwire, not proof of complete 025-028 inventory.
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname IN ('public', 'delivery_private', 'deedlight_delivery_private')
      AND p.proname ~* '(resend.*(webhook|event)|webhook.*(record|accept|event)|provider.*event.*(record|accept|process))'
      AND p.proname NOT IN (
        'deedlight_reserve_provider_event',
        'deedlight_bind_provider_event',
        'deedlight_process_nonsuppressing_event'
      )
  ) THEN
    RAISE EXCEPTION 'Additional legacy acceptance entry point requires source review'
      USING ERRCODE = '55000';
  END IF;

  -- Other legacy acceptance routines must be independently identified from
  -- real 025-028 source; this patch never makes the registry active.
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'record_resend_webhook_event_identity_bound'
  ) THEN
    RAISE EXCEPTION 'Legacy acceptance RPC still present' USING ERRCODE = '55000';
  END IF;
END
$close$;

-- Explicitly keep the one authoritative registry disabled. The actual full
-- 025-028 acceptance inventory, historical collision backfill, immutable
-- dispatch mapping, and suppression pipeline must be reviewed before cutover.
UPDATE deedlight_event_private.registry_control
  SET accepting_new_events = false
  WHERE singleton = true AND accepting_new_events = false;
DO $assert$
BEGIN
  IF (SELECT accepting_new_events FROM deedlight_event_private.registry_control
      WHERE singleton = true) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Registry is not safely disabled' USING ERRCODE = '55000';
  END IF;
END
$assert$;
COMMIT;
