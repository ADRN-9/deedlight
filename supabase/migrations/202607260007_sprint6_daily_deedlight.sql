-- Sprint 6 — Daily Deedlight Content System
-- Adds daily content scheduling, archiving, featured offerings, reflections/check-ins, and short-video planning fields.

create extension if not exists pgcrypto;

-- Keep this helper available even if an older migration was not applied.
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
      and coalesce(is_suspended, false) = false
  );
$$;

grant execute on function public.is_admin() to anon, authenticated;

create table if not exists public.daily_posts (
  id uuid primary key default gen_random_uuid(),
  slug text unique,
  scheduled_for date not null default current_date,
  status text not null default 'draft',
  kicker text default 'TODAY’S DEEDLIGHT',
  title text not null default 'A new light can begin today.',
  theme text,
  summary text,
  body text,
  small_deed text,
  reflection_prompt text,
  featured_offering_id uuid references public.offerings(id) on delete set null,
  image_url text,
  video_title text,
  video_hook text,
  video_script text,
  video_caption text,
  youtube_url text,
  video_status text not null default 'idea',
  published_at timestamptz,
  archived_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.daily_posts add column if not exists slug text;
alter table public.daily_posts add column if not exists scheduled_for date not null default current_date;
alter table public.daily_posts add column if not exists status text not null default 'draft';
alter table public.daily_posts add column if not exists kicker text default 'TODAY’S DEEDLIGHT';
alter table public.daily_posts add column if not exists title text not null default 'A new light can begin today.';
alter table public.daily_posts add column if not exists theme text;
alter table public.daily_posts add column if not exists summary text;
alter table public.daily_posts add column if not exists body text;
alter table public.daily_posts add column if not exists small_deed text;
alter table public.daily_posts add column if not exists reflection_prompt text;
alter table public.daily_posts add column if not exists featured_offering_id uuid references public.offerings(id) on delete set null;
alter table public.daily_posts add column if not exists image_url text;
alter table public.daily_posts add column if not exists video_title text;
alter table public.daily_posts add column if not exists video_hook text;
alter table public.daily_posts add column if not exists video_script text;
alter table public.daily_posts add column if not exists video_caption text;
alter table public.daily_posts add column if not exists youtube_url text;
alter table public.daily_posts add column if not exists video_status text not null default 'idea';
alter table public.daily_posts add column if not exists published_at timestamptz;
alter table public.daily_posts add column if not exists archived_at timestamptz;
alter table public.daily_posts add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.daily_posts add column if not exists created_at timestamptz not null default now();
alter table public.daily_posts add column if not exists updated_at timestamptz not null default now();

-- Add constraints safely only when absent.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'daily_posts_status_check'
  ) then
    alter table public.daily_posts
      add constraint daily_posts_status_check
      check (status in ('draft', 'scheduled', 'published', 'archived'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'daily_posts_video_status_check'
  ) then
    alter table public.daily_posts
      add constraint daily_posts_video_status_check
      check (video_status in ('idea', 'scripted', 'recorded', 'published'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'daily_posts_slug_unique'
  ) then
    alter table public.daily_posts
      add constraint daily_posts_slug_unique unique (slug);
  end if;
end $$;

create index if not exists daily_posts_status_scheduled_idx
  on public.daily_posts (status, scheduled_for desc);

create index if not exists daily_posts_featured_offering_idx
  on public.daily_posts (featured_offering_id);

create table if not exists public.daily_reflections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  daily_post_id uuid not null references public.daily_posts(id) on delete cascade,
  reflection_text text,
  did_today_deed boolean not null default false,
  mood_label text,
  is_private boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint daily_reflections_unique_user_post unique (user_id, daily_post_id)
);

alter table public.daily_reflections add column if not exists reflection_text text;
alter table public.daily_reflections add column if not exists did_today_deed boolean not null default false;
alter table public.daily_reflections add column if not exists mood_label text;
alter table public.daily_reflections add column if not exists is_private boolean not null default true;
alter table public.daily_reflections add column if not exists created_at timestamptz not null default now();
alter table public.daily_reflections add column if not exists updated_at timestamptz not null default now();

create index if not exists daily_reflections_post_idx on public.daily_reflections (daily_post_id);
create index if not exists daily_reflections_user_idx on public.daily_reflections (user_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_daily_posts_updated_at on public.daily_posts;
create trigger set_daily_posts_updated_at
before update on public.daily_posts
for each row execute function public.set_updated_at();

drop trigger if exists set_daily_reflections_updated_at on public.daily_reflections;
create trigger set_daily_reflections_updated_at
before update on public.daily_reflections
for each row execute function public.set_updated_at();

-- Grants
grant usage on schema public to anon, authenticated, service_role;
grant select on public.daily_posts to anon, authenticated;
grant select, insert, update, delete on public.daily_posts to authenticated;
grant select, insert, update, delete on public.daily_reflections to authenticated;
grant all on public.daily_posts to service_role;
grant all on public.daily_reflections to service_role;

-- RLS
alter table public.daily_posts enable row level security;
alter table public.daily_reflections enable row level security;

drop policy if exists "daily_posts_public_read_published" on public.daily_posts;
create policy "daily_posts_public_read_published"
on public.daily_posts
for select
using (status in ('published', 'archived'));

drop policy if exists "daily_posts_admin_all" on public.daily_posts;
create policy "daily_posts_admin_all"
on public.daily_posts
for all
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "daily_reflections_select_own_or_admin" on public.daily_reflections;
create policy "daily_reflections_select_own_or_admin"
on public.daily_reflections
for select
using (user_id = auth.uid() or public.is_admin());

drop policy if exists "daily_reflections_insert_own" on public.daily_reflections;
create policy "daily_reflections_insert_own"
on public.daily_reflections
for insert
with check (user_id = auth.uid());

drop policy if exists "daily_reflections_update_own" on public.daily_reflections;
create policy "daily_reflections_update_own"
on public.daily_reflections
for update
using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

drop policy if exists "daily_reflections_delete_admin" on public.daily_reflections;
create policy "daily_reflections_delete_admin"
on public.daily_reflections
for delete
using (public.is_admin());

-- Seed one editable daily post if the table is empty.
insert into public.daily_posts (
  slug,
  scheduled_for,
  status,
  kicker,
  title,
  theme,
  summary,
  body,
  small_deed,
  reflection_prompt,
  video_title,
  video_hook,
  video_script,
  video_caption,
  video_status,
  published_at
)
select
  'a-new-light-can-begin-today',
  current_date,
  'published',
  'TODAY’S DEEDLIGHT',
  'A new light can begin today.',
  'courage',
  'Beauty is not only found in nature. Sometimes beauty appears when one person refuses to join cruelty.',
  'Goodness does not prevail by accident. Today, choose one small act that protects dignity, reduces loneliness, or gives someone courage.',
  'Say one gentle sentence in defense of someone who is being judged unfairly.',
  'Where can I make one situation kinder today?',
  'A new light can begin today',
  'Goodness does not need a stage; it needs one person to begin.',
  'Today’s Deedlight is simple: notice one place where dignity needs protection, then add one sentence of gentleness.',
  'One small deed can keep light alive. #Deedlight #Goodness #Kindness',
  'idea',
  now()
where not exists (select 1 from public.daily_posts);
