# DeedLight Cycle 61 — original evidence-only recovery

**Project:** DeedLight only (`ADRN-9/deedlight`)
**Cycle 61 worker:** `0871d1bf81e545bcb38224b3a7b58cd9`
**Cycle 63 recovery worker:** `fa0f0f17b548461da2b3d40dd4731f03`
**Status:** evidence recovered and published for independent review. **NOT** an accepted implementation, merge approval or Production release.

## Identity and byte-verification

- **Original unchanged archive:** `ORIGINAL_C61_PACKAGE.zip`
- **Archive SHA-256:** `7e574ba3f8c455f30f5c18c1487fda45dcf5af1d4ae5f15f8ea4745724ea0630`
- **Archive byte length:** 35,836; **ZIP entries:** 17; CRC integrity PASS
- **Original migration SQL SHA-256:** `ed0dc53204c91b6171bc12de40929df6f54bae24e78716f0072d69593e008672`
- **Original file manifest:** `original/SHA256SUMS.txt`; 15 of 15 listed files verified
- **Archive versus extracted files:** 17 of 17 byte-for-byte matching
- Directly published files under `original/` were checked against their original Git blob hashes. The ZIP contains **all** original 17 files including test fixtures, both reference tests, six original logs, and the original docs. No archive byte or original source was rewritten.

## Independent reproduction

```sh
# Obtain ORIGINAL_C61_PACKAGE.zip from this evidence-only GitHub branch or pinned commit.
sha256sum ORIGINAL_C61_PACKAGE.zip
unzip -t ORIGINAL_C61_PACKAGE.zip
unzip -q ORIGINAL_C61_PACKAGE.zip
cd deedlight_c61_event_dedup_0871d1bf
sha256sum -c SHA256SUMS.txt
python3 -W error::ResourceWarning -m unittest discover -s tests -v
bash -n tests/run_disposable_postgres.sh
```

To retrieve this archive from GitHub, use the **Raw** link of `ORIGINAL_C61_PACKAGE.zip`. An independent Reviewer should compare the downloaded ZIP's SHA-256 to the value above, then validate its internal manifest before inspecting or executing anything.

## Verification dispositions

- **Cycle 63 rerun of recovered local tests:** 63 PASS, 0 FAIL (46 SQLite transactional/concurrency-reference + 17 static source-safety tests).
- **Original patch applicability:** previously reported in Cycle 61 logs; not independently re-applied in Cycle 63.
- **Shell syntax:** PASS.
- **PostgreSQL 16 executable behavior:** **NOT TESTED** — no PostgreSQL or Docker in Cycle 63 environment. The test runner is an unexecuted fixture, not a passing database test.
- **Application integration with actual 025–028 lifecycle tables:** **BLOCKED** — those original archives are not recovered.
- **Webhook/Resend and suppression behavior:** **NOT TESTED / OPEN**.
- **Repository source integration:** **NOT APPLIED**.
- **Merge / Production:** **NO-GO**.

This commit adds **only** evidence files on a uniquely named evidence branch; it does not modify PR #10, PR #11, `main`, application source, migrations, deployments or Production state.

The PostgreSQL fixture contains only a clearly marked disposable synthetic password (`synthetic-c61-local-only`); no live secrets, customer addresses or Production credentials were detected in the original archive review. Do not run the fixture against a shared or Production database.

**Source baseline recorded in original package:** `4a403eee5fe4fc45e3decde988dc5e488cdf3b81` (historical feasibility commit). Migration 025–028 integration and the Supabase migration-history discrepancy remain unverified.
