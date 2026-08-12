-- Sprint 10.3A — Gentle Daily Reminder Preferences
-- Stores private, opt-in reminder preferences without introducing delivery transport.
-- Reminder delivery remains a later infrastructure step.

begin;

create table if not exists public.daily_reminder_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  daily_enabled boolean not null default false,
  reminder_time time without time zone not null default '08:00',
  timezone text not null default 'UTC'
    check (
      char_length(timezone) between 1 and 64
      and timezone ~ '^[A-Za-z0-9_+./-]+$'
    ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists daily_reminder_preferences_set_updated_at
on public.daily_reminder_preferences;

create trigger daily_reminder_preferences_set_updated_at
before update on public.daily_reminder_preferences
for each row execute function public.set_updated_at();

alter table public.daily_reminder_preferences
  enable row level security;

drop policy if exists
  "daily_reminder_preferences_select_own"
on public.daily_reminder_preferences;

drop policy if exists
  "daily_reminder_preferences_insert_own"
on public.daily_reminder_preferences;

drop policy if exists
  "daily_reminder_preferences_update_own"
on public.daily_reminder_preferences;

create policy
  "daily_reminder_preferences_select_own"
on public.daily_reminder_preferences
for select
to authenticated
using (
  user_id = auth.uid()
);

create policy
  "daily_reminder_preferences_insert_own"
on public.daily_reminder_preferences
for insert
to authenticated
with check (
  user_id = auth.uid()
  and (
    daily_enabled = false
    or not exists (
      select 1
      from public.profiles p
      where p.user_id = auth.uid()
        and p.is_suspended = true
    )
  )
);

create policy
  "daily_reminder_preferences_update_own"
on public.daily_reminder_preferences
for update
to authenticated
using (
  user_id = auth.uid()
)
with check (
  user_id = auth.uid()
  and (
    daily_enabled = false
    or not exists (
      select 1
      from public.profiles p
      where p.user_id = auth.uid()
        and p.is_suspended = true
    )
  )
);

revoke all privileges
on table public.daily_reminder_preferences
from public, anon, authenticated;

grant select, insert, update
on table public.daily_reminder_preferences
to authenticated;

grant all
on table public.daily_reminder_preferences
to service_role;

notify pgrst, 'reload schema';

commit;
