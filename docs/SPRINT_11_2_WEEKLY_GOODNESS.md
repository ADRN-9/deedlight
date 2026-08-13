# Sprint 11.2 — Weekly Goodness

## Goal

Create a public seven-day goodness discovery surface without turning kindness
into a leaderboard.

## Public behavior

- `/weekly` shows approved public Offerings that were published or received
  public reaction activity in the last seven days.
- Ordering is a discovery aid only. The UI deliberately has no numbered ranks,
  podiums, member leaderboard, or winner language.
- Weekly counts are aggregates of Bless, Inspired, and Did too reactions.
- An optional Featured Light is chosen editorially by a database-role admin.
- `/api/share/weekly` provides a 1200×630 social preview.

## Privacy and safety

- Weekly APIs return no reaction user IDs.
- `offerings_public` remains the identity source, so anonymous Offerings expose
  no account UUID/name/username and suspended-member attribution remains
  suppressed.
- Weekly APIs do not query reflection tables or use reflection-derived
  `bless_score`.
- Daily deed completions, Saved Lights, and reminder preferences are excluded.
- The private `weekly_goodness_features` table has no browser-role table access.
- Public feature selection mutation requires `public.is_admin()`, so
  `ADMIN_EMAILS` fallback access alone cannot curate the public feature.

## Database objects

- `weekly_goodness_features`
- `get_weekly_goodness(integer)`
- `get_current_weekly_goodness_feature()`
- `set_weekly_goodness_feature(uuid)`

## Acceptance

1. Migration privilege assertions pass.
2. `/weekly` returns 200 signed out.
3. `/api/share/weekly` returns a valid PNG.
4. Weekly UI contains no numbered rank badges.
5. Anonymous identity remains absent from weekly responses.
6. Non-admin/browser roles cannot mutate the Featured Light.
7. A database-role admin can set and clear the Featured Light.
8. Existing Today, Offerings, Rising, Journey, reminders, and moderation
   behavior remain intact.
