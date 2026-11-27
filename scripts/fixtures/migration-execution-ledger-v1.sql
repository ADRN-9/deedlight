-- Disposable PostgreSQL 16 fixture only. Never add this file to supabase/migrations.
\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS deedlight_execution_ledger;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA deedlight_execution_ledger;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.raise_trust_failure(
  p_category text, p_reason text, p_context jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_sqlstate text;
BEGIN
  v_sqlstate := CASE p_category
    WHEN 'missing_trust' THEN 'D1001'
    WHEN 'invalid_source_identity' THEN 'D1002'
    WHEN 'missing_execution_evidence' THEN 'D1003'
    WHEN 'snapshot_substitution' THEN 'D1004'
    WHEN 'replay' THEN 'D1005'
    WHEN 'incomplete_preconditions' THEN 'D1006'
    WHEN 'failed_postconditions' THEN 'D1007'
    WHEN 'ambiguous_execution_outcome' THEN 'D1008'
    ELSE NULL
  END;
  IF v_sqlstate IS NULL OR p_reason IS NULL OR p_context IS NULL
    OR pg_catalog.jsonb_typeof(p_context) <> 'object' THEN
    RAISE EXCEPTION 'invalid trust-failure diagnostic request';
  END IF;
  RAISE EXCEPTION USING ERRCODE = v_sqlstate,
    MESSAGE = 'DEEDLIGHT_TRUST_FAILURE:' || p_category,
    DETAIL = pg_catalog.jsonb_build_object(
      'category', p_category, 'reason', p_reason, 'context', p_context
    )::text;
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.canonical_query_bundle_digest(p_manifest jsonb)
RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_canonical text; v_count integer; v_unique_count integer; v_member jsonb;
BEGIN
  IF pg_catalog.jsonb_typeof(p_manifest) IS DISTINCT FROM 'array' THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'missing_trust', 'query_bundle_manifest_not_array', '{}'::jsonb
    );
  END IF;
  IF pg_catalog.jsonb_array_length(p_manifest) = 0 THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'missing_trust', 'query_bundle_manifest_empty', '{}'::jsonb
    );
  END IF;
  FOR v_member IN SELECT value FROM pg_catalog.jsonb_array_elements(p_manifest) AS e(value) LOOP
    IF pg_catalog.jsonb_typeof(v_member) <> 'object'
      OR (SELECT pg_catalog.count(*) FROM pg_catalog.jsonb_object_keys(v_member)) <> 2
      OR NOT (v_member ? 'queryId') OR NOT (v_member ? 'querySha256')
      OR coalesce(v_member->>'queryId','') !~ '^[a-z][a-z0-9_]{0,63}$'
      OR coalesce(v_member->>'querySha256','') !~ '^[a-f0-9]{64}$' THEN
      PERFORM deedlight_execution_ledger.raise_trust_failure(
        'missing_trust', 'query_bundle_manifest_member_invalid', '{}'::jsonb
      );
    END IF;
  END LOOP;
  SELECT pg_catalog.count(*), pg_catalog.count(DISTINCT value->>'queryId')
    INTO v_count, v_unique_count
    FROM pg_catalog.jsonb_array_elements(p_manifest) AS e(value);
  IF v_count <> v_unique_count THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'missing_trust', 'query_bundle_manifest_duplicate_member', '{}'::jsonb
    );
  END IF;
  SELECT pg_catalog.string_agg(
    (value->>'queryId') || ':' || (value->>'querySha256'),
    pg_catalog.chr(10) ORDER BY pg_catalog.convert_to(value->>'queryId', 'UTF8')
  ) INTO v_canonical
  FROM pg_catalog.jsonb_array_elements(p_manifest) AS e(value);
  RETURN pg_catalog.encode(
    deedlight_execution_ledger.digest(pg_catalog.convert_to(v_canonical, 'UTF8'), 'sha256'),
    'hex'
  );
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.valid_source_identity(p_source_identity jsonb)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog
AS $fn$
  SELECT pg_catalog.jsonb_typeof(p_source_identity) = 'object'
    AND (SELECT pg_catalog.count(*) FROM pg_catalog.jsonb_object_keys(p_source_identity)) = 2
    AND pg_catalog.jsonb_typeof(p_source_identity->'path') = 'string'
    AND pg_catalog.btrim(p_source_identity->>'path') <> ''
    AND pg_catalog.left(p_source_identity->>'path',1) <> '/'
    AND pg_catalog.strpos(p_source_identity->>'path','..') = 0
    AND pg_catalog.strpos(p_source_identity->>'path',pg_catalog.chr(10)) = 0
    AND pg_catalog.jsonb_typeof(p_source_identity->'sha256') = 'string'
    AND (p_source_identity->>'sha256') ~ '^[a-f0-9]{64}$'
