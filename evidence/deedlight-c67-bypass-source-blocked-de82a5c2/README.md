# DeedLight C67 — conditional legacy webhook hard-stop correction

**Assignment:** `DL-C67-AUTHENTIC-MIGRATION-CORRECTION-D01`, worker `de82a5c20fe34b73a6eb2af7f18ceaa0`.

**Status: PARTIAL / AUTHENTIC SOURCE BLOCKED.** This is an **isolated, unmerged, non-Production** successor design to C65. The authentic migration archives 025–028 (expected SHA-256 `fe0bc550997887c31ae43851b05883cc72181eb2af7419fdb05a59aeb3e23fdf` and `f79eab77a271e82f281f236b493aeeff972424ce7d0b50a4e0e7d2f200b8271a`) were not accessible here. They were not reconstructed or verified. The SQL MUST NOT be accepted against a real schema until those exact source artifacts and a full inventory are recovered, independently reviewed, and proven on disposable PostgreSQL 16.

## Deliverables

- `patch/202611140031_c67_closed_world_legacy_webhook_hard_stop.sql`: a separate, proposed successor to C65 (not an accepted Supabase migration). Its actual target depends on authentic migration review and a per-session reviewed table manifest.
- `patch/ADD_C67_PROPOSED_MIGRATION.patch`: Git-applicable addition under `supabase/migrations/` for a future **authorized** isolated integration branch; never apply directly to `main`/Production.
- `tests/fixture_synthetic_legacy_025_028.sql`: clearly synthetic, intentionally **not** the missing genuine source.
- `tests/postgres_synthetic_success.sql` and `tests/postgres_missing_inventory_rejection.sql`: executable negative fixtures for **later** PostgreSQL 16 verification; **NOT RUN** in this assignment.
- `tests/run_disposable_postgres.sh`: guarded Docker-only runner; never accepts externally linked DB or provider credentials.
- `tests/test_c67_isolated.py`: executable SQLite reference/source-verifier tests. **NOT** a PostgreSQL implementation test.
- `CATALOG_INSPECTION.sql`: metadata-only catalog inspection to run against a disposable database with the authentic 025–028 chain; doesn't select user data or secret contents.
- `provenance/ORIGINAL_C65_UNCHANGED.sql` / `ORIGINAL_C61_UNCHANGED.sql`: byte-identical original local evidence (SHA-256 verified).
- `logs/`: observed local test and CI failure summaries.

## Corrections and STOP semantics

1. Exact RPC families `public.record_resend_webhook_event(...)` **and** `public.record_resend_webhook_event_identity_bound(...)` are both required and retired, all overloads, wrapper first. `DROP FUNCTION ... RESTRICT` stops on dependencies; no CASCADE. The old C65 pattern guard that contradicted existence of the base RPC is removed, **not** bypassed: a post-retirement assertion requires both families absent.
2. `public.delivery_provider_identity_conflicts` is a required, explicitly reviewed table in `pg_temp.c67_reviewed_event_tables`. The exact processed and pending tables **must** be supplied from genuine 025–028 source; this package does **not** claim their names. No name-pattern inventory is trusted. Table/role names outside the closed-world set fail preflight. An event-ID plus provider-related-column catalog scan trips on unreviewed stores.
3. Every attested legacy table receives `ENABLE ALWAYS` veto triggers for INSERT/UPDATE/DELETE and a statement TRUNCATE veto; direct and indirect `SECURITY DEFINER` writes fail. Browser and service-role DML is revoked. Existing rows remain unchanged. Role ownership/membership allowing trigger disablement is a preflight blocker.
4. `deedlight_event_private.registry_control.accepting_new_events` must be false; an always-on trigger blocks subsequent true updates. Existing safe registry functions remain present but cannot accept until independently reconciled and enabled by a separate approved cutover.
5. `public.begin_delivery_transport(uuid,uuid,text)` EXECUTE is revoked from `service_role` and browser roles. This intentionally stops scheduled outbound delivery while bounce/complaint suppression cannot be established. The older consent, lease and idempotency functions are **not** modified. Any future enablement requires reviewed recipient-suppression and transport reauthorization logic.

## Reproduction (local)

```sh
cd deedlight_c67_authentic_blocked_de82a5c2
python3 -m unittest discover -s tests -p 'test_c67_isolated.py' -v
python3 -m py_compile tests/test_c67_isolated.py
bash -n tests/run_disposable_postgres.sh
sha256sum -c SHA256SUMS.txt
```

For a **separately approved disposable PostgreSQL 16 Docker host only**, with all Production connection/provider environment variables absent:

```sh
DEEDLIGHT_C67_DISPOSABLE_APPROVED=true bash tests/run_disposable_postgres.sh
```

That Docker fixture is **synthetic**, not an authentic 025–028 migration-chain test. For the authentic chain, an independent Reviewer must first reproduce the exact original source, write and approve its 3+ concrete `(schema_name,table_name,role_in_pipeline)` inventory entries and execute the proposed SQL in the **same psql session** as that approved temporary inventory. The migration refuses a missing inventory and has not been executed in this assignment.

No existing PR, shared source, CI workflow, Production database, Worker, Cron, secrets, provider or issue was modified. The original C61 and C65 evidence remains unchanged. **MERGE NO-GO / PRODUCTION NO-GO.**
