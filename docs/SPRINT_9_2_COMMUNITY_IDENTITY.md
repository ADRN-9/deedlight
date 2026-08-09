# Sprint 9.2 — Community Identity Consistency

Sprint 9.1 shipped most of the original Community Identity scope:
public profiles, identified Offering profile links, privacy controls, and
gentle contribution totals.

Sprint 9.2 closes the remaining consistency gaps.

## Changes

- Repairs `offerings_rising` so it includes `author_username`.
- Keeps Rising Goodness freshness-weighted ranking active instead of relying
  silently on the fallback query.
- Logs Rising-view query failures before falling back.
- Removes account UUIDs from all rows in public Offering projections.
- Keeps anonymous Offering identity fully hidden.
- Keeps usernames hidden when a profile is private or suspended.
- Stops deriving new-user display names from email local-parts.
- Reloads the PostgREST schema cache after view changes.
- Appends canonical Sprint 9.1 and 9.2 migration parity to
  `supabase/run_in_sql_editor_all.sql`.

## Privacy contract

Public profile and Offering APIs must not expose:

- auth/user UUIDs
- email addresses
- role or suspension internals
- private Journey data
- private daily reflections
- anonymous Offering identity

Public profiles remain opt-in. Only approved, non-anonymous Offerings are
associated with a public username.

## Rising fallback

`getRisingOfferings()` retains a graceful fallback to `offerings_public`, but
schema/query errors are logged server-side so a broken Rising view is no
longer silent.
