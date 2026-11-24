-- Explicit, fail-closed bridge between historical Sprint 6 migration 007 and Migration 038.
-- The initial schema declares profiles.is_suspended NOT NULL DEFAULT false.
-- Sprint 6 added COALESCE defensively, but that is semantically equivalent only while
-- the NOT NULL invariant remains enforced. Restore the exact reviewed helper source
-- expected by Migration 038; never normalize an unknown function definition.

begin;

do $migration_038_admin_compatibility_preflight$
declare
  v_source text;
  v_source_hash text;
  v_security_definer boolean;
  v_config text[];
  v_suspended_not_null boolean;
  v_crypto_schema text;
begin
  select n.nspname into v_crypto_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_crypto_schema is null then
    raise exception 'Migration 038 compatibility requires pgcrypto.' using errcode = '55000';
  end if;

  if to_regclass('public.profiles') is null
    or to_regprocedure('public.is_admin()') is null then
    raise exception 'Migration 038 compatibility requires public.profiles and public.is_admin().' using errcode = '55000';
  end if;

  select a.attnotnull into v_suspended_not_null
  from pg_catalog.pg_attribute a
  where a.attrelid = 'public.profiles'::regclass
    and a.attname = 'is_suspended'
    and a.attnum > 0
    and not a.attisdropped;

  if v_suspended_not_null is distinct from true
    or exists (select 1 from public.profiles where is_suspended is null) then
    raise exception 'Migration 038 compatibility requires profiles.is_suspended to remain NOT NULL with no NULL rows.' using errcode = '55000';
  end if;

  select p.prosrc, p.prosecdef, p.proconfig
    into v_source, v_security_definer, v_config
  from pg_catalog.pg_proc p
  where p.oid = 'public.is_admin()'::regprocedure;

  if v_security_definer is distinct from true
    or v_config is distinct from array['search_path=public']::text[] then
    raise exception 'Migration 038 compatibility rejected is_admin() SECURITY DEFINER/search_path drift.' using errcode = '55000';
  end if;

  execute format(
    'select encode(%I.digest(convert_to($1, ''UTF8''), ''sha256''), ''hex'')',
    v_crypto_schema
  ) into v_source_hash using v_source;

  if v_source_hash is distinct from '4fb49052b2e525d8b355123d430df7e536a4da5207fd6ef3d21f3b2d770e98e0' then
    raise exception 'Migration 038 compatibility rejected unreviewed Sprint 6 is_admin() source.' using errcode = '55000';
  end if;

  if not has_function_privilege('anon', 'public.is_admin()', 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.is_admin()', 'EXECUTE')
    or not has_function_privilege('service_role', 'public.is_admin()', 'EXECUTE') then
    raise exception 'Migration 038 compatibility rejected is_admin() execution grant drift.' using errcode = '55000';
  end if;
end;
$migration_038_admin_compatibility_preflight$;

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where user_id = auth.uid()
      and role = 'admin'
      and is_suspended = false
  );
$$;

do $migration_038_admin_compatibility_postflight$
declare
  v_source text;
  v_source_hash text;
  v_security_definer boolean;
  v_config text[];
  v_crypto_schema text;
begin
  select n.nspname into v_crypto_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  select p.prosrc, p.prosecdef, p.proconfig
    into v_source, v_security_definer, v_config
  from pg_catalog.pg_proc p
  where p.oid = 'public.is_admin()'::regprocedure;

  execute format(
    'select encode(%I.digest(convert_to($1, ''UTF8''), ''sha256''), ''hex'')',
    v_crypto_schema
  ) into v_source_hash using v_source;

  if v_source_hash is distinct from '85e6838cf8feec05bcfe9e9051e5192bc8f0d42f7a53cb6c0450067d70bba74b'
    or v_security_definer is distinct from true
    or v_config is distinct from array['search_path=public']::text[] then
    raise exception 'Migration 038 compatibility failed to establish the exact reviewed is_admin() source and execution context.' using errcode = '55000';
  end if;

  if not has_function_privilege('anon', 'public.is_admin()', 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.is_admin()', 'EXECUTE')
    or not has_function_privilege('service_role', 'public.is_admin()', 'EXECUTE') then
    raise exception 'Migration 038 compatibility failed to preserve is_admin() execution grants.' using errcode = '55000';
  end if;
end;
$migration_038_admin_compatibility_postflight$;

commit;
