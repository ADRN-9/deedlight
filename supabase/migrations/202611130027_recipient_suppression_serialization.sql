-- REVIEW ONLY: proposed forward-only follow-on to isolated C44 migration 025.
-- NOT authorized for Production; version must be allocated by the exclusive Developer.
-- The migration does NOT install a webhook signing key or change any member preferences.
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.delivery_ledger') IS NULL
    OR to_regclass('public.delivery_provider_submissions') IS NULL
    OR to_regclass('public.delivery_provider_events') IS NULL
    OR to_regclass('public.delivery_recipient_suppressions') IS NULL
    OR to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') IS NULL
    OR to_regprocedure('public.claim_delivery_jobs(text,timestamptz,integer)') IS NULL
    OR to_regprocedure('public.claim_delivery_jobs(timestamptz,integer)') IS NOT NULL
    OR to_regprocedure('public.mark_delivery_sent_with_recipient(uuid,uuid,text,text)') IS NULL
    OR to_regprocedure('public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)') IS NULL
    OR to_regclass('public.delivery_recipient_state') IS NOT NULL
    OR to_regclass('public.delivery_provider_pending_events') IS NOT NULL
  THEN
    RAISE EXCEPTION 'C45 requires the exact 025 kind-scope + 026 lifecycle schema and an unapplied C45 state.';
  END IF;
END
$$;

-- An existing row is created even for an UNSUPPRESSED recipient.
-- This is the stable row that both transport authorization and webhook mutation lock.
CREATE TABLE public.delivery_recipient_state (
  recipient_fingerprint text PRIMARY KEY
    CHECK (recipient_fingerprint ~ '^[0-9a-f]{64}$'),
  suppression_reason text
    CHECK (suppression_reason IN ('permanent_bounce', 'spam_complaint')),
  suppressed_at timestamptz,
  pending_unmatched boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT recipient_suppression_consistency CHECK
    ((suppression_reason IS NULL AND suppressed_at IS NULL)
      OR (suppression_reason IS NOT NULL AND suppressed_at IS NOT NULL))
);

-- Authenticated event arrives before the HTTP sender records provider_result_id:
-- persist the signed event's minimal verified fields, then reconcile in the same
-- transaction that inserts the immutable submission association.
CREATE TABLE public.delivery_provider_pending_events (
  svix_event_id text PRIMARY KEY CHECK (svix_event_id ~ '^msg_[A-Za-z0-9_-]{6,180}$'),
  provider_email_id text NOT NULL CHECK (char_length(provider_email_id) BETWEEN 1 AND 255),
  recipient_fingerprint text NOT NULL CHECK (recipient_fingerprint ~ '^[0-9a-f]{64}$'),
  event_type text NOT NULL CHECK (event_type IN (
    'email.sent','email.delivered','email.delivery_delayed','email.failed',
    'email.bounced','email.complained','email.suppressed'
  )),
  event_at timestamptz NOT NULL,
  payload_sha256 text NOT NULL CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
  suppression_reason text CHECK (suppression_reason IN ('permanent_bounce','spam_complaint')),
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT pending_event_reason_consistency CHECK (
    (suppression_reason IS DISTINCT FROM 'spam_complaint' OR event_type='email.complained')
    AND (suppression_reason IS DISTINCT FROM 'permanent_bounce' OR event_type='email.bounced')
  )
);
CREATE INDEX delivery_provider_pending_lookup_idx
  ON public.delivery_provider_pending_events(provider_email_id, recipient_fingerprint, event_at);

ALTER TABLE public.delivery_recipient_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_provider_pending_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.delivery_recipient_state FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.delivery_provider_pending_events FROM PUBLIC, anon, authenticated, service_role;

-- Preserve every suppression already recorded under C44 (a forward-only backfill).
INSERT INTO public.delivery_recipient_state
  (recipient_fingerprint,suppression_reason,suppressed_at)
SELECT recipient_fingerprint,reason,created_at
FROM public.delivery_recipient_suppressions;

