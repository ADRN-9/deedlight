# Sprint 8 Today video hotfix

This hotfix updates `app/today/page.tsx` so the Today page no longer depends on an embedded Supabase relationship query for the featured Offering.

The prior query could return `null` data if Supabase relationship/schema cache was stale, causing `/today` to show fallback content even when the Daily Light row existed and `/videos` displayed the video correctly.

Apply, commit, push, then test `https://deedlight.com/today`.
