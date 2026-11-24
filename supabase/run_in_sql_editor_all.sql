-- DeedLight SQL Editor aggregate v1
-- Deterministically generated from immutable Git-blob-pinned migration sources and the maintained bootstrap seed.
-- Inventory Git blob SHA-1: 95d514a0bd97ff448c9507252eb1f5e69a507442
-- BEGIN SOURCE PROVENANCE
-- SOURCE 202607210001 202607210001_initial_schema.sql blob=a244ab0df3e766b0f36e29a222b3160f9f74c502 bytes=13648
-- SOURCE 202607210002 202607210002_rls_policies.sql blob=f96b482c0d1cf396baae5b91d7c96112f7e88284 bytes=5885
-- SOURCE 202607220003 202607220003_sprint3_offerings_review.sql blob=74e02f2e60b82cf07a6aac5f8cf57dcdb6fe1382 bytes=1064
-- SOURCE 202607260004 202607260004_sprint4_reactions.sql blob=c25dce46ecf69d082fcdbea2bb931b6acd9180fc bytes=4983
-- SOURCE 202607260005 202607260005_sprint5_moderation.sql blob=b48b4b8b3eea9fb55b68068011fa1371559228c2 bytes=5775
-- SOURCE 202607260006 202607260006_sprint5_admin_edit_hide_hotfix.sql blob=9e163de5119c3813724341b7a9eabeba6fdc2970 bytes=2008
-- SOURCE 202607260007 202607260007_sprint6_daily_deedlight.sql blob=e0c2379255003b8c7bc85a1fab781e23051f5e47 bytes=9545
-- SOURCE 202607260007 202607260007_sprint7_pwa_daily_engagement.sql blob=8b051cfce05ea75b1ee7a726864e2ad760f6fe5f bytes=6279
-- SOURCE 202607270008 202607270008_sprint8_short_video_studio.sql blob=5b583bd99562e14db554943d034c748ce302f5ee bytes=1890
-- SOURCE 202608060009 202608060009_sprint9_profiles_privacy.sql blob=6594ce6daa0183944fcc548885d6514e8adb9436 bytes=6031
-- SOURCE 202608100010 202608100010_sprint9_2_community_identity_consistency.sql blob=774708b7705d88a5a1e0da97e72a9d1b47c8884c bytes=3294
-- SOURCE 202608100011 202608100011_sprint9_3_moderation_aware_members.sql blob=1d1b7b844b88077351d2658af4be2b2db92eda97 bytes=12225
-- SOURCE 202608110012 202608110012_sprint10_1_daily_deed_completion.sql blob=0973f72e39ce07b41e053a20f1b781c394578877 bytes=4462
-- SOURCE 202608110013 202608110013_sprint10_2_saved_lights_gentle_rhythm.sql blob=5fd2f4a796a8a1dfd6237ccf36d1ab62c1dc1714 bytes=2769
-- SOURCE 202608120014 202608120014_sprint10_3_gentle_reminder_preferences.sql blob=2af1a6a2aa5cffc6ef6d08849b6f71fab44a54d0 bytes=2523
-- SOURCE 202608130015 202608130015_sprint11_2_weekly_goodness.sql blob=394c774032d8206c0b7a373640859c2a331667a9 bytes=8089
-- SOURCE 202608130016 202608130016_sprint11_3_invitations_newsletter_foundation.sql blob=8d68ed19859e1a820af52a43c110a38b6a460d48 bytes=12951
-- SOURCE 202608130017 202608130017_sprint12_1_offering_ownership_engagement.sql blob=bc23b12fe454c1f49b096fd2c7199e3a2aea5bb4 bytes=11901
-- SOURCE 202608140018 202608140018_sprint12_1_owner_removal_guard_hotfix.sql blob=0ea7eaf04d5c99e4c5a25893aae7694affdd44bc bytes=2780
-- SOURCE 202609230019 202609230019_sprint12_2_gentle_delivery_foundation.sql blob=1403b9324e786a2b724176875a70ffce92961d9b bytes=15845
-- SOURCE 202609230020 202609230020_delivery_reliability_hardening.sql blob=554615da3d15fc4c0d395691103d3be5676856fa bytes=13642
-- SOURCE 202609230021 202609230021_gentle_delivery_transport.sql blob=e50a06bd3a5ed386c54e789435c64b2bb4a54ab9 bytes=3417
-- SOURCE 202609240022 202609240022_auth_pgcrypto_schema_qualification.sql blob=f42afb3474f80c7d95cf5b47023b82cf5a948d4d bytes=1214
-- SOURCE 202611120023 202611120023_delivery_consent_linearization.sql blob=75f5086feab2cbda381066cb9094390190c3332f bytes=9411
-- SOURCE 202611120024 202611120024_delivery_identity_lease_capacity.sql blob=240271fd75081c062627cfc3d40bdc0c5feda049 bytes=12329
-- SOURCE 202611190025 202611190025_delivery_provider_webhooks.sql blob=e97c5c0ad645dfe43f11a88f01b030fa23dd5822 bytes=17132
-- SOURCE 202611190026 202611190026_delivery_provider_lifecycle.sql blob=6a06d780ad65babf2293a2746c68913758313af8 bytes=13857
-- SOURCE 202611200027 202611200027_delivery_provider_integrity.sql blob=a1469938ea13b5cb9d7cd883772bc60e4a058026 bytes=20879
-- SOURCE 202611210028 202611210028_delivery_claim_lock_expiry.sql blob=09d1927fba81d711bb37d214609931d2da2173a1 bytes=9643
-- SOURCE 202611210029 202611210029_delivery_legacy_replay_guard.sql blob=872fc49ec47e49b17e96ecf6ccaf5c8eb0e6322a bytes=7476
-- SOURCE 202611210030 202611210030_delivery_idempotency_receipt_guard.sql blob=c5e3955c4e0dde708a8ffdc9c420807c4241fa32 bytes=12214
-- SOURCE 202611220031 202611220031_delivery_final_recipient_suppression_gate.sql blob=26d69a0a4e73bc7cfd05814f3f6129bc199da02b bytes=6477
-- SOURCE 202611220032 202611220032_resend_suppression_list_sync.sql blob=6a0c0193d85ece99335f8715a65243ac42617f97 bytes=14118
-- SOURCE 202611220033 202611220033_delivery_cross_stream_suppression_order.sql blob=1cd0c2db5415a37b9a31ed8ef7de54db9019a88f bytes=4647
-- SOURCE 202611230034 202611230034_delivery_suppression_timestamp_order.sql blob=4ec8aa578ad851918f4c4b2535c476b4ceb40f1d bytes=11255
-- SOURCE 202611230035 202611230035_private_offering_base_table_rls.sql blob=3d0ce8dfd4abb88fccccd23c5ffb9c35f699c098 bytes=564
-- SOURCE 202611230036 202611230036_private_daily_reflection_admin_isolation.sql blob=61a1fbf48b4557873ba6016e74fd3995bc62ba14 bytes=2042
-- SOURCE 202611240037 202611240037_delivery_provider_integrity_conflict_evidence.sql blob=ac0449b50a881e3a895ef40a8eee28bea95a6ec0 bytes=44182
-- SOURCE 202611240038 202611240038_delivery_provider_integrity_lock_order_pagination.sql blob=38951751fc5abeb79b75c4e37e55da01262a18b8 bytes=43748
-- BOOTSTRAP SEED supabase/seed.sql blob=e85554aed1553dec407e83966a1b0093f5d1e9a3 bytes=2574 upserts=3
-- END SOURCE PROVENANCE
-- BEGIN MIGRATION SQL
create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  username text unique,
  display_name text not null,
  avatar_url text,
  bio text,
  country text,
  role text not null default 'member' check (role in ('member','trusted_member','moderator','admin')),
  is_verified boolean not null default false,
  is_suspended boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create table if not exists public.themes (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  icon_name text,
  accent_color text,
  created_at timestamptz not null default now()
);

