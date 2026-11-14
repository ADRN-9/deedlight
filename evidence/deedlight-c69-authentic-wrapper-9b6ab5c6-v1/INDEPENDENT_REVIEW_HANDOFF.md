# Cycle 69 — Independent Reviewer security gate

Assignment `DL-C69-TRANSPORT-WRAPPER-REMEDIATION-D01`, task `9b6ab5c633f64b35bd0d67a84ef6a5a5`.

## Findings verified against authentic 025–028

- 025 replaces `public.claim_delivery_jobs(timestamptz,integer)` with kind-bound `public.claim_delivery_jobs(text,timestamptz,integer)`.
- 026 defines `public.delivery_provider_events(svix_event_id PRIMARY KEY)` and `public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)`; defines `public.mark_delivery_sent_with_recipient(uuid,uuid,text,text)`.
- 027 defines `public.delivery_provider_pending_events(svix_event_id PRIMARY KEY)`, `public.delivery_recipient_state` and `public.begin_delivery_transport_with_suppression(uuid,uuid,text,text)`; the latter calls 024's `begin_delivery_transport(uuid,uuid,text)` internally. The mark-sent wrapper calls the base record RPC to promote pending events.
- 028 defines `public.delivery_provider_identity_conflicts(svix_event_id PRIMARY KEY)`, `public.begin_delivery_transport_identity_bound(uuid,uuid,text)` (the **service-role privileged wrapper**), `public.mark_delivery_sent_identity_bound(uuid,uuid,text)`, and `public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)`; the identity-bound recorder calls the base event recorder. This confirms C67 revocation of the base transport RPC alone was insufficient.

## Proposed implementation

This successor is **stop-only**: it rewrites bodies of all eight authentic transport, mark-sent and webhook recorder functions to explicit SQLSTATE 42501 failures, preserving signature and dependencies; revokes `PUBLIC`, `anon`, `authenticated`, `service_role` execution on these and the three C61 registry RPCs; adds `ENABLE ALWAYS` BEFORE INSERT/UPDATE/DELETE and TRUNCATE veto triggers on the **three exact authentic tables**; and refuses to enable `deedlight_event_private.registry_control.accepting_new_events`.

The eight protected functions are:

1. `public.begin_delivery_transport(uuid,uuid,text)` (024)
2. `public.begin_delivery_transport_with_suppression(uuid,uuid,text,text)` (027)
3. `public.begin_delivery_transport_identity_bound(uuid,uuid,text)` (028, service_role wrapper)
4. `public.mark_delivery_sent(uuid,uuid,text)` (020)
5. `public.mark_delivery_sent_with_recipient(uuid,uuid,text,text)` (026/027)
6. `public.mark_delivery_sent_identity_bound(uuid,uuid,text)` (028)
7. `public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)` (026/027)
8. `public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)` (028)

The three physically protected tables are `public.delivery_provider_events` (026 processed), `public.delivery_provider_pending_events` (027 pending), and `public.delivery_provider_identity_conflicts` (028 quarantine). All use `svix_event_id text PRIMARY KEY`, not `event_id`.

`deedlight_event_private.provider_event_registry` (C61) is the proposed future event authority, but stays **disabled**. Do not conflate physical freeze with operational provider lifecycle acceptance. Existing historical rows and suppression state are preserved; no acceptance or external send is permitted by this patch. It does not delete any migration 025–028 object.

## Mandatory independent acceptance checks

- Run `tests/run_disposable_pg16.sh` with an approved isolated authentic 019–024 bootstrap and the unmodified SHA256-verified original 025–028 + C61 files. Do not use the synthetic C65/C67 stand-ins.
- Verify the preflight succeeds only on the authentic object graph and rolls back on a missing table, wrong `svix_event_id` type or key, unknown overload, unknown definer call chain, missing registry, or pre-enabled registry.
- Run direct base RPC and identity wrapper calls, including when called indirectly from a definer-owned function; all must fail with SQLSTATE 42501. Verify `service_role` cannot EXECUTE the identity-bound wrapper. Check `anon`/`authenticated` privileges and table ACL/RLS.
- Verify all three `svix_event_id` tables reject INSERT/UPDATE/DELETE/TRUNCATE, including definer-owned writes; preserve synthetic historical pending and quarantine rows. Confirm malformed event ID cannot be accepted through another path.
- Try concurrent duplicate requests against processed/pending/conflict entry points and show the registry remains disabled; this is stop-only denial, **not** proven active cross-table deduplication.
- Check safe rollback through normal transaction failure. A subsequent authorized cutover must deliberately restore the reviewed RPCs, provision the keyring, reconcile historical IDs, implement atomic suppression, and prove consent/identity/lease and cross-kind behavior. Never regrant a bypass function or restore unsafe 024 fallback.
- Verify Cloudflare/Next/TypeScript and unsuppressed dependency audit against the **integrated exact SHA**, not the evidence branch.

## Known unresolved risks

Authenticated webhook receiver and Resend SDK integration, provider event classification, permanent-bounce/complaint and `email.suppressed` atomic suppression, historical global event-ID reconciliation, HMAC key rotation and email normalization, pending-event promotion, provider/ledger correlation, concurrent suppression/send linearization and failed/ambiguous outcome handling remain **OPEN**. This patch disables outgoing transport as a fail-closed interim action; it does NOT make the complete delivery system release-ready.

Production migration history remains unreconciled and source ownership remains unconfirmed. No shared application-source update, Production SQL, Cron activation, send, deploy, merge or Issue #6 closure is authorized.

**Recommended disposition: source-level correction ready for independent review; PostgreSQL acceptance NOT TESTED; integration and Production BLOCKED.**
