-- Disposable PostgreSQL 16 fixture only. Never run against Production.
\getenv fixture_auditor_password DEEDLIGHT_FIXTURE_AUDITOR_PASSWORD
\getenv fixture_spoofed_password DEEDLIGHT_FIXTURE_SPOOFED_PASSWORD
\getenv fixture_privileged_password DEEDLIGHT_FIXTURE_PRIVILEGED_PASSWORD
DROP SCHEMA IF EXISTS supabase_migrations CASCADE;
DROP FUNCTION IF EXISTS public.audit_fixture_security_definer_identity() CASCADE;
DROP FUNCTION IF EXISTS public.audit_fixture_privileged_definer_identity() CASCADE;
DROP FUNCTION IF EXISTS public.audit_fixture_custom_guc() CASCADE;
DROP FUNCTION IF EXISTS public.audit_fixture_bad_search_path() CASCADE;
DROP TABLE IF EXISTS public.audit_fixture_private CASCADE;
DROP TABLE IF EXISTS public.audit_fixture_termination_marker CASCADE;
DROP SEQUENCE IF EXISTS public.audit_fixture_sequence CASCADE;

DO $cleanup$
DECLARE
  v_role text;
BEGIN
  FOR v_role IN
    SELECT rolname
    FROM pg_catalog.pg_roles
    WHERE rolname = ANY (ARRAY[
      'deedlight_catalog_auditor',
      'deedlight_audit_spoofed_login',
      'deedlight_audit_switch_target',
      'deedlight_audit_nested_parent',
      'deedlight_audit_nested_leaf',
      'deedlight_audit_privileged_login',
      'deedlight_audit_definer_owner'
    ])
  LOOP
    EXECUTE format('DROP OWNED BY %I', v_role);
    EXECUTE format('DROP ROLE %I', v_role);
  END LOOP;
END;
$cleanup$;

CREATE ROLE deedlight_catalog_auditor LOGIN PASSWORD :'fixture_auditor_password' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE deedlight_audit_spoofed_login LOGIN PASSWORD :'fixture_spoofed_password' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE deedlight_audit_switch_target NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE deedlight_audit_nested_parent NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE deedlight_audit_nested_leaf NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE deedlight_audit_privileged_login LOGIN PASSWORD :'fixture_privileged_password' SUPERUSER;
CREATE ROLE deedlight_audit_definer_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;

CREATE SCHEMA supabase_migrations;
CREATE TABLE supabase_migrations.schema_migrations (
  version text NOT NULL PRIMARY KEY,
  statements text[],
  name text
);
INSERT INTO supabase_migrations.schema_migrations(version, statements, name)
VALUES ('202611240038', ARRAY['SELECT 1'], 'fixture_migration');

CREATE TABLE public.audit_fixture_private (id bigint, private_value text);
CREATE SEQUENCE public.audit_fixture_sequence OWNED BY public.audit_fixture_private.id;
CREATE TABLE public.audit_fixture_termination_marker (id integer PRIMARY KEY);

REVOKE SELECT ON pg_catalog.pg_roles FROM PUBLIC;
GRANT USAGE ON SCHEMA supabase_migrations TO deedlight_catalog_auditor;
GRANT SELECT ON supabase_migrations.schema_migrations TO deedlight_catalog_auditor;

GRANT SELECT ON pg_catalog.pg_class, pg_catalog.pg_attribute, pg_catalog.pg_attrdef,
  pg_catalog.pg_proc, pg_catalog.pg_auth_members, pg_catalog.pg_namespace,
  pg_catalog.pg_language, pg_catalog.pg_policies, pg_catalog.pg_constraint,
  pg_catalog.pg_indexes, pg_catalog.pg_trigger, pg_catalog.pg_default_acl,
  pg_catalog.pg_extension, pg_catalog.pg_sequence, pg_catalog.pg_index,
  pg_catalog.pg_depend, pg_catalog.pg_type, pg_catalog.pg_am, pg_catalog.pg_roles
