-- Disposable PostgreSQL 16 fixture only. Never add this file to supabase/migrations.
\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS deedlight_execution_ledger;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA deedlight_execution_ledger;

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'deedlight_ledger_approver') THEN
    CREATE ROLE deedlight_ledger_approver NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'deedlight_ledger_runner') THEN
    CREATE ROLE deedlight_ledger_runner NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'deedlight_ledger_observer') THEN
    CREATE ROLE deedlight_ledger_observer NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'deedlight_ledger_verifier') THEN
    CREATE ROLE deedlight_ledger_verifier NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'deedlight_ledger_recovery') THEN
    CREATE ROLE deedlight_ledger_recovery NOLOGIN NOINHERIT;
  END IF;
END
$roles$;

GRANT deedlight_ledger_approver, deedlight_ledger_runner,
  deedlight_ledger_observer, deedlight_ledger_verifier,
  deedlight_ledger_recovery TO postgres;

CREATE TABLE IF NOT EXISTS deedlight_execution_ledger.database_identity (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  system_identifier text NOT NULL,
  database_oid oid NOT NULL,
  database_name name NOT NULL,
  server_version_num integer NOT NULL,
  installed_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp()
);

DO $identity$
DECLARE
  v_system_identifier text;
  v_database_oid oid;
BEGIN
  SELECT system_identifier::text INTO STRICT v_system_identifier
  FROM pg_catalog.pg_control_system();
  SELECT oid INTO STRICT v_database_oid
  FROM pg_catalog.pg_database WHERE datname = pg_catalog.current_database();

  IF NOT EXISTS (SELECT 1 FROM deedlight_execution_ledger.database_identity) THEN
    INSERT INTO deedlight_execution_ledger.database_identity
      (singleton, system_identifier, database_oid, database_name, server_version_num)
    VALUES (true, v_system_identifier, v_database_oid, pg_catalog.current_database(),
      pg_catalog.current_setting('server_version_num')::integer);
  ELSIF NOT EXISTS (
    SELECT 1 FROM deedlight_execution_ledger.database_identity
    WHERE singleton
      AND system_identifier = v_system_identifier
      AND database_oid = v_database_oid
      AND database_name = pg_catalog.current_database()
      AND server_version_num = pg_catalog.current_setting('server_version_num')::integer
  ) THEN
    RAISE EXCEPTION 'ledger database identity differs from this PostgreSQL server/database';
  END IF;
END
$identity$;

CREATE TABLE IF NOT EXISTS deedlight_execution_ledger.approvals (
  approval_id uuid PRIMARY KEY,
  system_identifier text NOT NULL,
  database_oid oid NOT NULL,
  database_name name NOT NULL,
  record_id uuid NOT NULL,
  execution_id uuid NOT NULL,
  source_identity jsonb NOT NULL CHECK (jsonb_typeof(source_identity) = 'object'),
  approver_identity name NOT NULL,
  approved_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  consumed_at timestamptz,
  UNIQUE (system_identifier, database_oid, record_id),
  UNIQUE (system_identifier, database_oid, execution_id),
  UNIQUE (system_identifier, database_oid, approval_id)
);

CREATE TABLE IF NOT EXISTS deedlight_execution_ledger.executions (
  system_identifier text NOT NULL,
  database_oid oid NOT NULL,
  database_name name NOT NULL,
  record_id uuid NOT NULL,
  execution_id uuid NOT NULL,
  approval_id uuid NOT NULL,
  source_identity jsonb NOT NULL CHECK (jsonb_typeof(source_identity) = 'object'),
  status text NOT NULL CHECK (status IN ('reserved','running','succeeded','failed','partial','interrupted','unknown')),
  approver_identity name NOT NULL,
  runner_identity name,
  reserved_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  started_at timestamptz,
  heartbeat_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  completed_at timestamptz,
  outcome_detail jsonb,
  PRIMARY KEY (system_identifier, database_oid, execution_id),
  UNIQUE (system_identifier, database_oid, record_id),
  FOREIGN KEY (system_identifier, database_oid, approval_id)
    REFERENCES deedlight_execution_ledger.approvals(system_identifier, database_oid, approval_id),
  CHECK (
    (status IN ('reserved','running') AND completed_at IS NULL)
    OR (status IN ('succeeded','failed','partial','interrupted','unknown') AND completed_at IS NOT NULL)
  )
);