-- With the row locked, every successful event transition is atomic and monotonic.
-- The provider event has been verified by the server BEFORE this RPC is called.
CREATE OR REPLACE FUNCTION public.record_resend_webhook_event(
  p_event_id text,
  p_provider_email_id text,
  p_recipient_fingerprint text,
  p_event_type text,
  p_event_at timestamptz,
  p_payload_sha256 text,
  p_suppression_reason text DEFAULT NULL
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_sub public.delivery_provider_submissions%rowtype;
  v_existing public.delivery_provider_events%rowtype;
  v_pending public.delivery_provider_pending_events%rowtype;
  v_inserted text;
  v_next_state text;
BEGIN
  IF p_event_id IS NULL OR p_event_id !~ '^msg_[A-Za-z0-9_-]{6,180}$'
    OR p_provider_email_id IS NULL OR char_length(p_provider_email_id) NOT BETWEEN 1 AND 255
    OR nullif(btrim(p_provider_email_id),'') IS NULL
    OR p_recipient_fingerprint IS NULL OR p_recipient_fingerprint !~ '^[0-9a-f]{64}$'
    OR p_payload_sha256 IS NULL OR p_payload_sha256 !~ '^[0-9a-f]{64}$'
    OR p_event_at IS NULL
    OR p_event_type IS NULL OR p_event_type NOT IN (
      'email.sent','email.delivered','email.delivery_delayed','email.failed',
      'email.bounced','email.complained','email.suppressed')
    OR (p_suppression_reason IS NOT NULL AND
      ((p_suppression_reason='permanent_bounce' AND p_event_type<>'email.bounced')
      OR (p_suppression_reason='spam_complaint' AND p_event_type<>'email.complained')
      OR p_suppression_reason NOT IN ('permanent_bounce','spam_complaint')))
    OR (p_event_type='email.complained'
      AND p_suppression_reason IS DISTINCT FROM 'spam_complaint')
  THEN
    RAISE EXCEPTION 'Invalid verified webhook event.' USING ERRCODE='22023';
  END IF;

  -- Acquire in the same order as final transport and provider-result recording.
  -- INSERT handles the absent-row case; SELECT FOR UPDATE serializes both flows.
  INSERT INTO public.delivery_recipient_state(recipient_fingerprint)
  VALUES (p_recipient_fingerprint) ON CONFLICT DO NOTHING;
  PERFORM 1 FROM public.delivery_recipient_state
    WHERE recipient_fingerprint=p_recipient_fingerprint FOR UPDATE;

  -- A *processed* event with the same stable signed ID must match every field.
  SELECT * INTO v_existing FROM public.delivery_provider_events
    WHERE svix_event_id=p_event_id;
  IF FOUND THEN
    IF v_existing.provider_email_id IS DISTINCT FROM p_provider_email_id
      OR v_existing.recipient_fingerprint IS DISTINCT FROM p_recipient_fingerprint
      OR v_existing.event_type IS DISTINCT FROM p_event_type
      OR v_existing.event_at IS DISTINCT FROM p_event_at
      OR v_existing.payload_sha256 IS DISTINCT FROM p_payload_sha256
      OR v_existing.suppression_reason IS DISTINCT FROM p_suppression_reason
    THEN
      RAISE EXCEPTION 'Webhook event ID reused with different content.' USING ERRCODE='23505';
    END IF;
    RETURN 'duplicate';
  END IF;

  SELECT * INTO v_sub FROM public.delivery_provider_submissions
    WHERE provider_email_id=p_provider_email_id FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO public.delivery_provider_pending_events
      (svix_event_id,provider_email_id,recipient_fingerprint,event_type,
       event_at,payload_sha256,suppression_reason)
    VALUES
      (p_event_id,p_provider_email_id,p_recipient_fingerprint,p_event_type,
       p_event_at,p_payload_sha256,p_suppression_reason)
    ON CONFLICT (svix_event_id) DO NOTHING RETURNING svix_event_id INTO v_inserted;
    IF v_inserted IS NULL THEN
      SELECT * INTO v_pending FROM public.delivery_provider_pending_events
        WHERE svix_event_id=p_event_id;
      IF NOT FOUND
        OR v_pending.provider_email_id IS DISTINCT FROM p_provider_email_id
        OR v_pending.recipient_fingerprint IS DISTINCT FROM p_recipient_fingerprint
        OR v_pending.event_type IS DISTINCT FROM p_event_type
        OR v_pending.event_at IS DISTINCT FROM p_event_at
        OR v_pending.payload_sha256 IS DISTINCT FROM p_payload_sha256
        OR v_pending.suppression_reason IS DISTINCT FROM p_suppression_reason
      THEN
        RAISE EXCEPTION 'Pending webhook ID reused with different content.' USING ERRCODE='23505';
      END IF;
    END IF;
    -- An unmatched verified provider event freezes *new* transport for this
    -- fingerprint until reconciliation or an explicitly authorized resolution.
    UPDATE public.delivery_recipient_state SET
      pending_unmatched=true, updated_at=clock_timestamp()
    WHERE recipient_fingerprint=p_recipient_fingerprint;
    RETURN CASE WHEN v_inserted IS NULL THEN 'duplicate' ELSE 'pending' END;
  END IF;

  IF v_sub.recipient_fingerprint IS DISTINCT FROM p_recipient_fingerprint THEN
    RAISE EXCEPTION 'Provider recipient association mismatch.' USING ERRCODE='42501';
  END IF;

  -- A pending ID and a different provider ID/fingerprint cannot be re-used.
  SELECT * INTO v_pending FROM public.delivery_provider_pending_events
    WHERE svix_event_id=p_event_id;
  IF FOUND AND (
    v_pending.provider_email_id IS DISTINCT FROM p_provider_email_id
    OR v_pending.recipient_fingerprint IS DISTINCT FROM p_recipient_fingerprint
    OR v_pending.event_type IS DISTINCT FROM p_event_type
    OR v_pending.event_at IS DISTINCT FROM p_event_at
    OR v_pending.payload_sha256 IS DISTINCT FROM p_payload_sha256
    OR v_pending.suppression_reason IS DISTINCT FROM p_suppression_reason)
  THEN
    RAISE EXCEPTION 'Pending webhook association mismatch.' USING ERRCODE='23505';
  END IF;

  INSERT INTO public.delivery_provider_events
    (svix_event_id,job_id,provider_email_id,recipient_fingerprint,event_type,
     event_at,payload_sha256,suppression_reason)
  VALUES (p_event_id,v_sub.job_id,p_provider_email_id,p_recipient_fingerprint,p_event_type,
          p_event_at,p_payload_sha256,p_suppression_reason)
  ON CONFLICT (svix_event_id) DO NOTHING RETURNING svix_event_id INTO v_inserted;
  IF v_inserted IS NULL THEN
    RAISE EXCEPTION 'Concurrent webhook conflict: retry with same signed event.' USING ERRCODE='40001';
  END IF;

  v_next_state := CASE
    WHEN p_suppression_reason='spam_complaint' THEN 'complained'
    WHEN p_suppression_reason='permanent_bounce' THEN 'bounced'
    WHEN p_event_type='email.suppressed' THEN 'suppressed'
    WHEN p_event_type='email.delivered' THEN 'delivered'
    WHEN p_event_type='email.failed' THEN 'failed'
    WHEN p_event_type IN ('email.bounced','email.delivery_delayed') THEN 'delayed'
    ELSE 'sent' END;
  UPDATE public.delivery_provider_submissions SET
    lifecycle_state = CASE
      WHEN lifecycle_state='complained' THEN 'complained'
      WHEN lifecycle_state='bounced' AND v_next_state<>'complained' THEN 'bounced'
      WHEN lifecycle_state='suppressed' AND v_next_state NOT IN ('complained','bounced') THEN 'suppressed'
      WHEN v_next_state IN ('complained','bounced','suppressed') THEN v_next_state
      WHEN lifecycle_state='delivered' THEN 'delivered'
      WHEN v_next_state='delivered' THEN 'delivered'
      WHEN lifecycle_state='failed' AND v_next_state IN ('sent','delayed') THEN 'failed'
      WHEN lifecycle_state='delayed' AND v_next_state='sent' THEN 'delayed'
      ELSE v_next_state END,
    last_event_at=greatest(coalesce(last_event_at,p_event_at),p_event_at),
    last_event_type=CASE WHEN last_event_at IS NULL OR p_event_at>=last_event_at
      THEN p_event_type ELSE last_event_type END
  WHERE job_id=v_sub.job_id;

  IF p_suppression_reason IS NOT NULL THEN
    -- A complaint outranks a hard bounce. Neither a delayed delivery nor an
    -- external removal notification is allowed to remove this safety state.
    UPDATE public.delivery_recipient_state SET
      suppression_reason=CASE
        WHEN suppression_reason='spam_complaint'
          OR p_suppression_reason='spam_complaint' THEN 'spam_complaint'
        ELSE 'permanent_bounce' END,
      suppressed_at=coalesce(suppressed_at,clock_timestamp()),
      updated_at=clock_timestamp()
    WHERE recipient_fingerprint=p_recipient_fingerprint;

    INSERT INTO public.delivery_recipient_suppressions
      (recipient_fingerprint,first_job_id,reason,source_event_id)
    VALUES (p_recipient_fingerprint,v_sub.job_id,p_suppression_reason,p_event_id)
    ON CONFLICT (recipient_fingerprint) DO UPDATE SET
      reason=CASE WHEN public.delivery_recipient_suppressions.reason='spam_complaint'
        OR excluded.reason='spam_complaint' THEN 'spam_complaint'
        ELSE 'permanent_bounce' END;
  END IF;
  RETURN 'recorded';
END
$$;
REVOKE ALL ON FUNCTION public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)
  TO service_role;

