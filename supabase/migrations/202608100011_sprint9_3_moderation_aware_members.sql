-- Sprint 9.3 — Moderation-aware Members
-- Adds auditable member suspension/restore controls and closes community-write
-- suspension gaps without exposing or changing private Daily reflections.

begin;

-- ---------------------------------------------------------------------
-- 1. Append-only moderation history.
-- ---------------------------------------------------------------------

create table if not exists public.member_moderation_events (
  id uuid primary key default gen_random_uuid(),
  member_user_id uuid not null references auth.users(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null check (action in ('suspended', 'restored')),
  reason text not null check (char_length(reason) between 8 and 500),
  created_at timestamptz not null default now()
);

create index if not exists member_moderation_events_member_created_idx
  on public.member_moderation_events(member_user_id, created_at desc);

create index if not exists member_moderation_events_actor_created_idx
  on public.member_moderation_events(actor_user_id, created_at desc);

alter table public.member_moderation_events enable row level security;

drop policy if exists "member_moderation_events_admin_select"
on public.member_moderation_events;

create policy "member_moderation_events_admin_select"
on public.member_moderation_events
for select
to authenticated
using (public.is_admin());

revoke all privileges
on table public.member_moderation_events
from public, anon, authenticated;

grant all
on table public.member_moderation_events
to service_role;

-- ---------------------------------------------------------------------
-- 2. Database-admin-only member read APIs.
--    These projections intentionally contain no email addresses,
--    reflection text, Daily reflections, or auth/profile row IDs.
-- ---------------------------------------------------------------------

create or replace function public.admin_list_members(
  p_state text default 'all'
)
returns table (
  member_user_id uuid,
  username text,
  display_name text,
  role text,
  is_verified boolean,
  is_suspended boolean,
  is_public boolean,
  member_since timestamptz,
  offering_count bigint,
  approved_offering_count bigint,
  pending_offering_count bigint,
  open_report_count bigint,
  last_action text,
  last_reason text,
  last_moderated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Database-backed admin access is required.'
      using errcode = '42501';
  end if;

  if p_state not in ('all', 'active', 'suspended') then
    raise exception 'Invalid member state filter.'
      using errcode = '22023';
  end if;

  return query
  select
    p.user_id,
    p.username,
    p.display_name,
    p.role,
    p.is_verified,
    p.is_suspended,
    p.is_public,
    p.created_at,
    (
      select count(*)::bigint
      from public.offerings o
      where o.user_id = p.user_id
    ) as offering_count,
    (
      select count(*)::bigint
      from public.offerings o
      where o.user_id = p.user_id
        and o.status = 'approved'
    ) as approved_offering_count,
    (
      select count(*)::bigint
      from public.offerings o
      where o.user_id = p.user_id
        and o.status = 'pending'
    ) as pending_offering_count,
    (
      select count(*)::bigint
      from public.reports r
      join public.offerings o
        on o.id = r.offering_id
      where o.user_id = p.user_id
        and r.status in ('open', 'reviewing', 'pending')
    ) as open_report_count,
    latest.action,
    latest.reason,
    latest.created_at
  from public.profiles p
  left join lateral (
    select
      e.action,
      e.reason,
      e.created_at
    from public.member_moderation_events e
    where e.member_user_id = p.user_id
    order by e.created_at desc
    limit 1
  ) latest on true
  where
    p_state = 'all'
    or (p_state = 'active' and p.is_suspended = false)
    or (p_state = 'suspended' and p.is_suspended = true)
  order by
    p.is_suspended desc,
    p.created_at desc;
end;
$$;

revoke all
on function public.admin_list_members(text)
from public, anon;

grant execute
on function public.admin_list_members(text)
to authenticated;

create or replace function public.admin_get_member_context(
  p_member_user_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_profile jsonb;
  v_offerings jsonb;
  v_reports jsonb;
  v_events jsonb;
begin
  if not public.is_admin() then
    raise exception 'Database-backed admin access is required.'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'user_id', p.user_id,
    'username', p.username,
    'display_name', p.display_name,
    'role', p.role,
    'is_verified', p.is_verified,
    'is_suspended', p.is_suspended,
    'is_public', p.is_public,
    'member_since', p.created_at
  )
  into v_profile
  from public.profiles p
  where p.user_id = p_member_user_id;

  if v_profile is null then
    return null;
  end if;

  -- Deliberately no query to public.reflections or public.daily_reflections.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', o.id,
        'title', o.title,
        'status', o.status,
        'is_anonymous', o.is_anonymous,
        'open_report_count', coalesce(o.open_report_count, 0),
        'moderation_note', o.moderation_note,
        'created_at', o.created_at,
        'published_at', o.published_at
      )
      order by o.created_at desc
    ),
    '[]'::jsonb
  )
  into v_offerings
  from public.offerings o
  where o.user_id = p_member_user_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'offering_id', r.offering_id,
        'offering_title', o.title,
        'reason', r.reason,
        'status', r.status,
        'details', r.details,
        'admin_note', r.admin_note,
        'created_at', r.created_at
      )
      order by r.created_at desc
    ),
    '[]'::jsonb
  )
  into v_reports
  from public.reports r
  join public.offerings o
    on o.id = r.offering_id
  where o.user_id = p_member_user_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', e.id,
        'action', e.action,
        'reason', e.reason,
        'actor_name', coalesce(a.display_name, a.username, 'Deedlight admin'),
        'created_at', e.created_at
      )
      order by e.created_at desc
    ),
    '[]'::jsonb
  )
  into v_events
  from public.member_moderation_events e
  left join public.profiles a
    on a.user_id = e.actor_user_id
  where e.member_user_id = p_member_user_id;

  return jsonb_build_object(
    'profile', v_profile,
    'offerings', v_offerings,
    'reports', v_reports,
    'moderation_events', v_events
  );