TO deedlight_catalog_auditor, deedlight_audit_definer_owner;

CREATE FUNCTION public.audit_fixture_security_definer_identity()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog'
AS $fixture$
DECLARE
  v_session_role_oid oid;
  v_effective_role_oid oid;
BEGIN
  IF session_user <> 'deedlight_catalog_auditor'
    OR current_setting('deedlight.authenticated_principal', true) IS DISTINCT FROM session_user
    OR current_setting('role', true) IS DISTINCT FROM 'none' THEN
    RAISE EXCEPTION 'Fixture SECURITY DEFINER identity rejected.';
  END IF;
  SELECT oid INTO v_session_role_oid FROM pg_catalog.pg_roles WHERE rolname = session_user;
  SELECT oid INTO v_effective_role_oid FROM pg_catalog.pg_roles WHERE rolname = current_user;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE oid = v_session_role_oid AND rolcanlogin
      AND NOT rolsuper AND NOT rolcreaterole AND NOT rolcreatedb
      AND NOT rolreplication AND NOT rolbypassrls
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE oid = v_effective_role_oid
      AND NOT rolsuper AND NOT rolcreaterole AND NOT rolcreatedb
      AND NOT rolreplication AND NOT rolbypassrls
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles r
    WHERE r.oid <> v_session_role_oid
      AND pg_catalog.pg_has_role(v_session_role_oid, r.oid, 'MEMBER')
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles r
    WHERE r.oid <> v_effective_role_oid
      AND pg_catalog.pg_has_role(v_effective_role_oid, r.oid, 'MEMBER')
  ) THEN
    RAISE EXCEPTION 'Fixture SECURITY DEFINER role attributes or memberships rejected.';
  END IF;
  RETURN current_user || ':' || session_user;
END;
$fixture$;
ALTER FUNCTION public.audit_fixture_security_definer_identity()
  OWNER TO deedlight_audit_definer_owner;
GRANT EXECUTE ON FUNCTION public.audit_fixture_security_definer_identity()
  TO deedlight_catalog_auditor;

CREATE FUNCTION public.audit_fixture_privileged_definer_identity()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog, public'
AS $fixture$
DECLARE
  v_session_role_oid oid;
  v_effective_role_oid oid;
BEGIN
  IF session_user <> 'deedlight_catalog_auditor'
    OR current_setting('deedlight.authenticated_principal', true) IS DISTINCT FROM session_user
    OR current_setting('role', true) IS DISTINCT FROM 'none' THEN
    RAISE EXCEPTION 'Fixture SECURITY DEFINER identity rejected.';
  END IF;
  SELECT oid INTO v_session_role_oid FROM pg_catalog.pg_roles WHERE rolname = session_user;
  SELECT oid INTO v_effective_role_oid FROM pg_catalog.pg_roles WHERE rolname = current_user;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE oid = v_session_role_oid AND rolcanlogin
      AND NOT rolsuper AND NOT rolcreaterole AND NOT rolcreatedb
      AND NOT rolreplication AND NOT rolbypassrls
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE oid = v_effective_role_oid
      AND NOT rolsuper AND NOT rolcreaterole AND NOT rolcreatedb
      AND NOT rolreplication AND NOT rolbypassrls
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles r
    WHERE r.oid <> v_session_role_oid
      AND pg_catalog.pg_has_role(v_session_role_oid, r.oid, 'MEMBER')
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles r
    WHERE r.oid <> v_effective_role_oid
      AND pg_catalog.pg_has_role(v_effective_role_oid, r.oid, 'MEMBER')
  ) THEN
    RAISE EXCEPTION 'Fixture SECURITY DEFINER role attributes or memberships rejected.';
  END IF;
  RETURN current_user || ':' || session_user;
END;
$fixture$;
ALTER FUNCTION public.audit_fixture_privileged_definer_identity()
  OWNER TO deedlight_audit_privileged_login;
GRANT EXECUTE ON FUNCTION public.audit_fixture_privileged_definer_identity()
  TO deedlight_catalog_auditor;