$fn$;

CREATE TABLE IF NOT EXISTS deedlight_execution_ledger.query_bundle_manifests (
  bundle_id text PRIMARY KEY CHECK (bundle_id ~ '^[a-z][a-z0-9_]{0,63}$'),
  manifest jsonb NOT NULL CHECK (pg_catalog.jsonb_typeof(manifest) = 'array'),
  member_count integer NOT NULL CHECK (member_count > 0),
  manifest_sha256 text NOT NULL CHECK (manifest_sha256 ~ '^[a-f0-9]{64}$'),
  UNIQUE (bundle_id, manifest_sha256)
);


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
  query_sql text NOT NULL CHECK (pg_catalog.btrim(query_sql) ~* '^select[[:space:]]'),
  description text NOT NULL,
  query_sha256 text NOT NULL CHECK (query_sha256 ~ '^[a-f0-9]{64}$'),
  query_bundle_id text NOT NULL,
  query_bundle_digest text NOT NULL CHECK (query_bundle_digest ~ '^[a-f0-9]{64}$'),
  UNIQUE (query_id, query_sha256, query_bundle_id, query_bundle_digest),
  UNIQUE (query_id, query_sha256, query_bundle_digest),
  FOREIGN KEY (query_bundle_id, query_bundle_digest)
    REFERENCES deedlight_execution_ledger.query_bundle_manifests(bundle_id, manifest_sha256)
);

CREATE TABLE IF NOT EXISTS deedlight_execution_ledger.snapshots (
  system_identifier text NOT NULL,
  database_oid oid NOT NULL,
  execution_id uuid NOT NULL,
  phase text NOT NULL CHECK (phase IN ('pre','post')),
  query_id text NOT NULL,
  query_sha256 text NOT NULL CHECK (query_sha256 ~ '^[a-f0-9]{64}$'),
  query_bundle_digest text NOT NULL CHECK (query_bundle_digest ~ '^[a-f0-9]{64}$'),
  observer_identity name NOT NULL,
  observed_at timestamptz NOT NULL,
  snapshot jsonb NOT NULL,
  snapshot_sha256 text NOT NULL CHECK (snapshot_sha256 ~ '^[a-f0-9]{64}$'),
  PRIMARY KEY (system_identifier, database_oid, execution_id, phase),
  FOREIGN KEY (query_id, query_sha256, query_bundle_digest)
    REFERENCES deedlight_execution_ledger.observation_queries(query_id, query_sha256, query_bundle_digest),
  FOREIGN KEY (system_identifier, database_oid, execution_id)
    REFERENCES deedlight_execution_ledger.executions(system_identifier, database_oid, execution_id)
);

