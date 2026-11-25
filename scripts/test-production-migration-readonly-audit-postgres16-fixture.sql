-- Disposable PostgreSQL 16 fixture only. Never run against Production.
DROP SCHEMA IF EXISTS supabase_migrations CASCADE;
DROP TABLE IF EXISTS public.audit_fixture_private CASCADE;
DROP SEQUENCE IF EXISTS public.audit_fixture_sequence CASCADE;

CREATE ROLE deedlight_audit_approved NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE deedlight_audit_bad_membership NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE deedlight_audit_missing_history NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE deedlight_audit_missing_catalog NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE deedlight_audit_app_table NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE deedlight_audit_app_column NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE deedlight_audit_app_sequence NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

CREATE SCHEMA supabase_migrations;
CREATE TABLE supabase_migrations.schema_migrations (
  version text PRIMARY KEY,
  name text NOT NULL,
  statements text[] NOT NULL
);
INSERT INTO supabase_migrations.schema_migrations(version, name, statements)
VALUES ('202611240038', 'fixture_migration', ARRAY['SELECT 1']);

CREATE TABLE public.audit_fixture_private (id bigint, private_value text);
CREATE SEQUENCE public.audit_fixture_sequence OWNED BY public.audit_fixture_private.id;

REVOKE SELECT ON pg_catalog.pg_roles FROM PUBLIC;
GRANT USAGE ON SCHEMA supabase_migrations TO deedlight_audit_approved,
  deedlight_audit_bad_membership, deedlight_audit_missing_history,
  deedlight_audit_missing_catalog, deedlight_audit_app_table,
  deedlight_audit_app_column, deedlight_audit_app_sequence;
GRANT SELECT ON supabase_migrations.schema_migrations TO deedlight_audit_approved,
  deedlight_audit_bad_membership, deedlight_audit_missing_catalog,
  deedlight_audit_app_table, deedlight_audit_app_column, deedlight_audit_app_sequence;

GRANT SELECT ON pg_catalog.pg_class, pg_catalog.pg_attribute, pg_catalog.pg_proc,
  pg_catalog.pg_auth_members, pg_catalog.pg_namespace, pg_catalog.pg_language,
  pg_catalog.pg_policies, pg_catalog.pg_constraint, pg_catalog.pg_indexes,
  pg_catalog.pg_trigger, pg_catalog.pg_default_acl, pg_catalog.pg_extension,
  pg_catalog.pg_sequence, pg_catalog.pg_index, pg_catalog.pg_depend, pg_catalog.pg_type
TO deedlight_audit_approved, deedlight_audit_bad_membership,
  deedlight_audit_missing_history, deedlight_audit_missing_catalog,
  deedlight_audit_app_table, deedlight_audit_app_column, deedlight_audit_app_sequence;
GRANT SELECT ON pg_catalog.pg_roles TO deedlight_audit_approved,
  deedlight_audit_bad_membership, deedlight_audit_missing_history,
  deedlight_audit_app_table, deedlight_audit_app_column, deedlight_audit_app_sequence;

GRANT pg_read_all_data TO deedlight_audit_bad_membership;
GRANT SELECT ON public.audit_fixture_private TO deedlight_audit_app_table;
GRANT SELECT (private_value) ON public.audit_fixture_private TO deedlight_audit_app_column;
GRANT USAGE ON SEQUENCE public.audit_fixture_sequence TO deedlight_audit_app_sequence;
