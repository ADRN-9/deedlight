create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  username text unique,
  display_name text not null,
  avatar_url text,
  bio text,
  country text,
  role text not null default 'member' check (role in ('member','trusted_member','moderator','admin')),
  is_verified boolean not null default false,
  is_suspended boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create table if not exists public.themes (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  icon_name text,
  accent_color text,
  created_at timestamptz not null default now()
);

create table if not exists public.daily_posts (
  id uuid primary key default gen_random_uuid(),
  date date not null unique,
  slug text not null unique,
  title text not null,
  theme_id uuid references public.themes(id),
  reflection text not null,
  daily_action text not null,
  reflection_question text,
  image_url text,
  youtube_url text,
  status text not null default 'draft' check (status in ('draft','scheduled','published','archived')),
  created_by uuid references auth.users(id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger daily_posts_set_updated_at
before update on public.daily_posts
for each row execute function public.set_updated_at();

create table if not exists public.offerings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  theme_id uuid references public.themes(id),
  offering_type text not null check (offering_type in ('good_deed','goodness_invitation','gratitude','beauty_reminder','quiet_goodness','community_need')),
  title text not null check (char_length(title) between 4 and 120),
  body text not null check (char_length(body) between 20 and 5000),
  takeaway text,
  media_url text,
  media_type text check (media_type is null or media_type in ('image','video')),
  is_anonymous boolean not null default false,
  allow_reflections boolean not null default true,
  location_label text,
  status text not null default 'pending' check (status in ('draft','pending','approved','rejected','needs_edit','hidden')),
  moderation_note text,
  bless_count integer not null default 0 check (bless_count >= 0),
  inspired_count integer not null default 0 check (inspired_count >= 0),
  carried_forward_count integer not null default 0 check (carried_forward_count >= 0),
  reflection_count integer not null default 0 check (reflection_count >= 0),
  open_report_count integer not null default 0 check (open_report_count >= 0),
  bless_score numeric generated always as (
    bless_count * 1 + inspired_count * 3 + carried_forward_count * 5 + reflection_count * 2 - open_report_count * 10
  ) stored,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists offerings_status_published_idx on public.offerings(status, published_at desc);
create index if not exists offerings_bless_score_idx on public.offerings(bless_score desc);
create index if not exists offerings_user_id_idx on public.offerings(user_id);

create trigger offerings_set_updated_at
before update on public.offerings
for each row execute function public.set_updated_at();

create table if not exists public.reactions (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid not null references public.offerings(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction_type text not null check (reaction_type in ('bless','inspired_me','i_did_this_too')),
  created_at timestamptz not null default now(),
  unique (offering_id, user_id, reaction_type)
);

create index if not exists reactions_offering_id_idx on public.reactions(offering_id);
create index if not exists reactions_user_id_idx on public.reactions(user_id);

create table if not exists public.reflections (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid not null references public.offerings(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 2 and 2000),
  status text not null default 'visible' check (status in ('visible','hidden','removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger reflections_set_updated_at
before update on public.reflections
for each row execute function public.set_updated_at();

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid references public.offerings(id) on delete cascade,
  reflection_id uuid references public.reflections(id) on delete cascade,
  reported_by uuid references auth.users(id) on delete set null,
  reason text not null check (reason in ('exposes_vulnerable_person','hate_or_prejudice','fake_charity_or_fraud','harassment','graphic_or_disturbing','self_promotion','privacy_concern','other')),
  details text,
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  admin_note text,
  resolved_by uuid references auth.users(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  check (offering_id is not null or reflection_id is not null)
);

create table if not exists public.badges (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text not null,
  icon_name text,
  level_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.user_badges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade,
  awarded_at timestamptz not null default now(),
  unique (user_id, badge_id)
);

create table if not exists public.saved_lights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  offering_id uuid references public.offerings(id) on delete cascade,
  daily_post_id uuid references public.daily_posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  check ((offering_id is not null) <> (daily_post_id is not null))
);

create unique index if not exists saved_lights_unique_offering
on public.saved_lights(user_id, offering_id)
where offering_id is not null;

create unique index if not exists saved_lights_unique_daily_post
on public.saved_lights(user_id, daily_post_id)
where daily_post_id is not null;

create table if not exists public.daily_deed_completions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  daily_post_id uuid not null references public.daily_posts(id) on delete cascade,
  status text not null default 'completed' check (status in ('try','completed')),
  created_at timestamptz not null default now(),
  unique (user_id, daily_post_id, status)
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'display_name', ''), split_part(new.email, '@', 1), 'Deedlight member')
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.handle_reaction_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.offerings set
      bless_count = bless_count + case when new.reaction_type = 'bless' then 1 else 0 end,
      inspired_count = inspired_count + case when new.reaction_type = 'inspired_me' then 1 else 0 end,
      carried_forward_count = carried_forward_count + case when new.reaction_type = 'i_did_this_too' then 1 else 0 end
    where id = new.offering_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.offerings set
      bless_count = greatest(0, bless_count - case when old.reaction_type = 'bless' then 1 else 0 end),
      inspired_count = greatest(0, inspired_count - case when old.reaction_type = 'inspired_me' then 1 else 0 end),
      carried_forward_count = greatest(0, carried_forward_count - case when old.reaction_type = 'i_did_this_too' then 1 else 0 end)
    where id = old.offering_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists reactions_count_insert on public.reactions;
create trigger reactions_count_insert
after insert on public.reactions
for each row execute function public.handle_reaction_counts();

drop trigger if exists reactions_count_delete on public.reactions;
create trigger reactions_count_delete
after delete on public.reactions
for each row execute function public.handle_reaction_counts();



create or replace function public.handle_reflection_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'visible' then
      update public.offerings set reflection_count = reflection_count + 1 where id = new.offering_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.status = 'visible' then
      update public.offerings set reflection_count = greatest(0, reflection_count - 1) where id = old.offering_id;
    end if;
    return old;
  elsif tg_op = 'UPDATE' then
    if old.status <> 'visible' and new.status = 'visible' then
      update public.offerings set reflection_count = reflection_count + 1 where id = new.offering_id;
    elsif old.status = 'visible' and new.status <> 'visible' then
      update public.offerings set reflection_count = greatest(0, reflection_count - 1) where id = old.offering_id;
    end if;
    return new;
  end if;
  return null;
end;
$$;

drop trigger if exists reflections_count_insert on public.reflections;
create trigger reflections_count_insert
after insert on public.reflections
for each row execute function public.handle_reflection_counts();

drop trigger if exists reflections_count_update on public.reflections;
create trigger reflections_count_update
after update of status on public.reflections
for each row execute function public.handle_reflection_counts();

drop trigger if exists reflections_count_delete on public.reflections;
create trigger reflections_count_delete
after delete on public.reflections
for each row execute function public.handle_reflection_counts();

create or replace function public.handle_report_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.offering_id is not null and new.status = 'open' then
      update public.offerings set open_report_count = open_report_count + 1 where id = new.offering_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.offering_id is not null and old.status = 'open' then
      update public.offerings set open_report_count = greatest(0, open_report_count - 1) where id = old.offering_id;
    end if;
    return old;
  elsif tg_op = 'UPDATE' then
    if new.offering_id is not null then
      if old.status <> 'open' and new.status = 'open' then
        update public.offerings set open_report_count = open_report_count + 1 where id = new.offering_id;
      elsif old.status = 'open' and new.status <> 'open' then
        update public.offerings set open_report_count = greatest(0, open_report_count - 1) where id = new.offering_id;
      end if;
    end if;
    return new;
  end if;
  return null;
end;
$$;

drop trigger if exists reports_count_insert on public.reports;
create trigger reports_count_insert
after insert on public.reports
for each row execute function public.handle_report_counts();

drop trigger if exists reports_count_update on public.reports;
create trigger reports_count_update
after update of status on public.reports
for each row execute function public.handle_report_counts();

drop trigger if exists reports_count_delete on public.reports;
create trigger reports_count_delete
after delete on public.reports
for each row execute function public.handle_report_counts();

create or replace view public.offerings_public as
select
  o.id,
  o.user_id,
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
  case when o.is_anonymous then null else p.display_name end as author_name
from public.offerings o
left join public.themes t on t.id = o.theme_id
left join public.profiles p on p.user_id = o.user_id
where o.status = 'approved';
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

alter table public.profiles enable row level security;
alter table public.themes enable row level security;
alter table public.daily_posts enable row level security;
alter table public.offerings enable row level security;
alter table public.reactions enable row level security;
alter table public.reflections enable row level security;
alter table public.reports enable row level security;
alter table public.badges enable row level security;
alter table public.user_badges enable row level security;
alter table public.saved_lights enable row level security;
alter table public.daily_deed_completions enable row level security;

create policy "profiles_public_read" on public.profiles
for select using (is_suspended = false);

create policy "profiles_own_update" on public.profiles
for update using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "profiles_admin_all" on public.profiles
for all using (public.is_admin())
with check (public.is_admin());

create policy "themes_public_read" on public.themes
for select using (true);

create policy "themes_admin_all" on public.themes
for all using (public.is_admin())
with check (public.is_admin());

create policy "daily_posts_public_published_read" on public.daily_posts
for select using (status = 'published');

create policy "daily_posts_admin_all" on public.daily_posts
for all using (public.is_admin())
with check (public.is_admin());

create policy "offerings_public_approved_read" on public.offerings
for select using (status = 'approved');

create policy "offerings_own_read" on public.offerings
for select using (user_id = auth.uid());

create policy "offerings_user_insert_pending" on public.offerings
for insert with check (
  user_id = auth.uid()
  and status in ('draft','pending')
  and not exists (
    select 1 from public.profiles p
    where p.user_id = auth.uid() and p.is_suspended = true
  )
);

create policy "offerings_user_update_safe_statuses" on public.offerings
for update using (
  user_id = auth.uid()
  and status in ('draft','needs_edit')
) with check (
  user_id = auth.uid()
  and status in ('draft','pending')
);

create policy "offerings_admin_all" on public.offerings
for all using (public.is_admin())
with check (public.is_admin());

create policy "reactions_own_insert" on public.reactions
for insert with check (user_id = auth.uid());

create policy "reactions_own_delete" on public.reactions
for delete using (user_id = auth.uid());

create policy "reactions_own_read" on public.reactions
for select using (user_id = auth.uid() or public.is_admin());

create policy "reactions_admin_all" on public.reactions
for all using (public.is_admin())
with check (public.is_admin());

create policy "reflections_public_visible_read" on public.reflections
for select using (
  status = 'visible'
  and exists (select 1 from public.offerings o where o.id = offering_id and o.status = 'approved')
);

create policy "reflections_own_insert" on public.reflections
for insert with check (
  user_id = auth.uid()
  and exists (select 1 from public.offerings o where o.id = offering_id and o.status = 'approved' and o.allow_reflections = true)
);

create policy "reflections_own_update" on public.reflections
for update using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "reflections_admin_all" on public.reflections
for all using (public.is_admin())
with check (public.is_admin());

create policy "reports_own_insert" on public.reports
for insert with check (reported_by = auth.uid());

create policy "reports_admin_all" on public.reports
for all using (public.is_admin())
with check (public.is_admin());

create policy "badges_public_read" on public.badges
for select using (true);

create policy "badges_admin_all" on public.badges
for all using (public.is_admin())
with check (public.is_admin());

create policy "user_badges_public_read" on public.user_badges
for select using (true);

create policy "user_badges_admin_all" on public.user_badges
for all using (public.is_admin())
with check (public.is_admin());

create policy "saved_lights_own_all" on public.saved_lights
for all using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "daily_deed_completions_own_all" on public.daily_deed_completions
for all using (user_id = auth.uid())
with check (user_id = auth.uid());

-- Storage buckets. Safe to re-run.
insert into storage.buckets (id, name, public)
values
  ('daily-lights', 'daily-lights', true),
  ('offerings-media', 'offerings-media', true),
  ('profile-avatars', 'profile-avatars', true),
  ('admin-assets', 'admin-assets', false),
  ('share-cards', 'share-cards', true)
on conflict (id) do nothing;

create policy "storage_public_read_public_buckets" on storage.objects
for select using (bucket_id in ('daily-lights','offerings-media','profile-avatars','share-cards'));

create policy "storage_user_upload_offering_media" on storage.objects
for insert with check (
  bucket_id = 'offerings-media'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "storage_user_update_own_offering_media" on storage.objects
for update using (
  bucket_id = 'offerings-media'
  and auth.uid()::text = (storage.foldername(name))[1]
) with check (
  bucket_id = 'offerings-media'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "storage_user_upload_own_avatar" on storage.objects
for insert with check (
  bucket_id = 'profile-avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "storage_admin_all" on storage.objects
for all using (public.is_admin())
with check (public.is_admin());
insert into public.themes (slug, name, description, icon_name, accent_color)
values
  ('kindness', 'Kindness', 'Small acts that make life softer.', 'hand-heart', '#C9826B'),
  ('courage', 'Courage', 'Protecting dignity and truth with gentleness.', 'shield-flame', '#D9A441'),
  ('mercy', 'Mercy', 'Choosing compassion over cruelty.', 'open-palm', '#DCE9F5'),
  ('honesty', 'Honesty', 'Clear, truthful, trustworthy goodness.', 'gem-light', '#DCE9F5'),
  ('patience', 'Patience', 'Goodness that waits without bitterness.', 'hourglass-leaf', '#A8BFA3'),
  ('gratitude', 'Gratitude', 'Remembering goodness received.', 'hands-heart', '#C9826B'),
  ('beauty', 'Beauty', 'Moments that restore hope.', 'flower-sun', '#F4C76B'),
  ('justice', 'Justice', 'Fairness carried with dignity.', 'balanced-light', '#D9A441'),
  ('humility', 'Humility', 'Goodness without showing off.', 'small-candle', '#FFF8EA'),
  ('community', 'Community', 'Many small lights together.', 'circle-lights', '#A8BFA3')
on conflict (slug) do update set
  name = excluded.name,
  description = excluded.description,
  icon_name = excluded.icon_name,
  accent_color = excluded.accent_color;

insert into public.daily_posts (
  date,
  slug,
  title,
  theme_id,
  reflection,
  daily_action,
  reflection_question,
  status,
  published_at
)
values (
  current_date,
  'protect-someones-dignity',
  'Protect someone’s dignity',
  (select id from public.themes where slug = 'courage'),
  'Beauty is not only found in nature. Sometimes beauty appears when one person refuses to join cruelty.',
  'Say one gentle sentence in defense of someone who is being judged unfairly.',
  'Did I make one place safer for goodness today?',
  'published',
  now()
)
on conflict (date) do update set
  title = excluded.title,
  theme_id = excluded.theme_id,
  reflection = excluded.reflection,
  daily_action = excluded.daily_action,
  reflection_question = excluded.reflection_question,
  status = excluded.status,
  published_at = excluded.published_at;

insert into public.badges (slug, name, description, icon_name, level_name)
values
  ('quiet-helper-spark', 'Quiet Helper', 'Shared humble or anonymous goodness.', 'moon-hand', 'Spark'),
  ('kindness-carrier-spark', 'Kindness Carrier', 'Carried repeated acts of kindness.', 'hand-heart', 'Spark'),
  ('beauty-reminder-spark', 'Beauty Reminder', 'Shared beauty that restored hope.', 'flower-sun', 'Spark')
on conflict (slug) do update set
  name = excluded.name,
  description = excluded.description,
  icon_name = excluded.icon_name,
  level_name = excluded.level_name;


-- =====================================================================
-- BEGIN SPRINT 9.1 + 9.2 CANONICAL PARITY
-- This aggregate file predates the profile privacy work above.
-- The canonical migration bodies are appended verbatim so running this
-- bootstrap script reaches the same final privacy/identity state.
-- =====================================================================

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

-- Sprint 9.2 — Community Identity Consistency
-- Keeps public identity projections privacy-minimized and repairs Rising Goodness
-- after Sprint 9.1 added author_username to offerings_public.

begin;

-- New accounts should never derive a potentially public display name from email.
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
      'Deedlight member'
    )
  )
  on conflict (user_id) do nothing;

  return new;
end;
$$;

-- Public Offering projections do not need internal auth/profile UUIDs.
-- Human-facing attribution is carried only through author_name/author_username.
create or replace view public.offerings_public
with (security_barrier = true)
as
select
  o.id,
  null::uuid as user_id,
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

revoke all privileges
on table public.offerings_public
from public, anon, authenticated;

grant select
on table public.offerings_public
to anon, authenticated, service_role;

-- Preserve the existing Rising view column contract and append author_username
-- at the end, which CREATE OR REPLACE VIEW permits without breaking dependents.
create or replace view public.offerings_rising
with (security_barrier = true)
as
select
  op.id,
  op.user_id,
  op.title,
  op.body,
  op.takeaway,
  op.offering_type,
  op.media_url,
  op.media_type,
  op.is_anonymous,
  op.allow_reflections,
  op.location_label,
  op.bless_count,
  op.inspired_count,
  op.carried_forward_count,
  op.reflection_count,
  op.bless_score,
  op.published_at,
  op.theme_name,
  op.author_name,
  (
    coalesce(op.bless_score, 0)
    + case
        when op.published_at is null then 0
        when op.published_at > now() - interval '24 hours' then 30
        when op.published_at > now() - interval '7 days' then 12
        else 0
      end
  )::numeric as rising_score,
  op.author_username
from public.offerings_public op;

revoke all privileges
on table public.offerings_rising
from public, anon, authenticated;

grant select
on table public.offerings_rising
to anon, authenticated, service_role;

-- Revoke direct anonymous base-table access defensively.
revoke select
on table public.offerings
from anon;

-- Refresh the Supabase/PostgREST schema cache after changing public views.
notify pgrst, 'reload schema';

commit;

-- =====================================================================
-- END SPRINT 9.1 + 9.2 CANONICAL PARITY
-- =====================================================================


-- =====================================================================
-- BEGIN SPRINT 9.3 MODERATION-AWARE MEMBERS PARITY
-- Canonical Sprint 9.3 migration appended so the aggregate SQL reaches
-- the same final moderation and suspension-policy state.
-- =====================================================================

-- Sprint 9.3 — Moderation-aware Members
-- Adds auditable member suspension/restore controls and closes community-write
-- suspension gaps without exposing or changing private Daily reflections.

begin;

-- ---------------------------------------------------------------------
-- 1. Append-only moderation history.
-- ---------------------------------------------------------------------

create table if not exists public.member_moderation_events (
  id uuid primary key default gen_random_uuid(),
  member_user_id uuid not null references auth.users(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null check (action in ('suspended', 'restored')),
  reason text not null check (char_length(reason) between 8 and 500),
  created_at timestamptz not null default now()
);

create index if not exists member_moderation_events_member_created_idx
  on public.member_moderation_events(member_user_id, created_at desc);

create index if not exists member_moderation_events_actor_created_idx
  on public.member_moderation_events(actor_user_id, created_at desc);

alter table public.member_moderation_events enable row level security;

drop policy if exists "member_moderation_events_admin_select"
on public.member_moderation_events;

create policy "member_moderation_events_admin_select"
on public.member_moderation_events
for select
to authenticated
using (public.is_admin());

revoke all privileges
on table public.member_moderation_events
from public, anon, authenticated;

grant all
on table public.member_moderation_events
to service_role;

-- ---------------------------------------------------------------------
-- 2. Database-admin-only member read APIs.
--    These projections intentionally contain no email addresses,
--    reflection text, Daily reflections, or auth/profile row IDs.
-- ---------------------------------------------------------------------

create or replace function public.admin_list_members(
  p_state text default 'all'
)
returns table (
  member_user_id uuid,
  username text,
  display_name text,
  role text,
  is_verified boolean,
  is_suspended boolean,
  is_public boolean,
  member_since timestamptz,
  offering_count bigint,
  approved_offering_count bigint,
  pending_offering_count bigint,
  open_report_count bigint,
  last_action text,
  last_reason text,
  last_moderated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Database-backed admin access is required.'
      using errcode = '42501';
  end if;

  if p_state not in ('all', 'active', 'suspended') then
    raise exception 'Invalid member state filter.'
      using errcode = '22023';
  end if;

  return query
  select
    p.user_id,
    p.username,
    p.display_name,
    p.role,
    p.is_verified,
    p.is_suspended,
    p.is_public,
    p.created_at,
    (
      select count(*)::bigint
      from public.offerings o
      where o.user_id = p.user_id
    ) as offering_count,
    (
      select count(*)::bigint
      from public.offerings o
      where o.user_id = p.user_id
        and o.status = 'approved'
    ) as approved_offering_count,
    (
      select count(*)::bigint
      from public.offerings o
      where o.user_id = p.user_id
        and o.status = 'pending'
    ) as pending_offering_count,
    (
      select count(*)::bigint
      from public.reports r
      join public.offerings o
        on o.id = r.offering_id
      where o.user_id = p.user_id
        and r.status in ('open', 'reviewing', 'pending')
    ) as open_report_count,
    latest.action,
    latest.reason,
    latest.created_at
  from public.profiles p
  left join lateral (
    select
      e.action,
      e.reason,
      e.created_at
    from public.member_moderation_events e
    where e.member_user_id = p.user_id
    order by e.created_at desc
    limit 1
  ) latest on true
  where
    p_state = 'all'
    or (p_state = 'active' and p.is_suspended = false)
    or (p_state = 'suspended' and p.is_suspended = true)
  order by
    p.is_suspended desc,
    p.created_at desc;
end;
$$;

revoke all
on function public.admin_list_members(text)
from public, anon;

grant execute
on function public.admin_list_members(text)
to authenticated;

create or replace function public.admin_get_member_context(
  p_member_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_profile jsonb;
  v_offerings jsonb;
  v_reports jsonb;
  v_events jsonb;
begin
  if not public.is_admin() then
    raise exception 'Database-backed admin access is required.'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'user_id', p.user_id,
    'username', p.username,
    'display_name', p.display_name,
    'role', p.role,
    'is_verified', p.is_verified,
    'is_suspended', p.is_suspended,
    'is_public', p.is_public,
    'member_since', p.created_at
  )
  into v_profile
  from public.profiles p
  where p.user_id = p_member_user_id;

  if v_profile is null then
    return null;
  end if;

  -- Deliberately no query to public.reflections or public.daily_reflections.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', o.id,
        'title', o.title,
        'status', o.status,
        'is_anonymous', o.is_anonymous,
        'open_report_count', coalesce(o.open_report_count, 0),
        'moderation_note', o.moderation_note,
        'created_at', o.created_at,
        'published_at', o.published_at
      )
      order by o.created_at desc
    ),
    '[]'::jsonb
  )
  into v_offerings
  from public.offerings o
  where o.user_id = p_member_user_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'offering_id', r.offering_id,
        'offering_title', o.title,
        'reason', r.reason,
        'status', r.status,
        'details', r.details,
        'admin_note', r.admin_note,
        'created_at', r.created_at
      )
      order by r.created_at desc
    ),
    '[]'::jsonb
  )
  into v_reports
  from public.reports r
  join public.offerings o
    on o.id = r.offering_id
  where o.user_id = p_member_user_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', e.id,
        'action', e.action,
        'reason', e.reason,
        'actor_name', coalesce(a.display_name, a.username, 'Deedlight admin'),
        'created_at', e.created_at
      )
      order by e.created_at desc
    ),
    '[]'::jsonb
  )
  into v_events
  from public.member_moderation_events e
  left join public.profiles a
    on a.user_id = e.actor_user_id
  where e.member_user_id = p_member_user_id;

  return jsonb_build_object(
    'profile', v_profile,
    'offerings', v_offerings,
    'reports', v_reports,
    'moderation_events', v_events
  );
end;
$$;

revoke all
on function public.admin_get_member_context(uuid)
from public, anon;

grant execute
on function public.admin_get_member_context(uuid)
to authenticated;

-- ---------------------------------------------------------------------
-- 3. Auditable suspension mutation.
--    Only an unsuspended database-role admin may execute it.
--    Admin accounts cannot be moderated through this member tool.
-- ---------------------------------------------------------------------

create or replace function public.set_member_suspension(
  p_member_user_id uuid,
  p_suspended boolean,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_target public.profiles%rowtype;
  v_actor uuid := auth.uid();
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'Database-backed admin access is required.'
      using errcode = '42501';
  end if;

  if p_member_user_id is null or p_suspended is null then
    raise exception 'Member and suspension state are required.'
      using errcode = '22023';
  end if;

  if char_length(v_reason) < 8 or char_length(v_reason) > 500 then
    raise exception 'Moderation reason must be between 8 and 500 characters.'
      using errcode = '22023';
  end if;

  select p.*
  into v_target
  from public.profiles p
  where p.user_id = p_member_user_id
  for update;

  if not found then
    raise exception 'Member profile not found.'
      using errcode = '22023';
  end if;

  if v_target.user_id = v_actor then
    raise exception 'You cannot suspend or restore your own account from this tool.'
      using errcode = '42501';
  end if;

  if v_target.role = 'admin' then
    raise exception 'Admin accounts are not managed by the member suspension tool.'
      using errcode = '42501';
  end if;

  if v_target.is_suspended = p_suspended then
    if p_suspended then
      raise exception 'This member is already suspended.'
        using errcode = '22023';
    else
      raise exception 'This member is already active.'
        using errcode = '22023';
    end if;
  end if;

  update public.profiles
  set is_suspended = p_suspended
  where user_id = p_member_user_id;

  insert into public.member_moderation_events (
    member_user_id,
    actor_user_id,
    action,
    reason
  )
  values (
    p_member_user_id,
    v_actor,
    case when p_suspended then 'suspended' else 'restored' end,
    v_reason
  );
end;
$$;

revoke all
on function public.set_member_suspension(uuid, boolean, text)
from public, anon;

grant execute
on function public.set_member_suspension(uuid, boolean, text)
to authenticated;

-- ---------------------------------------------------------------------
-- 4. Close the remaining suspension gaps in community writes.
--    Existing insert/reaction/report policies are already suspension-aware.
-- ---------------------------------------------------------------------

drop policy if exists "offerings_update_own_or_admin"
on public.offerings;

create policy "offerings_update_own_or_admin"
on public.offerings
for update
to authenticated
using (
  public.is_admin()
  or (
    user_id = auth.uid()
    and status in ('draft', 'needs_edit')
    and not exists (
      select 1
      from public.profiles p
      where p.user_id = auth.uid()
        and p.is_suspended = true
    )
  )
)
with check (
  public.is_admin()
  or (
    user_id = auth.uid()
    and status in ('draft', 'pending', 'needs_edit')
    and not exists (
      select 1
      from public.profiles p
      where p.user_id = auth.uid()
        and p.is_suspended = true
    )
  )
);

drop policy if exists "offerings_user_update_safe_statuses"
on public.offerings;

create policy "offerings_user_update_safe_statuses"
on public.offerings
for update
to authenticated
using (
  user_id = auth.uid()
  and status in ('draft', 'needs_edit')
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
)
with check (
  user_id = auth.uid()
  and status in ('draft', 'pending')
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

drop policy if exists "reflections_own_insert"
on public.reflections;

create policy "reflections_own_insert"
on public.reflections
for insert
to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.offerings o
    where o.id = offering_id
      and o.status = 'approved'
      and o.allow_reflections = true
  )
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

drop policy if exists "reflections_own_update"
on public.reflections;

create policy "reflections_own_update"
on public.reflections
for update
to authenticated
using (
  user_id = auth.uid()
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
)
with check (
  user_id = auth.uid()
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

-- Private Daily reflections intentionally remain member-owned and unchanged.

notify pgrst, 'reload schema';

commit;

-- =====================================================================
-- END SPRINT 9.3 MODERATION-AWARE MEMBERS PARITY
-- =====================================================================

-- BEGIN SPRINT 10.1 DAILY DEED COMPLETION
-- Sprint 10.1 — Daily Habit & Retention
-- "I Did Today's Deed"
--
-- Bridges the legacy daily_posts completion model to the current
-- daily_lights system while keeping personal completion records private.

begin;

-- ============================================================
-- 1. Connect completion records to current Daily Lights
-- ============================================================

alter table public.daily_deed_completions
  add column if not exists daily_light_id uuid
  references public.daily_lights(id)
  on delete cascade;

alter table public.daily_deed_completions
  alter column daily_post_id drop not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'daily_deed_completions_has_source'
      and conrelid = 'public.daily_deed_completions'::regclass
  ) then
    alter table public.daily_deed_completions
      add constraint daily_deed_completions_has_source
      check (
        daily_post_id is not null
        or daily_light_id is not null
      );
  end if;
end
$$;

create unique index if not exists
  daily_deed_completions_user_light_unique
on public.daily_deed_completions (
  user_id,
  daily_light_id
);

create index if not exists
  daily_deed_completions_light_created_idx
on public.daily_deed_completions (
  daily_light_id,
  created_at desc
)
where daily_light_id is not null;

create index if not exists
  daily_deed_completions_user_created_idx
on public.daily_deed_completions (
  user_id,
  created_at desc
);

-- ============================================================
-- 2. Private completion RLS
-- ============================================================

alter table public.daily_deed_completions
  enable row level security;

drop policy if exists
  "daily_deed_completions_own_all"
on public.daily_deed_completions;

drop policy if exists
  "daily_deed_completions_select_own"
on public.daily_deed_completions;

drop policy if exists
  "daily_deed_completions_insert_own_published"
on public.daily_deed_completions;

drop policy if exists
  "daily_deed_completions_delete_own"
on public.daily_deed_completions;

create policy
  "daily_deed_completions_select_own"
on public.daily_deed_completions
for select
to authenticated
using (
  user_id = auth.uid()
);

create policy
  "daily_deed_completions_insert_own_published"
on public.daily_deed_completions
for insert
to authenticated
with check (
  user_id = auth.uid()
  and daily_light_id is not null
  and exists (
    select 1
    from public.daily_lights dl
    where dl.id = daily_light_id
      and dl.status = 'published'
  )
);

create policy
  "daily_deed_completions_delete_own"
on public.daily_deed_completions
for delete
to authenticated
using (
  user_id = auth.uid()
);

revoke all privileges
on table public.daily_deed_completions
from public, anon, authenticated;

grant select, insert, delete
on table public.daily_deed_completions
to authenticated;

grant all
on table public.daily_deed_completions
to service_role;

-- ============================================================
-- 3. Safe anonymous aggregate
-- ============================================================

drop view if exists
  public.daily_deed_completion_counts;

create view public.daily_deed_completion_counts
with (security_barrier = true)
as
select
  c.daily_light_id,
  count(*)::bigint as completion_count
from public.daily_deed_completions c
join public.daily_lights dl
  on dl.id = c.daily_light_id
where
  c.daily_light_id is not null
  and dl.status = 'published'
group by
  c.daily_light_id;

revoke all privileges
on table public.daily_deed_completion_counts
from public, anon, authenticated;

grant select
on table public.daily_deed_completion_counts
to anon, authenticated, service_role;

-- ============================================================
-- 4. Repair existing Daily Reflection compatibility
-- ============================================================

alter table public.daily_reflections
  alter column daily_post_id drop not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'daily_reflections_has_daily_source'
      and conrelid = 'public.daily_reflections'::regclass
  ) then
    alter table public.daily_reflections
      add constraint daily_reflections_has_daily_source
      check (
        daily_post_id is not null
        or daily_light_id is not null
      );
  end if;
end
$$;

notify pgrst, 'reload schema';

commit;
-- END SPRINT 10.1 DAILY DEED COMPLETION

-- BEGIN SPRINT 10.2 SAVED LIGHTS + GENTLE RHYTHM
-- Sprint 10.2 — Saved Lights + Gentle Rhythm
-- Extends the legacy saved_lights table to current Daily Lights and hardens
-- browser privileges. Saved rows remain private; rhythm remains derived only
-- from each member's private daily_deed_completions.

begin;

-- ============================================================
-- 1. Extend legacy saved_lights to current Daily Lights
-- ============================================================

alter table public.saved_lights
  add column if not exists daily_light_id uuid
  references public.daily_lights(id)
  on delete cascade;

alter table public.saved_lights
  drop constraint if exists saved_lights_check;

alter table public.saved_lights
  drop constraint if exists saved_lights_exactly_one_source;

alter table public.saved_lights
  add constraint saved_lights_exactly_one_source
  check (
    num_nonnulls(
      offering_id,
      daily_post_id,
      daily_light_id
    ) = 1
  );

create unique index if not exists
  saved_lights_unique_daily_light
on public.saved_lights (
  user_id,
  daily_light_id
)
where daily_light_id is not null;

create index if not exists
  saved_lights_user_created_idx
on public.saved_lights (
  user_id,
  created_at desc
);

-- ============================================================
-- 2. Replace broad legacy RLS with immutable private-save rules
-- ============================================================

alter table public.saved_lights
  enable row level security;

drop policy if exists
  "saved_lights_own_all"
on public.saved_lights;

drop policy if exists
  "saved_lights_select_own"
on public.saved_lights;

drop policy if exists
  "saved_lights_insert_own_published_daily_light"
on public.saved_lights;

drop policy if exists
  "saved_lights_delete_own"
on public.saved_lights;

create policy
  "saved_lights_select_own"