create table if not exists public.daily_posts (
  id uuid primary key default gen_random_uuid(),
  date date not null unique,
  slug text not null unique,
  title text not null,
  theme_id uuid references public.themes(id),
  reflection text not null,
  daily_action text not null,
  reflection_question text,
  image_url text,
  youtube_url text,
  status text not null default 'draft' check (status in ('draft','scheduled','published','archived')),
  created_by uuid references auth.users(id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger daily_posts_set_updated_at
before update on public.daily_posts
for each row execute function public.set_updated_at();

create table if not exists public.offerings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  theme_id uuid references public.themes(id),
  offering_type text not null check (offering_type in ('good_deed','goodness_invitation','gratitude','beauty_reminder','quiet_goodness','community_need')),
  title text not null check (char_length(title) between 4 and 120),
  body text not null check (char_length(body) between 20 and 5000),
  takeaway text,
  media_url text,
  media_type text check (media_type is null or media_type in ('image','video')),
  is_anonymous boolean not null default false,
  allow_reflections boolean not null default true,
  location_label text,
  status text not null default 'pending' check (status in ('draft','pending','approved','rejected','needs_edit','hidden')),
  moderation_note text,
  bless_count integer not null default 0 check (bless_count >= 0),
  inspired_count integer not null default 0 check (inspired_count >= 0),
  carried_forward_count integer not null default 0 check (carried_forward_count >= 0),
  reflection_count integer not null default 0 check (reflection_count >= 0),
  open_report_count integer not null default 0 check (open_report_count >= 0),
  bless_score numeric generated always as (
    bless_count * 1 + inspired_count * 3 + carried_forward_count * 5 + reflection_count * 2 - open_report_count * 10
  ) stored,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists offerings_status_published_idx on public.offerings(status, published_at desc);
create index if not exists offerings_bless_score_idx on public.offerings(bless_score desc);
create index if not exists offerings_user_id_idx on public.offerings(user_id);

create trigger offerings_set_updated_at
before update on public.offerings
for each row execute function public.set_updated_at();

create table if not exists public.reactions (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid not null references public.offerings(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction_type text not null check (reaction_type in ('bless','inspired_me','i_did_this_too')),
  created_at timestamptz not null default now(),
  unique (offering_id, user_id, reaction_type)
);

create index if not exists reactions_offering_id_idx on public.reactions(offering_id);
create index if not exists reactions_user_id_idx on public.reactions(user_id);

create table if not exists public.reflections (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid not null references public.offerings(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 2 and 2000),
  status text not null default 'visible' check (status in ('visible','hidden','removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger reflections_set_updated_at
before update on public.reflections
for each row execute function public.set_updated_at();

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid references public.offerings(id) on delete cascade,
  reflection_id uuid references public.reflections(id) on delete cascade,
  reported_by uuid references auth.users(id) on delete set null,
  reason text not null check (reason in ('exposes_vulnerable_person','hate_or_prejudice','fake_charity_or_fraud','harassment','graphic_or_disturbing','self_promotion','privacy_concern','other')),
  details text,
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  admin_note text,
  resolved_by uuid references auth.users(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  check (offering_id is not null or reflection_id is not null)
);

create table if not exists public.badges (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text not null,
  icon_name text,
  level_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.user_badges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade,
  awarded_at timestamptz not null default now(),
  unique (user_id, badge_id)
);

create table if not exists public.saved_lights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  offering_id uuid references public.offerings(id) on delete cascade,
  daily_post_id uuid references public.daily_posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  check ((offering_id is not null) <> (daily_post_id is not null))
);

create unique index if not exists saved_lights_unique_offering
on public.saved_lights(user_id, offering_id)
where offering_id is not null;

create unique index if not exists saved_lights_unique_daily_post
on public.saved_lights(user_id, daily_post_id)
where daily_post_id is not null;

create table if not exists public.daily_deed_completions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  daily_post_id uuid not null references public.daily_posts(id) on delete cascade,
  status text not null default 'completed' check (status in ('try','completed')),
  created_at timestamptz not null default now(),
  unique (user_id, daily_post_id, status)
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'display_name', ''), split_part(new.email, '@', 1), 'Deedlight member')
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

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



create or replace function public.handle_reflection_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'visible' then
      update public.offerings set reflection_count = reflection_count + 1 where id = new.offering_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.status = 'visible' then
      update public.offerings set reflection_count = greatest(0, reflection_count - 1) where id = old.offering_id;
    end if;
    return old;
  elsif tg_op = 'UPDATE' then
    if old.status <> 'visible' and new.status = 'visible' then
      update public.offerings set reflection_count = reflection_count + 1 where id = new.offering_id;
    elsif old.status = 'visible' and new.status <> 'visible' then
      update public.offerings set reflection_count = greatest(0, reflection_count - 1) where id = old.offering_id;
    end if;
    return new;
  end if;
  return null;
end;
$$;

drop trigger if exists reflections_count_insert on public.reflections;
create trigger reflections_count_insert
after insert on public.reflections
for each row execute function public.handle_reflection_counts();

drop trigger if exists reflections_count_update on public.reflections;
create trigger reflections_count_update
after update of status on public.reflections
for each row execute function public.handle_reflection_counts();

drop trigger if exists reflections_count_delete on public.reflections;
create trigger reflections_count_delete
after delete on public.reflections
for each row execute function public.handle_reflection_counts();

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
        update public.offerings set open_report_count = greatest(0, open_report_count - 1) where id = new.offering_id;
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

create or replace view public.offerings_public as
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

-- BEGIN BOOTSTRAP SEED (three idempotent upserts)
insert into public.themes (slug, name, description, icon_name, accent_color)
values
  ('kindness', 'Kindness', 'Small acts that make life softer.', 'hand-heart', '#C9826B'),
  ('courage', 'Courage', 'Protecting dignity and truth with gentleness.', 'shield-flame', '#D9A441'),
  ('mercy', 'Mercy', 'Choosing compassion over cruelty.', 'open-palm', '#DCE9F5'),
  ('honesty', 'Honesty', 'Clear, truthful, trustworthy goodness.', 'gem-light', '#DCE9F5'),
  ('patience', 'Patience', 'Goodness that waits without bitterness.', 'hourglass-leaf', '#A8BFA3'),
  ('gratitude', 'Gratitude', 'Remembering goodness received.', 'hands-heart', '#C9826B'),
  ('beauty', 'Beauty', 'Moments that restore hope.', 'flower-sun', '#F4C76B'),
  ('justice', 'Justice', 'Fairness carried with dignity.', 'balanced-light', '#D9A441'),
  ('humility', 'Humility', 'Goodness without showing off.', 'small-candle', '#FFF8EA'),
  ('community', 'Community', 'Many small lights together.', 'circle-lights', '#A8BFA3')
on conflict (slug) do update set
  name = excluded.name,
  description = excluded.description,
  icon_name = excluded.icon_name,
  accent_color = excluded.accent_color;

insert into public.daily_posts (
  date,
  slug,
  title,
  theme_id,
  reflection,
  daily_action,
  reflection_question,
  status,
  published_at
)
values (
  current_date,
  'protect-someones-dignity',
  'Protect someone’s dignity',
  (select id from public.themes where slug = 'courage'),
  'Beauty is not only found in nature. Sometimes beauty appears when one person refuses to join cruelty.',
  'Say one gentle sentence in defense of someone who is being judged unfairly.',
  'Did I make one place safer for goodness today?',
  'published',
  now()
)
on conflict (date) do update set
  title = excluded.title,
  theme_id = excluded.theme_id,
  reflection = excluded.reflection,
  daily_action = excluded.daily_action,
  reflection_question = excluded.reflection_question,
  status = excluded.status,
  published_at = excluded.published_at;

insert into public.badges (slug, name, description, icon_name, level_name)
values
  ('quiet-helper-spark', 'Quiet Helper', 'Shared humble or anonymous goodness.', 'moon-hand', 'Spark'),
  ('kindness-carrier-spark', 'Kindness Carrier', 'Carried repeated acts of kindness.', 'hand-heart', 'Spark'),
  ('beauty-reminder-spark', 'Beauty Reminder', 'Shared beauty that restored hope.', 'flower-sun', 'Spark')
on conflict (slug) do update set
  name = excluded.name,
  description = excluded.description,
  icon_name = excluded.icon_name,
  level_name = excluded.level_name;

-- END BOOTSTRAP SEED
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
-- Sprint 6 — Daily Deedlight Content System
-- Adds daily content scheduling, archiving, featured offerings, reflections/check-ins, and short-video planning fields.

create extension if not exists pgcrypto;

-- Keep this helper available even if an older migration was not applied.
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
      and coalesce(is_suspended, false) = false
  );
$$;

grant execute on function public.is_admin() to anon, authenticated;

create table if not exists public.daily_posts (
  id uuid primary key default gen_random_uuid(),
  slug text unique,
  scheduled_for date not null default current_date,
  status text not null default 'draft',
  kicker text default 'TODAY’S DEEDLIGHT',
  title text not null default 'A new light can begin today.',
  theme text,
  summary text,
  body text,
  small_deed text,
  reflection_prompt text,
  featured_offering_id uuid references public.offerings(id) on delete set null,
  image_url text,
  video_title text,
  video_hook text,
  video_script text,
  video_caption text,
  youtube_url text,
  video_status text not null default 'idea',
  published_at timestamptz,
  archived_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.daily_posts add column if not exists slug text;
alter table public.daily_posts add column if not exists scheduled_for date not null default current_date;
alter table public.daily_posts add column if not exists status text not null default 'draft';
alter table public.daily_posts add column if not exists kicker text default 'TODAY’S DEEDLIGHT';
alter table public.daily_posts add column if not exists title text not null default 'A new light can begin today.';
alter table public.daily_posts add column if not exists theme text;
alter table public.daily_posts add column if not exists summary text;
alter table public.daily_posts add column if not exists body text;
alter table public.daily_posts add column if not exists small_deed text;
alter table public.daily_posts add column if not exists reflection_prompt text;
alter table public.daily_posts add column if not exists featured_offering_id uuid references public.offerings(id) on delete set null;
alter table public.daily_posts add column if not exists image_url text;
alter table public.daily_posts add column if not exists video_title text;
alter table public.daily_posts add column if not exists video_hook text;
alter table public.daily_posts add column if not exists video_script text;
alter table public.daily_posts add column if not exists video_caption text;
alter table public.daily_posts add column if not exists youtube_url text;
alter table public.daily_posts add column if not exists video_status text not null default 'idea';
alter table public.daily_posts add column if not exists published_at timestamptz;
alter table public.daily_posts add column if not exists archived_at timestamptz;
alter table public.daily_posts add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.daily_posts add column if not exists created_at timestamptz not null default now();
alter table public.daily_posts add column if not exists updated_at timestamptz not null default now();

-- Add constraints safely only when absent.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'daily_posts_status_check'
  ) then
    alter table public.daily_posts
      add constraint daily_posts_status_check
      check (status in ('draft', 'scheduled', 'published', 'archived'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'daily_posts_video_status_check'
  ) then
    alter table public.daily_posts
      add constraint daily_posts_video_status_check
      check (video_status in ('idea', 'scripted', 'recorded', 'published'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'daily_posts_slug_unique'
  ) then
    alter table public.daily_posts
      add constraint daily_posts_slug_unique unique (slug);
  end if;
end $$;

create index if not exists daily_posts_status_scheduled_idx
  on public.daily_posts (status, scheduled_for desc);

create index if not exists daily_posts_featured_offering_idx
  on public.daily_posts (featured_offering_id);

create table if not exists public.daily_reflections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  daily_post_id uuid not null references public.daily_posts(id) on delete cascade,
  reflection_text text,
  did_today_deed boolean not null default false,
  mood_label text,
  is_private boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint daily_reflections_unique_user_post unique (user_id, daily_post_id)
);

alter table public.daily_reflections add column if not exists reflection_text text;
alter table public.daily_reflections add column if not exists did_today_deed boolean not null default false;
alter table public.daily_reflections add column if not exists mood_label text;
alter table public.daily_reflections add column if not exists is_private boolean not null default true;
alter table public.daily_reflections add column if not exists created_at timestamptz not null default now();
alter table public.daily_reflections add column if not exists updated_at timestamptz not null default now();

create index if not exists daily_reflections_post_idx on public.daily_reflections (daily_post_id);
create index if not exists daily_reflections_user_idx on public.daily_reflections (user_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_daily_posts_updated_at on public.daily_posts;
create trigger set_daily_posts_updated_at
before update on public.daily_posts
for each row execute function public.set_updated_at();

drop trigger if exists set_daily_reflections_updated_at on public.daily_reflections;
create trigger set_daily_reflections_updated_at
before update on public.daily_reflections
for each row execute function public.set_updated_at();

-- Grants
grant usage on schema public to anon, authenticated, service_role;
grant select on public.daily_posts to anon, authenticated;
grant select, insert, update, delete on public.daily_posts to authenticated;
grant select, insert, update, delete on public.daily_reflections to authenticated;
grant all on public.daily_posts to service_role;
grant all on public.daily_reflections to service_role;

-- RLS
alter table public.daily_posts enable row level security;
alter table public.daily_reflections enable row level security;

drop policy if exists "daily_posts_public_read_published" on public.daily_posts;
create policy "daily_posts_public_read_published"
on public.daily_posts
for select
using (status in ('published', 'archived'));

drop policy if exists "daily_posts_admin_all" on public.daily_posts;
create policy "daily_posts_admin_all"
on public.daily_posts
for all
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "daily_reflections_select_own_or_admin" on public.daily_reflections;
create policy "daily_reflections_select_own_or_admin"
on public.daily_reflections
for select
using (user_id = auth.uid() or public.is_admin());

drop policy if exists "daily_reflections_insert_own" on public.daily_reflections;
create policy "daily_reflections_insert_own"
on public.daily_reflections
for insert
with check (user_id = auth.uid());

drop policy if exists "daily_reflections_update_own" on public.daily_reflections;
create policy "daily_reflections_update_own"
on public.daily_reflections
for update
using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

drop policy if exists "daily_reflections_delete_admin" on public.daily_reflections;
create policy "daily_reflections_delete_admin"
on public.daily_reflections
for delete
using (public.is_admin());

-- Seed one editable daily post if the table is empty.
insert into public.daily_posts (
  slug,
  scheduled_for,
  status,
  kicker,
  title,
  theme,
  summary,
  body,
  small_deed,
  reflection_prompt,
  video_title,
  video_hook,
  video_script,
  video_caption,
  video_status,
  published_at
)
select
  'a-new-light-can-begin-today',
  current_date,
  'published',
  'TODAY’S DEEDLIGHT',
  'A new light can begin today.',
  'courage',
  'Beauty is not only found in nature. Sometimes beauty appears when one person refuses to join cruelty.',
  'Goodness does not prevail by accident. Today, choose one small act that protects dignity, reduces loneliness, or gives someone courage.',
  'Say one gentle sentence in defense of someone who is being judged unfairly.',
  'Where can I make one situation kinder today?',
  'A new light can begin today',
  'Goodness does not need a stage; it needs one person to begin.',
  'Today’s Deedlight is simple: notice one place where dignity needs protection, then add one sentence of gentleness.',
  'One small deed can keep light alive. #Deedlight #Goodness #Kindness',
  'idea',
  now()
where not exists (select 1 from public.daily_posts);
