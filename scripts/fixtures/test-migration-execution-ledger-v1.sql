\set ON_ERROR_STOP on

-- Verify identity is derived from the connected PostgreSQL server, not request input.
DO $identity_assert$
DECLARE v_identity jsonb;
BEGIN
  v_identity := deedlight_execution_ledger.current_database_identity();
  IF v_identity->>'databaseName' <> current_database()
    OR (v_identity->>'databaseOid')::oid <>
      (SELECT oid FROM pg_catalog.pg_database WHERE datname = current_database())
    OR v_identity->>'systemIdentifier' <>
      (SELECT system_identifier::text FROM pg_catalog.pg_control_system()) THEN
    RAISE EXCEPTION 'database identity was not derived from the connected server';
  END IF;
END
$identity_assert$;

-- A reservation rolled back by its caller must leave neither a ledger row nor a consumed approval.
SET ROLE deedlight_ledger_approver;
SELECT deedlight_execution_ledger.approve_execution(
  'c5700000-0000-4000-8000-000000000001',
  'c5700000-0000-4000-8000-000000000011',
  'c5700000-0000-4000-8000-000000000021',
  '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
);
RESET ROLE;
BEGIN;
SET LOCAL ROLE deedlight_ledger_runner;
SELECT deedlight_execution_ledger.reserve_execution(
  'c5700000-0000-4000-8000-000000000001',
  'c5700000-0000-4000-8000-000000000011',
  'c5700000-0000-4000-8000-000000000021',
  '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
);
ROLLBACK;
DO $assert$
BEGIN
  IF EXISTS (SELECT 1 FROM deedlight_execution_ledger.executions
    WHERE execution_id = 'c5700000-0000-4000-8000-000000000021')
    OR (SELECT consumed_at FROM deedlight_execution_ledger.approvals
      WHERE approval_id = 'c5700000-0000-4000-8000-000000000001') IS NOT NULL THEN
    RAISE EXCEPTION 'rollback did not atomically restore reservation and approval consumption';
  END IF;
END
$assert$;

-- Normal successful execution with independently collected server-side snapshots.
SET ROLE deedlight_ledger_runner;
SELECT deedlight_execution_ledger.reserve_execution(
  'c5700000-0000-4000-8000-000000000001',
  'c5700000-0000-4000-8000-000000000011',
  'c5700000-0000-4000-8000-000000000021',
  '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
);
RESET ROLE;
SET ROLE deedlight_ledger_observer;
SELECT deedlight_execution_ledger.capture_snapshot(
  'c5700000-0000-4000-8000-000000000021','pre','test_effects_v1'
);
RESET ROLE;
SET ROLE deedlight_ledger_runner;
SELECT deedlight_execution_ledger.start_execution('c5700000-0000-4000-8000-000000000021');
SELECT deedlight_execution_ledger.heartbeat_execution('c5700000-0000-4000-8000-000000000021');
RESET ROLE;
SET ROLE deedlight_ledger_runner;
BEGIN;
INSERT INTO deedlight_execution_ledger.test_effects(effect_value) VALUES ('fixture migration effect');
SELECT deedlight_execution_ledger.record_effect_commit_marker(
  'c5700000-0000-4000-8000-000000000021',
  '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
);
COMMIT;
RESET ROLE;
SET ROLE deedlight_ledger_observer;
SELECT deedlight_execution_ledger.capture_snapshot(
  'c5700000-0000-4000-8000-000000000021','post','test_effects_v1'
);
RESET ROLE;
SET ROLE deedlight_ledger_runner;
SELECT deedlight_execution_ledger.finalize_execution(
  'c5700000-0000-4000-8000-000000000021','succeeded','{"result":"fixture-complete"}'::jsonb
);
RESET ROLE;

DO $assert$
DECLARE v_pre jsonb; v_post jsonb; v_status text; v_pre_observer name; v_post_observer name;
        v_pre_query text; v_post_query text; v_pre_query_digest text; v_post_query_digest text;
        v_pre_bundle_digest text; v_post_bundle_digest text;
