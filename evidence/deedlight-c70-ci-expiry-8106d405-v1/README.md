# DeedLight Cycle 70 — CI lease-clock and dependency-security evidence

Assignment `DL-C70-CI-EXPIRY-AND-DEPENDENCY-REMEDIATION-D01`, task `8106d405aed14e0ebc0c936d4bcc7c1a`.

- Baseline: `ADRN-9/deedlight` failed Actions run `43606668445`, SHA `cf41a564ff1810aa1c8a592dfb147e5141ec963c`.
- Patch changes **only** `scripts/test-gentle-delivery-transport.sql` when later applied in an authorized integration workspace. No security function or consent logic was modified.
- `patch/test-gentle-delivery-transport.sql`: patched file, not a live shared-source change.
- `patch/0001-ci-transport-claim-relative-clock.patch`: unified patch against GitHub-verified original; its `git hash-object` is `d0cce02799b10cde845344278e00bb57c2dffe42`.
- `source/test-gentle-delivery-transport.original.sql`: byte-verified original copy.
- `tests/test_c70_fixture.py`: deterministic static and Python-reference tests. **Not PostgreSQL**.
- `tests/run_disposable_pg16.sh`: future isolated PostgreSQL 16 test; never run in this environment.
- `evidence/`: failure analysis, dependency upgrade recommendation, execution logs and checkpoint handoff.

To repeat local checks from this directory:

```bash
python3 -m unittest discover -s tests -v
python3 -m py_compile tests/test_c70_fixture.py
bash -n tests/run_disposable_pg16.sh
sha256sum -c SHA256SUMS.txt
```

To apply to a disposable checkout **at the exact baseline**:

```bash
git apply --check /path/to/patch/0001-ci-transport-claim-relative-clock.patch
git apply /path/to/patch/0001-ci-transport-claim-relative-clock.patch
bash /path/to/tests/run_disposable_pg16.sh "$PWD"
```

Do not run against Production. No Delivery/Cron activation. Reviewer ownership status remains unknown.
