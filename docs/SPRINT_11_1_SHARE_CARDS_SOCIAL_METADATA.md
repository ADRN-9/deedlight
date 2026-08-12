# Sprint 11.1 — Share Cards & Social Metadata

## Goal

Give Deedlight's public content trustworthy, branded social previews without
weakening the privacy boundaries established in Sprints 9 and 10.

## Delivered

- Dynamic 1200×630 share-card image endpoints for:
  - Deedlight default
  - Today's Daily Light
  - approved public Offerings
  - explicitly public member profiles
- Canonical metadata for Today, Offering detail, and public member profiles.
- Open Graph and Twitter metadata now point to content-specific share cards.
- Share-card content is generated only from public projections / public content.
- Anonymous Offering cards intentionally contain no author identity.
- Public member cards are generated only through `profiles_public`.
- Private Daily reflections, Saved Lights, deed-completion rows, and reminder
  preferences are not queried by any Sprint 11.1 share surface.

## Deliberate boundaries

Sprint 11.1 does not introduce:
- newsletter delivery
- referral tracking
- new database tables
- ranking changes
- private-data share cards

Those belong to later Sprint 11 gates.

## Acceptance

1. `npm run build` passes.
2. `/api/share/default`, `/api/share/today`,
   `/api/share/offering/<approved-id>`, and
   `/api/share/profile/<public-username>` return `image/png`.
3. `/today`, an Offering detail page, and a public profile emit canonical,
   Open Graph, and Twitter metadata pointing at the corresponding card.
4. An anonymous Offering share card contains no member name/username.
5. A private or suspended profile cannot produce public profile metadata because
   the application reads only `profiles_public`.
