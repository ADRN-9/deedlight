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

CREATE OR REPLACE FUNCTION c608_test.request(p_execution_ids uuid[],p_stale_after interval)
RETURNS jsonb LANGUAGE sql AS $fn$
  SELECT c603_test.sign_recovery(pg_catalog.jsonb_build_object(
    'staleAfter',p_stale_after::text,
    'targets',(SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'executionId',execution.execution_id,
      'expectedStatus',execution.status,
      'expectedSourceIdentity',execution.source_identity,
      'expectedHeartbeatAt',execution.heartbeat_at,
      'expectedRowVersion',execution.c603_row_version)
      ORDER BY execution.execution_id),'[]'::jsonb)
      FROM deedlight_execution_ledger.executions AS execution
      WHERE execution.execution_id=ANY(p_execution_ids)
        AND execution.status IN ('reserved','running')
        AND execution.heartbeat_at < pg_catalog.clock_timestamp()-p_stale_after)
  ))
$fn$;
REVOKE ALL ON FUNCTION c608_test.seed_execution(uuid,text,timestamptz),
  c608_test.request(uuid[],interval) FROM PUBLIC,
  deedlight_ledger_approver,deedlight_ledger_runner,deedlight_ledger_observer,
  deedlight_ledger_recovery,deedlight_ledger_verifier;

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

-- Keep stale rows for deterministic multi-session races.
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000009','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000010','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT c608_test.seed_execution('c6080000-0000-4000-8000-000000000011','running',
  pg_catalog.clock_timestamp()-interval '1 hour');
SELECT 'C608_SEQUENTIAL_RECOVERY_AUTHORIZATION_TESTS_PASS' AS evidence;
