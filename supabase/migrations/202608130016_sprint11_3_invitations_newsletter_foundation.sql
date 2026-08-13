-- Sprint 11.3 — Invitations & Newsletter Foundation
-- Private invitation attribution and explicit account-linked newsletter consent.
-- No email/newsletter delivery provider is introduced by this migration.
-- No reflections, Daily completions, Saved Lights, or reminder preferences are
-- read or exposed by this feature.

begin;

create extension if not exists pgcrypto;

create table if not exists public.invitation_links (
  id uuid primary key default gen_random_uuid(),
  inviter_user_id uuid not null references auth.users(id) on delete cascade,
  code text not null unique check (code ~ '^[a-f0-9]{36}$'),
  accepted_count integer not null default 0 check (accepted_count >= 0),
  expires_at timestamptz not null default (now() + interval '30 days'),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at > created_at)
);

create index if not exists invitation_links_inviter_created_idx
on public.invitation_links (inviter_user_id, created_at desc);

create index if not exists invitation_links_active_lookup_idx
on public.invitation_links (code, revoked_at, expires_at);

drop trigger if exists invitation_links_set_updated_at
on public.invitation_links;

create trigger invitation_links_set_updated_at
before update on public.invitation_links
for each row execute function public.set_updated_at();

alter table public.invitation_links enable row level security;

drop policy if exists "invitation_links_select_own"
on public.invitation_links;

create policy "invitation_links_select_own"
on public.invitation_links
for select to authenticated
using (inviter_user_id = auth.uid());

revoke all privileges on table public.invitation_links
from public, anon, authenticated;

grant select on table public.invitation_links to authenticated;
grant all privileges on table public.invitation_links to service_role;

create table if not exists public.invitation_acceptances (
  id uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.invitation_links(id) on delete cascade,
  invited_user_id uuid not null unique references auth.users(id) on delete cascade,
  accepted_at timestamptz not null default now()
);

create index if not exists invitation_acceptances_invitation_idx
on public.invitation_acceptances (invitation_id, accepted_at desc);

alter table public.invitation_acceptances enable row level security;

revoke all privileges on table public.invitation_acceptances
from public, anon, authenticated;

grant all privileges on table public.invitation_acceptances to service_role;

