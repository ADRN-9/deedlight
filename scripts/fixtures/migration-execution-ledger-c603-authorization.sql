-- C603 disposable PostgreSQL 16 overlay. Never apply this fixture to Production.
\set ON_ERROR_STOP on

DO $owner$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='deedlight_ledger_owner') THEN
    CREATE ROLE deedlight_ledger_owner NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
  END IF;
END
$owner$;

ALTER ROLE deedlight_ledger_owner INHERIT;
GRANT pg_monitor TO deedlight_ledger_owner;
GRANT USAGE, CREATE ON SCHEMA deedlight_execution_ledger TO deedlight_ledger_owner;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA deedlight_execution_ledger TO deedlight_ledger_owner;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA deedlight_execution_ledger TO deedlight_ledger_owner;

-- Five independent database principals; no actor is a member of another actor.
ALTER ROLE deedlight_ledger_approver LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
ALTER ROLE deedlight_ledger_runner LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
ALTER ROLE deedlight_ledger_observer LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
ALTER ROLE deedlight_ledger_recovery LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
ALTER ROLE deedlight_ledger_verifier LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
REVOKE deedlight_ledger_approver, deedlight_ledger_runner,
  deedlight_ledger_observer, deedlight_ledger_recovery,
  deedlight_ledger_verifier FROM postgres;

CREATE TABLE deedlight_execution_ledger.authorization_keys (
  actor name NOT NULL,
  principal name NOT NULL,
  key_id text NOT NULL,
  signing_key bytea NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  generation bigint NOT NULL,
  audience text NOT NULL,
  PRIMARY KEY (actor, key_id),
  UNIQUE (principal),
  CHECK (octet_length(signing_key) >= 32)
);

-- Disposable-only deterministic keys. Never reuse these values outside CI.
INSERT INTO deedlight_execution_ledger.authorization_keys
  (actor,principal,key_id,signing_key,generation,audience)
VALUES
 ('deedlight_ledger_approver','deedlight_ledger_approver','c603-approver-v1',decode(repeat('11',32),'hex'),1,'deedlight.execution-ledger.gateway.v1'),
 ('deedlight_ledger_runner','deedlight_ledger_runner','c603-runner-v1',decode(repeat('22',32),'hex'),1,'deedlight.execution-ledger.gateway.v1'),
 ('deedlight_ledger_observer','deedlight_ledger_observer','c603-observer-v1',decode(repeat('33',32),'hex'),1,'deedlight.execution-ledger.gateway.v1'),
 ('deedlight_ledger_recovery','deedlight_ledger_recovery','c603-recovery-v1',decode(repeat('44',32),'hex'),1,'deedlight.execution-ledger.gateway.v1'),
 ('deedlight_ledger_verifier','deedlight_ledger_verifier','c603-verifier-v1',decode(repeat('55',32),'hex'),1,'deedlight.execution-ledger.gateway.v1');

CREATE TABLE deedlight_execution_ledger.authorization_nonces (
  actor name NOT NULL,
  nonce uuid NOT NULL,
  request_digest text NOT NULL CHECK (request_digest ~ '^[a-f0-9]{64}$'),
  accepted_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (actor,nonce)
);

-- Actor identity is the authenticated login principal (session_user), never SET ROLE.
CREATE OR REPLACE FUNCTION deedlight_execution_ledger.actor_role()
RETURNS name
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
  SELECT CASE session_user::text
    WHEN 'deedlight_ledger_approver' THEN 'deedlight_ledger_approver'::name
    WHEN 'deedlight_ledger_runner' THEN 'deedlight_ledger_runner'::name
    WHEN 'deedlight_ledger_observer' THEN 'deedlight_ledger_observer'::name
    WHEN 'deedlight_ledger_recovery' THEN 'deedlight_ledger_recovery'::name
    WHEN 'deedlight_ledger_verifier' THEN 'deedlight_ledger_verifier'::name
    ELSE NULL
  END
$fn$;

