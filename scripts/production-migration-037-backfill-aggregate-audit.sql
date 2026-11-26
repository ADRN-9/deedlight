-- DeedLight Migration 037 backfill verification.
-- Human-controlled DBA-only aggregate audit; never run with the catalog collector identity.
-- Reads private rows internally but emits aggregate counts only. It does not prove migration execution provenance.
-- A missing authenticated Migration 037 execution timestamp makes post-migration anomaly scope ambiguous.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '5s';

DO $migration_037_audit_guard$
DECLARE
  v_role_oid oid;
  v_database_owner oid;
  v_is_superuser boolean;
BEGIN
  IF pg_catalog.current_setting('transaction_read_only') <> 'on' THEN
    RAISE EXCEPTION 'Migration 037 backfill audit requires a read-only transaction.';
  END IF;
  IF session_user IS DISTINCT FROM current_user
    OR pg_catalog.current_setting('role', true) IS DISTINCT FROM 'none' THEN
    RAISE EXCEPTION 'Migration 037 backfill audit requires a direct authenticated DBA session without SET ROLE.';
  END IF;
  SELECT oid, rolsuper INTO v_role_oid, v_is_superuser
  FROM pg_catalog.pg_roles WHERE rolname = session_user;
  SELECT datdba INTO v_database_owner
  FROM pg_catalog.pg_database WHERE datname = pg_catalog.current_database();
  IF v_role_oid IS NULL OR NOT (v_is_superuser OR v_role_oid = v_database_owner) THEN
    RAISE EXCEPTION 'Migration 037 backfill audit requires the direct database-owner or superuser identity.';
  END IF;
  IF pg_catalog.to_regclass('public.delivery_provider_integrity_anomalies') IS NULL
    OR pg_catalog.to_regclass('public.delivery_provider_events') IS NULL
    OR pg_catalog.to_regclass('public.delivery_provider_integrity_cases') IS NULL
    OR pg_catalog.to_regclass('public.delivery_provider_integrity_conflict_evidence') IS NULL THEN
    RAISE EXCEPTION 'Migration 037 backfill audit requires all four provider-integrity relations.';
  END IF;
  IF NOT pg_catalog.has_table_privilege(session_user, 'public.delivery_provider_integrity_anomalies', 'SELECT')
    OR NOT pg_catalog.has_table_privilege(session_user, 'public.delivery_provider_events', 'SELECT')
    OR NOT pg_catalog.has_table_privilege(session_user, 'public.delivery_provider_integrity_cases', 'SELECT')
    OR NOT pg_catalog.has_table_privilege(session_user, 'public.delivery_provider_integrity_conflict_evidence', 'SELECT') THEN
    RAISE EXCEPTION 'Migration 037 backfill audit requires SELECT access to its four protected source/target relations.';
  END IF;
END;
$migration_037_audit_guard$;