on public.saved_lights
for select
to authenticated
using (
  user_id = auth.uid()
);

create policy
  "saved_lights_insert_own_published_daily_light"
on public.saved_lights
for insert
to authenticated
with check (
  user_id = auth.uid()
  and daily_light_id is not null
  and offering_id is null
  and daily_post_id is null
  and exists (
    select 1
    from public.daily_lights dl
    where dl.id = daily_light_id
      and dl.status = 'published'
  )
);

create policy
  "saved_lights_delete_own"
on public.saved_lights
for delete
to authenticated
using (
  user_id = auth.uid()
);

-- Saving is immutable: create or remove a row; never update ownership/source.
revoke all privileges
on table public.saved_lights
from public, anon, authenticated;

grant select, insert, delete
on table public.saved_lights
to authenticated;

grant all
on table public.saved_lights
to service_role;

notify pgrst, 'reload schema';

commit;
-- END SPRINT 10.2 SAVED LIGHTS + GENTLE RHYTHM

-- BEGIN SPRINT 10.3A GENTLE DAILY REMINDER PREFERENCES
-- Sprint 10.3A — Gentle Daily Reminder Preferences
-- Stores private, opt-in reminder preferences without introducing delivery transport.
-- Reminder delivery remains a later infrastructure step.

begin;

