\set ON_ERROR_STOP on

CREATE TEMP TABLE c603_temp_bootstrap(id integer);
DROP TABLE c603_temp_bootstrap;

-- Test-only signer: it runs in the disposable CI database and is not shipped.
CREATE OR REPLACE FUNCTION pg_temp.c603_sign(
  p_actor text,p_operation text,p_execution_id uuid,p_request jsonb
) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE
  v_key bytea;
  v_key_id text := 'c603-' || replace(p_actor,'deedlight_ledger_','') || '-v1';
  v_envelope jsonb;
BEGIN
  v_key := CASE p_actor
    WHEN 'deedlight_ledger_approver' THEN decode(repeat('11',32),'hex')
    WHEN 'deedlight_ledger_runner' THEN decode(repeat('22',32),'hex')
    WHEN 'deedlight_ledger_observer' THEN decode(repeat('33',32),'hex')
    WHEN 'deedlight_ledger_recovery' THEN decode(repeat('44',32),'hex')
    WHEN 'deedlight_ledger_verifier' THEN decode(repeat('55',32),'hex')
    ELSE NULL END;
  IF v_key IS NULL THEN RAISE EXCEPTION 'unknown test actor'; END IF;
  v_envelope := pg_catalog.jsonb_build_object(
    'version',1,'operation',p_operation,'actor',p_actor,'principal',p_actor,
    'executionId',p_execution_id,
    'databaseResource',deedlight_execution_ledger.current_database_identity(),
    'generation',1,'audience','deedlight.execution-ledger.gateway.v1',
    'nonce',deedlight_execution_ledger.gen_random_uuid(),
    'issuedAt',pg_catalog.clock_timestamp(),
    'expiresAt',pg_catalog.clock_timestamp()+interval '1 minute',
    'request',p_request,
    'requestDigest',pg_catalog.encode(deedlight_execution_ledger.digest(
      pg_catalog.convert_to(p_request::text,'UTF8'),'sha256'),'hex'),
    'keyId',v_key_id
  );
  RETURN v_envelope || pg_catalog.jsonb_build_object('signature',
    pg_catalog.encode(deedlight_execution_ledger.hmac(
      pg_catalog.convert_to(v_envelope::text,'UTF8'),v_key,'sha256'),'hex'));
END
$fn$;
REVOKE ALL ON FUNCTION pg_temp.c603_sign(text,text,uuid,jsonb) FROM PUBLIC;

CREATE SCHEMA c603_test;
GRANT USAGE ON SCHEMA c603_test TO deedlight_ledger_approver,
  deedlight_ledger_runner,deedlight_ledger_observer,
  deedlight_ledger_recovery,deedlight_ledger_verifier;
