-- C73 nonproduction integration overlay. Apply AFTER authentic 025-028 and C61 registry 029.
-- The registry and keyring deliberately remain disabled/locked on installation.
-- No Production application, CLI migration history, email or Cron is authorized.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '45s';

DO $preflight$
BEGIN
  IF to_regclass('deedlight_event_private.provider_event_registry') IS NULL
    OR to_regclass('deedlight_event_private.registry_control') IS NULL
    OR to_regclass('public.delivery_provider_pending_events') IS NULL
    OR to_regclass('public.delivery_provider_identity_conflicts') IS NULL
    OR to_regclass('public.delivery_provider_events') IS NULL
    OR to_regclass('public.delivery_recipient_state') IS NULL
    OR to_regprocedure('public.begin_delivery_transport_identity_bound(uuid,uuid,text)') IS NULL
    OR to_regprocedure('public.mark_delivery_sent_identity_bound(uuid,uuid,text)') IS NULL
    OR to_regprocedure('public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)') IS NULL
    OR to_regprocedure('public.claim_delivery_jobs(timestamptz,integer)') IS NOT NULL
    OR to_regprocedure('public.claim_delivery_jobs(text,timestamptz,integer)') IS NULL THEN
    RAISE EXCEPTION 'C73 requires exact 025-029 source graph and no unscoped claim' USING ERRCODE='55000';
  END IF;
  IF (SELECT accepting_new_events FROM deedlight_event_private.registry_control WHERE singleton) IS DISTINCT FROM false
    OR EXISTS (SELECT 1 FROM deedlight_event_private.provider_event_registry) THEN
    RAISE EXCEPTION 'C73 event registry already active or populated; reconcile manually' USING ERRCODE='55000';
  END IF;
END
$preflight$;

-- A provider-suppressed recipient is never implicitly unsuppressed by any legacy
-- informational event. The pending flag is also pinned to true so the unmodified
-- 028 transport RPC sees and rejects this condition across active/legacy HMAC keys.
ALTER TABLE public.delivery_recipient_state
  ADD COLUMN provider_suppressed boolean NOT NULL DEFAULT false;
CREATE FUNCTION deedlight_event_private.preserve_provider_suppression()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  IF TG_OP='UPDATE' AND OLD.provider_suppressed AND NOT NEW.provider_suppressed THEN
    RAISE EXCEPTION 'Provider suppression cannot be cleared by webhook processing' USING ERRCODE='42501';
  END IF;
  IF NEW.provider_suppressed THEN NEW.pending_unmatched:=true; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER c73_preserve_provider_suppression
  BEFORE INSERT OR UPDATE ON public.delivery_recipient_state
  FOR EACH ROW EXECUTE FUNCTION deedlight_event_private.preserve_provider_suppression();
ALTER TABLE public.delivery_recipient_state ENABLE ALWAYS TRIGGER c73_preserve_provider_suppression;
REVOKE ALL ON FUNCTION deedlight_event_private.preserve_provider_suppression() FROM PUBLIC,anon,authenticated,service_role;

-- Every legacy event row has to be backed by an immutable registry identity.
-- This applies inside definer-owned functions as well as direct SQL writes.
CREATE FUNCTION deedlight_event_private.guard_legacy_event_row()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_rec deedlight_event_private.provider_event_registry%ROWTYPE;
BEGIN
  IF TG_OP='DELETE' THEN
    IF TG_TABLE_NAME='delivery_provider_pending_events'
      AND EXISTS (SELECT 1 FROM public.delivery_provider_events e
        WHERE e.svix_event_id=OLD.svix_event_id) THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'Legacy event deletion is forbidden' USING ERRCODE='42501';
  END IF;
  IF TG_OP='UPDATE' THEN
    RAISE EXCEPTION 'Legacy event identity rows are immutable' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_rec FROM deedlight_event_private.provider_event_registry
  WHERE provider='resend' AND event_id=NEW.svix_event_id FOR KEY SHARE;
  IF NOT FOUND OR v_rec.state='identity_conflict' THEN
    -- Conflicts are only allowed in the dedicated quarantine table.
    IF TG_TABLE_NAME<>'delivery_provider_identity_conflicts' THEN
      RAISE EXCEPTION 'Legacy provider event requires registry reservation' USING ERRCODE='42501';
    END IF;
  END IF;
  IF NOT FOUND OR (v_rec.provider_message_id IS DISTINCT FROM NEW.provider_email_id)
    OR (v_rec.payload_sha256 IS DISTINCT FROM decode(NEW.payload_sha256,'hex')) THEN
    RAISE EXCEPTION 'Legacy provider event does not match global registry' USING ERRCODE='42501';
  END IF;
  IF TG_TABLE_NAME<>'delivery_provider_identity_conflicts' THEN
    IF v_rec.event_type IS DISTINCT FROM NEW.event_type THEN
      RAISE EXCEPTION 'Legacy provider event type conflicts with global identity' USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE FUNCTION deedlight_event_private.reject_legacy_event_truncate()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  RAISE EXCEPTION 'Legacy event TRUNCATE is forbidden' USING ERRCODE='42501';
