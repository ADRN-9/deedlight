\set ON_ERROR_STOP on
DO $assert$
BEGIN
  IF (SELECT count(*) FROM deedlight_execution_ledger.query_bundle_manifests) <> 2 THEN
    RAISE EXCEPTION 'C585 bundle manifest cardinality mismatch';
  END IF;
  IF EXISTS (SELECT 1 FROM deedlight_execution_ledger.query_bundle_manifests
    WHERE manifest_sha256 <> deedlight_execution_ledger.canonical_query_bundle_digest(manifest)
       OR member_count <> jsonb_array_length(manifest)) THEN
    RAISE EXCEPTION 'C585 canonical manifest digest mismatch';
  END IF;
  BEGIN
    UPDATE deedlight_execution_ledger.query_bundle_manifests SET member_count=99
      WHERE bundle_id='test_effects_bundle_v1';
    RAISE EXCEPTION 'C585 manifest UPDATE unexpectedly succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='C585 manifest UPDATE unexpectedly succeeded' THEN RAISE; END IF;
    IF SQLERRM<>'ledger evidence is append-only' THEN RAISE; END IF;
  END;
  BEGIN
    DELETE FROM deedlight_execution_ledger.query_bundle_manifests WHERE bundle_id='test_effects_bundle_v1';
    RAISE EXCEPTION 'C585 manifest DELETE unexpectedly succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='C585 manifest DELETE unexpectedly succeeded' THEN RAISE; END IF;
    IF SQLERRM<>'ledger evidence is append-only' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE deedlight_execution_ledger.observation_queries SET description='forged'
      WHERE query_id='test_effects_v1';
    RAISE EXCEPTION 'C585 query UPDATE unexpectedly succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='C585 query UPDATE unexpectedly succeeded' THEN RAISE; END IF;
    IF SQLERRM<>'ledger evidence is append-only' THEN RAISE; END IF;
  END;
  BEGIN
    DELETE FROM deedlight_execution_ledger.observation_queries WHERE query_id='test_effects_v1';
    RAISE EXCEPTION 'C585 query DELETE unexpectedly succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='C585 query DELETE unexpectedly succeeded' THEN RAISE; END IF;
    IF SQLERRM<>'ledger evidence is append-only' THEN RAISE; END IF;
  END;
END
$assert$;

-- A real bundle reference with a substituted SQL digest must fail at observation time.
INSERT INTO deedlight_execution_ledger.observation_queries
  (query_id,query_sql,description,query_sha256,query_bundle_id,query_bundle_digest)
SELECT 'test_effects_forged_sql',query_sql,'negative SQL digest test',repeat('f',64),
  query_bundle_id,query_bundle_digest
FROM deedlight_execution_ledger.observation_queries WHERE query_id='test_effects_v1';
DO $assert$
BEGIN
  BEGIN
    INSERT INTO deedlight_execution_ledger.observation_queries
      (query_id,query_sql,description,query_sha256,query_bundle_id,query_bundle_digest)
    SELECT 'test_effects_forged_bundle',query_sql,'negative bundle digest test',query_sha256,
      query_bundle_id,repeat('e',64)
    FROM deedlight_execution_ledger.observation_queries WHERE query_id='test_effects_v1';
    RAISE EXCEPTION 'C585 bundle digest substitution unexpectedly succeeded';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
END
$assert$;
SET ROLE deedlight_ledger_observer;
DO $assert$
DECLARE v_detail text;
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.capture_snapshot(
      'c5700000-0000-4000-8000-000000000028','post','test_effects_forged_sql');
    RAISE EXCEPTION 'C585 SQL digest substitution unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE 'D1004' THEN
    GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
    IF v_detail NOT LIKE '%registered_sql_digest_mismatch%' THEN RAISE; END IF;
  END;
END
$assert$;
RESET ROLE;

