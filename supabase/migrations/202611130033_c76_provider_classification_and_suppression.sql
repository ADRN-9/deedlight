-- Cycle 76 isolated candidate: official Resend account suppressions and uncertain bounces.
-- Never apply to Production until exclusive ownership, migration reconciliation and review.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='45s';

DO $preflight$
BEGIN
  IF to_regclass('deedlight_event_private.provider_event_registry') IS NULL
    OR to_regclass('public.delivery_recipient_state') IS NULL
    OR to_regclass('public.delivery_provider_submissions') IS NULL
    OR to_regprocedure('public.deedlight_record_resend_verified(text,text,text,text,timestamptz,text,text)') IS NULL
    OR to_regprocedure('deedlight_event_private.c75_preserve_recipient_conflict_hold()') IS NULL
    OR to_regprocedure('deedlight_private.recipient_fingerprints(text)') IS NULL
    OR to_regprocedure('public.deedlight_record_resend_delivery_v2(text,text,text,text,timestamptz,text,text,text)') IS NOT NULL
    OR to_regclass('deedlight_event_private.c76_uncertain_bounces') IS NOT NULL THEN
    RAISE EXCEPTION 'C76 requires the exact unreplaced 032 provider security contracts' USING ERRCODE='55000';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
    WHERE tgrelid='public.delivery_recipient_state'::regclass
      AND tgname='c75_preserve_recipient_conflict_hold' AND tgenabled='A') THEN
    RAISE EXCEPTION 'C76 refuses migration without monotonic 032 recipient hold' USING ERRCODE='55000';
  END IF;
END $preflight$;

-- Private audit: original classification is immutable, including Transient and
-- Undetermined. Provider payload, email, signing keys and member ID are NOT stored.
CREATE TABLE deedlight_event_private.c76_bounce_classifications (
  provider text NOT NULL DEFAULT 'resend' CHECK (provider='resend'),
  event_id text NOT NULL,
  bounce_type text NOT NULL CHECK (bounce_type IN ('Permanent','Transient','Undetermined')),
  observed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(provider,event_id),
  FOREIGN KEY(provider,event_id)
    REFERENCES deedlight_event_private.provider_event_registry(provider,event_id) ON DELETE RESTRICT
);
CREATE TABLE deedlight_event_private.c76_uncertain_bounces (
  provider text NOT NULL DEFAULT 'resend' CHECK (provider='resend'),
  event_id text NOT NULL,
  recipient_fingerprint text NOT NULL CHECK (recipient_fingerprint ~ '^[0-9a-f]{64}$'),
  key_version smallint NOT NULL CHECK (key_version>0),
  observed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(provider,event_id,recipient_fingerprint),
  FOREIGN KEY(provider,event_id) REFERENCES deedlight_event_private.c76_bounce_classifications(provider,event_id)
    ON DELETE RESTRICT
);
CREATE INDEX c76_uncertain_bounces_fingerprint ON deedlight_event_private.c76_uncertain_bounces(recipient_fingerprint);

-- Account-list changes do not have a provider EMAIL message_id. Do not forge a
-- delivery-message association. Use one existing global registry ID instead.
CREATE TABLE deedlight_event_private.c76_account_suppression_events (
  provider text NOT NULL DEFAULT 'resend' CHECK (provider='resend'),
  event_id text NOT NULL,
  suppression_id text NOT NULL CHECK (length(suppression_id) BETWEEN 10 AND 128),
  event_type text NOT NULL CHECK (event_type IN ('suppression.added','suppression.removed')),
  origin text NOT NULL CHECK (origin IN ('bounce','complaint','manual')),
  source_id text CHECK (source_id IS NULL OR (length(source_id) BETWEEN 1 AND 255 AND source_id !~ '[[:cntrl:]]')),
  event_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(provider,event_id),
  FOREIGN KEY(provider,event_id) REFERENCES deedlight_event_private.provider_event_registry(provider,event_id)
    ON DELETE RESTRICT
);
CREATE TABLE deedlight_event_private.c76_account_suppression_recipients (
  provider text NOT NULL DEFAULT 'resend' CHECK (provider='resend'),
  event_id text NOT NULL,
  recipient_fingerprint text NOT NULL CHECK (recipient_fingerprint ~ '^[0-9a-f]{64}$'),
  key_version smallint NOT NULL CHECK (key_version>0),
  PRIMARY KEY(provider,event_id,recipient_fingerprint),
  FOREIGN KEY(provider,event_id) REFERENCES deedlight_event_private.c76_account_suppression_events(provider,event_id)
    ON DELETE RESTRICT
);

