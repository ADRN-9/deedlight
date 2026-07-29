# Sprint 8.1 — Admin Navigation + Production Polish

Sprint 8.1 adds a cleaner admin workspace and a small set of production-polish helpers.

## What this patch adds

- `/admin` becomes a real admin dashboard.
- Admin pages get a shared admin navigation bar through `app/admin/layout.tsx`.
- Daily Desk, Video Studio, Offerings, Reports, public Videos, and Auth Debug are reachable from one place.
- Non-admin users are blocked from the admin layout.
- A friendly site-wide `not-found` page is added.
- Reusable admin UI helpers are added:
  - `AdminCard`
  - `AdminEmptyState`
  - `AdminStatusMessage`
- Optional admin-only floating link can be inserted into the public app shell.

## Files

```text
app/admin/layout.tsx
app/admin/page.tsx
app/admin/not-found.tsx
app/not-found.tsx
components/admin/admin-card.tsx
components/admin/admin-empty-state.tsx
components/admin/admin-status-message.tsx
components/layout/admin-floating-link.tsx
scripts/apply-sprint8-1-layout.mjs
docs/SPRINT_8_1_ADMIN_NAV_POLISH.md
```

## Apply

From `C:\deedlight`, copy the patch files into the project root.

Optional but recommended: add the admin-only floating link to the public app shell:

```powershell
node scripts/apply-sprint8-1-layout.mjs
```

This script edits `app/layout.tsx` and inserts `<AdminFloatingLink />` without changing the rest of the layout.

## Deploy

```powershell
git status
git add app/admin app/not-found.tsx components/admin components/layout/admin-floating-link.tsx scripts/apply-sprint8-1-layout.mjs docs/SPRINT_8_1_ADMIN_NAV_POLISH.md app/layout.tsx
git commit -m "Implement Sprint 8.1 admin navigation polish"
git push
```

## Online acceptance test

After Cloudflare deploys, test from the real domain:

```text
https://deedlight.com/admin
https://deedlight.com/admin/daily
https://deedlight.com/admin/video-studio
https://deedlight.com/admin/offerings
https://deedlight.com/admin/reports
https://deedlight.com/videos
https://deedlight.com/today
```

Expected results:

- `/admin` shows the new admin dashboard.
- Admin nav appears on admin pages.
- Daily Desk and Video Studio are reachable without typing URLs manually.
- `/today` still shows Today’s Deedlight and the video embed.
- `/videos` still shows public videos.
- `/debug/auth` remains admin-only.
- Non-admin users cannot access `/admin`.

No Supabase SQL is required for Sprint 8.1.