create table if not exists public.daily_reminder_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  daily_enabled boolean not null default false,
  reminder_time time without time zone not null default '08:00',
  timezone text not null default 'UTC'
    check (
      char_length(timezone) between 1 and 64
      and timezone ~ '^[A-Za-z0-9_+./-]+$'
    ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists daily_reminder_preferences_set_updated_at
on public.daily_reminder_preferences;

create trigger daily_reminder_preferences_set_updated_at
before update on public.daily_reminder_preferences
for each row execute function public.set_updated_at();

alter table public.daily_reminder_preferences
  enable row level security;

drop policy if exists
  "daily_reminder_preferences_select_own"
on public.daily_reminder_preferences;

drop policy if exists
  "daily_reminder_preferences_insert_own"
on public.daily_reminder_preferences;

drop policy if exists
  "daily_reminder_preferences_update_own"
on public.daily_reminder_preferences;

create policy
  "daily_reminder_preferences_select_own"
on public.daily_reminder_preferences
for select
to authenticated
using (
  user_id = auth.uid()
);

create policy
  "daily_reminder_preferences_insert_own"
on public.daily_reminder_preferences
for insert
to authenticated
with check (
  user_id = auth.uid()
  and (
    daily_enabled = false
    or not exists (
      select 1
      from public.profiles p
      where p.user_id = auth.uid()
        and p.is_suspended = true
    )
  )
);

create policy
  "daily_reminder_preferences_update_own"
on public.daily_reminder_preferences
for update
to authenticated
using (
  user_id = auth.uid()
)
with check (
  user_id = auth.uid()
  and (
    daily_enabled = false
    or not exists (
      select 1
      from public.profiles p
      where p.user_id = auth.uid()
        and p.is_suspended = true
    )
  )
);

revoke all privileges
on table public.daily_reminder_preferences
from public, anon, authenticated;

grant select, insert, update
on table public.daily_reminder_preferences
to authenticated;

grant all
on table public.daily_reminder_preferences
to service_role;

notify pgrst, 'reload schema';

commit;
-- END SPRINT 10.3A GENTLE DAILY REMINDER PREFERENCES

-- Sprint 11.2 — Weekly Goodness
-- Seven-day public Offering activity plus an optional database-admin-curated
-- Featured Light. No reflection, Daily completion, Saved Light, or reminder
-- data is queried or exposed by these APIs.

begin;

-- ---------------------------------------------------------------------
-- 1. Make seven-day reaction aggregation efficient.
-- ---------------------------------------------------------------------

create index if not exists reactions_created_offering_type_idx
on public.reactions (created_at desc, offering_id, reaction_type);

-- ---------------------------------------------------------------------
-- 2. Private weekly feature selection.
--    The table itself is never readable or writable by browser roles.
-- ---------------------------------------------------------------------

create table if not exists public.weekly_goodness_features (
  week_start date primary key
    check (extract(isodow from week_start) = 1),
  offering_id uuid not null
    references public.offerings(id) on delete cascade,
  selected_by uuid
    references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.weekly_goodness_features
enable row level security;

drop trigger if exists weekly_goodness_features_set_updated_at
on public.weekly_goodness_features;

create trigger weekly_goodness_features_set_updated_at
before update on public.weekly_goodness_features
for each row execute function public.set_updated_at();

revoke all privileges
on table public.weekly_goodness_features
from public, anon, authenticated;

grant all privileges
on table public.weekly_goodness_features
to service_role;

-- ---------------------------------------------------------------------
-- 3. Public seven-day goodness API.
--    This SECURITY DEFINER function intentionally returns aggregate reaction
--    counts only. It exposes no reaction user IDs and does not read reflection
--    tables or reflection-derived bless_score values.
-- ---------------------------------------------------------------------

create or replace function public.get_weekly_goodness(
  p_limit integer default 12
)
returns table (
  id uuid,
  title text,
  body text,
  takeaway text,
  offering_type text,
  media_url text,
  media_type text,
  is_anonymous boolean,
  allow_reflections boolean,
  location_label text,
  bless_count integer,
  inspired_count integer,
  carried_forward_count integer,
  published_at timestamptz,
  theme_name text,
  author_name text,
  author_username text,
  weekly_bless_count integer,
  weekly_inspired_count integer,
  weekly_carried_forward_count integer,
  weekly_reaction_count integer
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_limit integer := least(
    greatest(coalesce(p_limit, 12), 1),
    24
  );
begin
  return query
  with recent as (
    select
      r.offering_id,
      count(*) filter (
        where r.reaction_type = 'bless'
      )::integer as weekly_bless_count,
      count(*) filter (
        where r.reaction_type = 'inspired_me'
      )::integer as weekly_inspired_count,
      count(*) filter (
        where r.reaction_type = 'i_did_this_too'
      )::integer as weekly_carried_forward_count,
      count(*)::integer as weekly_reaction_count
    from public.reactions r
    where r.created_at >= now() - interval '7 days'
    group by r.offering_id
  )
  select
    op.id,
    op.title,
    op.body,
    op.takeaway,
    op.offering_type,
    op.media_url,
    op.media_type,
    op.is_anonymous,
    op.allow_reflections,
    op.location_label,
    op.bless_count,
    op.inspired_count,
    op.carried_forward_count,
    op.published_at,
    op.theme_name,
    op.author_name,
    op.author_username,
    coalesce(recent.weekly_bless_count, 0)::integer,
    coalesce(recent.weekly_inspired_count, 0)::integer,
    coalesce(recent.weekly_carried_forward_count, 0)::integer,
    coalesce(recent.weekly_reaction_count, 0)::integer
  from public.offerings_public op
  left join recent
    on recent.offering_id = op.id
  where
    coalesce(recent.weekly_reaction_count, 0) > 0
    or op.published_at >= now() - interval '7 days'
  order by
    (
      coalesce(recent.weekly_bless_count, 0)
      + coalesce(recent.weekly_inspired_count, 0) * 2
      + coalesce(recent.weekly_carried_forward_count, 0) * 3
    ) desc,
    coalesce(recent.weekly_reaction_count, 0) desc,
    op.published_at desc nulls last,
    op.id
  limit v_limit;
end;
$$;

revoke all privileges
on function public.get_weekly_goodness(integer)
from public, anon, authenticated;

grant execute
on function public.get_weekly_goodness(integer)
to anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- 4. Public current Featured Light API.
--    Only the same privacy-minimized offerings_public projection is returned.
-- ---------------------------------------------------------------------

create or replace function public.get_current_weekly_goodness_feature()
returns table (
  week_start date,
  id uuid,
  title text,
  body text,
  takeaway text,
  offering_type text,
  media_url text,
  media_type text,
  is_anonymous boolean,
  allow_reflections boolean,
  location_label text,
  bless_count integer,
  inspired_count integer,
  carried_forward_count integer,
  published_at timestamptz,
  theme_name text,
  author_name text,
  author_username text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    f.week_start,
    op.id,
    op.title,
    op.body,
    op.takeaway,
    op.offering_type,
    op.media_url,
    op.media_type,
    op.is_anonymous,
    op.allow_reflections,
    op.location_label,
    op.bless_count,
    op.inspired_count,
    op.carried_forward_count,
    op.published_at,
    op.theme_name,
    op.author_name,
    op.author_username
  from public.weekly_goodness_features f
  join public.offerings_public op
    on op.id = f.offering_id
  where f.week_start =
    date_trunc('week', timezone('UTC', now()))::date
  limit 1;
$$;

revoke all privileges
on function public.get_current_weekly_goodness_feature()
from public, anon, authenticated;

grant execute
on function public.get_current_weekly_goodness_feature()
to anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- 5. Database-admin-only curation mutation.
--    ADMIN_EMAILS fallback access is deliberately insufficient here.
-- ---------------------------------------------------------------------

create or replace function public.set_weekly_goodness_feature(
  p_offering_id uuid
)
returns date
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_week_start date :=
    date_trunc('week', timezone('UTC', now()))::date;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'Database-backed admin access is required.'
      using errcode = '42501';
  end if;

  if p_offering_id is null then
    delete from public.weekly_goodness_features
    where week_start = v_week_start;

    return v_week_start;
  end if;

  if not exists (
    select 1
    from public.offerings o
    where o.id = p_offering_id
      and o.status = 'approved'
  ) then
    raise exception 'Featured Light must be an approved public Offering.'
      using errcode = '22023';
  end if;

  insert into public.weekly_goodness_features (
    week_start,
    offering_id,
    selected_by
  )
  values (
    v_week_start,
    p_offering_id,
    v_actor
  )
  on conflict (week_start)
  do update set
    offering_id = excluded.offering_id,
    selected_by = excluded.selected_by,
    updated_at = now();

  return v_week_start;
end;
$$;

revoke all privileges
on function public.set_weekly_goodness_feature(uuid)
from public, anon, authenticated;

grant execute
on function public.set_weekly_goodness_feature(uuid)
to authenticated, service_role;

notify pgrst, 'reload schema';

commit;

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

-- Sprint 12.1 — Offering Ownership & Engagement
-- Adds safe owner editing/removal/restore flows and private Offering saves.
-- Public attribution remains privacy-minimized; no public save counts or owner UUIDs are introduced.

begin;

-- ---------------------------------------------------------------------
-- 1. Distinguish member-removed Offerings from moderator-hidden content.
-- ---------------------------------------------------------------------

alter table public.offerings
  add column if not exists owner_removed_at timestamptz;

create index if not exists offerings_owner_removed_idx
  on public.offerings (user_id, owner_removed_at desc)
  where owner_removed_at is not null;

-- Keep owner_removed_at under the controlled owner RPCs rather than ordinary
-- browser INSERT/UPDATE privileges. Admin behavior is preserved.

drop policy if exists "offerings_user_insert_pending"
on public.offerings;

create policy "offerings_user_insert_pending"
on public.offerings
for insert
to authenticated
with check (
  user_id = auth.uid()
  and status in ('draft', 'pending')
  and owner_removed_at is null
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

drop policy if exists "offerings_update_own_or_admin"
on public.offerings;

create policy "offerings_update_own_or_admin"
on public.offerings
for update
to authenticated
using (
  public.is_admin()
  or (
    user_id = auth.uid()
    and status in ('draft', 'needs_edit')
    and owner_removed_at is null
    and not exists (
      select 1
      from public.profiles p
      where p.user_id = auth.uid()
        and p.is_suspended = true
    )
  )
)
with check (
  public.is_admin()
  or (
    user_id = auth.uid()
    and status in ('draft', 'pending', 'needs_edit')
    and owner_removed_at is null
    and not exists (
      select 1
      from public.profiles p
      where p.user_id = auth.uid()
        and p.is_suspended = true
    )
  )
);

drop policy if exists "offerings_user_update_safe_statuses"
on public.offerings;

create policy "offerings_user_update_safe_statuses"
on public.offerings
for update
to authenticated
using (
  user_id = auth.uid()
  and status in ('draft', 'needs_edit')
  and owner_removed_at is null
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
)
with check (
  user_id = auth.uid()
  and status in ('draft', 'pending')
  and owner_removed_at is null
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

-- ---------------------------------------------------------------------
-- 2. Extend private Saved Lights to approved Offerings.
--    Saves remain private, immutable rows: insert to save, delete to unsave.
-- ---------------------------------------------------------------------

drop policy if exists
  "saved_lights_insert_own_published_daily_light"
on public.saved_lights;

drop policy if exists
  "saved_lights_insert_own_published_source"
on public.saved_lights;

create policy
  "saved_lights_insert_own_published_source"
on public.saved_lights
for insert
to authenticated
with check (
  user_id = auth.uid()
  and (
    (
      daily_light_id is not null
      and offering_id is null
      and daily_post_id is null
      and exists (
        select 1
        from public.daily_lights dl
        where dl.id = daily_light_id
          and dl.status = 'published'
      )
    )
    or
    (
      offering_id is not null
      and daily_light_id is null
      and daily_post_id is null
      and exists (
        select 1
        from public.offerings_public op
        where op.id = offering_id
      )
    )
  )
);

revoke all privileges
on table public.saved_lights
from public, anon, authenticated;

grant select, insert, delete
on table public.saved_lights
to authenticated;

grant all
on table public.saved_lights
to service_role;

-- Repair the post-privacy reaction policy so members can react to any
-- approved public Offering, not only an Offering visible through own-row RLS.
-- The public view exposes no owner UUIDs and is sufficient for this boolean check.
drop policy if exists "reactions_insert_own_on_approved"
on public.reactions;

create policy "reactions_insert_own_on_approved"
on public.reactions
for insert
to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.offerings_public op
    where op.id = offering_id
  )
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

-- ---------------------------------------------------------------------
-- 3. Owner edit RPC.
--    Any edited public version leaves public discovery and returns to review.
--    Rejected or moderator-hidden Offerings cannot be bypassed by members.
-- ---------------------------------------------------------------------

create or replace function public.update_own_offering(
  p_offering_id uuid,
  p_offering_type text,
  p_title text,
  p_body text,
  p_takeaway text,
  p_media_url text,
  p_media_type text,
  p_is_anonymous boolean,
  p_allow_reflections boolean
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_offering public.offerings%rowtype;
  v_title text := btrim(coalesce(p_title, ''));
  v_body text := btrim(coalesce(p_body, ''));
  v_takeaway text := nullif(btrim(coalesce(p_takeaway, '')), '');
  v_media_url text := nullif(btrim(coalesce(p_media_url, '')), '');
  v_media_type text := p_media_type;
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
    raise exception 'An active member profile is required.' using errcode = '42501';
  end if;

  if p_offering_id is null then
    raise exception 'Offering is required.' using errcode = '22023';
  end if;

  if p_offering_type not in (
    'good_deed',
    'goodness_invitation',
    'gratitude',
    'beauty_reminder',
    'quiet_goodness',
    'community_need'
  ) then
    raise exception 'Invalid Offering type.' using errcode = '22023';
  end if;

  if char_length(v_title) < 4 or char_length(v_title) > 120 then
    raise exception 'Title must be between 4 and 120 characters.' using errcode = '22023';
  end if;

  if char_length(v_body) < 20 or char_length(v_body) > 5000 then
    raise exception 'Offering body must be between 20 and 5000 characters.' using errcode = '22023';
  end if;

  if v_takeaway is not null and char_length(v_takeaway) > 500 then
    raise exception 'Small deed must be 500 characters or fewer.' using errcode = '22023';
  end if;

  if v_media_url is not null and char_length(v_media_url) > 1000 then
    raise exception 'Media URL is too long.' using errcode = '22023';
  end if;

  if v_media_url is not null and v_media_url !~* '^https?://' then
    raise exception 'Media URL must use http or https.' using errcode = '22023';
  end if;

  if v_media_url is null then
    v_media_type := null;
  elsif v_media_type is null or v_media_type not in ('image', 'video') then
    raise exception 'Media type is invalid.' using errcode = '22023';
  end if;

  select o.*
  into v_offering
  from public.offerings o
  where o.id = p_offering_id
    and o.user_id = v_actor
  for update;

  if not found then
    raise exception 'Offering was not found.' using errcode = '42501';
  end if;

  if v_offering.status = 'rejected' then
    raise exception 'Rejected Offerings cannot be resubmitted from the member editor.' using errcode = '42501';
  end if;

  if v_offering.status = 'hidden' and v_offering.owner_removed_at is null then
    raise exception 'Moderator-hidden Offerings cannot be changed from the member editor.' using errcode = '42501';
  end if;

  update public.offerings
  set
    offering_type = p_offering_type,
    title = v_title,
    body = v_body,
    takeaway = v_takeaway,
    media_url = v_media_url,
    media_type = v_media_type,
    is_anonymous = coalesce(p_is_anonymous, false),
    allow_reflections = coalesce(p_allow_reflections, false),
    status = 'pending',
    moderation_note = null,
    published_at = null,
    owner_removed_at = null
  where id = p_offering_id;

  return p_offering_id;
end;
$$;

revoke all
on function public.update_own_offering(
  uuid, text, text, text, text, text, text, boolean, boolean
)
from public, anon;

grant execute
on function public.update_own_offering(
  uuid, text, text, text, text, text, text, boolean, boolean
)
to authenticated;

-- ---------------------------------------------------------------------
-- 4. Reversible owner removal.
--    This is intentionally a soft removal, not browser DELETE.
--    A suspended owner may still remove their own content for privacy/safety.
-- ---------------------------------------------------------------------

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
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  select o.*
  into v_offering
  from public.offerings o
  where o.id = p_offering_id
    and o.user_id = v_actor
  for update;

  if not found then
    raise exception 'Offering was not found.' using errcode = '42501';
  end if;

  if v_offering.status = 'hidden' and v_offering.owner_removed_at is null then
    raise exception 'Moderator-hidden Offerings cannot be changed from the member controls.' using errcode = '42501';
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
from public, anon;

grant execute
on function public.remove_own_offering(uuid)
to authenticated;

-- ---------------------------------------------------------------------
-- 5. Restore an owner-removed Offering to moderation review.
-- ---------------------------------------------------------------------

create or replace function public.restore_own_offering(
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
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.user_id = v_actor
      and p.is_suspended = false
  ) then
    raise exception 'An active member profile is required.' using errcode = '42501';
  end if;

  select o.*
  into v_offering
  from public.offerings o
  where o.id = p_offering_id
    and o.user_id = v_actor
  for update;

  if not found then
    raise exception 'Offering was not found.' using errcode = '42501';
  end if;

  if v_offering.status <> 'hidden' or v_offering.owner_removed_at is null then
    raise exception 'Only an Offering you removed can be restored.' using errcode = '42501';
  end if;

  update public.offerings
  set
    status = 'pending',
    owner_removed_at = null,
    moderation_note = null,
    published_at = null
  where id = p_offering_id;

  return p_offering_id;
end;
$$;

revoke all
on function public.restore_own_offering(uuid)
from public, anon;

grant execute
on function public.restore_own_offering(uuid)
to authenticated;

notify pgrst, 'reload schema';

commit;

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


-- Sprint 12.2 — Gentle Delivery Foundation
-- Transport-neutral queueing and authorization gates only.
-- This migration does not configure a cron trigger or any outbound provider.

begin;

-- ---------------------------------------------------------------------
-- 1. Reminder preference writes move behind one validating RPC.
-- ---------------------------------------------------------------------

create or replace function public.set_daily_reminder_preference(
  p_enabled boolean,
  p_reminder_time time without time zone,
  p_timezone text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_enabled boolean := coalesce(p_enabled, false);
  v_timezone text := btrim(coalesce(p_timezone, ''));
begin
  if v_actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  if p_reminder_time is null then
    raise exception 'A reminder time is required.' using errcode = '22023';
  end if;

  if char_length(v_timezone) < 1
     or char_length(v_timezone) > 64
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names tz
       where tz.name = v_timezone
     ) then
    raise exception 'A valid IANA timezone is required.' using errcode = '22023';
  end if;

  if v_enabled and exists (
    select 1
    from public.profiles p
    where p.user_id = v_actor
      and p.is_suspended = true
  ) then
    raise exception 'Reminder preferences cannot be enabled while community access is suspended.'
      using errcode = '42501';
  end if;

  insert into public.daily_reminder_preferences (
    user_id,
    daily_enabled,
    reminder_time,
    timezone
  )
  values (
    v_actor,
    v_enabled,
    p_reminder_time,
    v_timezone
  )
  on conflict (user_id)
  do update set
    daily_enabled = excluded.daily_enabled,
    reminder_time = excluded.reminder_time,
    timezone = excluded.timezone,
    updated_at = now();

  return v_enabled;
end;
$$;

revoke all privileges
on function public.set_daily_reminder_preference(boolean, time without time zone, text)
from public, anon, authenticated;

grant execute
on function public.set_daily_reminder_preference(boolean, time without time zone, text)
to authenticated;

revoke insert, update
on table public.daily_reminder_preferences
from authenticated;

-- ---------------------------------------------------------------------
-- 2. Private delivery ledger.
--    No recipient address or member content is stored here.
-- ---------------------------------------------------------------------

create table if not exists public.delivery_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null
    check (kind in ('daily_reminder', 'weekly_newsletter')),
  delivery_key text not null
    check (char_length(delivery_key) between 1 and 80),
  state text not null default 'queued'
    check (state in ('queued', 'claimed', 'cancelled', 'sent', 'failed')),
  scheduled_for timestamptz not null,
  claim_token uuid,
  claimed_at timestamptz,
  sent_at timestamptz,
  failed_at timestamptz,
  cancelled_at timestamptz,
  provider_result_id text
    check (
      provider_result_id is null
      or char_length(provider_result_id) between 1 and 255
    ),
  error_code text
    check (
      error_code is null
      or char_length(error_code) between 1 and 100
    ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (kind, user_id, delivery_key)
);

create index if not exists delivery_ledger_ready_idx
on public.delivery_ledger (state, scheduled_for, created_at);

create index if not exists delivery_ledger_user_idx
on public.delivery_ledger (user_id, created_at desc);

alter table public.delivery_ledger enable row level security;

drop trigger if exists delivery_ledger_set_updated_at
on public.delivery_ledger;

create trigger delivery_ledger_set_updated_at
before update on public.delivery_ledger
for each row execute function public.set_updated_at();

revoke all privileges
on table public.delivery_ledger
from public, anon, authenticated;

grant all privileges
on table public.delivery_ledger
to service_role;

-- ---------------------------------------------------------------------
-- 3. Deterministically enqueue today's due reminder for active opt-ins.
--    Repeated runs are idempotent through the unique delivery key.
-- ---------------------------------------------------------------------

create or replace function public.enqueue_due_daily_reminders(
  p_now timestamptz default now(),
  p_limit integer default 500
)
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_inserted integer := 0;
begin
  if p_now is null then
    raise exception 'A scheduler timestamp is required.' using errcode = '22023';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'p_limit must be between 1 and 5000.' using errcode = '22023';
  end if;

  with candidates as (
    select
      drp.user_id,
      timezone(drp.timezone, p_now)::date as local_date,
      (
        (
          timezone(drp.timezone, p_now)::date
          + drp.reminder_time
        ) at time zone drp.timezone
      ) as scheduled_for
    from public.daily_reminder_preferences drp
    join public.profiles p
      on p.user_id = drp.user_id
     and p.is_suspended = false
    join pg_catalog.pg_timezone_names tz
      on tz.name = drp.timezone
    where drp.daily_enabled = true
  ), due as (
    select *
    from candidates
    where scheduled_for <= p_now
    order by scheduled_for, user_id
    limit p_limit
  ), inserted as (
    insert into public.delivery_ledger (
      user_id,
      kind,
      delivery_key,
      scheduled_for
    )
    select
      due.user_id,
      'daily_reminder',
      'daily:' || due.local_date::text,
      due.scheduled_for
    from due
    on conflict (kind, user_id, delivery_key) do nothing
    returning 1
  )
  select count(*)::integer
  into v_inserted
  from inserted;

  return v_inserted;
end;
$$;

revoke all privileges
on function public.enqueue_due_daily_reminders(timestamptz, integer)
from public, anon, authenticated;

grant execute
on function public.enqueue_due_daily_reminders(timestamptz, integer)
to service_role;

-- ---------------------------------------------------------------------
-- 4. Enqueue one explicitly identified Weekly Goodness issue.
--    Email addresses remain in Supabase Auth and are never copied here.
-- ---------------------------------------------------------------------

create or replace function public.enqueue_weekly_goodness_delivery(
  p_week_start date,
  p_scheduled_for timestamptz default now(),
  p_limit integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_inserted integer := 0;
begin
  if p_week_start is null
     or extract(isodow from p_week_start) <> 1 then
    raise exception 'p_week_start must be a Monday.' using errcode = '22023';
  end if;

  if p_scheduled_for is null then
    raise exception 'A scheduled timestamp is required.' using errcode = '22023';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 10000 then
    raise exception 'p_limit must be between 1 and 10000.' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.weekly_goodness_features f
    where f.week_start = p_week_start
  ) then
    raise exception 'Weekly Goodness issue has not been explicitly curated.'
      using errcode = '22023';
  end if;

  with eligible as (
    select np.user_id
    from public.newsletter_preferences np
    join public.profiles p
      on p.user_id = np.user_id
     and p.is_suspended = false
    join auth.users u
      on u.id = np.user_id
     and u.email_confirmed_at is not null
     and nullif(btrim(u.email), '') is not null
    where np.weekly_enabled = true
      and np.consented_at is not null
    order by np.user_id
    limit p_limit
  ), inserted as (
    insert into public.delivery_ledger (
      user_id,
      kind,
      delivery_key,
      scheduled_for
    )
    select
      eligible.user_id,
      'weekly_newsletter',
      'weekly:' || p_week_start::text,
      p_scheduled_for
    from eligible
    on conflict (kind, user_id, delivery_key) do nothing
    returning 1
  )
  select count(*)::integer
  into v_inserted
  from inserted;

  return v_inserted;
end;
$$;

revoke all privileges
on function public.enqueue_weekly_goodness_delivery(date, timestamptz, integer)
from public, anon, authenticated;

grant execute
on function public.enqueue_weekly_goodness_delivery(date, timestamptz, integer)
to service_role;

-- ---------------------------------------------------------------------
-- 5. Claim due jobs without exposing recipient addresses.
-- ---------------------------------------------------------------------

create or replace function public.claim_delivery_jobs(
  p_now timestamptz default now(),
  p_limit integer default 100
)
returns table (
  job_id uuid,
  user_id uuid,
  kind text,
  delivery_key text,
  scheduled_for timestamptz,
  claim_token uuid
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if p_now is null then
    raise exception 'A claim timestamp is required.' using errcode = '22023';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'p_limit must be between 1 and 1000.' using errcode = '22023';
  end if;

  return query
  with picked as (
    select dl.id
    from public.delivery_ledger dl
    where dl.state = 'queued'
      and dl.scheduled_for <= p_now
    order by dl.scheduled_for, dl.created_at, dl.id
    for update skip locked
    limit p_limit
  ), claimed as (
    update public.delivery_ledger dl
    set
      state = 'claimed',
      claim_token = gen_random_uuid(),
      claimed_at = p_now,
      error_code = null,
      updated_at = now()
    from picked
    where dl.id = picked.id
    returning
      dl.id,
      dl.user_id,
      dl.kind,
      dl.delivery_key,
      dl.scheduled_for,
      dl.claim_token
  )
  select
    claimed.id,
    claimed.user_id,
    claimed.kind,
    claimed.delivery_key,
    claimed.scheduled_for,
    claimed.claim_token
  from claimed;
end;
$$;

revoke all privileges
on function public.claim_delivery_jobs(timestamptz, integer)
from public, anon, authenticated;

grant execute
on function public.claim_delivery_jobs(timestamptz, integer)
to service_role;

-- ---------------------------------------------------------------------
-- 6. Re-authorize immediately before any future external transport.
--    Revoked consent or suspension cancels the claimed job.
-- ---------------------------------------------------------------------

create or replace function public.authorize_delivery_job(
  p_job_id uuid,
  p_claim_token uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_job public.delivery_ledger%rowtype;
  v_authorized boolean := false;
begin
  if p_job_id is null or p_claim_token is null then
    raise exception 'A job ID and claim token are required.' using errcode = '22023';
  end if;

  select * into v_job
  from public.delivery_ledger dl
  where dl.id = p_job_id
  for update;

  if not found
     or v_job.state <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  if v_job.kind = 'daily_reminder' then
    select exists (
      select 1
      from public.daily_reminder_preferences drp
      join public.profiles p
        on p.user_id = drp.user_id
       and p.is_suspended = false
      join pg_catalog.pg_timezone_names tz
        on tz.name = drp.timezone
      where drp.user_id = v_job.user_id
        and drp.daily_enabled = true
        and v_job.delivery_key =
          'daily:' || timezone(drp.timezone, v_job.scheduled_for)::date::text
        and v_job.scheduled_for = (
          (
            timezone(drp.timezone, v_job.scheduled_for)::date
            + drp.reminder_time
          ) at time zone drp.timezone
        )
    ) into v_authorized;
  elsif v_job.kind = 'weekly_newsletter' then
    select exists (
      select 1
      from public.newsletter_preferences np
      join public.profiles p
        on p.user_id = np.user_id
       and p.is_suspended = false
      join auth.users u
        on u.id = np.user_id
       and u.email_confirmed_at is not null
       and nullif(btrim(u.email), '') is not null
      join public.weekly_goodness_features f
        on v_job.delivery_key = 'weekly:' || f.week_start::text
      where np.user_id = v_job.user_id
        and np.weekly_enabled = true
        and np.consented_at is not null
    ) into v_authorized;
  else
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  if not v_authorized then
    update public.delivery_ledger
    set
      state = 'cancelled',
      cancelled_at = now(),
      error_code = 'authorization_revoked',
      updated_at = now()
    where id = v_job.id;

    return false;
  end if;

  return true;
end;
$$;

revoke all privileges
on function public.authorize_delivery_job(uuid, uuid)
from public, anon, authenticated;

grant execute
on function public.authorize_delivery_job(uuid, uuid)
to service_role;

-- ---------------------------------------------------------------------
-- 7. Terminal state transitions. These record provider-neutral outcomes only.
-- ---------------------------------------------------------------------

create or replace function public.mark_delivery_sent(
  p_job_id uuid,
  p_claim_token uuid,
  p_provider_result_id text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if p_provider_result_id is not null
     and char_length(p_provider_result_id) > 255 then
    raise exception 'Provider result identifier is too long.' using errcode = '22023';
  end if;

  update public.delivery_ledger
  set
    state = 'sent',
    sent_at = now(),
    provider_result_id = nullif(btrim(p_provider_result_id), ''),
    error_code = null,
    updated_at = now()
  where id = p_job_id
    and state = 'claimed'
    and claim_token = p_claim_token;

  if not found then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  return true;
end;
$$;

revoke all privileges
on function public.mark_delivery_sent(uuid, uuid, text)
from public, anon, authenticated;

grant execute
on function public.mark_delivery_sent(uuid, uuid, text)
to service_role;

create or replace function public.mark_delivery_failed(
  p_job_id uuid,
  p_claim_token uuid,
  p_error_code text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_error_code text := btrim(coalesce(p_error_code, ''));
begin
  if char_length(v_error_code) < 1
     or char_length(v_error_code) > 100 then
    raise exception 'A bounded error code is required.' using errcode = '22023';
  end if;

  update public.delivery_ledger
  set
    state = 'failed',
    failed_at = now(),
    error_code = v_error_code,
    updated_at = now()
  where id = p_job_id
    and state = 'claimed'
    and claim_token = p_claim_token;

  if not found then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  return true;
end;
$$;

revoke all privileges
on function public.mark_delivery_failed(uuid, uuid, text)
from public, anon, authenticated;

grant execute
on function public.mark_delivery_failed(uuid, uuid, text)
to service_role;

notify pgrst, 'reload schema';

commit;

-- Delivery Reliability Hardening
-- Adds bounded claim leases and retry safety without activating transport.

begin;

-- ---------------------------------------------------------------------
-- 1. Refuse an unexpected or partially applied baseline.
-- ---------------------------------------------------------------------

do $$
begin
  if to_regclass('public.delivery_ledger') is null then
    raise exception 'Delivery reliability hardening requires the Sprint 12.2 delivery ledger.';
  end if;

  if to_regprocedure('public.claim_delivery_jobs(timestamp with time zone,integer)') is null
     or to_regprocedure('public.authorize_delivery_job(uuid,uuid)') is null
     or to_regprocedure('public.mark_delivery_sent(uuid,uuid,text)') is null
     or to_regprocedure('public.mark_delivery_failed(uuid,uuid,text)') is null then
    raise exception 'Delivery reliability hardening requires the complete Sprint 12.2 RPC baseline.';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'delivery_ledger'
      and column_name in (
        'claim_expires_at',
        'attempt_count',
        'last_attempt_at',
        'next_attempt_at'
      )
  )
  or to_regprocedure(
    'public.retry_delivery_job(uuid,uuid,timestamp with time zone,text)'
  ) is not null then
    raise exception 'Delivery reliability hardening is already or partially applied.';
  end if;

  if exists (
    select 1
    from public.delivery_ledger
    where state = 'claimed'
  ) then
    raise exception 'Delivery reliability hardening refuses to migrate live claimed jobs.';
  end if;
end
$$;

-- ---------------------------------------------------------------------
-- 2. Add bounded lease/retry metadata. Original scheduled_for remains the
--    semantic delivery time; next_attempt_at is transport retry availability.
-- ---------------------------------------------------------------------

alter table public.delivery_ledger
  add column claim_expires_at timestamptz,
  add column attempt_count integer not null default 0,
  add column last_attempt_at timestamptz,
  add column next_attempt_at timestamptz;

update public.delivery_ledger
set
  claim_token = null,
  claim_expires_at = null
where state <> 'claimed';

alter table public.delivery_ledger
  add constraint delivery_ledger_attempt_count_check
  check (attempt_count between 0 and 5),
  add constraint delivery_ledger_claim_lease_check
  check (
    (
      state = 'claimed'
      and claim_token is not null
      and claimed_at is not null
      and claim_expires_at is not null
    )
    or
    (
      state <> 'claimed'
      and claim_token is null
      and claim_expires_at is null
    )
  );

create index delivery_ledger_retry_ready_idx
on public.delivery_ledger (
  state,
  next_attempt_at,
  scheduled_for,
  created_at
);

-- ---------------------------------------------------------------------
-- 3. Claim queued jobs or reclaim expired leases. Each successful claim is
--    one attempt. Expired fifth attempts become terminal retry_exhausted.
-- ---------------------------------------------------------------------

create or replace function public.claim_delivery_jobs(
  p_now timestamptz default now(),
  p_limit integer default 100
)
returns table (
  job_id uuid,
  user_id uuid,
  kind text,
  delivery_key text,
  scheduled_for timestamptz,
  claim_token uuid
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if p_now is null then
    raise exception 'A claim timestamp is required.' using errcode = '22023';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'p_limit must be between 1 and 1000.' using errcode = '22023';
  end if;

  update public.delivery_ledger dl
  set
    state = 'failed',
    failed_at = p_now,
    claim_token = null,
    claim_expires_at = null,
    next_attempt_at = null,
    error_code = 'retry_exhausted',
    updated_at = now()
  where dl.state = 'claimed'
    and dl.claim_expires_at is not null
    and dl.claim_expires_at <= p_now
    and dl.attempt_count >= 5;

  return query
  with picked as (
    select dl.id
    from public.delivery_ledger dl
    where (
        dl.state = 'queued'
        and coalesce(dl.next_attempt_at, dl.scheduled_for) <= p_now
        and dl.attempt_count < 5
      )
      or (
        dl.state = 'claimed'
        and dl.claim_expires_at is not null
        and dl.claim_expires_at <= p_now
        and dl.attempt_count < 5
      )
    order by
      coalesce(dl.next_attempt_at, dl.scheduled_for),
      dl.created_at,
      dl.id
    for update skip locked
    limit p_limit
  ), claimed as (
    update public.delivery_ledger dl
    set
      state = 'claimed',
      claim_token = gen_random_uuid(),
      claimed_at = p_now,
      claim_expires_at = p_now + interval '5 minutes',
      attempt_count = dl.attempt_count + 1,
      last_attempt_at = p_now,
      next_attempt_at = null,
      error_code = null,
      updated_at = now()
    from picked
    where dl.id = picked.id
    returning
      dl.id,
      dl.user_id,
      dl.kind,
      dl.delivery_key,
      dl.scheduled_for,
      dl.claim_token
  )
  select
    claimed.id,
    claimed.user_id,
    claimed.kind,
    claimed.delivery_key,
    claimed.scheduled_for,
    claimed.claim_token
  from claimed;
end;
$$;

revoke all privileges
on function public.claim_delivery_jobs(timestamptz, integer)
from public, anon, authenticated;

grant execute
on function public.claim_delivery_jobs(timestamptz, integer)
to service_role;

-- ---------------------------------------------------------------------
-- 4. A claim must still be live when current authorization is checked.
--    Revoked consent/suspension cancels the job and invalidates the token.
-- ---------------------------------------------------------------------

create or replace function public.authorize_delivery_job(
  p_job_id uuid,
  p_claim_token uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_job public.delivery_ledger%rowtype;
  v_authorized boolean := false;
begin
  if p_job_id is null or p_claim_token is null then
    raise exception 'A job ID and claim token are required.' using errcode = '22023';
  end if;

  select * into v_job
  from public.delivery_ledger dl
  where dl.id = p_job_id
  for update;

  if not found
     or v_job.state <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token
     or v_job.claim_expires_at is null
     or v_job.claim_expires_at <= now() then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  if v_job.kind = 'daily_reminder' then
    select exists (
      select 1
      from public.daily_reminder_preferences drp
      join public.profiles p
        on p.user_id = drp.user_id
       and p.is_suspended = false
      join pg_catalog.pg_timezone_names tz
        on tz.name = drp.timezone
      where drp.user_id = v_job.user_id
        and drp.daily_enabled = true
        and v_job.delivery_key =
          'daily:' || timezone(drp.timezone, v_job.scheduled_for)::date::text
        and v_job.scheduled_for = (
          (
            timezone(drp.timezone, v_job.scheduled_for)::date
            + drp.reminder_time
          ) at time zone drp.timezone
        )
    ) into v_authorized;
  elsif v_job.kind = 'weekly_newsletter' then
    select exists (
      select 1
      from public.newsletter_preferences np
      join public.profiles p
        on p.user_id = np.user_id
       and p.is_suspended = false
      join auth.users u
        on u.id = np.user_id
       and u.email_confirmed_at is not null
       and nullif(btrim(u.email), '') is not null
      join public.weekly_goodness_features f
        on v_job.delivery_key = 'weekly:' || f.week_start::text
      where np.user_id = v_job.user_id
        and np.weekly_enabled = true
        and np.consented_at is not null
    ) into v_authorized;
  else
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  if not v_authorized then
    update public.delivery_ledger
    set
      state = 'cancelled',
      cancelled_at = now(),
      claim_token = null,
      claim_expires_at = null,
      next_attempt_at = null,
      error_code = 'authorization_revoked',
      updated_at = now()
    where id = v_job.id;

    return false;
  end if;

  return true;
end;
$$;

revoke all privileges
on function public.authorize_delivery_job(uuid, uuid)
from public, anon, authenticated;

grant execute
on function public.authorize_delivery_job(uuid, uuid)
to service_role;

-- ---------------------------------------------------------------------
-- 5. Temporary provider failures requeue the same logical job without
--    changing scheduled_for. A fifth failed attempt becomes terminal.
-- ---------------------------------------------------------------------

create or replace function public.retry_delivery_job(
  p_job_id uuid,
  p_claim_token uuid,
  p_retry_at timestamptz,
  p_error_code text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_job public.delivery_ledger%rowtype;
  v_error_code text := btrim(coalesce(p_error_code, ''));
begin
  if p_job_id is null or p_claim_token is null or p_retry_at is null then
    raise exception 'A job ID, claim token, and retry time are required.' using errcode = '22023';
  end if;

  if char_length(v_error_code) < 1
     or char_length(v_error_code) > 100 then
    raise exception 'A bounded error code is required.' using errcode = '22023';
  end if;

  if p_retry_at <= now()
     or p_retry_at > now() + interval '24 hours' then
    raise exception 'Retry time must be within the next 24 hours.' using errcode = '22023';
  end if;

  select * into v_job
  from public.delivery_ledger dl
  where dl.id = p_job_id
  for update;

  if not found
     or v_job.state <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token
     or v_job.claim_expires_at is null
     or v_job.claim_expires_at <= now() then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  if v_job.attempt_count >= 5 then
    update public.delivery_ledger
    set
      state = 'failed',
      failed_at = now(),
      claim_token = null,
      claim_expires_at = null,
      next_attempt_at = null,
      error_code = 'retry_exhausted',
      updated_at = now()
    where id = v_job.id;

    return false;
  end if;

  update public.delivery_ledger
  set
    state = 'queued',
    claim_token = null,
    claim_expires_at = null,
    next_attempt_at = p_retry_at,
    error_code = v_error_code,
    updated_at = now()
  where id = v_job.id;

  return true;
end;
$$;

revoke all privileges
on function public.retry_delivery_job(uuid, uuid, timestamptz, text)
from public, anon, authenticated;

grant execute
on function public.retry_delivery_job(uuid, uuid, timestamptz, text)
to service_role;

-- ---------------------------------------------------------------------
-- 6. Terminal outcomes require a live claim and invalidate its token.
-- ---------------------------------------------------------------------

create or replace function public.mark_delivery_sent(
  p_job_id uuid,
  p_claim_token uuid,
  p_provider_result_id text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if p_provider_result_id is not null
     and char_length(p_provider_result_id) > 255 then
    raise exception 'Provider result identifier is too long.' using errcode = '22023';
  end if;

  update public.delivery_ledger
  set
    state = 'sent',
    sent_at = now(),
    claim_token = null,
    claim_expires_at = null,
    next_attempt_at = null,
    provider_result_id = nullif(btrim(p_provider_result_id), ''),
    error_code = null,
    updated_at = now()
  where id = p_job_id
    and state = 'claimed'
    and claim_token = p_claim_token
    and claim_expires_at is not null
    and claim_expires_at > now();

  if not found then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  return true;
end;
$$;

revoke all privileges
on function public.mark_delivery_sent(uuid, uuid, text)
from public, anon, authenticated;

grant execute
on function public.mark_delivery_sent(uuid, uuid, text)
to service_role;

create or replace function public.mark_delivery_failed(
  p_job_id uuid,
  p_claim_token uuid,
  p_error_code text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_error_code text := btrim(coalesce(p_error_code, ''));
begin
  if char_length(v_error_code) < 1
     or char_length(v_error_code) > 100 then
    raise exception 'A bounded error code is required.' using errcode = '22023';
  end if;

  update public.delivery_ledger
  set
    state = 'failed',
    failed_at = now(),
    claim_token = null,
    claim_expires_at = null,
    next_attempt_at = null,
    error_code = v_error_code,
    updated_at = now()
  where id = p_job_id
    and state = 'claimed'
    and claim_token = p_claim_token
    and claim_expires_at is not null
    and claim_expires_at > now();

  if not found then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  return true;
end;
$$;

revoke all privileges
on function public.mark_delivery_failed(uuid, uuid, text)
from public, anon, authenticated;

grant execute
on function public.mark_delivery_failed(uuid, uuid, text)
to service_role;

notify pgrst, 'reload schema';

commit;


-- Gentle Delivery Transport — provider-idempotency boundary and weekly scheduler helper.
-- Requires delivery reliability migration 020.

begin;

do $$
begin
  if to_regclass('public.delivery_ledger') is null
     or to_regprocedure('public.retry_delivery_job(uuid,uuid,timestamp with time zone,text)') is null
     or not exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'delivery_ledger'
         and column_name = 'claim_expires_at'
     ) then
    raise exception 'Delivery reliability migration 020 must be applied first.';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'delivery_ledger'
      and column_name = 'transport_started_at'
  )
  or to_regprocedure('public.begin_delivery_transport(uuid,uuid)') is not null
  or to_regprocedure('public.enqueue_current_weekly_goodness_if_curated(timestamp with time zone,integer)') is not null then
    raise exception 'Gentle delivery transport migration appears partially applied.';
  end if;
end;
$$;

alter table public.delivery_ledger
  add column transport_started_at timestamptz;

create or replace function public.begin_delivery_transport(
  p_job_id uuid,
  p_claim_token uuid
)
returns timestamptz
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_started_at timestamptz;
begin
  if p_job_id is null or p_claim_token is null then
    raise exception 'A job ID and claim token are required.' using errcode = '22023';
  end if;

  update public.delivery_ledger
  set
    transport_started_at = coalesce(transport_started_at, now()),
    updated_at = now()
  where id = p_job_id
    and state = 'claimed'
    and claim_token = p_claim_token
    and claim_expires_at > now()
  returning transport_started_at into v_started_at;

  if not found then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  return v_started_at;
end;
$$;

revoke all privileges
on function public.begin_delivery_transport(uuid, uuid)
from public, anon, authenticated;

grant execute
on function public.begin_delivery_transport(uuid, uuid)
to service_role;

create or replace function public.enqueue_current_weekly_goodness_if_curated(
  p_now timestamptz default now(),
  p_limit integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_week_start date;
begin
  if p_now is null then
    raise exception 'A scheduler timestamp is required.' using errcode = '22023';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 10000 then
    raise exception 'p_limit must be between 1 and 10000.' using errcode = '22023';
  end if;

  v_week_start := (
    timezone('UTC', p_now)::date
    - (extract(isodow from timezone('UTC', p_now))::integer - 1)
  );

  if not exists (
    select 1
    from public.weekly_goodness_features f
    where f.week_start = v_week_start
  ) then
    return 0;
  end if;

  return public.enqueue_weekly_goodness_delivery(v_week_start, p_now, p_limit);
end;
$$;

revoke all privileges
on function public.enqueue_current_weekly_goodness_if_curated(timestamptz, integer)
from public, anon, authenticated;

grant execute
on function public.enqueue_current_weekly_goodness_if_curated(timestamptz, integer)
to service_role;

notify pgrst, 'reload schema';

commit;


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


-- Delivery consent linearization and starvation-free enqueue.
-- Migration 023: additive function replacements, no runtime activation.
begin;

do $$
begin
  if to_regclass('public.delivery_ledger') is null
     or to_regclass('public.daily_reminder_preferences') is null
     or to_regclass('public.newsletter_preferences') is null
     or to_regclass('public.profiles') is null
     or to_regclass('public.weekly_goodness_features') is null
     or to_regprocedure('public.begin_delivery_transport(uuid,uuid)') is null
     or to_regprocedure('public.retry_delivery_job(uuid,uuid,timestamp with time zone,text)') is null
     or not exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'delivery_ledger'
         and column_name = 'transport_started_at'
     ) then
    raise exception 'Migration 023 requires the verified delivery 019-021 baseline.';
  end if;
end;
$$;

-- Eliminate starvation: exclude existing logical jobs BEFORE the limit.
-- Uniqueness and ON CONFLICT remain the final concurrent-insertion guard.
create or replace function public.enqueue_due_daily_reminders(
  p_now timestamptz default now(),
  p_limit integer default 500
)
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_inserted integer := 0;
begin
  if p_now is null then
    raise exception 'A scheduler timestamp is required.' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'p_limit must be between 1 and 5000.' using errcode = '22023';
  end if;

  with candidates as (
    select
      drp.user_id,
      timezone(drp.timezone, p_now)::date as local_date,
      (
        (
          timezone(drp.timezone, p_now)::date
          + drp.reminder_time
        ) at time zone drp.timezone
      ) as scheduled_for
    from public.daily_reminder_preferences drp
    join public.profiles p
      on p.user_id = drp.user_id
     and p.is_suspended = false
    join pg_catalog.pg_timezone_names tz
      on tz.name = drp.timezone
    where drp.daily_enabled = true
  ), due as (
    select c.*
    from candidates c
    where c.scheduled_for <= p_now
      and not exists (
        select 1
        from public.delivery_ledger dl
        where dl.kind = 'daily_reminder'
          and dl.user_id = c.user_id
          and dl.delivery_key = 'daily:' || c.local_date::text
      )
    order by c.scheduled_for, c.user_id
    limit p_limit
  ), inserted as (
    insert into public.delivery_ledger (
      user_id, kind, delivery_key, scheduled_for
    )
    select
      due.user_id,
      'daily_reminder',
      'daily:' || due.local_date::text,
      due.scheduled_for
    from due
    on conflict (kind, user_id, delivery_key) do nothing
    returning 1
  )
  select count(*)::integer into v_inserted from inserted;

  return v_inserted;
end;
$$;

revoke all privileges
on function public.enqueue_due_daily_reminders(timestamptz, integer)
from public, anon, authenticated;
grant execute
on function public.enqueue_due_daily_reminders(timestamptz, integer)
to service_role;

create or replace function public.enqueue_weekly_goodness_delivery(
  p_week_start date,
  p_scheduled_for timestamptz default now(),
  p_limit integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_inserted integer := 0;
begin
  if p_week_start is null
     or extract(isodow from p_week_start) <> 1 then
    raise exception 'p_week_start must be a Monday.' using errcode = '22023';
  end if;
  if p_scheduled_for is null then
    raise exception 'A scheduled timestamp is required.' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 10000 then
    raise exception 'p_limit must be between 1 and 10000.' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.weekly_goodness_features f
    where f.week_start = p_week_start
  ) then
    raise exception 'Weekly Goodness issue has not been explicitly curated.'
      using errcode = '22023';
  end if;

  with eligible as (
    select np.user_id
    from public.newsletter_preferences np
    join public.profiles p
      on p.user_id = np.user_id
     and p.is_suspended = false
    join auth.users u
      on u.id = np.user_id
     and u.email_confirmed_at is not null
     and nullif(btrim(u.email), '') is not null
    where np.weekly_enabled = true
      and np.consented_at is not null
      and not exists (
        select 1 from public.delivery_ledger dl
        where dl.kind = 'weekly_newsletter'
          and dl.user_id = np.user_id
          and dl.delivery_key = 'weekly:' || p_week_start::text
      )
    order by np.user_id
    limit p_limit
  ), inserted as (
    insert into public.delivery_ledger (
      user_id, kind, delivery_key, scheduled_for
    )
    select
      eligible.user_id,
      'weekly_newsletter',
      'weekly:' || p_week_start::text,
      p_scheduled_for
    from eligible
    on conflict (kind, user_id, delivery_key) do nothing
    returning 1
  )
  select count(*)::integer into v_inserted from inserted;

  return v_inserted;
end;
$$;

revoke all privileges
on function public.enqueue_weekly_goodness_delivery(date, timestamptz, integer)
from public, anon, authenticated;
grant execute
on function public.enqueue_weekly_goodness_delivery(date, timestamptz, integer)
to service_role;

-- This RPC is the final authority immediately before external transport.
-- Under READ COMMITTED, FOR SHARE conflicts with consent/suspension UPDATE;
-- a revocation committed first is observed after waiting for its row lock.
-- Once this transaction commits, a later revocation cannot recall in-flight IO.
create or replace function public.begin_delivery_transport(
  p_job_id uuid,
  p_claim_token uuid
)
returns timestamptz
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_job public.delivery_ledger%rowtype;
  v_started_at timestamptz;
  v_authorized boolean := false;
begin
  if p_job_id is null or p_claim_token is null then
    raise exception 'A job ID and claim token are required.' using errcode = '22023';
  end if;

  select * into v_job
  from public.delivery_ledger dl
  where dl.id = p_job_id
  for update;

  if not found
     or v_job.state <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token
     or v_job.claim_expires_at is null
     or v_job.claim_expires_at <= now() then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  if v_job.kind = 'daily_reminder' then
    perform 1
    from public.daily_reminder_preferences drp
    join public.profiles p
      on p.user_id = drp.user_id
     and p.is_suspended = false
    join pg_catalog.pg_timezone_names tz
      on tz.name = drp.timezone
    where drp.user_id = v_job.user_id
      and drp.daily_enabled = true
      and v_job.delivery_key =
        'daily:' || timezone(drp.timezone, v_job.scheduled_for)::date::text
      and v_job.scheduled_for = (
        (
          timezone(drp.timezone, v_job.scheduled_for)::date
          + drp.reminder_time
        ) at time zone drp.timezone
      )
    for share of drp, p;
    v_authorized := found;
  elsif v_job.kind = 'weekly_newsletter' then
    perform 1
    from public.newsletter_preferences np
    join public.profiles p
      on p.user_id = np.user_id
     and p.is_suspended = false
    join auth.users u
      on u.id = np.user_id
     and u.email_confirmed_at is not null
     and nullif(btrim(u.email), '') is not null
    join public.weekly_goodness_features f
      on v_job.delivery_key = 'weekly:' || f.week_start::text
    where np.user_id = v_job.user_id
      and np.weekly_enabled = true
      and np.consented_at is not null
    for share of np, p, u, f;
    v_authorized := found;
  else
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  if not v_authorized then
    update public.delivery_ledger
    set state = 'cancelled',
        cancelled_at = now(),
        claim_token = null,
        claim_expires_at = null,
        next_attempt_at = null,
        error_code = 'authorization_revoked',
        updated_at = now()
    where id = v_job.id;
    -- NULL is a deny decision. The worker must never call the provider.
    return null;
  end if;

  update public.delivery_ledger
  set transport_started_at = coalesce(transport_started_at, now()),
      updated_at = now()
  where id = v_job.id
  returning transport_started_at into v_started_at;

  return v_started_at;
end;
$$;

revoke all privileges
on function public.begin_delivery_transport(uuid, uuid)
from public, anon, authenticated;
grant execute
on function public.begin_delivery_transport(uuid, uuid)
to service_role;


-- An auditable, schema-local attestation of the reviewed 023 function contract.
-- Migration history alone is not evidence that these exact replacements ran.
comment on function public.enqueue_due_daily_reminders(timestamptz, integer)
  is 'deedlight:023:daily-exclusion-before-limit:v1';
comment on function public.enqueue_weekly_goodness_delivery(date, timestamptz, integer)
  is 'deedlight:023:weekly-exclusion-before-limit:v1';
comment on function public.begin_delivery_transport(uuid, uuid)
  is 'deedlight:023:locked-consent-before-transport:v1';

notify pgrst, 'reload schema';
commit;


-- Delivery recipient identity, actual lease clock, Weekly capacity (migration 024).
begin;
do $$
begin
  if to_regprocedure('public.begin_delivery_transport(uuid,uuid)') is null
    or to_regprocedure('public.enqueue_current_weekly_goodness_if_curated(timestamp with time zone,integer)') is null
    or to_regclass('public.delivery_ledger') is null
    or to_regclass('auth.users') is null then
    raise exception 'Migration 024 requires the reviewed delivery baseline through 023.';
  end if;
-- Fail closed unless migration 023's reviewed source-level contracts ran.
-- The markers are written by 023 itself, independent of CLI migration history.
  if coalesce(obj_description(
      to_regprocedure('public.enqueue_due_daily_reminders(timestamptz,integer)'), 'pg_proc'
    ), '') <> 'deedlight:023:daily-exclusion-before-limit:v1'
    or coalesce(obj_description(
      to_regprocedure('public.enqueue_weekly_goodness_delivery(date,timestamptz,integer)'), 'pg_proc'
    ), '') <> 'deedlight:023:weekly-exclusion-before-limit:v1'
    or coalesce(obj_description(
      to_regprocedure('public.begin_delivery_transport(uuid,uuid)'), 'pg_proc'
    ), '') <> 'deedlight:023:locked-consent-before-transport:v1'
    or coalesce((
      select md5(p.prosrc) from pg_catalog.pg_proc p
      where p.oid = to_regprocedure('public.enqueue_due_daily_reminders(timestamptz,integer)')
    ), '') <> 'ad0b49bdc5d6ea94bbc2a73fa40985ac'
    or coalesce((
      select md5(p.prosrc) from pg_catalog.pg_proc p
      where p.oid = to_regprocedure('public.enqueue_weekly_goodness_delivery(date,timestamptz,integer)')
    ), '') <> 'd13eed60e2cf6413d0dd3e0531f5cf77'
    or coalesce((
      select md5(p.prosrc) from pg_catalog.pg_proc p
      where p.oid = to_regprocedure('public.begin_delivery_transport(uuid,uuid)')
    ), '') <> 'a5f2ba15937ab66bbdd71d3e6d175c2d'
    or exists (
      select 1 from pg_catalog.pg_proc p
      where p.oid in (
        to_regprocedure('public.enqueue_due_daily_reminders(timestamptz,integer)'),
        to_regprocedure('public.enqueue_weekly_goodness_delivery(date,timestamptz,integer)'),
        to_regprocedure('public.begin_delivery_transport(uuid,uuid)')
      )
      and (
        not p.prosecdef
        or p.provolatile <> 'v'
        or not (coalesce(p.proconfig, array[]::text[])
                @> array['search_path=public, auth, pg_temp']::text[])
        or p.prolang <> (
          select l.oid from pg_catalog.pg_language l where l.lanname = 'plpgsql'
        )
      )
    )
  then
    raise exception 'Migration 024 requires reviewed migration 023 functions and attestation.'
      using errcode = '55000';
  end if;
  if to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') is not null then
    raise exception 'Migration 024 recipient-bound RPC is already present.';
  end if;
end;
$$;

-- Identity is compared against the currently confirmed Auth email, locked
-- with the consent/profile rows. The address is never persisted in the ledger.
create function public.begin_delivery_transport(
  p_job_id uuid,
  p_claim_token uuid,
  p_expected_email text
)
returns timestamptz
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_job public.delivery_ledger%rowtype;
  v_started_at timestamptz;
  v_authorized boolean := false;
begin
  if p_job_id is null or p_claim_token is null
    or p_expected_email is null
    or char_length(p_expected_email) > 320
    or nullif(btrim(p_expected_email), '') is null then
    raise exception 'Invalid delivery transport authorization arguments.'
      using errcode = '22023';
  end if;

  select * into v_job from public.delivery_ledger dl
  where dl.id = p_job_id for update;

  if not found or v_job.state <> 'claimed'
    or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null
    or v_job.claim_expires_at <= clock_timestamp() then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  if v_job.kind = 'daily_reminder' then
    perform 1 from public.daily_reminder_preferences drp
    join public.profiles p on p.user_id = drp.user_id and p.is_suspended = false
    join auth.users u on u.id = drp.user_id
      and u.email_confirmed_at is not null and btrim(u.email) = p_expected_email
    join pg_catalog.pg_timezone_names tz on tz.name = drp.timezone
    where drp.user_id = v_job.user_id
      and drp.daily_enabled = true
      and v_job.delivery_key =
        'daily:' || timezone(drp.timezone, v_job.scheduled_for)::date::text
      and v_job.scheduled_for = (
        (timezone(drp.timezone, v_job.scheduled_for)::date
          + drp.reminder_time) at time zone drp.timezone
      )
    for share of drp, p, u;
    v_authorized := found;
  elsif v_job.kind = 'weekly_newsletter' then
    perform 1 from public.newsletter_preferences np
    join public.profiles p on p.user_id = np.user_id and p.is_suspended = false
    join auth.users u on u.id = np.user_id
      and u.email_confirmed_at is not null and btrim(u.email) = p_expected_email
    join public.weekly_goodness_features f
      on v_job.delivery_key = 'weekly:' || f.week_start::text
    where np.user_id = v_job.user_id
      and np.weekly_enabled = true and np.consented_at is not null
    for share of np, p, u, f;
    v_authorized := found;
  else
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  -- now() is transaction-start time; lock waits must use actual wall clock.
  if v_job.claim_expires_at <= clock_timestamp() then
    raise exception 'Claim expired during transport authorization.'
      using errcode = '42501';
  end if;

  if not v_authorized then
    update public.delivery_ledger set
      state = 'cancelled', cancelled_at = clock_timestamp(),
      claim_token = null, claim_expires_at = null, next_attempt_at = null,
      error_code = 'authorization_revoked', updated_at = clock_timestamp()
    where id = v_job.id;
    return null;
  end if;

  update public.delivery_ledger set
    transport_started_at = coalesce(transport_started_at, clock_timestamp()),
    updated_at = clock_timestamp()
  where id = v_job.id and state = 'claimed'
    and claim_token = p_claim_token
    and claim_expires_at > clock_timestamp()
  returning transport_started_at into v_started_at;

  if not found then
    raise exception 'Claim expired during transport authorization.'
      using errcode = '42501';
  end if;
  return v_started_at;
end;
$$;

revoke all privileges on function public.begin_delivery_transport(uuid,uuid,text)
from public, anon, authenticated;
grant execute on function public.begin_delivery_transport(uuid,uuid,text)
to service_role;
-- Old two-argument entry point must not bypass identity authorization.
drop function public.begin_delivery_transport(uuid,uuid);

-- All weekly enqueue entry points share this per-issue advisory lock.
-- A distinct logical ledger row counts forever, regardless of state. The
-- serialized eligible cohort is sampled after acquiring the lock. Late opt-ins
-- are considered by the next invocation; at capacity they cause a visible
-- SQLSTATE 54000 error rather than a false successful completion.
create or replace function public.enqueue_weekly_goodness_delivery(
  p_week_start date,
  p_scheduled_for timestamptz default now(),
  p_limit integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_delivery_key text;
  v_existing integer;
  v_room integer;
  v_candidates uuid[];
  v_candidate_count integer;
  v_inserted integer;
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Weekly scheduling requires READ COMMITTED isolation.'
      using errcode = '25000';
  end if;
  if p_week_start is null or extract(isodow from p_week_start) <> 1
     or p_scheduled_for is null then
    raise exception 'A curated Monday and timestamp are required.'
      using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'Weekly batch limit must be between 1 and 5000.'
      using errcode = '22023';
  end if;
  v_delivery_key := 'weekly:' || p_week_start::text;

  -- Transaction-scoped lock serializes direct and wrapper service-role RPCs.
  perform pg_catalog.pg_advisory_xact_lock(
    20261112, p_week_start - date '2000-01-01'
  );
  if not exists (
    select 1 from public.weekly_goodness_features f
    where f.week_start = p_week_start
  ) then
    raise exception 'Weekly Goodness issue has not been explicitly curated.'
      using errcode = '22023';
  end if;

  select count(*)::integer into v_existing
  from public.delivery_ledger dl
  where dl.kind = 'weekly_newsletter' and dl.delivery_key = v_delivery_key;

  if v_existing > 5000 then
    raise exception 'Weekly issue already exceeds the 5000-delivery ceiling.'
      using errcode = '54000', detail = 'deedlight:weekly-issue-capacity:v1';
  end if;
  v_room := least(5000 - v_existing, p_limit);

  -- Selection is a single SQL statement/snapshot under the issue lock.
  -- Never silently enqueue only the first p_limit members.
  select coalesce(array_agg(c.user_id order by c.user_id), array[]::uuid[])
    into v_candidates
  from (
    select np.user_id
    from public.newsletter_preferences np
    join public.profiles p
      on p.user_id = np.user_id and p.is_suspended = false
    join auth.users u
      on u.id = np.user_id
     and u.email_confirmed_at is not null
     and nullif(btrim(u.email), '') is not null
    where np.weekly_enabled = true
      and np.consented_at is not null
      and not exists (
        select 1 from public.delivery_ledger dl
        where dl.kind = 'weekly_newsletter'
          and dl.user_id = np.user_id
          and dl.delivery_key = v_delivery_key
      )
    order by np.user_id
    limit v_room + 1
  ) c;

  v_candidate_count := cardinality(v_candidates);
  if v_candidate_count > v_room then
    raise exception 'Weekly delivery capacity exceeded; no jobs enqueued.'
      using errcode = '54000', detail = 'deedlight:weekly-issue-capacity:v1';
  end if;
  if v_candidate_count = 0 then
    return 0;
  end if;

  insert into public.delivery_ledger (
    user_id, kind, delivery_key, scheduled_for
  )
  select candidate.user_id, 'weekly_newsletter', v_delivery_key, p_scheduled_for
  from unnest(v_candidates) as candidate(user_id)
  on conflict (kind, user_id, delivery_key) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted <> v_candidate_count then
    raise exception 'Concurrent weekly ledger write detected; transaction rolled back.'
      using errcode = '40001';
  end if;
  return v_inserted;
end;
$$;

revoke all privileges
on function public.enqueue_weekly_goodness_delivery(date,timestamptz,integer)
from public, anon, authenticated;
grant execute
on function public.enqueue_weekly_goodness_delivery(date,timestamptz,integer)
to service_role;

-- The public scheduler entry point delegates to the same serialized capacity
-- policy. An uncurated issue is a harmless no-op; an over-capacity issue fails.
create or replace function public.enqueue_current_weekly_goodness_if_curated(
  p_now timestamptz default now(),
  p_limit integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_week_start date;
begin
  if p_now is null then
    raise exception 'A scheduler timestamp is required.' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'Weekly batch limit must be between 1 and 5000.'
      using errcode = '22023';
  end if;
  v_week_start := timezone('UTC', p_now)::date
    - (extract(isodow from timezone('UTC', p_now))::integer - 1);

  if not exists (
    select 1 from public.weekly_goodness_features f
    where f.week_start = v_week_start
  ) then
    return 0;
  end if;

  return public.enqueue_weekly_goodness_delivery(
    v_week_start, p_now, p_limit
  );
end;
$$;

revoke all privileges
on function public.enqueue_current_weekly_goodness_if_curated(timestamptz,integer)
from public, anon, authenticated;
grant execute
on function public.enqueue_current_weekly_goodness_if_curated(timestamptz,integer)
to service_role;

notify pgrst, 'reload schema';
commit;

-- Resend bounce/complaint intake, replay suppression and transport gate.
-- Migration 025 is additive and does not activate outbound delivery.

begin;

do $$
begin
  if to_regclass('public.delivery_ledger') is null
    or to_regclass('auth.users') is null
    or to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') is null
    or to_regprocedure('public.enqueue_due_daily_reminders(timestamp with time zone,integer)') is null
    or to_regprocedure('public.enqueue_weekly_goodness_delivery(date,timestamp with time zone,integer)') is null then
    raise exception 'Migration 025 requires the reviewed delivery baseline through 024.';
  end if;
end;
$$;

create table public.delivery_provider_events (
  event_id text primary key
    check (char_length(event_id) between 1 and 255),
  event_type text not null
    check (event_type in ('email.bounced', 'email.complained', 'email.suppressed')),
  provider_email_id text not null
    check (char_length(provider_email_id) between 1 and 255),
  recipient_email text not null
    check (
      char_length(recipient_email) between 3 and 320
      and recipient_email = lower(btrim(recipient_email))
      and recipient_email !~ '[[:space:][:cntrl:]]'
      and position('@' in recipient_email) > 1
    ),
  bounce_type text
    check (bounce_type is null or bounce_type in ('Permanent', 'Transient', 'Unknown')),
  received_at timestamptz not null default clock_timestamp(),
  constraint delivery_provider_events_bounce_event_type_check
    check (
      (event_type = 'email.bounced' and bounce_type is not null)
      or (event_type <> 'email.bounced' and bounce_type is null)
    )
);

create index delivery_provider_events_email_id_idx
  on public.delivery_provider_events (provider_email_id);

create table public.delivery_provider_suppressions (
  recipient_email text primary key
    check (
      char_length(recipient_email) between 3 and 320
      and recipient_email = lower(btrim(recipient_email))
    ),
  reason text not null
    check (reason in ('permanent_bounce', 'complaint', 'provider_suppressed')),
  provider_event_id text not null
    references public.delivery_provider_events(event_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

alter table public.delivery_provider_events enable row level security;
alter table public.delivery_provider_suppressions enable row level security;

-- Even service_role uses the narrow RPC; raw recipient addresses stay private.
revoke all privileges on table public.delivery_provider_events
  from public, anon, authenticated, service_role;
revoke all privileges on table public.delivery_provider_suppressions
  from public, anon, authenticated, service_role;

create or replace function public.record_delivery_provider_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_bounce_type text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_email text;
  v_reason text;
  v_inserted integer;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_type is null
    or p_event_type not in ('email.bounced', 'email.complained', 'email.suppressed')
    or p_provider_email_id is null
    or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320 then
    raise exception 'Invalid delivery provider event.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid delivery provider recipient.' using errcode = '22023';
  end if;

  if p_event_type = 'email.bounced' then
    if p_bounce_type is null or p_bounce_type not in ('Permanent', 'Transient', 'Unknown') then
      raise exception 'Invalid delivery bounce classification.' using errcode = '22023';
    end if;
    if p_bounce_type <> 'Transient' then
      v_reason := 'permanent_bounce';
    end if;
  elsif p_bounce_type is not null then
    raise exception 'Bounce classification is only valid for bounced events.' using errcode = '22023';
  elsif p_event_type = 'email.complained' then
    v_reason := 'complaint';
  else
    v_reason := 'provider_suppressed';
  end if;

  -- Serialize the final transport authorization against provider suppression.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));

  insert into public.delivery_provider_events (
    event_id, event_type, provider_email_id, recipient_email, bounce_type
  ) values (
    p_event_id, p_event_type, p_provider_email_id, v_email, p_bounce_type
  )
  on conflict (event_id) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    return false;
  end if;

  if v_reason is not null then
    insert into public.delivery_provider_suppressions (
      recipient_email, reason, provider_event_id
    ) values (
      v_email, v_reason, p_event_id
    )
    on conflict (recipient_email) do update set
      reason = case
        when delivery_provider_suppressions.reason = 'complaint' then 'complaint'
        when excluded.reason = 'complaint' then 'complaint'
        when delivery_provider_suppressions.reason = 'permanent_bounce' then 'permanent_bounce'
        when excluded.reason = 'permanent_bounce' then 'permanent_bounce'
        else 'provider_suppressed'
      end,
      provider_event_id = case
        when delivery_provider_suppressions.reason = 'complaint'
          then delivery_provider_suppressions.provider_event_id
        when excluded.reason = 'complaint' then excluded.provider_event_id
        when delivery_provider_suppressions.reason = 'permanent_bounce'
          then delivery_provider_suppressions.provider_event_id
        when excluded.reason = 'permanent_bounce' then excluded.provider_event_id
        else excluded.provider_event_id
      end,
      updated_at = clock_timestamp();
  end if;

  return true;
end;
$$;

revoke all privileges
on function public.record_delivery_provider_event(text, text, text, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_event(text, text, text, text, text)
to service_role;

-- Exclude suppressed addresses before the batch limit so they cannot starve
-- eligible recipients or create a new logical job every day.
create or replace function public.enqueue_due_daily_reminders(
  p_now timestamptz default now(),
  p_limit integer default 500
)
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_inserted integer := 0;
begin
  if p_now is null then
    raise exception 'A scheduler timestamp is required.' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'p_limit must be between 1 and 5000.' using errcode = '22023';
  end if;

  with candidates as (
    select
      drp.user_id,
      timezone(drp.timezone, p_now)::date as local_date,
      (
        (timezone(drp.timezone, p_now)::date + drp.reminder_time)
        at time zone drp.timezone
      ) as scheduled_for
    from public.daily_reminder_preferences drp
    join public.profiles p
      on p.user_id = drp.user_id and p.is_suspended = false
    join auth.users u
      on u.id = drp.user_id
     and u.email_confirmed_at is not null
     and nullif(btrim(u.email), '') is not null
    join pg_catalog.pg_timezone_names tz
      on tz.name = drp.timezone
    where drp.daily_enabled = true
      and not exists (
        select 1 from public.delivery_provider_suppressions s
        where s.recipient_email = lower(btrim(u.email))
      )
  ), due as (
    select c.*
    from candidates c
    where c.scheduled_for <= p_now
      and not exists (
        select 1 from public.delivery_ledger dl
        where dl.kind = 'daily_reminder'
          and dl.user_id = c.user_id
          and dl.delivery_key = 'daily:' || c.local_date::text
      )
    order by c.scheduled_for, c.user_id
    limit p_limit
  ), inserted as (
    insert into public.delivery_ledger (
      user_id, kind, delivery_key, scheduled_for
    )
    select
      due.user_id,
      'daily_reminder',
      'daily:' || due.local_date::text,
      due.scheduled_for
    from due
    on conflict (kind, user_id, delivery_key) do nothing
    returning 1
  )
  select count(*)::integer into v_inserted from inserted;

  return v_inserted;
end;
$$;

revoke all privileges
on function public.enqueue_due_daily_reminders(timestamptz, integer)
from public, anon, authenticated;
grant execute
on function public.enqueue_due_daily_reminders(timestamptz, integer)
to service_role;

-- Preserve the issue-wide 5,000-row cap and serialization from migration 024.
create or replace function public.enqueue_weekly_goodness_delivery(
  p_week_start date,
  p_scheduled_for timestamptz default now(),
  p_limit integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_delivery_key text;
  v_existing integer;
  v_room integer;
  v_candidates uuid[];
  v_candidate_count integer;
  v_inserted integer;
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Weekly scheduling requires READ COMMITTED isolation.'
      using errcode = '25000';
  end if;
  if p_week_start is null or extract(isodow from p_week_start) <> 1
    or p_scheduled_for is null then
    raise exception 'A curated Monday and timestamp are required.' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'Weekly batch limit must be between 1 and 5000.' using errcode = '22023';
  end if;

  v_delivery_key := 'weekly:' || p_week_start::text;
  perform pg_catalog.pg_advisory_xact_lock(
    20261112, p_week_start - date '2000-01-01'
  );

  if not exists (
    select 1 from public.weekly_goodness_features f
    where f.week_start = p_week_start
  ) then
    raise exception 'Weekly Goodness issue has not been explicitly curated.'
      using errcode = '22023';
  end if;

  select count(*)::integer into v_existing
  from public.delivery_ledger dl
  where dl.kind = 'weekly_newsletter' and dl.delivery_key = v_delivery_key;

  if v_existing > 5000 then
    raise exception 'Weekly issue already exceeds the 5000-delivery ceiling.'
      using errcode = '54000', detail = 'deedlight:weekly-issue-capacity:v1';
  end if;
  v_room := least(5000 - v_existing, p_limit);

  select coalesce(array_agg(c.user_id order by c.user_id), array[]::uuid[])
    into v_candidates
  from (
    select np.user_id
    from public.newsletter_preferences np
    join public.profiles p
      on p.user_id = np.user_id and p.is_suspended = false
    join auth.users u
      on u.id = np.user_id
     and u.email_confirmed_at is not null
     and nullif(btrim(u.email), '') is not null
    where np.weekly_enabled = true
      and np.consented_at is not null
      and not exists (
        select 1 from public.delivery_provider_suppressions s
        where s.recipient_email = lower(btrim(u.email))
      )
      and not exists (
        select 1 from public.delivery_ledger dl
        where dl.kind = 'weekly_newsletter'
          and dl.user_id = np.user_id
          and dl.delivery_key = v_delivery_key
      )
    order by np.user_id
    limit v_room + 1
  ) c;

  v_candidate_count := cardinality(v_candidates);
  if v_candidate_count > v_room then
    raise exception 'Weekly delivery capacity exceeded; no jobs enqueued.'
      using errcode = '54000', detail = 'deedlight:weekly-issue-capacity:v1';
  end if;
  if v_candidate_count = 0 then return 0; end if;

  insert into public.delivery_ledger (
    user_id, kind, delivery_key, scheduled_for
  )
  select candidate.user_id, 'weekly_newsletter', v_delivery_key, p_scheduled_for
  from unnest(v_candidates) as candidate(user_id)
  on conflict (kind, user_id, delivery_key) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted <> v_candidate_count then
    raise exception 'Concurrent weekly ledger write detected; transaction rolled back.'
      using errcode = '40001';
  end if;
  return v_inserted;
end;
$$;

revoke all privileges
on function public.enqueue_weekly_goodness_delivery(date, timestamptz, integer)
from public, anon, authenticated;
grant execute
on function public.enqueue_weekly_goodness_delivery(date, timestamptz, integer)
to service_role;

-- This final authorization gate serializes against a bounce/complaint event.
-- If the provider event wins the per-address lock, no external send starts.
create or replace function public.begin_delivery_transport(
  p_job_id uuid,
  p_claim_token uuid,
  p_expected_email text
)
returns timestamptz
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_job public.delivery_ledger%rowtype;
  v_started_at timestamptz;
  v_authorized boolean := false;
  v_email text;
begin
  if p_job_id is null or p_claim_token is null
    or p_expected_email is null
    or char_length(p_expected_email) > 320
    or nullif(btrim(p_expected_email), '') is null then
    raise exception 'Invalid delivery transport authorization arguments.'
      using errcode = '22023';
  end if;

  v_email := lower(btrim(p_expected_email));

  select * into v_job from public.delivery_ledger dl
  where dl.id = p_job_id for update;

  if not found or v_job.state <> 'claimed'
    or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null
    or v_job.claim_expires_at <= clock_timestamp() then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  -- The webhook RPC takes this same lock before inserting a suppression.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));

  if v_job.kind = 'daily_reminder' then
    perform 1 from public.daily_reminder_preferences drp
    join public.profiles p
      on p.user_id = drp.user_id and p.is_suspended = false
    join auth.users u
      on u.id = drp.user_id
     and u.email_confirmed_at is not null
     and lower(btrim(u.email)) = v_email
    join pg_catalog.pg_timezone_names tz
      on tz.name = drp.timezone
    where drp.user_id = v_job.user_id
      and drp.daily_enabled = true
      and v_job.delivery_key =
        'daily:' || timezone(drp.timezone, v_job.scheduled_for)::date::text
      and v_job.scheduled_for = (
        (timezone(drp.timezone, v_job.scheduled_for)::date
          + drp.reminder_time) at time zone drp.timezone
      )
      and not exists (
        select 1 from public.delivery_provider_suppressions s
        where s.recipient_email = v_email
      )
    for share of drp, p, u;
    v_authorized := found;
  elsif v_job.kind = 'weekly_newsletter' then
    perform 1 from public.newsletter_preferences np
    join public.profiles p
      on p.user_id = np.user_id and p.is_suspended = false
    join auth.users u
      on u.id = np.user_id
     and u.email_confirmed_at is not null
     and lower(btrim(u.email)) = v_email
    join public.weekly_goodness_features f
      on v_job.delivery_key = 'weekly:' || f.week_start::text
    where np.user_id = v_job.user_id
      and np.weekly_enabled = true
      and np.consented_at is not null
      and not exists (
        select 1 from public.delivery_provider_suppressions s
        where s.recipient_email = v_email
      )
    for share of np, p, u, f;
    v_authorized := found;
  else
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  if v_job.claim_expires_at <= clock_timestamp() then
    raise exception 'Claim expired during transport authorization.' using errcode = '42501';
  end if;

  if not v_authorized then
    update public.delivery_ledger set
      state = 'cancelled',
      cancelled_at = clock_timestamp(),
      claim_token = null,
      claim_expires_at = null,
      next_attempt_at = null,
      error_code = 'authorization_revoked',
      updated_at = clock_timestamp()
    where id = v_job.id;
    return null;
  end if;

  update public.delivery_ledger set
    transport_started_at = coalesce(transport_started_at, clock_timestamp()),
    updated_at = clock_timestamp()
  where id = v_job.id
    and state = 'claimed'
    and claim_token = p_claim_token
    and claim_expires_at > clock_timestamp()
  returning transport_started_at into v_started_at;

  if not found then
    raise exception 'Claim expired during transport authorization.' using errcode = '42501';
  end if;
  return v_started_at;
end;
$$;

revoke all privileges
on function public.begin_delivery_transport(uuid, uuid, text)
from public, anon, authenticated;
grant execute
on function public.begin_delivery_transport(uuid, uuid, text)
to service_role;

comment on function public.begin_delivery_transport(uuid, uuid, text)
  is 'deedlight:025:provider-suppression-before-transport:v1';

notify pgrst, 'reload schema';
commit;

-- Provider lifecycle observability. This migration is additive; migration 025 is immutable.
begin;

do $$
begin
  if to_regclass('public.delivery_provider_events') is null
    or to_regprocedure('public.record_delivery_provider_event(text,text,text,text,text)') is null then
    raise exception 'Migration 026 requires the reviewed provider webhook baseline from migration 025.';
  end if;
end;
$$;

alter table public.delivery_provider_events
  add column provider_created_at timestamptz,
  add column failure_class text;

alter table public.delivery_provider_events
  drop constraint delivery_provider_events_event_type_check;

alter table public.delivery_provider_events
  add constraint delivery_provider_events_event_type_check
  check (event_type in (
    'email.sent',
    'email.delivered',
    'email.delivery_delayed',
    'email.bounced',
    'email.complained',
    'email.suppressed',
    'email.failed'
  )),
  add constraint delivery_provider_events_provider_created_at_check
  check (
    provider_created_at is not null
    or event_type in ('email.bounced', 'email.complained', 'email.suppressed')
  ),
  add constraint delivery_provider_events_failure_class_check
  check (
    (event_type = 'email.failed' and failure_class in (
      'invalid_recipient',
      'provider_authentication',
      'domain_verification',
      'quota_exceeded',
      'content_rejected',
      'unknown'
    ))
    or (event_type <> 'email.failed' and failure_class is null)
  );

create table public.delivery_provider_lifecycle (
  provider_email_id text primary key
    check (char_length(provider_email_id) between 1 and 255),
  status text not null
    check (status in (
      'email.sent',
      'email.delivered',
      'email.delivery_delayed',
      'email.bounced',
      'email.complained',
      'email.suppressed',
      'email.failed'
    )),
  status_rank smallint not null,
  provider_created_at timestamptz not null,
  received_at timestamptz not null,
  event_id text not null unique
    references public.delivery_provider_events(event_id) on delete restrict,
  failure_class text
    check (failure_class is null or failure_class in (
      'invalid_recipient',
      'provider_authentication',
      'domain_verification',
      'quota_exceeded',
      'content_rejected',
      'unknown'
    )),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint delivery_provider_lifecycle_status_rank_check
    check (status_rank = case status
      when 'email.sent' then 10
      when 'email.delivery_delayed' then 20
      when 'email.failed' then 30
      when 'email.bounced' then 40
      when 'email.suppressed' then 50
      when 'email.delivered' then 60
      when 'email.complained' then 70
      else 0
    end),
  constraint delivery_provider_lifecycle_failure_status_check
    check (
      (status = 'email.failed' and failure_class is not null)
      or (status <> 'email.failed' and failure_class is null)
    )
);

create index delivery_provider_lifecycle_status_idx
  on public.delivery_provider_lifecycle (status, provider_created_at desc);

alter table public.delivery_provider_lifecycle enable row level security;

revoke all privileges on table public.delivery_provider_lifecycle
  from public, anon, authenticated, service_role;

create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text default null,
  p_failure_class text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_email text;
  v_reason text;
  v_status_rank smallint;
  v_inserted integer;
  v_received_at timestamptz;
  v_lifecycle_rows integer;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_type is null
    or p_event_type not in (
      'email.sent',
      'email.delivered',
      'email.delivery_delayed',
      'email.bounced',
      'email.complained',
      'email.suppressed',
      'email.failed'
    )
    or p_provider_email_id is null
    or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320
    or p_provider_created_at is null then
    raise exception 'Invalid delivery provider lifecycle event.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid delivery provider recipient.' using errcode = '22023';
  end if;

  if p_event_type = 'email.bounced' then
    if p_bounce_type is null or p_bounce_type not in ('Permanent', 'Transient', 'Unknown') then
      raise exception 'Invalid delivery bounce classification.' using errcode = '22023';
    end if;
    if p_bounce_type <> 'Transient' then
      v_reason := 'permanent_bounce';
    end if;
  elsif p_bounce_type is not null then
    raise exception 'Bounce classification is only valid for bounced events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.failed' then
    if p_failure_class is null or p_failure_class not in (
      'invalid_recipient',
      'provider_authentication',
      'domain_verification',
      'quota_exceeded',
      'content_rejected',
      'unknown'
    ) then
      raise exception 'Invalid normalized provider failure classification.' using errcode = '22023';
    end if;
  elsif p_failure_class is not null then
    raise exception 'Failure classification is only valid for failed events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.complained' then
    v_reason := 'complaint';
  elsif p_event_type = 'email.suppressed' then
    v_reason := 'provider_suppressed';
  end if;

  v_status_rank := case p_event_type
    when 'email.sent' then 10
    when 'email.delivery_delayed' then 20
    when 'email.failed' then 30
    when 'email.bounced' then 40
    when 'email.suppressed' then 50
    when 'email.delivered' then 60
    when 'email.complained' then 70
    else 0
  end;

  -- Keep the existing suppression/transport serialization point and also
  -- serialize provider-ID-to-recipient correlation without exposing it.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, hashtext(p_provider_email_id));

  if exists (
    select 1
    from public.delivery_provider_events e
    where e.provider_email_id = p_provider_email_id
      and e.recipient_email <> v_email
  ) then
    raise exception 'Provider email correlation does not match.' using errcode = '22023';
  end if;

  insert into public.delivery_provider_events (
    event_id,
    event_type,
    provider_email_id,
    recipient_email,
    bounce_type,
    provider_created_at,
    failure_class
  ) values (
    p_event_id,
    p_event_type,
    p_provider_email_id,
    v_email,
    p_bounce_type,
    p_provider_created_at,
    p_failure_class
  )
  on conflict (event_id) do nothing
  returning received_at into v_received_at;

  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    return false;
  end if;

  if v_reason is not null then
    insert into public.delivery_provider_suppressions (
      recipient_email, reason, provider_event_id
    ) values (
      v_email, v_reason, p_event_id
    )
    on conflict (recipient_email) do update set
      reason = case
        when delivery_provider_suppressions.reason = 'complaint' then 'complaint'
        when excluded.reason = 'complaint' then 'complaint'
        when delivery_provider_suppressions.reason = 'permanent_bounce' then 'permanent_bounce'
        when excluded.reason = 'permanent_bounce' then 'permanent_bounce'
        else 'provider_suppressed'
      end,
      provider_event_id = case
        when delivery_provider_suppressions.reason = 'complaint'
          then delivery_provider_suppressions.provider_event_id
        when excluded.reason = 'complaint' then excluded.provider_event_id
        when delivery_provider_suppressions.reason = 'permanent_bounce'
          then delivery_provider_suppressions.provider_event_id
        when excluded.reason = 'permanent_bounce' then excluded.provider_event_id
        else excluded.provider_event_id
      end,
      updated_at = clock_timestamp();
  end if;

  -- Evidence rank is monotonic: late sent/delayed/failed events cannot replace
  -- delivered or complaint evidence. Equal-rank events use provider time,
  -- then event ID, as a deterministic tie-break independent of arrival order.
  insert into public.delivery_provider_lifecycle (
    provider_email_id,
    status,
    status_rank,
    provider_created_at,
    received_at,
    event_id,
    failure_class
  ) values (
    p_provider_email_id,
    p_event_type,
    v_status_rank,
    p_provider_created_at,
    v_received_at,
    p_event_id,
    p_failure_class
  )
  on conflict (provider_email_id) do update set
    status = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.status
      else delivery_provider_lifecycle.status
    end,
    status_rank = greatest(
      delivery_provider_lifecycle.status_rank,
      excluded.status_rank
    ),
    provider_created_at = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.provider_created_at
      else delivery_provider_lifecycle.provider_created_at
    end,
    received_at = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.received_at
      else delivery_provider_lifecycle.received_at
    end,
    event_id = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.event_id
      else delivery_provider_lifecycle.event_id
    end,
    failure_class = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.failure_class
      else delivery_provider_lifecycle.failure_class
    end,
    updated_at = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then clock_timestamp()
      else delivery_provider_lifecycle.updated_at
    end;

  get diagnostics v_lifecycle_rows = row_count;
  if v_lifecycle_rows <> 1 then
    raise exception 'Provider lifecycle persistence failed.' using errcode = '23505';
  end if;

  return true;
end;
$$;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)
to service_role;

comment on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)
  is 'deedlight:026:provider-lifecycle-idempotent-monotonic:v1';


-- Preserve the legacy suppression RPC contract while routing it through the
-- same provider-ID lock and lifecycle projection. Legacy callers have no
-- provider timestamp, so receipt time is the only safe timestamp available.
create or replace function public.record_delivery_provider_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_bounce_type text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $legacy$
begin
  if p_event_type not in ('email.bounced', 'email.complained', 'email.suppressed') then
    raise exception 'Unsupported legacy provider event type.' using errcode = '22023';
  end if;

  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    clock_timestamp(),
    p_bounce_type,
    null
  );
end;
$legacy$;

revoke all privileges
on function public.record_delivery_provider_event(text, text, text, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_event(text, text, text, text, text)
to service_role;

notify pgrst, 'reload schema';
commit;

-- Migration 027: provider event idempotency and lifecycle integrity.
-- Fail-closed provider event idempotency and lifecycle integrity.
-- Migration 025 remains immutable; all changes are additive.
begin;

alter table public.delivery_provider_events
  add column suppression_reason text,
  add column payload_fingerprint text,
  add constraint delivery_provider_events_suppression_reason_check
  check (
    (event_type = 'email.suppressed'
      and (suppression_reason is null or suppression_reason in (
        'previous_bounce',
        'previous_complaint',
        'provider_suppressed'
      )))
    or (event_type <> 'email.suppressed' and suppression_reason is null)
  ),
  add constraint delivery_provider_events_payload_fingerprint_check
  check (payload_fingerprint is null or payload_fingerprint ~ '^[0-9a-f]{64}$');

alter table public.delivery_provider_lifecycle
  drop constraint delivery_provider_lifecycle_status_check;

alter table public.delivery_provider_lifecycle
  add constraint delivery_provider_lifecycle_status_check
  check (status in (
    'email.sent',
    'email.delivered',
    'email.delivery_delayed',
    'email.bounced',
    'email.complained',
    'email.suppressed',
    'email.failed',
    'integrity_anomaly'
  ));

alter table public.delivery_provider_lifecycle
  drop constraint delivery_provider_lifecycle_status_rank_check;

alter table public.delivery_provider_lifecycle
  add constraint delivery_provider_lifecycle_status_rank_check
  check (status_rank = case status
    when 'email.sent' then 10
    when 'email.delivery_delayed' then 20
    when 'email.failed' then 30
    when 'email.bounced' then 40
    when 'email.suppressed' then 50
    when 'email.delivered' then 60
    when 'email.complained' then 70
    when 'integrity_anomaly' then 80
    else 0
  end);

create table public.delivery_provider_integrity_anomalies (
  event_id text not null
    references public.delivery_provider_events(event_id) on delete restrict,
  related_event_id text
    references public.delivery_provider_events(event_id) on delete restrict,
  anomaly_type text not null
    check (anomaly_type in (
      'duplicate_event_id_conflict',
      'contradictory_terminal_outcome'
    )),
  detected_at timestamptz not null default clock_timestamp(),
  constraint delivery_provider_integrity_anomalies_related_event_check
    check (related_event_id is null or related_event_id <> event_id)
);

create unique index delivery_provider_integrity_anomalies_dedupe_idx
  on public.delivery_provider_integrity_anomalies (
    event_id,
    anomaly_type,
    (coalesce(related_event_id, ''))
  );

alter table public.delivery_provider_integrity_anomalies enable row level security;

revoke all privileges on table public.delivery_provider_integrity_anomalies
  from public, anon, authenticated, service_role;

comment on table public.delivery_provider_integrity_anomalies
  is 'Private append-only integrity markers; contains no recipient or raw provider diagnostics.';

comment on column public.delivery_provider_events.suppression_reason
  is 'Normalized Resend data.suppressed.reason; null for historical or non-suppression events.';

comment on column public.delivery_provider_events.payload_fingerprint
  is 'SHA-256 of the signed raw webhook body; never stores the raw payload or provider diagnostics.';

create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text,
  p_failure_class text,
  p_suppression_reason text,
  p_payload_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_email text;
  v_reason text;
  v_status_rank smallint;
  v_inserted integer;
  v_received_at timestamptz;
  v_lifecycle_rows integer;
  v_existing public.delivery_provider_events%rowtype;
  v_conflicting_event_id text;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_type is null
    or p_event_type not in (
      'email.sent',
      'email.delivered',
      'email.delivery_delayed',
      'email.bounced',
      'email.complained',
      'email.suppressed',
      'email.failed'
    )
    or p_provider_email_id is null
    or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320
    or p_provider_created_at is null
    or (p_payload_fingerprint is not null
      and p_payload_fingerprint !~ '^[0-9a-f]{64}$') then
    raise exception 'Invalid delivery provider lifecycle event.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid delivery provider recipient.' using errcode = '22023';
  end if;

  if p_event_type = 'email.bounced' then
    if p_bounce_type is null or p_bounce_type not in ('Permanent', 'Transient', 'Unknown') then
      raise exception 'Invalid delivery bounce classification.' using errcode = '22023';
    end if;
    if p_bounce_type <> 'Transient' then
      v_reason := 'permanent_bounce';
    end if;
  elsif p_bounce_type is not null then
    raise exception 'Bounce classification is only valid for bounced events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.failed' then
    if p_failure_class is null or p_failure_class not in (
      'invalid_recipient',
      'provider_authentication',
      'domain_verification',
      'quota_exceeded',
      'content_rejected',
      'unknown'
    ) then
      raise exception 'Invalid normalized provider failure classification.' using errcode = '22023';
    end if;
  elsif p_failure_class is not null then
    raise exception 'Failure classification is only valid for failed events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.suppressed' then
    if p_suppression_reason is null or p_suppression_reason not in (
      'previous_bounce',
      'previous_complaint',
      'provider_suppressed'
    ) then
      raise exception 'Invalid normalized provider suppression reason.' using errcode = '22023';
    end if;
    v_reason := case p_suppression_reason
      when 'previous_complaint' then 'complaint'
      when 'previous_bounce' then 'permanent_bounce'
      else 'provider_suppressed'
    end;
  elsif p_suppression_reason is not null then
    raise exception 'Suppression reason is only valid for suppressed events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.complained' then
    v_reason := 'complaint';
  end if;

  v_status_rank := case p_event_type
    when 'email.sent' then 10
    when 'email.delivery_delayed' then 20
    when 'email.failed' then 30
    when 'email.bounced' then 40
    when 'email.suppressed' then 50
    when 'email.delivered' then 60
    when 'email.complained' then 70
    else 0
  end;

  -- Preserve the shared address lock and provider-ID correlation lock.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, hashtext(p_provider_email_id));

  insert into public.delivery_provider_events (
    event_id,
    event_type,
    provider_email_id,
    recipient_email,
    bounce_type,
    provider_created_at,
    failure_class,
    suppression_reason,
    payload_fingerprint
  ) values (
    p_event_id,
    p_event_type,
    p_provider_email_id,
    v_email,
    p_bounce_type,
    p_provider_created_at,
    p_failure_class,
    p_suppression_reason,
    p_payload_fingerprint
  )
  on conflict (event_id) do nothing
  returning received_at into v_received_at;

  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    select e.* into v_existing
    from public.delivery_provider_events e
    where e.event_id = p_event_id
    for update;

    if not found then
      raise exception 'Conflicting provider event could not be inspected.' using errcode = 'XX000';
    end if;

    if v_existing.event_type = p_event_type
      and v_existing.provider_email_id = p_provider_email_id
      and v_existing.recipient_email = v_email
      and v_existing.bounce_type is not distinct from p_bounce_type
      and (v_existing.provider_created_at is null
        or v_existing.provider_created_at = p_provider_created_at)
      and v_existing.failure_class is not distinct from p_failure_class
      -- Historical suppression metadata and legacy callers may lack a reason.
      -- Fingerprints are stricter below: stored digests require exact non-NULL replay input.
      and (
        v_existing.suppression_reason is null
        or p_suppression_reason is null
        or v_existing.suppression_reason = p_suppression_reason
      )
      and (
        -- Only genuinely historical rows without a stored digest are compatible.
        -- Fingerprinted rows require an exact, non-NULL digest on every replay.
        v_existing.payload_fingerprint is null
        or (p_payload_fingerprint is not null
          and v_existing.payload_fingerprint = p_payload_fingerprint)
      ) then
      return false;
    end if;

    insert into public.delivery_provider_integrity_anomalies (
      event_id, related_event_id, anomaly_type
    ) values (
      v_existing.event_id, null, 'duplicate_event_id_conflict'
    )
    on conflict do nothing;

    update public.delivery_provider_lifecycle
    set status = 'integrity_anomaly',
        status_rank = 80,
        failure_class = null,
        updated_at = clock_timestamp()
    where provider_email_id = v_existing.provider_email_id;

    return null;
  end if;

  if exists (
    select 1
    from public.delivery_provider_events e
    where e.provider_email_id = p_provider_email_id
      and e.recipient_email <> v_email
  ) then
    raise exception 'Provider email correlation does not match.' using errcode = '22023';
  end if;

  if v_reason is not null then
    insert into public.delivery_provider_suppressions (
      recipient_email, reason, provider_event_id
    ) values (
      v_email, v_reason, p_event_id
    )
    on conflict (recipient_email) do update set
      reason = case
        when delivery_provider_suppressions.reason = 'complaint' then 'complaint'
        when excluded.reason = 'complaint' then 'complaint'
        when delivery_provider_suppressions.reason = 'permanent_bounce' then 'permanent_bounce'
        when excluded.reason = 'permanent_bounce' then 'permanent_bounce'
        else 'provider_suppressed'
      end,
      provider_event_id = case
        when delivery_provider_suppressions.reason = 'complaint'
          then delivery_provider_suppressions.provider_event_id
        when excluded.reason = 'complaint' then excluded.provider_event_id
        when delivery_provider_suppressions.reason = 'permanent_bounce'
          then delivery_provider_suppressions.provider_event_id
        when excluded.reason = 'permanent_bounce' then excluded.provider_event_id
        else excluded.provider_event_id
      end,
      updated_at = clock_timestamp();
  end if;

  -- Delayed-to-delivered and delivered-to-complaint progression are valid.
  -- Incompatible terminal pairs are retained but never projected as success.
  select e.event_id into v_conflicting_event_id
  from public.delivery_provider_events e
  where e.provider_email_id = p_provider_email_id
    and e.event_id <> p_event_id
    and (
      (p_event_type = 'email.delivered'
        and e.event_type in ('email.bounced', 'email.failed', 'email.suppressed'))
      or (p_event_type in ('email.bounced', 'email.failed', 'email.suppressed')
        and e.event_type in ('email.delivered', 'email.complained'))
      or (p_event_type = 'email.complained'
        and e.event_type in ('email.bounced', 'email.failed', 'email.suppressed'))
      or (p_event_type = 'email.bounced'
        and e.event_type in ('email.failed', 'email.suppressed'))
      or (p_event_type = 'email.failed'
        and e.event_type in ('email.bounced', 'email.suppressed'))
      or (p_event_type = 'email.suppressed'
        and e.event_type in ('email.bounced', 'email.failed'))
    )
  order by e.received_at, e.event_id
  limit 1;

  if v_conflicting_event_id is not null then
    insert into public.delivery_provider_integrity_anomalies (
      event_id, related_event_id, anomaly_type
    ) values (
      p_event_id, v_conflicting_event_id, 'contradictory_terminal_outcome'
    )
    on conflict do nothing;

    insert into public.delivery_provider_lifecycle (
      provider_email_id,
      status,
      status_rank,
      provider_created_at,
      received_at,
      event_id,
      failure_class
    ) values (
      p_provider_email_id,
      'integrity_anomaly',
      80,
      p_provider_created_at,
      v_received_at,
      p_event_id,
      null
    )
    on conflict (provider_email_id) do update set
      status = 'integrity_anomaly',
      status_rank = 80,
      provider_created_at = excluded.provider_created_at,
      received_at = excluded.received_at,
      event_id = excluded.event_id,
      failure_class = null,
      updated_at = clock_timestamp();

    get diagnostics v_lifecycle_rows = row_count;
    if v_lifecycle_rows <> 1 then
      raise exception 'Provider lifecycle integrity state could not be persisted.' using errcode = '23505';
    end if;

    return null;
  end if;

  insert into public.delivery_provider_lifecycle (
    provider_email_id,
    status,
    status_rank,
    provider_created_at,
    received_at,
    event_id,
    failure_class
  ) values (
    p_provider_email_id,
    p_event_type,
    v_status_rank,
    p_provider_created_at,
    v_received_at,
    p_event_id,
    p_failure_class
  )
  on conflict (provider_email_id) do update set
    status = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.status
      else delivery_provider_lifecycle.status
    end,
    status_rank = greatest(
      delivery_provider_lifecycle.status_rank,
      excluded.status_rank
    ),
    provider_created_at = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.provider_created_at
      else delivery_provider_lifecycle.provider_created_at
    end,
    received_at = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.received_at
      else delivery_provider_lifecycle.received_at
    end,
    event_id = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.event_id
      else delivery_provider_lifecycle.event_id
    end,
    failure_class = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then excluded.failure_class
      else delivery_provider_lifecycle.failure_class
    end,
    updated_at = case
      when excluded.status_rank > delivery_provider_lifecycle.status_rank
        or (
          excluded.status_rank = delivery_provider_lifecycle.status_rank
          and (excluded.provider_created_at, excluded.event_id)
            > (delivery_provider_lifecycle.provider_created_at, delivery_provider_lifecycle.event_id)
        )
      then clock_timestamp()
      else delivery_provider_lifecycle.updated_at
    end;

  get diagnostics v_lifecycle_rows = row_count;
  if v_lifecycle_rows <> 1 then
    raise exception 'Provider lifecycle persistence failed.' using errcode = '23505';
  end if;

  return true;
end;
$$;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text, text)
to service_role;

comment on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text, text)
  is 'deedlight:027:provider-lifecycle-integrity-and-suppression-reasons:v1';

-- Compatibility wrapper for callers that already supply suppression_reason.
create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text,
  p_failure_class text,
  p_suppression_reason text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $compat$
begin
  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    p_provider_created_at,
    p_bounce_type,
    p_failure_class,
    p_suppression_reason,
    null
  );
end;
$compat$;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text)
to service_role;

-- Keep the original seven-argument RPC contract for trusted legacy callers.
create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text default null,
  p_failure_class text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $legacy$
declare
  v_existing_provider_created_at timestamptz;
  v_suppression_reason text;
begin
  select e.provider_created_at into v_existing_provider_created_at
  from public.delivery_provider_events e
  where e.event_id = p_event_id;

  if p_event_type = 'email.suppressed' then
    v_suppression_reason := 'provider_suppressed';
  end if;

  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    coalesce(v_existing_provider_created_at, p_provider_created_at, clock_timestamp()),
    p_bounce_type,
    p_failure_class,
    v_suppression_reason,
    null
  );
end;
$legacy$;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)
to service_role;

-- Preserve the original five-argument suppression RPC as a narrow wrapper.
create or replace function public.record_delivery_provider_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_bounce_type text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $legacy$
begin
  if p_event_type not in ('email.bounced', 'email.complained', 'email.suppressed') then
    raise exception 'Unsupported legacy provider event type.' using errcode = '22023';
  end if;

  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    clock_timestamp(),
    p_bounce_type,
    null
  );
end;
$legacy$;

revoke all privileges
on function public.record_delivery_provider_event(text, text, text, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_event(text, text, text, text, text)
to service_role;

notify pgrst, 'reload schema';
commit;

-- Correct lease expiry checks after ledger-row lock waits.
-- Migration 020 remains immutable; this additive migration replaces its four
-- transport-sensitive transitions using wall-clock time after row locking.
begin;
do $$
begin
  if to_regprocedure('public.authorize_delivery_job(uuid,uuid)') is null
    or to_regprocedure('public.retry_delivery_job(uuid,uuid,timestamptz,text)') is null
    or to_regprocedure('public.mark_delivery_sent(uuid,uuid,text)') is null
    or to_regprocedure('public.mark_delivery_failed(uuid,uuid,text)') is null then
    raise exception 'Migration 028 requires the reviewed delivery reliability RPCs.';
  end if;
end;
$$;

create or replace function public.authorize_delivery_job(p_job_id uuid, p_claim_token uuid)
returns boolean language plpgsql security definer
set search_path = public, auth, pg_temp
as $authorize$
declare
  v_job public.delivery_ledger%rowtype;
  v_authorized boolean := false;
  v_now timestamptz;
begin
  if p_job_id is null or p_claim_token is null then
    raise exception 'A job ID and claim token are required.' using errcode = '22023';
  end if;
  select * into v_job from public.delivery_ledger dl where dl.id = p_job_id for update;
  -- now() is fixed at transaction start and is unsafe after a row-lock wait.
  v_now := clock_timestamp();
  if not found or v_job.state <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token
     or v_job.claim_expires_at is null or v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  if v_job.kind = 'daily_reminder' then
    select exists (
      select 1 from public.daily_reminder_preferences drp
      join public.profiles p on p.user_id = drp.user_id and p.is_suspended = false
      join pg_catalog.pg_timezone_names tz on tz.name = drp.timezone
      where drp.user_id = v_job.user_id and drp.daily_enabled = true
        and v_job.delivery_key = 'daily:' || timezone(drp.timezone, v_job.scheduled_for)::date::text
        and v_job.scheduled_for = (
          (timezone(drp.timezone, v_job.scheduled_for)::date + drp.reminder_time)
          at time zone drp.timezone
        )
    ) into v_authorized;
  elsif v_job.kind = 'weekly_newsletter' then
    select exists (
      select 1 from public.newsletter_preferences np
      join public.profiles p on p.user_id = np.user_id and p.is_suspended = false
      join auth.users u on u.id = np.user_id
        and u.email_confirmed_at is not null and nullif(btrim(u.email), '') is not null
      join public.weekly_goodness_features f
        on v_job.delivery_key = 'weekly:' || f.week_start::text
      where np.user_id = v_job.user_id and np.weekly_enabled = true and np.consented_at is not null
    ) into v_authorized;
  else
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  -- Authorization reads may themselves take time; recheck before any result.
  v_now := clock_timestamp();
  if v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;
  if not v_authorized then
    update public.delivery_ledger set
      state = 'cancelled', cancelled_at = clock_timestamp(),
      claim_token = null, claim_expires_at = null, next_attempt_at = null,
      error_code = 'authorization_revoked', updated_at = clock_timestamp()
    where id = v_job.id and state = 'claimed' and claim_token = p_claim_token
      and claim_expires_at > clock_timestamp();
    if not found then
      raise exception 'Delivery claim is not authorized.' using errcode = '42501';
    end if;
    return false;
  end if;
  return true;
end;
$authorize$;
revoke all privileges on function public.authorize_delivery_job(uuid, uuid) from public, anon, authenticated;
grant execute on function public.authorize_delivery_job(uuid, uuid) to service_role;

create or replace function public.retry_delivery_job(
  p_job_id uuid, p_claim_token uuid, p_retry_at timestamptz, p_error_code text
)
returns boolean language plpgsql security definer
set search_path = public, auth, pg_temp
as $retry$
declare
  v_job public.delivery_ledger%rowtype;
  v_error_code text := btrim(coalesce(p_error_code, ''));
  v_now timestamptz;
begin
  if p_job_id is null or p_claim_token is null or p_retry_at is null then
    raise exception 'A job ID, claim token, and retry time are required.' using errcode = '22023';
  end if;
  if char_length(v_error_code) < 1 or char_length(v_error_code) > 100 then
    raise exception 'A bounded error code is required.' using errcode = '22023';
  end if;
  select * into v_job from public.delivery_ledger dl where dl.id = p_job_id for update;
  v_now := clock_timestamp();
  if not found or v_job.state <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token
     or v_job.claim_expires_at is null or v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;
  if p_retry_at <= v_now or p_retry_at > v_now + interval '24 hours' then
    raise exception 'Retry time must be within the next 24 hours.' using errcode = '22023';
  end if;
  if v_job.attempt_count >= 5 then
    update public.delivery_ledger set
      state = 'failed', failed_at = clock_timestamp(),
      claim_token = null, claim_expires_at = null, next_attempt_at = null,
      error_code = 'retry_exhausted', updated_at = clock_timestamp()
    where id = v_job.id and state = 'claimed' and claim_token = p_claim_token
      and claim_expires_at > clock_timestamp();
    if not found then
      raise exception 'Delivery claim is not authorized.' using errcode = '42501';
    end if;
    return false;
  end if;
  update public.delivery_ledger set
    state = 'queued', claim_token = null, claim_expires_at = null,
    next_attempt_at = p_retry_at, error_code = v_error_code, updated_at = clock_timestamp()
  where id = v_job.id and state = 'claimed' and claim_token = p_claim_token
    and claim_expires_at > clock_timestamp();
  if not found then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;
  return true;
end;
$retry$;
revoke all privileges on function public.retry_delivery_job(uuid, uuid, timestamptz, text)
from public, anon, authenticated;
grant execute on function public.retry_delivery_job(uuid, uuid, timestamptz, text) to service_role;

create or replace function public.mark_delivery_sent(
  p_job_id uuid, p_claim_token uuid, p_provider_result_id text default null
)
returns boolean language plpgsql security definer
set search_path = public, auth, pg_temp
as $sent$
declare
  v_job public.delivery_ledger%rowtype;
  v_now timestamptz;
begin
  if p_provider_result_id is not null and char_length(p_provider_result_id) > 255 then
    raise exception 'Provider result identifier is too long.' using errcode = '22023';
  end if;
  select * into v_job from public.delivery_ledger dl where dl.id = p_job_id for update;
  v_now := clock_timestamp();
  if not found or v_job.state <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token
     or v_job.claim_expires_at is null or v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;
  update public.delivery_ledger set
    state = 'sent', sent_at = clock_timestamp(),
    claim_token = null, claim_expires_at = null, next_attempt_at = null,
    provider_result_id = nullif(btrim(p_provider_result_id), ''),
    error_code = null, updated_at = clock_timestamp()
  where id = v_job.id and state = 'claimed' and claim_token = p_claim_token
    and claim_expires_at > clock_timestamp();
  if not found then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;
  return true;
end;
$sent$;
revoke all privileges on function public.mark_delivery_sent(uuid, uuid, text)
from public, anon, authenticated;
grant execute on function public.mark_delivery_sent(uuid, uuid, text) to service_role;

create or replace function public.mark_delivery_failed(
  p_job_id uuid, p_claim_token uuid, p_error_code text
)
returns boolean language plpgsql security definer
set search_path = public, auth, pg_temp
as $failed$
declare
  v_job public.delivery_ledger%rowtype;
  v_error_code text := btrim(coalesce(p_error_code, ''));
  v_now timestamptz;
begin
  if char_length(v_error_code) < 1 or char_length(v_error_code) > 100 then
    raise exception 'A bounded error code is required.' using errcode = '22023';
  end if;
  select * into v_job from public.delivery_ledger dl where dl.id = p_job_id for update;
  v_now := clock_timestamp();
  if not found or v_job.state <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token
     or v_job.claim_expires_at is null or v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;
  update public.delivery_ledger set
    state = 'failed', failed_at = clock_timestamp(),
    claim_token = null, claim_expires_at = null, next_attempt_at = null,
    error_code = v_error_code, updated_at = clock_timestamp()
  where id = v_job.id and state = 'claimed' and claim_token = p_claim_token
    and claim_expires_at > clock_timestamp();
  if not found then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;
  return true;
end;
$failed$;
revoke all privileges on function public.mark_delivery_failed(uuid, uuid, text)
from public, anon, authenticated;
grant execute on function public.mark_delivery_failed(uuid, uuid, text) to service_role;

notify pgrst, 'reload schema';
commit;

-- Restrict fingerprint-less provider RPCs to existing historical replays.
-- Migration 027 remains immutable; new events require the fingerprinted 9-argument RPC.
begin;

do $c226$
declare
  v_oid oid; v_source text; v_hash text; v_crypto_schema text;
  v_definer boolean; v_config text[]; v_language text; v_comment text;
begin
  if to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)') is null
    or to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)') is null
    or to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)') is null
    or to_regprocedure('public.record_delivery_provider_event(text,text,text,text,text)') is null then
    raise exception 'Migration 029 requires the reviewed provider lifecycle and legacy RPC overloads from migration 027.';
  end if;
  if to_regprocedure('public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)') is not null then
    raise exception 'Migration 029 refuses an existing private implementation with an unknown origin.';
  end if;
  v_oid := to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)');
  select p.prosrc,p.prosecdef,p.proconfig,l.lanname,obj_description(p.oid,'pg_proc')
  into v_source,v_definer,v_config,v_language,v_comment
  from pg_catalog.pg_proc p join pg_catalog.pg_language l on l.oid=p.prolang where p.oid=v_oid;
  if v_source is null or v_language <> 'plpgsql' or v_definer is distinct from true
    or v_config is distinct from array['search_path=public, auth, pg_temp']::text[]
    or v_comment is distinct from 'deedlight:027:provider-lifecycle-integrity-and-suppression-reasons:v1' then
    raise exception 'Migration 029 refuses an unrecognized migration-027 provider lifecycle implementation.';
  end if;
  select n.nspname into v_crypto_schema
  from pg_catalog.pg_extension e join pg_catalog.pg_namespace n on n.oid=e.extnamespace
  where e.extname='pgcrypto';
  if v_crypto_schema is null then
    raise exception 'Migration 029 requires pgcrypto to verify the migration-027 implementation identity.';
  end if;
  execute format('select encode(%I.digest(convert_to($1, ''UTF8''), ''sha256''), ''hex'')',v_crypto_schema)
  into v_hash using v_source;
  if v_hash is distinct from '8dbfc65b93677f9928114561d372dad69f16c9c746dadf80551c662161ba3ed5' then
    raise exception 'Migration 029 refuses an unrecognized migration-027 provider lifecycle implementation.';
  end if;
