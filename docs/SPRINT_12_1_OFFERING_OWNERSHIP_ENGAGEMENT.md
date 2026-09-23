# Sprint 12.1 — Offering Ownership & Engagement

Sprint 12.1 upgrades Deedlight's Offering experience without turning goodness into a popularity contest.

## Member ownership

- Members receive a private `•••` management menu for their own Offerings.
- Eligible Offerings can be edited and resubmitted for moderation.
- Editing an already-published Offering removes the current version from public discovery while the edited version is reviewed.
- Member removal is reversible soft removal (`owner_removed_at` + hidden state), not unrestricted browser DELETE. Direct member INSERT/UPDATE policies keep `owner_removed_at` null so only the guarded owner RPCs can change that marker.
- A member-removed Offering can be restored to the moderation queue.
- Moderator-hidden and rejected content cannot be bypassed through member edit/restore controls.
- Suspended members cannot edit or restore community content. They may still remove their own eligible Offering for privacy/safety.

## Private saves

The existing `public.saved_lights` table is reused. Authenticated members may privately save approved Offerings in addition to published Daily Lights. Saved Offering rows are member-owned under RLS, have no public count, and do not contribute to rankings, profiles, or community totals.

## Reactions

Deedlight keeps its existing language instead of adding a generic Like button:

- Bless
- Inspired
- Did too

Sprint 12.1 fixes selected-state hydration so the UI recognizes the actual database values `bless`, `inspired_me`, and `i_did_this_too` after reload. Reaction mutations keep optimistic feedback and duplicate-submit protection.

## Professional interaction polish

Offering cards and detail pages gain private Save and Share/Copy Link controls. `/journey` gains a structured My Offerings workspace with Published, In review, Needs attention, and Removed filters plus moderation notes and owner actions. `/offerings` category chips become real navigation rather than decorative labels.

## Privacy and moderation boundaries

- No private Daily reflections, Daily completion history, reminder preferences, or newsletter preferences are read by Sprint 12.1 features.
- Anonymous Offering author identity remains hidden by the established public Offering projection.
- The new UI determines ownership privately on the server and passes only an ownership boolean to public cards.
- No public save counts are introduced.
- No new public member ranking or referral system is introduced.
- Existing reaction rows and private saves belonging to other members are not deleted when an owner removes an Offering.

## Migration

Apply:

`supabase/migrations/202608130017_sprint12_1_offering_ownership_engagement.sql`

Then complete the Sprint 12.1 database contract and authenticated runtime acceptance before staging or committing.

## Owner-removal moderation guard

Migration `202608140018_sprint12_1_owner_removal_guard_hotfix.sql`
records the narrow Production repair applied after Sprint 12.1 migration
017. Rejected Offerings cannot use the member Remove -> Restore path to
return to moderation, and an Offering with `owner_removed_at` must remain
`hidden`. Removal remains a soft, reversible owner privacy action rather
than browser DELETE.
