-- Sprint 8 — Short Video Studio
-- Adds reusable short-video planning, publishing, and public embed fields to daily_lights.

begin;

alter table public.daily_lights
  add column if not exists video_status text not null default 'not_started',
  add column if not exists video_platform text,
  add column if not exists video_hashtags text,
  add column if not exists video_notes text,
  add column if not exists video_asset_url text,
  add column if not exists tiktok_url text,
  add column if not exists instagram_url text,
  add column if not exists short_video_public boolean not null default false,
  add column if not exists video_posted_at timestamptz;

update public.daily_lights
set video_status = 'not_started'
where video_status is null
   or video_status not in ('not_started', 'planned', 'scripted', 'recorded', 'posted', 'archived');

alter table public.daily_lights
  alter column video_status set default 'not_started',
  alter column video_status set not null,
  alter column short_video_public set default false,
  alter column short_video_public set not null;

alter table public.daily_lights
  drop constraint if exists daily_lights_video_status_check;

alter table public.daily_lights
  add constraint daily_lights_video_status_check
  check (video_status in ('not_started', 'planned', 'scripted', 'recorded', 'posted', 'archived'));

create index if not exists daily_lights_video_status_idx
  on public.daily_lights(video_status);

create index if not exists daily_lights_video_public_idx
  on public.daily_lights(short_video_public)
  where short_video_public = true;

create index if not exists daily_lights_video_posted_at_idx
  on public.daily_lights(video_posted_at desc);

grant select on public.daily_lights to anon, authenticated;
grant insert, update, delete on public.daily_lights to authenticated;
grant all on public.daily_lights to service_role;

commit;
