# Sprint 6 — Daily Deedlight Content System

## What this sprint adds

- Admin daily content desk at `/admin/daily`
- New daily post editor at `/admin/daily/new`
- Edit/schedule/publish/archive page at `/admin/daily/[id]`
- Public `/today` page powered by database content
- Past daily lights archive at `/today/archive`
- Featured Offering selector for daily inspiration
- Private daily reflection/check-in form
- Short-video planning fields for YouTube/Shorts content

## Apply files

Copy the files in this package into the project, then run:

```bash
git add app/admin/daily app/today components/daily lib/data/daily.ts lib/types-daily.ts supabase/migrations/202607260007_sprint6_daily_deedlight.sql docs/SPRINT_6_DAILY_DEEDLIGHT.md
git commit -m "Implement Sprint 6 daily Deedlight content system"
git push
```

Then apply the migration:

```bash
npx supabase db push
```

Or paste `supabase/migrations/202607260007_sprint6_daily_deedlight.sql` into Supabase SQL Editor and run it.

## Test checklist

1. Open `/admin/daily` as admin.
2. Create a new Daily Deedlight.
3. Save it as draft.
4. Mark it as scheduled.
5. Save edits and publish.
6. Open `/today` and confirm the published daily content appears.
7. Choose a featured Offering and confirm it appears on `/today`.
8. Sign in as a member and submit a private reflection/check-in.
9. Archive a daily post and confirm it appears in `/today/archive`.
10. Add short-video title, hook, script, caption, and YouTube URL.

## Notes

- Only admin users can create, edit, schedule, publish, or archive daily posts.
- Reflections are private to the user and admins.
- Public users can read only `published` and `archived` daily posts.
- The current public `/today` page now reads from `public.daily_posts` and falls back to safe default content if the table is unavailable.
