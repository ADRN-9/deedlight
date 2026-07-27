# Deedlight Sprint 7 Build/Run Patch

This patch updates Sprint 7 with build-safe source files for:

- PWA manifest and installable app assets
- Mobile bottom navigation
- Today’s Deedlight sharing
- Offering detail sharing metadata and share button
- Daily reflection/check-in submission
- Journey reflection history/progress
- Admin-only debug page
- Robust Supabase migration for `daily_lights` and `daily_reflections`

## Apply

From your project root:

```powershell
Copy-Item -Recurse -Force .\deedlight-sprint7-build-run-patch\* .\
```

Or copy the patch contents over the matching project folders manually.

## Run migration

Open Supabase SQL editor and run:

```text
supabase/migrations/202607260007_sprint7_pwa_daily_engagement.sql
```

## Build locally

```powershell
npm run build
```

Then test:

```powershell
npm run dev
```

## Verify

- `/manifest.webmanifest` loads JSON
- `/today` shows a daily light
- signed-in users can complete one reflection and see confirmation
- `/journey` shows reflection history and progress
- `/offerings/[id]` has a working share button
- `/debug/auth` is 404 for normal users and visible only for admin

## Commit and deploy

```powershell
git add .
git commit -m "Fix Sprint 7 PWA and daily reflection build"
git push
```

Security: do not expose `SUPABASE_SERVICE_ROLE_KEY` or admin diagnostics in client components.
