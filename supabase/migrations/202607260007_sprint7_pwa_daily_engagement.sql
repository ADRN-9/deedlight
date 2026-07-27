begin;

create extension if not exists pgcrypto;

create table if not exists public.daily_lights (
  id uuid primary key default gen_random_uuid(),
  scheduled_date date not null,
  status text not null default 'draft',
  kicker text default 'TODAY’S DEEDLIGHT',
  title text,
  theme text,
  summary text,
  small_deed text,
  reflection_prompt text,
  featured_offering_id uuid references public.offerings(id) on delete set null,
  video_title text,
  video_hook text,
  video_script text,
  archived_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.daily_lights add column if not exists scheduled_date date;
alter table public.daily_lights add column if not exists status text default 'draft';
alter table public.daily_lights add column if not exists kicker text default 'TODAY’S DEEDLIGHT';
alter table public.daily_lights add column if not exists title text;
alter table public.daily_lights add column if not exists theme text;
alter table public.daily_lights add column if not exists summary text;
alter table public.daily_lights add column if not exists small_deed text;
alter table public.daily_lights add column if not exists reflection_prompt text;
alter table public.daily_lights add column if not exists featured_offering_id uuid references public.offerings(id) on delete set null;
alter table public.daily_lights add column if not exists video_title text;
alter table public.daily_lights add column if not exists video_hook text;
alter table public.daily_lights add column if not exists video_script text;
alter table public.daily_lights add column if not exists archived_at timestamptz;
alter table public.daily_lights add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.daily_lights add column if not exists created_at timestamptz not null default now();
alter table public.daily_lights add column if not exists updated_at timestamptz not null default now();

alter table public.daily_lights alter column status set default 'draft';
alter table public.daily_lights alter column kicker set default 'TODAY’S DEEDLIGHT';

update public.daily_lights
set status = coalesce(status, 'draft'),
    kicker = coalesce(kicker, 'TODAY’S DEEDLIGHT'),
    title = coalesce(title, 'A new light can begin today.'),
    updated_at = now()
where status is null or kicker is null or title is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'daily_lights_scheduled_date_unique'
      and conrelid = 'public.daily_lights'::regclass
  ) then
    alter table public.daily_lights
      add constraint daily_lights_scheduled_date_unique unique (scheduled_date);
  end if;
end $$;

create table if not exists public.daily_reflections (
  id uuid primary key default gen_random_uuid(),
  daily_light_id uuid references public.daily_lights(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  reflection text,
  intention text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.daily_reflections add column if not exists daily_light_id uuid references public.daily_lights(id) on delete cascade;
alter table public.daily_reflections add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.daily_reflections add column if not exists reflection text;
alter table public.daily_reflections add column if not exists intention text;
alter table public.daily_reflections add column if not exists created_at timestamptz not null default now();
alter table public.daily_reflections add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'daily_reflections_daily_light_user_unique'
      and conrelid = 'public.daily_reflections'::regclass
  ) then
    alter table public.daily_reflections
      add constraint daily_reflections_daily_light_user_unique unique (daily_light_id, user_id);
  end if;
end $$;

alter table public.daily_lights enable row level security;
alter table public.daily_reflections enable row level security;

drop policy if exists "daily lights public read published" on public.daily_lights;
create policy "daily lights public read published"
on public.daily_lights
for select
to anon, authenticated
using (status = 'published' or public.is_admin());

drop policy if exists "daily lights admin insert" on public.daily_lights;
create policy "daily lights admin insert"
on public.daily_lights
for insert
to authenticated
with check (public.is_admin());

drop policy if exists "daily lights admin update" on public.daily_lights;
create policy "daily lights admin update"
on public.daily_lights
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "daily lights admin delete" on public.daily_lights;
create policy "daily lights admin delete"
on public.daily_lights
for delete
to authenticated
using (public.is_admin());

drop policy if exists "daily reflections select own or admin" on public.daily_reflections;
create policy "daily reflections select own or admin"
on public.daily_reflections
for select
to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists "daily reflections insert own" on public.daily_reflections;
create policy "daily reflections insert own"
on public.daily_reflections
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "daily reflections update own or admin" on public.daily_reflections;
create policy "daily reflections update own or admin"
on public.daily_reflections
for update
to authenticated
using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

grant select on public.daily_lights to anon, authenticated;
grant insert, update, delete on public.daily_lights to authenticated;
grant select, insert, update on public.daily_reflections to authenticated;
grant all on public.daily_lights to service_role;
grant all on public.daily_reflections to service_role;

commit;
