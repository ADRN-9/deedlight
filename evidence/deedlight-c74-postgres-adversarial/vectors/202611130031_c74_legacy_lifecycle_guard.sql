-- C74 isolated post-030 security correction. Review and test only.
-- Prevent direct or SECURITY DEFINER inserts that project one provider event
-- into an incompatible legacy lifecycle table. Preserve every historical row.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='45s';
DO $c74_preflight$
DECLARE v_n int;
BEGIN
 IF to_regclass('deedlight_event_private.provider_event_registry') IS NULL
    OR to_regclass('public.delivery_provider_events') IS NULL
    OR to_regclass('public.delivery_provider_pending_events') IS NULL
    OR to_regclass('public.delivery_provider_identity_conflicts') IS NULL
    OR to_regprocedure('public.deedlight_record_resend_verified(text,text,text,text,timestamptz,text,text)') IS NULL
 THEN RAISE EXCEPTION 'C74 requires authentic integrated migration 030 first' USING ERRCODE='55000';
 END IF;
 SELECT count(*) INTO v_n FROM pg_catalog.pg_trigger
 WHERE tgname='c73_registry_guard' AND tgenabled='A'
 AND tgrelid IN ('public.delivery_provider_events'::regclass,
     'public.delivery_provider_pending_events'::regclass,
     'public.delivery_provider_identity_conflicts'::regclass);
 IF v_n<>3 THEN
   RAISE EXCEPTION 'C74 refuses unknown legacy registry trigger graph' USING ERRCODE='55000';
 END IF;
 IF to_regprocedure('deedlight_event_private.c74_legacy_projection_guard()') IS NOT NULL THEN
   RAISE EXCEPTION 'C74 patch already applied; stop on unexpected migration state' USING ERRCODE='55000';
 END IF;
END $c74_preflight$;

CREATE FUNCTION deedlight_event_private.c74_legacy_projection_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $guard$
DECLARE v_state text;
BEGIN
 SELECT state INTO v_state FROM deedlight_event_private.provider_event_registry
   WHERE provider='resend' AND event_id=NEW.svix_event_id FOR KEY SHARE;
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Unregistered provider event' USING ERRCODE='42501';
 END IF;
 IF TG_TABLE_NAME='delivery_provider_pending_events' THEN
   IF v_state<>'pending'
     OR EXISTS (SELECT 1 FROM public.delivery_provider_events p
        WHERE p.svix_event_id=NEW.svix_event_id)
     OR EXISTS (SELECT 1 FROM public.delivery_provider_identity_conflicts c
        WHERE c.svix_event_id=NEW.svix_event_id) THEN
     RAISE EXCEPTION 'Processed or conflicted provider event cannot be pending' USING ERRCODE='42501';
   END IF;
 ELSIF TG_TABLE_NAME='delivery_provider_events' THEN
   -- During legitimate pending promotion, the registry state stays pending
   -- until the processed projection exists; the pending row is removed before
   -- commit by the existing recipient-bound mark-sent transaction.
   IF v_state NOT IN ('pending','processed')
     OR EXISTS (SELECT 1 FROM public.delivery_provider_identity_conflicts c
        WHERE c.svix_event_id=NEW.svix_event_id) THEN
     RAISE EXCEPTION 'Identity-conflicted provider event cannot be processed' USING ERRCODE='42501';
   END IF;
 ELSIF TG_TABLE_NAME='delivery_provider_identity_conflicts' THEN
   IF v_state<>'identity_conflict' THEN
     RAISE EXCEPTION 'Nonconflicted provider event cannot enter quarantine' USING ERRCODE='42501';
   END IF;
 ELSE
   RAISE EXCEPTION 'Unexpected provider event lifecycle table' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION deedlight_event_private.c74_legacy_projection_guard()
  FROM PUBLIC,anon,authenticated,service_role;
DO $install$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY[
   'delivery_provider_events','delivery_provider_pending_events',
   'delivery_provider_identity_conflicts'
 ] LOOP
   EXECUTE format(
     'CREATE TRIGGER c74_lifecycle_guard BEFORE INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION deedlight_event_private.c74_legacy_projection_guard()',t);
   EXECUTE format('ALTER TABLE public.%I ENABLE ALWAYS TRIGGER c74_lifecycle_guard',t);
 END LOOP;
END $install$;
COMMIT;
