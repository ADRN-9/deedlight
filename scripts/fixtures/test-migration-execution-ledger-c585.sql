\set ON_ERROR_STOP on

-- Independent, fixed digest vector: bytewise UTF-8 ordering and LF separators.
DO $vectors$
DECLARE v_manifest jsonb := '[{"queryId":"beta","querySha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},{"queryId":"alpha","querySha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]'::jsonb;
        v_expected constant text := 'bd74c6371a354921102fac978aadf1da23615655858f97f875671beaa4d624e4';
BEGIN
  IF deedlight_execution_ledger.canonical_query_bundle_digest(v_manifest) <> v_expected THEN
    RAISE EXCEPTION 'C593 independent canonical digest vector mismatch';
  END IF;
  IF deedlight_execution_ledger.canonical_query_bundle_digest(
    pg_catalog.jsonb_build_array(v_manifest->1, v_manifest->0)
  ) <> v_expected THEN
    RAISE EXCEPTION 'C593 manifest ordering is not permutation independent';
  END IF;
  BEGIN
    PERFORM deedlight_execution_ledger.canonical_query_bundle_digest(
      '[{"queryId":"alpha","querySha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},{"queryId":"alpha","querySha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]'::jsonb
    );
    RAISE EXCEPTION 'C593 duplicate manifest member unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE 'D1001' THEN NULL;
  END;
END
$vectors$;

-- A valid digest does not make a query a member of a different manifest.
INSERT INTO deedlight_execution_ledger.query_bundle_manifests
  (bundle_id, manifest, member_count, manifest_sha256)
VALUES (
  'c593_forged_bundle',
  '[{"queryId":"alpha","querySha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]'::jsonb,
  1,
  deedlight_execution_ledger.canonical_query_bundle_digest(
    '[{"queryId":"alpha","querySha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]'::jsonb
  )
);
INSERT INTO deedlight_execution_ledger.observation_queries
  (query_id,query_sql,description,query_sha256,query_bundle_id,query_bundle_digest)
SELECT 'c593_nonmember_query',query_sql,'C593 valid SQL but not a member of the forged manifest',
  query_sha256,'c593_forged_bundle',
  (SELECT manifest_sha256 FROM deedlight_execution_ledger.query_bundle_manifests WHERE bundle_id='c593_forged_bundle')
FROM deedlight_execution_ledger.observation_queries WHERE query_id='test_effects_v1';
SET ROLE deedlight_ledger_observer;
DO $membership$
DECLARE v_detail text;
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.capture_snapshot(
      'c5700000-0000-4000-8000-000000000028','post','c593_nonmember_query');
    RAISE EXCEPTION 'C593 nonmember query unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE 'D1004' THEN
    GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
    IF v_detail NOT LIKE '%query_bundle_manifest_integrity_or_membership_mismatch%' THEN RAISE; END IF;
  END;
END
$membership$;
RESET ROLE;

-- Source identity fields are immutable independently of the append-only row guards.
DO $immutability$
BEGIN
  BEGIN
    UPDATE deedlight_execution_ledger.approvals
      SET source_identity='{"path":"substituted.sql","sha256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}'::jsonb
      WHERE approval_id='c5700000-0000-4000-8000-000000000007';
    RAISE EXCEPTION 'C593 approval source identity mutation unexpectedly succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='C593 approval source identity mutation unexpectedly succeeded' THEN RAISE; END IF;
    IF SQLERRM<>'approval is immutable except for one-time consumption' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE deedlight_execution_ledger.executions
      SET source_identity='{"path":"substituted.sql","sha256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}'::jsonb
      WHERE execution_id='c5700000-0000-4000-8000-000000000028';
    RAISE EXCEPTION 'C593 execution source identity mutation unexpectedly succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='C593 execution source identity mutation unexpectedly succeeded' THEN RAISE; END IF;
    IF SQLERRM<>'execution identity and reservation evidence are immutable' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE deedlight_execution_ledger.execution_commit_markers
      SET source_identity='{"path":"substituted.sql","sha256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}'::jsonb
      WHERE execution_id='c5700000-0000-4000-8000-000000000028';
    RAISE EXCEPTION 'C593 marker source identity mutation unexpectedly succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='C593 marker source identity mutation unexpectedly succeeded' THEN RAISE; END IF;
    IF SQLERRM<>'ledger evidence is append-only' THEN RAISE; END IF;
  END;
END
$immutability$;

