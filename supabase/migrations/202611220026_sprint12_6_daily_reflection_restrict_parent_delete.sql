-- Sprint 12.6 — Prevent Daily content deletion from cascading into private reflections.
--
-- A Daily Post or Daily Light may be removed only when no private reflection
-- references it. Owner-authorized reflection deletion remains governed by RLS.
-- The auth.users -> daily_reflections cascade is intentionally preserved for
-- the existing account-erasure path; exceptional legal erasure remains a
-- separately authorized and auditable operation.

begin;

alter table public.daily_reflections
  drop constraint if exists daily_reflections_daily_post_id_fkey,
  drop constraint if exists daily_reflections_daily_light_id_fkey;

alter table public.daily_reflections
  add constraint daily_reflections_daily_post_id_fkey
    foreign key (daily_post_id)
    references public.daily_posts(id)
    on delete restrict,
  add constraint daily_reflections_daily_light_id_fkey
    foreign key (daily_light_id)
    references public.daily_lights(id)
    on delete restrict;

notify pgrst, 'reload schema';

commit;