CREATE TABLE IF NOT EXISTS deedlight_execution_ledger.observation_queries (
  query_id text PRIMARY KEY CHECK (query_id ~ '^[a-z][a-z0-9_]{0,63}$'),
  query_sql text NOT NULL CHECK (pg_catalog.btrim(query_sql) ~* '^select\s'),
  description text NOT NULL
);

CREATE TABLE IF NOT EXISTS deedlight_execution_ledger.snapshots (
  system_identifier text NOT NULL,
  database_oid oid NOT NULL,
  execution_id uuid NOT NULL,
  phase text NOT NULL CHECK (phase IN ('pre','post')),
  query_id text NOT NULL REFERENCES deedlight_execution_ledger.observation_queries(query_id),
  observer_identity name NOT NULL,
  observed_at timestamptz NOT NULL,
  snapshot jsonb NOT NULL,
  snapshot_sha256 text NOT NULL CHECK (snapshot_sha256 ~ '^[a-f0-9]{64}$'),
  PRIMARY KEY (system_identifier, database_oid, execution_id, phase),
  FOREIGN KEY (system_identifier, database_oid, execution_id)
    REFERENCES deedlight_execution_ledger.executions(system_identifier, database_oid, execution_id)
);

CREATE TABLE IF NOT EXISTS deedlight_execution_ledger.verification_events (
  system_identifier text NOT NULL,
  database_oid oid NOT NULL,
  execution_id uuid NOT NULL,
  verifier_identity name NOT NULL,
  verdict text NOT NULL CHECK (verdict IN ('verified','rejected','inconclusive')),
  evidence jsonb NOT NULL CHECK (jsonb_typeof(evidence) = 'object'),
  recorded_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  PRIMARY KEY (system_identifier, database_oid, execution_id, verifier_identity),
  FOREIGN KEY (system_identifier, database_oid, execution_id)
    REFERENCES deedlight_execution_ledger.executions(system_identifier, database_oid, execution_id)
);

-- This target is deliberately disposable. The registered query is fixed at install time.
CREATE TABLE IF NOT EXISTS deedlight_execution_ledger.test_effects (
  effect_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  effect_value text NOT NULL
);
INSERT INTO deedlight_execution_ledger.observation_queries(query_id, query_sql, description)
VALUES ('test_effects_v1',
  'SELECT count(*)::bigint AS effect_count FROM deedlight_execution_ledger.test_effects',
  'Disposable fixture effect count')
ON CONFLICT (query_id) DO NOTHING;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.actor_role()
RETURNS name
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
  SELECT nullif(pg_catalog.current_setting('role', true), 'none')::name
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.current_database_identity()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
        v_system_identifier text;
        v_database_oid oid;
