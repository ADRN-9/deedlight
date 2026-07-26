-- Deedlight Sprint 4 — Bless / Inspired / Did Too reactions
-- Safe to run more than once.

-- 1. Make sure API roles have the permissions needed for reaction reads/writes.
grant usage on schema public to anon, authenticated, service_role;
grant select on public.offerings to anon, authenticated;
grant select on public.offerings_public to anon, authenticated;
grant select, insert, delete on public.reactions to authenticated;
grant all on all tables in schema public to service_role;

-- 2. Keep the admin helper stable.
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where user_id = auth.uid()
      and role = 'admin'
      and is_suspended = false
  );
$$;

grant execute on function public.is_admin() to anon, authenticated;

-- 3. Make the reaction count trigger idempotent and reliable.
create or replace function public.handle_reaction_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.offerings set
      bless_count = bless_count + case when new.reaction_type = 'bless' then 1 else 0 end,
      inspired_count = inspired_count + case when new.reaction_type = 'inspired_me' then 1 else 0 end,
      carried_forward_count = carried_forward_count + case when new.reaction_type = 'i_did_this_too' then 1 else 0 end
    where id = new.offering_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.offerings set
      bless_count = greatest(0, bless_count - case when old.reaction_type = 'bless' then 1 else 0 end),
      inspired_count = greatest(0, inspired_count - case when old.reaction_type = 'inspired_me' then 1 else 0 end),
      carried_forward_count = greatest(0, carried_forward_count - case when old.reaction_type = 'i_did_this_too' then 1 else 0 end)
    where id = old.offering_id;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists reactions_count_insert on public.reactions;
create trigger reactions_count_insert
after insert on public.reactions
for each row execute function public.handle_reaction_counts();

drop trigger if exists reactions_count_delete on public.reactions;
create trigger reactions_count_delete
after delete on public.reactions
for each row execute function public.handle_reaction_counts();

-- 4. RLS: users may only react to approved public Offerings, and only as themselves.
alter table public.reactions enable row level security;

drop policy if exists "reactions_own_insert" on public.reactions;
drop policy if exists "reactions_own_delete" on public.reactions;
drop policy if exists "reactions_own_read" on public.reactions;
drop policy if exists "reactions_admin_all" on public.reactions;
drop policy if exists "reactions_select_own_or_admin" on public.reactions;
drop policy if exists "reactions_insert_own_on_approved" on public.reactions;
drop policy if exists "reactions_delete_own" on public.reactions;

create policy "reactions_select_own_or_admin"
on public.reactions
for select
using (user_id = auth.uid() or public.is_admin());

create policy "reactions_insert_own_on_approved"
on public.reactions
for insert
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.offerings o
    where o.id = offering_id
      and o.status = 'approved'
  )
  and not exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

create policy "reactions_delete_own"
on public.reactions
for delete
using (user_id = auth.uid());

create policy "reactions_admin_all"
on public.reactions
for all
using (public.is_admin())
with check (public.is_admin());

-- 5. Repair count drift, if any earlier tests were run while triggers/policies changed.
update public.offerings o
set
  bless_count = counts.bless_count,
  inspired_count = counts.inspired_count,
  carried_forward_count = counts.carried_forward_count
from (
  select
    o2.id,
    count(*) filter (where r.reaction_type = 'bless')::integer as bless_count,
    count(*) filter (where r.reaction_type = 'inspired_me')::integer as inspired_count,
    count(*) filter (where r.reaction_type = 'i_did_this_too')::integer as carried_forward_count
  from public.offerings o2
  left join public.reactions r on r.offering_id = o2.id
  group by o2.id
) counts
where counts.id = o.id;

-- 6. Helper view for Rising Goodness.
-- Uses reaction score first, then freshness. It exposes no private reaction rows.
create or replace view public.offerings_rising as
select
  op.*,
  (
    coalesce(op.bless_score, 0)
    + case
        when op.published_at is null then 0
        when op.published_at > now() - interval '24 hours' then 30
        when op.published_at > now() - interval '7 days' then 12
        else 0
      end
  )::numeric as rising_score
from public.offerings_public op;

grant select on public.offerings_rising to anon, authenticated;