create table if not exists public.newsletter_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  weekly_enabled boolean not null default false,
  consented_at timestamptz,
  unsubscribed_at timestamptz,
  consent_source text check (
    consent_source is null or consent_source in ('signup', 'settings')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists newsletter_preferences_set_updated_at
on public.newsletter_preferences;

create trigger newsletter_preferences_set_updated_at
before update on public.newsletter_preferences
for each row execute function public.set_updated_at();

alter table public.newsletter_preferences enable row level security;

drop policy if exists "newsletter_preferences_select_own"
on public.newsletter_preferences;

create policy "newsletter_preferences_select_own"
on public.newsletter_preferences
for select to authenticated
using (user_id = auth.uid());

revoke all privileges on table public.newsletter_preferences
from public, anon, authenticated;

grant select on table public.newsletter_preferences to authenticated;
grant all privileges on table public.newsletter_preferences to service_role;

insert into public.newsletter_preferences (user_id, weekly_enabled)
select u.id, false
from auth.users u
on conflict (user_id) do nothing;

create or replace function public.validate_invitation_code(p_code text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.invitation_links il
    join public.profiles p on p.user_id = il.inviter_user_id
    where il.code = lower(btrim(coalesce(p_code, '')))
      and il.revoked_at is null
      and il.expires_at > now()
      and p.is_suspended = false
  );
$$;

revoke all privileges on function public.validate_invitation_code(text)
from public, anon, authenticated;

grant execute on function public.validate_invitation_code(text)
to anon, authenticated, service_role;

create or replace function public.create_invitation_link()
returns table (
  invitation_id uuid,
  invitation_code text,
  invitation_expires_at timestamptz,
  accepted_count integer
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_link public.invitation_links%rowtype;
  v_code text;
begin
  if v_actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.user_id = v_actor
      and p.is_suspended = false
  ) then
    raise exception 'An active member account is required to create invitation links.'
      using errcode = '42501';
  end if;

  select il.* into v_link
  from public.invitation_links il
  where il.inviter_user_id = v_actor
    and il.revoked_at is null
    and il.expires_at > now()
  order by il.created_at desc
  limit 1;

  if found then
    invitation_id := v_link.id;
    invitation_code := v_link.code;
    invitation_expires_at := v_link.expires_at;
    accepted_count := v_link.accepted_count;
    return next;
    return;
  end if;

  if (
    select count(*)
    from public.invitation_links il
    where il.inviter_user_id = v_actor
      and il.created_at >= now() - interval '24 hours'
  ) >= 5 then
    raise exception 'Please wait before creating another invitation link.'
      using errcode = 'P0001';
  end if;

  v_code := encode(extensions.gen_random_bytes(18), 'hex');

  insert into public.invitation_links (inviter_user_id, code)
  values (v_actor, v_code)
  returning * into v_link;

  invitation_id := v_link.id;
  invitation_code := v_link.code;
  invitation_expires_at := v_link.expires_at;
  accepted_count := v_link.accepted_count;
  return next;
end;
$$;

revoke all privileges on function public.create_invitation_link()
from public, anon, authenticated;

grant execute on function public.create_invitation_link()
to authenticated, service_role;

create or replace function public.revoke_invitation_link(
  p_invitation_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  update public.invitation_links
  set revoked_at = now()
  where id = p_invitation_id
    and inviter_user_id = v_actor
    and revoked_at is null;

  return found;
end;
$$;

revoke all privileges on function public.revoke_invitation_link(uuid)
from public, anon, authenticated;

grant execute on function public.revoke_invitation_link(uuid)
to authenticated, service_role;

create or replace function public.set_newsletter_preference(
  p_enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_enabled boolean := coalesce(p_enabled, false);
begin
  if v_actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  if v_enabled and exists (
    select 1
    from public.profiles p
    where p.user_id = v_actor
      and p.is_suspended = true
  ) then
    raise exception 'Newsletter consent cannot be enabled while community access is suspended.'
      using errcode = '42501';
  end if;

  insert into public.newsletter_preferences (
    user_id, weekly_enabled, consented_at, unsubscribed_at, consent_source
  )
  values (
    v_actor,
    v_enabled,
    case when v_enabled then now() else null end,
    null,
    case when v_enabled then 'settings' else null end
  )
  on conflict (user_id)
  do update set
    weekly_enabled = excluded.weekly_enabled,
    consented_at = case
      when excluded.weekly_enabled
        then coalesce(public.newsletter_preferences.consented_at, now())
      else public.newsletter_preferences.consented_at
    end,
    unsubscribed_at = case
      when excluded.weekly_enabled then null
      when public.newsletter_preferences.weekly_enabled then now()
      else public.newsletter_preferences.unsubscribed_at
    end,
    consent_source = case
      when excluded.weekly_enabled then 'settings'
      else public.newsletter_preferences.consent_source
    end,
    updated_at = now();

  return v_enabled;
end;
$$;

revoke all privileges on function public.set_newsletter_preference(boolean)
from public, anon, authenticated;

grant execute on function public.set_newsletter_preference(boolean)
to authenticated, service_role;

create or replace function public.record_invitation_acceptance(
  p_invited_user_id uuid,
  p_code text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invitation_id uuid;
  v_inserted integer := 0;
begin
  if p_invited_user_id is null
     or p_code is null
     or lower(btrim(p_code)) !~ '^[a-f0-9]{36}$' then
    return false;
  end if;

  select il.id into v_invitation_id
  from public.invitation_links il
  join public.profiles p on p.user_id = il.inviter_user_id
  where il.code = lower(btrim(p_code))
    and il.revoked_at is null
    and il.expires_at > now()
    and il.inviter_user_id <> p_invited_user_id
    and p.is_suspended = false
  limit 1;

  if v_invitation_id is null then
    return false;
  end if;

  insert into public.invitation_acceptances (
    invitation_id, invited_user_id
  )
  values (v_invitation_id, p_invited_user_id)
  on conflict (invited_user_id) do nothing;

  get diagnostics v_inserted = row_count;

  if v_inserted = 1 then
    update public.invitation_links
    set accepted_count = accepted_count + 1
    where id = v_invitation_id;
    return true;
  end if;

  return false;
end;
$$;

revoke all privileges
on function public.record_invitation_acceptance(uuid, text)
from public, anon, authenticated;

create or replace function public.handle_growth_signup()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_newsletter_opt_in boolean := false;
  v_invite_code text;
begin
  if tg_op = 'INSERT' then
    v_newsletter_opt_in :=
      lower(coalesce(
        new.raw_user_meta_data->>'newsletter_weekly_opt_in', ''
      )) in ('true', '1', 'yes', 'on');

    insert into public.newsletter_preferences (
      user_id, weekly_enabled, consented_at, consent_source
    )
    values (
      new.id,
      v_newsletter_opt_in,
      case when v_newsletter_opt_in then now() else null end,
      case when v_newsletter_opt_in then 'signup' else null end
    )
    on conflict (user_id)
    do update set
      weekly_enabled = excluded.weekly_enabled,
      consented_at = case
        when excluded.weekly_enabled then coalesce(
          public.newsletter_preferences.consented_at,
          excluded.consented_at
        )
        else public.newsletter_preferences.consented_at
      end,
      consent_source = case
        when excluded.weekly_enabled then 'signup'
        else public.newsletter_preferences.consent_source
      end,
      updated_at = now();

    if new.email_confirmed_at is not null then
      v_invite_code := lower(btrim(coalesce(
        new.raw_user_meta_data->>'deedlight_invite_code', ''
      )));
      perform public.record_invitation_acceptance(
        new.id, nullif(v_invite_code, '')
      );
    end if;

    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.email_confirmed_at is null
     and new.email_confirmed_at is not null then
    v_invite_code := lower(btrim(coalesce(
      new.raw_user_meta_data->>'deedlight_invite_code', ''
    )));
    perform public.record_invitation_acceptance(
      new.id, nullif(v_invite_code, '')
    );
  end if;

  return new;
end;
$$;

revoke all privileges on function public.handle_growth_signup()
from public, anon, authenticated;

drop trigger if exists on_auth_user_growth_insert on auth.users;
create trigger on_auth_user_growth_insert
after insert on auth.users
for each row execute function public.handle_growth_signup();

drop trigger if exists on_auth_user_growth_email_confirmed on auth.users;
create trigger on_auth_user_growth_email_confirmed
after update of email_confirmed_at on auth.users
for each row execute function public.handle_growth_signup();

notify pgrst, 'reload schema';

commit;