CREATE OR REPLACE FUNCTION c603_test.assert_rejected(p_sql text,p_expected_state text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_state text;
BEGIN
  BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'C603 expected rejection but statement succeeded: %',p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    IF v_state IS DISTINCT FROM p_expected_state THEN
      RAISE EXCEPTION 'C603 wrong rejection SQLSTATE: expected %, got % for %',
        p_expected_state,v_state,p_sql;
    END IF;
  END;
END
$fn$;
REVOKE ALL ON FUNCTION c603_test.assert_rejected(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION c603_test.assert_rejected(text,text) TO
  deedlight_ledger_approver,deedlight_ledger_runner,deedlight_ledger_observer,
  deedlight_ledger_recovery,deedlight_ledger_verifier;

-- Positive: complete lifecycle through all five independently authenticated actors.
SELECT pg_temp.c603_sign('deedlight_ledger_approver','approve_execution',
 'c6030000-0000-4000-8000-000000000021',
 pg_catalog.jsonb_build_object('approvalId','c6030000-0000-4000-8000-000000000001'::uuid,
 'recordId','c6030000-0000-4000-8000-000000000011'::uuid,
 'executionId','c6030000-0000-4000-8000-000000000021'::uuid,
 'sourceIdentity','{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb)
) AS approval_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_approver;
SELECT deedlight_execution_ledger.approve_execution(
 'c6030000-0000-4000-8000-000000000001','c6030000-0000-4000-8000-000000000011',
 'c6030000-0000-4000-8000-000000000021',
 '{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb,
 :'approval_auth'::jsonb);
RESET SESSION AUTHORIZATION;
SELECT 'C603_APPROVER_SIGNED_APPROVAL_PASS' AS evidence;

SELECT pg_temp.c603_sign('deedlight_ledger_runner','reserve_execution',
 'c6030000-0000-4000-8000-000000000021',
 pg_catalog.jsonb_build_object('approvalId','c6030000-0000-4000-8000-000000000001'::uuid,
 'recordId','c6030000-0000-4000-8000-000000000011'::uuid,
 'executionId','c6030000-0000-4000-8000-000000000021'::uuid,
 'sourceIdentity','{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb)
) AS reserve_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_runner;
SELECT deedlight_execution_ledger.reserve_execution(
 'c6030000-0000-4000-8000-000000000001','c6030000-0000-4000-8000-000000000011',
 'c6030000-0000-4000-8000-000000000021',
 '{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb,
 :'reserve_auth'::jsonb);
RESET SESSION AUTHORIZATION;

SELECT pg_temp.c603_sign('deedlight_ledger_observer','capture_snapshot',
 'c6030000-0000-4000-8000-000000000021',
 pg_catalog.jsonb_build_object('executionId','c6030000-0000-4000-8000-000000000021'::uuid,
 'phase','pre','queryId','test_effects_v1','sourceIdentity','{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb)
) AS pre_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_observer;
SELECT deedlight_execution_ledger.capture_snapshot(
 'c6030000-0000-4000-8000-000000000021','pre','test_effects_v1','{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb,:'pre_auth'::jsonb);
RESET SESSION AUTHORIZATION;

SELECT pg_temp.c603_sign('deedlight_ledger_runner','start_execution',
 'c6030000-0000-4000-8000-000000000021',
 pg_catalog.jsonb_build_object('executionId','c6030000-0000-4000-8000-000000000021'::uuid,
 'sourceIdentity','{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb)
) AS start_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_runner;
SELECT deedlight_execution_ledger.start_execution('c6030000-0000-4000-8000-000000000021','{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb,:'start_auth'::jsonb);
RESET SESSION AUTHORIZATION;

SELECT pg_temp.c603_sign('deedlight_ledger_runner','heartbeat_execution',
 'c6030000-0000-4000-8000-000000000021',
 pg_catalog.jsonb_build_object('executionId','c6030000-0000-4000-8000-000000000021'::uuid,
 'sourceIdentity','{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb)
) AS heartbeat_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_runner;
SELECT deedlight_execution_ledger.heartbeat_execution('c6030000-0000-4000-8000-000000000021','{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb,:'heartbeat_auth'::jsonb);
RESET SESSION AUTHORIZATION;

SELECT pg_temp.c603_sign('deedlight_ledger_runner','record_effect_commit_marker',
 'c6030000-0000-4000-8000-000000000021',
 pg_catalog.jsonb_build_object('executionId','c6030000-0000-4000-8000-000000000021'::uuid,
 'sourceIdentity','{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb)
) AS marker_auth \gset
BEGIN;
SET SESSION AUTHORIZATION deedlight_ledger_runner;
INSERT INTO deedlight_execution_ledger.test_effects(effect_value) VALUES ('C603 signed gateway effect');
SELECT deedlight_execution_ledger.record_effect_commit_marker(
 'c6030000-0000-4000-8000-000000000021',
 '{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb,
 :'marker_auth'::jsonb);
COMMIT;
RESET SESSION AUTHORIZATION;

SELECT pg_temp.c603_sign('deedlight_ledger_observer','capture_snapshot',
 'c6030000-0000-4000-8000-000000000021',
 pg_catalog.jsonb_build_object('executionId','c6030000-0000-4000-8000-000000000021'::uuid,
 'phase','post','queryId','test_effects_v1','sourceIdentity','{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb)
) AS post_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_observer;
SELECT deedlight_execution_ledger.capture_snapshot(
 'c6030000-0000-4000-8000-000000000021','post','test_effects_v1','{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb,:'post_auth'::jsonb);
RESET SESSION AUTHORIZATION;

SELECT pg_temp.c603_sign('deedlight_ledger_runner','finalize_execution',
 'c6030000-0000-4000-8000-000000000021',
 pg_catalog.jsonb_build_object('executionId','c6030000-0000-4000-8000-000000000021'::uuid,
 'outcome','succeeded','outcomeDetail','{"result":"signed"}'::jsonb,
 'sourceIdentity','{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb)
) AS finalize_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_runner;
SELECT deedlight_execution_ledger.finalize_execution(
 'c6030000-0000-4000-8000-000000000021','succeeded','{"result":"signed"}'::jsonb,'{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb,:'finalize_auth'::jsonb);
RESET SESSION AUTHORIZATION;

SELECT pg_temp.c603_sign('deedlight_ledger_verifier','record_verification',
 'c6030000-0000-4000-8000-000000000021',
 pg_catalog.jsonb_build_object('executionId','c6030000-0000-4000-8000-000000000021'::uuid,
 'verdict','verified','evidence','{"independent":true}'::jsonb,
 'sourceIdentity','{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb)
) AS verify_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_verifier;
SELECT deedlight_execution_ledger.record_verification(
 'c6030000-0000-4000-8000-000000000021','verified','{"independent":true}'::jsonb,'{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb,:'verify_auth'::jsonb);
RESET SESSION AUTHORIZATION;
SELECT 'C603_ALL_NINE_SIGNED_POSITIVE_PATHS_PASS' AS evidence;

-- Recovery positive path with an independently signed, bounded stale interval.
SELECT pg_temp.c603_sign('deedlight_ledger_approver','approve_execution',
 'c6030000-0000-4000-8000-000000000022',
 pg_catalog.jsonb_build_object('approvalId','c6030000-0000-4000-8000-000000000002'::uuid,
 'recordId','c6030000-0000-4000-8000-000000000012'::uuid,
 'executionId','c6030000-0000-4000-8000-000000000022'::uuid,
 'sourceIdentity','{"path":"supabase/migrations/c603-recovery.sql","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'::jsonb)
) AS recovery_approval_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_approver;
SELECT deedlight_execution_ledger.approve_execution(
 'c6030000-0000-4000-8000-000000000002','c6030000-0000-4000-8000-000000000012',
 'c6030000-0000-4000-8000-000000000022',
 '{"path":"supabase/migrations/c603-recovery.sql","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'::jsonb,
 :'recovery_approval_auth'::jsonb);
RESET SESSION AUTHORIZATION;
SELECT pg_temp.c603_sign('deedlight_ledger_runner','reserve_execution',
 'c6030000-0000-4000-8000-000000000022',
 pg_catalog.jsonb_build_object('approvalId','c6030000-0000-4000-8000-000000000002'::uuid,
 'recordId','c6030000-0000-4000-8000-000000000012'::uuid,
 'executionId','c6030000-0000-4000-8000-000000000022'::uuid,
 'sourceIdentity','{"path":"supabase/migrations/c603-recovery.sql","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'::jsonb)
) AS recovery_reserve_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_runner;
SELECT deedlight_execution_ledger.reserve_execution(
 'c6030000-0000-4000-8000-000000000002','c6030000-0000-4000-8000-000000000012',
 'c6030000-0000-4000-8000-000000000022',
 '{"path":"supabase/migrations/c603-recovery.sql","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'::jsonb,
 :'recovery_reserve_auth'::jsonb);
RESET SESSION AUTHORIZATION;
SELECT pg_catalog.pg_sleep(0.02);
SELECT pg_temp.c603_sign('deedlight_ledger_recovery','recover_stale_executions',NULL,
 pg_catalog.jsonb_build_object('staleAfter','00:00:00.000001',
 'sourceSetDigest',(SELECT pg_catalog.encode(deedlight_execution_ledger.digest(
   pg_catalog.convert_to(coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
     'executionId',execution_id,'sourceIdentity',source_identity,'status',status,
     'heartbeatAt',heartbeat_at) ORDER BY execution_id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
   FROM deedlight_execution_ledger.executions WHERE status IN ('reserved','running')
     AND heartbeat_at < pg_catalog.clock_timestamp()-interval '1 microsecond'),
 'targetCount',(SELECT pg_catalog.count(*) FROM deedlight_execution_ledger.executions
   WHERE status IN ('reserved','running') AND heartbeat_at < pg_catalog.clock_timestamp()-interval '1 microsecond'))) AS recover_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT deedlight_execution_ledger.recover_stale_executions(interval '1 microsecond',:'recover_auth'::jsonb);
RESET SESSION AUTHORIZATION;
SELECT 'C603_RECOVERY_SIGNED_POSITIVE_PATH_PASS' AS evidence;

-- Assert the owner/actor separation and exact 5 x 9 EXECUTE matrix.
DO $catalog$
DECLARE v_proc text; v_actor text; v_allowed text; v_impl text; v_owner oid;
DECLARE v_rpc text[] := ARRAY[
 'approve_execution(uuid,uuid,uuid,jsonb,jsonb)',
 'reserve_execution(uuid,uuid,uuid,jsonb,jsonb)',
 'record_effect_commit_marker(uuid,jsonb,jsonb)',
 'capture_snapshot(uuid,text,text,jsonb,jsonb)',
 'start_execution(uuid,jsonb,jsonb)',
 'heartbeat_execution(uuid,jsonb,jsonb)',
 'finalize_execution(uuid,text,jsonb,jsonb,jsonb)',
 'recover_stale_executions(interval,jsonb)',
 'record_verification(uuid,text,jsonb,jsonb,jsonb)'
];
DECLARE v_actors text[] := ARRAY[
 'deedlight_ledger_approver','deedlight_ledger_runner','deedlight_ledger_observer',
 'deedlight_ledger_recovery','deedlight_ledger_verifier'
];
BEGIN
 SELECT oid INTO STRICT v_owner FROM pg_catalog.pg_roles WHERE rolname='deedlight_ledger_owner';
 IF (SELECT rolsuper OR rolcanlogin OR NOT rolinherit
     FROM pg_catalog.pg_roles WHERE rolname='deedlight_ledger_owner') THEN
   RAISE EXCEPTION 'C603 definer owner attributes invalid';
 END IF;
 IF pg_catalog.has_schema_privilege('deedlight_ledger_owner',
   'deedlight_execution_ledger','CREATE') THEN
   RAISE EXCEPTION 'C603 definer owner retained schema CREATE';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members m
   JOIN pg_catalog.pg_roles r ON r.oid=m.roleid
   JOIN pg_catalog.pg_roles u ON u.oid=m.member
   WHERE r.rolname=ANY(v_actors) AND u.rolname=ANY(v_actors)) THEN
   RAISE EXCEPTION 'C603 cross-actor membership detected';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members m
   JOIN pg_catalog.pg_roles r ON r.oid=m.roleid
   JOIN pg_catalog.pg_roles u ON u.oid=m.member
   WHERE (r.rolname=ANY(v_actors) OR u.rolname=ANY(v_actors))
     AND NOT (r.rolname='pg_monitor' AND u.rolname='deedlight_ledger_owner')) THEN
   RAISE EXCEPTION 'C603 actor principal has unexpected role membership';
 END IF;
 FOREACH v_actor IN ARRAY v_actors LOOP
   IF NOT (SELECT rolcanlogin AND NOT rolsuper AND NOT rolinherit
     FROM pg_catalog.pg_roles WHERE rolname=v_actor) THEN
     RAISE EXCEPTION 'C603 actor principal attributes invalid: %',v_actor;
   END IF;
   IF pg_catalog.has_table_privilege(v_actor,'deedlight_execution_ledger.approvals','SELECT')
     OR pg_catalog.has_table_privilege(v_actor,'deedlight_execution_ledger.executions','SELECT')
     OR pg_catalog.has_table_privilege(v_actor,'deedlight_execution_ledger.snapshots','SELECT')
     OR pg_catalog.has_table_privilege(v_actor,'deedlight_execution_ledger.execution_commit_markers','SELECT')
     OR pg_catalog.has_table_privilege(v_actor,'deedlight_execution_ledger.verification_events','SELECT')
     OR pg_catalog.has_table_privilege(v_actor,'deedlight_execution_ledger.authorization_keys','SELECT')
     OR pg_catalog.has_table_privilege(v_actor,'deedlight_execution_ledger.authorization_nonces','SELECT') THEN
     RAISE EXCEPTION 'C603 actor has direct protected-table read access: %',v_actor;
   END IF;
 END LOOP;

 FOREACH v_proc IN ARRAY v_rpc LOOP
   DECLARE v_oid oid := pg_catalog.to_regprocedure('deedlight_execution_ledger.'||v_proc);
   BEGIN
     IF v_oid IS NULL OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc p
       WHERE p.oid=v_oid AND p.proowner=v_owner AND p.prosecdef
         AND p.proconfig @> ARRAY['search_path=pg_catalog, deedlight_execution_ledger']
     ) THEN
       RAISE EXCEPTION 'C603 wrapper owner/SECURITY DEFINER/search_path assertion failed: %',v_proc;
     END IF;
     IF EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc p
       CROSS JOIN LATERAL pg_catalog.aclexplode(
         coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
       WHERE p.oid=v_oid AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
     ) THEN
       RAISE EXCEPTION 'C603 wrapper still grants PUBLIC EXECUTE: %',v_proc;
     END IF;
   END;
 END LOOP;

 FOREACH v_impl IN ARRAY ARRAY[
   'approve_execution_impl(uuid,uuid,uuid,jsonb)',
   'reserve_execution_impl(uuid,uuid,uuid,jsonb)',
   'record_effect_commit_marker_impl(uuid,jsonb)',
   'capture_snapshot_impl(uuid,text,text)',
   'start_execution_impl(uuid)',
   'heartbeat_execution_impl(uuid)',
   'finalize_execution_impl(uuid,text,jsonb)',
   'recover_stale_executions_impl(interval)',
   'record_verification_impl(uuid,text,jsonb)'
 ] LOOP
   v_proc := 'deedlight_execution_ledger.'||v_impl;
   IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
     WHERE p.oid=pg_catalog.to_regprocedure(v_proc) AND p.proowner=v_owner AND p.prosecdef) THEN
     RAISE EXCEPTION 'C603 implementation owner/SECURITY DEFINER assertion failed: %',v_impl;
   END IF;
   FOREACH v_actor IN ARRAY v_actors LOOP
     IF pg_catalog.has_function_privilege(v_actor,pg_catalog.to_regprocedure(v_proc),'EXECUTE') THEN
       RAISE EXCEPTION 'C603 actor can execute owner-only implementation: actor=% function=%',v_actor,v_impl;
     END IF;
   END LOOP;
 END LOOP;

 FOREACH v_actor IN ARRAY v_actors LOOP
   FOREACH v_proc IN ARRAY v_rpc LOOP
     v_allowed := CASE
       WHEN v_proc LIKE 'approve_execution%' THEN 'deedlight_ledger_approver'
       WHEN v_proc LIKE 'reserve_execution%' OR v_proc LIKE 'record_effect_commit_marker%'
         OR v_proc LIKE 'start_execution%' OR v_proc LIKE 'heartbeat_execution%'
         OR v_proc LIKE 'finalize_execution%' THEN 'deedlight_ledger_runner'
       WHEN v_proc LIKE 'capture_snapshot%' THEN 'deedlight_ledger_observer'
       WHEN v_proc LIKE 'recover_stale_executions%' THEN 'deedlight_ledger_recovery'
       ELSE 'deedlight_ledger_verifier' END;
     IF pg_catalog.has_function_privilege(v_actor,
       pg_catalog.to_regprocedure('deedlight_execution_ledger.'||v_proc),'EXECUTE')
       IS DISTINCT FROM (v_actor=v_allowed) THEN
       RAISE EXCEPTION 'C603 unexpected EXECUTE matrix actor=% rpc=%',v_actor,v_proc;
     END IF;
   END LOOP;
 END LOOP;
END
$catalog$;
SELECT 'C603_FIVE_ACTOR_NINE_RPC_EXECUTE_MATRIX_PASS' AS evidence;

-- Each actor attempts all nine RPCs. The single permitted function rejects
-- missing signatures; the other eight fail at the EXECUTE boundary.
CREATE TEMP TABLE c603_before AS
SELECT
 (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.approvals t) approvals,
 (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.executions t) executions,
 (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.snapshots t) snapshots,
 (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.execution_commit_markers t) markers,
 (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.verification_events t) verifications,
 (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.authorization_nonces t) nonces;

SET SESSION AUTHORIZATION deedlight_ledger_approver;
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.approve_execution(NULL,NULL,NULL,NULL,NULL)','D1001');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.reserve_execution(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.record_effect_commit_marker(NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.capture_snapshot(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.start_execution(NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.heartbeat_execution(NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.finalize_execution(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.recover_stale_executions(NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.record_verification(NULL,NULL,NULL,NULL,NULL)','42501');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION deedlight_ledger_runner;
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.approve_execution(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.reserve_execution(NULL,NULL,NULL,NULL,NULL)','D1001');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.record_effect_commit_marker(NULL,NULL,NULL)','D1001');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.capture_snapshot(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.start_execution(NULL,NULL,NULL)','D1001');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.heartbeat_execution(NULL,NULL,NULL)','D1001');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.finalize_execution(NULL,NULL,NULL,NULL,NULL)','D1001');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.recover_stale_executions(NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.record_verification(NULL,NULL,NULL,NULL,NULL)','42501');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION deedlight_ledger_observer;
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.approve_execution(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.reserve_execution(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.record_effect_commit_marker(NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.capture_snapshot(NULL,NULL,NULL,NULL,NULL)','D1001');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.start_execution(NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.heartbeat_execution(NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.finalize_execution(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.recover_stale_executions(NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.record_verification(NULL,NULL,NULL,NULL,NULL)','42501');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION deedlight_ledger_recovery;
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.approve_execution(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.reserve_execution(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.record_effect_commit_marker(NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.capture_snapshot(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.start_execution(NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.heartbeat_execution(NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.finalize_execution(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.recover_stale_executions(NULL,NULL)','D1001');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.record_verification(NULL,NULL,NULL,NULL,NULL)','42501');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION deedlight_ledger_verifier;
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.approve_execution(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.reserve_execution(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.record_effect_commit_marker(NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.capture_snapshot(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.start_execution(NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.heartbeat_execution(NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.finalize_execution(NULL,NULL,NULL,NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.recover_stale_executions(NULL,NULL)','42501');
SELECT c603_test.assert_rejected('SELECT deedlight_execution_ledger.record_verification(NULL,NULL,NULL,NULL,NULL)','D1001');
RESET SESSION AUTHORIZATION;

DO $side_effects$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM c603_before b
  WHERE b.approvals=(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.approvals t)
    AND b.executions=(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.executions t)
    AND b.snapshots=(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.snapshots t)
    AND b.markers=(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.execution_commit_markers t)
    AND b.verifications=(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.verification_events t)
    AND b.nonces=(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.authorization_nonces t)
 ) THEN RAISE EXCEPTION 'C603 rejected requests caused protected side effects'; END IF;
END
$side_effects$;
SELECT 'C603_5X9_ADVERSARIAL_MATRIX_ZERO_SIDE_EFFECTS_PASS' AS evidence;

-- Role impersonation must fail for an authenticated actor principal.
DO $membership$
BEGIN
 IF pg_catalog.pg_has_role('deedlight_ledger_approver','deedlight_ledger_runner','MEMBER')
   OR pg_catalog.pg_has_role('deedlight_ledger_runner','deedlight_ledger_approver','MEMBER')
   OR pg_catalog.pg_has_role('deedlight_ledger_observer','deedlight_ledger_runner','MEMBER')
   OR pg_catalog.pg_has_role('deedlight_ledger_recovery','deedlight_ledger_verifier','MEMBER') THEN
   RAISE EXCEPTION 'C603 actor-to-actor SET ROLE membership exists';
 END IF;
END
$membership$;
SELECT 'C603_CROSS_ROLE_SET_ROLE_MEMBERSHIP_DENIED_PASS' AS evidence;

-- Old unwrapped signatures are gone; internal implementation names are not executable by actors.
DO $legacy$
BEGIN
 IF pg_catalog.to_regprocedure('deedlight_execution_ledger.approve_execution(uuid,uuid,uuid,jsonb)') IS NOT NULL
  OR pg_catalog.to_regprocedure('deedlight_execution_ledger.reserve_execution(uuid,uuid,uuid,jsonb)') IS NOT NULL
  OR pg_catalog.to_regprocedure('deedlight_execution_ledger.record_effect_commit_marker(uuid,jsonb)') IS NOT NULL
  OR pg_catalog.to_regprocedure('deedlight_execution_ledger.capture_snapshot(uuid,text,text)') IS NOT NULL
  OR pg_catalog.to_regprocedure('deedlight_execution_ledger.start_execution(uuid)') IS NOT NULL
  OR pg_catalog.to_regprocedure('deedlight_execution_ledger.heartbeat_execution(uuid)') IS NOT NULL
  OR pg_catalog.to_regprocedure('deedlight_execution_ledger.finalize_execution(uuid,text,jsonb)') IS NOT NULL
  OR pg_catalog.to_regprocedure('deedlight_execution_ledger.recover_stale_executions(interval)') IS NOT NULL
  OR pg_catalog.to_regprocedure('deedlight_execution_ledger.record_verification(uuid,text,jsonb)') IS NOT NULL THEN
  RAISE EXCEPTION 'C603 legacy unwrapped RPC signature remains exposed';
 END IF;
END
$legacy$;

-- Cryptographic adversarial checks: replay, request substitution, wrong actor,
-- resource substitution and invalid signature. Each must fail before a nonce or
-- ledger row is accepted.
CREATE TEMP TABLE c603_adversarial_before AS
SELECT
 (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.approvals t) approvals,
 (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.executions t) executions,
 (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.snapshots t) snapshots,
 (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.execution_commit_markers t) markers,
 (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.verification_events t) verifications,
 (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.authorization_nonces t) nonces;

SET SESSION AUTHORIZATION deedlight_ledger_approver;
SELECT c603_test.assert_rejected(
 format('SELECT deedlight_execution_ledger.approve_execution(%L,%L,%L,%L::jsonb,%L::jsonb)',
  'c6030000-0000-4000-8000-000000000001','c6030000-0000-4000-8000-000000000011',
  'c6030000-0000-4000-8000-000000000021',
  '{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}',
  :'approval_auth'),
 'D1005');
SELECT c603_test.assert_rejected(
 format('SELECT deedlight_execution_ledger.approve_execution(%L,%L,%L,%L::jsonb,%L::jsonb)',
  'c6030000-0000-4000-8000-000000000003','c6030000-0000-4000-8000-000000000013',
  'c6030000-0000-4000-8000-000000000023',
  '{"path":"supabase/migrations/substituted.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}',
  :'approval_auth'),
 'D1001');
RESET SESSION AUTHORIZATION;

SELECT pg_temp.c603_sign('deedlight_ledger_runner','reserve_execution',
 'c6030000-0000-4000-8000-000000000021',
 pg_catalog.jsonb_build_object('approvalId','c6030000-0000-4000-8000-000000000001'::uuid,
 'recordId','c6030000-0000-4000-8000-000000000011'::uuid,
 'executionId','c6030000-0000-4000-8000-000000000021'::uuid,
 'sourceIdentity','{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb)
) || pg_catalog.jsonb_build_object('signature',repeat('0',64)) AS bad_signature_auth \gset
SET SESSION AUTHORIZATION deedlight_ledger_runner;
SELECT c603_test.assert_rejected(
 format('SELECT deedlight_execution_ledger.reserve_execution(%L,%L,%L,%L::jsonb,%L::jsonb)',
  'c6030000-0000-4000-8000-000000000001','c6030000-0000-4000-8000-000000000011',
  'c6030000-0000-4000-8000-000000000021',
  '{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}',
  :'approval_auth'),
 'D1001');
SELECT c603_test.assert_rejected(
 format('SELECT deedlight_execution_ledger.reserve_execution(%L,%L,%L,%L::jsonb,%L::jsonb)',
  'c6030000-0000-4000-8000-000000000001','c6030000-0000-4000-8000-000000000011',
  'c6030000-0000-4000-8000-000000000021',
  '{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}',
  :'bad_signature_auth'),
 'D1001');
SELECT c603_test.assert_rejected(
 format('SELECT deedlight_execution_ledger.reserve_execution(%L,%L,%L,%L::jsonb,%L::jsonb)',
  'c6030000-0000-4000-8000-000000000001','c6030000-0000-4000-8000-000000000011',
  'c6030000-0000-4000-8000-000000000021',
  '{"path":"supabase/migrations/c603-positive.sql","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}',
  :'approval_auth'),
 'D1001');
RESET SESSION AUTHORIZATION;

DO $adversarial_side_effects$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM c603_adversarial_before b
  WHERE b.approvals=(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.approvals t)
    AND b.executions=(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.executions t)
    AND b.snapshots=(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.snapshots t)
    AND b.markers=(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.execution_commit_markers t)
    AND b.verifications=(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.verification_events t)
    AND b.nonces=(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM deedlight_execution_ledger.authorization_nonces t)
 ) THEN RAISE EXCEPTION 'C603 cryptographic rejection changed protected state'; END IF;
END
$adversarial_side_effects$;
SELECT 'C603_SIGNATURE_REPLAY_BINDING_ZERO_SIDE_EFFECTS_PASS' AS evidence;

SELECT 'C603_LEGACY_UNWRAPPED_RPC_SIGNATURES_REMOVED_PASS' AS evidence;


DROP SCHEMA c603_test CASCADE;