END $$;
REVOKE ALL ON FUNCTION deedlight_event_private.guard_legacy_event_row() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION deedlight_event_private.reject_legacy_event_truncate() FROM PUBLIC,anon,authenticated,service_role;
DO $triggers$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['delivery_provider_events', 'delivery_provider_pending_events', 'delivery_provider_identity_conflicts'] LOOP
    EXECUTE format('CREATE TRIGGER c73_registry_guard BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION deedlight_event_private.guard_legacy_event_row()',v_table);
    EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER c73_registry_guard',v_table);
    EXECUTE format('CREATE TRIGGER c73_no_truncate BEFORE TRUNCATE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION deedlight_event_private.reject_legacy_event_truncate()',v_table);
    EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER c73_no_truncate',v_table);
  END LOOP;
END $triggers$;

-- Do not accept event ingestion until every historical legacy svix_event_id is
-- collision-free and represented in the sole authoritative registry.
CREATE FUNCTION deedlight_event_private.guard_registry_enablement()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  IF NEW.accepting_new_events AND NOT OLD.accepting_new_events THEN
    IF NEW.reconciled_at IS NULL OR NEW.reconciled_evidence IS NULL
      OR NOT EXISTS (SELECT 1 FROM deedlight_private.delivery_recipient_key_control
        WHERE singleton AND mode='ready')
      OR EXISTS (
        SELECT svix_event_id FROM (
          SELECT svix_event_id FROM public.delivery_provider_events
          UNION ALL SELECT svix_event_id FROM public.delivery_provider_pending_events
          UNION ALL SELECT svix_event_id FROM public.delivery_provider_identity_conflicts
        ) historic GROUP BY svix_event_id HAVING count(*)>1
      ) OR EXISTS (
        SELECT 1 FROM public.delivery_provider_events e LEFT JOIN deedlight_event_private.provider_event_registry r
          ON r.provider='resend' AND r.event_id=e.svix_event_id
        WHERE r.event_id IS NULL OR r.provider_message_id IS DISTINCT FROM e.provider_email_id
          OR r.event_type IS DISTINCT FROM e.event_type OR r.payload_sha256 IS DISTINCT FROM decode(e.payload_sha256,'hex')
      ) OR EXISTS (
        SELECT 1 FROM public.delivery_provider_pending_events e LEFT JOIN deedlight_event_private.provider_event_registry r
          ON r.provider='resend' AND r.event_id=e.svix_event_id
        WHERE r.event_id IS NULL OR r.provider_message_id IS DISTINCT FROM e.provider_email_id
          OR r.event_type IS DISTINCT FROM e.event_type OR r.payload_sha256 IS DISTINCT FROM decode(e.payload_sha256,'hex')
      ) OR EXISTS (
        SELECT 1 FROM public.delivery_provider_identity_conflicts e LEFT JOIN deedlight_event_private.provider_event_registry r
          ON r.provider='resend' AND r.event_id=e.svix_event_id
        WHERE r.event_id IS NULL OR r.state<>'identity_conflict'
          OR r.provider_message_id IS DISTINCT FROM e.provider_email_id
          OR r.payload_sha256 IS DISTINCT FROM decode(e.payload_sha256,'hex')
      ) THEN
      RAISE EXCEPTION 'Global event identity and keyring reconciliation incomplete' USING ERRCODE='55000';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER c73_registry_enablement
  BEFORE UPDATE ON deedlight_event_private.registry_control
  FOR EACH ROW EXECUTE FUNCTION deedlight_event_private.guard_registry_enablement();
