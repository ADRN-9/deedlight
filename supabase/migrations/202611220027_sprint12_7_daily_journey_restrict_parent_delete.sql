-- Sprint 12.7 — Prevent Daily content deletion from cascading into private Journey records.
--
-- Saved Lights and Daily Deed completions are private member-owned history.
-- Daily Posts and Daily Lights may be deleted only after these private child
-- records have been explicitly removed by their owners or through account
-- erasure. The auth.users -> child-row cascades remain unchanged.

begin;

alter table public.saved_lights
  drop constraint if exists saved_lights_daily_post_id_fkey,
  drop constraint if exists saved_lights_daily_light_id_fkey;

alter table public.saved_lights
  add constraint saved_lights_daily_post_id_fkey
    foreign key (daily_post_id)
    references public.daily_posts(id)
    on delete restrict,
  add constraint saved_lights_daily_light_id_fkey
    foreign key (daily_light_id)
    references public.daily_lights(id)
    on delete restrict;

alter table public.daily_deed_completions
  drop constraint if exists daily_deed_completions_daily_post_id_fkey,
  drop constraint if exists daily_deed_completions_daily_light_id_fkey;

alter table public.daily_deed_completions
  add constraint daily_deed_completions_daily_post_id_fkey
    foreign key (daily_post_id)
    references public.daily_posts(id)
    on delete restrict,
  add constraint daily_deed_completions_daily_light_id_fkey
    foreign key (daily_light_id)
    references public.daily_lights(id)
    on delete restrict;

notify pgrst, 'reload schema';

commit;
