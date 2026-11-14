# DeedLight C65 — legacy webhook acceptance fail-closed correction

**Assignment:** `DL-C65-LEGACY-WEBHOOK-BYPASS-REMEDIATION-D01`  
**Worker:** `10293e9053104286a3300b06c23d02dd`  
**Scope:** isolated reviewable SQL migration and negative tests, **not an integrated release**.

## Historical source and preserved evidence

- Verified DeedLight integration candidate: `4a403eee5fe4fc45e3decde988dc5e488cdf3b81`.
- Verified C61 evidence publication: `80fed7f0b3e07c3c9ee0cf0fdb0675559a54b9bd`.
- Original C61 archive is **unchanged** in `provenance/ORIGINAL_C61_PACKAGE.zip`, SHA-256 `7e574ba3f8c455f30f5c18c1487fda45dcf5af1d4ae5f15f8ea4745724ea0630`.
- Original C61 registry SQL SHA-256 `ed0dc53204c91b6171bc12de40929df6f54bae24e78716f0072d69593e008672`.
- Authentic migrations 025–028 were **not recovered**. Their exact function signatures, event table names, historical rows, privileges, and recipient-suppression implementation remain UNKNOWN. Do not extrapolate a full integration from synthetic fixtures.

## What is implemented in the standalone patch

`patch/202611140030_close_legacy_webhook_acceptance.sql` is a **post-029** migration candidate. It:

1. Refuses missing C61 registry objects, absent DB roles, an active registry, and repeated installation.
2. Refuses autoactivation. The central registry remains disabled until legacy backfill, historical collision accounting and all bypass paths have independent sign-off.
3. Drops **all overloads** of `public.record_resend_webhook_event_identity_bound` using `DROP FUNCTION ... RESTRICT`. A dependent object causes the entire transaction to fail; no `CASCADE` or silent fallback.
4. Installs `ENABLE ALWAYS` triggers that veto INSERT, UPDATE and DELETE on catalog-discovered old event acceptance tables in reviewed likely schemas, including inside SECURITY DEFINER function calls. The table discovery regex is **not** a substitute for the real 025–028 inventory.
5. Revokes browser/service direct table privileges for the discovered old event tables, creates a private veto inventory and a no-privilege `SECURITY INVOKER` veto trigger function.
6. Refuses additional obviously named legacy acceptance routines; unknown/obfuscated paths still require source inspection.
7. Preserves historical records, pending events, identity conflicts, original suppression records, and the C61 registry unchanged; it does not mark bounce/complaint events processed.

The known unsafe RPC intentionally becomes unavailable (fail-closed). This is a **hard-stop**, not a silent redirect. The server webhook application must be migrated to the reviewed central-registry path before a staged activation.

## Reproduce without Production access

```bash
python3 -m unittest discover -s tests -v
python3 -m unittest discover -s extracted-original/tests -v # after independently extracting C61
bash -n tests/run_disposable_postgres.sh
sha256sum -c SHA256SUMS.txt
```

Optional PostgreSQL 16 test only on a verified isolated Docker engine:

```bash
DEEDLIGHT_C65_DISPOSABLE_ACK=I_CONFIRM_SYNTHETIC_POSTGRES_ONLY \
  bash tests/run_disposable_postgres.sh
```

That script uses a synthetic database inside a Docker container with `--network none`, no host ports and an explicitly synthetic password. **It has not been executed in Cycle 65.** Never run these fixtures on a real or shared database.

## Integration STOP conditions

The patch cannot establish exhaustive bypass closure until the original migrations 025–028, all SQL acceptance entry points, table grants, application webhook routes, and historical collisions are independently reconciled. It must remain isolated pending exclusive-source ownership, PostgreSQL 16 execution, real webhook/SDK regression, durable suppression and recipient-send concurrency tests, and formal Reviewer sign-off. No Production migrations or activation are permitted by this artifact.
