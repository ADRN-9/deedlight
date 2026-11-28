\set ON_ERROR_STOP on

CREATE SCHEMA c608_test;

CREATE OR REPLACE FUNCTION c608_test.seed_execution(
  p_execution_id uuid,p_status text,p_heartbeat_at timestamptz
) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
  v_approval_id uuid := deedlight_execution_ledger.gen_random_uuid();
  v_record_id uuid := deedlight_execution_ledger.gen_random_uuid();
  v_source jsonb := '{"path":"c608-disposable-recovery-test","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb;
BEGIN
  IF p_status NOT IN ('reserved','running') THEN RAISE EXCEPTION 'invalid seed status'; END IF;
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  INSERT INTO deedlight_execution_ledger.approvals
    (approval_id,system_identifier,database_oid,database_name,record_id,execution_id,
     source_identity,approver_identity)
  VALUES (v_approval_id,v_identity.system_identifier,v_identity.database_oid,
    v_identity.database_name,v_record_id,p_execution_id,v_source,'c608-test-approver');
  INSERT INTO deedlight_execution_ledger.executions
    (system_identifier,database_oid,database_name,record_id,execution_id,approval_id,
     source_identity,status,approver_identity,runner_identity,started_at,heartbeat_at)
  VALUES (v_identity.system_identifier,v_identity.database_oid,v_identity.database_name,
    v_record_id,p_execution_id,v_approval_id,v_source,p_status,'c608-test-approver',
    CASE WHEN p_status='running' THEN 'c608-test-runner'::name ELSE NULL END,
    CASE WHEN p_status='running' THEN pg_catalog.clock_timestamp() ELSE NULL END,
    p_heartbeat_at);
END
$fn$;

CREATE OR REPLACE FUNCTION c608_test.assert_execution_snapshot(
  p_execution_id uuid,p_status text,p_heartbeat_at timestamptz,
  p_source_identity jsonb,p_row_version bigint
) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_actual deedlight_execution_ledger.executions%ROWTYPE;
BEGIN
  SELECT * INTO v_actual FROM deedlight_execution_ledger.executions
  WHERE execution_id=p_execution_id;
  IF NOT FOUND OR v_actual.status IS DISTINCT FROM p_status
    OR v_actual.heartbeat_at IS DISTINCT FROM p_heartbeat_at
    OR v_actual.source_identity IS DISTINCT FROM p_source_identity
    OR v_actual.c603_row_version IS DISTINCT FROM p_row_version THEN
    RAISE EXCEPTION 'C610 execution snapshot mismatch for %: actual=(%,%,%,%) expected=(%,%,%,%)',
      p_execution_id,v_actual.status,v_actual.heartbeat_at,v_actual.source_identity,
      v_actual.c603_row_version,p_status,p_heartbeat_at,p_source_identity,p_row_version;
  END IF;
END
$fn$;

CREATE OR REPLACE FUNCTION c608_test.request(p_execution_ids uuid[],p_stale_after interval)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE
  v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
  v_requested_count integer;
  v_eligible_count integer;
  v_targets jsonb;
BEGIN
  SELECT * INTO STRICT v_identity
  FROM deedlight_execution_ledger.database_identity WHERE singleton;
  IF p_execution_ids IS NULL OR pg_catalog.cardinality(p_execution_ids)=0
    OR pg_catalog.cardinality(p_execution_ids)>10000
    OR pg_catalog.array_position(p_execution_ids,NULL) IS NOT NULL
    OR p_stale_after IS NULL OR p_stale_after<=interval '0 seconds'
    OR p_stale_after>interval '7 days' THEN
    RAISE EXCEPTION USING ERRCODE='D1006',
      MESSAGE='C608 recovery authorization request is invalid';
  END IF;

  SELECT pg_catalog.count(DISTINCT requested.execution_id)
  INTO v_requested_count
  FROM pg_catalog.unnest(p_execution_ids) AS requested(execution_id);
  IF v_requested_count<>pg_catalog.cardinality(p_execution_ids) THEN
    RAISE EXCEPTION USING ERRCODE='D1006',
      MESSAGE='C608 recovery authorization request contains duplicate IDs';
  END IF;

  SELECT pg_catalog.count(*),
    coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'executionId',execution.execution_id,
      'expectedStatus',execution.status,
      'expectedSourceIdentity',execution.source_identity,
      'expectedHeartbeatAt',execution.heartbeat_at,
      'expectedRowVersion',execution.c603_row_version)
      ORDER BY execution.execution_id),'[]'::jsonb)
  INTO v_eligible_count,v_targets
  FROM deedlight_execution_ledger.executions AS execution
  WHERE execution.system_identifier=v_identity.system_identifier
    AND execution.database_oid=v_identity.database_oid
    AND execution.execution_id=ANY(p_execution_ids)
    AND execution.status IN ('reserved','running')
    AND execution.heartbeat_at < pg_catalog.clock_timestamp()-p_stale_after;

  IF v_eligible_count<>pg_catalog.cardinality(p_execution_ids) THEN
    RAISE EXCEPTION USING ERRCODE='D1006',
      MESSAGE='C608 every requested execution ID must resolve to one eligible target';
  END IF;

  RETURN c603_test.sign_recovery(pg_catalog.jsonb_build_object(
    'staleAfter',p_stale_after::text,'targets',v_targets));
