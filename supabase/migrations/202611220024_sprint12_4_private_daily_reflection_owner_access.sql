-- Sprint 12.4 — Keep Daily reflections private to their owner.
--
-- Daily reflection content is personal Journey data, not moderation data.
-- Administrators continue to use the narrow moderation APIs, which deliberately
-- exclude Daily reflection content. Ordinary authenticated database access
-- must never grant an administrator another member's reflection text.
--
-- The historical admin DELETE policy is retained as a deletion-only boundary;
-- it does not grant SELECT or UPDATE access to private reflection content.

begin;

alter table public.daily_reflections enable row level security;

-- Sprint 6 used underscore-separated policy names; Sprint 7 recreated
-- equivalent policies with spaces. Remove both historical generations.
drop policy if exists "daily_reflections_select_own_or_admin"
on public.daily_reflections;
drop policy if exists "daily reflections select own or admin"
on public.daily_reflections;
drop policy if exists "daily_reflections_select_own"
on public.daily_reflections;
drop policy if exists "daily reflections select own"
on public.daily_reflections;

create policy "daily_reflections_select_own"
on public.daily_reflections
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "daily_reflections_insert_own"
on public.daily_reflections;
drop policy if exists "daily reflections insert own"
on public.daily_reflections;

create policy "daily_reflections_insert_own"
on public.daily_reflections
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "daily_reflections_update_own"
on public.daily_reflections;
drop policy if exists "daily_reflections_update_own_or_admin"
on public.daily_reflections;
drop policy if exists "daily reflections update own or admin"
on public.daily_reflections;

create policy "daily_reflections_update_own"
on public.daily_reflections
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- Preserve the existing administrator deletion policy. It does not expose
-- reflection content and the SELECT policy above remains owner-only.
drop policy if exists "daily_reflections_delete_admin"
on public.daily_reflections;

create policy "daily_reflections_delete_admin"
on public.daily_reflections
for delete
to authenticated
using (public.is_admin());

revoke all privileges
on table public.daily_reflections
from public, anon;

grant select, insert, update, delete
on table public.daily_reflections
to authenticated;

grant all
on table public.daily_reflections
to service_role;

notify pgrst, 'reload schema';

commit;
