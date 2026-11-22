-- Sprint 12.5 — Restrict Daily reflection deletion to its owner.
--
-- Daily reflections are private Journey data. Members may remove their own
-- rows through ordinary authenticated database operations, while admins must
-- not gain cross-member access through a special DELETE policy. Exceptional
-- legal-erasure or support access belongs in a separately authorized,
-- auditable server-side mechanism.

begin;

alter table public.daily_reflections enable row level security;

-- Remove the historical administrator-only policy and its space-separated
-- spelling before installing the owner-only rule.
drop policy if exists "daily_reflections_delete_admin"
on public.daily_reflections;
drop policy if exists "daily reflections delete admin"
on public.daily_reflections;
drop policy if exists "daily_reflections_delete_own"
on public.daily_reflections;
drop policy if exists "daily reflections delete own"
on public.daily_reflections;

create policy "daily_reflections_delete_own"
on public.daily_reflections
for delete
to authenticated
using (user_id = auth.uid());

notify pgrst, 'reload schema';

commit;