BEGIN
  SELECT status INTO STRICT v_status FROM deedlight_execution_ledger.executions
    WHERE execution_id = 'c5700000-0000-4000-8000-000000000021';
  SELECT snapshot INTO STRICT v_pre FROM deedlight_execution_ledger.snapshots
    WHERE execution_id = 'c5700000-0000-4000-8000-000000000021' AND phase = 'pre';
  SELECT snapshot INTO STRICT v_post FROM deedlight_execution_ledger.snapshots
    WHERE execution_id = 'c5700000-0000-4000-8000-000000000021' AND phase = 'post';
  SELECT observer_identity INTO STRICT v_pre_observer FROM deedlight_execution_ledger.snapshots
    WHERE execution_id = 'c5700000-0000-4000-8000-000000000021' AND phase = 'pre';
  SELECT observer_identity INTO STRICT v_post_observer FROM deedlight_execution_ledger.snapshots
    WHERE execution_id = 'c5700000-0000-4000-8000-000000000021' AND phase = 'post';
  SELECT query_id, query_sha256, query_bundle_digest
    INTO STRICT v_pre_query, v_pre_query_digest, v_pre_bundle_digest
    FROM deedlight_execution_ledger.snapshots
    WHERE execution_id = 'c5700000-0000-4000-8000-000000000021' AND phase = 'pre';
  SELECT query_id, query_sha256, query_bundle_digest
    INTO STRICT v_post_query, v_post_query_digest, v_post_bundle_digest
    FROM deedlight_execution_ledger.snapshots
    WHERE execution_id = 'c5700000-0000-4000-8000-000000000021' AND phase = 'post';
  IF v_status <> 'succeeded' OR v_pre->'rows'->0->>'effect_count' <> '0'
    OR v_post->'rows'->0->>'effect_count' <> '1'
    OR v_pre_observer <> 'deedlight_ledger_observer' OR v_post_observer <> 'deedlight_ledger_observer'
    OR v_pre->'databaseIdentity' <> v_post->'databaseIdentity'
    OR v_pre_query <> v_post_query OR v_pre_query_digest <> v_post_query_digest
    OR v_pre_bundle_digest <> v_post_bundle_digest
    OR v_pre->>'querySha256' <> v_post->>'querySha256'
    OR v_pre->>'queryBundleDigest' <> v_post->>'queryBundleDigest' THEN
    RAISE EXCEPTION 'successful execution or independent pre/post snapshots invalid';
  END IF;
END
$assert$;

-- Separate verifier role records a verdict; it cannot mutate execution status.
SET ROLE deedlight_ledger_verifier;
SELECT deedlight_execution_ledger.record_verification(
  'c5700000-0000-4000-8000-000000000021','verified','{"fixture":"synthetic; not migration acceptance"}'::jsonb
);
RESET ROLE;

-- Partial effects are recorded as partial, never upgraded to success by the verifier.
SET ROLE deedlight_ledger_approver;
SELECT deedlight_execution_ledger.approve_execution(
  'c5700000-0000-4000-8000-000000000006',
  'c5700000-0000-4000-8000-000000000016',
  'c5700000-0000-4000-8000-000000000026',
  '{"path":"supabase/migrations/test-partial.sql","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}'::jsonb
);
RESET ROLE;
SET ROLE deedlight_ledger_runner;
SELECT deedlight_execution_ledger.reserve_execution(
  'c5700000-0000-4000-8000-000000000006',
  'c5700000-0000-4000-8000-000000000016',
  'c5700000-0000-4000-8000-000000000026',
  '{"path":"supabase/migrations/test-partial.sql","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}'::jsonb
);
RESET ROLE;
SET ROLE deedlight_ledger_observer;
SELECT deedlight_execution_ledger.capture_snapshot(
  'c5700000-0000-4000-8000-000000000026','pre','test_effects_v1'
);
RESET ROLE;
SET ROLE deedlight_ledger_runner;
SELECT deedlight_execution_ledger.start_execution('c5700000-0000-4000-8000-000000000026');
RESET ROLE;
SET ROLE deedlight_ledger_runner;
BEGIN;
INSERT INTO deedlight_execution_ledger.test_effects(effect_value) VALUES ('partial fixture effect');
SELECT deedlight_execution_ledger.record_effect_commit_marker(
  'c5700000-0000-4000-8000-000000000026',
  '{"path":"supabase/migrations/test-partial.sql","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}'::jsonb
);
COMMIT;
RESET ROLE;
SET ROLE deedlight_ledger_observer;
SELECT deedlight_execution_ledger.capture_snapshot(
  'c5700000-0000-4000-8000-000000000026','post','test_effects_v1'
);
RESET ROLE;
SET ROLE deedlight_ledger_runner;
SELECT deedlight_execution_ledger.finalize_execution(
  'c5700000-0000-4000-8000-000000000026','partial','{"reason":"fixture interrupted after a committed effect"}'::jsonb
);
RESET ROLE;
DO $assert$
BEGIN
  IF (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id = 'c5700000-0000-4000-8000-000000000026') <> 'partial' THEN
    RAISE EXCEPTION 'partial execution was not preserved as partial';
  END IF;