-- Reservation must reject a valid but substituted source identity.
SET ROLE deedlight_ledger_approver;
SELECT deedlight_execution_ledger.approve_execution(
  'c5850000-0000-4000-8000-000000000004',
  'c5850000-0000-4000-8000-000000000014',
  'c5850000-0000-4000-8000-000000000024',
  '{"path":"supabase/migrations/c585-approved.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb
);
RESET ROLE;
SET ROLE deedlight_ledger_runner;
DO $assert$
DECLARE v_detail text;
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.reserve_execution(
      'c5850000-0000-4000-8000-000000000004',
      'c5850000-0000-4000-8000-000000000014',
      'c5850000-0000-4000-8000-000000000024',
      '{"path":"supabase/migrations/c585-substituted.sql","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'::jsonb
    );
    RAISE EXCEPTION 'C585 reservation source substitution unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE 'D1002' THEN
    GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
    IF v_detail NOT LIKE '%reservation_source_identity_substitution%' THEN RAISE; END IF;
  END;
END
$assert$;
RESET ROLE;

-- Marker source identity cannot be substituted after reservation.
SET ROLE deedlight_ledger_runner;
DO $assert$
DECLARE v_detail text;
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.record_effect_commit_marker(
      'c5700000-0000-4000-8000-000000000028',
      '{"path":"supabase/migrations/substituted.sql","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'::jsonb);
    RAISE EXCEPTION 'C585 marker source substitution unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE 'D1002' THEN
    GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
    IF v_detail NOT LIKE '%marker_source_identity_substitution%' THEN RAISE; END IF;
  END;
END
$assert$;
RESET ROLE;

-- Both absent pre and absent post are distinct machine-readable finalization failures.
DO $seed$
DECLARE v_identity deedlight_execution_ledger.database_identity%ROWTYPE;
        v_source jsonb := '{"path":"supabase/migrations/c585-finalize.sql","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}'::jsonb;
BEGIN
  SELECT * INTO STRICT v_identity FROM deedlight_execution_ledger.database_identity WHERE singleton;
  INSERT INTO deedlight_execution_ledger.approvals
    (approval_id,system_identifier,database_oid,database_name,record_id,execution_id,source_identity,approver_identity,consumed_at)
  VALUES
    ('c5850000-0000-4000-8000-000000000002',v_identity.system_identifier,v_identity.database_oid,v_identity.database_name,'c5850000-0000-4000-8000-000000000012','c5850000-0000-4000-8000-000000000022',v_source,'deedlight_ledger_approver',clock_timestamp()),
    ('c5850000-0000-4000-8000-000000000003',v_identity.system_identifier,v_identity.database_oid,v_identity.database_name,'c5850000-0000-4000-8000-000000000013','c5850000-0000-4000-8000-000000000023',v_source,'deedlight_ledger_approver',clock_timestamp());
  INSERT INTO deedlight_execution_ledger.executions
    (system_identifier,database_oid,database_name,record_id,execution_id,approval_id,source_identity,status,approver_identity,runner_identity,started_at)
  VALUES
    (v_identity.system_identifier,v_identity.database_oid,v_identity.database_name,'c5850000-0000-4000-8000-000000000012','c5850000-0000-4000-8000-000000000022','c5850000-0000-4000-8000-000000000002',v_source,'running','deedlight_ledger_approver','deedlight_ledger_runner',clock_timestamp()),
    (v_identity.system_identifier,v_identity.database_oid,v_identity.database_name,'c5850000-0000-4000-8000-000000000013','c5850000-0000-4000-8000-000000000023','c5850000-0000-4000-8000-000000000003',v_source,'running','deedlight_ledger_approver','deedlight_ledger_runner',clock_timestamp());
  INSERT INTO deedlight_execution_ledger.execution_commit_markers
    (system_identifier,database_oid,execution_id,source_identity,runner_identity,transaction_id)
  VALUES
    (v_identity.system_identifier,v_identity.database_oid,'c5850000-0000-4000-8000-000000000022',v_source,'deedlight_ledger_runner',pg_current_xact_id()::text),
    (v_identity.system_identifier,v_identity.database_oid,'c5850000-0000-4000-8000-000000000023',v_source,'deedlight_ledger_runner',pg_current_xact_id()::text);
  INSERT INTO deedlight_execution_ledger.snapshots
    (system_identifier,database_oid,execution_id,phase,query_id,query_sha256,query_bundle_digest,observer_identity,observed_at,snapshot,snapshot_sha256)
  SELECT system_identifier,database_oid,'c5850000-0000-4000-8000-000000000023','pre',query_id,query_sha256,
    query_bundle_digest,observer_identity,observed_at,snapshot,snapshot_sha256
  FROM deedlight_execution_ledger.snapshots
  WHERE execution_id='c5700000-0000-4000-8000-000000000021' AND phase='pre';
