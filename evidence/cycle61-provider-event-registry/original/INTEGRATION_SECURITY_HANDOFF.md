# C61 integration and independent security review handoff

## Why the high-severity defect exists

Three independent *accepted* event stores can each enforce their own primary key while accepting the **same** Resend `svix-id` in different tables (processed, pending/unmatched, identity-conflict). A `SELECT ... WHERE id NOT IN (...)` pre-check cannot prevent concurrent insertion into the other table. An idempotency key for **sending** a message is also not a durable identity constraint for **received** webhook events.

The patch replaces independent acceptance with one `(provider,svix-id)` primary key. All three lifecycle states are exclusive values in the **same row**, and quarantine evidence is subordinate by foreign key. `INSERT ... ON CONFLICT DO NOTHING` uses PostgreSQL unique-index conflict serialization; `SELECT ... FOR UPDATE` serializes retries and quarantining after a duplicate. On an unexpected missing row or database failure the RPC throws instead of accepting the event.

## Historical data and migration ordering

**Unresolved:** The original 025–028 source and both Cycle 47–48 archives are absent. Their concrete table names, grants, existing event IDs, application callers, dispatch binding mechanism and suppression pipeline are unknown. This patch deliberately chooses a fresh private schema and refuses duplicate installation.

Suggested independent preflight after source recovery, all on an **authorized disposable** test DB:

1. Inventory actual 025–028 physical event tables, columns and grants. Record each source table/row's original unique ID, provider, event type, payload digest, current processing state, provider message association and quarantine status. Do **not** export raw recipient data or signing secrets.
2. Build a private staging map with provenance (`source_table`,`provider`,`event_id`,`payload_sha256`,`state`) preserving every original row and its own immutable source key. Count duplicates across distinct sources, **including byte-identical IDs**. Escalate any cross-source duplicate; do not silently choose the winner or `ON CONFLICT DO NOTHING` the history.
3. Match each provider message ID to exactly one immutable dispatch/ledger record; 0 matches remain pending, 2+ matches quarantine. If historical recipient fingerprints conflict or HMAC keys rotated, stop pending independent DB-authoritative identity reconciliation. Do not trust a webhook-supplied recipient address/fingerprint as an ownership grant.
4. Backfill every reviewed unique identity into the registry with its original state and append its quarantine evidence. Maintain a reconciliation inventory proving `expected IDs = imported IDs + explicitly held conflicts` and zero unreviewed rows. Keep source records intact for forensic review.
5. Make **old write paths fail closed** (revoke/replace direct table grants and remove webhook bypasses). Prove every possible webhook acceptance flow calls the single registry. Then have an independently authorized operator set the new private registry-control row to active with a verified reconciliation evidence ID. No generic self-activation or Production auto-push is supplied.
6. Run the PostgreSQL fixture, actual 025–028 integration fixture, CI source/role grants, real SDK verifier, and actual transport/suppression regression suite at the exact reviewed SHA before proposing a merge.

Until those steps are completed, the off-by-default registry cannot be used in a deployed webhook. It is a reviewable security correction, not an accepted integrated release.

## Browser and worker security

- The physical registry and quarantine evidence are in `deedlight_event_private`, an unexposed schema with no grants to `PUBLIC`, `anon`, `authenticated` or `service_role`. The only RPC EXECUTE grants are to server-only `service_role`; no browser credential may reach them. A SQL function being present under `public` is **not** sufficient for browser EXECUTE without an ACL check: the fixture checks effective privileges.
- Database functions are `SECURITY DEFINER` and must be created by a trusted migration owner, with `SET search_path = pg_catalog,pg_temp` and schema-qualified data references. An independently reviewed migration must confirm that both schema and function ownership are trustworthy.
- Server webhook handler must verify raw-body Resend signature and 300-second freshness before calling `reserve`; do not call on a parsed or reserialized JSON body or when signing configuration is absent. Use exact pinned SDK interface from the recovered dependency lock.
- Never return provider event IDs, message IDs, member/user identifiers, recipient fingerprints, addresses, payload hashes or raw database exceptions in public responses/logs. Expose bounded status codes and aggregate counts only.
- A service-role compromise is privileged and can call reservation RPC without a valid provider signature. Protect the key server-side and do not represent the database RPC as independent webhook authentication.

## Deliberate limits of this narrow patch

- `deedlight_bind_provider_event` ties a signed provider *message* ID to the existing private delivery ledger; it is only **message-level binding**, not authoritative verification of a specific historical **recipient address** after an email change. Actual immutable dispatch-recipient snapshots, HMAC rotation rules and canonicalization must be integrated from independently reviewed 025–028 source.
- **No suppression table mutation is included.** Events requiring suppression cannot be marked processed through the new safe-only function. The handler must not report those events as successfully applied merely because reservation returned `NEW_PENDING`.
- A delayed `email.delivered` may be marked processed after DB binding, but it cannot release an existing suppressed recipient. `suppression.removed` similarly must never automatically reactivate DeedLight sending.
- A `READ COMMITTED` unique-index conflict wait and row lock ensure event-ID serialization; they **do not** serialize suppression inserts against the final recipient transport gate. The recipient-lock missing-row race from Cycle 33 still needs its separate PostgreSQL proof.
- The current source's `public.delivery_ledger.provider_result_id` is not guaranteed globally unique. This patch adds a UNIQUE partial index and will **fail atomically** if historical duplicates exist. The binding RPC also retains an explicit 2+ match quarantine as defense in depth. Review the index's locking/DDL implications before a controlled rollout.
- Failed/bounce classification, provider event parsing, transient-vs-permanent decisions, retry/idempotency behavior and real Resend webhook acceptance remain external integration gates.
- Migration 025–028 source reconciliation, active source-writing ownership, reviewed grant/RLS behavior, `supabase db push`, Production migration history and Deployment are all blocked/out of scope.

## Independent Reviewer required gates

1. Inspect actual archive/source hashes and proposed schema/function `SECURITY DEFINER` ACLs; verify **no browser EXECUTE** and no direct private DML grants.
2. Execute Docker PostgreSQL 16 fixtures with two true DB sessions, inspect lock blocking, unique index races, abort/retry and quarantined immutable evidence, rather than accepting SQLite model proof.
3. Confirm legacy 025–028 tables are non-writable acceptance paths after cutover; test duplicate IDs across all previously separate states, including historical collisions and partial migration abort.
4. Prove no bounce/complaint/suppression event is marked processed without an atomic suppression write and authoritative recipient match. Test out-of-order `email.delivered` and `suppression.removed` remain monotone.
5. Confirm provider signature verification before registry calls using **actual pinned SDK**, no synthetic verifier substitution. Recheck C60's BLOCKED SDK comparison.
6. Validate source migration order and historical Production migration reconciliation. No branch integration, approval or Production access should be inferred from this local artifact.
