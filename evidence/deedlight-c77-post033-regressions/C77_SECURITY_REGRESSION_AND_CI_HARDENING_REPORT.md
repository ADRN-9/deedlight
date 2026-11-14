# DeedLight Cycle 77 — post-033 security regression and CI hardening

**Assignment:** DL-C77-POST033-SECURITY-REGRESSION-AND-CI-HARDENING-D01  
**Recovery baseline:** C76 evidence commit `d786f5640c9702a82b2b0f34c67e30d8d62115b1`  
**Exact reconstructed application tree:** `5b9fa485c0dcc67beb5b82e9623e5dff4e93260b`  
**C76 patch SHA-256:** `88c57e35489b4c7b5b806be02612dff67ef3ffd401cd884976e1d76982251672`  
**Scope:** Evidence-only Git branch; no shared application-source changes, provider sends, or Production operations.

## CLOSED—VERIFIED: source reconstruction

Both isolated C77 workflows independently checked the four pinned C73-C76 patch digests and the staged Git tree after each patch. Expected C75 corrected tree `3ffedca10b5f38b375b08350ea7090e5a0a000d8`; final C76 tree `5b9fa485c0dcc67beb5b82e9623e5dff4e93260b`. No source rewrite was performed.

## CLOSED—VERIFIED: PostgreSQL 16 post-033 event matrix

Successful run: https://github.com/ADRN-9/deedlight/actions/runs/43641058569  
Tested evidence-branch head: `c3bcfc2ecf033be95334c0e4aecebf6bccad81e7`  
GitHub artifact: `14132590121`, `c77-post033-security-pg16`  
Artifact ZIP SHA-256: `7b60293c209de8a6f43b3edc633a21ccf3326a2c6d282630939d5603438e149b`  
Artifact's 9-file manifest verified independently, 9/9 matches.

- Permanent bounce before provider association -> pending -> correlated/persisted -> permanent hold; later delivery success cannot remove it: **PASS**.
- Complaint before correlation -> pending -> promoted; early `suppression.removed` cannot erase spam hold: **PASS**.
- Undetermined bounce before correlation -> pending -> promoted; later delivery success cannot clear temporary hold: **PASS**.
- `email.suppressed` before correlation -> pending -> promoted into durable provider hold: **PASS**.
- Account suppression removal before and after promotion does not release independent permanent/complaint restrictions: **PASS**.
- Exact duplicate event ID is deduplicated; modified-payload replay is quarantined: **PASS**.
- Mismatched signed recipient metadata quarantines the original provider binding and does not suppress unrelated recipient: **PASS**.
- Key rotation from active 1 to legacy 1 + active 2 preserves historical bindings, complaint holds and uncertain holds: **PASS**.
- Requiring a missing historical key version fails closed: **PASS**.
- Attempting final transport with guessed Auth email is rejected; correct-recipient positive control succeeds: **PASS**.

Fixture: `fixtures/test-c77-post033.sql`. Its first draft failed on a fixture-only restricted-table read; a later extension failed on an incorrect fixture assumption that sent jobs retained claim tokens. Both tests were corrected and the final run passed. These were not demonstrated product defects.

## CLOSED—VERIFIED: real PostgreSQL two-session races

Successful run: https://github.com/ADRN-9/deedlight/actions/runs/43641001189  
Tested evidence-branch head: `4467e34176e6dab3f1ce9b9944917a258fd3b19a`  
GitHub artifact: `14132301392`, `c77-concurrent-provider-races-pg16`  
Artifact ZIP SHA-256: `2b54110135908ccd76f55ba8146b40fe17fc299703b3d45531e9f39c308856e0`  
Artifact's 22-file manifest verified independently, 22/22 matches.