END
$seed$;
SET ROLE deedlight_ledger_runner;
DO $assert$
DECLARE v_detail text;
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.finalize_execution('c5850000-0000-4000-8000-000000000022','succeeded','{"result":"no-pre"}'::jsonb);
    RAISE EXCEPTION 'C585 missing pre snapshot unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE 'D1006' THEN
    GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
    IF v_detail NOT LIKE '%pre_snapshot_missing%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM deedlight_execution_ledger.finalize_execution('c5850000-0000-4000-8000-000000000023','succeeded','{"result":"no-post"}'::jsonb);
    RAISE EXCEPTION 'C585 missing post snapshot unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE 'D1006' THEN
    GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
    IF v_detail NOT LIKE '%post_snapshot_missing%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM deedlight_execution_ledger.finalize_execution('c5700000-0000-4000-8000-000000000021','succeeded','{"result":"duplicate"}'::jsonb);
    RAISE EXCEPTION 'C585 terminal finalization unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE 'D1007' THEN NULL;
  END;
END
$assert$;
RESET ROLE;

DO $assert$
BEGIN
  BEGIN
    UPDATE deedlight_execution_ledger.snapshots SET snapshot_sha256=repeat('f',64)
      WHERE execution_id='c5700000-0000-4000-8000-000000000021' AND phase='pre';
    RAISE EXCEPTION 'C585 snapshot UPDATE unexpectedly succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='C585 snapshot UPDATE unexpectedly succeeded' THEN RAISE; END IF;
    IF SQLERRM<>'ledger evidence is append-only' THEN RAISE; END IF;
  END;
  BEGIN
    DELETE FROM deedlight_execution_ledger.snapshots
      WHERE execution_id='c5700000-0000-4000-8000-000000000021' AND phase='pre';
    RAISE EXCEPTION 'C585 snapshot DELETE unexpectedly succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='C585 snapshot DELETE unexpectedly succeeded' THEN RAISE; END IF;
    IF SQLERRM<>'ledger evidence is append-only' THEN RAISE; END IF;
  END;
END
$assert$;
SELECT 'C585_BUNDLE_DIGEST_PASS' AS evidence;
SELECT 'C585_SQL_AND_BUNDLE_SUBSTITUTION_REJECTED' AS evidence;
SELECT 'C585_QUERY_MANIFEST_SNAPSHOT_IMMUTABILITY_PASS' AS evidence;
SELECT 'C585_SOURCE_IDENTITY_SUBSTITUTION_REJECTED' AS evidence;
SELECT 'C585_MISSING_PRE_POST_SNAPSHOT_REJECTED' AS evidence;

-- Missing observer trust and malformed source identity have distinct fail-closed outcomes.
SET ROLE deedlight_ledger_runner;
DO $assert$
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.capture_snapshot(
      'c5700000-0000-4000-8000-000000000028','post','test_effects_v1');
    RAISE EXCEPTION 'C585 missing observer trust unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE 'D1001' THEN NULL;
  END;
  BEGIN
    PERFORM deedlight_execution_ledger.reserve_execution(
      'c5850000-0000-4000-8000-000000000004',
      'c5850000-0000-4000-8000-000000000014',
      'c5850000-0000-4000-8000-000000000024',
      '{"path":"../escape.sql","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'::jsonb);
    RAISE EXCEPTION 'C585 malformed source identity unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE 'D1002' THEN NULL;
  END;
END
$assert$;
RESET ROLE;