END
$fn$;
REVOKE ALL ON FUNCTION c608_test.seed_execution(uuid,text,timestamptz),
  c608_test.request(uuid[],interval) FROM PUBLIC,
  deedlight_ledger_approver,deedlight_ledger_runner,deedlight_ledger_observer,
  deedlight_ledger_recovery,deedlight_ledger_verifier;
CREATE OR REPLACE FUNCTION c608_test.assert_trust_failure(p_sql text,p_expected_reason text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_state text; v_detail text;
BEGIN
  BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'C613 expected trust failure but statement succeeded: %',p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state=RETURNED_SQLSTATE,v_detail=PG_EXCEPTION_DETAIL;
    IF v_state IS DISTINCT FROM 'D1006'
      OR v_detail IS NULL
      OR (v_detail::jsonb->>'reason') IS DISTINCT FROM p_expected_reason THEN
      RAISE EXCEPTION 'C613 wrong trust failure: expected D1006/% got %/% for %',
        p_expected_reason,v_state,v_detail,p_sql;
    END IF;
  END;
END
$fn$;
CREATE OR REPLACE FUNCTION c608_test.assert_nonce_absent(p_authorization jsonb)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  IF EXISTS (
    SELECT 1 FROM deedlight_execution_ledger.authorization_nonces
    WHERE actor='deedlight_ledger_recovery'
      AND nonce=(p_authorization->>'nonce')::uuid
  ) THEN
    RAISE EXCEPTION 'C613 rejected recovery request consumed its authorization nonce';
  END IF;
END
$fn$;
CREATE OR REPLACE FUNCTION c608_test.assert_business_snapshot()
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_before jsonb; v_after jsonb;
BEGIN
  SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(row_data) ORDER BY row_data.execution_id),'[]'::jsonb)
  INTO v_before FROM pg_temp.c613_business_before AS row_data;
  SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(row_data) ORDER BY row_data.execution_id),'[]'::jsonb)
  INTO v_after FROM deedlight_execution_ledger.executions AS row_data;
  IF v_before IS DISTINCT FROM v_after THEN
    RAISE EXCEPTION 'C613 rejected request partially mutated business rows';
  END IF;
END
$fn$;
REVOKE ALL ON FUNCTION c608_test.assert_trust_failure(text,text),
  c608_test.assert_nonce_absent(jsonb),c608_test.assert_business_snapshot() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION c608_test.assert_trust_failure(text,text)
  TO deedlight_ledger_recovery;

-- Heartbeat change after signing invalidates the entire two-row request.
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000001','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000002','reserved',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.request(ARRAY[
  'c6080000-0000-4000-8000-000000000001',
  'c6080000-0000-4000-8000-000000000002'
]::uuid[],interval '1 minute') AS heartbeat_race_auth \gset
UPDATE deedlight_execution_ledger.executions
SET heartbeat_at=pg_catalog.clock_timestamp()
WHERE execution_id='c6080000-0000-4000-8000-000000000001';
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT c603_test.assert_rejected(format(
  'SELECT deedlight_execution_ledger.recover_stale_executions(%L::interval,%L::jsonb)',
  '1 minute',:'heartbeat_race_auth'),'D1006');
