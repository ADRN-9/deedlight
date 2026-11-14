# C65 independent security review — required gates

## Core finding and proposed correction

Original C61 registry enforces uniqueness for only callers of `deedlight_reserve_provider_event`. The historical `record_resend_webhook_event_identity_bound(...)` acceptance RPC can bypass it by writing separate legacy lifecycle records. Independent keys on processed/pending/quarantine stores do **not** enforce a provider/event-ID identity across stores or concurrent requests.

The C65 patch prevents known legacy writes at the PostgreSQL boundary, not merely with a TypeScript duplicate lookup: it drops all signatures of the known legacy RPC and installs always-enabled write-denying triggers on discovered acceptance tables. On a missing registry, active registry, dependent functions, missing target tables, or additional named event-ingestion functions, migration aborts atomically. It **does not** activate C61 or rewrite event history.

## Required integration against actual 025–028 source

1. Recover original migrations 025–028 and the two original Cycle 47–48 archives. Independently verify their expected source hashes; inventory every app route, service-role RPC, SECURITY DEFINER function, trigger and physical table that accepts a provider event, including unrecognized names and privilege inheritance. This task could not complete that catalog inventory.
2. Ensure **every** legacy event-acceptance table and intermediary SECURITY DEFINER path is physically vetoed or retired. Check schema names/signatures against actual historical source. If matching changes are required, create a *new version* of this patch; do not silently edit the published evidence.
3. Classify existing duplicate IDs across processed/pending/conflict histories. Retain each source row and provenance; quarantine collisions and mismatched recipient association. Require `accepted IDs = imported unique IDs + independently held conflicts` before cutover.
4. Review C61 private registry control and source of recipient authority. No application-supplied fingerprint may override an immutable dispatch-to-recipient record. Changing email, HMAC key rotation and canonicalization remain separate unresolved security gates.
5. For permanent bounce, complaint and provider suppression, reserve + bind + recipient suppression must happen in one reviewed transaction or remain pending/quarantined. Do **not** mark them successful merely to progress registry state. Enforce the same stable-recipient lock at final transport authorization and suppression insertion; missing-row race remains unresolved without real PostgreSQL tests.
6. Use `pg_catalog` to verify public/anon/authenticated lack EXECUTE or direct DML and that roles cannot bypass vetoes through inherited grants or SECURITY DEFINER routines. Review migration owner, trigger ownership, `SET search_path`, RLS and table exposure.
7. Execute C65 SQL and negative fixtures on *disposable PostgreSQL 16*, then the authentic 021–030 migration chain and live webhook source using a synthetic pinned Resend SDK. Exercise cross-RPC concurrent delivery, replay, rebindings, historical collisions, interrupted transactions, consent revoked, suppression, stale claims, Weekly capacity and disabled delivery.
8. Treat rollback as a **stop-only** operation: keep delivery disabled, do not restore the legacy accepting function or drop vetoes until an independently reviewed central ingestion path is installed. `ROLLBACK` of the migration transaction on failed preflight preserves the old state, so any pre-existing unsafe acceptance remains a deployment blocker.

## Meaning of results

- `CLOSED—VERIFIED`: original C61 archive, local post-029 patch file, local SQLite/concurrency and static tests, and archive checksum.
- `NOT TESTED`: PostgreSQL 16, actual SQL grants, true concurrent service-role RPCs, real 025–028 migration ordering and Workers/Resend integration.
- `OPEN`: full legacy path inventory and suppression/send concurrency, provider event classification, recipient key rotation and canonicalization.
- `BLOCKED`: shared application-source ownership reconciliation, historical Production migration reconciliation, merge/deploy/Production readiness.

The **HIGH-severity legacy bypass is not closed** by this isolated patch. It is a concrete proposed hard-stop requiring a further PostgreSQL and source-level acceptance review.
