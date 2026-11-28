\set ON_ERROR_STOP on

WITH resource AS (
  SELECT deedlight_execution_ledger.current_database_identity() AS identity
)
INSERT INTO deedlight_execution_ledger.approvals
  (approval_id,system_identifier,database_oid,database_name,record_id,
   execution_id,source_identity,approver_identity)
SELECT 'c6050000-0000-4000-8000-000000000006'::uuid,
  identity->>'systemIdentifier',(identity->>'databaseOid')::oid,
  identity->>'databaseName','c6050000-0000-4000-8000-000000000016'::uuid,
  'c6050000-0000-4000-8000-000000000026'::uuid,
  '{"path":"supabase/migrations/c605-recovery-concurrency.sql","sha256":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}'::jsonb,
  'deedlight_ledger_approver'
FROM resource;

WITH resource AS (
  SELECT deedlight_execution_ledger.current_database_identity() AS identity
)
INSERT INTO deedlight_execution_ledger.executions
  (system_identifier,database_oid,database_name,record_id,execution_id,
   approval_id,source_identity,status,approver_identity,heartbeat_at)
SELECT identity->>'systemIdentifier',(identity->>'databaseOid')::oid,
  identity->>'databaseName','c6050000-0000-4000-8000-000000000016'::uuid,
  'c6050000-0000-4000-8000-000000000026'::uuid,
  'c6050000-0000-4000-8000-000000000006'::uuid,
  '{"path":"supabase/migrations/c605-recovery-concurrency.sql","sha256":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}'::jsonb,
  'reserved','deedlight_ledger_approver',
  pg_catalog.clock_timestamp()-interval '1 hour'
FROM resource;

SELECT 'C605_RECOVERY_CONCURRENCY_FIXTURE_READY' AS evidence;
