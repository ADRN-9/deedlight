# Sprint 12.2 — Gentle Delivery Foundation

## Discovery baseline

Sprint 12.2 starts from `sprint-12-1-complete` / `1efa8d095cc350a75df22e30892cd1305dda5fa5`.

The repository already has two explicit opt-in foundations, but no outbound transport:

- Daily reminder preferences are private, off by default, and store a local reminder time plus IANA timezone.
- Weekly Goodness newsletter consent is private, off by default, and mutated through `set_newsletter_preference(boolean)`.
- Both earlier sprint documents explicitly state that actual delivery is inactive.
- `wrangler.jsonc` has no Cron Trigger configuration.
- `package.json` has no email, SMS, push, or notification provider dependency.
- The current API surface contains health/share routes only; there is no delivery worker route.

## Security observation

Reminder preference writes are still direct authenticated table `INSERT` / `UPDATE` operations. The server action validates IANA timezones, but the database policy itself only protects ownership/suspension and does not independently validate that the timezone exists in PostgreSQL's timezone catalog.

A future scheduler must not trust a queued or claimed row as continuing authority. Consent can be revoked and a member can become suspended after a job is queued or claimed. Claiming therefore grants no delivery authority; current authorization must be checked immediately before any external transport.

## Sprint 12.2 scope

This increment will build transport-neutral, fail-closed delivery readiness without sending anything externally:

1. Move daily reminder preference mutation behind a validating security-definer RPC and remove direct authenticated browser `INSERT` / `UPDATE` grants.
2. Add a private service-role-only delivery ledger containing only `user_id`, delivery kind/key, state, scheduling timestamps, bounded provider result identifiers, and bounded error codes.
3. Add deterministic enqueue functions for due daily reminders and explicitly identified Weekly Goodness issues.
4. Exclude suspended members and, for newsletter jobs, users without a confirmed account email.
5. Deduplicate queue entries by `(kind, user_id, delivery_key)`.
6. Treat a claim token only as concurrency control, not authorization. Re-check current consent/suspension immediately before any future transport send; revoked authorization cancels the job instead of silently proceeding.
7. Keep recipient email addresses and all member content out of the delivery ledger.
8. Add explicit CI tests for browser privilege denial, timezone validation, opt-in filtering, suspension filtering, deduplication, stale-authorization cancellation, and terminal-state transitions.
9. Mirror migration 019 into `supabase/run_in_sql_editor_all.sql` so the repository's manual fresh-environment SQL path remains aligned with the incremental migration history.

## Explicit exclusions

Sprint 12.2 will **not** add or imply active delivery. It will not add:

- Cloudflare Cron Triggers.
- Resend, SendGrid, Postmark, Mailgun, Twilio, web push, or any other transport provider.
- Provider credentials or API tokens.
- Email addresses in the delivery ledger.
- Reflection text, Saved Lights, Offering bodies, or private Journey content in delivery jobs.
- Public delivery counts, rankings, or activity indicators.

Transport activation is a separate production step and requires an explicitly selected provider, server-side credentials, and a production-specific rollout/rollback plan.

## Acceptance plan

CI must prove all of the following before the migration is considered ready:

1. `anon` and `authenticated` cannot read or mutate the delivery ledger.
2. `anon` and `authenticated` cannot execute queue/claim/terminal-state functions.
3. Authenticated members can change only their own reminder preference through the validating RPC.
4. Unsupported timezone data fails closed.
5. Suspended members cannot enable reminders and are never enqueued.
6. Disabled reminder/newsletter preferences are never enqueued.
7. Unconfirmed newsletter accounts are never enqueued.
8. Duplicate enqueue attempts create no duplicate job.
9. Revoking consent or suspending a member after claim causes the pre-transport authorization gate to cancel the job.
10. No external transport is invoked by tests or application code.
11. TypeScript, Next.js build, dependency audit, and Cloudflare packaging remain green.

## Production rollout

Migration 019 was applied to the Deedlight production database on 23 September 2026 through a temporary guarded workflow using the scoped landing-audit credential. The workflow first proved the expected Sprint 12.1 production baseline, then applied the exact migration file and verified the resulting privilege model.

Production verification confirmed that `delivery_ledger` exists with RLS enabled and zero rows; `anon` and `authenticated` have no ledger DML privileges; `service_role` has the required ledger and delivery-RPC privileges; direct authenticated reminder `INSERT` / `UPDATE` privileges are removed; the authenticated reminder RPC remains available; delivery enqueue/claim/authorization RPCs remain unavailable to authenticated clients; and the reminder and pre-transport authorization RPCs are security-definer functions. Invalid-timezone behavior was also exercised inside a rollback-only production transaction.

This database rollout does **not** activate delivery. No provider, provider credential, Cloudflare Cron Trigger, scheduler, email/SMS/push transport, or outbound delivery worker is introduced by Sprint 12.2. Application landing and production smoke verification remain separate rollout gates before the sprint completion tag.
