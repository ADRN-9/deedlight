-- Sprint 12.1 — Offering Ownership & Engagement
-- Adds safe owner editing/removal/restore flows and private Offering saves.
-- Public attribution remains privacy-minimized; no public save counts or owner UUIDs are introduced.

begin;

-- ---------------------------------------------------------------------
-- 1. Distinguish member-removed Offerings from moderator-hidden content.
-- ---------------------------------------------------------------------

alter table public.offerings
  add column if not exists owner_removed_at timestamptz;

create index if not exists offerings_owner_removed_idx
  on public.offerings (user_id, owner_removed_at desc)
  where owner_removed_at is not null;

-- Keep owner_removed_at under the controlled owner RPCs rather than ordinary
-- browser INSERT/UPDATE privileges. Admin behavior is preserved.

drop policy if exists "offerings_user_insert_pending"
on public.offerings;

create policy "offerings_user_insert_pending"
on public.offerings
for insert
to authenticated
with check (
  user_id = auth.uid()
  and status in ('draft', 'pending')
  and owner_removed_at is null
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

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
    and owner_removed_at is null
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
    and owner_removed_at is null
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
  and owner_removed_at is null
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
  and owner_removed_at is null
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

-- ---------------------------------------------------------------------
-- 2. Extend private Saved Lights to approved Offerings.
--    Saves remain private, immutable rows: insert to save, delete to unsave.
-- ---------------------------------------------------------------------

drop policy if exists
  "saved_lights_insert_own_published_daily_light"
on public.saved_lights;

drop policy if exists
  "saved_lights_insert_own_published_source"
on public.saved_lights;

create policy
  "saved_lights_insert_own_published_source"
on public.saved_lights
for insert
to authenticated
with check (
  user_id = auth.uid()
  and (
    (
      daily_light_id is not null
      and offering_id is null
      and daily_post_id is null
      and exists (
        select 1
        from public.daily_lights dl
        where dl.id = daily_light_id
          and dl.status = 'published'
      )
    )
    or
    (
      offering_id is not null
      and daily_light_id is null
      and daily_post_id is null
      and exists (
        select 1
        from public.offerings_public op
        where op.id = offering_id
      )
    )
  )
);

revoke all privileges
on table public.saved_lights
from public, anon, authenticated;

grant select, insert, delete
on table public.saved_lights
to authenticated;

grant all
on table public.saved_lights
to service_role;

-- Repair the post-privacy reaction policy so members can react to any
-- approved public Offering, not only an Offering visible through own-row RLS.
-- The public view exposes no owner UUIDs and is sufficient for this boolean check.
drop policy if exists "reactions_insert_own_on_approved"
on public.reactions;

create policy "reactions_insert_own_on_approved"
on public.reactions
for insert
to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.offerings_public op
    where op.id = offering_id
  )
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

-- ---------------------------------------------------------------------
-- 3. Owner edit RPC.
--    Any edited public version leaves public discovery and returns to review.
--    Rejected or moderator-hidden Offerings cannot be bypassed by members.
-- ---------------------------------------------------------------------