-- Retain the original business logic as owner-only implementation functions.
ALTER FUNCTION deedlight_execution_ledger.approve_execution(uuid,uuid,uuid,jsonb) RENAME TO approve_execution_impl;
ALTER FUNCTION deedlight_execution_ledger.reserve_execution(uuid,uuid,uuid,jsonb) RENAME TO reserve_execution_impl;
ALTER FUNCTION deedlight_execution_ledger.record_effect_commit_marker(uuid,jsonb) RENAME TO record_effect_commit_marker_impl;
ALTER FUNCTION deedlight_execution_ledger.capture_snapshot(uuid,text,text) RENAME TO capture_snapshot_impl;
ALTER FUNCTION deedlight_execution_ledger.start_execution(uuid) RENAME TO start_execution_impl;
ALTER FUNCTION deedlight_execution_ledger.heartbeat_execution(uuid) RENAME TO heartbeat_execution_impl;
ALTER FUNCTION deedlight_execution_ledger.finalize_execution(uuid,text,jsonb) RENAME TO finalize_execution_impl;
ALTER FUNCTION deedlight_execution_ledger.recover_stale_executions(interval) RENAME TO recover_stale_executions_impl;
ALTER FUNCTION deedlight_execution_ledger.record_verification(uuid,text,jsonb) RENAME TO record_verification_impl;

ALTER FUNCTION deedlight_execution_ledger.approve_execution_impl(uuid,uuid,uuid,jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.reserve_execution_impl(uuid,uuid,uuid,jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.record_effect_commit_marker_impl(uuid,jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.capture_snapshot_impl(uuid,text,text) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.start_execution_impl(uuid) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.heartbeat_execution_impl(uuid) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.finalize_execution_impl(uuid,text,jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.recover_stale_executions_impl(interval) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.record_verification_impl(uuid,text,jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.current_database_identity() OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.actor_role() OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.raise_trust_failure(text,text,jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.valid_source_identity(jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.canonical_query_bundle_digest(jsonb) OWNER TO deedlight_ledger_owner;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.authorize_request(
  p_envelope jsonb,
  p_operation text,
  p_actor name,
  p_execution_id uuid,
  p_request jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger
AS $fn$
DECLARE
  v_principal name := session_user::name;
  v_key deedlight_execution_ledger.authorization_keys%ROWTYPE;
  v_resource jsonb;
  v_request_digest text;
  v_expected_signature text;
  v_issued_at timestamptz;
  v_expires_at timestamptz;
  v_rows integer;
BEGIN
  IF p_envelope IS NULL OR pg_catalog.jsonb_typeof(p_envelope) IS DISTINCT FROM 'object'
    OR (SELECT pg_catalog.count(*) FROM pg_catalog.jsonb_object_keys(p_envelope)) <> 15
    OR NOT (p_envelope ?& ARRAY['version','operation','actor','principal','executionId',
      'databaseResource','generation','audience','nonce','issuedAt','expiresAt',
      'request','requestDigest','keyId','signature']) THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'missing_trust','authorization_envelope_shape_invalid','{}'::jsonb);
  END IF;

  IF p_envelope->>'version' IS DISTINCT FROM '1'
    OR p_envelope->>'operation' IS DISTINCT FROM p_operation
    OR p_envelope->>'actor' IS DISTINCT FROM p_actor::text
    OR p_envelope->>'principal' IS DISTINCT FROM v_principal::text
    OR p_envelope->>'executionId' IS DISTINCT FROM p_execution_id::text
    OR p_envelope->'request' IS DISTINCT FROM p_request
    OR p_envelope->>'audience' IS DISTINCT FROM 'deedlight.execution-ledger.gateway.v1'
    OR p_envelope->>'generation' IS DISTINCT FROM '1'
    OR p_envelope->>'keyId' IS DISTINCT FROM ('c603-' || replace(p_actor::text,'deedlight_ledger_','') || '-v1') THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'missing_trust','authorization_request_binding_mismatch',
      pg_catalog.jsonb_build_object('operation',p_operation,'actor',p_actor));
  END IF;

  v_request_digest := pg_catalog.encode(
    deedlight_execution_ledger.digest(
      pg_catalog.convert_to(p_request::text,'UTF8'),'sha256'),'hex');
  IF p_envelope->>'requestDigest' IS DISTINCT FROM v_request_digest THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'missing_trust','authorization_request_digest_mismatch','{}'::jsonb);
  END IF;

  v_resource := deedlight_execution_ledger.current_database_identity();
  IF p_envelope->'databaseResource' IS DISTINCT FROM v_resource THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'missing_trust','authorization_database_resource_mismatch','{}'::jsonb);
  END IF;

  SELECT * INTO v_key
  FROM deedlight_execution_ledger.authorization_keys
  WHERE actor=p_actor AND principal=v_principal
    AND key_id=p_envelope->>'keyId' AND enabled AND generation=1
    AND audience='deedlight.execution-ledger.gateway.v1';
  IF NOT FOUND THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'missing_trust','authorization_key_not_found','{}'::jsonb);
  END IF;
  IF deedlight_execution_ledger.actor_role() IS DISTINCT FROM p_actor THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'missing_trust','authorization_principal_not_authorized','{}'::jsonb);
  END IF;

  v_issued_at := (p_envelope->>'issuedAt')::timestamptz;
  v_expires_at := (p_envelope->>'expiresAt')::timestamptz;
  IF v_issued_at > pg_catalog.clock_timestamp() + interval '15 seconds'
    OR v_expires_at <= pg_catalog.clock_timestamp()
    OR v_expires_at <= v_issued_at
    OR v_expires_at > v_issued_at + interval '2 minutes' THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'missing_trust','authorization_envelope_expired_or_out_of_window','{}'::jsonb);
  END IF;

  IF coalesce(p_envelope->>'nonce','') !~ '^[0-9a-fA-F-]{36}$'
    OR coalesce(p_envelope->>'signature','') !~ '^[a-f0-9]{64}$' THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'missing_trust','authorization_nonce_or_signature_invalid','{}'::jsonb);
  END IF;

  v_expected_signature := pg_catalog.encode(
    deedlight_execution_ledger.hmac(
      pg_catalog.convert_to((p_envelope - 'signature')::text,'UTF8'),
      v_key.signing_key,'sha256'),'hex');
  IF v_expected_signature IS DISTINCT FROM p_envelope->>'signature' THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'missing_trust','authorization_signature_invalid','{}'::jsonb);
  END IF;

  INSERT INTO deedlight_execution_ledger.authorization_nonces
    (actor,nonce,request_digest,expires_at)
  VALUES (p_actor,(p_envelope->>'nonce')::uuid,v_request_digest,v_expires_at)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    PERFORM deedlight_execution_ledger.raise_trust_failure(
      'replay','authorization_nonce_replayed','{}'::jsonb);
  END IF;
