# Sprint 10.3A — Gentle Daily Reminder Preferences

## Goal

Add a private, opt-in reminder preference foundation without pretending
that delivery transport already exists.

## What this increment adds

- `daily_reminder_preferences`, one private row per member.
- Reminders default to off.
- Preferred local time plus an explicit IANA timezone.
- `/settings/reminders`.
- A Journey reminder-status card.
- RLS and browser grants limited to the authenticated owner.
- Suspended members may turn an existing preference off, but may not
  enable reminders.
- No email address, public profile field, reflection text, saved-light
  content, or Offering content is stored in the reminder table.

## What this increment deliberately does not add

- Cloudflare Cron Triggers.
- Email delivery.
- Web Push / service-worker subscriptions.
- SMS.
- "You are falling behind" messaging.
- Public streaks or reminder status.

The repository audit found no notification, subscription, newsletter,
or cron implementation. Transport must therefore be designed as a
separate step instead of being inferred.

## Acceptance

1. Signed-out `/settings/reminders` redirects to login.
2. Signed-in settings load with reminders off for a member with no row.
3. Saving writes exactly one own-user preference row.
4. Another browser role cannot read the private table.
5. A suspended member cannot enable reminders, but can disable them.
6. Journey shows only the signed-in member's reminder summary.
7. Production build passes.