end;
$c226$;

-- Keep the reviewed 027 lifecycle implementation intact under a private name.
-- The public canonical RPC below becomes the only entry point to this implementation.
alter function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text, text
) rename to _record_delivery_provider_lifecycle_event_fingerprinted_impl;

revoke all privileges
on function public._record_delivery_provider_lifecycle_event_fingerprinted_impl(
  text, text, text, text, timestamptz, text, text, text, text
)
from public, anon, authenticated, service_role;

comment on function public._record_delivery_provider_lifecycle_event_fingerprinted_impl(
  text, text, text, text, timestamptz, text, text, text, text
)
is 'Private migration-027 lifecycle implementation; invoke only through the fingerprint-enforcing canonical RPC.';

create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text,
  p_failure_class text,
  p_suppression_reason text,
  p_payload_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $canonical$
declare
  v_existing public.delivery_provider_events%rowtype;
  v_email text;
begin
  if p_payload_fingerprint is null then
    if p_event_id is null or char_length(p_event_id) not between 1 and 255
      or p_provider_email_id is null or char_length(p_provider_email_id) not between 1 and 255
      or p_recipient_email is null or char_length(p_recipient_email) > 320 then
      raise exception 'A valid event ID, provider email ID and recipient are required for historical replay.'
        using errcode = '22023';
    end if;

    v_email := lower(btrim(p_recipient_email));
    if char_length(v_email) not between 3 and 320 then
      raise exception 'Invalid delivery provider recipient.' using errcode = '22023';
    end if;

    -- Match the canonical implementation's lock order before inspecting the
    -- event row. This serializes NULL-digest replays against concurrent inserts.
    perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
    perform pg_catalog.pg_advisory_xact_lock(20261126, hashtext(p_provider_email_id));

    select e.* into v_existing
    from public.delivery_provider_events e
    where e.event_id = p_event_id
    for update;

    if not found then
      raise exception 'Fingerprint-less provider events cannot be inserted; use the fingerprinted canonical RPC.'
        using errcode = '42501';
    end if;

    -- A stored NULL digest is the historical compatibility case. A stored
    -- non-NULL digest must take the implementation's conflict/anomaly path:
    -- the legacy caller cannot prove an exact replay without the raw-body hash.
  end if;

  return public._record_delivery_provider_lifecycle_event_fingerprinted_impl(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    p_provider_created_at,
    p_bounce_type,
    p_failure_class,
    p_suppression_reason,
    p_payload_fingerprint
  );