DO $privacy$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['c76_bounce_classifications','c76_uncertain_bounces',
    'c76_account_suppression_events','c76_account_suppression_recipients'] LOOP
    EXECUTE format('ALTER TABLE deedlight_event_private.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('REVOKE ALL ON deedlight_event_private.%I FROM PUBLIC,anon,authenticated,service_role',t);
  END LOOP;
END $privacy$;

-- A later delivered/sent event must NEVER clear an unresolved Undetermined
-- bounce. There is deliberately no automatic release function in this cycle.
CREATE FUNCTION deedlight_event_private.c76_preserve_uncertain_bounce_hold()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $guard$
BEGIN
  IF NOT NEW.pending_unmatched AND EXISTS (
    SELECT 1 FROM deedlight_event_private.c76_uncertain_bounces b
      WHERE b.recipient_fingerprint=NEW.recipient_fingerprint
  ) THEN
    NEW.pending_unmatched:=true;
  END IF;
  RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION deedlight_event_private.c76_preserve_uncertain_bounce_hold()
  FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER c76_preserve_uncertain_bounce_hold
  BEFORE UPDATE ON public.delivery_recipient_state FOR EACH ROW
  EXECUTE FUNCTION deedlight_event_private.c76_preserve_uncertain_bounce_hold();
ALTER TABLE public.delivery_recipient_state ENABLE ALWAYS TRIGGER c76_preserve_uncertain_bounce_hold;

-- This is the sole service-callable DELIVERED/MESSAGE webhook RPC after C76.
-- The prior 7-argument definer is now internal-only to prevent a caller
-- omitting the Undetermined classification and bypassing a safety hold.
CREATE FUNCTION public.deedlight_record_resend_delivery_v2(
  p_event_id text,p_provider_email_id text,p_recipient_email text,
  p_event_type text,p_event_at timestamptz,p_payload_sha256 text,
  p_suppression_reason text,p_bounce_type text
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $handler$
DECLARE v_result text; v_actual text; v_fp record;
BEGIN
  IF (p_event_type='email.bounced' AND (
       p_bounce_type NOT IN ('Permanent','Transient','Undetermined') OR p_bounce_type IS NULL
       OR (p_bounce_type='Permanent' AND p_suppression_reason IS DISTINCT FROM 'permanent_bounce')
       OR (p_bounce_type IN ('Transient','Undetermined') AND p_suppression_reason IS NOT NULL)
     )) OR (p_event_type IS DISTINCT FROM 'email.bounced' AND p_bounce_type IS NOT NULL) THEN
    RAISE EXCEPTION 'Missing or inconsistent authenticated bounce classification' USING ERRCODE='22023';
  END IF;
  -- The original 030 function locks all current + historical fingerprints,
  -- reserves the sole event identity and processes/pends/quarantines atomically.
  v_result:=public.deedlight_record_resend_verified(
    p_event_id,p_provider_email_id,p_recipient_email,p_event_type,p_event_at,
    p_payload_sha256,p_suppression_reason);
  IF p_event_type='email.bounced' AND v_result<>'quarantined' THEN
    INSERT INTO deedlight_event_private.c76_bounce_classifications(event_id,bounce_type)
      VALUES(p_event_id,p_bounce_type) ON CONFLICT (provider,event_id) DO NOTHING;
    IF EXISTS (SELECT 1 FROM deedlight_event_private.c76_bounce_classifications b
        WHERE b.event_id=p_event_id AND b.bounce_type IS DISTINCT FROM p_bounce_type) THEN
      RAISE EXCEPTION 'Bounce classification changed under same event ID' USING ERRCODE='23505';
    END IF;
    IF p_bounce_type='Undetermined' THEN
      -- Unknown association remains a pending safety hold; conflicting known
      -- association is quarantined by the underlying 030 function instead.
      SELECT s.recipient_fingerprint INTO v_actual FROM public.delivery_provider_submissions s
        WHERE s.provider_email_id=p_provider_email_id;
      IF v_actual IS NULL OR EXISTS (
        SELECT 1 FROM deedlight_private.recipient_fingerprints(p_recipient_email) f
          WHERE f.fingerprint=v_actual) THEN
        FOR v_fp IN SELECT * FROM deedlight_private.recipient_fingerprints(p_recipient_email)
            ORDER BY fingerprint LOOP
          INSERT INTO deedlight_event_private.c76_uncertain_bounces
            (event_id,recipient_fingerprint,key_version)
            VALUES(p_event_id,v_fp.fingerprint,v_fp.key_version)
            ON CONFLICT DO NOTHING;
          INSERT INTO public.delivery_recipient_state(recipient_fingerprint)
            VALUES(v_fp.fingerprint) ON CONFLICT DO NOTHING;
          UPDATE public.delivery_recipient_state SET pending_unmatched=true,
            updated_at=clock_timestamp() WHERE recipient_fingerprint=v_fp.fingerprint;
        END LOOP;
      END IF;
    END IF;
  END IF;
  RETURN v_result;
END $handler$;
REVOKE ALL ON FUNCTION public.deedlight_record_resend_delivery_v2(text,text,text,text,timestamptz,text,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.deedlight_record_resend_delivery_v2(text,text,text,text,timestamptz,text,text,text)
  TO service_role;
REVOKE ALL ON FUNCTION public.deedlight_record_resend_verified(text,text,text,text,timestamptz,text,text)
  FROM PUBLIC,anon,authenticated,service_role;

-- Official suppression.added / suppression.removed events have a SUPPRESSION
-- id and account email, not an outbound message id. Signature verification
-- happens before this narrow RPC; fingerprints are computed only in the DB.
CREATE FUNCTION public.deedlight_record_resend_suppression_verified(
  p_event_id text,p_suppression_id text,p_recipient_email text,
  p_origin text,p_source_id text,p_event_type text,p_event_at timestamptz,
  p_payload_sha256 text
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $handler$
DECLARE v_r record; v_actual text; v_reserved text;
BEGIN
  IF p_event_id IS NULL OR p_event_id !~ '^msg_[A-Za-z0-9_-]{6,180}$'
    OR p_suppression_id IS NULL OR p_suppression_id !~ '^[A-Za-z0-9-]{10,128}$'
    OR p_recipient_email IS NULL OR p_event_type IS NULL
    OR p_event_type NOT IN ('suppression.added','suppression.removed')
    OR p_event_at IS NULL OR p_payload_sha256 IS NULL OR p_payload_sha256 !~ '^[0-9a-f]{64}$'
    OR p_origin IS NULL OR p_origin NOT IN ('bounce','complaint','manual')
    OR (p_source_id IS NOT NULL AND (length(p_source_id) NOT BETWEEN 1 AND 255
      OR p_source_id ~ '[[:cntrl:]]')) THEN
    RAISE EXCEPTION 'Invalid verified account suppression metadata' USING ERRCODE='22023';
  END IF;
  -- Database-authoritative source correlation, only if source ID is an
  -- already known outbound provider message. No guessed member from email.
  IF p_source_id IS NOT NULL THEN
    SELECT s.recipient_fingerprint INTO v_actual FROM public.delivery_provider_submissions s
      WHERE s.provider_email_id=p_source_id;
  END IF;
  FOR v_r IN SELECT DISTINCT fingerprint FROM (
    SELECT f.fingerprint FROM deedlight_private.recipient_fingerprints(p_recipient_email) f
    UNION ALL SELECT v_actual WHERE v_actual IS NOT NULL
  ) ids ORDER BY fingerprint LOOP
    INSERT INTO public.delivery_recipient_state(recipient_fingerprint)
      VALUES(v_r.fingerprint) ON CONFLICT DO NOTHING;
    PERFORM 1 FROM public.delivery_recipient_state s
      WHERE s.recipient_fingerprint=v_r.fingerprint FOR UPDATE;
  END LOOP;
  v_reserved:=public.deedlight_reserve_provider_event(
    'resend',p_event_id,decode(p_payload_sha256,'hex'),p_event_type,NULL);
  IF v_reserved IN ('IDENTITY_CONFLICT','QUARANTINED') THEN
    IF v_actual IS NOT NULL THEN
      UPDATE public.delivery_recipient_state SET pending_unmatched=true,
        updated_at=clock_timestamp() WHERE recipient_fingerprint=v_actual;
    END IF;
    RETURN 'quarantined';
  END IF;
  IF v_reserved='DUPLICATE_PROCESSED' THEN RETURN 'duplicate'; END IF;
  IF v_reserved<>'NEW_PENDING' THEN
    RAISE EXCEPTION 'Unexpected incomplete suppression reservation' USING ERRCODE='55000';
  END IF;
  IF v_actual IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM deedlight_private.recipient_fingerprints(p_recipient_email) f
      WHERE f.fingerprint=v_actual) THEN
    UPDATE deedlight_event_private.provider_event_registry
      SET state='identity_conflict',updated_at=clock_timestamp()
      WHERE provider='resend' AND event_id=p_event_id;
    INSERT INTO deedlight_event_private.provider_event_quarantine
      (provider,event_id,reason,conflicting_sha256)
      VALUES('resend',p_event_id,'ambiguous_provider_delivery',decode(p_payload_sha256,'hex'))
      ON CONFLICT DO NOTHING;
    UPDATE public.delivery_recipient_state SET pending_unmatched=true,
      updated_at=clock_timestamp() WHERE recipient_fingerprint=v_actual;
    RETURN 'quarantined';
  END IF;
  INSERT INTO deedlight_event_private.c76_account_suppression_events
    (event_id,suppression_id,event_type,origin,source_id,event_at)
  VALUES(p_event_id,p_suppression_id,p_event_type,p_origin,p_source_id,p_event_at)
  ON CONFLICT (provider,event_id) DO NOTHING;
  FOR v_r IN SELECT * FROM deedlight_private.recipient_fingerprints(p_recipient_email)
      ORDER BY fingerprint LOOP
    INSERT INTO deedlight_event_private.c76_account_suppression_recipients
      (event_id,recipient_fingerprint,key_version)
      VALUES(p_event_id,v_r.fingerprint,v_r.key_version)
      ON CONFLICT DO NOTHING;
    IF p_event_type='suppression.added' THEN
      -- A signed suppression.added is an account-wide do-not-send event.
      -- A removal NEVER revokes this or an independent complaint/consent hold.
      UPDATE public.delivery_recipient_state
        SET provider_suppressed=true,pending_unmatched=true,updated_at=clock_timestamp()
        WHERE recipient_fingerprint=v_r.fingerprint;
    END IF;
  END LOOP;
  UPDATE deedlight_event_private.provider_event_registry
    SET state='processed',updated_at=clock_timestamp()
    WHERE provider='resend' AND event_id=p_event_id AND state='pending';
  IF NOT FOUND AND v_reserved='NEW_PENDING' THEN
    RAISE EXCEPTION 'Suppression event lost global registry identity' USING ERRCODE='55000';
  END IF;
  RETURN 'recorded';
END $handler$;
REVOKE ALL ON FUNCTION public.deedlight_record_resend_suppression_verified(text,text,text,text,text,text,timestamptz,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.deedlight_record_resend_suppression_verified(text,text,text,text,text,text,timestamptz,text)
  TO service_role;
COMMIT;