ALTER TABLE deedlight_event_private.registry_control ENABLE ALWAYS TRIGGER c73_registry_enablement;
REVOKE ALL ON FUNCTION deedlight_event_private.guard_registry_enablement() FROM PUBLIC,anon,authenticated,service_role;

-- An authorized send must have a healthy global webhook lifecycle. Throwing
-- here rolls back 028's earlier transport_started_at write atomically.
CREATE FUNCTION deedlight_event_private.guard_transport_intent()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_hold boolean; v_pending boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM deedlight_event_private.registry_control c
    WHERE c.singleton AND c.accepting_new_events AND c.reconciled_at IS NOT NULL
      AND c.reconciled_evidence IS NOT NULL FOR SHARE) THEN
    RAISE EXCEPTION 'Delivery disabled until provider event registry is reconciled' USING ERRCODE='42501';
  END IF;
  SELECT provider_suppressed,pending_unmatched INTO v_hold,v_pending
    FROM public.delivery_recipient_state WHERE recipient_fingerprint=NEW.recipient_fingerprint FOR UPDATE;
  IF NOT FOUND OR v_hold OR v_pending THEN
    RAISE EXCEPTION 'Recipient has unresolved provider safety hold' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER c73_transport_safety
  BEFORE INSERT OR UPDATE ON public.delivery_transport_intents
  FOR EACH ROW EXECUTE FUNCTION deedlight_event_private.guard_transport_intent();
ALTER TABLE public.delivery_transport_intents ENABLE ALWAYS TRIGGER c73_transport_safety;
REVOKE ALL ON FUNCTION deedlight_event_private.guard_transport_intent() FROM PUBLIC,anon,authenticated,service_role;

