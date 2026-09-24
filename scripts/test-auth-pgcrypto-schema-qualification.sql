\set ON_ERROR_STOP on

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

revoke all on schema extensions from public;

DO $$ BEGIN
  create role supabase_auth_admin nologin;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

create schema if not exists auth;

alter role supabase_auth_admin set search_path = auth;
revoke all on schema extensions from supabase_auth_admin;

grant usage on schema auth to supabase_auth_admin;

create table auth.users (
  id uuid primary key,
  email text,
  raw_user_meta_data jsonb not null default '{}'::jsonb
);

grant insert on auth.users to supabase_auth_admin;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  display_name text not null
);

-- Reproduce the current Production trigger relationship.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.profiles (user_id, username, display_name)
  values (
    new.id,
    'member-' || encode(gen_random_bytes(8), 'hex'),
    coalesce(nullif(new.raw_user_meta_data->>'display_name', ''), 'Deedlight member')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- The pre-hotfix function must fail even for its postgres SECURITY DEFINER owner
-- because the function's explicit search_path excludes the extensions schema.
-- This proves the regression test would catch the Production failure.
do $$
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data)
    values ('10000000-0000-0000-0000-000000000001', 'preflight@example.test', '{}'::jsonb);
    raise exception 'Expected the unqualified pgcrypto call to fail.';
  exception
    when undefined_function then
      null;
  end;
end
$$;

\ir ../supabase/migrations/202609240022_auth_pgcrypto_schema_qualification.sql

-- Auth's platform role remains narrow: the fix must not depend on widening its
-- search_path or granting the Auth service access to the extension schema.
do $$
begin
  if exists (
    select 1
    from pg_roles
    where rolname = 'supabase_auth_admin'
      and coalesce(array_to_string(rolconfig, ','), '') not like '%search_path=auth%'
  ) then
    raise exception 'Auth role search_path was unexpectedly changed.';
  end if;

  if has_schema_privilege('supabase_auth_admin', 'extensions', 'USAGE') then
    raise exception 'Regression test must not grant Auth role USAGE on extensions.';
  end if;

  if position(
    'extensions.gen_random_bytes(8)' in
    pg_get_functiondef('public.handle_new_user()'::regprocedure)
  ) = 0 then
    raise exception 'handle_new_user does not schema-qualify gen_random_bytes.';
  end if;
end
$$;

set role supabase_auth_admin;
insert into auth.users (id, email, raw_user_meta_data)
values (
  '10000000-0000-0000-0000-000000000002',
  'canary@example.test',
  '{"display_name":"Canary"}'::jsonb
);
reset role;

do $$
declare
  v_username text;
  v_display_name text;
begin
  select username, display_name
  into v_username, v_display_name
  from public.profiles
  where user_id = '10000000-0000-0000-0000-000000000002';

  if v_username is null or v_username !~ '^member-[a-f0-9]{16}$' then
    raise exception 'Auth-trigger profile username was not generated correctly: %', v_username;
  end if;

  if v_display_name <> 'Canary' then
    raise exception 'Auth-trigger profile display name changed unexpectedly: %', v_display_name;
  end if;
end
$$;

select 'Auth pgcrypto schema-qualification behavior PASS' as result;
