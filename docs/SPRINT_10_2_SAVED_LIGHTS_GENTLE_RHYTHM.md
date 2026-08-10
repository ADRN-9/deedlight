# Sprint 10.2 — Saved Lights + Gentle Rhythm

## Purpose

Sprint 10.2 adds private Daily Light saving and a non-competitive view of recent daily practice. It intentionally avoids streak pressure, public habit metrics, and any exposure of private reflections.

## Saved Lights

- Reuses the existing `public.saved_lights` table instead of creating a second save system.
- Adds `daily_light_id` for the current `public.daily_lights` model.
- Preserves the legacy `offering_id` and `daily_post_id` columns for compatibility.
- The Sprint 10.2 UI saves current published Daily Lights only.
- Each saved row belongs to exactly one source.
- A member can save the same Daily Light only once.
- Saved rows are private and never projected to public profiles or public aggregate views.

## Security contract

Browser roles receive no direct `saved_lights` access as `anon`. `authenticated` receives only `SELECT`, `INSERT`, and `DELETE`. There is no browser `UPDATE`, `TRUNCATE`, `TRIGGER`, or `REFERENCES` privilege.

RLS allows members to select and delete only their own rows. New saves must belong to the authenticated user and point to a published current Daily Light. Saving is modeled as immutable: insert to save, delete to unsave.

## Gentle rhythm

The Journey derives a private rhythm from the member's existing `daily_deed_completions` rows. It shows:

- Lights carried in the last seven calendar days, using the Daily Light's canonical `scheduled_date`.
- Total Lights carried.
- The most recently carried Daily Light date.

There is no stored streak, reset state, ranking, or public rhythm field. Missing a day has no penalty.

## Privacy boundary

This sprint does not query, expose, aggregate, or publish private Daily reflection text. Saved Lights and rhythm data stay inside authenticated Journey experiences.
