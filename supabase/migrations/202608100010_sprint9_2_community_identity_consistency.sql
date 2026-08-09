-- Sprint 9.2 — Community Identity Consistency
-- Keeps public identity projections privacy-minimized and repairs Rising Goodness
-- after Sprint 9.1 added author_username to offerings_public.

begin;

-- New accounts should never derive a potentially public display name from email.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.profiles (
    user_id,
    username,
    display_name
  )
  values (
    new.id,
    'member-' || encode(gen_random_bytes(8), 'hex'),
    coalesce(
      nullif(new.raw_user_meta_data->>'display_name', ''),
      'Deedlight member'
    )
  )
  on conflict (user_id) do nothing;

  return new;
end;
$$;

-- Public Offering projections do not need internal auth/profile UUIDs.
-- Human-facing attribution is carried only through author_name/author_username.
create or replace view public.offerings_public
with (security_barrier = true)
as
select
  o.id,
  null::uuid as user_id,
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
  case
    when o.is_anonymous
      or coalesce(p.is_suspended, false)
    then null::text
    else p.display_name
  end as author_name,
  case
    when o.is_anonymous
      or coalesce(p.is_suspended, false)
      or coalesce(p.is_public, false) = false
    then null::text
    else p.username
  end as author_username
from public.offerings o
left join public.themes t on t.id = o.theme_id
left join public.profiles p on p.user_id = o.user_id
where o.status = 'approved';

revoke all privileges
on table public.offerings_public
from public, anon, authenticated;

grant select
on table public.offerings_public
to anon, authenticated, service_role;

-- Preserve the existing Rising view column contract and append author_username
-- at the end, which CREATE OR REPLACE VIEW permits without breaking dependents.
create or replace view public.offerings_rising
with (security_barrier = true)
as
select
  op.id,
  op.user_id,
  op.title,
  op.body,
  op.takeaway,
  op.offering_type,
  op.media_url,
  op.media_type,
  op.is_anonymous,
  op.allow_reflections,
  op.location_label,
  op.bless_count,
  op.inspired_count,
  op.carried_forward_count,
  op.reflection_count,
  op.bless_score,
  op.published_at,
  op.theme_name,
  op.author_name,
  (
    coalesce(op.bless_score, 0)
    + case
        when op.published_at is null then 0
        when op.published_at > now() - interval '24 hours' then 30
        when op.published_at > now() - interval '7 days' then 12
        else 0
      end
  )::numeric as rising_score,
  op.author_username
from public.offerings_public op;

revoke all privileges
on table public.offerings_rising
from public, anon, authenticated;

grant select
on table public.offerings_rising
to anon, authenticated, service_role;

-- Revoke direct anonymous base-table access defensively.
revoke select
on table public.offerings
from anon;

-- Refresh the Supabase/PostgREST schema cache after changing public views.
notify pgrst, 'reload schema';

commit;
