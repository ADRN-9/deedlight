-- Production Auth hotfix — schema-qualify pgcrypto in the auth.users profile trigger.
--
-- Supabase keeps pgcrypto in the `extensions` schema while the auth service
-- executes with a deliberately narrow search_path. The Deedlight trigger
-- function introduced in Sprint 9 called gen_random_bytes() without a schema,
-- causing new Auth-user creation to fail before confirmation email delivery.
--
-- Keep the existing profile/bootstrap behavior and SECURITY DEFINER boundary;
-- only make the extension dependency explicit.

begin;

do $$
begin
  if to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception 'Required extensions.gen_random_bytes(integer) is missing.';
  end if;
end
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.profiles (
    user_id,
    username,
    display_name
  )
  values (
    new.id,
    'member-' || encode(extensions.gen_random_bytes(8), 'hex'),
    coalesce(
      nullif(new.raw_user_meta_data->>'display_name', ''),
      'Deedlight member'
    )
  )
  on conflict (user_id) do nothing;

  return new;
end;
$$;

commit;
