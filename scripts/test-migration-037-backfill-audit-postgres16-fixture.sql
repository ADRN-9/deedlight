-- Disposable PostgreSQL 16 fixture only. Never run against Production.
\getenv fixture_authorization DEEDLIGHT_DISPOSABLE_FIXTURE_AUTHORIZATION
\getenv fixture_expected_server_addr DEEDLIGHT_EXPECTED_SERVER_ADDR
\getenv fixture_unauthorized_password DEEDLIGHT_BACKFILL_UNAUTHORIZED_PASSWORD
\if :{?fixture_authorization}
\else
\echo 'FAIL: disposable fixture authorization missing'
SELECT 1 / 0;
\endif
SELECT pg_catalog.set_config('deedlight.fixture_authorization', :'fixture_authorization', false);
SELECT pg_catalog.set_config('deedlight.fixture_expected_server_addr', :'fixture_expected_server_addr', false);
DO $guard$
BEGIN
  IF current_setting('deedlight.fixture_authorization', true) IS DISTINCT FROM 'deedlight-postgres16-ci-disposable-v1'
    OR current_database() <> 'deedlight_migration037_test'
    OR session_user <> 'postgres'
    OR current_setting('server_version_num')::integer / 10000 <> 16
    OR host(inet_server_addr()) IS DISTINCT FROM current_setting('deedlight.fixture_expected_server_addr', true)
    OR inet_server_port() <> 5432 THEN
    RAISE EXCEPTION 'Refusing fixture setup outside the authorized PostgreSQL 16 disposable endpoint.';
  END IF;
END;
$guard$;
CREATE ROLE deedlight_backfill_unauthorized LOGIN PASSWORD :'fixture_unauthorized_password'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT;
GRANT USAGE ON SCHEMA public TO deedlight_backfill_unauthorized;
CREATE TABLE public.delivery_provider_events (
  event_id text PRIMARY KEY,
  event_type text NOT NULL,
  provider_email_id text,
  recipient_email text NOT NULL,
  provider_suppression_id text,
  provider_created_at timestamptz,
  bounce_type text,
  failure_class text,
  suppression_reason text,
  suppression_origin text,
  suppression_source_id text,
  suppression_created_at timestamptz,
  payload_fingerprint text
);
CREATE TABLE public.delivery_provider_integrity_anomalies (
  event_id text NOT NULL REFERENCES public.delivery_provider_events(event_id),
  related_event_id text REFERENCES public.delivery_provider_events(event_id),
  anomaly_type text NOT NULL,
  detected_at timestamptz NOT NULL
);
CREATE TABLE public.delivery_provider_integrity_cases (
  conflict_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  recipient_email text NOT NULL,
  anomaly_type text NOT NULL,
  UNIQUE (recipient_email, anomaly_type)
);
CREATE TABLE public.delivery_provider_integrity_conflict_evidence (
  evidence_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  conflict_id bigint NOT NULL REFERENCES public.delivery_provider_integrity_cases(conflict_id),
  recipient_email text NOT NULL,
  event_id text NOT NULL,
  related_event_id text,
  event_type text NOT NULL,
  provider_email_id text,
  provider_suppression_id text,
  provider_created_at timestamptz,
  bounce_type text,
  failure_class text,
  suppression_reason text,
  suppression_origin text,
  suppression_source_id text,
  suppression_created_at timestamptz,
  payload_fingerprint text,
  stored_event_id text NOT NULL,
  stored_recipient_email text NOT NULL,
  evidence_source text NOT NULL,
  observed_at timestamptz NOT NULL
);
INSERT INTO public.delivery_provider_events VALUES
  ('evt-001','email.bounced','provider-001','one@example.invalid',NULL,'2026-11-20T10:00:00Z','Permanent',NULL,NULL,NULL,NULL,NULL,NULL),
  ('evt-002','email.complained','provider-002','two@example.invalid',NULL,'2026-11-20T10:01:00Z',NULL,NULL,NULL,NULL,NULL,NULL,repeat('a',64)),
  ('evt-003','email.bounced','provider-003','two@example.invalid',NULL,'2026-11-20T10:02:00Z','Permanent',NULL,NULL,NULL,NULL,NULL,repeat('b',64));
INSERT INTO public.delivery_provider_integrity_anomalies VALUES
  ('evt-001',NULL,'duplicate_event_id_conflict','2026-11-20T10:00:01Z'),
  ('evt-002',NULL,'contradictory_terminal_outcome','2026-11-20T10:01:01Z'),
  ('evt-003','evt-002','contradictory_terminal_outcome','2026-11-20T10:02:01Z');
INSERT INTO public.delivery_provider_integrity_cases(recipient_email, anomaly_type)
SELECT DISTINCT e.recipient_email, a.anomaly_type
FROM public.delivery_provider_integrity_anomalies a
JOIN public.delivery_provider_events e ON e.event_id = a.event_id;
INSERT INTO public.delivery_provider_integrity_conflict_evidence (
  conflict_id, recipient_email, event_id, related_event_id, event_type,
  provider_email_id, provider_suppression_id, provider_created_at, bounce_type,
  failure_class, suppression_reason, suppression_origin, suppression_source_id,
  suppression_created_at, payload_fingerprint, stored_event_id, stored_recipient_email,
  evidence_source, observed_at
)
SELECT c.conflict_id, e.recipient_email, a.event_id, a.related_event_id, e.event_type,
  e.provider_email_id, e.provider_suppression_id, e.provider_created_at, e.bounce_type,
  e.failure_class, e.suppression_reason, e.suppression_origin, e.suppression_source_id,
  e.suppression_created_at, e.payload_fingerprint, stored.event_id, stored.recipient_email,
  'legacy_anomaly_backfill', a.detected_at
FROM public.delivery_provider_integrity_anomalies a
JOIN public.delivery_provider_events e ON e.event_id = a.event_id
JOIN public.delivery_provider_integrity_cases c
  ON c.recipient_email = e.recipient_email AND c.anomaly_type = a.anomaly_type
JOIN public.delivery_provider_events stored
  ON stored.event_id = coalesce(a.related_event_id, a.event_id)
WHERE a.event_id IN ('evt-001','evt-002');
