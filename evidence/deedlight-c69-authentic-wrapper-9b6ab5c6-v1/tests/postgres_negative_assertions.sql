-- Run only after authentic 019-028, C61 disabled registry and C69 hard stop.
-- All event identities and data are synthetic; no outbound network calls.
\set ON_ERROR_STOP on
DO $checks$
DECLARE
  v_fn text;
  v_table text;
  v_count bigint;
  v_error text;
BEGIN
  FOR v_fn IN SELECT pg_catalog.unnest(ARRAY[
    'public.begin_delivery_transport(uuid,uuid,text)',
    'public.begin_delivery_transport_with_suppression(uuid,uuid,text,text)',
    'public.begin_delivery_transport_identity_bound(uuid,uuid,text)',
    'public.mark_delivery_sent(uuid,uuid,text)',
    'public.mark_delivery_sent_with_recipient(uuid,uuid,text,text)',
    'public.mark_delivery_sent_identity_bound(uuid,uuid,text)',
    'public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)',
    'public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)',
    'public.deedlight_reserve_provider_event(text,text,bytea,text,text)',
    'public.deedlight_bind_provider_event(text,text)',
    'public.deedlight_process_nonsuppressing_event(text,text)'
  ]) LOOP
    IF pg_catalog.has_function_privilege('service_role',v_fn,'EXECUTE')
       OR pg_catalog.has_function_privilege('anon',v_fn,'EXECUTE')
       OR pg_catalog.has_function_privilege('authenticated',v_fn,'EXECUTE') THEN
      RAISE EXCEPTION 'C69 failure: externally callable function %',v_fn;
    END IF;
  END LOOP;

  -- Even an owner/indirect definer invocation must fail before touching data.
  BEGIN
    PERFORM public.begin_delivery_transport_identity_bound(NULL,NULL,NULL);
    RAISE EXCEPTION 'C69 identity transport wrapper unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error NOT LIKE 'C69 %' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.begin_delivery_transport_with_suppression(NULL,NULL,NULL,NULL);
    RAISE EXCEPTION 'C69 suppression transport wrapper unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error NOT LIKE 'C69 %' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.begin_delivery_transport(NULL,NULL,NULL);
    RAISE EXCEPTION 'C69 base transport unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error NOT LIKE 'C69 %' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.record_resend_webhook_event('msg_c69event001','provider.synthetic',repeat('a',64),
      'email.bounced',clock_timestamp(),repeat('b',64),'permanent_bounce');
    RAISE EXCEPTION 'C69 base record RPC unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error NOT LIKE 'C69 %' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.record_resend_webhook_event_identity_bound('msg_c69event001','provider.synthetic',
      'test@example.invalid','email.complained',clock_timestamp(),repeat('c',64),'spam_complaint');
    RAISE EXCEPTION 'C69 identity-bound record RPC unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error NOT LIKE 'C69 %' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.mark_delivery_sent_identity_bound(NULL,NULL,'provider.synthetic');
    RAISE EXCEPTION 'C69 mark-sent wrapper unexpectedly accepted';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error NOT LIKE 'C69 %' THEN RAISE; END IF;
  END;

  FOREACH v_table IN ARRAY ARRAY[
    'delivery_provider_events','delivery_provider_pending_events',
    'delivery_provider_identity_conflicts'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger tr
      JOIN pg_catalog.pg_class c ON tr.tgrelid=c.oid
      WHERE c.oid=pg_catalog.to_regclass('public.'||v_table)
        AND tr.tgname='c69_veto_event_dml' AND tr.tgenabled='A'
    ) OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_trigger tr
      WHERE tr.tgrelid=pg_catalog.to_regclass('public.'||v_table)
        AND tr.tgname='c69_veto_event_truncate' AND tr.tgenabled='A'
    ) THEN RAISE EXCEPTION 'C69 missing always-on table veto %',v_table; END IF;

    BEGIN
      EXECUTE pg_catalog.format('INSERT INTO public.%I DEFAULT VALUES',v_table);
      RAISE EXCEPTION 'C69 table write bypass %',v_table;
    EXCEPTION WHEN SQLSTATE '42501' THEN
      GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
      IF v_error NOT LIKE 'C69 %' THEN RAISE; END IF;
    END;
    BEGIN
      EXECUTE pg_catalog.format('TRUNCATE public.%I',v_table);
      RAISE EXCEPTION 'C69 table truncation bypass %',v_table;
    EXCEPTION WHEN SQLSTATE '42501' THEN
      GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
      IF v_error NOT LIKE 'C69 %' THEN RAISE; END IF;
    END;
  END LOOP;

  IF (SELECT accepting_new_events FROM deedlight_event_private.registry_control
      WHERE singleton=true) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'C69 registry unexpectedly enabled';
  END IF;
  BEGIN
    UPDATE deedlight_event_private.registry_control SET accepting_new_events=true
      WHERE singleton=true;
    RAISE EXCEPTION 'C69 registry unexpectedly activated';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error NOT LIKE 'C69 %' THEN RAISE; END IF;
  END;
  SELECT count(*) INTO v_count FROM deedlight_event_private.c69_retired_function_inventory;
  IF v_count<>8 THEN RAISE EXCEPTION 'C69 unexpected function count %',v_count; END IF;
