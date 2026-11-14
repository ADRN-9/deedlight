# DeedLight C70 — Executed command record and limitations

Worker: `8106d405aed14e0ebc0c936d4bcc7c1a`.

## Source identity checks (performed)

Read-only GitHub connector retrieval at `cf41a564ff1810aa1c8a592dfb147e5141ec963c`:

- `scripts/test-gentle-delivery-transport.sql`: Git blob `d0cce02799b10cde845344278e00bb57c2dffe42`.
- `scripts/test-delivery-reliability-terminals.sql`: Git blob `31634044ca7873a6fb134635be85f39f6f12a0ae`.
- `supabase/migrations/202609230020_delivery_reliability_hardening.sql`: Git blob `554615da3d15fc4c0d395691103d3be5676856fa`.
- `supabase/migrations/202609230021_gentle_delivery_transport.sql`: Git blob `e50a06bd3a5ed386c54e789435c64b2bb4a54ab9`.
- `package.json`: Git blob `76cbb9f2cb84dcd8c316ef99efff7a052e573782`.
- `package-lock.json`: Git blob `78f4d841ec05dfda5b0b405478ab33dc75efba20`.
- `.github/workflows/pr-validation.yml`: Git blob `2fc21bc11f8138b30f139c320dd241eb98c30adb`.

Original SQL was copied byte-for-byte; local `git hash-object source/test-gentle-delivery-transport.original.sql` returned exactly `d0cce02799b10cde845344278e00bb57c2dffe42`.

## Actually executed local commands

```bash
python -m unittest discover -s tests -v
python -m py_compile tests/test_c70_fixture.py
bash -n tests/run_disposable_pg16.sh
npm view next@16.4.6 version --fetch-retries=0 --fetch-timeout=3000
```

Actual outcomes:
- **27 Python tests PASS**, 0 FAIL, 0 SKIPPED. The tests include `git apply --check`, real `git apply` on a disposable original fixture, and byte-for-byte comparison.
- Python compilation **PASS**.
- Bash runner syntax **PASS**.
- npm registry reachability **FAILED**: `getaddrinfo EAI_AGAIN registry.npmjs.org` (log included).
- PostgreSQL binary (`psql`) **NOT INSTALLED**; Docker **NOT INSTALLED**. No PostgreSQL fixture run occurred.
- A new `npm audit` on the full lockfile **NOT RUN** (registry unavailable and no local full repository checkout). The original **real CI audit** from run 43606668445 was inspected instead, and remains failing.
- TypeScript, Next build, Cloudflare packaging, GitHub CI at corrected head and Production verification **NOT RUN**.

## Interpretation

The lease/identity/reference tests only demonstrate a corrected *synthetic fixture* and independently checked source semantics. They do not demonstrate a successful PostgreSQL execution, a clean dependency audit, or Production safety. No privileged credentials, external email, Production services, or customer data were used.
