-- Sprint 3 support migration: safe to run after Sprint 1 schema.
-- It improves public view safety and adds useful indexes for admin review queues.

create index if not exists offerings_status_created_idx
on public.offerings(status, created_at desc);

create index if not exists offerings_user_status_created_idx
on public.offerings(user_id, status, created_at desc);

create or replace view public.offerings_public
with (security_invoker = true)
as
select
  o.id,
  o.user_id,
  o.title,
  o.body,
  o.takeaway,
  o.offering_type,
  o.media_url,
  o.media_type,
  o.is_anonymous,
  o.allow_reflections,
  o.location_label,
  o.bless_count,
  o.inspired_count,
  o.carried_forward_count,
  o.reflection_count,
  o.bless_score,
  o.published_at,
  t.name as theme_name,
  case when o.is_anonymous then null else p.display_name end as author_name
from public.offerings o
left join public.themes t on t.id = o.theme_id
left join public.profiles p on p.user_id = o.user_id
where o.status = 'approved';

grant select on public.offerings_public to anon, authenticated;
