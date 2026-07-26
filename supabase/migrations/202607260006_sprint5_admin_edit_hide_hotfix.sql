-- Deedlight Sprint 5 hotfix — admin edit + hide reliability.
-- Safe to run after Sprint 5.

-- 1. Make sure the offerings status check allows hidden content.
do $$
declare
  constraint_row record;
begin
  for constraint_row in
    select conname
    from pg_constraint
    where conrelid = 'public.offerings'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format('alter table public.offerings drop constraint if exists %I', constraint_row.conname);
  end loop;
end $$;

alter table public.offerings
add constraint offerings_status_check
check (status in ('draft','pending','approved','rejected','needs_edit','hidden'));

-- 2. Make sure authenticated admins can update all Offering statuses.
grant select, insert, update on public.offerings to authenticated;
grant all on public.offerings to service_role;

drop policy if exists "offerings_update_own_or_admin" on public.offerings;
create policy "offerings_update_own_or_admin"
on public.offerings
for update
using (
  public.is_admin()
  or (
    user_id = auth.uid()
    and status in ('draft', 'needs_edit')
  )
)
with check (
  public.is_admin()
  or (
    user_id = auth.uid()
    and status in ('draft', 'pending', 'needs_edit')
  )
);

-- 3. Public views should only expose approved Offerings.
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
