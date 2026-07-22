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