end;
$canonical$;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text, text
)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text, text
)
to service_role;

comment on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text, text
)
is 'deedlight:029:fingerprint-required-for-new-provider-events:v1';

-- Reassert the service-only legacy RPC boundary. Their existing wrappers
-- pass NULL to the canonical entry point and therefore cannot create rows.
revoke all privileges
on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text
)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text
)
to service_role;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text
)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text
)
to service_role;

revoke all privileges
on function public.record_delivery_provider_event(text, text, text, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_event(text, text, text, text, text)
to service_role;

notify pgrst, 'reload schema';
commit;

-- Make provider idempotency timing database-authoritative and validate Resend receipts.
begin;
do $migration_030_preflight$
declare
  v_crypto_schema text;
  v_authorize_oid oid := to_regprocedure('public.authorize_delivery_job(uuid,uuid)');
  v_failed_oid oid := to_regprocedure('public.mark_delivery_failed(uuid,uuid,text)');
  v_authorize_source text;
  v_failed_source text;
  v_authorize_hash text;
  v_failed_hash text;
  v_authorize_definer boolean;
  v_failed_definer boolean;
  v_authorize_config text[];
  v_failed_config text[];
  v_authorize_language text;
  v_failed_language text;
begin
  if v_authorize_oid is null
    or v_failed_oid is null
    or to_regprocedure('public.retry_delivery_job(uuid,uuid,timestamptz,text)') is null
    or to_regprocedure('public.mark_delivery_sent(uuid,uuid,text)') is null
    or not exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'delivery_ledger'
        and column_name = 'transport_started_at'
    ) then
    raise exception 'Migration 030 requires the exact hardened migration-028 authorize_delivery_job and mark_delivery_failed implementations.';
  end if;

  select n.nspname into v_crypto_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_crypto_schema is null then
    raise exception 'Migration 030 requires pgcrypto to attest migration-028 function source.';
  end if;

  select p.prosrc, p.prosecdef, p.proconfig, l.lanname
  into v_authorize_source, v_authorize_definer, v_authorize_config, v_authorize_language
  from pg_catalog.pg_proc p
  join pg_catalog.pg_language l on l.oid = p.prolang
  where p.oid = v_authorize_oid;

  select p.prosrc, p.prosecdef, p.proconfig, l.lanname
  into v_failed_source, v_failed_definer, v_failed_config, v_failed_language
  from pg_catalog.pg_proc p
  join pg_catalog.pg_language l on l.oid = p.prolang
  where p.oid = v_failed_oid;

  execute format(
    'select encode(%I.digest(convert_to($1, ''UTF8''), ''sha256''), ''hex'')',
    v_crypto_schema
  ) into v_authorize_hash using v_authorize_source;

  execute format(
    'select encode(%I.digest(convert_to($1, ''UTF8''), ''sha256''), ''hex'')',
    v_crypto_schema
  ) into v_failed_hash using v_failed_source;

  if v_authorize_hash is distinct from 'dea4d0ecb1518edec6c60f1ec998669af65b2164a547cffe67f5cbdaa8644215'
    or v_failed_hash is distinct from 'c7830ca2281fa85e4466fa45c32c1067dba4c9766eeeb26d26dcdb3b46b72b78'
    or v_authorize_language is distinct from 'plpgsql'
    or v_failed_language is distinct from 'plpgsql'
    or v_authorize_definer is distinct from true
    or v_failed_definer is distinct from true
    or v_authorize_config is distinct from array['search_path=public, auth, pg_temp']::text[]
    or v_failed_config is distinct from array['search_path=public, auth, pg_temp']::text[] then
    raise exception 'Migration 030 requires the exact hardened migration-028 authorize_delivery_job and mark_delivery_failed implementations.';
  end if;

  if has_function_privilege('anon', v_authorize_oid, 'EXECUTE')
    or has_function_privilege('authenticated', v_authorize_oid, 'EXECUTE')
    or not has_function_privilege('service_role', v_authorize_oid, 'EXECUTE')
    or has_function_privilege('anon', v_failed_oid, 'EXECUTE')
    or has_function_privilege('authenticated', v_failed_oid, 'EXECUTE')
    or not has_function_privilege('service_role', v_failed_oid, 'EXECUTE')
    or exists (
      select 1
      from pg_catalog.pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid in (v_authorize_oid, v_failed_oid)
        and a.grantee = 0
        and a.privilege_type = 'EXECUTE'
    ) then
    raise exception 'Migration 030 requires migration-028 service-role-only RPC privileges.';
  end if;
end;
$migration_030_preflight$;

drop function if exists public.authorize_delivery_idempotency_window(uuid,uuid);
create function public.authorize_delivery_idempotency_window(p_job_id uuid,p_claim_token uuid)
returns text language plpgsql security definer
set search_path = public, auth, pg_temp
as $idempotency$
declare v_job public.delivery_ledger%rowtype; v_now timestamptz;
begin
  if p_job_id is null or p_claim_token is null then raise exception 'A job ID and claim token are required.' using errcode='22023'; end if;
  -- Re-run the full consent/profile/claim authorization after transport start and immediately before send.
  if public.authorize_delivery_job(p_job_id,p_claim_token) is not true then return 'cancelled'; end if;
  select * into v_job from public.delivery_ledger dl where dl.id=p_job_id for update;
  v_now := clock_timestamp();
  if not found or v_job.state <> 'claimed' or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null or v_job.claim_expires_at <= v_now or v_job.transport_started_at is null then
    raise exception 'Delivery claim is not authorized for provider transport.' using errcode='42501';
  end if;
  if v_job.transport_started_at + interval '23 hours' <= v_now + interval '30 seconds' then
    update public.delivery_ledger set state='failed',failed_at=clock_timestamp(),claim_token=null,
      claim_expires_at=null,next_attempt_at=null,error_code='provider_idempotency_window_expired',updated_at=clock_timestamp()
    where id=v_job.id and state='claimed' and claim_token=p_claim_token and claim_expires_at > clock_timestamp();
    if not found then raise exception 'Delivery claim is not authorized for provider transport.' using errcode='42501'; end if;
    return 'expired';
  end if;
  return 'authorized';
end;
$idempotency$;
revoke all privileges on function public.authorize_delivery_idempotency_window(uuid,uuid) from public,anon,authenticated;
grant execute on function public.authorize_delivery_idempotency_window(uuid,uuid) to service_role;
comment on function public.authorize_delivery_idempotency_window(uuid,uuid)
is 'deedlight:030:database-authoritative-provider-idempotency-horizon:v1';

create or replace function public.retry_delivery_job(p_job_id uuid,p_claim_token uuid,p_error_code text)
returns boolean language plpgsql security definer
set search_path = public, auth, pg_temp
as $retry$
declare v_job public.delivery_ledger%rowtype; v_error text:=btrim(coalesce(p_error_code,'')); v_now timestamptz; v_retry_at timestamptz;
begin
  if p_job_id is null or p_claim_token is null then raise exception 'A job ID and claim token are required.' using errcode='22023'; end if;
  if char_length(v_error)<1 or char_length(v_error)>100 then raise exception 'A bounded error code is required.' using errcode='22023'; end if;
  select * into v_job from public.delivery_ledger dl where dl.id=p_job_id for update;
  v_now:=clock_timestamp();
  if not found or v_job.state<>'claimed' or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null or v_job.claim_expires_at<=v_now or v_job.transport_started_at is null then
    raise exception 'Delivery claim is not authorized for retry.' using errcode='42501';
  end if;
  if v_job.attempt_count>=5 then
    update public.delivery_ledger set state='failed',failed_at=clock_timestamp(),claim_token=null,claim_expires_at=null,
      next_attempt_at=null,error_code='retry_exhausted',updated_at=clock_timestamp()
    where id=v_job.id and state='claimed' and claim_token=p_claim_token and claim_expires_at>clock_timestamp();
    if not found then raise exception 'Delivery claim is not authorized for retry.' using errcode='42501'; end if;
    return false;
  end if;
  v_retry_at:=v_now+interval '5 minutes';
  if v_job.transport_started_at+interval '23 hours'<=v_retry_at+interval '30 seconds' then
    update public.delivery_ledger set state='failed',failed_at=clock_timestamp(),claim_token=null,claim_expires_at=null,
      next_attempt_at=null,error_code='provider_idempotency_window_expired',updated_at=clock_timestamp()
    where id=v_job.id and state='claimed' and claim_token=p_claim_token and claim_expires_at>clock_timestamp();
    if not found then raise exception 'Delivery claim is not authorized for retry.' using errcode='42501'; end if;
    return false;
  end if;
  update public.delivery_ledger set state='queued',claim_token=null,claim_expires_at=null,next_attempt_at=v_retry_at,
    error_code=v_error,updated_at=clock_timestamp()
  where id=v_job.id and state='claimed' and claim_token=p_claim_token and claim_expires_at>clock_timestamp()
    and transport_started_at+interval '23 hours'>clock_timestamp()+interval '5 minutes 30 seconds';
  if not found then
    update public.delivery_ledger set state='failed',failed_at=clock_timestamp(),claim_token=null,claim_expires_at=null,
      next_attempt_at=null,error_code='provider_idempotency_window_expired',updated_at=clock_timestamp()
    where id=v_job.id and state='claimed' and claim_token=p_claim_token and claim_expires_at>clock_timestamp()
      and transport_started_at+interval '23 hours'<=clock_timestamp()+interval '5 minutes 30 seconds';
    if found then return false; end if;
    raise exception 'Delivery claim is not authorized for retry.' using errcode='42501';
  end if;
  return true;
