-- Explicit, fail-closed bridge between historical Sprint 6 migration 007 and Migration 038.
-- Sprint 6 added COALESCE defensively; restore the exact reviewed Migration 038 helper
-- only while profiles.is_suspended remains NOT NULL and contains no NULL values.
--
-- Ownership acceptance is deliberately separate from this bridge. No Production owner
-- is hardcoded: this transaction resolves the existing owner, preserves its OID/name,
-- and proves replacement cannot silently change ownership. Production acceptance still
-- requires authoritative Query 8A/8B evidence and DBA/security approval.
--
-- ACL contract comes from Sprint 6's explicit GRANT EXECUTE to anon and authenticated.
-- PostgreSQL's effective default ACL may additionally include PUBLIC. Preserve that
-- existing PUBLIC state, reject every other explicit grantee, reject inherited EXECUTE
-- outside the owner/application roles when PUBLIC is absent, and compare ACL/default
-- ACL snapshots byte-for-byte (canonical JSON) before and after replacement.

begin;

do $migration_038_admin_compatibility_preflight$
declare
  v_source text;
  v_source_hash text;
  v_security_definer boolean;
  v_config text[];
  v_suspended_not_null boolean;
  v_crypto_schema text;
  v_function_oid oid := 'public.is_admin()'::regprocedure;
  v_owner_oid oid;
  v_owner_name name;
  v_acl jsonb;
  v_default_acl jsonb;
  v_public_execute boolean;
  v_is_canonical boolean;