end;
$$;

revoke all
on function public.admin_get_member_context(uuid)
from public, anon;

grant execute
on function public.admin_get_member_context(uuid)
to authenticated;

-- ---------------------------------------------------------------------
-- 3. Auditable suspension mutation.
--    Only an unsuspended database-role admin may execute it.
--    Admin accounts cannot be moderated through this member tool.
-- ---------------------------------------------------------------------

create or replace function public.set_member_suspension(
  p_member_user_id uuid,
  p_suspended boolean,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_target public.profiles%rowtype;
  v_actor uuid := auth.uid();
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'Database-backed admin access is required.'
      using errcode = '42501';
  end if;

  if p_member_user_id is null or p_suspended is null then
    raise exception 'Member and suspension state are required.'
      using errcode = '22023';
  end if;

  if char_length(v_reason) < 8 or char_length(v_reason) > 500 then
    raise exception 'Moderation reason must be between 8 and 500 characters.'
      using errcode = '22023';
  end if;

  select p.*
  into v_target
  from public.profiles p
  where p.user_id = p_member_user_id
  for update;

  if not found then
    raise exception 'Member profile not found.'
      using errcode = '22023';
  end if;

  if v_target.user_id = v_actor then
    raise exception 'You cannot suspend or restore your own account from this tool.'
      using errcode = '42501';
  end if;

  if v_target.role = 'admin' then
    raise exception 'Admin accounts are not managed by the member suspension tool.'
      using errcode = '42501';
  end if;

  if v_target.is_suspended = p_suspended then
    if p_suspended then
      raise exception 'This member is already suspended.'
        using errcode = '22023';
    else
      raise exception 'This member is already active.'
        using errcode = '22023';
    end if;
  end if;

  update public.profiles
  set is_suspended = p_suspended
  where user_id = p_member_user_id;

  insert into public.member_moderation_events (
    member_user_id,
    actor_user_id,
    action,
    reason
  )
  values (
    p_member_user_id,
    v_actor,
    case when p_suspended then 'suspended' else 'restored' end,
    v_reason
  );
end;
$$;

revoke all
on function public.set_member_suspension(uuid, boolean, text)
from public, anon;

grant execute
on function public.set_member_suspension(uuid, boolean, text)
to authenticated;

-- ---------------------------------------------------------------------
-- 4. Close the remaining suspension gaps in community writes.
--    Existing insert/reaction/report policies are already suspension-aware.
-- ---------------------------------------------------------------------

drop policy if exists "offerings_update_own_or_admin"
on public.offerings;

create policy "offerings_update_own_or_admin"
on public.offerings
for update
to authenticated
using (
  public.is_admin()
  or (
    user_id = auth.uid()
    and status in ('draft', 'needs_edit')
    and not exists (
      select 1
      from public.profiles p
      where p.user_id = auth.uid()
        and p.is_suspended = true
    )
  )
)
with check (
  public.is_admin()
  or (
    user_id = auth.uid()
    and status in ('draft', 'pending', 'needs_edit')
    and not exists (
      select 1
      from public.profiles p
      where p.user_id = auth.uid()
        and p.is_suspended = true
    )
  )
);

drop policy if exists "offerings_user_update_safe_statuses"
on public.offerings;

create policy "offerings_user_update_safe_statuses"
on public.offerings
for update
to authenticated
using (
  user_id = auth.uid()
  and status in ('draft', 'needs_edit')
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
)
with check (
  user_id = auth.uid()
  and status in ('draft', 'pending')
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

drop policy if exists "reflections_own_insert"
on public.reflections;

create policy "reflections_own_insert"
on public.reflections
for insert
to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.offerings o
    where o.id = offering_id
      and o.status = 'approved'
      and o.allow_reflections = true
  )
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

drop policy if exists "reflections_own_update"
on public.reflections;

create policy "reflections_own_update"
on public.reflections
for update
to authenticated
using (
  user_id = auth.uid()
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
)
with check (
  user_id = auth.uid()
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

-- Private Daily reflections intentionally remain member-owned and unchanged.

notify pgrst, 'reload schema';

commit;