end;
$retry$;
revoke all privileges on function public.retry_delivery_job(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.retry_delivery_job(uuid,uuid,text) to service_role;
comment on function public.retry_delivery_job(uuid,uuid,text)
is 'deedlight:030:database-authoritative-retry-time-and-provider-horizon:v1';

create or replace function public.retry_delivery_job(p_job_id uuid,p_claim_token uuid,p_retry_at timestamptz,p_error_code text)
returns boolean language plpgsql security definer
set search_path = public, auth, pg_temp
as $legacy_retry$
begin return public.retry_delivery_job(p_job_id,p_claim_token,p_error_code); end;
$legacy_retry$;
revoke all privileges on function public.retry_delivery_job(uuid,uuid,timestamptz,text) from public,anon,authenticated;
grant execute on function public.retry_delivery_job(uuid,uuid,timestamptz,text) to service_role;
comment on function public.retry_delivery_job(uuid,uuid,timestamptz,text)
is 'deedlight:030:legacy-retry-timestamp-ignored:v1';

create or replace function public.mark_delivery_sent(p_job_id uuid,p_claim_token uuid,p_provider_result_id text default null)
returns boolean language plpgsql security definer
set search_path = public, auth, pg_temp
as $sent$
declare v_job public.delivery_ledger%rowtype; v_now timestamptz;
begin
  select * into v_job from public.delivery_ledger dl where dl.id=p_job_id for update;
  v_now:=clock_timestamp();
  if not found or v_job.state<>'claimed' or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null or v_job.claim_expires_at<=v_now or v_job.transport_started_at is null then
    raise exception 'Delivery claim is not authorized for sent transition.' using errcode='42501';
  end if;
  if p_provider_result_id is null or char_length(p_provider_result_id)<>36
    or p_provider_result_id<>btrim(p_provider_result_id)
    or p_provider_result_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'A valid Resend email identifier is required.' using errcode='22023';
  end if;
  update public.delivery_ledger set state='sent',sent_at=clock_timestamp(),claim_token=null,claim_expires_at=null,
    next_attempt_at=null,provider_result_id=p_provider_result_id,error_code=null,updated_at=clock_timestamp()
  where id=v_job.id and state='claimed' and claim_token=p_claim_token and claim_expires_at>clock_timestamp()
    and transport_started_at is not null;
  if not found then raise exception 'Delivery claim is not authorized for sent transition.' using errcode='42501'; end if;
  return true;
end;
$sent$;
revoke all privileges on function public.mark_delivery_sent(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mark_delivery_sent(uuid,uuid,text) to service_role;
comment on function public.mark_delivery_sent(uuid,uuid,text)
is 'deedlight:030:validated-resend-receipt-and-transport-evidence:v1';
notify pgrst,'reload schema';
commit;

-- Revalidate the exact recipient, current consent and provider suppression at the final send boundary.
-- Migration 031 replaces migration 030's last pre-send authorization RPC.
begin;

do $$
begin
  if to_regprocedure('public.authorize_delivery_idempotency_window(uuid,uuid)') is null
    or to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') is null
    or to_regclass('public.delivery_provider_suppressions') is null
    or to_regclass('public.daily_reminder_preferences') is null
    or to_regclass('public.newsletter_preferences') is null
    or to_regclass('public.profiles') is null
    or to_regclass('auth.users') is null then
    raise exception 'Migration 031 requires the reviewed delivery, recipient and provider-suppression baseline through migration 030.';
  end if;
end;
$$;

drop function public.authorize_delivery_idempotency_window(uuid, uuid);

create function public.authorize_delivery_idempotency_window(
  p_job_id uuid,
  p_claim_token uuid,
  p_expected_email text
)
returns text
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $final_gate$
declare
  v_job public.delivery_ledger%rowtype;
  v_email text;
  v_authorized boolean := false;
  v_now timestamptz;
begin
  if p_job_id is null or p_claim_token is null
    or p_expected_email is null
    or char_length(p_expected_email) > 320
    or nullif(btrim(p_expected_email), '') is null then
    raise exception 'A job ID, claim token and expected recipient are required.'
      using errcode = '22023';
  end if;

  v_email := lower(btrim(p_expected_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    raise exception 'Invalid expected delivery recipient.' using errcode = '22023';
  end if;

  select * into v_job
  from public.delivery_ledger dl
  where dl.id = p_job_id
  for update;

  v_now := clock_timestamp();
  if not found or v_job.state <> 'claimed'
    or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null
    or v_job.claim_expires_at <= v_now
    or v_job.transport_started_at is null then
    raise exception 'Delivery claim is not authorized for provider transport.'
      using errcode = '42501';
  end if;

  -- Serialize the final check with bounce/complaint/suppression intake.
  -- A suppression committed before this lock is observed; a concurrent event
  -- must wait until this final authorization transaction completes.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));

  if v_job.kind = 'daily_reminder' then
    perform 1
    from public.daily_reminder_preferences drp
    join public.profiles p
      on p.user_id = drp.user_id
     and p.is_suspended = false
    join auth.users u
      on u.id = drp.user_id
     and u.email_confirmed_at is not null
     and lower(btrim(u.email)) = v_email
    join pg_catalog.pg_timezone_names tz
      on tz.name = drp.timezone
    where drp.user_id = v_job.user_id
      and drp.daily_enabled = true
      and v_job.delivery_key =
        'daily:' || timezone(drp.timezone, v_job.scheduled_for)::date::text
      and v_job.scheduled_for = (
        (timezone(drp.timezone, v_job.scheduled_for)::date
          + drp.reminder_time) at time zone drp.timezone
      )
      and not exists (
        select 1
        from public.delivery_provider_suppressions s
        where s.recipient_email = v_email
      )
    for share of drp, p, u;
    v_authorized := found;
  elsif v_job.kind = 'weekly_newsletter' then
    perform 1
    from public.newsletter_preferences np
    join public.profiles p
      on p.user_id = np.user_id
     and p.is_suspended = false
    join auth.users u
      on u.id = np.user_id
     and u.email_confirmed_at is not null
     and lower(btrim(u.email)) = v_email
    join public.weekly_goodness_features f
      on v_job.delivery_key = 'weekly:' || f.week_start::text
    where np.user_id = v_job.user_id
      and np.weekly_enabled = true
      and np.consented_at is not null
      and not exists (
        select 1
        from public.delivery_provider_suppressions s
        where s.recipient_email = v_email
      )
    for share of np, p, u, f;
    v_authorized := found;
  else
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  -- Preference, profile and Auth rows remain locked through this transaction.
  -- Recheck the finite claim lease after those potentially blocking reads.
  v_now := clock_timestamp();
  if v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim expired during final authorization.'
      using errcode = '42501';
  end if;

  if not v_authorized then
    update public.delivery_ledger
    set state = 'cancelled',
        cancelled_at = clock_timestamp(),
        claim_token = null,
        claim_expires_at = null,
        next_attempt_at = null,
        error_code = 'authorization_revoked',
        updated_at = clock_timestamp()
    where id = v_job.id
      and state = 'claimed'
      and claim_token = p_claim_token
      and claim_expires_at > clock_timestamp();

    if not found then
      raise exception 'Delivery claim is not authorized for provider transport.'
        using errcode = '42501';
    end if;
    return 'cancelled';
  end if;

  if v_job.transport_started_at + interval '23 hours' <= v_now + interval '30 seconds' then
    update public.delivery_ledger
    set state = 'failed',
        failed_at = clock_timestamp(),
        claim_token = null,
        claim_expires_at = null,
        next_attempt_at = null,
        error_code = 'provider_idempotency_window_expired',
        updated_at = clock_timestamp()
    where id = v_job.id
      and state = 'claimed'
      and claim_token = p_claim_token
      and claim_expires_at > clock_timestamp();

    if not found then
      raise exception 'Delivery claim is not authorized for provider transport.'
        using errcode = '42501';
    end if;
    return 'expired';
  end if;

  return 'authorized';
end;
$final_gate$;

revoke all privileges
on function public.authorize_delivery_idempotency_window(uuid, uuid, text)
from public, anon, authenticated;
grant execute
on function public.authorize_delivery_idempotency_window(uuid, uuid, text)
to service_role;
comment on function public.authorize_delivery_idempotency_window(uuid, uuid, text)
is 'deedlight:031:final-recipient-consent-and-suppression-gate:v1';

notify pgrst, 'reload schema';
commit;

-- Resend managed suppression-list webhook synchronization.
-- Removal clears only provider-level suppression; Deedlight complaint/bounce holds remain.
begin;

alter table public.delivery_provider_events
  alter column provider_email_id drop not null;

alter table public.delivery_provider_events
  drop constraint delivery_provider_events_event_type_check;

alter table public.delivery_provider_events
  add constraint delivery_provider_events_event_type_check
  check (event_type in (
    'email.sent',
    'email.delivered',
    'email.delivery_delayed',
    'email.bounced',
    'email.complained',
    'email.suppressed',
    'email.failed',
    'suppression.added',
    'suppression.removed'
  )),
  add column provider_suppression_id text,
  add column suppression_origin text,
  add column suppression_source_id text,
  add column suppression_created_at timestamptz,
  add constraint delivery_provider_events_provider_suppression_id_check
    check (provider_suppression_id is null
      or char_length(provider_suppression_id) between 1 and 255),
  add constraint delivery_provider_events_suppression_origin_check
    check (suppression_origin is null
      or suppression_origin in ('bounce', 'complaint', 'manual')),
  add constraint delivery_provider_events_suppression_source_id_check
    check (suppression_source_id is null
      or char_length(suppression_source_id) between 1 and 255),
  add constraint delivery_provider_events_suppression_shape_check
    check (
      (
        event_type in ('suppression.added', 'suppression.removed')
        and provider_email_id is null
        and provider_suppression_id is not null
        and suppression_origin is not null
        and suppression_created_at is not null
        and bounce_type is null
        and failure_class is null
        and suppression_reason is null
        and payload_fingerprint is not null
      )
      or (
        event_type not in ('suppression.added', 'suppression.removed')
        and provider_email_id is not null
        and provider_suppression_id is null
        and suppression_origin is null
        and suppression_source_id is null
        and suppression_created_at is null
      )
    );

create index delivery_provider_events_suppression_id_idx
  on public.delivery_provider_events (provider_suppression_id)
  where provider_suppression_id is not null;

alter table public.delivery_provider_integrity_anomalies
  drop constraint delivery_provider_integrity_anomalies_anomaly_type_check;

alter table public.delivery_provider_integrity_anomalies
  add constraint delivery_provider_integrity_anomalies_anomaly_type_check
  check (anomaly_type in (
    'duplicate_event_id_conflict',
    'contradictory_terminal_outcome',
    'suppression_event_timestamp_conflict'
  ));

create table public.delivery_provider_suppression_state (
  recipient_email text primary key
    check (
      char_length(recipient_email) between 3 and 320
      and recipient_email = lower(btrim(recipient_email))
      and recipient_email !~ '[[:space:][:cntrl:]]'
      and position('@' in recipient_email) > 1
    ),
  provider_suppression_id text not null
    check (char_length(provider_suppression_id) between 1 and 255),
  origin text not null check (origin in ('bounce', 'complaint', 'manual')),
  is_active boolean not null,
  provider_created_at timestamptz not null,
  event_id text not null
    references public.delivery_provider_events(event_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint delivery_provider_suppression_state_id_unique
    unique (provider_suppression_id)
);

alter table public.delivery_provider_suppression_state enable row level security;
revoke all privileges on table public.delivery_provider_suppression_state
  from public, anon, authenticated, service_role;

create function public.record_delivery_provider_suppression_event(
  p_event_id text,
  p_event_type text,
  p_provider_suppression_id text,
  p_recipient_email text,
  p_suppression_origin text,
  p_suppression_source_id text,
  p_suppression_created_at timestamptz,
  p_provider_created_at timestamptz,
  p_payload_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $suppression_sync$
declare
  v_email text;
  v_inserted integer;
  v_existing public.delivery_provider_events%rowtype;
  v_state public.delivery_provider_suppression_state%rowtype;
  v_reason text;
  v_active boolean;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_id !~ '^[[:graph:]]+$'
    or p_event_type is null
    or p_event_type not in ('suppression.added', 'suppression.removed')
    or p_provider_suppression_id is null
    or char_length(p_provider_suppression_id) not between 1 and 255
    or p_provider_suppression_id !~ '^[[:graph:]]+$'
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320
    or p_suppression_origin is null
    or p_suppression_origin not in ('bounce', 'complaint', 'manual')
    or (p_suppression_source_id is not null
      and (char_length(p_suppression_source_id) not between 1 and 255
        or p_suppression_source_id !~ '^[[:graph:]]+$'))
    or p_suppression_created_at is null
    or p_provider_created_at is null
    or p_payload_fingerprint is null
    or p_payload_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid provider suppression event.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid provider suppression recipient.' using errcode = '22023';
  end if;

  -- Match the existing delivery and lifecycle lock order: address, then provider ID.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261127, hashtext(p_provider_suppression_id));

  if exists (
    select 1
    from public.delivery_provider_events e
    where e.provider_suppression_id = p_provider_suppression_id
      and e.recipient_email <> v_email
  ) then
    raise exception 'Provider suppression correlation does not match.'
      using errcode = '22023';
  end if;

  insert into public.delivery_provider_events (
    event_id,
    event_type,
    provider_email_id,
    recipient_email,
    bounce_type,
    provider_created_at,
    failure_class,
    suppression_reason,
    payload_fingerprint,
    provider_suppression_id,
    suppression_origin,
    suppression_source_id,
    suppression_created_at
  ) values (
    p_event_id,
    p_event_type,
    null,
    v_email,
    null,
    p_provider_created_at,
    null,
    null,
    p_payload_fingerprint,
    p_provider_suppression_id,
    p_suppression_origin,
    p_suppression_source_id,
    p_suppression_created_at
  )
  on conflict (event_id) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    select e.* into v_existing
    from public.delivery_provider_events e
    where e.event_id = p_event_id
    for update;

    if not found then
      raise exception 'Conflicting provider suppression event could not be inspected.'
        using errcode = 'XX000';
    end if;

    if v_existing.event_type = p_event_type
      and v_existing.provider_email_id is null
      and v_existing.recipient_email = v_email
      and v_existing.provider_created_at = p_provider_created_at
      and v_existing.provider_suppression_id = p_provider_suppression_id
      and v_existing.suppression_origin = p_suppression_origin
      and v_existing.suppression_source_id is not distinct from p_suppression_source_id
      and v_existing.suppression_created_at = p_suppression_created_at
      and v_existing.payload_fingerprint = p_payload_fingerprint then
      return false;
    end if;

    insert into public.delivery_provider_integrity_anomalies (
      event_id, related_event_id, anomaly_type
    ) values (
      v_existing.event_id, null, 'duplicate_event_id_conflict'
    )
    on conflict do nothing;

    if v_existing.provider_email_id is not null then
      update public.delivery_provider_lifecycle
      set status = 'integrity_anomaly',
          status_rank = 80,
          failure_class = null,
          updated_at = clock_timestamp()
      where provider_email_id = v_existing.provider_email_id;
    end if;

    return null;
  end if;

  select * into v_state
  from public.delivery_provider_suppression_state s
  where s.recipient_email = v_email
  for update;

  v_active := p_event_type = 'suppression.added';

  if not found then
    insert into public.delivery_provider_suppression_state (
      recipient_email,
      provider_suppression_id,
      origin,
      is_active,
      provider_created_at,
      event_id
    ) values (
      v_email,
      p_provider_suppression_id,
      p_suppression_origin,
      v_active,
      p_provider_created_at,
      p_event_id
    )
    returning * into v_state;
  elsif p_provider_created_at > v_state.provider_created_at then
    update public.delivery_provider_suppression_state
    set provider_suppression_id = p_provider_suppression_id,
        origin = p_suppression_origin,
        is_active = v_active,
        provider_created_at = p_provider_created_at,
        event_id = p_event_id,
        updated_at = clock_timestamp()
    where recipient_email = v_email
    returning * into v_state;
  elsif p_provider_created_at = v_state.provider_created_at
    and (
      v_state.provider_suppression_id <> p_provider_suppression_id
      or v_state.origin <> p_suppression_origin
      or v_state.is_active <> v_active
    ) then
    -- Equal-time contradictory state is ambiguous: preserve the block.
    insert into public.delivery_provider_integrity_anomalies (
      event_id, related_event_id, anomaly_type
    ) values (
      p_event_id, v_state.event_id, 'suppression_event_timestamp_conflict'
    )
    on conflict do nothing;

    update public.delivery_provider_suppression_state
    set provider_suppression_id = greatest(provider_suppression_id, p_provider_suppression_id),
        origin = case
          when origin = 'complaint' or p_suppression_origin = 'complaint' then 'complaint'
          when origin = 'bounce' or p_suppression_origin = 'bounce' then 'bounce'
          else 'manual'
        end,
        is_active = true,
        event_id = greatest(event_id, p_event_id),
        updated_at = clock_timestamp()
    where recipient_email = v_email
    returning * into v_state;
  elsif p_provider_created_at = v_state.provider_created_at
    and p_event_id > v_state.event_id then
    update public.delivery_provider_suppression_state
    set event_id = p_event_id,
        updated_at = clock_timestamp()
    where recipient_email = v_email
    returning * into v_state;
  end if;

  -- Any bounce/complaint origin is an independent Deedlight hold, even
  -- when that event arrives after a newer provider removal event.
  if p_suppression_origin in ('bounce', 'complaint')
    or v_state.origin in ('bounce', 'complaint') then
    v_reason := case
      when p_suppression_origin = 'complaint' or v_state.origin = 'complaint'
        then 'complaint'
      else 'permanent_bounce'
    end;
  elsif v_state.is_active then
    v_reason := 'provider_suppressed';
  else
    v_reason := null;
  end if;

  if v_reason is not null then
    insert into public.delivery_provider_suppressions (
      recipient_email, reason, provider_event_id
    ) values (
      v_email,
      v_reason,
      case
        when v_state.origin = 'complaint' then v_state.event_id
        when p_suppression_origin = 'complaint' then p_event_id
        when v_state.origin = 'bounce' then v_state.event_id
        when p_suppression_origin = 'bounce' then p_event_id
        else v_state.event_id
      end
    )
    on conflict (recipient_email) do update set
      reason = case
        when delivery_provider_suppressions.reason = 'complaint' then 'complaint'
        when excluded.reason = 'complaint' then 'complaint'
        when delivery_provider_suppressions.reason = 'permanent_bounce' then 'permanent_bounce'
        when excluded.reason = 'permanent_bounce' then 'permanent_bounce'
        else 'provider_suppressed'
      end,
      provider_event_id = case
        when delivery_provider_suppressions.reason = 'complaint'
          then delivery_provider_suppressions.provider_event_id
        when excluded.reason = 'complaint' then excluded.provider_event_id
        when delivery_provider_suppressions.reason = 'permanent_bounce'
          then delivery_provider_suppressions.provider_event_id
        when excluded.reason = 'permanent_bounce' then excluded.provider_event_id
        else excluded.provider_event_id
      end,
      updated_at = clock_timestamp();
  elsif v_state.origin = 'manual'
    and exists (
      select 1
      from public.delivery_provider_events added
      where added.event_type = 'suppression.added'
        and added.provider_suppression_id = v_state.provider_suppression_id
        and added.recipient_email = v_email
        and added.suppression_origin = 'manual'
    ) then
    -- A removal without its matching add is not authority to clear old blocks.
    delete from public.delivery_provider_suppressions
    where recipient_email = v_email
      and reason = 'provider_suppressed';
  end if;

  return true;
end;
$suppression_sync$;

revoke all privileges
on function public.record_delivery_provider_suppression_event(
  text, text, text, text, text, text, timestamptz, timestamptz, text
)
from public, anon, authenticated, service_role;
grant execute
on function public.record_delivery_provider_suppression_event(
  text, text, text, text, text, text, timestamptz, timestamptz, text
)
to service_role;
comment on function public.record_delivery_provider_suppression_event(
  text, text, text, text, text, text, timestamptz, timestamptz, text
)
is 'deedlight:032:resend-suppression-list-sync:v1';

notify pgrst, 'reload schema';
commit;

-- Reconcile email.suppressed lifecycle events with the migration-032 provider-state projection.
-- A late generic lifecycle event cannot restore a manual suppression removed later by Resend.
begin;

do $migration_033_preflight$
begin
  if to_regclass('public.delivery_provider_suppressions') is null
    or to_regclass('public.delivery_provider_suppression_state') is null
    or to_regprocedure('public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)') is null then
    raise exception 'Migration 033 requires migration 032 suppression state and the private migration-029 lifecycle implementation.';
  end if;
end;
$migration_033_preflight$;

-- Preserve migration 029's fingerprint gate and legacy replay-only behavior.
-- The private implementation takes the shared per-recipient advisory lock;
-- that transaction-scoped lock remains held through this reconciliation.
create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text,
  p_failure_class text,
  p_suppression_reason text,
  p_payload_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $cross_stream$
declare
  v_existing public.delivery_provider_events%rowtype;
  v_email text;
  v_result boolean;
begin
  if p_payload_fingerprint is null then
    if p_event_id is null or char_length(p_event_id) not between 1 and 255
      or p_provider_email_id is null or char_length(p_provider_email_id) not between 1 and 255
      or p_recipient_email is null or char_length(p_recipient_email) > 320 then
      raise exception 'A valid event ID, provider email ID and recipient are required for historical replay.'
        using errcode = '22023';
    end if;

    v_email := lower(btrim(p_recipient_email));
    if char_length(v_email) not between 3 and 320 then
      raise exception 'Invalid delivery provider recipient.' using errcode = '22023';
    end if;

    -- Keep the canonical implementation's lock order for fingerprint-less replays.
    perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
    perform pg_catalog.pg_advisory_xact_lock(20261126, hashtext(p_provider_email_id));

    select e.* into v_existing
    from public.delivery_provider_events e
    where e.event_id = p_event_id
    for update;

    if not found then
      raise exception 'Fingerprint-less provider events cannot be inserted; use the fingerprinted canonical RPC.'
        using errcode = '42501';
    end if;
  end if;

  v_result := public._record_delivery_provider_lifecycle_event_fingerprinted_impl(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    p_provider_created_at,
    p_bounce_type,
    p_failure_class,
    p_suppression_reason,
    p_payload_fingerprint
  );

  if v_result is true
    and p_event_type = 'email.suppressed'
    and p_suppression_reason = 'provider_suppressed' then
    v_email := lower(btrim(p_recipient_email));

    -- A strictly newer manual removal wins across the email and suppression-list
    -- event families. Equal timestamps remain blocked as ambiguous.
    if exists (
      select 1
      from public.delivery_provider_suppression_state s
      where s.recipient_email = v_email
        and s.origin = 'manual'
        and s.is_active = false
        and s.provider_created_at > p_provider_created_at
        and exists (
          select 1
          from public.delivery_provider_events added
          where added.event_type = 'suppression.added'
            and added.provider_suppression_id = s.provider_suppression_id
            and added.recipient_email = v_email
            and added.suppression_origin = 'manual'
        )
    ) then
      delete from public.delivery_provider_suppressions
      where recipient_email = v_email
        and reason = 'provider_suppressed';
    end if;
  end if;

  return v_result;
end;
$cross_stream$;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text, text
)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text, text
)
to service_role;

comment on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text, text
)
is 'deedlight:033:cross-stream-suppression-order:v1';

notify pgrst, 'reload schema';
commit;

-- Forward-only hardening for cross-stream provider suppression event timestamps.
-- Keep migrations 032/033 immutable; this replaces only the suppression-list RPC.
begin;

create index if not exists delivery_provider_events_generic_suppression_order_idx
  on public.delivery_provider_events (recipient_email, provider_created_at)
  where event_type = 'email.suppressed'
    and (suppression_reason = 'provider_suppressed' or suppression_reason is null);

create or replace function public.record_delivery_provider_suppression_event(
  p_event_id text,
  p_event_type text,
  p_provider_suppression_id text,
  p_recipient_email text,
  p_suppression_origin text,
  p_suppression_source_id text,
  p_suppression_created_at timestamptz,
  p_provider_created_at timestamptz,
  p_payload_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $suppression_sync$
declare
  v_email text;
  v_inserted integer;
  v_existing public.delivery_provider_events%rowtype;
  v_state public.delivery_provider_suppression_state%rowtype;
  v_reason text;
  v_active boolean;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_id !~ '^[[:graph:]]+$'
    or p_event_type is null
    or p_event_type not in ('suppression.added', 'suppression.removed')
    or p_provider_suppression_id is null
    or char_length(p_provider_suppression_id) not between 1 and 255
    or p_provider_suppression_id !~ '^[[:graph:]]+$'
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320
    or p_suppression_origin is null
    or p_suppression_origin not in ('bounce', 'complaint', 'manual')
    or (p_suppression_source_id is not null
      and (char_length(p_suppression_source_id) not between 1 and 255
        or p_suppression_source_id !~ '^[[:graph:]]+$'))
    or p_suppression_created_at is null
    or p_provider_created_at is null
    or p_payload_fingerprint is null
    or p_payload_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid provider suppression event.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid provider suppression recipient.' using errcode = '22023';
  end if;

  -- Match the existing delivery and lifecycle lock order: address, then provider ID.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261127, hashtext(p_provider_suppression_id));

  if exists (
    select 1
    from public.delivery_provider_events e
    where e.provider_suppression_id = p_provider_suppression_id
      and e.recipient_email <> v_email
  ) then
    raise exception 'Provider suppression correlation does not match.'
      using errcode = '22023';
  end if;

  insert into public.delivery_provider_events (
    event_id,
    event_type,
    provider_email_id,
    recipient_email,
    bounce_type,
    provider_created_at,
    failure_class,
    suppression_reason,
    payload_fingerprint,
    provider_suppression_id,
    suppression_origin,
    suppression_source_id,
    suppression_created_at
  ) values (
    p_event_id,
    p_event_type,
    null,
    v_email,
    null,
    p_provider_created_at,
    null,
    null,
    p_payload_fingerprint,
    p_provider_suppression_id,
    p_suppression_origin,
    p_suppression_source_id,
    p_suppression_created_at
  )
  on conflict (event_id) do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    select e.* into v_existing
    from public.delivery_provider_events e
    where e.event_id = p_event_id
    for update;

    if not found then
      raise exception 'Conflicting provider suppression event could not be inspected.'
        using errcode = 'XX000';
    end if;

    if v_existing.event_type = p_event_type
      and v_existing.provider_email_id is null
      and v_existing.recipient_email = v_email
      and v_existing.provider_created_at = p_provider_created_at
      and v_existing.provider_suppression_id = p_provider_suppression_id
      and v_existing.suppression_origin = p_suppression_origin
      and v_existing.suppression_source_id is not distinct from p_suppression_source_id
      and v_existing.suppression_created_at = p_suppression_created_at
      and v_existing.payload_fingerprint = p_payload_fingerprint then
      return false;
    end if;

    insert into public.delivery_provider_integrity_anomalies (
      event_id, related_event_id, anomaly_type
    ) values (
      v_existing.event_id, null, 'duplicate_event_id_conflict'
    )
    on conflict do nothing;

    if v_existing.provider_email_id is not null then
      update public.delivery_provider_lifecycle
      set status = 'integrity_anomaly',
          status_rank = 80,
          failure_class = null,
          updated_at = clock_timestamp()
      where provider_email_id = v_existing.provider_email_id;
    end if;

    return null;
  end if;

  select * into v_state
  from public.delivery_provider_suppression_state s
  where s.recipient_email = v_email
  for update;

  v_active := p_event_type = 'suppression.added';

  if not found then
    insert into public.delivery_provider_suppression_state (
      recipient_email,
      provider_suppression_id,
      origin,
      is_active,
      provider_created_at,
      event_id
    ) values (
      v_email,
      p_provider_suppression_id,
      p_suppression_origin,
      v_active,
      p_provider_created_at,
      p_event_id
    )
    returning * into v_state;
  elsif p_provider_created_at > v_state.provider_created_at then
    update public.delivery_provider_suppression_state
    set provider_suppression_id = p_provider_suppression_id,
        origin = p_suppression_origin,
        is_active = v_active,
        provider_created_at = p_provider_created_at,
        event_id = p_event_id,
        updated_at = clock_timestamp()
    where recipient_email = v_email
    returning * into v_state;
  elsif p_provider_created_at = v_state.provider_created_at
    and (
      v_state.provider_suppression_id <> p_provider_suppression_id
      or v_state.origin <> p_suppression_origin
      or v_state.is_active <> v_active
    ) then
    -- Equal-time contradictory state is ambiguous: preserve the block.
    insert into public.delivery_provider_integrity_anomalies (
      event_id, related_event_id, anomaly_type
    ) values (
      p_event_id, v_state.event_id, 'suppression_event_timestamp_conflict'
    )
    on conflict do nothing;

    update public.delivery_provider_suppression_state
    set provider_suppression_id = greatest(provider_suppression_id, p_provider_suppression_id),
        origin = case
          when origin = 'complaint' or p_suppression_origin = 'complaint' then 'complaint'
          when origin = 'bounce' or p_suppression_origin = 'bounce' then 'bounce'
          else 'manual'
        end,
        is_active = true,
        event_id = greatest(event_id, p_event_id),
        updated_at = clock_timestamp()
    where recipient_email = v_email
    returning * into v_state;
  elsif p_provider_created_at = v_state.provider_created_at
    and p_event_id > v_state.event_id then
    update public.delivery_provider_suppression_state
    set event_id = p_event_id,
        updated_at = clock_timestamp()
    where recipient_email = v_email
    returning * into v_state;
  end if;

  -- Any bounce/complaint origin is an independent Deedlight hold, even
  -- when that event arrives after a newer provider removal event.
  if p_suppression_origin in ('bounce', 'complaint')
    or v_state.origin in ('bounce', 'complaint') then
    v_reason := case
      when p_suppression_origin = 'complaint' or v_state.origin = 'complaint'
        then 'complaint'
      else 'permanent_bounce'
    end;
  elsif v_state.is_active then
    v_reason := 'provider_suppressed';
  else
    v_reason := null;
  end if;

  if v_reason is not null then
    insert into public.delivery_provider_suppressions (
      recipient_email, reason, provider_event_id
    ) values (
      v_email,
      v_reason,
      case
        when v_state.origin = 'complaint' then v_state.event_id
        when p_suppression_origin = 'complaint' then p_event_id
        when v_state.origin = 'bounce' then v_state.event_id
        when p_suppression_origin = 'bounce' then p_event_id
        else v_state.event_id
      end
    )
    on conflict (recipient_email) do update set
      reason = case
        when delivery_provider_suppressions.reason = 'complaint' then 'complaint'
        when excluded.reason = 'complaint' then 'complaint'
        when delivery_provider_suppressions.reason = 'permanent_bounce' then 'permanent_bounce'
        when excluded.reason = 'permanent_bounce' then 'permanent_bounce'
        else 'provider_suppressed'
      end,
      provider_event_id = case
        when delivery_provider_suppressions.reason = 'complaint'
          then delivery_provider_suppressions.provider_event_id
        when excluded.reason = 'complaint' then excluded.provider_event_id
        when delivery_provider_suppressions.reason = 'permanent_bounce'
          then delivery_provider_suppressions.provider_event_id
        when excluded.reason = 'permanent_bounce' then excluded.provider_event_id
        else excluded.provider_event_id
      end,
      updated_at = clock_timestamp();
  elsif v_state.origin = 'manual'
    and exists (
      select 1
      from public.delivery_provider_events added
      where added.event_type = 'suppression.added'
        and added.provider_suppression_id = v_state.provider_suppression_id
        and added.recipient_email = v_email
        and added.suppression_origin = 'manual'
    )
    and not exists (
      select 1
      from public.delivery_provider_events lifecycle
      where lifecycle.event_type = 'email.suppressed'
        and lifecycle.recipient_email = v_email
        and (
          lifecycle.suppression_reason = 'provider_suppressed'
          or lifecycle.suppression_reason is null
        )
        and (
          lifecycle.provider_created_at is null
          or lifecycle.provider_created_at >= p_provider_created_at
        )
    ) then
    -- Only a strictly newer manual removal may clear generic lifecycle evidence.
    -- Unknown legacy timestamps are ambiguous and therefore fail closed.
    delete from public.delivery_provider_suppressions
    where recipient_email = v_email
      and reason = 'provider_suppressed';
  end if;

  return true;
end;
$suppression_sync$;


revoke all privileges
on function public.record_delivery_provider_suppression_event(
  text, text, text, text, text, text, timestamptz, timestamptz, text
)
from public, anon, authenticated, service_role;
grant execute
on function public.record_delivery_provider_suppression_event(
  text, text, text, text, text, text, timestamptz, timestamptz, text
)
to service_role;
comment on function public.record_delivery_provider_suppression_event(
  text, text, text, text, text, text, timestamptz, timestamptz, text
)
is 'deedlight:034:provider-suppression-timestamp-order:v1';

notify pgrst, 'reload schema';
commit;

-- DeedLight privacy hardening: public Offering access stays on the projection.
-- The Sprint 5 base-table policy survived Sprint 9's projection boundary and
-- exposed approved rows (including internal columns) to every authenticated member.
-- Preserve the existing owner/admin policies and grants; remove only that stale
-- public-read policy so base-table reads remain owner/admin scoped.

begin;

drop policy if exists "offerings_select_public_or_own"
on public.offerings;

drop policy if exists "offerings_public_approved_read"
on public.offerings;

commit;


-- Private Daily Journey reflection authorization hardening.
-- Reflection contents are visible and mutable only by their owning member.
-- Administrator moderation continues through narrow projections that exclude reflections.

begin;

alter table public.daily_reflections
  enable row level security;

-- Both historical migrations created permissive policies using different names.
drop policy if exists "daily_reflections_select_own_or_admin"
on public.daily_reflections;

drop policy if exists "daily reflections select own or admin"
on public.daily_reflections;

drop policy if exists "daily_reflections_select_own"
on public.daily_reflections;

create policy "daily_reflections_select_own"
on public.daily_reflections
for select
to authenticated
using (
  user_id = auth.uid()
);

drop policy if exists "daily_reflections_insert_own"
on public.daily_reflections;

drop policy if exists "daily reflections insert own"
on public.daily_reflections;

create policy "daily_reflections_insert_own"
on public.daily_reflections
for insert
to authenticated
with check (
  user_id = auth.uid()
);

drop policy if exists "daily_reflections_update_own"
on public.daily_reflections;

drop policy if exists "daily reflections update own or admin"
on public.daily_reflections;

create policy "daily_reflections_update_own"
on public.daily_reflections
for update
to authenticated
using (
  user_id = auth.uid()
)
with check (
  user_id = auth.uid()
);

-- No browser role, including administrators, may delete private reflections.
drop policy if exists "daily_reflections_delete_admin"
on public.daily_reflections;

drop policy if exists "daily reflections delete admin"
on public.daily_reflections;

revoke all privileges
on table public.daily_reflections
from public, anon, authenticated;

grant select, insert, update
on table public.daily_reflections
to authenticated;

-- Retain the existing trusted server-only database capability.
grant all privileges
on table public.daily_reflections
to service_role;

notify pgrst, 'reload schema';

commit;


-- Durable recipient-scoped provider-integrity conflict evidence.
-- Migration 036 remains immutable. This migration adds an auditable case/evidence model
-- and wraps the existing provider RPCs without changing their trusted caller signatures.

begin;

do $migration_037_preflight$
declare
  v_lifecycle_comment text;
  v_suppression_comment text;
begin
  if to_regclass('public.delivery_provider_events') is null
    or to_regclass('public.delivery_provider_lifecycle') is null
    or to_regclass('public.delivery_provider_suppressions') is null
    or to_regclass('public.delivery_provider_suppression_state') is null
    or to_regclass('public.delivery_provider_integrity_anomalies') is null
    or to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)') is null
    or to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)') is null
    or to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)') is null
    or to_regprocedure('public.record_delivery_provider_event(text,text,text,text,text)') is null
    or to_regprocedure('public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)') is null
    or to_regprocedure('public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)') is null
    or to_regprocedure('public.is_admin()') is null then
    raise exception 'Migration 037 requires the reviewed provider RPC, suppression-state, integrity and admin prerequisites.';
  end if;

  select obj_description(
    to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)'),
    'pg_proc'
  ) into v_lifecycle_comment;
  select obj_description(
    to_regprocedure('public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)'),
    'pg_proc'
  ) into v_suppression_comment;

  if v_lifecycle_comment is distinct from 'deedlight:033:cross-stream-suppression-order:v1'
    or v_suppression_comment is distinct from 'deedlight:034:provider-suppression-timestamp-order:v1' then
    raise exception 'Migration 037 refuses an unrecognized provider RPC implementation.';
  end if;

  if to_regprocedure('public._record_delivery_provider_lifecycle_event_pre037_impl(text,text,text,text,timestamptz,text,text,text,text)') is not null
    or to_regprocedure('public._record_delivery_provider_suppression_event_pre037_impl(text,text,text,text,text,text,timestamptz,timestamptz,text)') is not null
    or to_regclass('public.delivery_provider_integrity_cases') is not null
    or to_regclass('public.delivery_provider_integrity_conflict_evidence') is not null
    or to_regclass('public.delivery_provider_integrity_conflict_history') is not null then
    raise exception 'Migration 037 refuses pre-existing objects with an unknown origin.';
  end if;
end;
$migration_037_preflight$;

create table public.delivery_provider_integrity_cases (
  conflict_id bigint generated always as identity primary key,
  recipient_email text not null
    check (
      char_length(recipient_email) between 3 and 320
      and recipient_email = lower(btrim(recipient_email))
      and recipient_email !~ '[[:space:][:cntrl:]]'
      and position('@' in recipient_email) > 1
    ),
  anomaly_type text not null
    check (anomaly_type in (
      'duplicate_event_id_conflict',
      'contradictory_terminal_outcome',
      'suppression_event_timestamp_conflict',
      'provider_email_recipient_conflict',
      'provider_suppression_recipient_conflict'
    )),
  state text not null default 'open'
    check (state in ('open', 'resolved')),
  first_detected_at timestamptz not null default clock_timestamp(),
  last_detected_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete restrict,
  resolution_note text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint delivery_provider_integrity_cases_resolution_shape_check
    check (
      (state = 'open' and resolved_at is null and resolved_by is null and resolution_note is null)
      or
      (state = 'resolved' and resolved_at is not null and resolved_by is not null
        and resolution_note is not null and char_length(btrim(resolution_note)) between 12 and 2000)
    ),
  constraint delivery_provider_integrity_cases_recipient_anomaly_unique
    unique (recipient_email, anomaly_type)
);

create index delivery_provider_integrity_cases_state_detected_idx
  on public.delivery_provider_integrity_cases (state, last_detected_at desc);

