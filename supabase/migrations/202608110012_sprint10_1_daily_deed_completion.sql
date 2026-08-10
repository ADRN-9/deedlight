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
