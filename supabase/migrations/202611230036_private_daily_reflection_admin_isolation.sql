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
