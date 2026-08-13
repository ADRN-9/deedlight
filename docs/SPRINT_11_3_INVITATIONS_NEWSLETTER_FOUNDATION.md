# Sprint 11.3 — Invitations & Newsletter Foundation

## Scope

Sprint 11.3 creates a private, noncompetitive growth foundation without
pretending that Deedlight has outbound invitation or newsletter delivery.

### Invitations

- Signed-in, active members can create one reusable private invitation link.
- Invitation codes are 144-bit random hexadecimal capabilities.
- Public validation returns only `true` or `false`; it exposes no inviter
  identity, profile data, acceptance count, or invitation ID.
- Suspended inviters cannot create a new link and their existing links no
  longer validate or attribute signups.
- Members may revoke their own link even while suspended.
- A confirmed new account can be attributed to at most one invitation.
- Accepted invitee user IDs are stored only in a browser-inaccessible private
  ledger.
- Invitation counts are private to the inviter and are never a public ranking.
- Deedlight does not send invitation email in this sprint.

### Newsletter consent

- The Weekly Goodness newsletter preference is off by default.
- Signup includes an explicit unchecked checkbox.
- Signed-in members can enable or revoke consent later at
  `/settings/newsletter`.
- Suspended members can revoke an enabled preference but cannot newly opt in.
- The preference table stores the auth user ID and consent lifecycle only; it
  intentionally does not duplicate the account email.
- Authenticated browser users have SELECT-only access to their own preference.
  Mutations go through `set_newsletter_preference(boolean)` so consent
  timestamps cannot be fabricated through direct table writes.
- Delivery is not active. No email provider, sending job, campaign worker, or
  delivery claim is added by Sprint 11.3.

## Database objects

- `invitation_links`
- `invitation_acceptances`
- `newsletter_preferences`
- `validate_invitation_code(text)`
- `create_invitation_link()`
- `revoke_invitation_link(uuid)`
- `set_newsletter_preference(boolean)`
- `record_invitation_acceptance(uuid, text)` (internal)
- `handle_growth_signup()` (auth trigger)

## Privacy exclusions

Invitation and newsletter features do not query or expose:

- `daily_reflections`
- `daily_deed_completions`
- `saved_lights`
- `daily_reminder_preferences`

## Acceptance

1. Migration privilege assertions pass.
2. Anonymous callers can validate only an invitation code boolean.
3. Anonymous callers cannot create/revoke links or mutate newsletter consent.
4. Invitation and acceptance tables are not publicly readable.
5. Newsletter preferences are private and off by default.
6. Active member create → validate → revoke flow passes.
7. Newsletter enable → disable/restored-state flow passes.
8. Suspended member protections pass.
9. `/signup?invite=...`, `/invite`, `/settings/newsletter`, and privacy
   disclosures render correctly.
10. Existing private surfaces remain protected.
