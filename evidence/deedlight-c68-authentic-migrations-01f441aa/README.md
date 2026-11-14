# DeedLight — C68 independently authenticated SQL migration proposals (025–028)

## Source identity and authorization
The four UTF-8 SQL files in this evidence-only directory are **byte-for-byte identical** to the isolated **Cycle 48 corrected proposal**, authenticated by Git blob SHA-1 against original ZIP-extracted bytes and their SHA-256 manifests. They are not production migrations, not installed in `main`, and do not authorize `supabase db push`.

- Original C47 ZIP SHA256: fe0bc550997887c31ae43851b05883cc72181eb2af7419fdb05a59aeb3e23fdf; 96/96 original SHA256SUMS entries PASS.
- Original C48 ZIP SHA256: f79eab77a271e82f281f236b493aeeff972424ce7d0b50a4e0e7d2f200b8271a; 49/49 original SHA256SUMS entries PASS.
- C47 combined source patch SHA256: bcf49fed9a51d834d8b61593d6231f28263d5bd860b5fc63d9a844ae2c98e29b; C48 guard patch SHA256: bc663cd7de76f23c7bfbb64321ee9ca7a79d4c55cadd2a4f0872870cfb8d1aa3.
- Source baseline before proposals: `4a403eee5fe4fc45e3decde988dc5e488cdf3b81`. This evidence branch is based on unchanged `main` `ce82b3fdf1a73510de70e3729a487d4ae00e66e3` and changes **only** paths beneath `evidence/deedlight-c68-authentic-migrations-01f441aa/`.

## Verify
```sh
cd evidence/deedlight-c68-authentic-migrations-01f441aa
sha256sum --check SHA256SUMS.txt
```

## Known security/release issues — NOT ACCEPTED
- Event acceptance lifecycle tables: `public.delivery_provider_events` (026), `public.delivery_provider_pending_events` (027), `public.delivery_provider_identity_conflicts` (028); all use `svix_event_id` rather than `event_id`.
- Unsafe event RPC families: `public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)` and `public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)`. The correct retirement must cover both; check definer callers.
- `public.begin_delivery_transport_identity_bound(uuid,uuid,text)` has a service-role EXECUTE grant and is SECURITY DEFINER; revoking only the base RPC does not prove an outbound transport hard-stop.
- The C67 proposed migration 031 is isolated, UNEXECUTED and incompatible with ordinary migration execution until its session-local `pg_temp.c67_reviewed_event_tables` manifest is explicitly provisioned. Its table tripwire ignores `svix_event_id` in genuine legacy stores.
- No PostgreSQL16, negative-role tests, exact-head CI, Prod metadata reconciliation, authenticated webhook suppression, transport safety or Production rollout have been accepted. Exclusive shared-source ownership is unresolved.

**SAFE BOUNDARY:** Evidence-only archival publication, not source integration; no existing application/migration files, PRs, Production data, Worker configuration, Cron or provider sends are modified.
