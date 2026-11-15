\set ON_ERROR_STOP on
-- C79: catalog-only assertions for the committed 025–033 security surface.
-- Disposable PostgreSQL 16 only. Never establishes Production schema identity.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '20s';
WITH checks (invariant, passed) AS (
  VALUES
    ('kind_scoped_claim_exists',
      to_regprocedure('public.claim_delivery_jobs(text,timestamptz,integer)') IS NOT NULL),
    ('unscoped_claim_retired',
      to_regprocedure('public.claim_delivery_jobs(timestamptz,integer)') IS NULL),
    ('service_kind_claim_allowed',
      has_function_privilege('service_role','public.claim_delivery_jobs(text,timestamptz,integer)','EXECUTE')),
    ('browser_kind_claim_denied',
      NOT has_function_privilege('anon','public.claim_delivery_jobs(text,timestamptz,integer)','EXECUTE')
      AND NOT has_function_privilege('authenticated','public.claim_delivery_jobs(text,timestamptz,integer)','EXECUTE')),
    ('identity_bound_final_send_present',
      to_regprocedure('public.begin_delivery_transport_identity_bound(uuid,uuid,text)') IS NOT NULL),
    ('identity_bound_service_only',
      has_function_privilege('service_role','public.begin_delivery_transport_identity_bound(uuid,uuid,text)','EXECUTE')
      AND NOT has_function_privilege('anon','public.begin_delivery_transport_identity_bound(uuid,uuid,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','public.begin_delivery_transport_identity_bound(uuid,uuid,text)','EXECUTE')),
    ('legacy_final_send_service_denied',
      NOT has_function_privilege('service_role','public.begin_delivery_transport(uuid,uuid,text)','EXECUTE')),
    ('legacy_mark_sent_service_denied',
      NOT has_function_privilege('service_role','public.mark_delivery_sent(uuid,uuid,text)','EXECUTE')),
    ('new_delivery_webhook_service_only',
      has_function_privilege('service_role','public.deedlight_record_resend_delivery_v2(text,text,text,text,timestamptz,text,text,text)','EXECUTE')
      AND NOT has_function_privilege('anon','public.deedlight_record_resend_delivery_v2(text,text,text,text,timestamptz,text,text,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','public.deedlight_record_resend_delivery_v2(text,text,text,text,timestamptz,text,text,text)','EXECUTE')),
    ('new_suppression_webhook_service_only',
      has_function_privilege('service_role','public.deedlight_record_resend_suppression_verified(text,text,text,text,text,text,timestamptz,text)','EXECUTE')
      AND NOT has_function_privilege('anon','public.deedlight_record_resend_suppression_verified(text,text,text,text,text,text,timestamptz,text)','EXECUTE')
      AND NOT has_function_privilege('authenticated','public.deedlight_record_resend_suppression_verified(text,text,text,text,text,text,timestamptz,text)','EXECUTE')),
    ('legacy_webhook_service_denied',
      NOT has_function_privilege('service_role','public.deedlight_record_resend_verified(text,text,text,text,timestamptz,text,text)','EXECUTE')),
    ('new_webhooks_definer_fixed_path',
      (SELECT count(*)=2 FROM pg_catalog.pg_proc p
       JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public'
         AND p.proname IN ('deedlight_record_resend_delivery_v2','deedlight_record_resend_suppression_verified')
         AND p.prosecdef
         AND EXISTS (SELECT 1 FROM unnest(p.proconfig) cfg
                     WHERE replace(cfg,' ','')='search_path=pg_catalog,pg_temp'))),
    ('private_registry_unique_identity',
      EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
        WHERE c.conrelid='deedlight_event_private.provider_event_registry'::regclass
          AND c.contype='p')),
    ('registry_not_browser_accessible',
      NOT has_schema_privilege('anon','deedlight_event_private','USAGE')
      AND NOT has_schema_privilege('authenticated','deedlight_event_private','USAGE')
      AND NOT has_table_privilege('anon','deedlight_event_private.provider_event_registry','SELECT')
      AND NOT has_table_privilege('authenticated','deedlight_event_private.provider_event_registry','SELECT')),
    ('c76_private_tables_rls_and_privileges',
      (SELECT count(*)=4 AND coalesce(bool_and(c.relrowsecurity
          AND NOT has_table_privilege('anon',c.oid,'SELECT')
          AND NOT has_table_privilege('authenticated',c.oid,'SELECT')),false)
       FROM pg_catalog.pg_class c
       JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='deedlight_event_private'
       AND c.relname IN ('c76_bounce_classifications','c76_uncertain_bounces',
                         'c76_account_suppression_events','c76_account_suppression_recipients'))),
    ('c74_projection_guard_three_tables',
      (SELECT count(*)=3 FROM pg_catalog.pg_trigger t
       WHERE t.tgname='c74_lifecycle_guard' AND t.tgenabled='A'
         AND t.tgrelid IN ('public.delivery_provider_events'::regclass,
            'public.delivery_provider_pending_events'::regclass,
            'public.delivery_provider_identity_conflicts'::regclass))),
    ('c75_conflict_hold_always_trigger',
      EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
       WHERE tgname='c75_preserve_recipient_conflict_hold' AND tgenabled='A'
         AND tgrelid='public.delivery_recipient_state'::regclass)),
    ('c76_uncertain_bounce_always_trigger',
      EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
       WHERE tgname='c76_preserve_uncertain_bounce_hold' AND tgenabled='A'
         AND tgrelid='public.delivery_recipient_state'::regclass)),
    ('recipient_keyring_exists',
      to_regclass('deedlight_private.delivery_recipient_keyring') IS NOT NULL)
)
SELECT pg_catalog.jsonb_build_object(
  'invariant',invariant,'passed',passed,'source_tree','5b9fa485c0dcc67beb5b82e9623e5dff4e93260b'
) AS c79_catalog_security_assertion
FROM checks ORDER BY invariant;
ROLLBACK;