-- Simulate logical-restore substitution of the persisted identity anchor.
-- Every privileged operation must fail before consuming or changing ledger state.
BEGIN;
CREATE TEMP TABLE c593_identity_anchor AS
SELECT system_identifier, database_oid, database_name, server_version_num
FROM deedlight_execution_ledger.database_identity WHERE singleton;
SET LOCAL session_replication_role = replica;
UPDATE deedlight_execution_ledger.database_identity
SET system_identifier = CASE WHEN system_identifier LIKE '0%'
  THEN '1' || substr(system_identifier, 2) ELSE '0' || substr(system_identifier, 2) END
WHERE singleton;
SET LOCAL session_replication_role = origin;

CREATE TEMP TABLE c593_identity_side_effect_baseline AS
SELECT
  (SELECT count(*) FROM deedlight_execution_ledger.execution_commit_markers
    WHERE execution_id='c5700000-0000-4000-8000-000000000028') AS marker_count,
  (SELECT count(*) FROM deedlight_execution_ledger.executions WHERE status='running') AS running_count;
SET LOCAL ROLE deedlight_ledger_runner;
DO $identity$
DECLARE v_detail text;
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.reserve_execution(
      'c5850000-0000-4000-8000-000000000004',
      'c5850000-0000-4000-8000-000000000014',
      'c5850000-0000-4000-8000-000000000024',
      '{"path":"supabase/migrations/c585-approved.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb);
    RAISE EXCEPTION 'C593 reserve accepted substituted database identity';
  EXCEPTION WHEN SQLSTATE 'D1001' THEN
    GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
    IF v_detail NOT LIKE '%live_database_identity_mismatch%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM deedlight_execution_ledger.record_effect_commit_marker(
      'c5700000-0000-4000-8000-000000000028',
      '{"path":"supabase/migrations/test-query-mismatch.sql","sha256":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}'::jsonb);
    RAISE EXCEPTION 'C593 marker accepted substituted database identity';
  EXCEPTION WHEN SQLSTATE 'D1001' THEN
    GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
    IF v_detail NOT LIKE '%live_database_identity_mismatch%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM deedlight_execution_ledger.finalize_execution(
      'c5700000-0000-4000-8000-000000000028','failed','{"result":"identity-mismatch"}'::jsonb);
    RAISE EXCEPTION 'C593 finalize accepted substituted database identity';
  EXCEPTION WHEN SQLSTATE 'D1001' THEN
    GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
    IF v_detail NOT LIKE '%live_database_identity_mismatch%' THEN RAISE; END IF;
  END;
END
$identity$;
RESET ROLE;

SET LOCAL ROLE deedlight_ledger_recovery;
DO $identity$
DECLARE v_detail text;
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.recover_stale_executions(interval '1 microsecond');
    RAISE EXCEPTION 'C593 recovery accepted substituted database identity';
  EXCEPTION WHEN SQLSTATE 'D1001' THEN
    GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
    IF v_detail NOT LIKE '%live_database_identity_mismatch%' THEN RAISE; END IF;
  END;
END
$identity$;
RESET ROLE;

DO $side_effects$
BEGIN
  IF (SELECT count(*) FROM deedlight_execution_ledger.execution_commit_markers
      WHERE execution_id='c5700000-0000-4000-8000-000000000028')
    <> (SELECT marker_count FROM c593_identity_side_effect_baseline) THEN
    RAISE EXCEPTION 'C593 identity failure changed commit markers';
  END IF;
  IF (SELECT count(*) FROM deedlight_execution_ledger.executions WHERE status='running')
    <> (SELECT running_count FROM c593_identity_side_effect_baseline) THEN
    RAISE EXCEPTION 'C593 identity failure changed execution statuses';
  END IF;
  IF EXISTS (SELECT 1 FROM deedlight_execution_ledger.approvals
    WHERE approval_id='c5850000-0000-4000-8000-000000000004' AND consumed_at IS NOT NULL) THEN
    RAISE EXCEPTION 'C593 identity failure consumed approval';
  END IF;
  IF EXISTS (SELECT 1 FROM deedlight_execution_ledger.executions
    WHERE execution_id='c5850000-0000-4000-8000-000000000024') THEN
    RAISE EXCEPTION 'C593 identity failure created execution';
  END IF;
END
$side_effects$;

SET LOCAL session_replication_role = replica;
UPDATE deedlight_execution_ledger.database_identity
SET (system_identifier,database_oid,database_name,server_version_num) =
  (SELECT system_identifier,database_oid,database_name,server_version_num FROM c593_identity_anchor);
SET LOCAL session_replication_role = origin;
COMMIT;

