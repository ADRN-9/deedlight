\set ON_ERROR_STOP on

-- Disposable SQL privilege-boundary regression only. This does not emulate an
-- external verifier or prove Production gateway enforcement.
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='deedlight_ledger_untrusted') THEN
    CREATE ROLE deedlight_ledger_untrusted NOLOGIN NOINHERIT;
  END IF;
END
$roles$;

-- Permit name resolution while deliberately granting no function EXECUTE.
GRANT USAGE ON SCHEMA deedlight_execution_ledger TO deedlight_ledger_untrusted;

CREATE TEMP TABLE c600_before AS
SELECT
  (SELECT count(*) FROM deedlight_execution_ledger.approvals) AS approvals,
  (SELECT count(*) FROM deedlight_execution_ledger.executions) AS executions,
  (SELECT count(*) FROM deedlight_execution_ledger.snapshots) AS snapshots,
  (SELECT count(*) FROM deedlight_execution_ledger.execution_commit_markers) AS markers,
  (SELECT count(*) FROM deedlight_execution_ledger.verification_events) AS verifications;

DO $privilege_assert$
DECLARE
  v_proc text;
  v_procedures text[] := ARRAY[
    'deedlight_execution_ledger.approve_execution(uuid,uuid,uuid,jsonb)',
    'deedlight_execution_ledger.reserve_execution(uuid,uuid,uuid,jsonb)',
    'deedlight_execution_ledger.record_effect_commit_marker(uuid,jsonb)',
    'deedlight_execution_ledger.capture_snapshot(uuid,text,text)',
    'deedlight_execution_ledger.start_execution(uuid)',
    'deedlight_execution_ledger.heartbeat_execution(uuid)',
    'deedlight_execution_ledger.finalize_execution(uuid,text,jsonb)',
    'deedlight_execution_ledger.recover_stale_executions(interval)',
    'deedlight_execution_ledger.record_verification(uuid,text,jsonb)'
  ];
BEGIN
  FOREACH v_proc IN ARRAY v_procedures LOOP
    IF pg_catalog.to_regprocedure(v_proc) IS NULL
      OR pg_catalog.has_function_privilege(
        'deedlight_ledger_untrusted', pg_catalog.to_regprocedure(v_proc), 'EXECUTE'
      ) THEN
      RAISE EXCEPTION 'C600 direct invocation privilege unexpectedly granted: %', v_proc;
    END IF;
  END LOOP;
END
$privilege_assert$;

SET ROLE deedlight_ledger_untrusted;

DO $direct_call_assert$
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.approve_execution(
      'c6000000-0000-4000-8000-000000000001',
      'c6000000-0000-4000-8000-000000000011',
      'c6000000-0000-4000-8000-000000000021',
      '{"path":"supabase/migrations/c600-unauthorized.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
    );
    RAISE EXCEPTION 'C600 unauthorized approve_execution unexpectedly executed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM deedlight_execution_ledger.reserve_execution(
      'c6000000-0000-4000-8000-000000000001',
      'c6000000-0000-4000-8000-000000000011',
      'c6000000-0000-4000-8000-000000000021',
      '{"path":"supabase/migrations/c600-unauthorized.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
    );
    RAISE EXCEPTION 'C600 unauthorized reserve_execution unexpectedly executed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM deedlight_execution_ledger.record_effect_commit_marker(
      'c6000000-0000-4000-8000-000000000021',
      '{"path":"supabase/migrations/c600-unauthorized.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
    );
    RAISE EXCEPTION 'C600 unauthorized record_effect_commit_marker unexpectedly executed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM deedlight_execution_ledger.capture_snapshot(
      'c6000000-0000-4000-8000-000000000021','pre','test_effects_v1'
    );
    RAISE EXCEPTION 'C600 unauthorized capture_snapshot unexpectedly executed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM deedlight_execution_ledger.start_execution('c6000000-0000-4000-8000-000000000021');
    RAISE EXCEPTION 'C600 unauthorized start_execution unexpectedly executed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM deedlight_execution_ledger.heartbeat_execution('c6000000-0000-4000-8000-000000000021');
    RAISE EXCEPTION 'C600 unauthorized heartbeat_execution unexpectedly executed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM deedlight_execution_ledger.finalize_execution(
      'c6000000-0000-4000-8000-000000000021','succeeded','{"result":"unauthorized"}'::jsonb
    );
    RAISE EXCEPTION 'C600 unauthorized finalize_execution unexpectedly executed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM deedlight_execution_ledger.recover_stale_executions(interval '1 minute');
    RAISE EXCEPTION 'C600 unauthorized recover_stale_executions unexpectedly executed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM deedlight_execution_ledger.record_verification(
      'c6000000-0000-4000-8000-000000000021','verified','{"result":"unauthorized"}'::jsonb
    );
    RAISE EXCEPTION 'C600 unauthorized record_verification unexpectedly executed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$direct_call_assert$;

RESET ROLE;

DO $side_effect_assert$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM c600_before b
    WHERE b.approvals = (SELECT count(*) FROM deedlight_execution_ledger.approvals)
      AND b.executions = (SELECT count(*) FROM deedlight_execution_ledger.executions)
      AND b.snapshots = (SELECT count(*) FROM deedlight_execution_ledger.snapshots)
      AND b.markers = (SELECT count(*) FROM deedlight_execution_ledger.execution_commit_markers)
      AND b.verifications = (SELECT count(*) FROM deedlight_execution_ledger.verification_events)
  ) THEN
    RAISE EXCEPTION 'C600 unauthorized direct invocation changed ledger state';
  END IF;
END
$side_effect_assert$;

SELECT 'C600_NINE_RPC_UNAUTHORIZED_DIRECT_CALLS_DENIED_ZERO_SIDE_EFFECTS' AS evidence;