END
$fn$;

ALTER FUNCTION deedlight_execution_ledger.authorize_request(jsonb,text,name,uuid,jsonb) OWNER TO deedlight_ledger_owner;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.approve_execution(
  p_approval_id uuid,p_record_id uuid,p_execution_id uuid,p_source_identity jsonb,p_authorization jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger AS $fn$
BEGIN
  PERFORM deedlight_execution_ledger.authorize_request(p_authorization,'approve_execution',
    'deedlight_ledger_approver',p_execution_id,
    pg_catalog.jsonb_build_object('approvalId',p_approval_id,'recordId',p_record_id,
      'executionId',p_execution_id,'sourceIdentity',p_source_identity));
  PERFORM deedlight_execution_ledger.approve_execution_impl(p_approval_id,p_record_id,p_execution_id,p_source_identity);
END $fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.reserve_execution(
  p_approval_id uuid,p_record_id uuid,p_execution_id uuid,p_source_identity jsonb,p_authorization jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger AS $fn$
BEGIN
  PERFORM deedlight_execution_ledger.authorize_request(p_authorization,'reserve_execution',
    'deedlight_ledger_runner',p_execution_id,
    pg_catalog.jsonb_build_object('approvalId',p_approval_id,'recordId',p_record_id,
      'executionId',p_execution_id,'sourceIdentity',p_source_identity));
  PERFORM deedlight_execution_ledger.reserve_execution_impl(p_approval_id,p_record_id,p_execution_id,p_source_identity);
END $fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.record_effect_commit_marker(
  p_execution_id uuid,p_source_identity jsonb,p_authorization jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger AS $fn$
BEGIN
  PERFORM deedlight_execution_ledger.authorize_request(p_authorization,'record_effect_commit_marker',
    'deedlight_ledger_runner',p_execution_id,
    pg_catalog.jsonb_build_object('executionId',p_execution_id,'sourceIdentity',p_source_identity));
  PERFORM deedlight_execution_ledger.record_effect_commit_marker_impl(p_execution_id,p_source_identity);
END $fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.capture_snapshot(
  p_execution_id uuid,p_phase text,p_query_id text,p_authorization jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger AS $fn$
DECLARE v_source jsonb;
BEGIN
  SELECT source_identity INTO STRICT v_source FROM deedlight_execution_ledger.executions
  WHERE execution_id=p_execution_id;
  PERFORM deedlight_execution_ledger.authorize_request(p_authorization,'capture_snapshot',
    'deedlight_ledger_observer',p_execution_id,
    pg_catalog.jsonb_build_object('executionId',p_execution_id,'phase',p_phase,
      'queryId',p_query_id,'sourceIdentity',v_source));
  RETURN deedlight_execution_ledger.capture_snapshot_impl(p_execution_id,p_phase,p_query_id);
END $fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.start_execution(
  p_execution_id uuid,p_authorization jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger AS $fn$
DECLARE v_source jsonb;
BEGIN
  SELECT source_identity INTO STRICT v_source FROM deedlight_execution_ledger.executions
  WHERE execution_id=p_execution_id;
  PERFORM deedlight_execution_ledger.authorize_request(p_authorization,'start_execution',
    'deedlight_ledger_runner',p_execution_id,
    pg_catalog.jsonb_build_object('executionId',p_execution_id,'sourceIdentity',v_source));
  PERFORM deedlight_execution_ledger.start_execution_impl(p_execution_id);
END $fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.heartbeat_execution(
  p_execution_id uuid,p_authorization jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger AS $fn$
DECLARE v_source jsonb;
BEGIN
  SELECT source_identity INTO STRICT v_source FROM deedlight_execution_ledger.executions
  WHERE execution_id=p_execution_id;
  PERFORM deedlight_execution_ledger.authorize_request(p_authorization,'heartbeat_execution',
    'deedlight_ledger_runner',p_execution_id,
    pg_catalog.jsonb_build_object('executionId',p_execution_id,'sourceIdentity',v_source));
  PERFORM deedlight_execution_ledger.heartbeat_execution_impl(p_execution_id);
END $fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.finalize_execution(
  p_execution_id uuid,p_outcome text,p_outcome_detail jsonb,p_authorization jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger AS $fn$
DECLARE v_source jsonb;
BEGIN
  SELECT source_identity INTO STRICT v_source FROM deedlight_execution_ledger.executions
  WHERE execution_id=p_execution_id;
  PERFORM deedlight_execution_ledger.authorize_request(p_authorization,'finalize_execution',
    'deedlight_ledger_runner',p_execution_id,
    pg_catalog.jsonb_build_object('executionId',p_execution_id,'outcome',p_outcome,
      'outcomeDetail',p_outcome_detail,'sourceIdentity',v_source));
  PERFORM deedlight_execution_ledger.finalize_execution_impl(p_execution_id,p_outcome,p_outcome_detail);
END $fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.recover_stale_executions(
  p_stale_after interval,p_authorization jsonb
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger AS $fn$
DECLARE v_targets jsonb; v_digest text; v_count integer;
BEGIN
  SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'executionId',execution_id,'sourceIdentity',source_identity,
      'status',status,'heartbeatAt',heartbeat_at) ORDER BY execution_id),'[]'::jsonb)
    INTO v_targets
  FROM deedlight_execution_ledger.executions
  WHERE status IN ('reserved','running')
    AND heartbeat_at < pg_catalog.clock_timestamp() - p_stale_after;
  v_count := pg_catalog.jsonb_array_length(v_targets);
  v_digest := pg_catalog.encode(deedlight_execution_ledger.digest(
    pg_catalog.convert_to(v_targets::text,'UTF8'),'sha256'),'hex');
  PERFORM deedlight_execution_ledger.authorize_request(p_authorization,'recover_stale_executions',
    'deedlight_ledger_recovery',NULL,
    pg_catalog.jsonb_build_object('staleAfter',p_stale_after::text,
      'sourceSetDigest',v_digest,'targetCount',v_count));
  RETURN deedlight_execution_ledger.recover_stale_executions_impl(p_stale_after);
END $fn$;

CREATE OR REPLACE FUNCTION deedlight_execution_ledger.record_verification(
  p_execution_id uuid,p_verdict text,p_evidence jsonb,p_authorization jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, deedlight_execution_ledger AS $fn$
DECLARE v_source jsonb;
BEGIN
  SELECT source_identity INTO STRICT v_source FROM deedlight_execution_ledger.executions
  WHERE execution_id=p_execution_id;
  PERFORM deedlight_execution_ledger.authorize_request(p_authorization,'record_verification',
    'deedlight_ledger_verifier',p_execution_id,
    pg_catalog.jsonb_build_object('executionId',p_execution_id,'verdict',p_verdict,
      'evidence',p_evidence,'sourceIdentity',v_source));
  PERFORM deedlight_execution_ledger.record_verification_impl(p_execution_id,p_verdict,p_evidence);
END $fn$;

-- Owner-only internals; public and runtime actors cannot call the old RPC bodies.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA deedlight_execution_ledger FROM PUBLIC,
  deedlight_ledger_approver,deedlight_ledger_runner,deedlight_ledger_observer,
  deedlight_ledger_recovery,deedlight_ledger_verifier;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA deedlight_execution_ledger TO deedlight_ledger_owner;
GRANT SELECT ON deedlight_execution_ledger.authorization_keys TO deedlight_ledger_owner;
GRANT INSERT,SELECT ON deedlight_execution_ledger.authorization_nonces TO deedlight_ledger_owner;
GRANT USAGE ON SCHEMA deedlight_execution_ledger TO
  deedlight_ledger_approver,deedlight_ledger_runner,deedlight_ledger_observer,
  deedlight_ledger_recovery,deedlight_ledger_verifier;

ALTER FUNCTION deedlight_execution_ledger.approve_execution(uuid,uuid,uuid,jsonb,jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.reserve_execution(uuid,uuid,uuid,jsonb,jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.record_effect_commit_marker(uuid,jsonb,jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.capture_snapshot(uuid,text,text,jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.start_execution(uuid,jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.heartbeat_execution(uuid,jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.finalize_execution(uuid,text,jsonb,jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.recover_stale_executions(interval,jsonb) OWNER TO deedlight_ledger_owner;
ALTER FUNCTION deedlight_execution_ledger.record_verification(uuid,text,jsonb,jsonb) OWNER TO deedlight_ledger_owner;

GRANT EXECUTE ON FUNCTION deedlight_execution_ledger.approve_execution(uuid,uuid,uuid,jsonb,jsonb) TO deedlight_ledger_approver;
GRANT EXECUTE ON FUNCTION deedlight_execution_ledger.reserve_execution(uuid,uuid,uuid,jsonb,jsonb),
  deedlight_execution_ledger.record_effect_commit_marker(uuid,jsonb,jsonb),
  deedlight_execution_ledger.start_execution(uuid,jsonb),
  deedlight_execution_ledger.heartbeat_execution(uuid,jsonb),
  deedlight_execution_ledger.finalize_execution(uuid,text,jsonb,jsonb) TO deedlight_ledger_runner;
GRANT EXECUTE ON FUNCTION deedlight_execution_ledger.capture_snapshot(uuid,text,text,jsonb) TO deedlight_ledger_observer;
GRANT EXECUTE ON FUNCTION deedlight_execution_ledger.recover_stale_executions(interval,jsonb) TO deedlight_ledger_recovery;
GRANT EXECUTE ON FUNCTION deedlight_execution_ledger.record_verification(uuid,text,jsonb,jsonb) TO deedlight_ledger_verifier;
REVOKE CREATE ON SCHEMA deedlight_execution_ledger FROM deedlight_ledger_owner;

-- The definer is deliberately a NOLOGIN, non-superuser role.
DO $assert$
DECLARE v_actor name;
BEGIN
  IF (SELECT rolsuper OR rolcanlogin FROM pg_catalog.pg_roles WHERE rolname='deedlight_ledger_owner') THEN
    RAISE EXCEPTION 'C603 definer owner must be NOLOGIN and NOSUPERUSER';
  END IF;
  FOREACH v_actor IN ARRAY ARRAY['deedlight_ledger_approver','deedlight_ledger_runner',
    'deedlight_ledger_observer','deedlight_ledger_recovery','deedlight_ledger_verifier']::name[] LOOP
    IF EXISTS (
      SELECT 1 FROM pg_catalog.pg_auth_members m
      JOIN pg_catalog.pg_roles r ON r.oid=m.roleid
      JOIN pg_catalog.pg_roles member ON member.oid=m.member
      WHERE r.rolname IN ('deedlight_ledger_approver','deedlight_ledger_runner',
        'deedlight_ledger_observer','deedlight_ledger_recovery','deedlight_ledger_verifier')
        AND member.rolname=v_actor
    ) THEN RAISE EXCEPTION 'C603 actor role membership must be empty: %',v_actor; END IF;
  END LOOP;
END
$assert$;

SELECT 'C603_SIGNED_AUTHORIZATION_OVERLAY_INSTALLED' AS evidence;