-- Database-OID substitution models a logical restore into another database on the same cluster.
BEGIN;
CREATE TEMP TABLE c593_oid_anchor AS
SELECT database_oid FROM deedlight_execution_ledger.database_identity WHERE singleton;
SET LOCAL session_replication_role = replica;
UPDATE deedlight_execution_ledger.database_identity
SET database_oid = (database_oid::bigint + 1)::oid
WHERE singleton;
SET LOCAL session_replication_role = origin;
SET LOCAL ROLE deedlight_ledger_recovery;
DO $oid$
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.recover_stale_executions(interval '1 microsecond');
    RAISE EXCEPTION 'C593 recovery accepted logical-restore database OID substitution';
  EXCEPTION WHEN SQLSTATE 'D1001' THEN NULL;
  END;
END
$oid$;
RESET ROLE;
SET LOCAL session_replication_role = replica;
UPDATE deedlight_execution_ledger.database_identity
SET database_oid = (SELECT database_oid FROM c593_oid_anchor);
SET LOCAL session_replication_role = origin;
COMMIT;

DO $assert$
BEGIN
  IF (SELECT count(*) FROM deedlight_execution_ledger.query_bundle_manifests
      WHERE bundle_id IN ('test_effects_bundle_v1','test_effects_bundle_v2')) <> 2 THEN
    RAISE EXCEPTION 'C585 bundle manifest cardinality mismatch';
  END IF;
  IF EXISTS (SELECT 1 FROM deedlight_execution_ledger.query_bundle_manifests
    WHERE bundle_id IN ('test_effects_bundle_v1','test_effects_bundle_v2')
      AND (manifest_sha256 <> deedlight_execution_ledger.canonical_query_bundle_digest(manifest)
       OR member_count <> jsonb_array_length(manifest))) THEN
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

-- A manifest whose stored digest is forged must be rejected even when membership matches.
INSERT INTO deedlight_execution_ledger.query_bundle_manifests
  (bundle_id, manifest, member_count, manifest_sha256)
SELECT 'c593_forged_digest_bundle',
  pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
    'queryId','c593_forged_digest_query','querySha256',q.query_sha256)),
  1, repeat('e',64)
FROM deedlight_execution_ledger.observation_queries q
WHERE q.query_id='test_effects_v1';
INSERT INTO deedlight_execution_ledger.observation_queries
  (query_id,query_sql,description,query_sha256,query_bundle_id,query_bundle_digest)
SELECT 'c593_forged_digest_query',q.query_sql,'C593 deliberately forged manifest digest',
  q.query_sha256,'c593_forged_digest_bundle',repeat('e',64)
FROM deedlight_execution_ledger.observation_queries q
WHERE q.query_id='test_effects_v1';
SET ROLE deedlight_ledger_observer;
DO $forged$
DECLARE v_detail text;
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.capture_snapshot(
      'c5700000-0000-4000-8000-000000000028','post','c593_forged_digest_query');
    RAISE EXCEPTION 'C593 forged manifest digest unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE 'D1004' THEN
    GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
    IF v_detail NOT LIKE '%query_bundle_manifest_integrity_or_membership_mismatch%' THEN RAISE; END IF;
  END;
END
$forged$;
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

-- A fixture-only untrusted role has function EXECUTE but no observer authority.
-- This reaches the function's fail-closed trust check without widening runner privileges.
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='deedlight_ledger_untrusted') THEN
    CREATE ROLE deedlight_ledger_untrusted NOLOGIN NOINHERIT;
  END IF;
END
$roles$;
GRANT deedlight_ledger_untrusted TO postgres;
GRANT USAGE ON SCHEMA deedlight_execution_ledger TO deedlight_ledger_untrusted;
GRANT EXECUTE ON FUNCTION deedlight_execution_ledger.capture_snapshot(uuid,text,text)
  TO deedlight_ledger_untrusted;
SET ROLE deedlight_ledger_untrusted;
DO $assert$
BEGIN
  BEGIN
    PERFORM deedlight_execution_ledger.capture_snapshot(
      'c5700000-0000-4000-8000-000000000028','post','test_effects_v1');
    RAISE EXCEPTION 'C585 missing observer trust unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE 'D1001' THEN NULL;
  END;
END
$assert$;
RESET ROLE;

SET ROLE deedlight_ledger_runner;
DO $assert$
BEGIN
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

SELECT 'C593_BYTEWISE_CANONICAL_DIGEST_VECTOR_PASS' AS evidence;
SELECT 'C593_FORGED_MANIFEST_NONMEMBER_QUERY_REJECTED' AS evidence;
SELECT 'C593_FORGED_MANIFEST_DIGEST_REJECTED' AS evidence;
SELECT 'C593_SOURCE_IDENTITY_IMMUTABILITY_PASS' AS evidence;
SELECT 'C593_LIVE_DATABASE_IDENTITY_FAIL_CLOSED_PASS' AS evidence;
