-- Sprint 11.2 — Weekly Goodness
-- Seven-day public Offering activity plus an optional database-admin-curated
-- Featured Light. No reflection, Daily completion, Saved Light, or reminder
-- data is queried or exposed by these APIs.

begin;

-- ---------------------------------------------------------------------
-- 1. Make seven-day reaction aggregation efficient.
-- ---------------------------------------------------------------------

create index if not exists reactions_created_offering_type_idx
on public.reactions (created_at desc, offering_id, reaction_type);

-- ---------------------------------------------------------------------
-- 2. Private weekly feature selection.
--    The table itself is never readable or writable by browser roles.
-- ---------------------------------------------------------------------

create table if not exists public.weekly_goodness_features (
  week_start date primary key
    check (extract(isodow from week_start) = 1),
  offering_id uuid not null
    references public.offerings(id) on delete cascade,
  selected_by uuid
    references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.weekly_goodness_features
enable row level security;

drop trigger if exists weekly_goodness_features_set_updated_at
on public.weekly_goodness_features;

create trigger weekly_goodness_features_set_updated_at
before update on public.weekly_goodness_features
for each row execute function public.set_updated_at();

revoke all privileges
on table public.weekly_goodness_features
from public, anon, authenticated;

grant all privileges
on table public.weekly_goodness_features
to service_role;

-- ---------------------------------------------------------------------
-- 3. Public seven-day goodness API.
--    This SECURITY DEFINER function intentionally returns aggregate reaction
--    counts only. It exposes no reaction user IDs and does not read reflection
--    tables or reflection-derived bless_score values.
-- ---------------------------------------------------------------------

create or replace function public.get_weekly_goodness(
  p_limit integer default 12
)
returns table (
  id uuid,
  title text,
  body text,
  takeaway text,
  offering_type text,
  media_url text,
  media_type text,
  is_anonymous boolean,
  allow_reflections boolean,
  location_label text,
  bless_count integer,
  inspired_count integer,
  carried_forward_count integer,
  published_at timestamptz,
  theme_name text,
  author_name text,
  author_username text,
  weekly_bless_count integer,
  weekly_inspired_count integer,
  weekly_carried_forward_count integer,
  weekly_reaction_count integer
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_limit integer := least(
    greatest(coalesce(p_limit, 12), 1),
    24
  );
begin
  return query
  with recent as (
    select
      r.offering_id,
      count(*) filter (
        where r.reaction_type = 'bless'
      )::integer as weekly_bless_count,
      count(*) filter (
        where r.reaction_type = 'inspired_me'
      )::integer as weekly_inspired_count,
      count(*) filter (
        where r.reaction_type = 'i_did_this_too'
      )::integer as weekly_carried_forward_count,
      count(*)::integer as weekly_reaction_count
    from public.reactions r
    where r.created_at >= now() - interval '7 days'
    group by r.offering_id
  )
  select
    op.id,
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
    op.published_at,
    op.theme_name,
    op.author_name,
    op.author_username,
    coalesce(recent.weekly_bless_count, 0)::integer,
    coalesce(recent.weekly_inspired_count, 0)::integer,
    coalesce(recent.weekly_carried_forward_count, 0)::integer,
    coalesce(recent.weekly_reaction_count, 0)::integer
  from public.offerings_public op
  left join recent
    on recent.offering_id = op.id
  where
    coalesce(recent.weekly_reaction_count, 0) > 0
    or op.published_at >= now() - interval '7 days'
  order by
    (
      coalesce(recent.weekly_bless_count, 0)
      + coalesce(recent.weekly_inspired_count, 0) * 2
      + coalesce(recent.weekly_carried_forward_count, 0) * 3
    ) desc,
    coalesce(recent.weekly_reaction_count, 0) desc,
    op.published_at desc nulls last,
    op.id
  limit v_limit;
end;
$$;

revoke all privileges
on function public.get_weekly_goodness(integer)
from public, anon, authenticated;

grant execute
on function public.get_weekly_goodness(integer)
to anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- 4. Public current Featured Light API.
--    Only the same privacy-minimized offerings_public projection is returned.
-- ---------------------------------------------------------------------

create or replace function public.get_current_weekly_goodness_feature()
returns table (
  week_start date,
  id uuid,
  title text,
  body text,
  takeaway text,
  offering_type text,
  media_url text,
  media_type text,
  is_anonymous boolean,
  allow_reflections boolean,
  location_label text,
  bless_count integer,
  inspired_count integer,
  carried_forward_count integer,
  published_at timestamptz,
  theme_name text,
  author_name text,
  author_username text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    f.week_start,
    op.id,
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
    op.published_at,
    op.theme_name,
    op.author_name,
    op.author_username
  from public.weekly_goodness_features f
  join public.offerings_public op
    on op.id = f.offering_id
  where f.week_start =
    date_trunc('week', timezone('UTC', now()))::date
  limit 1;
$$;

revoke all privileges
on function public.get_current_weekly_goodness_feature()
from public, anon, authenticated;

grant execute
on function public.get_current_weekly_goodness_feature()
to anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- 5. Database-admin-only curation mutation.
--    ADMIN_EMAILS fallback access is deliberately insufficient here.
-- ---------------------------------------------------------------------

create or replace function public.set_weekly_goodness_feature(
  p_offering_id uuid
)
returns date
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_week_start date :=
    date_trunc('week', timezone('UTC', now()))::date;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'Database-backed admin access is required.'
      using errcode = '42501';
  end if;

  if p_offering_id is null then
    delete from public.weekly_goodness_features
    where week_start = v_week_start;

    return v_week_start;
  end if;

  if not exists (
    select 1
    from public.offerings o
    where o.id = p_offering_id
      and o.status = 'approved'
  ) then
    raise exception 'Featured Light must be an approved public Offering.'
      using errcode = '22023';
  end if;

  insert into public.weekly_goodness_features (
    week_start,
    offering_id,
    selected_by
  )
  values (
    v_week_start,
    p_offering_id,
    v_actor
  )
  on conflict (week_start)
  do update set
    offering_id = excluded.offering_id,
    selected_by = excluded.selected_by,
    updated_at = now();

  return v_week_start;
end;
$$;

revoke all privileges
on function public.set_weekly_goodness_feature(uuid)
from public, anon, authenticated;

grant execute
on function public.set_weekly_goodness_feature(uuid)
to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