CREATE TABLE IF NOT EXISTS deedlight_execution_ledger.execution_commit_markers (
  system_identifier text NOT NULL,
  database_oid oid NOT NULL,
  execution_id uuid NOT NULL,
  source_identity jsonb NOT NULL CHECK (jsonb_typeof(source_identity) = 'object'),
  runner_identity name NOT NULL,
  transaction_id text NOT NULL,
  committed_marker_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  PRIMARY KEY (system_identifier, database_oid, execution_id),
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
WITH registered(query_id, query_sql, description, bundle_name) AS (
  VALUES
    ('test_effects_v1',
      'SELECT count(*)::bigint AS effect_count FROM deedlight_execution_ledger.test_effects',
      'Disposable fixture effect count',
      'test_effects_bundle_v1'),
    ('test_effects_nonempty_v1',
      'SELECT count(*)::bigint AS nonempty_effect_count FROM deedlight_execution_ledger.test_effects WHERE effect_value <> ''''',
      'Disposable fixture non-empty effect count',
      'test_effects_bundle_v1'),
    ('test_effects_v2',
      'SELECT count(*)::bigint AS matching_effect_count FROM deedlight_execution_ledger.test_effects WHERE effect_value = ''snapshot mismatch fixture effect''',
      'Disposable fixture independently versioned effect query',
      'test_effects_bundle_v2')
), digested AS (
  SELECT query_id, query_sql, description, bundle_name,
    pg_catalog.encode(deedlight_execution_ledger.digest(
      pg_catalog.convert_to(query_sql, 'UTF8'), 'sha256'), 'hex') AS query_sha256
  FROM registered
), bundles AS (
  SELECT bundle_name,
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object('queryId', query_id, 'querySha256', query_sha256)
      ORDER BY query_id
    ) AS manifest
  FROM digested
  GROUP BY bundle_name
), manifests AS (
  SELECT bundle_name, manifest,
    deedlight_execution_ledger.canonical_query_bundle_digest(manifest) AS manifest_sha256
  FROM bundles
)
INSERT INTO deedlight_execution_ledger.query_bundle_manifests
  (bundle_id, manifest, member_count, manifest_sha256)
SELECT bundle_name, manifest, pg_catalog.jsonb_array_length(manifest), manifest_sha256
FROM manifests
ON CONFLICT (bundle_id) DO NOTHING;

WITH registered(query_id, query_sql, description, bundle_name) AS (
  VALUES
    ('test_effects_v1',
      'SELECT count(*)::bigint AS effect_count FROM deedlight_execution_ledger.test_effects',
      'Disposable fixture effect count',
      'test_effects_bundle_v1'),
    ('test_effects_nonempty_v1',
      'SELECT count(*)::bigint AS nonempty_effect_count FROM deedlight_execution_ledger.test_effects WHERE effect_value <> ''''',
      'Disposable fixture non-empty effect count',
      'test_effects_bundle_v1'),
    ('test_effects_v2',
      'SELECT count(*)::bigint AS matching_effect_count FROM deedlight_execution_ledger.test_effects WHERE effect_value = ''snapshot mismatch fixture effect''',
      'Disposable fixture independently versioned effect query',
      'test_effects_bundle_v2')
), digested AS (
  SELECT query_id, query_sql, description, bundle_name,
    pg_catalog.encode(deedlight_execution_ledger.digest(
      pg_catalog.convert_to(query_sql, 'UTF8'), 'sha256'), 'hex') AS query_sha256
  FROM registered
)
INSERT INTO deedlight_execution_ledger.observation_queries
  (query_id, query_sql, description, query_sha256, query_bundle_id, query_bundle_digest)
SELECT d.query_id, d.query_sql, d.description, d.query_sha256,
  d.bundle_name, m.manifest_sha256
FROM digested d
JOIN deedlight_execution_ledger.query_bundle_manifests m ON m.bundle_id = d.bundle_name
ON CONFLICT (query_id) DO NOTHING;
GRANT INSERT ON deedlight_execution_ledger.test_effects TO deedlight_ledger_runner;
GRANT USAGE, SELECT ON SEQUENCE deedlight_execution_ledger.test_effects_effect_id_seq
  TO deedlight_ledger_runner;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.actor_role()
RETURNS name
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
  SELECT nullif(pg_catalog.current_setting('role', true), 'none')::name
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.current_database_identity()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
        v_system_identifier text;
        v_database_oid oid;
        v_server_version_num integer;