END
$assert$;

-- Completed execution and consumed approval are permanently replay-protected.
SET ROLE deedlight_ledger_runner;
DO $assert$
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.reserve_execution(
      'c5700000-0000-4000-8000-000000000001',
      'c5700000-0000-4000-8000-000000000011',
      'c5700000-0000-4000-8000-000000000021',
      '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
    );
    RAISE EXCEPTION 'replay unexpectedly accepted';
  EXCEPTION WHEN unique_violation OR raise_exception THEN
    IF SQLERRM = 'replay unexpectedly accepted' THEN RAISE; END IF;
  END;
END
$assert$;
RESET ROLE;

-- Duplicate execution ID with a different record ID is rejected at approval.
SET ROLE deedlight_ledger_approver;
DO $assert$
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.approve_execution(
      'c5700000-0000-4000-8000-000000000002',
      'c5700000-0000-4000-8000-000000000012',
      'c5700000-0000-4000-8000-000000000021',
      '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
    );
    RAISE EXCEPTION 'duplicate execution identity unexpectedly approved';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END
$assert$;
RESET ROLE;

-- Duplicate record ID with a different execution ID is rejected at approval.
SET ROLE deedlight_ledger_approver;
DO $assert$
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.approve_execution(
      'c5700000-0000-4000-8000-000000000003',
      'c5700000-0000-4000-8000-000000000011',
      'c5700000-0000-4000-8000-000000000023',
      '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
    );
    RAISE EXCEPTION 'duplicate record identity unexpectedly approved';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END
$assert$;
RESET ROLE;

-- A reservation abandoned before execution becomes interrupted, never silently reusable.
SET ROLE deedlight_ledger_approver;
SELECT deedlight_execution_ledger.approve_execution(
  'c5700000-0000-4000-8000-000000000004',
  'c5700000-0000-4000-8000-000000000014',
  'c5700000-0000-4000-8000-000000000024',
  '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
);
RESET ROLE;
SET ROLE deedlight_ledger_runner;
SELECT deedlight_execution_ledger.reserve_execution(
  'c5700000-0000-4000-8000-000000000004',
  'c5700000-0000-4000-8000-000000000014',
  'c5700000-0000-4000-8000-000000000024',
  '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
);
RESET ROLE;
SELECT pg_catalog.pg_sleep(0.02);
SET ROLE deedlight_ledger_recovery;
SELECT deedlight_execution_ledger.recover_stale_executions(interval '1 microsecond');
RESET ROLE;
DO $assert$
BEGIN
  IF (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id = 'c5700000-0000-4000-8000-000000000024') <> 'interrupted' THEN
    RAISE EXCEPTION 'reserved crash did not become interrupted';
  END IF;
END
$assert$;

-- An interrupted reservation remains non-replayable.
SET ROLE deedlight_ledger_runner;
DO $assert$
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.reserve_execution(
      'c5700000-0000-4000-8000-000000000004',
      'c5700000-0000-4000-8000-000000000014',
      'c5700000-0000-4000-8000-000000000024',
      '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
    );
    RAISE EXCEPTION 'interrupted execution replay unexpectedly accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'interrupted execution replay unexpectedly accepted' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'approval is missing, consumed, or does not bind%' THEN RAISE; END IF;
  END;
END
$assert$;
RESET ROLE;

-- A running process that disappears has an ambiguous outcome and becomes unknown.
SET ROLE deedlight_ledger_approver;
SELECT deedlight_execution_ledger.approve_execution(
  'c5700000-0000-4000-8000-000000000005',
  'c5700000-0000-4000-8000-000000000015',
  'c5700000-0000-4000-8000-000000000025',
  '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
);
RESET ROLE;
SET ROLE deedlight_ledger_runner;
SELECT deedlight_execution_ledger.reserve_execution(
  'c5700000-0000-4000-8000-000000000005',
  'c5700000-0000-4000-8000-000000000015',
  'c5700000-0000-4000-8000-000000000025',
  '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
);
RESET ROLE;
SET ROLE deedlight_ledger_observer;
SELECT deedlight_execution_ledger.capture_snapshot(
  'c5700000-0000-4000-8000-000000000025','pre','test_effects_v1'
);
RESET ROLE;
SET ROLE deedlight_ledger_runner;
SELECT deedlight_execution_ledger.start_execution('c5700000-0000-4000-8000-000000000025');
RESET ROLE;
SELECT pg_catalog.pg_sleep(0.02);
SET ROLE deedlight_ledger_recovery;
SELECT deedlight_execution_ledger.recover_stale_executions(interval '1 microsecond');
RESET ROLE;
DO $assert$
BEGIN
  IF (SELECT status FROM deedlight_execution_ledger.executions
      WHERE execution_id = 'c5700000-0000-4000-8000-000000000025') <> 'unknown' THEN
    RAISE EXCEPTION 'running crash did not become unknown';
  END IF;
