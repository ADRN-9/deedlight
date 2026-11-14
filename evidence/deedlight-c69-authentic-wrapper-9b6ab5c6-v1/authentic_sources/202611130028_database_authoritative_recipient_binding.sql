-- C46 ISOLATED SECURITY PROPOSAL, NOT AN APPROVED MIGRATION NUMBER.
-- Forward-only overlay after reviewed 019-024 plus isolated C44/C45 proposals.
-- Production execution and key provisioning are prohibited by this assignment.
-- No key values or email addresses are embedded in this file.
BEGIN;
DO $$
BEGIN
  IF to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') IS NULL
    OR to_regprocedure('public.claim_delivery_jobs(text,timestamptz,integer)') IS NULL
    OR to_regprocedure('public.claim_delivery_jobs(timestamptz,integer)') IS NOT NULL
    OR to_regprocedure('public.begin_delivery_transport_with_suppression(uuid,uuid,text,text)') IS NULL
    OR to_regprocedure('public.mark_delivery_sent_with_recipient(uuid,uuid,text,text)') IS NULL
    OR to_regprocedure('public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)') IS NULL
    OR to_regclass('public.delivery_recipient_state') IS NULL
    OR to_regclass('public.delivery_provider_pending_events') IS NULL
    OR to_regclass('public.delivery_provider_submissions') IS NULL
    OR to_regprocedure('extensions.hmac(bytea,bytea,text)') IS NULL
    OR to_regclass('deedlight_private.delivery_recipient_keyring') IS NOT NULL
  THEN
    RAISE EXCEPTION 'C46 requires verified 024 + C44/C45 state, qualified extensions.hmac, and unapplied keyring';
  END IF;
  -- No silent reinterpretation of recipient hashes created with the old
  -- application-only key. Existing history requires a separately verified
  -- identity-by-identity reconciliation; abort instead of enabling new sends.
  IF EXISTS (SELECT 1 FROM public.delivery_provider_submissions)
    OR EXISTS (SELECT 1 FROM public.delivery_provider_events)
    OR EXISTS (SELECT 1 FROM public.delivery_provider_pending_events)
    OR EXISTS (SELECT 1 FROM public.delivery_recipient_suppressions)
    OR EXISTS (SELECT 1 FROM public.delivery_recipient_state) THEN
    RAISE EXCEPTION 'Historical provider/suppression identities require audited rebind before C46';
  END IF;
END $$;

CREATE SCHEMA deedlight_private;
REVOKE ALL ON SCHEMA deedlight_private FROM PUBLIC, anon, authenticated, service_role;

