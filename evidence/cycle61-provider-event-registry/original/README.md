# DeedLight C61 — provider event-ID uniqueness remediation (isolated)

**Assignment:** `DL-C61-EVENT-DEDUP-REMEDIATION-D01`  
**GP task:** `0871d1bf81e545bcb38224b3a7b58cd9`  
**Project:** DeedLight ONLY (`ADRN-9/deedlight`)  
**Disposition:** **PARTIAL — isolated implementation produced; PostgreSQL NOT TESTED; shared integration BLOCKED.**  
**Merge / Production:** **NO-GO.** Nothing was written to GitHub or deployed.

## Source identities and archive recovery

Read-only GitHub verification, November 14, 2026:

- `main`: `ce82b3fdf1a73510de70e3729a487d4ae00e66e3`
- Cycle 22 integrated feasibility tree: `4a403eee5fe4fc45e3decde988dc5e488cdf3b81`
- PR #10: `c983e2ed8b93c935139c935343261570ecea6978`, draft and unmerged.
- PR #11: `aed588d771dc04fda5e5c18d8611239ac926a513`, draft and unmerged.
- The checked feasibility tree has **no** source migrations numbered 025–028 or Resend webhook handler. The original Cycle 47–48 archives are NOT in the accessible conversation inventory or `/mnt/data`:
  - consolidated remediation expected (UNVERIFIED): `fe0bc550997887c31ae43851b05883cc72181eb2af7419fdb05a59aeb3e23fdf`;
  - database corrections expected (UNVERIFIED): `f79eab77a271e82f281f236b493aeeff972424ce7d0b50a4e0e7d2f200b8271a`.
- Historical Cycle 34 reference ZIP recovered, SHA-256 `3ac116f825db3442af345a2def5ccfae87059c59cd737a70d0b50a4f79bbc130`.
- Cycle 60 SDK comparison ZIP recovered, SHA-256 `79b12655eaab0403389fb598eda1944be2b9fd4f092fd2e8e4f878db9eea32a0`. Its accurate conclusion is **official SDK compatibility BLOCKED**: local 36/36 Node reference checks passed, but the real SDK and missing Cycle 47–48 implementation were not run together.

No claim is made that the unavailable C47–48 archives or their reported checksums were recovered.

## What is implemented

The isolated, reviewable SQL file is `patch/PROPOSED_POST_028_provider_event_registry.sql`. It is **not** an applied migration and its filename is deliberately not directly accepted as a Supabase CLI migration timestamp. The accompanying `patch/ADD_PROVIDER_EVENT_REGISTRY.patch` is a proposed addition to the repository; do not apply without coordinator clearance and verified migration ordering.

The SQL creates:

1. A **single private physical event registry** with a PostgreSQL primary key `(provider,event_id)` and an exclusive `pending | processed | identity_conflict` state. Three views represent these states; they are not independent acceptance tables.
2. Private, append-preserving conflict evidence with a foreign key to the authoritative registry. A conflicting replay quarantines the original identity and retains its original payload digest; no silently replaced or separately accepted ID.
   The same migration proposes a UNIQUE partial index on `public.delivery_ledger(provider_result_id) WHERE provider_result_id IS NOT NULL` to prevent one Resend message ID from mapping to two logical deliveries. If historical message IDs collide, **migration aborts** pending explicit reconciliation.
3. `public.deedlight_reserve_provider_event(...)`: service-role-only `SECURITY DEFINER` RPC using unique-index conflict serialization and row locking. Same event returns a duplicate disposition, conflicting payload/metadata returns quarantine. A PostgreSQL error is never classified as a replay.
4. `public.deedlight_bind_provider_event(...)`: service-role-only DB-authoritative lookup using the persisted `public.delivery_ledger.provider_result_id`. No caller-supplied email, user ID or fingerprint is accepted as authority. Zero matches remain pending; multiple matches quarantine. This only **binds pending**, not suppresses a recipient.
5. `public.deedlight_process_nonsuppressing_event(...)`: service-role-only, bound-only promotion for **`email.sent` and `email.delivered`**. Complaint, bounce, failed, suppression and unsupported event types cannot be marked processed through this path. Delayed success does not unsuppress.
6. Explicit browser-role REVOKEs, private schema/data, bounded fields and a strict `pg_catalog,pg_temp` function search path.
7. An **off-by-default** control row. Admission remains blocked until all historical 025–028 sources, duplicates, pending receipts and quarantine records are reconciled by a separately authorized operator. No activation RPC is shipped.

