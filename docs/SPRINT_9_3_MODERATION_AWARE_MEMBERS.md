# Sprint 9.3 — Moderation-aware Members

Sprint 9.3 adds member moderation context without turning Deedlight into a
ranking system or exposing private reflection data.

## Admin surfaces

Database-backed admins receive:

- `/admin/members`
- `/admin/members/[userId]`
- member state, role, verification and public-profile state
- gentle Offering counts
- report context attached to that member's Offerings
- auditable suspension/restore history
- links to existing Offering moderation pages

The member workspace intentionally does **not** query:

- `daily_reflections`
- reflection text from `reflections`
- email addresses
- auth/profile internal row IDs

## Suspension model

Suspension is an account-level community safety state.

While suspended, a member:

- has public profile attribution suppressed by the existing public projections
- cannot create or resubmit Offerings
- cannot add reactions
- cannot submit reports
- cannot create or update community Offering reflections

Suspension does not:

- delete existing Offerings
- delete reactions or reports
- expose private data
- remove access to private Daily reflections

## Mutation safety

`set_member_suspension(...)` is a SECURITY DEFINER RPC that:

- requires `public.is_admin()`
- therefore requires the database profile role `admin`
- refuses self-suspension/self-restore
- refuses moderation of admin accounts
- requires a reason between 8 and 500 characters
- records every state change in `member_moderation_events`

The `ADMIN_EMAILS` application fallback continues to grant existing admin UI
access, but it does not grant member-suspension mutations.

## RLS hardening

Sprint 9.3 closes the remaining suspension gaps in:

- both member Offering UPDATE policies
- community Offering-reflection INSERT
- community Offering-reflection UPDATE

Existing Offering INSERT, reaction INSERT, and report INSERT policies were
already suspension-aware and remain unchanged.

Private Daily-reflection policies are intentionally unchanged.
