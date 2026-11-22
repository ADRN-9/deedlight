-- Sprint 12.3 — Keep private Offering rows behind owner/admin RLS.
-- Public approved content is served by offerings_public / offerings_rising.
-- The older Sprint 5 policy also exposed approved base-table rows (including
-- user_id and moderation_note) to every authenticated member. Remove that
-- broad read path while retaining own-row and database-admin access.

begin;

drop policy if exists "offerings_select_public_or_own"
on public.offerings;

notify pgrst, 'reload schema';

commit;
