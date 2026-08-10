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
