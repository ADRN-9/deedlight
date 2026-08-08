-- Sprint 9.1 — Profiles + Community Trust
-- Migration-first privacy foundation.

begin;

alter table public.profiles
  add column if not exists is_public boolean not null default false,
  add column if not exists show_contribution_stats boolean not null default true,
  add column if not exists default_offering_anonymous boolean not null default false;

-- Existing members receive non-identifying placeholders and may choose a
-- human-readable username later in profile settings.
update public.profiles
set username = 'member-' || encode(gen_random_bytes(8), 'hex')
where username is null or btrim(username) = '';

update public.profiles
set username = lower(btrim(username))
where username is not null;

alter table public.profiles
  drop constraint if exists profiles_username_key;

drop index if exists public.profiles_username_key;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_username_format_check'
  ) then
    alter table public.profiles
      add constraint profiles_username_format_check
      check (username ~ '^[a-z0-9][a-z0-9_-]{2,29}$');
  end if;
end
$$;

alter table public.profiles
  alter column username set not null;

create unique index if not exists profiles_username_lower_key
  on public.profiles (lower(username));

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
    'member-' || encode(gen_random_bytes(8), 'hex'),
    coalesce(
      nullif(new.raw_user_meta_data->>'display_name', ''),
      split_part(new.email, '@', 1),
      'Deedlight member'
    )
  )
  on conflict (user_id) do nothing;

  return new;
end;
$$;

-- Direct profile-table access is private. Public pages use profiles_public.
drop policy if exists "profiles_public_read" on public.profiles;
drop policy if exists "profiles_select_public" on public.profiles;
drop policy if exists "profiles_own_read" on public.profiles;
drop policy if exists "profiles_own_update" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;

create policy "profiles_own_read"
on public.profiles
for select
to authenticated
using (user_id = auth.uid());

create policy "profiles_own_update"
on public.profiles
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

revoke all privileges on table public.profiles from anon;
revoke all privileges on table public.profiles from authenticated;

grant select on table public.profiles to authenticated;

grant update (
  username,
  display_name,
  bio,
  country,
  is_public,
  show_contribution_stats,
  default_offering_anonymous
) on table public.profiles to authenticated;

drop view if exists public.profiles_public;

create view public.profiles_public
with (security_barrier = true)
as
select
  p.username,
  p.display_name,
  p.bio,
  p.country,
  p.is_verified,
  p.created_at as member_since,
  p.show_contribution_stats,
  case
    when p.show_contribution_stats
      then coalesce(stats.published_offering_count, 0)
    else null
  end as published_offering_count,
  case
    when p.show_contribution_stats
      then coalesce(stats.total_bless_count, 0)
    else null
  end as total_bless_count,
  case
    when p.show_contribution_stats
      then coalesce(stats.total_inspired_count, 0)
    else null
  end as total_inspired_count,
  case
    when p.show_contribution_stats
      then coalesce(stats.total_carried_forward_count, 0)
    else null
  end as total_carried_forward_count
from public.profiles p
left join lateral (
  select
    count(*)::integer as published_offering_count,
    coalesce(sum(o.bless_count), 0)::integer
      as total_bless_count,
    coalesce(sum(o.inspired_count), 0)::integer
      as total_inspired_count,
    coalesce(sum(o.carried_forward_count), 0)::integer
      as total_carried_forward_count
  from public.offerings o
  where o.user_id = p.user_id
    and o.status = 'approved'
    and o.is_anonymous = false
) stats on true
where p.is_public = true
  and p.is_suspended = false;

revoke all privileges
on table public.profiles_public
from public, anon, authenticated;

grant select
on table public.profiles_public
to anon, authenticated, service_role;

-- Anonymous Offerings expose no account UUID or public identity.
create or replace view public.offerings_public
with (security_barrier = true)
as
select
  o.id,
  case
    when o.is_anonymous then null::uuid
    else o.user_id
  end as user_id,
  o.title,
  o.body,
  o.takeaway,
  o.offering_type,
  o.media_url,
  o.media_type,
  o.is_anonymous,
  o.allow_reflections,
  o.location_label,
  o.bless_count,
  o.inspired_count,
  o.carried_forward_count,
  o.reflection_count,
  o.bless_score,
  o.published_at,
  t.name as theme_name,
  case
    when o.is_anonymous
      or coalesce(p.is_suspended, false)
    then null::text
    else p.display_name
  end as author_name,
  case
    when o.is_anonymous
      or coalesce(p.is_suspended, false)
      or coalesce(p.is_public, false) = false
    then null::text
    else p.username
  end as author_username
from public.offerings o
left join public.themes t on t.id = o.theme_id
left join public.profiles p on p.user_id = o.user_id
where o.status = 'approved';

-- Public callers use offerings_public. The base table is available only to
-- authenticated callers and remains constrained by RLS for own/admin data.
drop policy if exists "offerings_public_approved_read"
on public.offerings;

revoke all privileges
on table public.offerings
from anon;

revoke all privileges
on table public.offerings
from authenticated;

grant select, insert, update
on table public.offerings
to authenticated;

revoke all privileges
on table public.offerings_public
from public, anon, authenticated;

grant select
on table public.offerings_public
to anon, authenticated, service_role;

commit;
