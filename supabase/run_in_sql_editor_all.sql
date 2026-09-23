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
