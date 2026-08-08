# Sprint 9.1 — Profiles + Community Trust

## Scope

- Private profile settings at `/settings/profile`.
- Opt-in public profiles at `/people/[username]`.
- Case-normalized unique usernames.
- Optional gentle contribution totals.
- Default anonymity preference for new Offerings.
- Public profile links from non-anonymous Offerings.
- Anonymous Offering author UUIDs removed from the public view.
- Direct anonymous access to the `profiles` table removed.
- Browser-role `TRUNCATE`, trigger, and reference privileges removed from
  `profiles`, `offerings`, and their public views.

## Privacy contract

- Profiles are private by default.
- Suspended profiles never appear publicly.
- Only approved, non-anonymous Offerings appear on public profiles.
- Daily reflections are never queried or rendered by public profile routes.
- `role`, `is_suspended`, internal profile IDs, and member user IDs are not
  exposed through `profiles_public`.
- Anonymous Offerings expose neither an author name, username, nor user UUID.

## Deployment order

1. Apply `202608060009_sprint9_profiles_privacy.sql` in Supabase SQL Editor.
2. Verify the migration using the supplied read-only queries.
3. Commit and push the source patch.
4. Test profile settings while signed in.
5. Test public/private profile behavior while signed out.