create or replace function public.update_own_offering(
  p_offering_id uuid,
  p_offering_type text,
  p_title text,
  p_body text,
  p_takeaway text,
  p_media_url text,
  p_media_type text,
  p_is_anonymous boolean,
  p_allow_reflections boolean
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_offering public.offerings%rowtype;
  v_title text := btrim(coalesce(p_title, ''));
  v_body text := btrim(coalesce(p_body, ''));
  v_takeaway text := nullif(btrim(coalesce(p_takeaway, '')), '');
  v_media_url text := nullif(btrim(coalesce(p_media_url, '')), '');
  v_media_type text := p_media_type;
begin
  if v_actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.user_id = v_actor
      and p.is_suspended = false
  ) then
    raise exception 'An active member profile is required.' using errcode = '42501';
  end if;

  if p_offering_id is null then
    raise exception 'Offering is required.' using errcode = '22023';
  end if;

  if p_offering_type not in (
    'good_deed',
    'goodness_invitation',
    'gratitude',
    'beauty_reminder',
    'quiet_goodness',
    'community_need'
  ) then
    raise exception 'Invalid Offering type.' using errcode = '22023';
  end if;

  if char_length(v_title) < 4 or char_length(v_title) > 120 then
    raise exception 'Title must be between 4 and 120 characters.' using errcode = '22023';
  end if;

  if char_length(v_body) < 20 or char_length(v_body) > 5000 then
    raise exception 'Offering body must be between 20 and 5000 characters.' using errcode = '22023';
  end if;

  if v_takeaway is not null and char_length(v_takeaway) > 500 then
    raise exception 'Small deed must be 500 characters or fewer.' using errcode = '22023';
  end if;

  if v_media_url is not null and char_length(v_media_url) > 1000 then
    raise exception 'Media URL is too long.' using errcode = '22023';
  end if;

  if v_media_url is not null and v_media_url !~* '^https?://' then
    raise exception 'Media URL must use http or https.' using errcode = '22023';
  end if;

  if v_media_url is null then
    v_media_type := null;
  elsif v_media_type is null or v_media_type not in ('image', 'video') then
    raise exception 'Media type is invalid.' using errcode = '22023';
  end if;

  select o.*
  into v_offering
  from public.offerings o
  where o.id = p_offering_id
    and o.user_id = v_actor
  for update;

  if not found then
    raise exception 'Offering was not found.' using errcode = '42501';
  end if;

  if v_offering.status = 'rejected' then
    raise exception 'Rejected Offerings cannot be resubmitted from the member editor.' using errcode = '42501';
  end if;

  if v_offering.status = 'hidden' and v_offering.owner_removed_at is null then
    raise exception 'Moderator-hidden Offerings cannot be changed from the member editor.' using errcode = '42501';
  end if;

  update public.offerings
  set
    offering_type = p_offering_type,
    title = v_title,
    body = v_body,
    takeaway = v_takeaway,
    media_url = v_media_url,
    media_type = v_media_type,
    is_anonymous = coalesce(p_is_anonymous, false),
    allow_reflections = coalesce(p_allow_reflections, false),
    status = 'pending',
    moderation_note = null,
    published_at = null,
    owner_removed_at = null
  where id = p_offering_id;

  return p_offering_id;
end;
$$;

revoke all
on function public.update_own_offering(
  uuid, text, text, text, text, text, text, boolean, boolean
)
from public, anon;

grant execute
on function public.update_own_offering(
  uuid, text, text, text, text, text, text, boolean, boolean
)
to authenticated;

-- ---------------------------------------------------------------------
-- 4. Reversible owner removal.
--    This is intentionally a soft removal, not browser DELETE.
--    A suspended owner may still remove their own content for privacy/safety.
-- ---------------------------------------------------------------------

create or replace function public.remove_own_offering(
  p_offering_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_offering public.offerings%rowtype;
begin
  if v_actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  select o.*
  into v_offering
  from public.offerings o
  where o.id = p_offering_id
    and o.user_id = v_actor
  for update;

  if not found then
    raise exception 'Offering was not found.' using errcode = '42501';
  end if;

  if v_offering.status = 'hidden' and v_offering.owner_removed_at is null then
    raise exception 'Moderator-hidden Offerings cannot be changed from the member controls.' using errcode = '42501';
  end if;

  if v_offering.owner_removed_at is not null then
    return p_offering_id;
  end if;

  update public.offerings
  set
    status = 'hidden',
    owner_removed_at = now(),
    published_at = null
  where id = p_offering_id;

  return p_offering_id;
end;
$$;

revoke all
on function public.remove_own_offering(uuid)
from public, anon;

grant execute
on function public.remove_own_offering(uuid)
to authenticated;

-- ---------------------------------------------------------------------
-- 5. Restore an owner-removed Offering to moderation review.
-- ---------------------------------------------------------------------

create or replace function public.restore_own_offering(
  p_offering_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_offering public.offerings%rowtype;
begin
  if v_actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.user_id = v_actor
      and p.is_suspended = false
  ) then
    raise exception 'An active member profile is required.' using errcode = '42501';
  end if;

  select o.*
  into v_offering
  from public.offerings o
  where o.id = p_offering_id
    and o.user_id = v_actor
  for update;

  if not found then
    raise exception 'Offering was not found.' using errcode = '42501';
  end if;

  if v_offering.status <> 'hidden' or v_offering.owner_removed_at is null then
    raise exception 'Only an Offering you removed can be restored.' using errcode = '42501';
  end if;

  update public.offerings
  set
    status = 'pending',
    owner_removed_at = null,
    moderation_note = null,
    published_at = null
  where id = p_offering_id;

  return p_offering_id;
end;
$$;

revoke all
on function public.restore_own_offering(uuid)
from public, anon;

grant execute
on function public.restore_own_offering(uuid)
to authenticated;

notify pgrst, 'reload schema';

commit;