-- This wrapper takes the recipient lock BEFORE ledger row locks to avoid
-- lock-order inversion when a webhook races the sender's result persistence.
CREATE OR REPLACE FUNCTION public.mark_delivery_sent_with_recipient(
  p_job_id uuid, p_claim_token uuid, p_provider_email_id text,
  p_recipient_fingerprint text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_user uuid;
  v_pending public.delivery_provider_pending_events%rowtype;
  v_result text;
BEGIN
  IF p_job_id IS NULL OR p_claim_token IS NULL
    OR p_provider_email_id IS NULL OR char_length(p_provider_email_id) NOT BETWEEN 1 AND 255
    OR nullif(btrim(p_provider_email_id),'') IS NULL
    OR p_recipient_fingerprint IS NULL OR p_recipient_fingerprint !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION 'Invalid provider submission arguments.' USING ERRCODE='22023';
  END IF;

  INSERT INTO public.delivery_recipient_state(recipient_fingerprint)
    VALUES(p_recipient_fingerprint) ON CONFLICT DO NOTHING;
  PERFORM 1 FROM public.delivery_recipient_state
    WHERE recipient_fingerprint=p_recipient_fingerprint FOR UPDATE;

  SELECT user_id INTO v_user FROM public.delivery_ledger
    WHERE id=p_job_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown job.' USING ERRCODE='42501'; END IF;
  IF public.mark_delivery_sent(p_job_id,p_claim_token,p_provider_email_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'Delivery mark-sent authorization failed.' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.delivery_provider_submissions
    (job_id,user_id,provider_email_id,recipient_fingerprint)
  VALUES (p_job_id,v_user,p_provider_email_id,p_recipient_fingerprint);

  -- An authentic webhook may have arrived before this provider ID was saved.
  -- Lock/consume those pending rows while holding the same recipient lock.
  FOR v_pending IN
    SELECT * FROM public.delivery_provider_pending_events
    WHERE provider_email_id=p_provider_email_id
      AND recipient_fingerprint=p_recipient_fingerprint
    ORDER BY event_at,svix_event_id FOR UPDATE
  LOOP
    v_result:=public.record_resend_webhook_event(
      v_pending.svix_event_id,v_pending.provider_email_id,
      v_pending.recipient_fingerprint,v_pending.event_type,v_pending.event_at,
      v_pending.payload_sha256,v_pending.suppression_reason);
    IF v_result NOT IN ('recorded','duplicate') THEN
      RAISE EXCEPTION 'Pending event reconciliation failed.' USING ERRCODE='40001';
    END IF;
    DELETE FROM public.delivery_provider_pending_events
      WHERE svix_event_id=v_pending.svix_event_id;
  END LOOP;

  UPDATE public.delivery_recipient_state SET
    pending_unmatched=EXISTS (
      SELECT 1 FROM public.delivery_provider_pending_events
      WHERE recipient_fingerprint=p_recipient_fingerprint),
    updated_at=clock_timestamp()
  WHERE recipient_fingerprint=p_recipient_fingerprint;
  RETURN true;
END
$$;
REVOKE ALL ON FUNCTION public.mark_delivery_sent_with_recipient(uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_delivery_sent_with_recipient(uuid,uuid,text,text)
  TO service_role;

-- Outbound final authorization: state row lock THEN legacy 024 consent/identity
-- gate in one DB transaction. The lock is released at transaction commit.
CREATE FUNCTION public.begin_delivery_transport_with_suppression(
  p_job_id uuid, p_claim_token uuid,
  p_expected_email text, p_recipient_fingerprint text
) RETURNS timestamptz
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_reason text;
  v_pending boolean;
  v_job public.delivery_ledger%rowtype;
BEGIN
  IF p_job_id IS NULL OR p_claim_token IS NULL
    OR p_expected_email IS NULL OR char_length(p_expected_email) NOT BETWEEN 1 AND 320
    OR nullif(btrim(p_expected_email),'') IS NULL
    OR p_recipient_fingerprint IS NULL OR p_recipient_fingerprint !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION 'Invalid final transport authorization arguments.' USING ERRCODE='22023';
  END IF;

  INSERT INTO public.delivery_recipient_state(recipient_fingerprint)
    VALUES(p_recipient_fingerprint) ON CONFLICT DO NOTHING;
  SELECT suppression_reason,pending_unmatched INTO v_reason,v_pending
    FROM public.delivery_recipient_state
    WHERE recipient_fingerprint=p_recipient_fingerprint FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recipient state unavailable.' USING ERRCODE='42501';
  END IF;

  IF v_reason IS NOT NULL OR v_pending THEN
    -- Even the denial must honor the original live claim and confirmed member
    -- identity. Never cancel a job on an arbitrary/mismatched email argument.
    SELECT * INTO v_job FROM public.delivery_ledger
      WHERE id=p_job_id FOR UPDATE;
    IF NOT FOUND OR v_job.state<>'claimed'
      OR v_job.claim_token IS DISTINCT FROM p_claim_token
      OR v_job.claim_expires_at IS NULL
      OR v_job.claim_expires_at<=clock_timestamp() THEN
      RAISE EXCEPTION 'Delivery claim is not authorized.' USING ERRCODE='42501';
    END IF;
    PERFORM 1 FROM auth.users u
      WHERE u.id=v_job.user_id
      AND u.email_confirmed_at IS NOT NULL
      AND btrim(u.email)=p_expected_email
      FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Recipient identity is not authorized.' USING ERRCODE='42501';
    END IF;
    UPDATE public.delivery_ledger SET
      state='cancelled',cancelled_at=clock_timestamp(),
      claim_token=NULL,claim_expires_at=NULL,next_attempt_at=NULL,
      error_code=CASE WHEN v_reason IS NOT NULL
        THEN 'recipient_suppressed' ELSE 'recipient_pending_provider_event' END,
      updated_at=clock_timestamp()
    WHERE id=p_job_id;
    RETURN NULL;
  END IF;

  -- Existing 024 RPC rechecks current Daily/Weekly consent, suspension,
  -- Auth email, claim token and claim lease under PostgreSQL locks.
  RETURN public.begin_delivery_transport(p_job_id,p_claim_token,p_expected_email);
END
$$;
REVOKE ALL ON FUNCTION public.begin_delivery_transport_with_suppression(uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.begin_delivery_transport_with_suppression(uuid,uuid,text,text)
  TO service_role;

-- Critical: the old three-argument RPC MUST NOT remain callable by
-- service_role; otherwise the application can bypass suppression.
REVOKE ALL ON FUNCTION public.begin_delivery_transport(uuid,uuid,text)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