END $checks$;

-- Count historical records separately: C69 must not delete or update any.
SELECT 'C69_PG16_NEGATIVE_ASSERTIONS_PASSED' AS result;
DO $history$
DECLARE v_error text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.delivery_provider_pending_events
      WHERE svix_event_id='msg_c69pending001')
    OR NOT EXISTS (SELECT 1 FROM public.delivery_provider_identity_conflicts
      WHERE svix_event_id='msg_c69conflict001') THEN
    RAISE EXCEPTION 'C69 historical quarantine rows were modified or lost';
  END IF;
  BEGIN
    DELETE FROM public.delivery_provider_pending_events
      WHERE svix_event_id='msg_c69pending001';
    RAISE EXCEPTION 'C69 pending deletion allowed';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error NOT LIKE 'C69 %' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.delivery_provider_identity_conflicts
      SET payload_sha256=repeat('f',64) WHERE svix_event_id='msg_c69conflict001';
    RAISE EXCEPTION 'C69 conflict overwrite allowed';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error NOT LIKE 'C69 %' THEN RAISE; END IF;
  END;
END $history$;
SELECT 'C69_HISTORICAL_QUARANTINE_PRESERVED' AS result;
-- Browser and service roles cannot reach the retired entry points or event stores.
SET ROLE anon;
DO $anon_security$
BEGIN
  IF pg_catalog.has_function_privilege(current_user,
       'public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)',
       'EXECUTE')
     OR pg_catalog.has_function_privilege(current_user,
       'public.begin_delivery_transport_identity_bound(uuid,uuid,text)','EXECUTE')
     OR pg_catalog.has_table_privilege(current_user,
       'public.delivery_provider_identity_conflicts','INSERT') THEN
    RAISE EXCEPTION 'C69 anon role unexpectedly retains lifecycle access';
  END IF;
END $anon_security$;
RESET ROLE;
SET ROLE authenticated;
DO $authenticated_security$
BEGIN
  IF pg_catalog.has_function_privilege(current_user,
       'public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)','EXECUTE')
     OR pg_catalog.has_function_privilege(current_user,
       'public.begin_delivery_transport_with_suppression(uuid,uuid,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'C69 browser role unexpectedly retains legacy RPC access';
  END IF;
END $authenticated_security$;
RESET ROLE;
SET ROLE service_role;
DO $service_security$
BEGIN
  IF pg_catalog.has_function_privilege(current_user,
       'public.begin_delivery_transport_identity_bound(uuid,uuid,text)','EXECUTE')
     OR pg_catalog.has_function_privilege(current_user,
       'public.mark_delivery_sent_identity_bound(uuid,uuid,text)','EXECUTE')
     OR pg_catalog.has_function_privilege(current_user,
       'public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)','EXECUTE')
     OR pg_catalog.has_function_privilege(current_user,
       'public.deedlight_reserve_provider_event(text,text,bytea,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'C69 service role unexpectedly retains lifecycle RPC access';
  END IF;
END $service_security$;
RESET ROLE;
SELECT 'C69_BROWSER_AND_SERVICE_ROLE_GATES_PASSED' AS result;