END
$assert$;

-- Runner and approver roles cannot invoke the verifier function at the SQL privilege boundary.
SET ROLE deedlight_ledger_runner;
DO $assert$
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.record_verification(
      'c5700000-0000-4000-8000-000000000021','verified','{}'::jsonb
    );
    RAISE EXCEPTION 'runner unexpectedly acquired verifier authority';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$assert$;
RESET ROLE;
SET ROLE deedlight_ledger_approver;
DO $assert$
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.record_verification(
      'c5700000-0000-4000-8000-000000000021','verified','{}'::jsonb
    );
    RAISE EXCEPTION 'approver unexpectedly acquired verifier authority';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$assert$;
RESET ROLE;

-- Terminal outcomes cannot be rewritten, including by table owner.
DO $assert$
BEGIN
  BEGIN
    UPDATE deedlight_execution_ledger.executions SET status = 'failed'
    WHERE execution_id = 'c5700000-0000-4000-8000-000000000021';
    RAISE EXCEPTION 'terminal mutation unexpectedly accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'terminal mutation unexpectedly accepted' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'terminal execution outcomes are immutable%' THEN RAISE; END IF;
  END;
END
$assert$;

-- Direct ledger reads and writes are unavailable to the operational roles.
SET ROLE deedlight_ledger_runner;
DO $assert$
BEGIN
  BEGIN
    PERFORM 1 FROM deedlight_execution_ledger.executions;
    RAISE EXCEPTION 'runner unexpectedly read ledger table directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$assert$;
DO $assert$
BEGIN
  BEGIN
    INSERT INTO deedlight_execution_ledger.executions
      (system_identifier, database_oid, database_name, record_id, execution_id,
       approval_id, source_identity, status, approver_identity)
    VALUES ('forged', '1'::oid, current_database(), gen_random_uuid(), gen_random_uuid(),
      gen_random_uuid(), '{}'::jsonb, 'reserved', 'forged');
    RAISE EXCEPTION 'runner unexpectedly inserted directly into ledger';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$assert$;
RESET ROLE;

-- The observer is read-only: no direct fixture mutation or ledger table access.
SET ROLE deedlight_ledger_observer;
DO $assert$
BEGIN
  BEGIN
    INSERT INTO deedlight_execution_ledger.test_effects(effect_value) VALUES ('unauthorized');
    RAISE EXCEPTION 'observer unexpectedly mutated fixture';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$assert$;
RESET ROLE;

-- Forged database identity is not accepted as a function parameter and direct ledger writes are revoked.
SET ROLE deedlight_ledger_runner;
DO $assert$
BEGIN
  BEGIN
    EXECUTE 'SELECT deedlight_execution_ledger.reserve_execution(' ||
      quote_literal('c5700000-0000-4000-8000-000000000001') || ',' ||
      quote_literal('c5700000-0000-4000-8000-000000000011') || ',' ||
      quote_literal('c5700000-0000-4000-8000-000000000021') || ',' ||
      quote_literal('{"path":"x","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}') ||
      ', ''{"databaseName":"forged"}''::jsonb)';
    RAISE EXCEPTION 'caller-supplied database identity unexpectedly accepted';
  EXCEPTION WHEN undefined_function THEN NULL;
  END;
END
$assert$;
RESET ROLE;