begin
  select n.nspname into v_crypto_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_crypto_schema is null then
    raise exception 'Migration 038 compatibility requires pgcrypto.' using errcode = '55000';
  end if;

  if to_regclass('public.profiles') is null
    or v_function_oid is null then
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

  select p.prosrc, p.prosecdef, p.proconfig, p.proowner, owner_role.rolname
    into v_source, v_security_definer, v_config, v_owner_oid, v_owner_name
  from pg_catalog.pg_proc p
  left join pg_catalog.pg_roles owner_role on owner_role.oid = p.proowner
  where p.oid = v_function_oid;

  if v_owner_oid is null or v_owner_name is null then
    raise exception 'Migration 038 compatibility rejected unresolved is_admin() owner.' using errcode = '55000';
  end if;

  if v_security_definer is distinct from true
    or v_config is distinct from array['search_path=public']::text[] then
    raise exception 'Migration 038 compatibility rejected is_admin() SECURITY DEFINER/search_path drift.' using errcode = '55000';
  end if;

  execute format(
    'select encode(%I.digest(convert_to($1, ''UTF8''), ''hex''), ''hex'')',
    v_crypto_schema
  ) into v_source_hash using v_source;

  if v_source_hash = '85e6838cf8feec05bcfe9e9051e5192bc8f0d42f7a53cb6c0450067d70bba74b' then
    v_is_canonical := true;
  elsif v_source_hash = '4fb49052b2e525d8b355123d430df7e536a4da5207fd6ef3d21f3b2d770e98e0' then
    v_is_canonical := false;
  else
    raise exception 'Migration 038 compatibility rejected unreviewed is_admin() source.' using errcode = '55000';
  end if;

  -- Compare the effective ACL, including PostgreSQL's default ACL when proacl is NULL.
  select COALESCE(jsonb_agg(jsonb_build_object(
    'grantee', acl.grantee,
    'grantor', acl.grantor,
    'privilege', acl.privilege_type,
    'grantable', acl.is_grantable
  ) order by acl.grantee, acl.grantor, acl.privilege_type, acl.is_grantable), '[]'::jsonb)
    into v_acl
  from pg_catalog.aclexplode((
    select COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
    from pg_catalog.pg_proc p where p.oid = v_function_oid
  )) acl;

  if not exists (
    select 1 from pg_catalog.aclexplode((
      select COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
      from pg_catalog.pg_proc p where p.oid = v_function_oid
    )) acl
    where acl.grantee = 'anon'::regrole::oid
      and acl.privilege_type = 'EXECUTE'
      and not acl.is_grantable
  ) or not exists (
    select 1 from pg_catalog.aclexplode((
      select COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
      from pg_catalog.pg_proc p where p.oid = v_function_oid
    )) acl
    where acl.grantee = 'authenticated'::regrole::oid
      and acl.privilege_type = 'EXECUTE'
      and not acl.is_grantable
  ) then
    raise exception 'Migration 038 compatibility rejected missing historical anon/authenticated EXECUTE grants.' using errcode = '55000';
  end if;

  if exists (
    select 1
    from pg_catalog.aclexplode((
      select COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
      from pg_catalog.pg_proc p where p.oid = v_function_oid
    )) acl
    where acl.privilege_type <> 'EXECUTE'
      or acl.is_grantable
      or acl.grantor <> v_owner_oid
      or acl.grantee not in (0, v_owner_oid, 'anon'::regrole::oid, 'authenticated'::regrole::oid)
  ) then
    raise exception 'Migration 038 compatibility rejected unexpected direct function EXECUTE ACL grantee or grant option.' using errcode = '55000';
  end if;

  select exists (
    select 1 from pg_catalog.aclexplode((
      select COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
      from pg_catalog.pg_proc p where p.oid = v_function_oid
    )) acl
    where acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  ) into v_public_execute;

  -- Without PUBLIC EXECUTE, only the function owner and the two historical
  -- application grantees may have effective EXECUTE, including through membership.
  if not v_public_execute and exists (
    select 1
    from pg_catalog.pg_roles r
    where r.oid not in (v_owner_oid, 'anon'::regrole::oid, 'authenticated'::regrole::oid)
      and not r.rolsuper
      and not r.rolsuper
      and pg_catalog.has_function_privilege(r.oid, v_function_oid, 'EXECUTE')
  ) then
    raise exception 'Migration 038 compatibility rejected unexpected inherited/effective function EXECUTE privilege.' using errcode = '55000';
  end if;

  -- Default ACLs do not retroactively change this function, but capture the exact
  -- owner/global/public-schema defaults so replacement cannot conceal concurrent drift.
  select COALESCE(jsonb_agg(jsonb_build_object(
    'schema', d.defaclnamespace,
    'acl', d.defaclacl::text
  ) order by d.defaclnamespace), '[]'::jsonb)
    into v_default_acl
  from pg_catalog.pg_default_acl d
  where d.defaclrole = v_owner_oid
    and d.defaclobjtype = 'f'
    and (d.defaclnamespace = 0 or d.defaclnamespace = 'public'::regnamespace);

  perform set_config('deedlight.migration038.owner_oid', v_owner_oid::text, true);
  perform set_config('deedlight.migration038.owner_name', v_owner_name::text, true);
  perform set_config('deedlight.migration038.acl_snapshot', v_acl::text, true);
  perform set_config('deedlight.migration038.default_acl_snapshot', v_default_acl::text, true);
  perform set_config('deedlight.migration038.public_execute', v_public_execute::text, true);
  perform set_config('deedlight.migration038.canonical_noop', v_is_canonical::text, true);
end;
$migration_038_admin_compatibility_preflight$;

-- Canonical Migration 038 re-execution is an explicit verified no-op.
-- The function is replaced only for the exact reviewed Sprint 6 fingerprint.
do $migration_038_admin_compatibility_apply$
begin
  if not current_setting('deedlight.migration038.canonical_noop')::boolean then
    execute
      'create or replace function public.is_admin()' || E'\n' ||
      'returns boolean' || E'\n' ||
      'language sql' || E'\n' ||
      'security definer' || E'\n' ||
      'set search_path = public' || E'\n' ||
      'as $fn$' || E'\n' ||
      '  select exists (' || E'\n' ||
      '    select 1' || E'\n' ||
      '    from public.profiles' || E'\n' ||
      '    where user_id = auth.uid()' || E'\n' ||
      '      and role = ''admin''' || E'\n' ||
      '      and is_suspended = false' || E'\n' ||
      '  );' || E'\n' ||
      '$fn$';
  end if;
end;
$migration_038_admin_compatibility_apply$;