BEGIN
  SELECT system_identifier::text INTO STRICT v_system_identifier FROM pg_catalog.pg_control_system();
  SELECT oid INTO STRICT v_database_oid FROM pg_catalog.pg_database WHERE datname = pg_catalog.current_database();
  v_server_version_num := pg_catalog.current_setting('server_version_num')::integer;
  SELECT * INTO v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  IF NOT FOUND THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'missing_trust', 'database_identity_anchor_missing', '{}'::jsonb
    );
  END IF;
  IF v_identity.system_identifier <> v_system_identifier
    OR v_identity.database_oid <> v_database_oid
    OR v_identity.database_name <> pg_catalog.current_database()
    OR v_identity.server_version_num <> v_server_version_num THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'missing_trust', 'live_database_identity_mismatch',
      pg_catalog.jsonb_build_object(
        'anchorSystemIdentifier', v_identity.system_identifier,
        'liveSystemIdentifier', v_system_identifier,
        'anchorDatabaseOid', v_identity.database_oid,
        'liveDatabaseOid', v_database_oid,
        'anchorDatabaseName', v_identity.database_name,
        'liveDatabaseName', pg_catalog.current_database(),
        'anchorServerVersionNum', v_identity.server_version_num,
        'liveServerVersionNum', v_server_version_num
      )
    );
  END IF;
  RETURN pg_catalog.jsonb_build_object(
    'systemIdentifier', v_system_identifier,
    'databaseOid', v_database_oid,
    'databaseName', pg_catalog.current_database(),
    'serverVersionNum', v_server_version_num
  );
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.approve_execution(
  p_approval_id uuid, p_record_id uuid, p_execution_id uuid, p_source_identity jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_actor name;
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
BEGIN
  PERFORM deedlight_execution_ledger.current_database_identity();
  v_actor := deedlight_execution_ledger.actor_role();
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
DECLARE v_actor name;
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
        v_approval deedlight_execution_ledger.approvals%ROWTYPE;
BEGIN
  PERFORM deedlight_execution_ledger.current_database_identity();
  v_actor := deedlight_execution_ledger.actor_role();
  IF v_actor IS DISTINCT FROM 'deedlight_ledger_runner' THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('missing_trust','runner_authority_missing',jsonb_build_object('actor',v_actor));
  END IF;
  IF NOT deedlight_execution_ledger.valid_source_identity(p_source_identity) THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('invalid_source_identity','reservation_source_identity_invalid','{}'::jsonb);
  END IF;
  SELECT * INTO v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  IF NOT FOUND THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('missing_trust','database_identity_anchor_missing','{}'::jsonb);
  END IF;
  SELECT * INTO v_approval FROM deedlight_execution_ledger.approvals
  WHERE approval_id=p_approval_id AND system_identifier=v_identity.system_identifier
    AND database_oid=v_identity.database_oid AND database_name=v_identity.database_name FOR UPDATE;
  IF NOT FOUND OR v_approval.consumed_at IS NOT NULL THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('replay','approval_missing_or_consumed',jsonb_build_object('approvalId',p_approval_id));
  END IF;
  IF v_approval.record_id<>p_record_id OR v_approval.execution_id<>p_execution_id THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('replay','approval_scope_mismatch',jsonb_build_object('approvalId',p_approval_id));
  END IF;
  IF v_approval.source_identity<>p_source_identity THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('invalid_source_identity','reservation_source_identity_substitution',jsonb_build_object('approvalId',p_approval_id));
  END IF;
  INSERT INTO deedlight_execution_ledger.executions
    (system_identifier,database_oid,database_name,record_id,execution_id,approval_id,source_identity,status,approver_identity)
  VALUES (v_identity.system_identifier,v_identity.database_oid,v_identity.database_name,p_record_id,p_execution_id,
    p_approval_id,p_source_identity,'reserved',v_approval.approver_identity);
  UPDATE deedlight_execution_ledger.approvals SET consumed_at=pg_catalog.clock_timestamp()
  WHERE approval_id=p_approval_id;
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.record_effect_commit_marker(
  p_execution_id uuid, p_source_identity jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_actor name;
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
        v_execution deedlight_execution_ledger.executions%ROWTYPE;
BEGIN
  PERFORM deedlight_execution_ledger.current_database_identity();
  v_actor := deedlight_execution_ledger.actor_role();
  IF v_actor IS DISTINCT FROM 'deedlight_ledger_runner' THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('missing_trust','runner_authority_missing',jsonb_build_object('actor',v_actor));
  END IF;
  IF NOT deedlight_execution_ledger.valid_source_identity(p_source_identity) THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('invalid_source_identity','marker_source_identity_invalid','{}'::jsonb);
  END IF;
  SELECT * INTO v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  IF NOT FOUND THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('missing_trust','database_identity_anchor_missing','{}'::jsonb);
  END IF;
  SELECT * INTO v_execution FROM deedlight_execution_ledger.executions
  WHERE system_identifier=v_identity.system_identifier AND database_oid=v_identity.database_oid
    AND execution_id=p_execution_id FOR UPDATE;
  IF NOT FOUND THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('missing_execution_evidence','marker_execution_missing',jsonb_build_object('executionId',p_execution_id));
  END IF;
  IF v_execution.source_identity<>p_source_identity THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('invalid_source_identity','marker_source_identity_substitution',jsonb_build_object('executionId',p_execution_id));
  END IF;
  IF v_execution.status<>'running' OR v_execution.runner_identity<>v_actor THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('missing_execution_evidence','marker_runner_not_active',jsonb_build_object('executionId',p_execution_id));
  END IF;
  INSERT INTO deedlight_execution_ledger.execution_commit_markers
    (system_identifier,database_oid,execution_id,source_identity,runner_identity,transaction_id)
  VALUES (v_identity.system_identifier,v_identity.database_oid,p_execution_id,p_source_identity,v_actor,
    pg_catalog.pg_current_xact_id()::text);
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.capture_snapshot(
  p_execution_id uuid, p_phase text, p_query_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_actor name;
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
        v_execution deedlight_execution_ledger.executions%ROWTYPE;
        v_query deedlight_execution_ledger.observation_queries%ROWTYPE;
        v_bundle deedlight_execution_ledger.query_bundle_manifests%ROWTYPE;
        v_rows jsonb;
        v_snapshot jsonb;
        v_observed_at timestamptz := pg_catalog.clock_timestamp();
BEGIN
  PERFORM deedlight_execution_ledger.current_database_identity();
  v_actor := deedlight_execution_ledger.actor_role();
  IF v_actor IS DISTINCT FROM 'deedlight_ledger_observer' THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('missing_trust','observer_authority_missing',jsonb_build_object('actor',v_actor));
  END IF;
  IF p_phase IS NULL OR p_phase NOT IN ('pre','post') THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('incomplete_preconditions','snapshot_phase_invalid',jsonb_build_object('phase',p_phase));
  END IF;
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  SELECT * INTO v_execution FROM deedlight_execution_ledger.executions
  WHERE system_identifier = v_identity.system_identifier AND database_oid = v_identity.database_oid
    AND execution_id = p_execution_id FOR SHARE;
  IF NOT FOUND THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('missing_execution_evidence','snapshot_execution_not_found',jsonb_build_object('executionId',p_execution_id));
  END IF;
  IF v_actor IN (v_execution.approver_identity, v_execution.runner_identity) THEN
    RAISE EXCEPTION 'snapshot observer must be independent of approver and runner';
  END IF;
  IF (p_phase = 'pre' AND v_execution.status <> 'reserved')
    OR (p_phase = 'post' AND v_execution.status <> 'running') THEN
    RAISE EXCEPTION 'snapshot phase does not match execution state';
  END IF;
  IF p_phase = 'post' AND NOT EXISTS (
    SELECT 1 FROM deedlight_execution_ledger.execution_commit_markers
    WHERE system_identifier = v_identity.system_identifier
      AND database_oid = v_identity.database_oid
      AND execution_id = p_execution_id
      AND source_identity = v_execution.source_identity
      AND runner_identity = v_execution.runner_identity
  ) THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('missing_execution_evidence','post_snapshot_commit_marker_missing',jsonb_build_object('executionId',p_execution_id));
  END IF;
  SELECT * INTO v_query FROM deedlight_execution_ledger.observation_queries WHERE query_id = p_query_id;
  IF NOT FOUND THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('missing_trust','observation_query_not_registered',jsonb_build_object('queryId',p_query_id));
  END IF;
  IF pg_catalog.encode(deedlight_execution_ledger.digest(pg_catalog.convert_to(v_query.query_sql,'UTF8'),'sha256'),'hex') <> v_query.query_sha256 THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('snapshot_substitution','registered_sql_digest_mismatch',jsonb_build_object('queryId',p_query_id));
  END IF;
  SELECT * INTO v_bundle FROM deedlight_execution_ledger.query_bundle_manifests
  WHERE bundle_id = v_query.query_bundle_id AND manifest_sha256 = v_query.query_bundle_digest;
  IF NOT FOUND THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('missing_trust','query_bundle_manifest_missing',jsonb_build_object('bundleId',v_query.query_bundle_id));
  END IF;
  IF v_bundle.member_count <> pg_catalog.jsonb_array_length(v_bundle.manifest)
    OR deedlight_execution_ledger.canonical_query_bundle_digest(v_bundle.manifest) <> v_bundle.manifest_sha256
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.jsonb_array_elements(v_bundle.manifest) AS member(value)
      WHERE value->>'queryId'=v_query.query_id AND value->>'querySha256'=v_query.query_sha256) THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('snapshot_substitution','query_bundle_manifest_integrity_or_membership_mismatch',jsonb_build_object('queryId',p_query_id,'bundleId',v_query.query_bundle_id));
  END IF;
  EXECUTE pg_catalog.format(
    'SELECT COALESCE(jsonb_agg(to_jsonb(q)), ''[]''::jsonb) FROM (%s) AS q', v_query.query_sql
  ) INTO v_rows;
  v_snapshot := pg_catalog.jsonb_build_object(
    'databaseIdentity', deedlight_execution_ledger.current_database_identity(),
    'queryId', p_query_id,
    'querySha256', v_query.query_sha256,
    'queryBundleDigest', v_query.query_bundle_digest,
    'rows', v_rows, 'observedAt', v_observed_at
  );
  INSERT INTO deedlight_execution_ledger.snapshots
    (system_identifier, database_oid, execution_id, phase, query_id,
     query_sha256, query_bundle_digest, observer_identity, observed_at, snapshot, snapshot_sha256)
  VALUES (v_identity.system_identifier, v_identity.database_oid, p_execution_id, p_phase,
    p_query_id, v_query.query_sha256, v_query.query_bundle_digest,
    v_actor, v_observed_at, v_snapshot,
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
DECLARE v_actor name;
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
BEGIN
  PERFORM deedlight_execution_ledger.current_database_identity();
  v_actor := deedlight_execution_ledger.actor_role();
  IF v_actor IS DISTINCT FROM 'deedlight_ledger_runner' THEN RAISE EXCEPTION 'migration runner authority required'; END IF;
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  IF NOT EXISTS (SELECT 1 FROM deedlight_execution_ledger.snapshots
    WHERE system_identifier = v_identity.system_identifier AND database_oid = v_identity.database_oid
      AND execution_id = p_execution_id AND phase = 'pre') THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('missing_execution_evidence','pre_execution_snapshot_missing',jsonb_build_object('executionId',p_execution_id));
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
DECLARE v_actor name;
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
BEGIN
  PERFORM deedlight_execution_ledger.current_database_identity();
  v_actor := deedlight_execution_ledger.actor_role();
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
DECLARE v_actor name;
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
BEGIN
  PERFORM deedlight_execution_ledger.current_database_identity();
  v_actor := deedlight_execution_ledger.actor_role();
  IF v_actor IS DISTINCT FROM 'deedlight_ledger_runner' THEN RAISE EXCEPTION 'migration runner authority required'; END IF;
  IF p_outcome NOT IN ('succeeded','failed','partial') OR p_outcome_detail IS NULL
    OR pg_catalog.jsonb_typeof(p_outcome_detail) <> 'object' THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('incomplete_preconditions','terminal_outcome_not_explicit_or_supported',jsonb_build_object('outcome',p_outcome));
  END IF;
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  IF NOT EXISTS (SELECT 1 FROM deedlight_execution_ledger.execution_commit_markers
    WHERE system_identifier = v_identity.system_identifier AND database_oid = v_identity.database_oid
      AND execution_id = p_execution_id) THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('missing_execution_evidence','committed_effect_marker_missing',jsonb_build_object('executionId',p_execution_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM deedlight_execution_ledger.snapshots
    WHERE system_identifier=v_identity.system_identifier AND database_oid=v_identity.database_oid
      AND execution_id=p_execution_id AND phase='pre') THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('incomplete_preconditions','pre_snapshot_missing',jsonb_build_object('executionId',p_execution_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM deedlight_execution_ledger.snapshots
    WHERE system_identifier=v_identity.system_identifier AND database_oid=v_identity.database_oid
      AND execution_id=p_execution_id AND phase='post') THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('incomplete_preconditions','post_snapshot_missing',jsonb_build_object('executionId',p_execution_id));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM deedlight_execution_ledger.snapshots pre
    JOIN deedlight_execution_ledger.snapshots post
      ON post.system_identifier=pre.system_identifier AND post.database_oid=pre.database_oid
      AND post.execution_id=pre.execution_id
    WHERE pre.system_identifier=v_identity.system_identifier AND pre.database_oid=v_identity.database_oid
      AND pre.execution_id=p_execution_id AND pre.phase='pre' AND post.phase='post'
      AND pre.query_id=post.query_id AND pre.query_sha256=post.query_sha256
      AND pre.query_bundle_digest=post.query_bundle_digest
  ) THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('snapshot_substitution','pre_post_query_identity_mismatch',jsonb_build_object('executionId',p_execution_id));
  END IF;
  UPDATE deedlight_execution_ledger.executions
  SET status = p_outcome, completed_at = pg_catalog.clock_timestamp(), outcome_detail = p_outcome_detail
  WHERE system_identifier = v_identity.system_identifier AND database_oid = v_identity.database_oid
    AND execution_id = p_execution_id AND status = 'running' AND runner_identity = v_actor;
  IF NOT FOUND THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure('failed_postconditions','execution_not_active_for_finalizing_runner',jsonb_build_object('executionId',p_execution_id));
  END IF;
END
$fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.recover_stale_executions(p_stale_after interval)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE v_actor name;
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
        v_count integer;
BEGIN
  PERFORM deedlight_execution_ledger.current_database_identity();
  v_actor := deedlight_execution_ledger.actor_role();
  IF v_actor IS DISTINCT FROM 'deedlight_ledger_recovery' THEN PERFORM deedlight_execution_ledger.raise_trust_failure('missing_trust','recovery_authority_missing',jsonb_build_object('actor',v_actor)); END IF;
  IF p_stale_after IS NULL OR p_stale_after <= interval '0 seconds'
    OR p_stale_after > interval '7 days' THEN PERFORM deedlight_execution_ledger.raise_trust_failure('incomplete_preconditions','recovery_timeout_outside_safe_bounds','{}'::jsonb); END IF;
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  UPDATE deedlight_execution_ledger.executions
  SET status = CASE WHEN status = 'reserved' THEN 'interrupted' ELSE 'unknown' END,
      completed_at = pg_catalog.clock_timestamp(),
      outcome_detail = CASE WHEN status='running' THEN pg_catalog.jsonb_build_object('category','ambiguous_execution_outcome','diagnosticCode','D1008','reason','running_execution_stale_after_heartbeat','recoveryActor',v_actor) ELSE pg_catalog.jsonb_build_object('category','incomplete_preconditions','reason','reserved_execution_expired_before_start','recoveryActor',v_actor) END
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
DECLARE v_actor name;
        v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
        v_execution deedlight_execution_ledger.executions%ROWTYPE;
BEGIN
  PERFORM deedlight_execution_ledger.current_database_identity();
  v_actor := deedlight_execution_ledger.actor_role();
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
    OR (OLD.status = 'running' AND NEW.status IN ('succeeded','failed','partial','unknown'))
    OR (OLD.status = 'running' AND NEW.status = 'running'
      AND NEW.runner_identity = OLD.runner_identity
      AND NEW.started_at = OLD.started_at
      AND NEW.completed_at IS NULL
      AND NEW.outcome_detail IS NULL
      AND NEW.heartbeat_at >= OLD.heartbeat_at)) THEN
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

DROP TRIGGER IF EXISTS execution_delete_guard ON deedlight_execution_ledger.executions;
CREATE TRIGGER execution_delete_guard BEFORE DELETE ON deedlight_execution_ledger.executions
FOR EACH ROW EXECUTE FUNCTION deedlight_execution_ledger.reject_ledger_mutation();
DROP TRIGGER IF EXISTS query_bundle_manifests_append_only ON deedlight_execution_ledger.query_bundle_manifests;
CREATE TRIGGER query_bundle_manifests_append_only BEFORE UPDATE OR DELETE
ON deedlight_execution_ledger.query_bundle_manifests
FOR EACH ROW EXECUTE FUNCTION deedlight_execution_ledger.reject_ledger_mutation();

DROP TRIGGER IF EXISTS query_bundle_manifests_append_only ON deedlight_execution_ledger.query_bundle_manifests;
CREATE TRIGGER query_bundle_manifests_append_only BEFORE UPDATE OR DELETE
ON deedlight_execution_ledger.query_bundle_manifests
FOR EACH ROW EXECUTE FUNCTION deedlight_execution_ledger.reject_ledger_mutation();
DROP TRIGGER IF EXISTS observation_queries_append_only ON deedlight_execution_ledger.observation_queries;
CREATE TRIGGER observation_queries_append_only BEFORE UPDATE OR DELETE ON deedlight_execution_ledger.observation_queries
FOR EACH ROW EXECUTE FUNCTION deedlight_execution_ledger.reject_ledger_mutation();
DROP TRIGGER IF EXISTS database_identity_append_only ON deedlight_execution_ledger.database_identity;
CREATE TRIGGER database_identity_append_only BEFORE UPDATE OR DELETE ON deedlight_execution_ledger.database_identity
FOR EACH ROW EXECUTE FUNCTION deedlight_execution_ledger.reject_ledger_mutation();

DROP TRIGGER IF EXISTS snapshots_append_only ON deedlight_execution_ledger.snapshots;
CREATE TRIGGER snapshots_append_only BEFORE UPDATE OR DELETE ON deedlight_execution_ledger.snapshots
FOR EACH ROW EXECUTE FUNCTION deedlight_execution_ledger.reject_ledger_mutation();
DROP TRIGGER IF EXISTS execution_commit_markers_append_only ON deedlight_execution_ledger.execution_commit_markers;
CREATE TRIGGER execution_commit_markers_append_only BEFORE UPDATE OR DELETE ON deedlight_execution_ledger.execution_commit_markers
FOR EACH ROW EXECUTE FUNCTION deedlight_execution_ledger.reject_ledger_mutation();
DROP TRIGGER IF EXISTS verification_events_append_only ON deedlight_execution_ledger.verification_events;
CREATE TRIGGER verification_events_append_only BEFORE UPDATE OR DELETE ON deedlight_execution_ledger.verification_events
FOR EACH ROW EXECUTE FUNCTION deedlight_execution_ledger.reject_ledger_mutation();

REVOKE ALL ON SCHEMA deedlight_execution_ledger FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA deedlight_execution_ledger FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA deedlight_execution_ledger FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA deedlight_execution_ledger FROM PUBLIC;
GRANT USAGE ON SCHEMA deedlight_execution_ledger TO
  deedlight_ledger_approver, deedlight_ledger_runner, deedlight_ledger_observer,
  deedlight_ledger_verifier, deedlight_ledger_recovery;
GRANT EXECUTE ON FUNCTION deedlight_execution_ledger.approve_execution(uuid,uuid,uuid,jsonb)
  TO deedlight_ledger_approver;
GRANT EXECUTE ON FUNCTION deedlight_execution_ledger.reserve_execution(uuid,uuid,uuid,jsonb),
  deedlight_execution_ledger.start_execution(uuid),
  deedlight_execution_ledger.record_effect_commit_marker(uuid,jsonb),
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