WITH source_rows AS (
  SELECT
    a.anomaly_type,
    a.event_id,
    a.related_event_id,
    a.detected_at AS observed_at,
    e.recipient_email,
    e.event_type,
    e.provider_email_id,
    e.provider_suppression_id,
    e.provider_created_at,
    e.bounce_type,
    e.failure_class,
    e.suppression_reason,
    e.suppression_origin,
    e.suppression_source_id,
    e.suppression_created_at,
    e.payload_fingerprint,
    stored.event_id AS stored_event_id,
    stored.recipient_email AS stored_recipient_email
  FROM public.delivery_provider_integrity_anomalies a
  LEFT JOIN public.delivery_provider_events e ON e.event_id = a.event_id
  LEFT JOIN public.delivery_provider_events stored
    ON stored.event_id = pg_catalog.coalesce(a.related_event_id, a.event_id)
),
eligible AS (
  SELECT * FROM source_rows
  WHERE recipient_email IS NOT NULL AND stored_event_id IS NOT NULL
),
case_keys AS (
  SELECT DISTINCT recipient_email, anomaly_type FROM eligible
),
missing_cases AS (
  SELECT k.recipient_email, k.anomaly_type
  FROM case_keys k
  LEFT JOIN public.delivery_provider_integrity_cases c
    ON c.recipient_email = k.recipient_email AND c.anomaly_type = k.anomaly_type
  WHERE c.conflict_id IS NULL
),
expected_null_rows AS (
  SELECT * FROM eligible WHERE payload_fingerprint IS NULL
),
actual_all_rows AS (
  SELECT
    c.recipient_email,
    c.anomaly_type,
    e.event_id,
    e.related_event_id,
    e.event_type,
    e.provider_email_id,
    e.provider_suppression_id,
    e.provider_created_at,
    e.bounce_type,
    e.failure_class,
    e.suppression_reason,
    e.suppression_origin,
    e.suppression_source_id,
    e.suppression_created_at,
    e.payload_fingerprint,
    e.stored_event_id,
    e.stored_recipient_email,
    e.observed_at,
    e.evidence_source
  FROM public.delivery_provider_integrity_conflict_evidence e
  JOIN public.delivery_provider_integrity_cases c ON c.conflict_id = e.conflict_id
),
actual_legacy_rows AS (
  SELECT
    recipient_email, anomaly_type, event_id, related_event_id, event_type,
    provider_email_id, provider_suppression_id, provider_created_at, bounce_type,
    failure_class, suppression_reason, suppression_origin, suppression_source_id,
    suppression_created_at, payload_fingerprint, stored_event_id,
    stored_recipient_email, observed_at
  FROM actual_all_rows
  WHERE evidence_source = 'legacy_anomaly_backfill'
),
actual_null_rows AS (
  SELECT * FROM actual_legacy_rows WHERE payload_fingerprint IS NULL
),
missing_null_rows AS (
  SELECT * FROM expected_null_rows
  EXCEPT ALL
  SELECT * FROM actual_null_rows
),
extra_null_rows AS (
  SELECT * FROM actual_null_rows
  EXCEPT ALL
  SELECT * FROM expected_null_rows
),
expected_fingerprint_groups AS (
  SELECT recipient_email, anomaly_type, payload_fingerprint
  FROM eligible
  WHERE payload_fingerprint IS NOT NULL
  GROUP BY recipient_email, anomaly_type, payload_fingerprint
),
actual_fingerprint_groups AS (
  SELECT recipient_email, anomaly_type, payload_fingerprint
  FROM actual_legacy_rows
  WHERE payload_fingerprint IS NOT NULL
  GROUP BY recipient_email, anomaly_type, payload_fingerprint
),
missing_fingerprint_groups AS (
  SELECT * FROM expected_fingerprint_groups
  EXCEPT
  SELECT * FROM actual_fingerprint_groups
),
extra_fingerprint_groups AS (
  SELECT * FROM actual_fingerprint_groups
  EXCEPT
  SELECT * FROM expected_fingerprint_groups
),
fingerprint_variants AS (
  SELECT recipient_email, anomaly_type, payload_fingerprint
  FROM eligible
  WHERE payload_fingerprint IS NOT NULL
  GROUP BY recipient_email, anomaly_type, payload_fingerprint
  HAVING pg_catalog.count(DISTINCT pg_catalog.jsonb_build_array(
    event_id, related_event_id, event_type, provider_email_id, provider_suppression_id,
    provider_created_at, bounce_type, failure_class, suppression_reason, suppression_origin,
    suppression_source_id, suppression_created_at, stored_event_id, stored_recipient_email, observed_at
  )) > 1
),
unmatched_legacy_rows AS (
  SELECT a.*
  FROM actual_legacy_rows a
  WHERE NOT EXISTS (
    SELECT 1 FROM eligible s
    WHERE pg_catalog.to_jsonb(a) = pg_catalog.to_jsonb(s)
  )
),
provider_rpc_only_rows AS (
  SELECT s.event_id, s.related_event_id, s.recipient_email, s.anomaly_type
  FROM eligible s
  WHERE EXISTS (
    SELECT 1 FROM actual_all_rows rpc
    WHERE rpc.evidence_source = 'provider_rpc'
      AND rpc.event_id = s.event_id
      AND rpc.related_event_id IS NOT DISTINCT FROM s.related_event_id
      AND rpc.recipient_email = s.recipient_email
      AND rpc.anomaly_type = s.anomaly_type
  )
  AND NOT EXISTS (
    SELECT 1 FROM actual_legacy_rows legacy
    WHERE legacy.event_id = s.event_id
      AND legacy.related_event_id IS NOT DISTINCT FROM s.related_event_id
      AND legacy.recipient_email = s.recipient_email
      AND legacy.anomaly_type = s.anomaly_type
  )
),
expected_fingerprint_rows AS (
  SELECT DISTINCT ON (recipient_email, anomaly_type, payload_fingerprint) *
  FROM eligible
  WHERE payload_fingerprint IS NOT NULL
  ORDER BY recipient_email, anomaly_type, payload_fingerprint,
    event_id, related_event_id NULLS FIRST, observed_at
),
expected_rows AS (
  SELECT * FROM expected_null_rows
  UNION ALL
  SELECT * FROM expected_fingerprint_rows
),
counts AS (
  SELECT
    (SELECT pg_catalog.count(*) FROM source_rows) AS source_anomaly_count,
    (SELECT pg_catalog.count(*) FROM source_rows WHERE recipient_email IS NULL) AS missing_source_event_count,
    (SELECT pg_catalog.count(*) FROM source_rows WHERE recipient_email IS NOT NULL AND stored_event_id IS NULL) AS missing_stored_event_count,
    (SELECT pg_catalog.count(*) FROM case_keys) AS expected_case_count,
    (SELECT pg_catalog.count(*) FROM missing_cases) AS missing_case_count,
    (SELECT pg_catalog.count(*) FROM expected_rows) AS expected_legacy_evidence_count,
    (SELECT pg_catalog.count(*) FROM actual_legacy_rows) AS actual_legacy_evidence_count,
    (SELECT pg_catalog.count(*) FROM missing_null_rows) AS missing_null_fingerprint_rows,
    (SELECT pg_catalog.count(*) FROM extra_null_rows) AS extra_null_fingerprint_rows,
    (SELECT pg_catalog.count(*) FROM missing_fingerprint_groups) AS missing_fingerprint_groups,
    (SELECT pg_catalog.count(*) FROM extra_fingerprint_groups) AS extra_fingerprint_groups,
    (SELECT pg_catalog.count(*) FROM fingerprint_variants) AS conflicting_fingerprint_groups,
    (SELECT pg_catalog.count(*) FROM unmatched_legacy_rows) AS unmatched_legacy_evidence_rows,
    (SELECT pg_catalog.count(*) FROM provider_rpc_only_rows) AS provider_rpc_only_anomaly_rows
)
SELECT
  'migration_037_backfill_v1' AS evidence_projection,
  c.source_anomaly_count,
  c.missing_source_event_count,
  c.missing_stored_event_count,
  c.expected_case_count,
  c.missing_case_count,
  c.expected_legacy_evidence_count,
  c.actual_legacy_evidence_count,
  c.missing_null_fingerprint_rows,
  c.extra_null_fingerprint_rows,
  c.missing_fingerprint_groups,
  c.extra_fingerprint_groups,
  c.conflicting_fingerprint_groups,
  c.unmatched_legacy_evidence_rows,
  c.provider_rpc_only_anomaly_rows,
  (
    c.missing_source_event_count = 0
    AND c.missing_stored_event_count = 0
    AND c.missing_case_count = 0
    AND c.expected_legacy_evidence_count = c.actual_legacy_evidence_count
    AND c.missing_null_fingerprint_rows = 0
    AND c.extra_null_fingerprint_rows = 0
    AND c.missing_fingerprint_groups = 0
    AND c.extra_fingerprint_groups = 0
    AND c.conflicting_fingerprint_groups = 0
    AND c.unmatched_legacy_evidence_rows = 0
    AND c.provider_rpc_only_anomaly_rows = 0
  ) AS complete
FROM counts c;

ROLLBACK;
