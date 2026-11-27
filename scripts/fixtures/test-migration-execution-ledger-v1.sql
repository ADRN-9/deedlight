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
SELECT deedlight_execution_ledger.approve_execution(
  'c5700000-0000-4000-8000-000000000001',
  'c5700000-0000-4000-8000-000000000011',
  'c5700000-0000-4000-8000-000000000021',
  '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
);
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
RESET ROLE;
INSERT INTO deedlight_execution_ledger.test_effects(effect_value) VALUES ('fixture migration effect');
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
  IF v_status <> 'succeeded' OR v_pre->'rows'->0->>'effect_count' <> '0'
    OR v_post->'rows'->0->>'effect_count' <> '1'
    OR v_pre_observer <> 'deedlight_ledger_observer' OR v_post_observer <> 'deedlight_ledger_observer'
    OR v_pre->'databaseIdentity' <> v_post->'databaseIdentity' THEN
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

-- Duplicate record ID with a different execution ID is rejected at approval.
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

-- A reservation abandoned before execution becomes interrupted, never silently reusable.
SELECT deedlight_execution_ledger.approve_execution(
  'c5700000-0000-4000-8000-000000000004',
  'c5700000-0000-4000-8000-000000000014',
  'c5700000-0000-4000-8000-000000000024',
  '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
);
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

-- A running process that disappears has an ambiguous outcome and becomes unknown.
SELECT deedlight_execution_ledger.approve_execution(
  'c5700000-0000-4000-8000-000000000005',
  'c5700000-0000-4000-8000-000000000015',
  'c5700000-0000-4000-8000-000000000025',
  '{"path":"supabase/migrations/test.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
);
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

-- Runner and approver roles cannot invoke the independent verifier operation.
SET ROLE deedlight_ledger_runner;
DO $assert$
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.record_verification(
      'c5700000-0000-4000-8000-000000000021','verified','{}'::jsonb
    );
    RAISE EXCEPTION 'runner unexpectedly acquired verifier authority';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'runner unexpectedly acquired verifier authority' THEN RAISE; END IF;
    IF SQLERRM <> 'independent verifier authority required' THEN RAISE; END IF;
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
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'approver unexpectedly acquired verifier authority' THEN RAISE; END IF;
    IF SQLERRM <> 'independent verifier authority required' THEN RAISE; END IF;
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

SELECT 'C577 disposable PostgreSQL ledger integration: PASS' AS result;