-- Finalization must reject two independently registered but different observation queries.
SET ROLE deedlight_ledger_approver;
SELECT deedlight_execution_ledger.approve_execution(
  'c5700000-0000-4000-8000-000000000008',
  'c5700000-0000-4000-8000-000000000018',
  'c5700000-0000-4000-8000-000000000028',
  '{"path":"supabase/migrations/test-query-mismatch.sql","sha256":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}'::jsonb
);
RESET ROLE;
SET ROLE deedlight_ledger_runner;
SELECT deedlight_execution_ledger.reserve_execution(
  'c5700000-0000-4000-8000-000000000008',
  'c5700000-0000-4000-8000-000000000018',
  'c5700000-0000-4000-8000-000000000028',
  '{"path":"supabase/migrations/test-query-mismatch.sql","sha256":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}'::jsonb
);
RESET ROLE;
SET ROLE deedlight_ledger_observer;
SELECT deedlight_execution_ledger.capture_snapshot(
  'c5700000-0000-4000-8000-000000000028','pre','test_effects_v1'
);
RESET ROLE;
SET ROLE deedlight_ledger_runner;
SELECT deedlight_execution_ledger.start_execution('c5700000-0000-4000-8000-000000000028');
BEGIN;
INSERT INTO deedlight_execution_ledger.test_effects(effect_value)
VALUES ('snapshot mismatch fixture effect');
SELECT deedlight_execution_ledger.record_effect_commit_marker(
  'c5700000-0000-4000-8000-000000000028',
  '{"path":"supabase/migrations/test-query-mismatch.sql","sha256":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}'::jsonb
);
COMMIT;
RESET ROLE;
SET ROLE deedlight_ledger_observer;
SELECT deedlight_execution_ledger.capture_snapshot(
  'c5700000-0000-4000-8000-000000000028','post','test_effects_v2'
);
RESET ROLE;
SET ROLE deedlight_ledger_runner;
DO $assert$
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.finalize_execution(
      'c5700000-0000-4000-8000-000000000028','succeeded','{"result":"must-not-finalize"}'::jsonb
    );
    RAISE EXCEPTION 'finalization accepted different pre/post observation queries';
  EXCEPTION WHEN SQLSTATE 'D1004' THEN
    IF SQLERRM = 'finalization accepted different pre/post observation queries' THEN RAISE; END IF;
    
  END;
END
$assert$;
RESET ROLE;
DO $assert$
DECLARE v_pre_bundle text; v_post_bundle text; v_pre_query text; v_post_query text;
BEGIN
  SELECT query_bundle_digest, query_sha256 INTO STRICT v_pre_bundle, v_pre_query
  FROM deedlight_execution_ledger.snapshots
  WHERE execution_id = 'c5700000-0000-4000-8000-000000000028' AND phase = 'pre';
  SELECT query_bundle_digest, query_sha256 INTO STRICT v_post_bundle, v_post_query
  FROM deedlight_execution_ledger.snapshots
  WHERE execution_id = 'c5700000-0000-4000-8000-000000000028' AND phase = 'post';
  IF v_pre_bundle = v_post_bundle OR v_pre_query = v_post_query THEN
    RAISE EXCEPTION 'query mismatch fixture did not bind distinct registered queries and bundle digests';
  END IF;
END
$assert$;

-- Leave a committed RUNNING reservation for the shell harness to crash during a migration transaction.
SET ROLE deedlight_ledger_approver;
SELECT deedlight_execution_ledger.approve_execution(
  'c5700000-0000-4000-8000-000000000007',
  'c5700000-0000-4000-8000-000000000017',
  'c5700000-0000-4000-8000-000000000027',
  '{"path":"supabase/migrations/test-crash.sql","sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}'::jsonb
);
RESET ROLE;
SET ROLE deedlight_ledger_runner;
SELECT deedlight_execution_ledger.reserve_execution(
  'c5700000-0000-4000-8000-000000000007',
  'c5700000-0000-4000-8000-000000000017',
  'c5700000-0000-4000-8000-000000000027',
  '{"path":"supabase/migrations/test-crash.sql","sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}'::jsonb
);
RESET ROLE;
SET ROLE deedlight_ledger_observer;
SELECT deedlight_execution_ledger.capture_snapshot(
  'c5700000-0000-4000-8000-000000000027','pre','test_effects_v1'
);
RESET ROLE;
SET ROLE deedlight_ledger_runner;
SELECT deedlight_execution_ledger.start_execution('c5700000-0000-4000-8000-000000000027');
RESET ROLE;
SET ROLE deedlight_ledger_observer;
DO $assert$
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.capture_snapshot(
      'c5700000-0000-4000-8000-000000000027','post','test_effects_v1'
    );
    RAISE EXCEPTION 'post-snapshot accepted without committed migration marker';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'post-snapshot accepted without committed migration marker' THEN RAISE; END IF;
    IF SQLERRM <> 'post-snapshot requires a committed effect marker from the active runner transaction' THEN RAISE; END IF;
  END;
END
$assert$;
RESET ROLE;

SELECT 'C578_SNAPSHOT_MATCHING_QUERY_PASS' AS evidence;
SELECT 'C578_SNAPSHOT_MISMATCH_REJECTED' AS evidence;
SELECT 'C578_SQL_FIXTURE_SETUP_PASS; crash-recovery shell harness still pending' AS result;