**Webhook entry point requirement:** Always verify the untouched raw body and `svix-id`, `svix-timestamp`, `svix-signature` against the current pinned Resend SDK and nonproduction webhook signing secret **before** invoking these database RPCs. Event ID is the authenticated `svix-id`, **not** `data.id` (the provider message ID). `payload_sha256` is an event-equality digest only. It is **not recipient authorization**. Missing or invalid signature/configuration must never reach the registry.

## Exact local execution

From this extracted package directory:

```sh
python3 -W error::ResourceWarning -m unittest discover -s tests -v
bash -n tests/run_disposable_postgres.sh
sha256sum -c SHA256SUMS.txt
```

Local tests use a **real SQLite UNIQUE primary key and transaction concurrency**, but are still only a **surrogate**, not execution of the PostgreSQL functions or the DeedLight webhook application. Tests use synthetic email-event identifiers and no recipient addresses, tokens or real provider requests.

An explicitly **NOT RUN** PostgreSQL 16 fixture is provided for an independently approved, disposable Docker environment:

```sh
DEEDLIGHT_C61_DISPOSABLE_ACK=I_CONFIRM_SYNTHETIC_DATA_ONLY \
  bash tests/run_disposable_postgres.sh
```

This script creates and destroys its **own** network-disconnected `postgres:16` Docker container. It does not connect to a host Postgres endpoint, SSH tunnel, Supabase, or provider; it adds synthetic roles and a stub transport function solely inside that container. **It must not be run as a Production smoke test.** Docker and PostgreSQL are absent in this execution environment; no PostgreSQL claims follow from the script's existence.

## Integration stop conditions

- Recover authentic 025–028 source, schema and history, and reconcile **every** legacy processed, pending and identity-conflict event ID. Detect duplicates across tables; fail if duplicate ownership is ambiguous. Do not rely on absence of names in the historical candidate tree as proof the missing migrations do not exist elsewhere.
- Backfill identities to this one registry **transactionally, without discarding or rewriting quarantine evidence**. Decommission or revoke direct acceptance writes to independent old tables; provide read-only compatibility views where safe. Activate control only after reviewable reconciliation evidence and matching source/DB checks.
- Insert the unique reservation in the authenticated webhook handler **before** writing any lifecycle table. Treat `IDENTITY_CONFLICT` and `QUARANTINED` as fail-closed; the response must not implicitly acknowledge suppression as complete.
- Install a separate reviewed, atomic suppression processor for permanent bounce/complaint and provider suppression events. Preserve the existing database-authoritative recipient lock and final transport gate. **This patch deliberately does not implement suppression application.** An unprocessed bounce remains a **release blocker**.
- Verify schema grants, RLS, migration 025–028 ordering, stored-function bodies and both physical event uniqueness and suppression/send concurrency on disposable PostgreSQL 16.
- Preserve PR #10 claims, current consent, recipient binding, suspension checks, retry bounds, 23-hour ambiguous-outcome horizon, stable send idempotency, `DELIVERY_ENABLED=false`, Weekly capacity limit and unsuppressed dependency audit.
- Obtain independent security review and exclusive source ownership clearance before any repository integration. No PR merge or Production operation is authorized by this package.

See `INTEGRATION_SECURITY_HANDOFF.md` and `EVIDENCE_AND_RESULTS.md` for precise remaining risks and test classification.
