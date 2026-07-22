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

alter table public.profiles enable row level security;
alter table public.themes enable row level security;
alter table public.daily_posts enable row level security;
alter table public.offerings enable row level security;
alter table public.reactions enable row level security;
alter table public.reflections enable row level security;
alter table public.reports enable row level security;
alter table public.badges enable row level security;
alter table public.user_badges enable row level security;
alter table public.saved_lights enable row level security;
alter table public.daily_deed_completions enable row level security;

create policy "profiles_public_read" on public.profiles
for select using (is_suspended = false);

create policy "profiles_own_update" on public.profiles
for update using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "profiles_admin_all" on public.profiles
for all using (public.is_admin())
with check (public.is_admin());

create policy "themes_public_read" on public.themes
for select using (true);

create policy "themes_admin_all" on public.themes
for all using (public.is_admin())
with check (public.is_admin());

create policy "daily_posts_public_published_read" on public.daily_posts
for select using (status = 'published');

create policy "daily_posts_admin_all" on public.daily_posts
for all using (public.is_admin())
with check (public.is_admin());

create policy "offerings_public_approved_read" on public.offerings
for select using (status = 'approved');

create policy "offerings_own_read" on public.offerings
for select using (user_id = auth.uid());

create policy "offerings_user_insert_pending" on public.offerings
for insert with check (
  user_id = auth.uid()
  and status in ('draft','pending')
  and not exists (
    select 1 from public.profiles p
    where p.user_id = auth.uid() and p.is_suspended = true
  )
);

create policy "offerings_user_update_safe_statuses" on public.offerings
for update using (
  user_id = auth.uid()
  and status in ('draft','needs_edit')
) with check (
  user_id = auth.uid()
  and status in ('draft','pending')
);

create policy "offerings_admin_all" on public.offerings
for all using (public.is_admin())
with check (public.is_admin());

create policy "reactions_own_insert" on public.reactions
for insert with check (user_id = auth.uid());

create policy "reactions_own_delete" on public.reactions
for delete using (user_id = auth.uid());

create policy "reactions_own_read" on public.reactions
for select using (user_id = auth.uid() or public.is_admin());

create policy "reactions_admin_all" on public.reactions
for all using (public.is_admin())
with check (public.is_admin());

create policy "reflections_public_visible_read" on public.reflections
for select using (
  status = 'visible'
  and exists (select 1 from public.offerings o where o.id = offering_id and o.status = 'approved')
);

create policy "reflections_own_insert" on public.reflections
for insert with check (
  user_id = auth.uid()
  and exists (select 1 from public.offerings o where o.id = offering_id and o.status = 'approved' and o.allow_reflections = true)
);

create policy "reflections_own_update" on public.reflections
for update using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "reflections_admin_all" on public.reflections
for all using (public.is_admin())
with check (public.is_admin());

create policy "reports_own_insert" on public.reports
for insert with check (reported_by = auth.uid());

create policy "reports_admin_all" on public.reports
for all using (public.is_admin())
with check (public.is_admin());

create policy "badges_public_read" on public.badges
for select using (true);

create policy "badges_admin_all" on public.badges
for all using (public.is_admin())
with check (public.is_admin());

create policy "user_badges_public_read" on public.user_badges
for select using (true);

create policy "user_badges_admin_all" on public.user_badges
for all using (public.is_admin())
with check (public.is_admin());

create policy "saved_lights_own_all" on public.saved_lights
for all using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "daily_deed_completions_own_all" on public.daily_deed_completions
for all using (user_id = auth.uid())
with check (user_id = auth.uid());

-- Storage buckets. Safe to re-run.
insert into storage.buckets (id, name, public)
values
  ('daily-lights', 'daily-lights', true),
  ('offerings-media', 'offerings-media', true),
  ('profile-avatars', 'profile-avatars', true),
  ('admin-assets', 'admin-assets', false),
  ('share-cards', 'share-cards', true)
on conflict (id) do nothing;

create policy "storage_public_read_public_buckets" on storage.objects
for select using (bucket_id in ('daily-lights','offerings-media','profile-avatars','share-cards'));

create policy "storage_user_upload_offering_media" on storage.objects
for insert with check (
  bucket_id = 'offerings-media'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "storage_user_update_own_offering_media" on storage.objects
for update using (
  bucket_id = 'offerings-media'
  and auth.uid()::text = (storage.foldername(name))[1]
) with check (
  bucket_id = 'offerings-media'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "storage_user_upload_own_avatar" on storage.objects
for insert with check (
  bucket_id = 'profile-avatars'
  and auth.uid()::text = (storage.foldername(name))[1]
);

create policy "storage_admin_all" on storage.objects
for all using (public.is_admin())
with check (public.is_admin());
