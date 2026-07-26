-- Deedlight Sprint 5 — Admin Content Quality + Moderation Upgrade
-- Safe to run more than once.

-- 1. Permissions needed by Supabase API roles.
grant usage on schema public to anon, authenticated, service_role;
grant select on public.offerings_public to anon, authenticated;
grant select on public.offerings_rising to anon, authenticated;
grant select on public.offerings to authenticated;
grant insert, update on public.offerings to authenticated;
grant select, insert, update on public.reports to authenticated;
grant all on all tables in schema public to service_role;

-- 2. Useful moderation indexes.
create index if not exists reports_status_created_idx
on public.reports(status, created_at desc);

create index if not exists reports_offering_status_idx
on public.reports(offering_id, status, created_at desc);

create index if not exists offerings_open_report_count_idx
on public.offerings(open_report_count desc, created_at desc);

-- 3. Stable admin helper.
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

-- 4. Offerings RLS: admin can edit/hide/approve; members can edit their drafts/needs_edit.
alter table public.offerings enable row level security;

drop policy if exists "offerings_select_public_or_own" on public.offerings;
create policy "offerings_select_public_or_own"
on public.offerings
for select
using (
  status = 'approved'
  or user_id = auth.uid()
  or public.is_admin()
);

drop policy if exists "offerings_insert_own_pending" on public.offerings;
create policy "offerings_insert_own_pending"
on public.offerings
for insert
with check (
  user_id = auth.uid()
  and status in ('draft', 'pending')
  and not exists (
    select 1 from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

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

-- 5. Reports RLS: users can create and read their own reports; admins can manage all reports.
alter table public.reports enable row level security;

drop policy if exists "reports_own_insert" on public.reports;
drop policy if exists "reports_admin_all" on public.reports;
drop policy if exists "reports_select_own_or_admin" on public.reports;
drop policy if exists "reports_insert_own_approved_offering" on public.reports;
drop policy if exists "reports_admin_update" on public.reports;

create policy "reports_select_own_or_admin"
on public.reports
for select
using (reported_by = auth.uid() or public.is_admin());

create policy "reports_insert_own_approved_offering"
on public.reports
for insert
with check (
  reported_by = auth.uid()
  and (
    offering_id is null
    or exists (
      select 1 from public.offerings o
      where o.id = offering_id
        and o.status = 'approved'
    )
  )
  and not exists (
    select 1 from public.profiles p
    where p.user_id = auth.uid()
      and p.is_suspended = true
  )
);

create policy "reports_admin_update"
on public.reports
for update
using (public.is_admin())
with check (public.is_admin());

create policy "reports_admin_all"
on public.reports
for all
using (public.is_admin())
with check (public.is_admin());

-- 6. Ensure report count triggers exist and repair current counts.
create or replace function public.handle_report_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.offering_id is not null and new.status = 'open' then
      update public.offerings set open_report_count = open_report_count + 1 where id = new.offering_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.offering_id is not null and old.status = 'open' then
      update public.offerings set open_report_count = greatest(0, open_report_count - 1) where id = old.offering_id;
    end if;
    return old;
  elsif tg_op = 'UPDATE' then
    if new.offering_id is not null then
      if old.status <> 'open' and new.status = 'open' then
        update public.offerings set open_report_count = open_report_count + 1 where id = new.offering_id;
      elsif old.status = 'open' and new.status <> 'open' then
        update public.offerings set open_report_count = greatest(0, open_report_count - 1) where id = old.offering_id;
      end if;
    end if;
    return new;
  end if;
  return null;
end;
$$;

drop trigger if exists reports_count_insert on public.reports;
create trigger reports_count_insert
after insert on public.reports
for each row execute function public.handle_report_counts();

drop trigger if exists reports_count_update on public.reports;
create trigger reports_count_update
after update of status on public.reports
for each row execute function public.handle_report_counts();

drop trigger if exists reports_count_delete on public.reports;
create trigger reports_count_delete
after delete on public.reports
for each row execute function public.handle_report_counts();

update public.offerings o
set open_report_count = counts.open_report_count
from (
  select
    o2.id,
    count(*) filter (where r.status = 'open')::integer as open_report_count
  from public.offerings o2
  left join public.reports r on r.offering_id = o2.id
  group by o2.id
) counts
where counts.id = o.id;
