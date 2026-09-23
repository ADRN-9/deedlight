-- Sprint 12.1 owner-removal moderation guard hotfix.
-- Records the narrow Production repair applied after migration 017.
-- Rejected Offerings cannot use Remove -> Restore to bypass moderation.
-- An owner-removed Offering must remain hidden while owner_removed_at is set.

begin;

do $$
declare
  v_removed_count integer;
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'offerings'
      and column_name = 'owner_removed_at'
  ) then
    raise exception
      'Sprint 12.1 owner_removed_at column is missing.';
  end if;

  if to_regprocedure(
    'public.remove_own_offering(uuid)'
  ) is null then
    raise exception
      'Sprint 12.1 remove_own_offering(uuid) is missing.';
  end if;

  select count(*)
  into v_removed_count
  from public.offerings
  where owner_removed_at is not null;

  if v_removed_count <> 0 then
    raise exception
      'Hotfix aborted: expected 0 currently owner-removed Offerings; found %.',
      v_removed_count;
  end if;
end
$$;

alter table public.offerings
  drop constraint if exists offerings_owner_removed_hidden;

alter table public.offerings
  add constraint offerings_owner_removed_hidden
  check (
    owner_removed_at is null
    or status = 'hidden'
  );

create or replace function public.remove_own_offering(
  p_offering_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_offering public.offerings%rowtype;
begin
  if v_actor is null then
    raise exception
      'Authentication is required.'
      using errcode = '42501';
  end if;

  select o.*
  into v_offering
  from public.offerings o
  where o.id = p_offering_id
    and o.user_id = v_actor
  for update;

  if not found then
    raise exception
      'Offering was not found.'
      using errcode = '42501';
  end if;

  if v_offering.status = 'rejected' then
    raise exception
      'Rejected Offerings cannot be changed from the member controls.'
      using errcode = '42501';
  end if;

  if (
    v_offering.status = 'hidden'
    and v_offering.owner_removed_at is null
  ) then
    raise exception
      'Moderator-hidden Offerings cannot be changed from the member controls.'
      using errcode = '42501';
  end if;

  if v_offering.owner_removed_at is not null then
    return p_offering_id;
  end if;

  update public.offerings
  set
    status = 'hidden',
    owner_removed_at = now(),
    published_at = null
  where id = p_offering_id;

  return p_offering_id;
end;
$$;

revoke all
on function public.remove_own_offering(uuid)
from public, anon, authenticated;

grant execute
on function public.remove_own_offering(uuid)
to authenticated;

notify pgrst, 'reload schema';

commit;