create table public.delivery_provider_integrity_conflict_evidence (
  evidence_id bigint generated always as identity primary key,
  conflict_id bigint not null
    references public.delivery_provider_integrity_cases(conflict_id) on delete restrict,
  recipient_email text not null
    check (
      char_length(recipient_email) between 3 and 320
      and recipient_email = lower(btrim(recipient_email))
      and recipient_email !~ '[[:space:][:cntrl:]]'
      and position('@' in recipient_email) > 1
    ),
  event_id text not null check (char_length(event_id) between 1 and 255),
  related_event_id text
    references public.delivery_provider_events(event_id) on delete restrict,
  event_type text not null
    check (event_type in (
      'email.sent',
      'email.delivered',
      'email.delivery_delayed',
      'email.bounced',
      'email.complained',
      'email.suppressed',
      'email.failed',
      'suppression.added',
      'suppression.removed'
    )),
  provider_email_id text,
  provider_suppression_id text,
  provider_created_at timestamptz,
  bounce_type text
    check (bounce_type is null or bounce_type in ('Permanent', 'Transient', 'Unknown')),
  failure_class text
    check (failure_class is null or failure_class in (
      'invalid_recipient',
      'provider_authentication',
      'domain_verification',
      'quota_exceeded',
      'content_rejected',
      'unknown'
    )),
  suppression_reason text
    check (suppression_reason is null or suppression_reason in (
      'previous_bounce',
      'previous_complaint',
      'provider_suppressed'
    )),
  suppression_origin text
    check (suppression_origin is null or suppression_origin in ('bounce', 'complaint', 'manual')),
  suppression_source_id text,
  suppression_created_at timestamptz,
  payload_fingerprint text
    check (payload_fingerprint is null or payload_fingerprint ~ '^[0-9a-f]{64}$'),
  stored_event_id text not null
    references public.delivery_provider_events(event_id) on delete restrict,
  stored_recipient_email text not null
    check (
      char_length(stored_recipient_email) between 3 and 320
      and stored_recipient_email = lower(btrim(stored_recipient_email))
      and stored_recipient_email !~ '[[:space:][:cntrl:]]'
      and position('@' in stored_recipient_email) > 1
    ),
  evidence_source text not null
    check (evidence_source in ('provider_rpc', 'legacy_anomaly_backfill')),
  observed_at timestamptz not null default clock_timestamp(),
  constraint delivery_provider_integrity_conflict_evidence_event_shape_check
    check (
      (event_type in ('suppression.added', 'suppression.removed')
        and provider_email_id is null and provider_suppression_id is not null)
      or
      (event_type not in ('suppression.added', 'suppression.removed')
        and provider_email_id is not null and provider_suppression_id is null)
    )
);

create index delivery_provider_integrity_conflict_evidence_case_order_idx
  on public.delivery_provider_integrity_conflict_evidence (conflict_id, observed_at desc, evidence_id desc);

-- A repeated signed payload is the same evidence. Fingerprint-less legacy conflicts
-- remain individually visible because their identity cannot be proven.
create unique index delivery_provider_integrity_conflict_evidence_fingerprint_idx
  on public.delivery_provider_integrity_conflict_evidence (conflict_id, payload_fingerprint)
  where payload_fingerprint is not null;

create table public.delivery_provider_integrity_conflict_history (
  history_id bigint generated always as identity primary key,
  conflict_id bigint not null
    references public.delivery_provider_integrity_cases(conflict_id) on delete restrict,
  action text not null check (action in ('resolved', 'reopened')),
  actor_id uuid references auth.users(id) on delete restrict,
  note text not null check (char_length(btrim(note)) between 12 and 2000),
  evidence_id bigint
    references public.delivery_provider_integrity_conflict_evidence(evidence_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint delivery_provider_integrity_conflict_history_actor_check
    check (
      (action = 'resolved' and actor_id is not null and evidence_id is null)
      or (action = 'reopened' and actor_id is null and evidence_id is not null)
    )
);

create index delivery_provider_integrity_conflict_history_case_order_idx
  on public.delivery_provider_integrity_conflict_history (conflict_id, created_at, history_id);

alter table public.delivery_provider_integrity_cases enable row level security;
alter table public.delivery_provider_integrity_conflict_evidence enable row level security;
alter table public.delivery_provider_integrity_conflict_history enable row level security;

revoke all privileges on table public.delivery_provider_integrity_cases
  from public, anon, authenticated, service_role;
revoke all privileges on table public.delivery_provider_integrity_conflict_evidence
  from public, anon, authenticated, service_role;
revoke all privileges on table public.delivery_provider_integrity_conflict_history
  from public, anon, authenticated, service_role;

comment on table public.delivery_provider_integrity_cases
  is 'Private recipient-scoped provider-integrity cases. Case state is mutable only through guarded internal/admin RPCs.';
comment on table public.delivery_provider_integrity_conflict_evidence
  is 'Private append-only normalized provider conflict evidence; stores fingerprints and event fields, never raw webhook bodies or diagnostics.';
comment on table public.delivery_provider_integrity_conflict_history
  is 'Private append-only resolution/reopening audit trail for provider-integrity cases.';

create or replace function public._deny_delivery_provider_integrity_audit_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $immutable$
begin
  raise exception 'Provider-integrity evidence and resolution history are append-only.'
    using errcode = '42501';
end;
$immutable$;

revoke all privileges
on function public._deny_delivery_provider_integrity_audit_mutation()
from public, anon, authenticated, service_role;

create trigger delivery_provider_integrity_conflict_evidence_immutable
before update or delete on public.delivery_provider_integrity_conflict_evidence
for each row execute function public._deny_delivery_provider_integrity_audit_mutation();

create trigger delivery_provider_integrity_conflict_history_immutable
before update or delete on public.delivery_provider_integrity_conflict_history
for each row execute function public._deny_delivery_provider_integrity_audit_mutation();

-- Preserve every historical anomaly marker that can be tied to a known recipient.
-- Earlier migrations did not retain the conflicting payload, so this backfill records
-- only the canonical event fields that actually exist and labels them as legacy evidence.
insert into public.delivery_provider_integrity_cases (
  recipient_email, anomaly_type, first_detected_at, last_detected_at
)
select
  e.recipient_email,
  a.anomaly_type,
  min(a.detected_at),
  max(a.detected_at)
from public.delivery_provider_integrity_anomalies a
join public.delivery_provider_events e on e.event_id = a.event_id
group by e.recipient_email, a.anomaly_type
on conflict (recipient_email, anomaly_type) do nothing;

insert into public.delivery_provider_integrity_conflict_evidence (
  conflict_id,
  recipient_email,
  event_id,
  related_event_id,
  event_type,
  provider_email_id,
  provider_suppression_id,
  provider_created_at,
  bounce_type,
  failure_class,
  suppression_reason,
  suppression_origin,
  suppression_source_id,
  suppression_created_at,
  payload_fingerprint,
  stored_event_id,
  stored_recipient_email,
  evidence_source,
  observed_at
)
select
  c.conflict_id,
  e.recipient_email,
  a.event_id,
  a.related_event_id,
  e.event_type,
  e.provider_email_id,
  e.provider_suppression_id,
  e.provider_created_at,
  e.bounce_type,
  e.failure_class,
  e.suppression_reason,
  e.suppression_origin,
  e.suppression_source_id,
  e.suppression_created_at,
  e.payload_fingerprint,
  stored.event_id,
  stored.recipient_email,
  'legacy_anomaly_backfill',
  a.detected_at
from public.delivery_provider_integrity_anomalies a
join public.delivery_provider_events e on e.event_id = a.event_id
join public.delivery_provider_integrity_cases c
  on c.recipient_email = e.recipient_email
 and c.anomaly_type = a.anomaly_type
join public.delivery_provider_events stored
  on stored.event_id = coalesce(a.related_event_id, a.event_id)
on conflict do nothing;

create or replace function public._record_delivery_provider_integrity_conflict(
  p_recipient_email text,
  p_event_id text,
  p_related_event_id text,
  p_anomaly_type text,
  p_event_type text,
  p_provider_email_id text,
  p_provider_suppression_id text,
  p_provider_created_at timestamptz,
  p_bounce_type text,
  p_failure_class text,
  p_suppression_reason text,
  p_suppression_origin text,
  p_suppression_source_id text,
  p_suppression_created_at timestamptz,
  p_payload_fingerprint text,
  p_stored_event_id text,
  p_stored_recipient_email text
)
returns bigint
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $record_conflict$
declare
  v_email text;
  v_now timestamptz := clock_timestamp();
  v_conflict_id bigint;
  v_evidence_id bigint;
  v_state text;
begin
  v_email := lower(btrim(p_recipient_email));
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_anomaly_type is null or p_anomaly_type not in (
      'duplicate_event_id_conflict',
      'contradictory_terminal_outcome',
      'suppression_event_timestamp_conflict',
      'provider_email_recipient_conflict',
      'provider_suppression_recipient_conflict'
    )
    or p_event_type is null or p_event_type not in (
      'email.sent', 'email.delivered', 'email.delivery_delayed', 'email.bounced',
      'email.complained', 'email.suppressed', 'email.failed',
      'suppression.added', 'suppression.removed'
    )
    or p_stored_event_id is null or char_length(p_stored_event_id) not between 1 and 255
    or p_payload_fingerprint is not null and p_payload_fingerprint !~ '^[0-9a-f]{64}$'
    or char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or p_stored_recipient_email is null
    or p_stored_recipient_email <> lower(btrim(p_stored_recipient_email)) then
    raise exception 'Invalid normalized provider-integrity conflict evidence.' using errcode = '22023';
  end if;

  insert into public.delivery_provider_integrity_cases (
    recipient_email, anomaly_type, first_detected_at, last_detected_at
  ) values (
    v_email, p_anomaly_type, v_now, v_now
  )
  on conflict (recipient_email, anomaly_type) do nothing
  returning conflict_id into v_conflict_id;

  if v_conflict_id is null then
    select c.conflict_id, c.state
      into v_conflict_id, v_state
    from public.delivery_provider_integrity_cases c
    where c.recipient_email = v_email
      and c.anomaly_type = p_anomaly_type
    for update;
  else
    select c.state into v_state
    from public.delivery_provider_integrity_cases c
    where c.conflict_id = v_conflict_id
    for update;
  end if;

  if v_conflict_id is null then
    raise exception 'Provider-integrity case could not be locked.' using errcode = 'XX000';
  end if;

  insert into public.delivery_provider_integrity_conflict_evidence (
    conflict_id,
    recipient_email,
    event_id,
    related_event_id,
    event_type,
    provider_email_id,
    provider_suppression_id,
    provider_created_at,
    bounce_type,
    failure_class,
    suppression_reason,
    suppression_origin,
    suppression_source_id,
    suppression_created_at,
    payload_fingerprint,
    stored_event_id,
    stored_recipient_email,
    evidence_source,
    observed_at
  ) values (
    v_conflict_id,
    v_email,
    p_event_id,
    p_related_event_id,
    p_event_type,
    p_provider_email_id,
    p_provider_suppression_id,
    p_provider_created_at,
    p_bounce_type,
    p_failure_class,
    p_suppression_reason,
    p_suppression_origin,
    p_suppression_source_id,
    p_suppression_created_at,
    p_payload_fingerprint,
    p_stored_event_id,
    lower(btrim(p_stored_recipient_email)),
    'provider_rpc',
    v_now
  )
  on conflict (conflict_id, payload_fingerprint)
    where payload_fingerprint is not null
    do nothing
  returning evidence_id into v_evidence_id;

  -- An identical signed payload is not new evidence and cannot reopen a case.
  if v_evidence_id is null then
    return v_conflict_id;
  end if;

  if v_state = 'resolved' then
    insert into public.delivery_provider_integrity_conflict_history (
      conflict_id, action, actor_id, note, evidence_id, created_at
    ) values (
      v_conflict_id,
      'reopened',
      null,
      'New conflicting provider evidence arrived after resolution; the prior resolution is retained in this audit history.',
      v_evidence_id,
      v_now
    );
  end if;

  update public.delivery_provider_integrity_cases
  set state = 'open',
      last_detected_at = v_now,
      resolved_at = null,
      resolved_by = null,
      resolution_note = null,
      updated_at = v_now
  where conflict_id = v_conflict_id;

  return v_conflict_id;
end;
$record_conflict$;

revoke all privileges
on function public._record_delivery_provider_integrity_conflict(text,text,text,text,text,text,text,timestamptz,text,text,text,text,text,timestamptz,text,text,text)
from public, anon, authenticated, service_role;

comment on function public._record_delivery_provider_integrity_conflict(text,text,text,text,text,text,text,timestamptz,text,text,text,text,text,timestamptz,text,text,text)
  is 'Private migration-037 helper. Call only while holding the provider RPC recipient and correlation advisory locks.';

-- Keep the prior lifecycle implementation private and call it only after acquiring
-- the same recipient-then-provider-ID transaction locks used by migration 027.
alter function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text, text
) rename to _record_delivery_provider_lifecycle_event_pre037_impl;

revoke all privileges
on function public._record_delivery_provider_lifecycle_event_pre037_impl(
  text, text, text, text, timestamptz, text, text, text, text
)
from public, anon, authenticated, service_role;

comment on function public._record_delivery_provider_lifecycle_event_pre037_impl(
  text, text, text, text, timestamptz, text, text, text, text
)
is 'Private pre-037 lifecycle RPC; preserves migration 033 cross-stream behavior and migration 029 fingerprint enforcement.';

create function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text,
  p_failure_class text,
  p_suppression_reason text,
  p_payload_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $lifecycle_037$
declare
  v_email text;
  v_existing public.delivery_provider_events%rowtype;
  v_related public.delivery_provider_events%rowtype;
  v_anomaly public.delivery_provider_integrity_anomalies%rowtype;
  v_existing_lifecycle public.delivery_provider_lifecycle%rowtype;
  v_had_lifecycle boolean := false;
  v_result boolean;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_type is null
    or p_event_type not in (
      'email.sent', 'email.delivered', 'email.delivery_delayed', 'email.bounced',
      'email.complained', 'email.suppressed', 'email.failed'
    )
    or p_provider_email_id is null
    or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320
    or p_provider_created_at is null
    or (p_payload_fingerprint is not null and p_payload_fingerprint !~ '^[0-9a-f]{64}$') then
    raise exception 'Invalid delivery provider lifecycle event.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid delivery provider recipient.' using errcode = '22023';
  end if;

  if p_event_type = 'email.bounced' then
    if p_bounce_type is null or p_bounce_type not in ('Permanent', 'Transient', 'Unknown') then
      raise exception 'Invalid delivery bounce classification.' using errcode = '22023';
    end if;
  elsif p_bounce_type is not null then
    raise exception 'Bounce classification is only valid for bounced events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.failed' then
    if p_failure_class is null or p_failure_class not in (
      'invalid_recipient', 'provider_authentication', 'domain_verification',
      'quota_exceeded', 'content_rejected', 'unknown'
    ) then
      raise exception 'Invalid normalized provider failure classification.' using errcode = '22023';
    end if;
  elsif p_failure_class is not null then
    raise exception 'Failure classification is only valid for failed events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.suppressed' then
    if p_suppression_reason is null or p_suppression_reason not in (
      'previous_bounce', 'previous_complaint', 'provider_suppressed'
    ) then
      raise exception 'Invalid normalized provider suppression reason.' using errcode = '22023';
    end if;
  elsif p_suppression_reason is not null then
    raise exception 'Suppression reason is only valid for suppressed events.' using errcode = '22023';
  end if;

  -- Lock order is a contract shared with delivery transport and migration 034:
  -- normalized recipient first, provider email ID second. Both locks last to commit.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, hashtext(p_provider_email_id));

  select e.* into v_existing
  from public.delivery_provider_events e
  where e.event_id = p_event_id
  for update;

  select l.* into v_existing_lifecycle
  from public.delivery_provider_lifecycle l
  where l.provider_email_id = p_provider_email_id
  for update;
  v_had_lifecycle := found;

  -- Migration 027 used to raise and roll back on a provider-email-ID recipient
  -- collision. Persist the rejected attempt as private evidence instead, return
  -- NULL (the webhook route maps it to retryable HTTP 503), and keep the original
  -- event/suppression state untouched.
  select e.* into v_related
  from public.delivery_provider_events e
  where e.provider_email_id = p_provider_email_id
    and e.recipient_email <> v_email
  order by e.received_at, e.event_id
  limit 1
  for update;

  if found then
    perform public._record_delivery_provider_integrity_conflict(
      v_email, p_event_id, v_related.event_id, 'provider_email_recipient_conflict',
      p_event_type, p_provider_email_id, null, p_provider_created_at,
      p_bounce_type, p_failure_class, p_suppression_reason, null, null, null,
      p_payload_fingerprint, v_related.event_id, v_related.recipient_email
    );

    update public.delivery_provider_lifecycle
    set status = 'integrity_anomaly',
        status_rank = 80,
        failure_class = null,
        updated_at = clock_timestamp()
    where provider_email_id = p_provider_email_id;

    return null;
  end if;

  v_result := public._record_delivery_provider_lifecycle_event_pre037_impl(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    v_email,
    p_provider_created_at,
    p_bounce_type,
    p_failure_class,
    p_suppression_reason,
    p_payload_fingerprint
  );

  if v_result is null then
    select a.* into v_anomaly
    from public.delivery_provider_integrity_anomalies a
    where a.event_id = p_event_id
      and a.anomaly_type in ('duplicate_event_id_conflict', 'contradictory_terminal_outcome')
    order by a.detected_at desc
    limit 1;

    if not found then
      raise exception 'Provider lifecycle conflict was not durably classified.' using errcode = 'XX000';
    end if;

    select e.* into v_existing
    from public.delivery_provider_events e
    where e.event_id = p_event_id
    for update;

    if v_anomaly.anomaly_type = 'duplicate_event_id_conflict' then
      if not found then
        raise exception 'Conflicting duplicate provider event has no canonical event row.' using errcode = 'XX000';
      end if;
      perform public._record_delivery_provider_integrity_conflict(
        v_email, p_event_id, null, v_anomaly.anomaly_type,
        p_event_type, p_provider_email_id, null, p_provider_created_at,
        p_bounce_type, p_failure_class, p_suppression_reason, null, null, null,
        p_payload_fingerprint, v_existing.event_id, v_existing.recipient_email
      );

    else
      select e.* into v_related
      from public.delivery_provider_events e
      where e.event_id = v_anomaly.related_event_id
      for update;
      if not found then
        raise exception 'Contradictory provider event has no related canonical event.' using errcode = 'XX000';
      end if;
      perform public._record_delivery_provider_integrity_conflict(
        v_email, p_event_id, v_anomaly.related_event_id, v_anomaly.anomaly_type,
        p_event_type, p_provider_email_id, null, p_provider_created_at,
        p_bounce_type, p_failure_class, p_suppression_reason, null, null, null,
        p_payload_fingerprint, v_related.event_id, v_related.recipient_email
      );

      -- The prior implementation projected the conflicting terminal event over
      -- the canonical one. Keep only the integrity status overlay and restore all
      -- previously authoritative event/timestamp/classification fields.
      if v_had_lifecycle then
        update public.delivery_provider_lifecycle
        set status = 'integrity_anomaly',
            status_rank = 80,
            provider_created_at = v_existing_lifecycle.provider_created_at,
            received_at = v_existing_lifecycle.received_at,
            event_id = v_existing_lifecycle.event_id,
            failure_class = null,
            updated_at = clock_timestamp()
        where provider_email_id = p_provider_email_id;
      end if;
    end if;
  end if;

  return v_result;
end;
$lifecycle_037$;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text, text)
from public, anon, authenticated, service_role;
grant execute
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text, text)
to service_role;
comment on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text, text)
  is 'deedlight:037:recipient-scoped-provider-integrity-evidence:v1';

-- Preserve the seven-argument legacy RPC but acquire the same locks before
-- reading its historical timestamp. The eight- and five-argument wrappers
-- continue to delegate to this guarded canonical path.
create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text default null,
  p_failure_class text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $legacy_037$
declare
  v_email text;
  v_existing_provider_created_at timestamptz;
  v_suppression_reason text;
begin
  if p_recipient_email is not null and p_provider_email_id is not null then
    v_email := lower(btrim(p_recipient_email));
    perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
    perform pg_catalog.pg_advisory_xact_lock(20261126, hashtext(p_provider_email_id));
    select e.provider_created_at into v_existing_provider_created_at
    from public.delivery_provider_events e
    where e.event_id = p_event_id
    for update;
  end if;

  if p_event_type = 'email.suppressed' then
    v_suppression_reason := 'provider_suppressed';
  end if;

  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    coalesce(v_existing_provider_created_at, p_provider_created_at, clock_timestamp()),
    p_bounce_type,
    p_failure_class,
    v_suppression_reason,
    null
  );
end;
$legacy_037$;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)
from public, anon, authenticated, service_role;
grant execute
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text)
to service_role;

-- Reassert the original eight- and five-argument trusted legacy boundaries.
revoke all privileges
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text)
from public, anon, authenticated, service_role;
grant execute
on function public.record_delivery_provider_lifecycle_event(text, text, text, text, timestamptz, text, text, text)
to service_role;

revoke all privileges
on function public.record_delivery_provider_event(text, text, text, text, text)
from public, anon, authenticated, service_role;
grant execute
on function public.record_delivery_provider_event(text, text, text, text, text)
to service_role;

-- Keep the previous suppression-list implementation private. The wrapper below
-- captures duplicate IDs, equal-timestamp conflicts and cross-recipient ID reuse.
alter function public.record_delivery_provider_suppression_event(
  text, text, text, text, text, text, timestamptz, timestamptz, text
) rename to _record_delivery_provider_suppression_event_pre037_impl;

revoke all privileges
on function public._record_delivery_provider_suppression_event_pre037_impl(
  text, text, text, text, text, text, timestamptz, timestamptz, text
)
from public, anon, authenticated, service_role;

comment on function public._record_delivery_provider_suppression_event_pre037_impl(
  text, text, text, text, text, text, timestamptz, timestamptz, text
)
is 'Private pre-037 suppression-list RPC; preserves migration 034 event ordering and complaint/bounce holds.';

create function public.record_delivery_provider_suppression_event(
  p_event_id text,
  p_event_type text,
  p_provider_suppression_id text,
  p_recipient_email text,
  p_suppression_origin text,
  p_suppression_source_id text,
  p_suppression_created_at timestamptz,
  p_provider_created_at timestamptz,
  p_payload_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $suppression_037$
declare
  v_email text;
  v_related public.delivery_provider_events%rowtype;
  v_existing public.delivery_provider_events%rowtype;
  v_anomaly public.delivery_provider_integrity_anomalies%rowtype;
  v_result boolean;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_id !~ '^[[:graph:]]+$'
    or p_event_type is null or p_event_type not in ('suppression.added', 'suppression.removed')
    or p_provider_suppression_id is null
    or char_length(p_provider_suppression_id) not between 1 and 255
    or p_provider_suppression_id !~ '^[[:graph:]]+$'
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320
    or p_suppression_origin is null
    or p_suppression_origin not in ('bounce', 'complaint', 'manual')
    or (p_suppression_source_id is not null
      and (char_length(p_suppression_source_id) not between 1 and 255
        or p_suppression_source_id !~ '^[[:graph:]]+$'))
    or p_suppression_created_at is null
    or p_provider_created_at is null
    or p_payload_fingerprint is null
    or p_payload_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid provider suppression event.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid provider suppression recipient.' using errcode = '22023';
  end if;

  -- Match migration 034: normalized recipient first, suppression ID second.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261127, hashtext(p_provider_suppression_id));

  select e.* into v_existing
  from public.delivery_provider_events e
  where e.event_id = p_event_id
  for update;

  select e.* into v_related
  from public.delivery_provider_events e
  where e.provider_suppression_id = p_provider_suppression_id
    and e.recipient_email <> v_email
  order by e.received_at, e.event_id
  limit 1
  for update;

  if found then
    perform public._record_delivery_provider_integrity_conflict(
      v_email, p_event_id, v_related.event_id, 'provider_suppression_recipient_conflict',
      p_event_type, null, p_provider_suppression_id, p_provider_created_at,
      null, null, null, p_suppression_origin, p_suppression_source_id,
      p_suppression_created_at, p_payload_fingerprint,
      v_related.event_id, v_related.recipient_email
    );
    return null;
  end if;

  v_result := public._record_delivery_provider_suppression_event_pre037_impl(
    p_event_id,
    p_event_type,
    p_provider_suppression_id,
    v_email,
    p_suppression_origin,
    p_suppression_source_id,
    p_suppression_created_at,
    p_provider_created_at,
    p_payload_fingerprint
  );

  if v_result is null or v_result is true then
    select a.* into v_anomaly
    from public.delivery_provider_integrity_anomalies a
    where a.event_id = p_event_id
      and a.anomaly_type in ('duplicate_event_id_conflict', 'suppression_event_timestamp_conflict')
    order by a.detected_at desc
    limit 1;

    if found then
      select e.* into v_existing
      from public.delivery_provider_events e
      where e.event_id = coalesce(v_anomaly.related_event_id, v_anomaly.event_id)
      for update;

      if not found then
        raise exception 'Conflicting suppression event has no canonical event row.' using errcode = 'XX000';
      end if;

      perform public._record_delivery_provider_integrity_conflict(
        v_email,
        p_event_id,
        v_anomaly.related_event_id,
        v_anomaly.anomaly_type,
        p_event_type,
        null,
        p_provider_suppression_id,
        p_provider_created_at,
        null,
        null,
        null,
        p_suppression_origin,
        p_suppression_source_id,
        p_suppression_created_at,
        p_payload_fingerprint,
        v_existing.event_id,
        v_existing.recipient_email
      );
    elsif v_result is null then
      raise exception 'Provider suppression conflict was not durably classified.' using errcode = 'XX000';
    end if;
  end if;

  return v_result;
end;
$suppression_037$;

revoke all privileges
on function public.record_delivery_provider_suppression_event(text, text, text, text, text, text, timestamptz, timestamptz, text)
from public, anon, authenticated, service_role;
grant execute
on function public.record_delivery_provider_suppression_event(text, text, text, text, text, text, timestamptz, timestamptz, text)
to service_role;
comment on function public.record_delivery_provider_suppression_event(text, text, text, text, text, text, timestamptz, timestamptz, text)
  is 'deedlight:037:recipient-scoped-provider-suppression-integrity-evidence:v1';

