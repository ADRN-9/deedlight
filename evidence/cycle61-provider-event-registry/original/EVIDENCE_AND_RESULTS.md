# C61 raw execution evidence and limits

- Project / repo: DeedLight / `ADRN-9/deedlight`.
- Task: `0871d1bf81e545bcb38224b3a7b58cd9`.
- Exact baseline read-only GitHub verification: main `ce82b3fdf1a73510de70e3729a487d4ae00e66e3`, integration feasibility `4a403eee5fe4fc45e3decde988dc5e488cdf3b81`, PR #10 `c983e2ed8b93c935139c935343261570ecea6978` draft/unmerged, PR #11 `aed588d771dc04fda5e5c18d8611239ac926a513` draft/unmerged.
- Original expected Cycle 47–48 archives NOT RECOVERED. Their claimed SHA-256 values are copied as **expected, unverified** references, not certified artifacts.
- Previous C60 official SDK compatibility status: **BLOCKED**. Its available ZIP SHA-256 was verified locally, but this task did not redo SDK comparison.
- Local environment: Python 3.13.5, SQLite 3.46.1; `psql`, `postgres`, `initdb`, `pg_ctl`, `docker` and `podman` were not found. PostgreSQL source SQL **not parsed/executed**.
- Local SQLite test uses actual in-process SQLite btree uniqueness and transaction locking with separate connections/threads. It is a surrogate and **not equivalent** to PostgreSQL `INSERT ... ON CONFLICT`, row locking, function grants or Supabase RPC behavior.
- `tests/test_registry_reference.py`: 46 tests (synthetic identities, duplicate/pending/processed/conflicts, quarantine evidence, actual SQLite concurrency, historical collision preflight, out-of-order event and application of safe-only processing).
- `tests/test_patch_safety.py`: 17 source-text invariants; passes do not establish PostgreSQL semantics.
- One early static-test run failed due to a case mismatch in the test harness and emitted SQLite connection ResourceWarnings. The tests were corrected and connections closed. The final run is the authority, without hiding the earlier failure.
- PostgreSQL 16 integration fixture and independent role/grant tests: **NOT RUN** (environment lacks a disposable server). The Docker-only runner is provided as future executable test material; its `bash -n` check does **not** prove its PG assertions pass.
- Browser/Production/Supabase/Resend webhook end-to-end tests: **NOT RUN**. No provider sends, Production access, repo commits, CI, branch creation, migration application or PR changes occurred.

## Final local commands

```sh
python3 -W error::ResourceWarning -m unittest discover -s tests -v
bash -n tests/run_disposable_postgres.sh
python3 -m compileall -q tests
sha256sum -c SHA256SUMS.txt
```

Full sanitized unittest stdout/stderr: `evidence/all_local_tests.log`. Manifest/ZIP verification results are recorded separately in `evidence/package_verification.log`. No actual user addresses or credentials appear in test fixtures.

## Gate classification

| Check | Disposition |
|---|---|
| Isolated database-authoritative event-ID registry SQL authored | **IMPLEMENTED (local artifact only)** |
| Live PostgreSQL 16 execution and concurrent UNIQUE/role checks | **NOT TESTED** |
| SQLite reference and source-text checks | **CLOSED—VERIFIED for the local surrogate only** |
| Event-ID uniqueness across the real 025–028 physical stores | **BLOCKED — source unavailable, cutover not integrated** |
| Historical event backfill/reconciliation | **BLOCKED** |
| Complaint/bounce atomic suppression and final send authorization | **OPEN / NOT IMPLEMENTED HERE** |
| Actual pinned Resend SDK verification / webhook handler | **BLOCKED (Cycle 60)** |
| Recipient identity under key rotation/canonicalization | **OPEN** |
| Merge or Production deployment gate | **BLOCKED / NO-GO** |