RESET SESSION AUTHORIZATION;
DO $assert$
BEGIN
  IF (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000001') IS DISTINCT FROM 'running'
    OR (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000002') IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'C608 heartbeat rejection partially mutated the authorized target set';
  END IF;
END
$assert$;
SELECT 'C608_HEARTBEAT_CHANGE_REJECTED_ZERO_PARTIAL_MUTATION_PASS' AS evidence;

-- Finalization after signing invalidates the whole set; the other target stays active.
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000003','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000004','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.request(ARRAY[
  'c6080000-0000-4000-8000-000000000003',
  'c6080000-0000-4000-8000-000000000004'
]::uuid[],interval '1 minute') AS finalize_race_auth \gset
UPDATE deedlight_execution_ledger.executions
SET status='succeeded',completed_at=pg_catalog.clock_timestamp(),
    outcome_detail='{"result":"completed-after-recovery-authorization"}'::jsonb
WHERE execution_id='c6080000-0000-4000-8000-000000000003';
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT c603_test.assert_rejected(format(
  'SELECT deedlight_execution_ledger.recover_stale_executions(%L::interval,%L::jsonb)',
  '1 minute',:'finalize_race_auth'),'D1006');
RESET SESSION AUTHORIZATION;
DO $assert$
BEGIN
  IF (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000003') IS DISTINCT FROM 'succeeded'
    OR (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000004') IS DISTINCT FROM 'running' THEN
    RAISE EXCEPTION 'C608 finalization rejection partially mutated the authorized target set';
  END IF;
END
$assert$;
SELECT 'C608_FINALIZATION_AFTER_AUTH_REJECTED_ZERO_PARTIAL_MUTATION_PASS' AS evidence;

-- A row crosses the stale threshold after signing; it is excluded and untouched.
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000005','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000006','running',
  pg_catalog.clock_timestamp()-interval '0.5 seconds');
SELECT c608_test.request(ARRAY[
  'c6080000-0000-4000-8000-000000000005'
]::uuid[],interval '1 second') AS new_stale_auth \gset
SELECT pg_catalog.pg_sleep(0.7);
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT deedlight_execution_ledger.recover_stale_executions(
  interval '1 second',:'new_stale_auth'::jsonb);
RESET SESSION AUTHORIZATION;
DO $assert$
BEGIN
  IF (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000005') IS DISTINCT FROM 'unknown'
    OR (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000006') IS DISTINCT FROM 'running' THEN
    RAISE EXCEPTION 'C608 recovery mutated a newly stale row outside the authorized target set';
  END IF;
END
$assert$;
SELECT 'C608_NEWLY_STALE_ROW_EXCLUDED_FROM_MUTATION_PASS' AS evidence;

-- A disappeared target rejects the complete operation and leaves remaining rows untouched.
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000007','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000008','reserved',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.request(ARRAY[
  'c6080000-0000-4000-8000-000000000007',
  'c6080000-0000-4000-8000-000000000008'
]::uuid[],interval '1 minute') AS missing_target_auth \gset
-- Simulate an out-of-band disappearance in this disposable database only.
ALTER TABLE deedlight_execution_ledger.executions DISABLE TRIGGER execution_delete_guard;
DELETE FROM deedlight_execution_ledger.executions
WHERE execution_id='c6080000-0000-4000-8000-000000000007';
ALTER TABLE deedlight_execution_ledger.executions ENABLE TRIGGER execution_delete_guard;
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT c603_test.assert_rejected(format(
  'SELECT deedlight_execution_ledger.recover_stale_executions(%L::interval,%L::jsonb)',
  '1 minute',:'missing_target_auth'),'D1006');
RESET SESSION AUTHORIZATION;
DO $assert$
BEGIN
  IF (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000008') IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'C608 missing-target rejection partially mutated remaining targets';
  END IF;
END
$assert$;
SELECT 'C608_MISSING_TARGET_REJECTED_ZERO_PARTIAL_MUTATION_PASS' AS evidence;

-- Source identity is checked independently of heartbeat and row version.
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000012','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000013','reserved',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.request(ARRAY[
  'c6080000-0000-4000-8000-000000000012',
  'c6080000-0000-4000-8000-000000000013'
]::uuid[],interval '1 minute') AS source_identity_auth \gset
ALTER TABLE deedlight_execution_ledger.executions
  DISABLE TRIGGER execution_transition_guard;
ALTER TABLE deedlight_execution_ledger.executions
  DISABLE TRIGGER a_c603_execution_row_version;
UPDATE deedlight_execution_ledger.executions
SET source_identity='{"path":"c608-disposable-source-changed","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'::jsonb
WHERE execution_id='c6080000-0000-4000-8000-000000000012';
ALTER TABLE deedlight_execution_ledger.executions
  ENABLE TRIGGER a_c603_execution_row_version;
ALTER TABLE deedlight_execution_ledger.executions
  ENABLE TRIGGER execution_transition_guard;
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT c603_test.assert_rejected(format(
  'SELECT deedlight_execution_ledger.recover_stale_executions(%L::interval,%L::jsonb)',
  '1 minute',:'source_identity_auth'),'D1006');
RESET SESSION AUTHORIZATION;
SELECT c608_test.assert_execution_snapshot(
  'c6080000-0000-4000-8000-000000000012','running',
  (:'source_identity_auth'::jsonb->'request'->'targets'->0->>'expectedHeartbeatAt')::timestamptz,
  '{"path":"c608-disposable-source-changed","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'::jsonb,
  (:'source_identity_auth'::jsonb->'request'->'targets'->0->>'expectedRowVersion')::bigint
);
DO $assert$
BEGIN
  IF (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000013') IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'C610 source-identity-only rejection partially mutated the other target';
  END IF;
END
$assert$;
SELECT 'C610_SOURCE_IDENTITY_ONLY_CHANGE_REJECTED_ZERO_MUTATION_PASS' AS evidence;

-- Row-version mismatch is checked independently of heartbeat and source identity.
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000014','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000015','reserved',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.request(ARRAY[
  'c6080000-0000-4000-8000-000000000014',
  'c6080000-0000-4000-8000-000000000015'
]::uuid[],interval '1 minute') AS row_version_auth \gset
ALTER TABLE deedlight_execution_ledger.executions DISABLE TRIGGER a_c603_execution_row_version;
UPDATE deedlight_execution_ledger.executions
SET c603_row_version=c603_row_version+1
WHERE execution_id='c6080000-0000-4000-8000-000000000014';
ALTER TABLE deedlight_execution_ledger.executions ENABLE TRIGGER a_c603_execution_row_version;
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT c603_test.assert_rejected(format(
  'SELECT deedlight_execution_ledger.recover_stale_executions(%L::interval,%L::jsonb)',
  '1 minute',:'row_version_auth'),'D1006');
RESET SESSION AUTHORIZATION;
SELECT c608_test.assert_execution_snapshot(
  'c6080000-0000-4000-8000-000000000014','running',
  (:'row_version_auth'::jsonb->'request'->'targets'->0->>'expectedHeartbeatAt')::timestamptz,
  :'row_version_auth'::jsonb->'request'->'targets'->0->'expectedSourceIdentity',
  (:'row_version_auth'::jsonb->'request'->'targets'->0->>'expectedRowVersion')::bigint+1
);
DO $assert$
BEGIN
  IF (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000015') IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'C610 row-version-only rejection partially mutated the other target';
  END IF;
END
$assert$;
SELECT 'C610_ROW_VERSION_ONLY_CHANGE_REJECTED_ZERO_MUTATION_PASS' AS evidence;

-- Duplicate input IDs must not be silently collapsed into a smaller signed set.
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000016','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c603_test.assert_rejected(
  'SELECT c608_test.request(ARRAY[''c6080000-0000-4000-8000-000000000016'',''c6080000-0000-4000-8000-000000000016'']::uuid[],interval ''1 minute'')',
  'D1006');
DO $assert$
BEGIN
  IF (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000016') IS DISTINCT FROM 'running' THEN
    RAISE EXCEPTION 'C610 duplicate input rejection mutated an execution';
  END IF;
END
$assert$;
SELECT 'C610_DUPLICATE_INPUT_IDS_REJECTED_ZERO_MUTATION_PASS' AS evidence;

-- C613: reject malformed or excessive requested UUID arrays before signing.
SELECT c603_test.assert_rejected(
  'SELECT c608_test.request(NULL::uuid[],interval ''1 minute'')','D1006');
SELECT c603_test.assert_rejected(
  'SELECT c608_test.request(ARRAY[NULL::uuid],interval ''1 minute'')','D1006');
SELECT c603_test.assert_rejected(
  'SELECT c608_test.request(ARRAY[]::uuid[],interval ''1 minute'')','D1006');
SELECT c603_test.assert_rejected(
  'SELECT c608_test.request(pg_catalog.array_fill(''c6080000-0000-4000-8000-000000000016''::uuid,ARRAY[10001]),interval ''1 minute'')',
  'D1006');
SELECT 'C613_NULL_ARRAY_NULL_ELEMENT_EMPTY_AND_OVERSIZED_REQUESTS_REJECTED_PASS' AS evidence;

-- Missing and ineligible requested IDs cannot be silently omitted by the signer.
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000017','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000018','running',
  pg_catalog.clock_timestamp());
SELECT c603_test.assert_rejected(
  'SELECT c608_test.request(ARRAY[''c6080000-0000-4000-8000-000000000017'',''c6080000-0000-4000-8000-000000000099'']::uuid[],interval ''1 minute'')',
  'D1006');
SELECT c603_test.assert_rejected(
  'SELECT c608_test.request(ARRAY[''c6080000-0000-4000-8000-000000000017'',''c6080000-0000-4000-8000-000000000018'']::uuid[],interval ''1 minute'')',
  'D1006');
DO $assert$
BEGIN
  IF (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000017') IS DISTINCT FROM 'running'
    OR (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000018') IS DISTINCT FROM 'running' THEN
    RAISE EXCEPTION 'C610 missing/ineligible request rejection changed business state';
  END IF;
END
$assert$;
SELECT 'C610_MISSING_AND_INELIGIBLE_INPUTS_REJECTED_ZERO_MUTATION_PASS' AS evidence;

-- A valid signature containing duplicate target IDs is rejected by recovery.
SELECT c608_test.request(ARRAY[
  'c6080000-0000-4000-8000-000000000017'
]::uuid[],interval '1 minute') AS duplicate_base_auth \gset
SELECT c603_test.sign_recovery(jsonb_build_object(
  'staleAfter','00:01:00',
  'targets',jsonb_build_array(
    :'duplicate_base_auth'::jsonb->'request'->'targets'->0,
    :'duplicate_base_auth'::jsonb->'request'->'targets'->0
  )
)) AS duplicate_signed_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT c603_test.assert_rejected(format(
  'SELECT deedlight_execution_ledger.recover_stale_executions(%L::interval,%L::jsonb)',
  '1 minute',:'duplicate_signed_auth'),'D1006');
RESET SESSION AUTHORIZATION;
DO $assert$
BEGIN
  IF (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000017') IS DISTINCT FROM 'running' THEN
    RAISE EXCEPTION 'C610 duplicate signed target rejection mutated an execution';
  END IF;
END
$assert$;
SELECT 'C610_DUPLICATE_SIGNED_TARGETS_REJECTED_ZERO_MUTATION_PASS' AS evidence;

-- A valid signature containing descending IDs is rejected before any mutation.
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000019','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000020','reserved',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.request(ARRAY[
  'c6080000-0000-4000-8000-000000000019',
  'c6080000-0000-4000-8000-000000000020'
]::uuid[],interval '1 minute') AS unordered_base_auth \gset
SELECT c603_test.sign_recovery(jsonb_build_object(
  'staleAfter','00:01:00',
  'targets',jsonb_build_array(
    :'unordered_base_auth'::jsonb->'request'->'targets'->1,
    :'unordered_base_auth'::jsonb->'request'->'targets'->0
  )
)) AS unordered_signed_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT c603_test.assert_rejected(format(
  'SELECT deedlight_execution_ledger.recover_stale_executions(%L::interval,%L::jsonb)',
  '1 minute',:'unordered_signed_auth'),'D1006');
RESET SESSION AUTHORIZATION;
DO $assert$
BEGIN
  IF (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000019') IS DISTINCT FROM 'running'
    OR (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id='c6080000-0000-4000-8000-000000000020') IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'C610 unordered target rejection partially mutated the target set';
  END IF;
END
$assert$;
SELECT 'C610_UNORDERED_TARGET_IDS_REJECTED_ZERO_MUTATION_PASS' AS evidence;

-- C613: the runtime implementation must reject an empty signed target set.
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000023','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000024','reserved',
  pg_catalog.clock_timestamp()-interval '1 hour');
CREATE TEMP TABLE c613_business_before ON COMMIT PRESERVE ROWS AS
SELECT * FROM deedlight_execution_ledger.executions;
SELECT c603_test.sign_recovery(jsonb_build_object(
  'staleAfter','00:01:00','targets','[]'::jsonb
)) AS empty_targets_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT c608_test.assert_trust_failure(format(
  'SELECT deedlight_execution_ledger.recover_stale_executions(%L::interval,%L::jsonb)',
  '1 minute',:'empty_targets_auth'),'recovery_target_set_empty');
RESET SESSION AUTHORIZATION;
SELECT c608_test.assert_business_snapshot();
SELECT c608_test.assert_nonce_absent(:'empty_targets_auth'::jsonb);
SELECT 'C613_SIGNED_EMPTY_TARGETS_REJECTED_ZERO_MUTATION_NONCE_ROLLBACK_PASS' AS evidence;

-- SQL NULL and JSON null target arrays both fail closed in the runtime implementation.
SELECT c608_test.assert_trust_failure(
  'SELECT deedlight_execution_ledger.recover_stale_executions_targets_impl(NULL::jsonb,interval ''1 minute'')',
  'recovery_target_set_invalid');
SELECT c603_test.sign_recovery(jsonb_build_object(
  'staleAfter','00:01:00','targets',NULL::jsonb
)) AS null_targets_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT c608_test.assert_trust_failure(format(
  'SELECT deedlight_execution_ledger.recover_stale_executions(%L::interval,%L::jsonb)',
  '1 minute',:'null_targets_auth'),'recovery_target_set_invalid');
RESET SESSION AUTHORIZATION;
SELECT c608_test.assert_business_snapshot();
SELECT c608_test.assert_nonce_absent(:'null_targets_auth'::jsonb);
SELECT 'C613_NULL_TARGET_ARRAY_REJECTED_NONCE_ROLLBACK_PASS' AS evidence;

-- A JSON null element is not a valid signed target object.
SELECT c603_test.sign_recovery(jsonb_build_object(
  'staleAfter','00:01:00','targets',jsonb_build_array(NULL::jsonb)
)) AS null_element_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT c608_test.assert_trust_failure(format(
  'SELECT deedlight_execution_ledger.recover_stale_executions(%L::interval,%L::jsonb)',
  '1 minute',:'null_element_auth'),'recovery_target_shape_invalid');
RESET SESSION AUTHORIZATION;
SELECT c608_test.assert_business_snapshot();
SELECT c608_test.assert_nonce_absent(:'null_element_auth'::jsonb);
SELECT 'C613_NULL_TARGET_ELEMENT_REJECTED_NONCE_ROLLBACK_PASS' AS evidence;

-- Oversized signed arrays are rejected before inspecting or locking their elements.
SELECT c603_test.sign_recovery(jsonb_build_object(
  'staleAfter','00:01:00',
  'targets',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('oversized',n))
    FROM pg_catalog.generate_series(1,10001) AS generated(n))
)) AS oversized_targets_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT c608_test.assert_trust_failure(format(
  'SELECT deedlight_execution_ledger.recover_stale_executions(%L::interval,%L::jsonb)',
  '1 minute',:'oversized_targets_auth'),'recovery_target_set_too_large');
RESET SESSION AUTHORIZATION;
SELECT c608_test.assert_business_snapshot();
SELECT c608_test.assert_nonce_absent(:'oversized_targets_auth'::jsonb);
SELECT 'C613_OVERSIZED_TARGET_ARRAY_REJECTED_NONCE_ROLLBACK_PASS' AS evidence;

-- Dedicated targets for the later-target-change-while-earlier-lock-is-held race.
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000021','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000022','reserved',
  pg_catalog.clock_timestamp()-interval '1 hour');

-- Keep stale rows for deterministic multi-session races.
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000009','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000010','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000011','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT 'C608_SEQUENTIAL_RECOVERY_AUTHORIZATION_TESTS_PASS' AS evidence;