do $migration_038_admin_compatibility_postflight$
declare
  v_source text;
  v_source_hash text;
  v_security_definer boolean;
  v_config text[];
  v_crypto_schema text;
  v_owner_oid oid;
  v_owner_name name;
  v_acl jsonb;
  v_default_acl jsonb;
  v_public_execute boolean;
  v_function_oid oid := 'public.is_admin()'::regprocedure;
begin
  select n.nspname into v_crypto_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  select p.prosrc, p.prosecdef, p.proconfig, p.proowner, owner_role.rolname
    into v_source, v_security_definer, v_config, v_owner_oid, v_owner_name
  from pg_catalog.pg_proc p
  left join pg_catalog.pg_roles owner_role on owner_role.oid = p.proowner
  where p.oid = v_function_oid;

  execute format(
    'select encode(%I.digest(convert_to($1, ''UTF8''), ''hex''), ''hex'')',
    v_crypto_schema
  ) into v_source_hash using v_source;

  if v_source_hash is distinct from '85e6838cf8feec05bcfe9e9051e5192bc8f0d42f7a53cb6c0450067d70bba74b'
    or v_security_definer is distinct from true
    or v_config is distinct from array['search_path=public']::text[] then
    raise exception 'Migration 038 compatibility failed to establish the exact reviewed is_admin() source and execution context.' using errcode = '55000';
  end if;

  if v_owner_oid::text is distinct from current_setting('deedlight.migration038.owner_oid')
    or v_owner_name::text is distinct from current_setting('deedlight.migration038.owner_name') then
    raise exception 'Migration 038 compatibility failed to preserve the exact is_admin() owner identity.' using errcode = '55000';
  end if;

  select COALESCE(jsonb_agg(jsonb_build_object(
    'grantee', acl.grantee,
    'grantor', acl.grantor,
    'privilege', acl.privilege_type,
    'grantable', acl.is_grantable
  ) order by acl.grantee, acl.grantor, acl.privilege_type, acl.is_grantable), '[]'::jsonb)
    into v_acl
  from pg_catalog.aclexplode((
    select COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
    from pg_catalog.pg_proc p where p.oid = v_function_oid
  )) acl;

  select COALESCE(jsonb_agg(jsonb_build_object(
    'schema', d.defaclnamespace,
    'acl', d.defaclacl::text
  ) order by d.defaclnamespace), '[]'::jsonb)
    into v_default_acl
  from pg_catalog.pg_default_acl d
  where d.defaclrole = v_owner_oid
    and d.defaclobjtype = 'f'
    and (d.defaclnamespace = 0 or d.defaclnamespace = 'public'::regnamespace);

  select exists (
    select 1 from pg_catalog.aclexplode((
      select COALESCE(p.proacl, pg_catalog.acldefault('f', p.proowner))
      from pg_catalog.pg_proc p where p.oid = v_function_oid
    )) acl
    where acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  ) into v_public_execute;

  if v_acl::text is distinct from current_setting('deedlight.migration038.acl_snapshot')
    or v_default_acl::text is distinct from current_setting('deedlight.migration038.default_acl_snapshot')
    or v_public_execute::text is distinct from current_setting('deedlight.migration038.public_execute') then
    raise exception 'Migration 038 compatibility failed to preserve the exact function ACL/default ACL contract.' using errcode = '55000';
  end if;

  if not has_function_privilege('anon', v_function_oid, 'EXECUTE')
    or not has_function_privilege('authenticated', v_function_oid, 'EXECUTE') then
    raise exception 'Migration 038 compatibility failed to preserve historical anon/authenticated EXECUTE behavior.' using errcode = '55000';
  end if;

  if not v_public_execute and exists (
    select 1
    from pg_catalog.pg_roles r
    where r.oid not in (v_owner_oid, 'anon'::regrole::oid, 'authenticated'::regrole::oid)
      and pg_catalog.has_function_privilege(r.oid, v_function_oid, 'EXECUTE')
  ) then
    raise exception 'Migration 038 compatibility postflight detected unexpected inherited/effective function EXECUTE privilege.' using errcode = '55000';
  end if;
end;
$migration_038_admin_compatibility_postflight$;

commit;
