-- Disposable PostgreSQL 16 ownership-audit fixture. Synthetic identities only.
BEGIN;

CREATE ROLE deedlight_fixture_owner NOLOGIN INHERIT;
CREATE ROLE deedlight_fixture_middle NOLOGIN INHERIT;
CREATE ROLE deedlight_fixture_privileged NOLOGIN CREATEROLE BYPASSRLS;
CREATE ROLE deedlight_fixture_inherited NOLOGIN INHERIT;
CREATE ROLE deedlight_fixture_setonly NOLOGIN INHERIT;
CREATE ROLE deedlight_fixture_acl_reader NOLOGIN;
GRANT CREATE ON SCHEMA public TO deedlight_fixture_owner;

DO $fixture$
DECLARE
  signature text;
BEGIN
  FOREACH signature IN ARRAY ARRAY[
    'public.is_admin()',
    'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)',
    'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)',
    'public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)',
    'public.record_delivery_provider_event(text,text,text,text,text)',
    'public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)',
    'public._record_delivery_provider_integrity_conflict(text,text,text,text,text,text,text,timestamptz,text,text,text,text,text,timestamptz,text,text,text)',
    'public._record_delivery_provider_lifecycle_event_pre037_impl(text,text,text,text,timestamptz,text,text,text,text)',
    'public._record_delivery_provider_suppression_event_pre037_impl(text,text,text,text,text,text,timestamptz,timestamptz,text)',
    'public._deny_delivery_provider_integrity_audit_mutation()',
    'public.admin_list_delivery_provider_integrity_conflicts(text,integer)',
    'public.admin_list_delivery_provider_integrity_evidence(bigint,integer)',
    'public.admin_list_delivery_provider_integrity_history(bigint,integer)',
    'public.admin_resolve_delivery_provider_integrity_conflict(bigint,text)',
    'public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamptz,bigint)',
    'public.admin_get_delivery_provider_integrity_conflict(bigint)',
    'public.admin_list_delivery_provider_integrity_evidence_page(bigint,integer,timestamptz,bigint)',
    'public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)'
  ]
  LOOP
    EXECUTE format(
      'CREATE FUNCTION %s RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog AS %L',
      signature,
      'SELECT 1'
    );
    EXECUTE format('ALTER FUNCTION %s OWNER TO deedlight_fixture_owner', signature);
  END LOOP;
  REVOKE CREATE ON SCHEMA public FROM deedlight_fixture_owner;
END
$fixture$;

-- Distinguish a stored ACL from PostgreSQL's default function ACL.
REVOKE ALL PRIVILEGES ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO deedlight_fixture_acl_reader;

-- Direct inherited membership, recursive SET-only membership, and two direct edge variants.
GRANT deedlight_fixture_middle TO deedlight_fixture_owner
  WITH INHERIT TRUE, SET TRUE;
GRANT deedlight_fixture_privileged TO deedlight_fixture_middle
  WITH INHERIT FALSE, SET TRUE;
GRANT deedlight_fixture_inherited TO deedlight_fixture_owner
  WITH INHERIT TRUE, SET TRUE;
GRANT deedlight_fixture_setonly TO deedlight_fixture_owner
  WITH INHERIT FALSE, SET TRUE;

COMMIT;
