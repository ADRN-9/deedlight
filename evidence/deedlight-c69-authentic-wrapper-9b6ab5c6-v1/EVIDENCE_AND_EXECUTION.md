# DeedLight C69 — Evidence and execution

## Original sources, SHA-256 verified by direct GitHub connector

- `ADRN-9/deedlight` commit `f4bffa2d24f5241012b99f673eaaa39ac1dc2907` under `evidence/deedlight-c68-authentic-migrations-01f441aa/`:
  - 025 `93f990990b2112e1ee4f049e5d9b9495ffd4d17e43159a9bf6146953d1ae9fc9`
  - 026 `d1f2812f343c799e42583f57265bc967cbeab98ca5400d4206e5bddc559be137`
  - 027 `3d30d188b867ab45e70befb5bbc2f69c5c94e594d29efb5d2758ecc7c7e1b81e`
  - 028 `d0e85b338a6b96fea5fcc8121369cd2dc20faab0cc8183ee01139a0015c0d391`
- Existing C61 registry source and SHA-256: `ed0dc53204c91b6171bc12de40929df6f54bae24e78716f0072d69593e008672`, GitHub evidence commit `80fed7f0b3e07c3c9ee0cf0fdb0675559a54b9bd`.
- Existing unmerged C67 SQL and SHA-256: `453fc32d63bb9a6fbdf44c4b1364c3f377353728e0531362c29f56415861945e`, evidence commit `1e6927b9270f3cd443d5ef1c0ed9af60ec095538`.
- Historical integration candidate SHA `4a403eee5fe4fc45e3decde988dc5e488cdf3b81`; contains no integrated 025–028.

## Corrections

1. Explicitly retire/revoke all three transport starts (`begin_delivery_transport`, `begin_delivery_transport_with_suppression`, `begin_delivery_transport_identity_bound`), all three mark-sent paths, and both webhook record paths. Definer wrappers cannot bypass because function bodies themselves raise 42501. No uncontrolled CASCADE deletion.
2. Exact-event-table preflight uses `svix_event_id text PRIMARY KEY` and explicitly lists processed `delivery_provider_events`, pending `delivery_provider_pending_events`, conflict `delivery_provider_identity_conflicts`. Always-on row and TRUNCATE triggers deny legacy writes. Browser/service privilege revocation, historical rows preserved, C61 registry remains disabled.
3. The SQL preflight refuses unknown overloads and privileged call chains, preserves source ownership evidence in a private inventory, and prevents registry enablement absent separately reviewed cutover.

## Executed

- `python3 -m unittest discover -s tests -p 'test_c69_isolated.py' -v`: **29 discovered; 28 PASS, 1 SKIP** (authentic 025–028 source files not locally mounted; verified byte hashes in GitHub directly). This is source + SQLite-denial surrogate, **not PostgreSQL**.
- Unmodified historical C61 isolated suite: **63 PASS**.
- Unmodified historical C65 isolated suite: **34 PASS**.
- Unmodified historical C67 isolated suite: **40 PASS**.
- Git `apply --check`, Git `apply`, exact-file `cmp`: PASS in disposable local repository.
- Python compilation, shell syntax, package manifest and ZIP integrity: PASS.
- **PostgreSQL 16: NOT TESTED**; Docker, `psql`, and PostgreSQL executable absent.
- **New application/Cloudflare/Next/TypeScript integration: NOT RUN**; no source changes in shared branches.
- Historical GitHub run `43606668445` was actually inspected and did NOT execute this migration; see `evidence/CI_FAILURE_43606668445.md`.

## Disposition

**PARTIAL — concrete isolated hard-stop patch. Source correction submitted for review; PostgreSQL acceptance NOT TESTED; integration BLOCKED; Production NO-GO.**