-- Public service-role RPC accepting ONLY verified metadata from the server's
-- raw-body Svix signature verifier. The database never trusts caller-provided
-- fingerprints; they are derived from active AND legacy DB keys.
CREATE FUNCTION public.deedlight_record_resend_verified(
  p_event_id text,p_provider_email_id text,p_recipient_email text,
  p_event_type text,p_event_at timestamptz,p_payload_sha256 text,
  p_suppression_reason text DEFAULT NULL
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $handler$
DECLARE v_r record; v_known text; v_actual text; v_active text;
        v_reserved text; v_result text; v_job uuid; v_id text;
BEGIN
  IF p_event_id IS NULL OR p_event_id !~ '^msg_[A-Za-z0-9_-]{6,180}$'
    OR p_provider_email_id IS NULL OR length(p_provider_email_id) NOT BETWEEN 1 AND 255
    OR p_recipient_email IS NULL OR length(p_recipient_email) NOT BETWEEN 3 AND 320
    OR p_event_at IS NULL OR p_payload_sha256 IS NULL OR p_payload_sha256 !~ '^[0-9a-f]{64}$'
    OR p_event_type NOT IN ('email.sent','email.delivered','email.delivery_delayed','email.failed',
      'email.bounced','email.complained','email.suppressed')
    OR (p_event_type='email.complained' AND p_suppression_reason IS DISTINCT FROM 'spam_complaint')
    OR (p_suppression_reason IS NOT NULL AND NOT (
      (p_suppression_reason='spam_complaint' AND p_event_type='email.complained')
      OR (p_suppression_reason='permanent_bounce' AND p_event_type='email.bounced'))) THEN
    RAISE EXCEPTION 'Invalid authenticated provider event metadata' USING ERRCODE='22023';
  END IF;
  -- Obtain optional preexisting association before recipient locks. A later
  -- authoritative FOR UPDATE rechecks it and fails on concurrent remapping.
  SELECT s.recipient_fingerprint INTO v_known FROM public.delivery_provider_submissions s
    WHERE s.provider_email_id=p_provider_email_id;
  -- Lock all impacted recipients in stable order to serialize with 028 transport.
  FOR v_r IN SELECT DISTINCT fingerprint FROM (
    SELECT f.fingerprint FROM deedlight_private.recipient_fingerprints(p_recipient_email) f
    UNION ALL SELECT v_known WHERE v_known IS NOT NULL
  ) k ORDER BY fingerprint LOOP
    INSERT INTO public.delivery_recipient_state(recipient_fingerprint)
      VALUES(v_r.fingerprint) ON CONFLICT DO NOTHING;
    PERFORM 1 FROM public.delivery_recipient_state s
      WHERE s.recipient_fingerprint=v_r.fingerprint FOR UPDATE;
  END LOOP;
  SELECT f.fingerprint INTO v_active FROM deedlight_private.recipient_fingerprints(p_recipient_email) f
    WHERE f.phase='active';
  IF v_active IS NULL THEN RAISE EXCEPTION 'Missing active recipient key' USING ERRCODE='42501'; END IF;

  v_reserved:=public.deedlight_reserve_provider_event('resend',p_event_id,
    decode(p_payload_sha256,'hex'),p_event_type,p_provider_email_id);
  IF v_reserved IN ('IDENTITY_CONFLICT','QUARANTINED') THEN
    -- A contradictory signed retry is quarantined and freezes the original
    -- associated recipient until independent incident reconciliation.
    IF v_known IS NOT NULL THEN
      UPDATE public.delivery_recipient_state SET pending_unmatched=true,
        updated_at=clock_timestamp() WHERE recipient_fingerprint=v_known;
    END IF;
    RETURN 'quarantined';
  END IF;
  IF v_reserved='DUPLICATE_PROCESSED' THEN RETURN 'duplicate'; END IF;

  SELECT s.recipient_fingerprint,s.job_id INTO v_actual,v_job
    FROM public.delivery_provider_submissions s WHERE s.provider_email_id=p_provider_email_id FOR UPDATE;
  IF FOUND AND (v_known IS DISTINCT FROM v_actual OR NOT EXISTS (
    SELECT 1 FROM deedlight_private.recipient_fingerprints(p_recipient_email) f
      WHERE f.fingerprint=v_actual)) THEN
    UPDATE deedlight_event_private.provider_event_registry SET state='identity_conflict',
      updated_at=clock_timestamp() WHERE provider='resend' AND event_id=p_event_id;
    INSERT INTO deedlight_event_private.provider_event_quarantine
      (provider,event_id,reason,conflicting_sha256)
    VALUES ('resend',p_event_id,'changed_provider_delivery_binding',decode(p_payload_sha256,'hex'))
    ON CONFLICT DO NOTHING;
    INSERT INTO public.delivery_provider_identity_conflicts
      (svix_event_id,provider_email_id,original_recipient_fingerprint,
       signed_recipient_fingerprint,payload_sha256)
    VALUES (p_event_id,p_provider_email_id,v_actual,v_active,p_payload_sha256)
    ON CONFLICT DO NOTHING;
    UPDATE public.delivery_recipient_state SET pending_unmatched=true,
      updated_at=clock_timestamp() WHERE recipient_fingerprint=v_actual;
    RETURN 'quarantined';
  END IF;

  -- The exact 027 recorder is internal only; an ENABLE ALWAYS trigger requires
  -- the earlier global reservation for any event-table write.
  v_result:=public.record_resend_webhook_event(p_event_id,p_provider_email_id,
    coalesce(v_actual,v_active),p_event_type,p_event_at,p_payload_sha256,p_suppression_reason);
  IF v_result NOT IN ('recorded','pending','duplicate') THEN
    RAISE EXCEPTION 'Unexpected provider event state' USING ERRCODE='55000';
  END IF;
  IF v_result='pending' OR (v_result='duplicate' AND v_job IS NULL) THEN
    RETURN 'pending';
  END IF;
  IF p_event_type='email.suppressed' THEN
    -- Account-level suppression must block all key versions permanently.
    FOR v_r IN SELECT fingerprint FROM deedlight_private.recipient_fingerprints(p_recipient_email) LOOP
      UPDATE public.delivery_recipient_state
        SET provider_suppressed=true,pending_unmatched=true,updated_at=clock_timestamp()
        WHERE recipient_fingerprint=v_r.fingerprint;
    END LOOP;
  END IF;
  -- A previously unmatched event may be promoted by a second verified POST
  -- after the provider submission appears. Remove the old pending projection
  -- atomically; one global registry row remains the identity authority.
  DELETE FROM public.delivery_provider_pending_events
    WHERE svix_event_id=p_event_id AND provider_email_id=p_provider_email_id;
  IF v_actual IS NOT NULL THEN
    UPDATE public.delivery_recipient_state s
      SET pending_unmatched=s.provider_suppressed OR EXISTS (
          SELECT 1 FROM public.delivery_provider_pending_events e
            WHERE e.recipient_fingerprint=s.recipient_fingerprint),
          updated_at=clock_timestamp()
      WHERE s.recipient_fingerprint=v_actual;
  END IF;
  UPDATE deedlight_event_private.provider_event_registry
    SET state='processed',bound_delivery_id=v_job,updated_at=clock_timestamp()
    WHERE provider='resend' AND event_id=p_event_id;
  RETURN CASE WHEN v_result='duplicate' THEN 'duplicate' ELSE 'recorded' END;
END $handler$;
REVOKE ALL ON FUNCTION public.deedlight_record_resend_verified(text,text,text,text,timestamptz,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.deedlight_record_resend_verified(text,text,text,text,timestamptz,text,text)
  TO service_role;

-- A pending webhook may be promoted during 027's mark-sent transaction.
-- No second event identity is minted: only the existing registry row advances.
CREATE FUNCTION deedlight_event_private.promote_legacy_pending()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_job uuid;
BEGIN
  SELECT e.job_id INTO v_job FROM public.delivery_provider_events e
    WHERE e.svix_event_id=OLD.svix_event_id;
  IF FOUND THEN
    UPDATE deedlight_event_private.provider_event_registry
      SET state='processed',bound_delivery_id=v_job,updated_at=clock_timestamp()
      WHERE provider='resend' AND event_id=OLD.svix_event_id AND state='pending';
  END IF;
  RETURN OLD;
END $$;
CREATE TRIGGER c73_promote_pending
  AFTER DELETE ON public.delivery_provider_pending_events
  FOR EACH ROW EXECUTE FUNCTION deedlight_event_private.promote_legacy_pending();
ALTER TABLE public.delivery_provider_pending_events ENABLE ALWAYS TRIGGER c73_promote_pending;
REVOKE ALL ON FUNCTION deedlight_event_private.promote_legacy_pending() FROM PUBLIC,anon,authenticated,service_role;


-- A pending provider-suppressed event promoted during mark-sent must retain
-- its permanent recipient hold; the old 027 recorder lacks this distinction.
CREATE FUNCTION deedlight_event_private.propagate_provider_suppressed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  IF NEW.event_type='email.suppressed' THEN
    UPDATE public.delivery_recipient_state
      SET provider_suppressed=true,pending_unmatched=true,updated_at=clock_timestamp()
      WHERE recipient_fingerprint=NEW.recipient_fingerprint;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Suppressed recipient state not locked' USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER c73_suppressed_event
  AFTER INSERT ON public.delivery_provider_events
  FOR EACH ROW EXECUTE FUNCTION deedlight_event_private.propagate_provider_suppressed();
ALTER TABLE public.delivery_provider_events ENABLE ALWAYS TRIGGER c73_suppressed_event;
REVOKE ALL ON FUNCTION deedlight_event_private.propagate_provider_suppressed() FROM PUBLIC,anon,authenticated,service_role;

-- Retire every callable predecessor. Definer-owned bodies retain the safe
-- internal 027 function only through the newly reserved registry identity.
REVOKE ALL ON FUNCTION public.deedlight_reserve_provider_event(text,text,bytea,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.deedlight_bind_provider_event(text,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.deedlight_process_nonsuppressing_event(text,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.begin_delivery_transport(uuid,uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.begin_delivery_transport_with_suppression(uuid,uuid,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.mark_delivery_sent(uuid,uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.mark_delivery_sent_with_recipient(uuid,uuid,text,text)
  FROM PUBLIC,anon,authenticated,service_role;

-- Even a definer-owned caller must never be able to bypass registry handling
-- via the old exported identity-bound webhook path. No permissive fallback.
CREATE OR REPLACE FUNCTION public.record_resend_webhook_event_identity_bound(
  p_event_id text,p_provider_email_id text,p_recipient_email text,
  p_event_type text,p_event_at timestamptz,p_payload_sha256 text,p_suppression_reason text DEFAULT NULL
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  RAISE EXCEPTION 'Legacy webhook identity entry point disabled; use global registry' USING ERRCODE='42501';
END $$;
REVOKE ALL ON FUNCTION public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