Two PostgreSQL client sessions and held transactions tested:
- Daily claim versus concurrent consent revocation: **PASS**; final transport denied.
- Weekly claim versus concurrent consent revocation: **PASS**; final transport denied.
- Complaint transaction versus claimed Daily final authorization: **PASS**; no new transport.
- Original-recipient identity-conflict quarantine versus retry final authorization: **PASS**; no new transport.
- Account suppression removal versus permanent bounce: **PASS**; permanent hold persists.
- No unauthorized synthetic transport persisted for tested revocations: **PASS**.

Vector: `vectors/c77-security-races.sh`. Initial race fixture used an outdated synthetic delivery date and produced a null initial transport; corrected to prior/current UTC due windows, then passed. No provider HTTP was invoked.

## CLOSED—VERIFIED: reuse of prior exact-tree CI

C76 workflow `43637087966`: PostgreSQL16, signed Svix HTTP, security/consent tests, TypeScript, Next.js, Cloudflare package and high-threshold dependency audit **SUCCESS**. C76 workflow `43637533235`: two-session kind isolation and stale/expired lease **SUCCESS**. Both reconstructed the identical application tree used here. C77 did not change that application tree, so costly signed HTTP/build/package checks were not repeated. Exact-head final-release CI and Production deploy/smoke were **NOT TESTED**.

## OPEN: dependency and global PR Validation issues

Nine moderate `glob`/`minimatch` dependency vulnerabilities were previously recorded and remain unresolved. Do not force breaking dependency upgrades. Evidence-branch pushes also triggered the repository's general `PR Validation` workflow: at least one such run failed in legacy transport database behavior and the validation/audit gate. These general-workflow failures are **OPEN**; they do not negate the isolated exact-tree C77 PostgreSQL passes, and they must not be described as final exact-head CI PASS.

## OPEN/BLOCKED: workflow cleanup

The C76 evidence branch still has four temporary workflows under `.github/workflows/`. The publication workflow has `contents: write`; its intended script stages only C76 evidence paths and pushes to the C76 evidence branch, but retaining a writable workflow is unnecessary post-publication. Three sources are archived in C76 evidence. This C77 package archives the fourth, `c76-publish-evidence.yml`.

`recommendations/C76_TEMP_WORKFLOW_CLEANUP.patch` is a **non-applied** four-file deletion patch. Its deleted contents were compared byte-for-byte against all four source files at C76 evidence commit, and it changes no other paths. **Patch application: NOT TESTED**; **cleanup execution: BLOCKED** until coordinator writer-fencing and explicit source-branch approval. No evidence files are deleted.

## OPEN / NOT TESTED

- All mathematically possible event permutations and provider-side live retry behavior.
- Actual provider HTTP race after final DB authorization; the database lock is released before external HTTP and cannot make that boundary atomic.
- Historical key retirement/deletion after complete reconciliation; missing required versions were tested, actual key retirement was not.
- Mid-flight Cloudflare environment kill-switch flip; `DELIVERY_ENABLED=false` was asserted statically and C76 synthetic no-send tests passed.
- Production Cron, actual provider bounce/complaint delivery, kill-switch cycle, release CI, authenticated Production regression and Production smoke.
- Long-term archive of the C77 full CI log ZIPs within Git history. The two GitHub Actions ZIP artifacts are currently retrievable but subject to workflow retention; retain external copies before expiry.

## BLOCKED: ownership / independent review

Original interrupted Developer task `ac39b06970ba4bd78097761e17875524`: terminal state UNKNOWN. Interrupted Reviewer task `24efa58f2e554120aedb6a0f25f76ba8`: terminal state and browser-observer readiness UNKNOWN. No authoritative exclusive shared-source writer lease was supplied. Coordinator must fence old workers, establish expected-SHA ownership and source-write scope, and confirm restored Reviewer readiness before any integration or duplicate review routing.

**Recommended next bounded assignment:** a restored independent Reviewer should inspect the exact C76 tree plus C77 fixtures, logs, tested race boundaries and remaining untested cases. Any defect should receive a narrowly scoped remedy only after exclusive source ownership. No Production operations, merges, tags or Issue #6 closure were performed.