BEGIN
  SELECT system_identifier::text INTO STRICT v_system_identifier FROM pg_catalog.pg_control_system();
  SELECT oid INTO STRICT v_database_oid FROM pg_catalog.pg_database WHERE datname = pg_catalog.current_database();
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  IF v_identity.system_identifier <> v_system_identifier
    OR v_identity.database_oid <> v_database_oid
    OR v_identity.database_name <> pg_catalog.current_database()
    OR v_identity.server_version_num <> pg_catalog.current_setting('server_version_num')::integer THEN
    RAISE EXCEPTION 'server-derived database identity mismatch';
  END IF;
  RETURN pg_catalog.jsonb_build_object(
    'systemIdentifier', v_system_identifier,
    'databaseOid', v_database_oid,
    'databaseName', pg_catalog.current_database(),
    'serverVersionNum', pg_catalog.current_setting('server_version_num')::integer
  );
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.approve_execution(
  p_approval_id uuid, p_record_id uuid, p_execution_id uuid, p_source_identity jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_actor name := deedlight_execution_ledger.actor_role();
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
BEGIN
  IF v_actor IS DISTINCT FROM 'deedlight_ledger_approver' THEN
    RAISE EXCEPTION 'approver authority required';
  END IF;
  IF p_approval_id IS NULL OR p_record_id IS NULL OR p_execution_id IS NULL
    OR p_source_identity IS NULL OR pg_catalog.jsonb_typeof(p_source_identity) <> 'object' THEN
    RAISE EXCEPTION 'approval scope is incomplete';
  END IF;
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  INSERT INTO deedlight_execution_ledger.approvals
    (approval_id, system_identifier, database_oid, database_name, record_id, execution_id,
     source_identity, approver_identity)
  VALUES (p_approval_id, v_identity.system_identifier, v_identity.database_oid,
    v_identity.database_name, p_record_id, p_execution_id, p_source_identity, v_actor);
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.reserve_execution(
  p_approval_id uuid, p_record_id uuid, p_execution_id uuid, p_source_identity jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_actor name := deedlight_execution_ledger.actor_role();
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
        v_approval deedlight_execution_ledger.approvals%ROWTYPE;
BEGIN
  IF v_actor IS DISTINCT FROM 'deedlight_ledger_runner' THEN
    RAISE EXCEPTION 'migration runner authority required';
  END IF;
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  SELECT * INTO v_approval FROM deedlight_execution_ledger.approvals
  WHERE approval_id = p_approval_id
    AND system_identifier = v_identity.system_identifier
    AND database_oid = v_identity.database_oid
    AND database_name = v_identity.database_name
  FOR UPDATE;
  IF NOT FOUND OR v_approval.consumed_at IS NOT NULL
    OR v_approval.record_id <> p_record_id
    OR v_approval.execution_id <> p_execution_id
    OR v_approval.source_identity <> p_source_identity THEN
    RAISE EXCEPTION 'approval is missing, consumed, or does not bind this execution scope';
  END IF;
  INSERT INTO deedlight_execution_ledger.executions
    (system_identifier, database_oid, database_name, record_id, execution_id,
     approval_id, source_identity, status, approver_identity)
  VALUES (v_identity.system_identifier, v_identity.database_oid, v_identity.database_name,
    p_record_id, p_execution_id, p_approval_id, p_source_identity, 'reserved',
    v_approval.approver_identity);
  UPDATE deedlight_execution_ledger.approvals
  SET consumed_at = pg_catalog.clock_timestamp()
  WHERE approval_id = p_approval_id;
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.capture_snapshot(
  p_execution_id uuid, p_phase text, p_query_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_actor name := deedlight_execution_ledger.actor_role();
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
        v_execution deedlight_execution_ledger.executions%ROWTYPE;
        v_query deedlight_execution_ledger.observation_queries%ROWTYPE;
        v_rows jsonb;
        v_snapshot jsonb;
        v_observed_at timestamptz := pg_catalog.clock_timestamp();
BEGIN
  IF v_actor IS DISTINCT FROM 'deedlight_ledger_observer' THEN
    RAISE EXCEPTION 'independent read-only observer authority required';
  END IF;
  IF p_phase NOT IN ('pre','post') THEN RAISE EXCEPTION 'unsupported snapshot phase'; END IF;
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  SELECT * INTO STRICT v_execution FROM deedlight_execution_ledger.executions
  WHERE system_identifier = v_identity.system_identifier AND database_oid = v_identity.database_oid
    AND execution_id = p_execution_id FOR SHARE;
  IF v_actor IN (v_execution.approver_identity, v_execution.runner_identity) THEN
    RAISE EXCEPTION 'snapshot observer must be independent of approver and runner';
  END IF;
  IF (p_phase = 'pre' AND v_execution.status <> 'reserved')
    OR (p_phase = 'post' AND v_execution.status <> 'running') THEN
    RAISE EXCEPTION 'snapshot phase does not match execution state';
  END IF;
  SELECT * INTO STRICT v_query FROM deedlight_execution_ledger.observation_queries WHERE query_id = p_query_id;
  EXECUTE pg_catalog.format(
    'SELECT COALESCE(jsonb_agg(to_jsonb(q)), ''[]''::jsonb) FROM (%s) AS q', v_query.query_sql
  ) INTO v_rows;
  v_snapshot := pg_catalog.jsonb_build_object(
    'databaseIdentity', deedlight_execution_ledger.current_database_identity(),
    'queryId', p_query_id, 'rows', v_rows, 'observedAt', v_observed_at
  );
  INSERT INTO deedlight_execution_ledger.snapshots
    (system_identifier, database_oid, execution_id, phase, query_id,
     observer_identity, observed_at, snapshot, snapshot_sha256)
  VALUES (v_identity.system_identifier, v_identity.database_oid, p_execution_id, p_phase,
    p_query_id, v_actor, v_observed_at, v_snapshot,
    pg_catalog.encode(deedlight_execution_ledger.digest(
      pg_catalog.convert_to(v_snapshot::text, 'UTF8'), 'sha256'), 'hex'));
  RETURN v_snapshot;
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.start_execution(p_execution_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_actor name := deedlight_execution_ledger.actor_role();
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
BEGIN
  IF v_actor IS DISTINCT FROM 'deedlight_ledger_runner' THEN RAISE EXCEPTION 'migration runner authority required'; END IF;
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  IF NOT EXISTS (SELECT 1 FROM deedlight_execution_ledger.snapshots
    WHERE system_identifier = v_identity.system_identifier AND database_oid = v_identity.database_oid
      AND execution_id = p_execution_id AND phase = 'pre') THEN
    RAISE EXCEPTION 'independently collected pre-execution snapshot required';
  END IF;
  UPDATE deedlight_execution_ledger.executions
  SET status = 'running', runner_identity = v_actor,
      started_at = pg_catalog.clock_timestamp(), heartbeat_at = pg_catalog.clock_timestamp()
  WHERE system_identifier = v_identity.system_identifier AND database_oid = v_identity.database_oid
    AND execution_id = p_execution_id AND status = 'reserved';
  IF NOT FOUND THEN RAISE EXCEPTION 'execution is not reservable'; END IF;
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.heartbeat_execution(p_execution_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_actor name := deedlight_execution_ledger.actor_role();
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
BEGIN
  IF v_actor IS DISTINCT FROM 'deedlight_ledger_runner' THEN RAISE EXCEPTION 'migration runner authority required'; END IF;
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  UPDATE deedlight_execution_ledger.executions SET heartbeat_at = pg_catalog.clock_timestamp()
  WHERE system_identifier = v_identity.system_identifier AND database_oid = v_identity.database_oid
    AND execution_id = p_execution_id AND status = 'running' AND runner_identity = v_actor;
  IF NOT FOUND THEN RAISE EXCEPTION 'active execution owned by this runner not found'; END IF;
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.finalize_execution(
  p_execution_id uuid, p_outcome text, p_outcome_detail jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_actor name := deedlight_execution_ledger.actor_role();
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
BEGIN
  IF v_actor IS DISTINCT FROM 'deedlight_ledger_runner' THEN RAISE EXCEPTION 'migration runner authority required'; END IF;
  IF p_outcome NOT IN ('succeeded','failed','partial') OR p_outcome_detail IS NULL
    OR pg_catalog.jsonb_typeof(p_outcome_detail) <> 'object' THEN
    RAISE EXCEPTION 'terminal outcome must be explicit and supported';
  END IF;
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  IF NOT EXISTS (SELECT 1 FROM deedlight_execution_ledger.snapshots
    WHERE system_identifier = v_identity.system_identifier AND database_oid = v_identity.database_oid
      AND execution_id = p_execution_id AND phase = 'pre')
    OR NOT EXISTS (SELECT 1 FROM deedlight_execution_ledger.snapshots
    WHERE system_identifier = v_identity.system_identifier AND database_oid = v_identity.database_oid
      AND execution_id = p_execution_id AND phase = 'post') THEN
    RAISE EXCEPTION 'independently collected pre and post snapshots required before finalization';
  END IF;
  UPDATE deedlight_execution_ledger.executions
  SET status = p_outcome, completed_at = pg_catalog.clock_timestamp(), outcome_detail = p_outcome_detail
  WHERE system_identifier = v_identity.system_identifier AND database_oid = v_identity.database_oid
    AND execution_id = p_execution_id AND status = 'running' AND runner_identity = v_actor;
  IF NOT FOUND THEN RAISE EXCEPTION 'active execution owned by this runner not found'; END IF;
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.recover_stale_executions(p_stale_after interval)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_actor name := deedlight_execution_ledger.actor_role();
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
        v_count integer;
BEGIN
  IF v_actor IS DISTINCT FROM 'deedlight_ledger_recovery' THEN RAISE EXCEPTION 'recovery authority required'; END IF;
  IF p_stale_after IS NULL OR p_stale_after <= interval '0 seconds'
    OR p_stale_after > interval '7 days' THEN RAISE EXCEPTION 'recovery timeout outside safe bounds'; END IF;
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  UPDATE deedlight_execution_ledger.executions
  SET status = CASE WHEN status = 'reserved' THEN 'interrupted' ELSE 'unknown' END,
      completed_at = pg_catalog.clock_timestamp(),
      outcome_detail = pg_catalog.jsonb_build_object('reason','stale_execution_recovery','recoveryActor',v_actor)
  WHERE system_identifier = v_identity.system_identifier AND database_oid = v_identity.database_oid
    AND status IN ('reserved','running')
    AND heartbeat_at < pg_catalog.clock_timestamp() - p_stale_after;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.record_verification(
  p_execution_id uuid, p_verdict text, p_evidence jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_actor name := deedlight_execution_ledger.actor_role();
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
        v_execution deedlight_execution_ledger.executions%ROWTYPE;
BEGIN
  IF v_actor IS DISTINCT FROM 'deedlight_ledger_verifier' THEN RAISE EXCEPTION 'independent verifier authority required'; END IF;
  IF p_verdict NOT IN ('verified','rejected','inconclusive') OR p_evidence IS NULL
    OR pg_catalog.jsonb_typeof(p_evidence) <> 'object' THEN RAISE EXCEPTION 'verification evidence invalid'; END IF;
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  SELECT * INTO STRICT v_execution FROM deedlight_execution_ledger.executions
  WHERE system_identifier = v_identity.system_identifier AND database_oid = v_identity.database_oid
    AND execution_id = p_execution_id;
  IF v_execution.status NOT IN ('succeeded','failed','partial','interrupted','unknown')
    OR v_actor IN (v_execution.approver_identity, v_execution.runner_identity) THEN
    RAISE EXCEPTION 'verification requires terminal execution and independent verifier';
  END IF;
  INSERT INTO deedlight_execution_ledger.verification_events
    (system_identifier, database_oid, execution_id, verifier_identity, verdict, evidence)
  VALUES (v_identity.system_identifier, v_identity.database_oid, p_execution_id, v_actor, p_verdict, p_evidence);
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.guard_execution_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
BEGIN
  IF OLD.status IN ('succeeded','failed','partial','interrupted','unknown') THEN
    RAISE EXCEPTION 'terminal execution outcomes are immutable';
  END IF;
  IF NOT ((OLD.status = 'reserved' AND NEW.status IN ('running','interrupted'))
    OR (OLD.status = 'running' AND NEW.status IN ('succeeded','failed','partial','unknown'))) THEN
    RAISE EXCEPTION 'invalid execution state transition: % -> %', OLD.status, NEW.status;
  END IF;
  IF NEW.system_identifier <> OLD.system_identifier OR NEW.database_oid <> OLD.database_oid
    OR NEW.database_name <> OLD.database_name OR NEW.record_id <> OLD.record_id
    OR NEW.execution_id <> OLD.execution_id OR NEW.approval_id <> OLD.approval_id
    OR NEW.source_identity <> OLD.source_identity OR NEW.approver_identity <> OLD.approver_identity
    OR NEW.reserved_at <> OLD.reserved_at THEN
    RAISE EXCEPTION 'execution identity and reservation evidence are immutable';
  END IF;
  RETURN NEW;
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.reject_ledger_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
BEGIN
  RAISE EXCEPTION 'ledger evidence is append-only';
END
$fn$;

DROP TRIGGER IF EXISTS execution_transition_guard ON deedlight_execution_ledger.executions;
CREATE TRIGGER execution_transition_guard BEFORE UPDATE ON deedlight_execution_ledger.executions
FOR EACH ROW EXECUTE FUNCTION deedlight_execution_ledger.guard_execution_transition();
DROP TRIGGER IF EXISTS approvals_append_only ON deedlight_execution_ledger.approvals;
CREATE TRIGGER approvals_append_only BEFORE UPDATE OR DELETE ON deedlight_execution_ledger.approvals
FOR EACH ROW EXECUTE FUNCTION deedlight_execution_ledger.reject_ledger_mutation();
-- Reservation consumption is performed by the owner function; trigger exception is not bypassed by SECURITY DEFINER.
-- Use a dedicated trigger to permit exactly one NULL -> timestamp consumption.
CREATE OR REPLACE FUNCTION deedlight_execution_ledger.guard_approval_consumption()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, deedlight_execution_ledger AS $fn$
BEGIN
  IF OLD.consumed_at IS NOT NULL OR NEW.consumed_at IS NULL
    OR (to_jsonb(NEW) - 'consumed_at') <> (to_jsonb(OLD) - 'consumed_at') THEN
    RAISE EXCEPTION 'approval is immutable except for one-time consumption';
  END IF;
  RETURN NEW;
END
$fn$;
DROP TRIGGER approvals_append_only ON deedlight_execution_ledger.approvals;
CREATE TRIGGER approvals_append_only BEFORE UPDATE OR DELETE ON deedlight_execution_ledger.approvals
FOR EACH ROW EXECUTE FUNCTION deedlight_execution_ledger.guard_approval_consumption();

DROP TRIGGER IF EXISTS snapshots_append_only ON deedlight_execution_ledger.snapshots;
CREATE TRIGGER snapshots_append_only BEFORE UPDATE OR DELETE ON deedlight_execution_ledger.snapshots
FOR EACH ROW EXECUTE FUNCTION deedlight_execution_ledger.reject_ledger_mutation();
DROP TRIGGER IF EXISTS verification_events_append_only ON deedlight_execution_ledger.verification_events;
CREATE TRIGGER verification_events_append_only BEFORE UPDATE OR DELETE ON deedlight_execution_ledger.verification_events
FOR EACH ROW EXECUTE FUNCTION deedlight_execution_ledger.reject_ledger_mutation();

REVOKE ALL ON SCHEMA deedlight_execution_ledger FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA deedlight_execution_ledger FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA deedlight_execution_ledger FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA deedlight_execution_ledger FROM PUBLIC;
GRANT USAGE ON SCHEMA deedlight_execution_ledger TO
  deedlight_ledger_approver, deedlight_ledger_runner, deedlight_ledger_observer,
  deedlight_ledger_verifier, deedlight_ledger_recovery;
GRANT EXECUTE ON FUNCTION deedlight_execution_ledger.approve_execution(uuid,uuid,uuid,jsonb)
  TO deedlight_ledger_approver;
GRANT EXECUTE ON FUNCTION deedlight_execution_ledger.reserve_execution(uuid,uuid,uuid,jsonb),
  deedlight_execution_ledger.start_execution(uuid),
  deedlight_execution_ledger.heartbeat_execution(uuid),
  deedlight_execution_ledger.finalize_execution(uuid,text,jsonb)
  TO deedlight_ledger_runner;
GRANT EXECUTE ON FUNCTION deedlight_execution_ledger.capture_snapshot(uuid,text,text)
  TO deedlight_ledger_observer;
GRANT EXECUTE ON FUNCTION deedlight_execution_ledger.record_verification(uuid,text,jsonb)
  TO deedlight_ledger_verifier;
GRANT EXECUTE ON FUNCTION deedlight_execution_ledger.recover_stale_executions(interval)
  TO deedlight_ledger_recovery;
GRANT EXECUTE ON FUNCTION deedlight_execution_ledger.current_database_identity()
  TO deedlight_ledger_approver, deedlight_ledger_runner, deedlight_ledger_observer,
    deedlight_ledger_verifier, deedlight_ledger_recovery;