create function public.admin_list_delivery_provider_integrity_conflicts(
  p_state text default 'open',
  p_limit integer default 100
)
returns table (
  conflict_id bigint,
  recipient_email text,
  anomaly_type text,
  state text,
  first_detected_at timestamptz,
  last_detected_at timestamptz,
  evidence_count bigint,
  resolved_at timestamptz,
  resolved_by uuid,
  resolution_note text
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $admin_list$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_state is null or p_state not in ('open', 'resolved', 'all')
    or p_limit is null or p_limit not between 1 and 200 then
    raise exception 'Invalid provider-integrity conflict list parameters.' using errcode = '22023';
  end if;

  return query
  select
    c.conflict_id,
    c.recipient_email,
    c.anomaly_type,
    c.state,
    c.first_detected_at,
    c.last_detected_at,
    count(e.evidence_id)::bigint,
    c.resolved_at,
    c.resolved_by,
    c.resolution_note
  from public.delivery_provider_integrity_cases c
  left join public.delivery_provider_integrity_conflict_evidence e
    on e.conflict_id = c.conflict_id
  where p_state = 'all' or c.state = p_state
  group by c.conflict_id
  order by c.last_detected_at desc, c.conflict_id desc
  limit p_limit;
end;
$admin_list$;

revoke all privileges
on function public.admin_list_delivery_provider_integrity_conflicts(text, integer)
from public, anon, authenticated, service_role;
grant execute
on function public.admin_list_delivery_provider_integrity_conflicts(text, integer)
to authenticated;

create function public.admin_list_delivery_provider_integrity_evidence(
  p_conflict_id bigint,
  p_limit integer default 100
)
returns table (
  evidence_id bigint,
  observed_at timestamptz,
  recipient_email text,
  event_id text,
  related_event_id text,
  event_type text,
  provider_email_id text,
  provider_suppression_id text,
  provider_created_at timestamptz,
  bounce_type text,
  failure_class text,
  suppression_reason text,
  suppression_origin text,
  suppression_source_id text,
  suppression_created_at timestamptz,
  payload_fingerprint text,
  stored_event_id text,
  stored_recipient_email text,
  evidence_source text
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $admin_evidence$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_conflict_id is null or p_limit is null or p_limit not between 1 and 500 then
    raise exception 'Invalid provider-integrity evidence list parameters.' using errcode = '22023';
  end if;

  return query
  select
    e.evidence_id,
    e.observed_at,
    e.recipient_email,
    e.event_id,
    e.related_event_id,
    e.event_type,
    e.provider_email_id,
    e.provider_suppression_id,
    e.provider_created_at,
    e.bounce_type,
    e.failure_class,
    e.suppression_reason,
    e.suppression_origin,
    e.suppression_source_id,
    e.suppression_created_at,
    e.payload_fingerprint,
    e.stored_event_id,
    e.stored_recipient_email,
    e.evidence_source
  from public.delivery_provider_integrity_conflict_evidence e
  where e.conflict_id = p_conflict_id
  order by e.observed_at desc, e.evidence_id desc
  limit p_limit;
end;
$admin_evidence$;

revoke all privileges
on function public.admin_list_delivery_provider_integrity_evidence(bigint, integer)
from public, anon, authenticated, service_role;
grant execute
on function public.admin_list_delivery_provider_integrity_evidence(bigint, integer)
to authenticated;

create function public.admin_list_delivery_provider_integrity_history(
  p_conflict_id bigint,
  p_limit integer default 100
)
returns table (
  history_id bigint,
  action text,
  actor_id uuid,
  note text,
  evidence_id bigint,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $admin_history$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_conflict_id is null or p_limit is null or p_limit not between 1 and 500 then
    raise exception 'Invalid provider-integrity history list parameters.' using errcode = '22023';
  end if;

  return query
  select h.history_id, h.action, h.actor_id, h.note, h.evidence_id, h.created_at
  from public.delivery_provider_integrity_conflict_history h
  where h.conflict_id = p_conflict_id
  order by h.created_at, h.history_id
  limit p_limit;
end;
$admin_history$;

revoke all privileges
on function public.admin_list_delivery_provider_integrity_history(bigint, integer)
from public, anon, authenticated, service_role;
grant execute
on function public.admin_list_delivery_provider_integrity_history(bigint, integer)
to authenticated;

create function public.admin_resolve_delivery_provider_integrity_conflict(
  p_conflict_id bigint,
  p_resolution_note text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $admin_resolve$
declare
  v_case public.delivery_provider_integrity_cases%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_conflict_id is null or p_resolution_note is null
    or char_length(btrim(p_resolution_note)) not between 12 and 2000 then
    raise exception 'A conflict ID and meaningful resolution note are required.' using errcode = '22023';
  end if;

  select c.* into v_case
  from public.delivery_provider_integrity_cases c
  where c.conflict_id = p_conflict_id
  for update;

  if not found then
    raise exception 'Provider-integrity conflict case was not found.' using errcode = '22023';
  end if;
  if v_case.state = 'resolved' then
    return false;
  end if;

  insert into public.delivery_provider_integrity_conflict_history (
    conflict_id, action, actor_id, note, evidence_id, created_at
  ) values (
    v_case.conflict_id,
    'resolved',
    auth.uid(),
    btrim(p_resolution_note),
    null,
    v_now
  );

  update public.delivery_provider_integrity_cases
  set state = 'resolved',
      resolved_at = v_now,
      resolved_by = auth.uid(),
      resolution_note = btrim(p_resolution_note),
      updated_at = v_now
  where conflict_id = v_case.conflict_id;

  return true;
end;
$admin_resolve$;

revoke all privileges
on function public.admin_resolve_delivery_provider_integrity_conflict(bigint, text)
from public, anon, authenticated, service_role;
grant execute
on function public.admin_resolve_delivery_provider_integrity_conflict(bigint, text)
to authenticated;

comment on function public.admin_list_delivery_provider_integrity_conflicts(text, integer)
  is 'Admin-only private listing of recipient-scoped provider-integrity cases.';
comment on function public.admin_list_delivery_provider_integrity_evidence(bigint, integer)
  is 'Admin-only listing of normalized provider-integrity evidence; never exposes raw webhook bodies.';
comment on function public.admin_list_delivery_provider_integrity_history(bigint, integer)
  is 'Admin-only listing of immutable provider-integrity resolution/reopening history.';
comment on function public.admin_resolve_delivery_provider_integrity_conflict(bigint, text)
  is 'Admin-only resolution transition. New distinct conflict evidence automatically reopens the case and preserves this history.';

notify pgrst, 'reload schema';
commit;


-- Forward-only hardening for provider event identity serialization and paginated admin review.
-- Migrations 036 and 037 remain immutable. Unexpected source/ACL/configuration drift aborts atomically.
begin;

do $migration_038_preflight$
declare
  v_crypto_schema text;
  v_expected record;
  v_oid oid;
  v_source text;
  v_source_hash text;
  v_security_definer boolean;
  v_config text[];
begin
  if to_regclass('public.delivery_provider_integrity_cases') is null
    or to_regclass('public.delivery_provider_integrity_conflict_evidence') is null
    or to_regclass('public.delivery_provider_integrity_conflict_history') is null
    or to_regprocedure('public.is_admin()') is null then
    raise exception 'Migration 038 requires the complete migration-037 provider-integrity and administrator contract.';
  end if;

  select n.nspname into v_crypto_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_crypto_schema is null then
    raise exception 'Migration 038 requires pgcrypto for exact provider RPC source attestation.';
  end if;

  if to_regprocedure('public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamptz,bigint)') is not null
    or to_regprocedure('public.admin_get_delivery_provider_integrity_conflict(bigint)') is not null
    or to_regprocedure('public.admin_list_delivery_provider_integrity_evidence_page(bigint,integer,timestamptz,bigint)') is not null
    or to_regprocedure('public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)') is not null
    or to_regclass('public.delivery_provider_integrity_cases_state_cursor_idx') is not null
    or to_regclass('public.delivery_provider_integrity_conflict_history_reopened_cursor_idx') is not null then
    raise exception 'Migration 038 refuses pre-existing pagination objects with an unknown origin.';
  end if;

  for v_expected in
    select * from (values
      ('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)', '4b8c7b9c0ea7af1cea5e3d34ed3d1a21cbd5c17958a4d89f8c857cfa38f7581b', 'search_path=public, auth, pg_temp', 'service_role'),
      ('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)', '9be2593c7187516b0ca4a413f9443b02fd8f4ea9b02f539f1b5b504eb53eb694', 'search_path=public, auth, pg_temp', 'service_role'),
      ('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)', 'abca9b6c4ccd2e51dc7b0523d18b4e6931a082baa3b260fe308b78e0e7563536', 'search_path=public, auth, pg_temp', 'service_role'),
      ('public.record_delivery_provider_event(text,text,text,text,text)', '5896bffd634d825be05a5e8bdf78c6b0bae2ded24591b283fea764a74cb5343b', 'search_path=public, auth, pg_temp', 'service_role'),
      ('public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)', '5e3eb059c12dd9caa50a060447fd09d3afc217142bd58e94d1afd5a1cbbb62a6', 'search_path=public, auth, pg_temp', 'service_role'),
      ('public._record_delivery_provider_integrity_conflict(text,text,text,text,text,text,text,timestamptz,text,text,text,text,text,timestamptz,text,text,text)', 'efc5a85b3e0ca1ee32f38e12f5f2538a135ee08203f79d1c9d2e57a4d0950871', 'search_path=public, auth, pg_temp', 'private'),
      ('public._record_delivery_provider_lifecycle_event_pre037_impl(text,text,text,text,timestamptz,text,text,text,text)', '68bf0948c041e70670499811334bee6fc4546254d0597d38b880e8aad18c7241', 'search_path=public, auth, pg_temp', 'private'),
      ('public._record_delivery_provider_suppression_event_pre037_impl(text,text,text,text,text,text,timestamptz,timestamptz,text)', 'd67c0f2da59cd87e769938a9c86878791080a2e9597409113796be078e87e64a', 'search_path=public, auth, pg_temp', 'private'),
      ('public._deny_delivery_provider_integrity_audit_mutation()', '2dff07aeeb597e3d8e8bca99108a4df8d1538161ab0b0e4c34e47d71790d96c9', 'search_path=pg_catalog', 'private'),
      ('public.admin_list_delivery_provider_integrity_conflicts(text,integer)', 'c77643294b78d01bdad25cce4cfc0e7bac10f7d12f9898c2b169fa012add6bc0', 'search_path=public, auth, pg_temp', 'authenticated'),
      ('public.admin_list_delivery_provider_integrity_evidence(bigint,integer)', '72609677508aa59960571a22c39b4b6cbbb0bcf3106339b995b5133a863d4b3f', 'search_path=public, auth, pg_temp', 'authenticated'),
      ('public.admin_list_delivery_provider_integrity_history(bigint,integer)', 'c818efdd81bc98ad96adb7439ee70024cb101fbfcaa9cfe557bbf3c2dfe233a4', 'search_path=public, auth, pg_temp', 'authenticated'),
      ('public.admin_resolve_delivery_provider_integrity_conflict(bigint,text)', '53de2fc64a9fa634efe33e18b7f639a474d9f359a2c57066b9bac760aa9b16e1', 'search_path=public, auth, pg_temp', 'authenticated')
    ) as expected(signature, source_sha256, expected_search_path, access_role)
  loop
    v_oid := to_regprocedure(v_expected.signature);
    if v_oid is null then
      raise exception 'Migration 038 requires reviewed function signature %.', v_expected.signature;
    end if;

    select p.prosrc, p.prosecdef, p.proconfig
      into v_source, v_security_definer, v_config
    from pg_catalog.pg_proc p
    where p.oid = v_oid;

    if v_security_definer is distinct from true
      or v_config is distinct from array[v_expected.expected_search_path]::text[] then
      raise exception 'Migration 038 rejected SECURITY DEFINER/search_path drift in %.', v_expected.signature;
    end if;

    execute format(
      'select encode(%I.digest(convert_to($1, ''UTF8''), ''sha256''), ''hex'')',
      v_crypto_schema
    ) into v_source_hash using v_source;

    if v_source_hash is distinct from v_expected.source_sha256 then
      raise exception 'Migration 038 rejected unreviewed function source for %.', v_expected.signature;
    end if;

    if v_expected.access_role = 'service_role' then
      if has_function_privilege('anon', v_oid, 'EXECUTE')
        or has_function_privilege('authenticated', v_oid, 'EXECUTE')
        or not has_function_privilege('service_role', v_oid, 'EXECUTE') then
        raise exception 'Migration 038 rejected non-service provider RPC grants for %.', v_expected.signature;
      end if;
    elsif v_expected.access_role = 'authenticated' then
      if has_function_privilege('anon', v_oid, 'EXECUTE')
        or has_function_privilege('service_role', v_oid, 'EXECUTE')
        or not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
        raise exception 'Migration 038 rejected administrator RPC grants for %.', v_expected.signature;
      end if;
    elsif v_expected.access_role = 'private' then
      if has_function_privilege('anon', v_oid, 'EXECUTE')
        or has_function_privilege('authenticated', v_oid, 'EXECUTE')
        or has_function_privilege('service_role', v_oid, 'EXECUTE') then
        raise exception 'Migration 038 rejected private helper grants for %.', v_expected.signature;
      end if;
    else
      raise exception 'Migration 038 has an invalid preflight access contract.';
    end if;
  end loop;

  if not (select relrowsecurity from pg_catalog.pg_class where oid='public.delivery_provider_integrity_cases'::regclass)
    or not (select relrowsecurity from pg_catalog.pg_class where oid='public.delivery_provider_integrity_conflict_evidence'::regclass)
    or not (select relrowsecurity from pg_catalog.pg_class where oid='public.delivery_provider_integrity_conflict_history'::regclass)
    or has_table_privilege('anon','public.delivery_provider_integrity_cases','SELECT')
    or has_table_privilege('authenticated','public.delivery_provider_integrity_cases','SELECT')
    or has_table_privilege('service_role','public.delivery_provider_integrity_cases','SELECT')
    or has_table_privilege('anon','public.delivery_provider_integrity_conflict_evidence','SELECT')
    or has_table_privilege('authenticated','public.delivery_provider_integrity_conflict_evidence','SELECT')
    or has_table_privilege('service_role','public.delivery_provider_integrity_conflict_evidence','SELECT')
    or has_table_privilege('anon','public.delivery_provider_integrity_conflict_history','SELECT')
    or has_table_privilege('authenticated','public.delivery_provider_integrity_conflict_history','SELECT')
    or has_table_privilege('service_role','public.delivery_provider_integrity_conflict_history','SELECT') then
    raise exception 'Migration 038 rejected provider-integrity table privacy drift.';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid='public.delivery_provider_integrity_conflict_evidence'::regclass
      and tgname='delivery_provider_integrity_conflict_evidence_immutable'
      and tgfoid=to_regprocedure('public._deny_delivery_provider_integrity_audit_mutation()')
      and not tgisinternal
  ) or not exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid='public.delivery_provider_integrity_conflict_history'::regclass
      and tgname='delivery_provider_integrity_conflict_history_immutable'
      and tgfoid=to_regprocedure('public._deny_delivery_provider_integrity_audit_mutation()')
      and not tgisinternal
  ) then
    raise exception 'Migration 038 requires both append-only audit triggers.';
  end if;
end;
$migration_038_preflight$;

-- Indexes match the keyset order and make the latest reopening independently discoverable.
create index delivery_provider_integrity_cases_state_cursor_idx
  on public.delivery_provider_integrity_cases (state, last_detected_at desc, conflict_id desc);

create index delivery_provider_integrity_conflict_history_reopened_cursor_idx
  on public.delivery_provider_integrity_conflict_history (conflict_id, created_at desc, history_id desc)
  where action = 'reopened';

create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text,
  p_failure_class text,
  p_suppression_reason text,
  p_payload_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $lifecycle_037$
declare
  v_email text;
  v_existing public.delivery_provider_events%rowtype;
  v_related public.delivery_provider_events%rowtype;
  v_anomaly public.delivery_provider_integrity_anomalies%rowtype;
  v_existing_lifecycle public.delivery_provider_lifecycle%rowtype;
  v_had_lifecycle boolean := false;
  v_result boolean;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_type is null
    or p_event_type not in (
      'email.sent', 'email.delivered', 'email.delivery_delayed', 'email.bounced',
      'email.complained', 'email.suppressed', 'email.failed'
    )
    or p_provider_email_id is null
    or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320
    or p_provider_created_at is null
    or (p_payload_fingerprint is not null and p_payload_fingerprint !~ '^[0-9a-f]{64}$') then
    raise exception 'Invalid delivery provider lifecycle event.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid delivery provider recipient.' using errcode = '22023';
  end if;

  if p_event_type = 'email.bounced' then
    if p_bounce_type is null or p_bounce_type not in ('Permanent', 'Transient', 'Unknown') then
      raise exception 'Invalid delivery bounce classification.' using errcode = '22023';
    end if;
  elsif p_bounce_type is not null then
    raise exception 'Bounce classification is only valid for bounced events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.failed' then
    if p_failure_class is null or p_failure_class not in (
      'invalid_recipient', 'provider_authentication', 'domain_verification',
      'quota_exceeded', 'content_rejected', 'unknown'
    ) then
      raise exception 'Invalid normalized provider failure classification.' using errcode = '22023';
    end if;
  elsif p_failure_class is not null then
    raise exception 'Failure classification is only valid for failed events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.suppressed' then
    if p_suppression_reason is null or p_suppression_reason not in (
      'previous_bounce', 'previous_complaint', 'provider_suppressed'
    ) then
      raise exception 'Invalid normalized provider suppression reason.' using errcode = '22023';
    end if;
  elsif p_suppression_reason is not null then
    raise exception 'Suppression reason is only valid for suppressed events.' using errcode = '22023';
  end if;

  -- Global order: event identity, normalized recipient, then provider correlation.
  perform pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext(p_event_id));
  perform pg_catalog.pg_advisory_xact_lock(20261119, pg_catalog.hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, pg_catalog.hashtext(p_provider_email_id));

  select e.* into v_existing
  from public.delivery_provider_events e
  where e.event_id = p_event_id
  for update;

  select l.* into v_existing_lifecycle
  from public.delivery_provider_lifecycle l
  where l.provider_email_id = p_provider_email_id
  for update;
  v_had_lifecycle := found;

  -- Migration 027 used to raise and roll back on a provider-email-ID recipient
  -- collision. Persist the rejected attempt as private evidence instead, return
  -- NULL (the webhook route maps it to retryable HTTP 503), and keep the original
  -- event/suppression state untouched.
  select e.* into v_related
  from public.delivery_provider_events e
  where e.provider_email_id = p_provider_email_id
    and e.recipient_email <> v_email
  order by e.received_at, e.event_id
  limit 1
  for update;

  if found then
    perform public._record_delivery_provider_integrity_conflict(
      v_email, p_event_id, v_related.event_id, 'provider_email_recipient_conflict',
      p_event_type, p_provider_email_id, null, p_provider_created_at,
      p_bounce_type, p_failure_class, p_suppression_reason, null, null, null,
      p_payload_fingerprint, v_related.event_id, v_related.recipient_email
    );

    update public.delivery_provider_lifecycle
    set status = 'integrity_anomaly',
        status_rank = 80,
        failure_class = null,
        updated_at = clock_timestamp()
    where provider_email_id = p_provider_email_id;

    return null;
  end if;

  v_result := public._record_delivery_provider_lifecycle_event_pre037_impl(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    v_email,
    p_provider_created_at,
    p_bounce_type,
    p_failure_class,
    p_suppression_reason,
    p_payload_fingerprint
  );

  if v_result is null then
    select a.* into v_anomaly
    from public.delivery_provider_integrity_anomalies a
    where a.event_id = p_event_id
      and a.anomaly_type in ('duplicate_event_id_conflict', 'contradictory_terminal_outcome')
    order by a.detected_at desc
    limit 1;

    if not found then
      raise exception 'Provider lifecycle conflict was not durably classified.' using errcode = 'XX000';
    end if;

    select e.* into v_existing
    from public.delivery_provider_events e
    where e.event_id = p_event_id
    for update;

    if v_anomaly.anomaly_type = 'duplicate_event_id_conflict' then
      if not found then
        raise exception 'Conflicting duplicate provider event has no canonical event row.' using errcode = 'XX000';
      end if;
      perform public._record_delivery_provider_integrity_conflict(
        v_email, p_event_id, null, v_anomaly.anomaly_type,
        p_event_type, p_provider_email_id, null, p_provider_created_at,
        p_bounce_type, p_failure_class, p_suppression_reason, null, null, null,
        p_payload_fingerprint, v_existing.event_id, v_existing.recipient_email
      );

    else
      select e.* into v_related
      from public.delivery_provider_events e
      where e.event_id = v_anomaly.related_event_id
      for update;
      if not found then
        raise exception 'Contradictory provider event has no related canonical event.' using errcode = 'XX000';
      end if;
      perform public._record_delivery_provider_integrity_conflict(
        v_email, p_event_id, v_anomaly.related_event_id, v_anomaly.anomaly_type,
        p_event_type, p_provider_email_id, null, p_provider_created_at,
        p_bounce_type, p_failure_class, p_suppression_reason, null, null, null,
        p_payload_fingerprint, v_related.event_id, v_related.recipient_email
      );

      -- The prior implementation projected the conflicting terminal event over
      -- the canonical one. Keep only the integrity status overlay and restore all
      -- previously authoritative event/timestamp/classification fields.
      if v_had_lifecycle then
        update public.delivery_provider_lifecycle
        set status = 'integrity_anomaly',
            status_rank = 80,
            provider_created_at = v_existing_lifecycle.provider_created_at,
            received_at = v_existing_lifecycle.received_at,
            event_id = v_existing_lifecycle.event_id,
            failure_class = null,
            updated_at = clock_timestamp()
        where provider_email_id = p_provider_email_id;
      end if;
    end if;
  end if;

  return v_result;
end;
$lifecycle_037$;

create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text default null,
  p_failure_class text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $legacy_037$
declare
  v_email text;
  v_existing_provider_created_at timestamptz;
  v_suppression_reason text;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_provider_email_id is null or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null or char_length(p_recipient_email) > 320 then
    raise exception 'Invalid legacy delivery provider event identity.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    raise exception 'Invalid legacy delivery provider recipient.' using errcode = '22023';
  end if;

  -- The legacy timestamp lookup must happen only after the global event lock.
  perform pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext(p_event_id));
  perform pg_catalog.pg_advisory_xact_lock(20261119, pg_catalog.hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, pg_catalog.hashtext(p_provider_email_id));

  select e.provider_created_at into v_existing_provider_created_at
  from public.delivery_provider_events e
  where e.event_id = p_event_id
  for update;

  if p_event_type = 'email.suppressed' then
    v_suppression_reason := 'provider_suppressed';
  end if;

  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    coalesce(v_existing_provider_created_at, p_provider_created_at, clock_timestamp()),
    p_bounce_type,
    p_failure_class,
    v_suppression_reason,
    null
  );
end;
$legacy_037$; then
    raise exception 'Invalid legacy delivery provider recipient.' using errcode = '22023';
  end if;

  -- The legacy timestamp lookup must happen only after the global event lock.
  perform pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext(p_event_id));
  perform pg_catalog.pg_advisory_xact_lock(20261119, pg_catalog.hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, pg_catalog.hashtext(p_provider_email_id));

  select e.provider_created_at into v_existing_provider_created_at
  from public.delivery_provider_events e
  where e.event_id = p_event_id
  for update;

  if p_event_type = 'email.suppressed' then
    v_suppression_reason := 'provider_suppressed';
  end if;

  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    coalesce(v_existing_provider_created_at, p_provider_created_at, clock_timestamp()),
    p_bounce_type,
    p_failure_class,
    v_suppression_reason,
    null
  );
end;
$legacy_037$;

create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text,
  p_failure_class text,
  p_suppression_reason text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $compat_038$
declare
  v_email text;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_provider_email_id is null or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null or char_length(p_recipient_email) > 320 then
    raise exception 'Invalid legacy delivery provider event identity.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    raise exception 'Invalid legacy delivery provider recipient.' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext(p_event_id));
  perform pg_catalog.pg_advisory_xact_lock(20261119, pg_catalog.hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, pg_catalog.hashtext(p_provider_email_id));

  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    v_email,
    p_provider_created_at,
    p_bounce_type,
    p_failure_class,
    p_suppression_reason,
    null
  );
end;
$compat_038$;

create or replace function public.record_delivery_provider_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_bounce_type text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $legacy_038$
declare
  v_email text;
begin
  if p_event_type not in ('email.bounced', 'email.complained', 'email.suppressed') then
    raise exception 'Unsupported legacy provider event type.' using errcode = '22023';
  end if;
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_provider_email_id is null or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null or char_length(p_recipient_email) > 320 then
    raise exception 'Invalid legacy delivery provider event identity.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    raise exception 'Invalid legacy delivery provider recipient.' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext(p_event_id));
  perform pg_catalog.pg_advisory_xact_lock(20261119, pg_catalog.hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, pg_catalog.hashtext(p_provider_email_id));

  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    v_email,
    clock_timestamp(),
    p_bounce_type,
    null
  );
end;
$legacy_038$;

create or replace function public.record_delivery_provider_suppression_event(
  p_event_id text,
  p_event_type text,
  p_provider_suppression_id text,
  p_recipient_email text,
  p_suppression_origin text,
  p_suppression_source_id text,
  p_suppression_created_at timestamptz,
  p_provider_created_at timestamptz,
  p_payload_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $suppression_037$
declare
  v_email text;
  v_related public.delivery_provider_events%rowtype;
  v_existing public.delivery_provider_events%rowtype;
  v_anomaly public.delivery_provider_integrity_anomalies%rowtype;
  v_result boolean;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_id !~ '^[[:graph:]]+$'
    or p_event_type is null or p_event_type not in ('suppression.added', 'suppression.removed')
    or p_provider_suppression_id is null
    or char_length(p_provider_suppression_id) not between 1 and 255
    or p_provider_suppression_id !~ '^[[:graph:]]+$'
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320
    or p_suppression_origin is null
    or p_suppression_origin not in ('bounce', 'complaint', 'manual')
    or (p_suppression_source_id is not null
      and (char_length(p_suppression_source_id) not between 1 and 255
        or p_suppression_source_id !~ '^[[:graph:]]+$'))
    or p_suppression_created_at is null
    or p_provider_created_at is null
    or p_payload_fingerprint is null
    or p_payload_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid provider suppression event.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid provider suppression recipient.' using errcode = '22023';
  end if;

  -- Global order: event identity, normalized recipient, then suppression correlation.
  perform pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext(p_event_id));
  perform pg_catalog.pg_advisory_xact_lock(20261119, pg_catalog.hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261127, pg_catalog.hashtext(p_provider_suppression_id));

  select e.* into v_existing
  from public.delivery_provider_events e
  where e.event_id = p_event_id
  for update;

  select e.* into v_related
  from public.delivery_provider_events e
  where e.provider_suppression_id = p_provider_suppression_id
    and e.recipient_email <> v_email
  order by e.received_at, e.event_id
  limit 1
  for update;

  if found then
    perform public._record_delivery_provider_integrity_conflict(
      v_email, p_event_id, v_related.event_id, 'provider_suppression_recipient_conflict',
      p_event_type, null, p_provider_suppression_id, p_provider_created_at,
      null, null, null, p_suppression_origin, p_suppression_source_id,
      p_suppression_created_at, p_payload_fingerprint,
      v_related.event_id, v_related.recipient_email
    );
    return null;
  end if;

  v_result := public._record_delivery_provider_suppression_event_pre037_impl(
    p_event_id,
    p_event_type,
    p_provider_suppression_id,
    v_email,
    p_suppression_origin,
    p_suppression_source_id,
    p_suppression_created_at,
    p_provider_created_at,
    p_payload_fingerprint
  );

  if v_result is null or v_result is true then
    select a.* into v_anomaly
    from public.delivery_provider_integrity_anomalies a
    where a.event_id = p_event_id
      and a.anomaly_type in ('duplicate_event_id_conflict', 'suppression_event_timestamp_conflict')
    order by a.detected_at desc
    limit 1;

    if found then
      select e.* into v_existing
      from public.delivery_provider_events e
      where e.event_id = coalesce(v_anomaly.related_event_id, v_anomaly.event_id)
      for update;

      if not found then
        raise exception 'Conflicting suppression event has no canonical event row.' using errcode = 'XX000';
      end if;

      perform public._record_delivery_provider_integrity_conflict(
        v_email,
        p_event_id,
        v_anomaly.related_event_id,
        v_anomaly.anomaly_type,
        p_event_type,
        null,
        p_provider_suppression_id,
        p_provider_created_at,
        null,
        null,
        null,
        p_suppression_origin,
        p_suppression_source_id,
        p_suppression_created_at,
        p_payload_fingerprint,
        v_existing.event_id,
        v_existing.recipient_email
      );
    elsif v_result is null then
      raise exception 'Provider suppression conflict was not durably classified.' using errcode = 'XX000';
    end if;
  end if;

  return v_result;
end;
$suppression_037$;

create function public.admin_list_delivery_provider_integrity_conflicts_page(
  p_state text default 'open',
  p_limit integer default 50,
  p_before_last_detected_at timestamptz default null,
  p_before_conflict_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $integrity_conflict_page$
declare
  v_total_count bigint;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_state is null or p_state not in ('open', 'resolved', 'all')
    or p_limit is null or p_limit not between 1 and 100
    or (p_before_last_detected_at is null) <> (p_before_conflict_id is null)
    or (p_before_conflict_id is not null and p_before_conflict_id <= 0) then
    raise exception 'Invalid provider-integrity case page parameters.' using errcode = '22023';
  end if;

  select count(*) into v_total_count
  from public.delivery_provider_integrity_cases c
  where p_state = 'all' or c.state = p_state;

  with page_plus_one as (
    select
      c.conflict_id,
      c.recipient_email,
      c.anomaly_type,
      c.state,
      c.first_detected_at,
      c.last_detected_at,
      (select count(*) from public.delivery_provider_integrity_conflict_evidence e
       where e.conflict_id = c.conflict_id)::bigint as evidence_count,
      c.resolved_at,
      c.resolved_by,
      c.resolution_note
    from public.delivery_provider_integrity_cases c
    where (p_state = 'all' or c.state = p_state)
      and (p_before_last_detected_at is null
        or (c.last_detected_at, c.conflict_id) < (p_before_last_detected_at, p_before_conflict_id))
    order by c.last_detected_at desc, c.conflict_id desc
    limit p_limit + 1
  ),
  page as (
    select * from page_plus_one
    order by last_detected_at desc, conflict_id desc
    limit p_limit
  ),
  metadata as (
    select count(*) > p_limit as has_more from page_plus_one
  ),
  tail as (
    select last_detected_at, conflict_id
    from page
    order by last_detected_at asc, conflict_id asc
    limit 1
  )
  select jsonb_build_object(
    'total_count', v_total_count,
    'has_more', metadata.has_more,
    'next_cursor', case when metadata.has_more then
      (select jsonb_build_object(
        'last_detected_at', tail.last_detected_at,
        'conflict_id', tail.conflict_id::text
      ) from tail)
      else null end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'conflict_id', page.conflict_id::text,
        'recipient_email', page.recipient_email,
        'anomaly_type', page.anomaly_type,
        'state', page.state,
        'first_detected_at', page.first_detected_at,
        'last_detected_at', page.last_detected_at,
        'evidence_count', page.evidence_count,
        'resolved_at', page.resolved_at,
        'resolved_by', page.resolved_by,
        'resolution_note', page.resolution_note
      ) order by page.last_detected_at desc, page.conflict_id desc)
      from page
    ), '[]'::jsonb)
  ) into v_result
  from metadata;

  return v_result;
end;
$integrity_conflict_page$;

create function public.admin_get_delivery_provider_integrity_conflict(
  p_conflict_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $integrity_conflict_get$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_conflict_id is null or p_conflict_id <= 0 then
    raise exception 'A valid provider-integrity case ID is required.' using errcode = '22023';
  end if;

  select jsonb_build_object(
    'conflict_id', c.conflict_id::text,
    'recipient_email', c.recipient_email,
    'anomaly_type', c.anomaly_type,
    'state', c.state,
    'first_detected_at', c.first_detected_at,
    'last_detected_at', c.last_detected_at,
    'evidence_count', (
      select count(*) from public.delivery_provider_integrity_conflict_evidence e
      where e.conflict_id = c.conflict_id
    ),
    'history_count', (
      select count(*) from public.delivery_provider_integrity_conflict_history h
      where h.conflict_id = c.conflict_id
    ),
    'resolved_at', c.resolved_at,
    'resolved_by', c.resolved_by,
    'resolution_note', c.resolution_note,
    'latest_reopened', (
      select jsonb_build_object(
        'created_at', h.created_at,
        'note', h.note,
        'evidence_id', h.evidence_id::text
      )
      from public.delivery_provider_integrity_conflict_history h
      where h.conflict_id = c.conflict_id
        and h.action = 'reopened'
      order by h.created_at desc, h.history_id desc
      limit 1
    )
  ) into v_result
  from public.delivery_provider_integrity_cases c
  where c.conflict_id = p_conflict_id;

  return v_result;
end;
$integrity_conflict_get$;

create function public.admin_list_delivery_provider_integrity_evidence_page(
  p_conflict_id bigint,
  p_limit integer default 50,
  p_before_observed_at timestamptz default null,
  p_before_evidence_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $integrity_evidence_page$
declare
  v_total_count bigint;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_conflict_id is null or p_conflict_id <= 0
    or p_limit is null or p_limit not between 1 and 100
    or (p_before_observed_at is null) <> (p_before_evidence_id is null)
    or (p_before_evidence_id is not null and p_before_evidence_id <= 0) then
    raise exception 'Invalid provider-integrity evidence page parameters.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.delivery_provider_integrity_cases c where c.conflict_id = p_conflict_id) then
    raise exception 'Provider-integrity conflict case was not found.' using errcode = '22023';
  end if;

  select count(*) into v_total_count
  from public.delivery_provider_integrity_conflict_evidence e
  where e.conflict_id = p_conflict_id;

  with page_plus_one as (
    select e.*
    from public.delivery_provider_integrity_conflict_evidence e
    where e.conflict_id = p_conflict_id
      and (p_before_observed_at is null
        or (e.observed_at, e.evidence_id) < (p_before_observed_at, p_before_evidence_id))
    order by e.observed_at desc, e.evidence_id desc
    limit p_limit + 1
  ),
  page as (
    select * from page_plus_one
    order by observed_at desc, evidence_id desc
    limit p_limit
  ),
  metadata as (
    select count(*) > p_limit as has_more from page_plus_one
  ),
  tail as (
    select observed_at, evidence_id
    from page
    order by observed_at asc, evidence_id asc
    limit 1
  )
  select jsonb_build_object(
    'total_count', v_total_count,
    'has_more', metadata.has_more,
    'next_cursor', case when metadata.has_more then
      (select jsonb_build_object(
        'observed_at', tail.observed_at,
        'evidence_id', tail.evidence_id::text
      ) from tail)
      else null end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'evidence_id', page.evidence_id::text,
        'observed_at', page.observed_at,
        'recipient_email', page.recipient_email,
        'event_id', page.event_id,
        'related_event_id', page.related_event_id,
        'event_type', page.event_type,
        'provider_email_id', page.provider_email_id,
        'provider_suppression_id', page.provider_suppression_id,
        'provider_created_at', page.provider_created_at,
        'bounce_type', page.bounce_type,
        'failure_class', page.failure_class,
        'suppression_reason', page.suppression_reason,
        'suppression_origin', page.suppression_origin,
        'suppression_source_id', page.suppression_source_id,
        'suppression_created_at', page.suppression_created_at,
        'payload_fingerprint', page.payload_fingerprint,
        'stored_event_id', page.stored_event_id,
        'stored_recipient_email', page.stored_recipient_email,
        'evidence_source', page.evidence_source
      ) order by page.observed_at desc, page.evidence_id desc)
      from page
    ), '[]'::jsonb)
  ) into v_result
  from metadata;

  return v_result;
end;
$integrity_evidence_page$;

create function public.admin_list_delivery_provider_integrity_history_page(
  p_conflict_id bigint,
  p_limit integer default 50,
  p_before_created_at timestamptz default null,
  p_before_history_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $integrity_history_page$
declare
  v_total_count bigint;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_conflict_id is null or p_conflict_id <= 0
    or p_limit is null or p_limit not between 1 and 100
    or (p_before_created_at is null) <> (p_before_history_id is null)
    or (p_before_history_id is not null and p_before_history_id <= 0) then
    raise exception 'Invalid provider-integrity history page parameters.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.delivery_provider_integrity_cases c where c.conflict_id = p_conflict_id) then
    raise exception 'Provider-integrity conflict case was not found.' using errcode = '22023';
  end if;

  select count(*) into v_total_count
  from public.delivery_provider_integrity_conflict_history h
  where h.conflict_id = p_conflict_id;

  with page_plus_one as (
    select h.*
    from public.delivery_provider_integrity_conflict_history h
    where h.conflict_id = p_conflict_id
      and (p_before_created_at is null
        or (h.created_at, h.history_id) < (p_before_created_at, p_before_history_id))
    order by h.created_at desc, h.history_id desc
    limit p_limit + 1
  ),
  page as (
    select * from page_plus_one
    order by created_at desc, history_id desc
    limit p_limit
  ),
  metadata as (
    select count(*) > p_limit as has_more from page_plus_one
  ),
  tail as (
    select created_at, history_id
    from page
    order by created_at asc, history_id asc
    limit 1
  )
  select jsonb_build_object(
    'total_count', v_total_count,
    'has_more', metadata.has_more,
    'next_cursor', case when metadata.has_more then
      (select jsonb_build_object(
        'created_at', tail.created_at,
        'history_id', tail.history_id::text
      ) from tail)
      else null end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'history_id', page.history_id::text,
        'action', page.action,
        'actor_id', page.actor_id,
        'note', page.note,
        'evidence_id', page.evidence_id::text,
        'created_at', page.created_at
      ) order by page.created_at desc, page.history_id desc)
      from page
    ), '[]'::jsonb)
  ) into v_result
  from metadata;

  return v_result;
end;
$integrity_history_page$;

revoke all privileges on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text) to service_role;
comment on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)
  is 'deedlight:038:event-id-recipient-provider-lock-order:v1';

revoke all privileges on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text) to service_role;
comment on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)
  is 'deedlight:038:event-id-recipient-provider-lock-order:v1';

revoke all privileges on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text) to service_role;
comment on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)
  is 'deedlight:038:event-id-recipient-provider-lock-order:v1';

revoke all privileges on function public.record_delivery_provider_event(text,text,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_delivery_provider_event(text,text,text,text,text) to service_role;
comment on function public.record_delivery_provider_event(text,text,text,text,text)
  is 'deedlight:038:event-id-recipient-provider-lock-order:v1';

revoke all privileges on function public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)
  to service_role;
comment on function public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)
  is 'deedlight:038:event-id-recipient-provider-lock-order:v1';

revoke all privileges on function public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamptz,bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamptz,bigint)
  to authenticated;

revoke all privileges on function public.admin_get_delivery_provider_integrity_conflict(bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_get_delivery_provider_integrity_conflict(bigint)
  to authenticated;

revoke all privileges on function public.admin_list_delivery_provider_integrity_evidence_page(bigint,integer,timestamptz,bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_list_delivery_provider_integrity_evidence_page(bigint,integer,timestamptz,bigint)
  to authenticated;

revoke all privileges on function public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)
  to authenticated;

comment on function public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamptz,bigint)
  is 'Admin-only keyset page of private provider-integrity cases with exact filtered total and continuation cursor.';
comment on function public.admin_get_delivery_provider_integrity_conflict(bigint)
  is 'Admin-only direct case retrieval independent of list pagination; includes exact counts and latest reopening summary.';
comment on function public.admin_list_delivery_provider_integrity_evidence_page(bigint,integer,timestamptz,bigint)
  is 'Admin-only keyset page of append-only normalized provider evidence with exact total and continuation cursor.';
comment on function public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)
  is 'Admin-only newest-first keyset page of append-only resolution/reopening history with exact total and continuation cursor.';

notify pgrst, 'reload schema';
commit;