-- Only an explicitly authorized database operator can provision/rotate keys.
-- 'locked' is the default so installation alone can never enable delivery.
CREATE TABLE deedlight_private.delivery_recipient_key_control (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  mode text NOT NULL DEFAULT 'locked' CHECK (mode IN ('locked','ready')),
  required_key_versions smallint[] NOT NULL DEFAULT '{}'::smallint[],
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO deedlight_private.delivery_recipient_key_control(singleton) VALUES (true);
CREATE TABLE deedlight_private.delivery_recipient_keyring (
  key_version smallint PRIMARY KEY CHECK (key_version > 0),
  secret_bytes bytea NOT NULL CHECK (octet_length(secret_bytes) >= 32),
  phase text NOT NULL CHECK (phase IN ('active','legacy')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE UNIQUE INDEX recipient_only_one_active_key
  ON deedlight_private.delivery_recipient_keyring((phase)) WHERE phase='active';
-- Material from a given version is immutable. Phase changes/additions require
-- an explicit fail-closed maintenance lock; old keys are never silently removed.
CREATE FUNCTION deedlight_private.guard_recipient_keyring_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_mode text;
BEGIN
  SELECT mode INTO v_mode FROM deedlight_private.delivery_recipient_key_control
    WHERE singleton FOR SHARE;
  IF v_mode IS DISTINCT FROM 'locked' THEN
    RAISE EXCEPTION 'Keyring changes require locked mode' USING ERRCODE='42501';
  END IF;
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'Key retirement requires reviewed rekey migration' USING ERRCODE='42501';
  END IF;
  IF TG_OP='UPDATE' AND
    (NEW.key_version IS DISTINCT FROM OLD.key_version
      OR NEW.secret_bytes IS DISTINCT FROM OLD.secret_bytes) THEN
    RAISE EXCEPTION 'Key identity and material are immutable' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_delivery_recipient_key_change
  BEFORE INSERT OR UPDATE OR DELETE ON deedlight_private.delivery_recipient_keyring
  FOR EACH ROW EXECUTE FUNCTION deedlight_private.guard_recipient_keyring_change();
REVOKE ALL ON FUNCTION deedlight_private.guard_recipient_keyring_change()
  FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE deedlight_private.delivery_recipient_keyring ENABLE ROW LEVEL SECURITY;
ALTER TABLE deedlight_private.delivery_recipient_key_control ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE deedlight_private.delivery_recipient_keyring, deedlight_private.delivery_recipient_key_control
  FROM PUBLIC, anon, authenticated, service_role;

-- Addresses are deliberately restricted to unambiguous ASCII input.
-- Local-part case is preserved; only the domain is ASCII-lowercased.
-- This can deny unusual legitimate addresses, but must never merge two identities.
CREATE FUNCTION deedlight_private.normalize_recipient_email(p_email text)
RETURNS text LANGUAGE plpgsql IMMUTABLE STRICT
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_email text; v_local text; v_domain text;
BEGIN
  v_email:=btrim(p_email);
  IF length(v_email) < 3 OR length(v_email) > 320
    OR v_email !~ '^[!-~]+$' OR v_email ~ '[<>]'
    OR length(v_email)-length(replace(v_email,'@','')) <> 1
  THEN RAISE EXCEPTION 'Ambiguous recipient identity' USING ERRCODE='22023'; END IF;
  v_local:=split_part(v_email,'@',1);
  v_domain:=split_part(v_email,'@',2);
  IF v_local='' OR v_domain !~ '^[A-Za-z0-9.-]+$'
    OR position('.' in v_domain)=0
    OR v_domain LIKE '.%' OR v_domain LIKE '%.'
  THEN RAISE EXCEPTION 'Ambiguous recipient identity' USING ERRCODE='22023'; END IF;
  RETURN v_local || '@' || lower(v_domain);
END $$;
REVOKE ALL ON FUNCTION deedlight_private.normalize_recipient_email(text) FROM PUBLIC,anon,authenticated,service_role;

-- Every gate locks control row to pin the keyring epoch until COMMIT.
-- Missing active/legacy keys, a broken version catalog or rotation lock => STOP.
CREATE FUNCTION deedlight_private.recipient_fingerprints(p_email text)
RETURNS TABLE(key_version smallint, fingerprint text, phase text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_norm text; v_required smallint[]; v_actual smallint[]; v_count integer;
BEGIN
  SELECT c.required_key_versions INTO v_required
    FROM deedlight_private.delivery_recipient_key_control c WHERE c.singleton AND c.mode='ready'
    FOR SHARE;
  IF NOT FOUND OR cardinality(v_required)=0 THEN
    RAISE EXCEPTION 'Recipient keyring is unavailable' USING ERRCODE='42501';
  END IF;
  SELECT coalesce(array_agg(k.key_version ORDER BY k.key_version),'{}'::smallint[]),
         count(*) FILTER (WHERE k.phase='active')
    INTO v_actual,v_count FROM deedlight_private.delivery_recipient_keyring k;
  IF v_actual IS DISTINCT FROM v_required OR v_count<>1 THEN
    RAISE EXCEPTION 'Recipient keyring requires reconciliation' USING ERRCODE='42501';
  END IF;
  v_norm:=deedlight_private.normalize_recipient_email(p_email);
  RETURN QUERY SELECT k.key_version,
    encode(extensions.hmac(convert_to(v_norm,'UTF8'),k.secret_bytes,'sha256'),'hex'),
    k.phase
    FROM deedlight_private.delivery_recipient_keyring k ORDER BY k.key_version;
END $$;
REVOKE ALL ON FUNCTION deedlight_private.recipient_fingerprints(text) FROM PUBLIC,anon,authenticated,service_role;

-- Recipient fingerprint selected at the point of CURRENT DB authorization.
-- A later Auth email change cannot rewrite this immutable provider association.
CREATE TABLE public.delivery_transport_intents (
  job_id uuid PRIMARY KEY REFERENCES public.delivery_ledger(id) ON DELETE CASCADE,
  claim_token uuid NOT NULL,
  recipient_fingerprint text NOT NULL CHECK (recipient_fingerprint ~ '^[0-9a-f]{64}$'),
  key_version smallint NOT NULL CHECK (key_version > 0),
  authorized_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
-- Authentic provider event disagrees with the immutable original recipient:
-- quarantine the conflict and freeze only the ORIGINAL bound recipient.
-- Never apply an event's suppression to an unrelated asserted address.
CREATE TABLE public.delivery_provider_identity_conflicts (
  svix_event_id text PRIMARY KEY CHECK (svix_event_id ~ '^msg_[A-Za-z0-9_-]{6,180}$'),
  provider_email_id text NOT NULL CHECK (char_length(provider_email_id) BETWEEN 1 AND 255),
  original_recipient_fingerprint text NOT NULL CHECK (original_recipient_fingerprint ~ '^[0-9a-f]{64}$'),
  signed_recipient_fingerprint text NOT NULL CHECK (signed_recipient_fingerprint ~ '^[0-9a-f]{64}$'),
  payload_sha256 text NOT NULL CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
  received_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.delivery_provider_identity_conflicts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.delivery_provider_identity_conflicts
  FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX delivery_provider_identity_conflicts_provider_idx
  ON public.delivery_provider_identity_conflicts(provider_email_id,received_at);
ALTER TABLE public.delivery_transport_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.delivery_transport_intents FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX delivery_transport_intents_recipient_idx
  ON public.delivery_transport_intents(recipient_fingerprint,authorized_at DESC);

-- DB independently determines the fingerprint from the CURRENT confirmed
-- Supabase Auth email. The runtime never supplies the identity hash.
CREATE FUNCTION public.begin_delivery_transport_identity_bound(
  p_job_id uuid,p_claim_token uuid,p_expected_email text
) RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  v_email text; v_fp record; v_active_fp text; v_active_version smallint;
  v_deny_fp text; v_reason text; v_pending boolean; v_started timestamptz;
  v_previous public.delivery_transport_intents%rowtype;
BEGIN
  IF p_job_id IS NULL OR p_claim_token IS NULL OR p_expected_email IS NULL THEN
    RAISE EXCEPTION 'Invalid transport identity arguments' USING ERRCODE='22023'; END IF;
  SELECT u.email INTO v_email
    FROM public.delivery_ledger dl JOIN auth.users u ON u.id=dl.user_id
    WHERE dl.id=p_job_id AND u.email_confirmed_at IS NOT NULL
      AND btrim(u.email)=p_expected_email FOR SHARE OF u;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unconfirmed or changed recipient' USING ERRCODE='42501'; END IF;
  -- Lock ALL active and legacy fingerprints in deterministic fingerprint order,
  -- including previously absent state rows. Avoids rotation-time escape paths.
  FOR v_fp IN SELECT * FROM deedlight_private.recipient_fingerprints(v_email) ORDER BY fingerprint LOOP
    INSERT INTO public.delivery_recipient_state(recipient_fingerprint)
      VALUES(v_fp.fingerprint) ON CONFLICT DO NOTHING;
    SELECT s.suppression_reason,s.pending_unmatched INTO v_reason,v_pending
      FROM public.delivery_recipient_state s
      WHERE s.recipient_fingerprint=v_fp.fingerprint FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Recipient state missing' USING ERRCODE='42501'; END IF;
    IF v_reason IS NOT NULL OR v_pending THEN v_deny_fp:=v_fp.fingerprint; END IF;
    IF v_fp.phase='active' THEN
      v_active_fp:=v_fp.fingerprint; v_active_version:=v_fp.key_version;
    END IF;
  END LOOP;
  IF v_active_fp IS NULL THEN RAISE EXCEPTION 'Missing active key' USING ERRCODE='42501'; END IF;
  v_started:=public.begin_delivery_transport_with_suppression(
    p_job_id,p_claim_token,p_expected_email,coalesce(v_deny_fp,v_active_fp));
  IF v_started IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO v_previous FROM public.delivery_transport_intents WHERE job_id=p_job_id FOR UPDATE;
  IF FOUND AND v_previous.recipient_fingerprint<>v_active_fp THEN
    RAISE EXCEPTION 'Recipient identity changed across logical retry' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.delivery_transport_intents
    (job_id,claim_token,recipient_fingerprint,key_version,authorized_at)
  VALUES(p_job_id,p_claim_token,v_active_fp,v_active_version,clock_timestamp())
  ON CONFLICT (job_id) DO UPDATE SET
    claim_token=excluded.claim_token,
    key_version=excluded.key_version,
    authorized_at=excluded.authorized_at;
  RETURN v_started;
END $$;
REVOKE ALL ON FUNCTION public.begin_delivery_transport_identity_bound(uuid,uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.begin_delivery_transport_identity_bound(uuid,uuid,text)
  TO service_role;

-- Use the PRE-SEND snapshot, never the current Auth email or a Worker hash.
CREATE FUNCTION public.mark_delivery_sent_identity_bound(
  p_job_id uuid,p_claim_token uuid,p_provider_email_id text
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_fp text; v_intent public.delivery_transport_intents%rowtype;
BEGIN
  IF p_job_id IS NULL OR p_claim_token IS NULL OR p_provider_email_id IS NULL
    OR length(p_provider_email_id) NOT BETWEEN 1 AND 255 THEN
    RAISE EXCEPTION 'Invalid submission identity arguments' USING ERRCODE='22023'; END IF;
  -- Read fingerprint without locking first, then use the SAME lock ordering
  -- as the original C45 mark-sent wrapper: recipient before ledger/intent.
  SELECT recipient_fingerprint INTO v_fp FROM public.delivery_transport_intents
    WHERE job_id=p_job_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Missing original transport identity' USING ERRCODE='42501'; END IF;
  -- Fail closed if key catalog is locked, incomplete, or version was retired.
  PERFORM 1 FROM deedlight_private.recipient_fingerprints('healthcheck@example.test');
  INSERT INTO public.delivery_recipient_state(recipient_fingerprint)
    VALUES (v_fp) ON CONFLICT DO NOTHING;
  PERFORM 1 FROM public.delivery_recipient_state WHERE recipient_fingerprint=v_fp FOR UPDATE;
  SELECT * INTO v_intent FROM public.delivery_transport_intents
    WHERE job_id=p_job_id FOR UPDATE;
  IF NOT FOUND OR v_intent.recipient_fingerprint IS DISTINCT FROM v_fp
    OR v_intent.claim_token IS DISTINCT FROM p_claim_token
    OR NOT EXISTS (SELECT 1 FROM deedlight_private.delivery_recipient_keyring k
      WHERE k.key_version=v_intent.key_version) THEN
    RAISE EXCEPTION 'Stale or changed transport identity' USING ERRCODE='42501';
  END IF;
  RETURN public.mark_delivery_sent_with_recipient(
    p_job_id,p_claim_token,p_provider_email_id,v_intent.recipient_fingerprint);
END $$;
REVOKE ALL ON FUNCTION public.mark_delivery_sent_identity_bound(uuid,uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.mark_delivery_sent_identity_bound(uuid,uuid,text)
  TO service_role;

-- The webhook request must be verified BEFORE this call. The DB derives
-- ALL hash versions from the SIGNED provider recipient email, and rejects
-- any provider-ID association not belonging to that recipient.
CREATE FUNCTION public.record_resend_webhook_event_identity_bound(
  p_event_id text,p_provider_email_id text,p_recipient_email text,
  p_event_type text,p_event_at timestamptz,p_payload_sha256 text,
  p_suppression_reason text DEFAULT NULL
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_fp record; v_active text; v_associated text; v_reason text;
        v_pending boolean; v_result text;
BEGIN
  IF p_recipient_email IS NULL OR p_event_id IS NULL OR p_provider_email_id IS NULL THEN
    RAISE EXCEPTION 'Missing webhook identity' USING ERRCODE='22023'; END IF;
  -- Resolve provider submission before creating any state row for a signed
  -- recipient: an authentic mismatch must not mutate the unrelated address.
  SELECT s.recipient_fingerprint INTO v_associated
    FROM public.delivery_provider_submissions s
    WHERE s.provider_email_id=p_provider_email_id;
  IF FOUND AND NOT EXISTS(
    SELECT 1 FROM deedlight_private.recipient_fingerprints(p_recipient_email) p
      WHERE p.fingerprint=v_associated
  ) THEN
    SELECT p.fingerprint INTO v_active
      FROM deedlight_private.recipient_fingerprints(p_recipient_email) p
      WHERE p.phase='active';
    IF v_active IS NULL THEN RAISE EXCEPTION 'Missing active key' USING ERRCODE='42501'; END IF;
    INSERT INTO public.delivery_recipient_state(recipient_fingerprint)
      VALUES(v_associated) ON CONFLICT DO NOTHING;
    PERFORM 1 FROM public.delivery_recipient_state
      WHERE recipient_fingerprint=v_associated FOR UPDATE;
    IF EXISTS (SELECT 1 FROM public.delivery_provider_events e WHERE e.svix_event_id=p_event_id)
      OR EXISTS (SELECT 1 FROM public.delivery_provider_pending_events e WHERE e.svix_event_id=p_event_id) THEN
      RAISE EXCEPTION 'Webhook event ID already associated' USING ERRCODE='23505';
    END IF;
    INSERT INTO public.delivery_provider_identity_conflicts
      (svix_event_id,provider_email_id,original_recipient_fingerprint,
        signed_recipient_fingerprint,payload_sha256)
    VALUES (p_event_id,p_provider_email_id,v_associated,v_active,p_payload_sha256)
    ON CONFLICT (svix_event_id) DO NOTHING;
    IF NOT EXISTS (SELECT 1 FROM public.delivery_provider_identity_conflicts c
       WHERE c.svix_event_id=p_event_id AND c.provider_email_id=p_provider_email_id
         AND c.original_recipient_fingerprint=v_associated
         AND c.signed_recipient_fingerprint=v_active
         AND c.payload_sha256=p_payload_sha256) THEN
      RAISE EXCEPTION 'Provider identity conflict event ID reused' USING ERRCODE='23505';
    END IF;
    UPDATE public.delivery_recipient_state SET
      pending_unmatched=true,updated_at=clock_timestamp()
      WHERE recipient_fingerprint=v_associated;
    RETURN 'pending'; -- successful only after this transaction COMMITs
  END IF;
  -- Known match or unknown provider ID: lock all versions for this address.
  FOR v_fp IN SELECT * FROM deedlight_private.recipient_fingerprints(p_recipient_email) ORDER BY fingerprint LOOP
    INSERT INTO public.delivery_recipient_state(recipient_fingerprint)
      VALUES(v_fp.fingerprint) ON CONFLICT DO NOTHING;
    PERFORM 1 FROM public.delivery_recipient_state
      WHERE recipient_fingerprint=v_fp.fingerprint FOR UPDATE;
    IF v_fp.phase='active' THEN v_active:=v_fp.fingerprint; END IF;
  END LOOP;
  IF v_active IS NULL THEN RAISE EXCEPTION 'Missing active key' USING ERRCODE='42501'; END IF;
  v_result:=public.record_resend_webhook_event(
    p_event_id,p_provider_email_id,coalesce(v_associated,v_active),
    p_event_type,p_event_at,p_payload_sha256,p_suppression_reason);
  RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)
  TO service_role;

-- Remove *all* externally executable predecessor entry points. Definer-owned
-- helpers remain internal; callable rights for browser and service roles vanish.
REVOKE ALL ON FUNCTION public.begin_delivery_transport(uuid,uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.begin_delivery_transport_with_suppression(uuid,uuid,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.mark_delivery_sent_with_recipient(uuid,uuid,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
