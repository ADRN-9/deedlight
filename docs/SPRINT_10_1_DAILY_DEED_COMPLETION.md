# Sprint 10.1 — Daily Deed Completion

## Goal

Give signed-in members one calm, persistent daily action: **I did today’s deed**.

## Product contract

- A member can mark a published `daily_lights` row as carried forward.
- One member can have at most one completion for the same Daily Light.
- Undo removes that member-owned completion.
- The member's completion history is private and appears only in Journey.
- Public visitors may see only an anonymous aggregate completion count.
- No public participant list, ranking, streak comparison, or profile exposure is introduced.
- Suspended members retain access to private Daily/Journey habit features.
- Fallback/synthetic Today content cannot be completed.
- Daily reflections remain private and separate from deed completion.

## Private Daily reflection authorization

- The `daily_reflections` base table is member-private: authenticated SELECT, INSERT, and UPDATE policies require `user_id = auth.uid()`.
- Database administrators use narrow moderation projections and are not granted a reflection-content exception. The member moderation context must not query `daily_reflections`.
- Anonymous browser roles have no direct table privileges. Authenticated browser roles have no DELETE privilege or DELETE policy.
- The `service_role` grant is retained only for trusted server-side operations; browser clients and the administrator member-review interface use the authenticated session client, not a service-role key.
- These boundaries are exercised by the privacy authorization PostgreSQL behavior suite, including cross-member and administrator negative assertions.

## Compatibility

The original `daily_deed_completions` table belongs to the legacy
`daily_posts` system. Sprint 10.1 adds `daily_light_id`, keeps legacy columns
non-destructively, and enforces unique `(user_id, daily_light_id)` completion
for the current Daily Light product.

Sprint 10.1 also repairs the existing Daily reflection compatibility gap:
current `/today` writes `daily_light_id`, while production still required
legacy `daily_post_id`.

## Public aggregate

`daily_deed_completion_counts` exposes only:

- `daily_light_id`
- `completion_count`

It contains no member identity, timestamps, reflections, or private fields.

## Sprint 10.2 boundary

Saved Lights, timezone-aware rhythms/streaks, and reminder behavior remain
outside Sprint 10.1.
