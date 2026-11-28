# C605 — C603 security-review remediation and remaining trust boundary

**Repository:** ADRN-9/deedlight  
**C603 starting candidate:** `121ccd7913a68306d026a3bb38dc7c9853506628`  
**C603 PR:** #41 — remains open, draft and unmerged  
**C605 branch:** `feat/c605-external-ledger-authorization`  
**C605 implementation code head (before this documentation-only update):** `53cde4b67a84128e75841f995603208a7df8b6bd`  
**Exact-head branch workflow:** [run #2460](https://github.com/ADRN-9/deedlight/actions/runs/46103973446) — 13/13 jobs PASS at that code head.  
**Scope:** additive disposable PostgreSQL 16 fixture changes, adversarial tests, and an external Ed25519 authority prototype. No Production changes.

## 1. Repository recovery and preservation

At task start, PR #41 was open/draft/unmerged at the exact C603 candidate. PRs #36–#40 were also open and unmerged. The C603 exact-head CI runs previously recorded as successful were #2415 (PostgreSQL 16 ledger job) and #2416 (13-job PR workflow).

The historical migration tree contained 40 SQL migrations and all 40 paths matched `supabase/migration-inventory.json`. C605 adds no historical migration and changes no C575/C576 contract. C605 is a new branch based on the exact PR #41 head; no existing commits were overwritten.

The GitHub review-submission endpoint returned no C604 review record. This implementation nevertheless treats the Manager-provided C604 REQUEST_CHANGES findings as the authoritative checklist. The absence of a recorded review is not acceptance.

## 2. Recovery target-set race — implemented and PostgreSQL-tested

The old wrapper independently calculated a signed target-set digest and then called the legacy implementation, which re-ran a broad stale-row predicate. The authorized set and mutated set could therefore differ.

C605 changes the disposable wrapper:

1. Validate the stale interval.
2. Select stale execution rows in stable `execution_id` order using `FOR UPDATE`.
3. While those row locks are held, build the exact ordered target snapshot and UUID array.
4. Calculate the target digest from that snapshot and validate the signed authorization against the digest and count.
5. Pass the exact UUID array to `recover_stale_executions_targets_impl(uuid[], interval)`.
6. Update only those IDs, rechecking database resource, state and stale threshold. A row-count mismatch raises a trust failure and rolls back the transaction.

A newly stale row inserted after target selection is deliberately deferred to a later recovery pass.

### PostgreSQL 16 evidence

The exact-head job emitted:
- `C605_RECOVERY_SIGNED_TARGET_SET_MISMATCH_ZERO_MUTATION_PASS`
- `C605_RECOVERY_MUTATES_ONLY_SIGNED_TARGET_SET_PASS`
- `C605_RECOVERY_NEW_STALE_ROW_DEFERRED_TO_NEXT_PASS_PASS`
- `C605_RECOVERY_CONCURRENT_ROW_CHANGE_REJECTED_ZERO_SIDE_EFFECTS_PASS`

The multi-session test holds a stale execution row lock in one PostgreSQL session while the recovery wrapper waits in another. The first session changes the row to `interrupted`; after the lock releases, PostgreSQL rechecks the row predicate. Recovery rejects the now-stale signed target digest, consumes no authorization nonce, and does not overwrite the concurrent writer's state or outcome.

This is actual disposable PostgreSQL 16 concurrency evidence, not a Production race test.

## 3. Monotonic generation and revocation — implemented in disposable SQL fixture

C605 adds a per-actor `authorization_generations` row with generation and active/revoked state.

- Generation updates are guarded: an active generation can advance only by exactly one; it cannot decrement, skip, or be reactivated after revocation.
- Rotation uses compare-and-swap on the expected generation, disables prior keys and installs a new generation key in one transaction.
- Authorization obtains a `FOR SHARE` lock on the active generation row and matching key row. Locks remain held through the protected operation's transaction.
- A concurrent rotation/revocation therefore serializes behind an already-admitted transaction. Requests linearized before revocation may finish; requests starting after the generation transition commits must use the new generation or fail closed.
- Tests reject a generation-1 token after rotation to generation 2, verify the generation-2 key path, reject stale compare-and-swap, and reject a revoked actor.

The PostgreSQL 16 job emitted:
- `C605_MONOTONIC_GENERATION_ROTATION_AND_REVOCATION_PASS`
- `C605_GENERATION_REVOCATION_SERIALIZED_AFTER_INFLIGHT_AUTHORIZATION_PASS`
- `C605_REVOKED_TOKEN_REPLAY_REJECTED_ZERO_SIDE_EFFECTS_PASS`

The multi-session revocation test pauses an admitted verification RPC after authorization, starts revocation from another connection, and records `C605_REVOCATION_WAIT_MS=7937 BLOCKER_PID_OBSERVED=true`. The revocation was observed blocked behind the admitted transaction's generation lock. After the admitted transaction completed, revocation committed; replay of the pre-revocation token then failed with no nonce or verification-event side effects.

This generation table is still database-local. A clone or stale database restore can rewind it. Production generation must be owned by an independently administered, monotonic, linearizable authority.

## 4. External trust architecture prototype

The new `scripts/test-c605-external-authorization.mjs` prototype uses Node's OpenSSL-backed Ed25519 implementation with three distinct key pairs:

- Provider/resource authority signs the live external resource identity and generation.
- Independent policy authority signs actor, operation, request digest, resource, generation, audience and nonce.
- Nonce/fencing authority verifies both assertions, atomically consumes the nonce, and signs a short-lived dispatch receipt.

The disposable nonce store uses atomic exclusive file creation (`O_EXCL`), mode `0600`, and file/directory `fsync`. Tests use two authority instances sharing the same local nonce directory; exactly one concurrent consume wins. A recreated authority object with the same test keys and nonce directory rejects replay even when the simulated restored database's local nonce table is empty.

The prototype also covers:
- physical clone with a copied PostgreSQL system identifier but a different provider resource ID;
- generation rotation and revocation before/after dispatch admission;
- tampered request claims and invalid signatures;
- expiry and future-issued boundaries;
- database transaction rollback after external consume, requiring a fresh nonce on retry.

### Prototype boundary — not Production infrastructure

The provider, policy and nonce key pairs are generated in memory in the same Node test process. The nonce state is a local filesystem simulation shared by test instances, not a separate service or multi-region consensus system. Recreating the authority object is not proof of an actual process/host disaster-recovery drill. No HSM/KMS, provider API, independent cloud account, separate administrative domain, gateway deployment or production network path is provisioned.

The prototype shows a bounded external trust design and fail-closed behavior; it does not prove Production physical-clone protection. Real assurance requires the external resource identity to be authenticated by the infrastructure provider and every dispatch to consult an independently protected, durable, linearizable nonce authority online.

The current C603 PostgreSQL fixture still uses disposable database-held HMAC keys and PostgreSQL JSONB canonicalization. C605 does **not** claim that PostgreSQL now verifies Ed25519 receipts. A reviewed PostgreSQL verifier extension or an approved isolated cryptographic verification boundary, plus gateway-only database networking and per-request online nonce admission, must be selected and integrated before Production.

## 5. Canonicalization specification — JCS-Integer v1 prototype

The external prototype uses a constrained deterministic JSON profile. This is a versioned project profile, not a claim of full RFC 8785 compatibility.

1. Encode canonical output as UTF-8 JSON with no insignificant whitespace.
2. Object keys are sorted by ECMAScript UTF-16 code-unit ordering.
3. Strings and keys must be NFC-normalized Unicode scalar strings. Reject unpaired surrogates; do not silently normalize signed input.
4. Values are limited to objects, arrays, strings, booleans, null and safe integers. Floating-point numbers, NaN, infinities, undefined, symbols, sparse arrays and non-plain objects are rejected.
5. JSON parsers at the wire boundary must reject duplicate object keys before object materialization. Unknown fields are rejected by each operation's closed schema.
6. Hash the exact canonical UTF-8 bytes with SHA-256. Sign versioned, domain-separated typed claims, not a concatenated string or PostgreSQL-only serialization.

Cross-language vectors:

| Input object | Canonical UTF-8 JSON | SHA-256 |
|---|---|---|
| `{"b":2,"a":1}` | `{"a":1,"b":2}` | `43258cff783fe7036d8a43033f830adfc60ec037382473548ac742b888292777` |
| `{"z":1,"a":{"y":true,"x":"é"},"arr":[3,"ok"]}` | `{"a":{"x":"é","y":true},"arr":[3,"ok"],"z":1}` | `b998c4dfd549775bb9ddd3ab0545d44e64fd98cb0d8c04254f8e4e0f6d86d484` |
| `{"message":"café","n":0,"ok":true}` | `{"message":"café","n":0,"ok":true}` | `7baabaafc3c9275b12e78c02044e44aed5536a5543916209083c50f6e99e8abe` |

All three vectors are exercised by the Node tests. A second implementation in the chosen gateway language and a PostgreSQL integration vector suite are still required before this profile is accepted. Existing C603 JSONB text digests are not silently reinterpreted as JCS-Integer digests.

## 6. Constant-time verification

The prototype delegates Ed25519 verification to Node/OpenSSL and tests Node's `timingSafeEqual` for fixed-length byte comparisons. The C603 SQL HMAC comparison remains ordinary SQL equality and is test-only. No reviewed constant-time PostgreSQL primitive has been implemented or approved. This gate is **NOT ESTABLISHED** for Production.

## 7. Exact-head validation evidence

**Code head:** `53cde4b67a84128e75841f995603208a7df8b6bd`  
**Branch workflow:** [run #2460](https://github.com/ADRN-9/deedlight/actions/runs/46103973446) — all 13 jobs PASS.  
**PostgreSQL 16 job:** `140852527578` — PASS. Actual logs contain the recovery, revocation, role, replay and zero-side-effect markers listed above.  
**External authority Node tests:** 12 PASS, 0 FAIL in that PostgreSQL job.

Validation logs confirm:
- TypeScript check — PASS
- Next.js production build with non-Production configuration — PASS
- Cloudflare packaging build with non-Production configuration — PASS
- Dependency advisory gate — PASS
- Migration inventory aggregate, migration ordering, provider webhook, delivery reliability, privacy authorization, production evidence collector, security-definer ownership, auth pgcrypto, gentle transport, migration 037 and Sprint 12.2 jobs — PASS

This is CI evidence for a disposable test environment. It is not Production deploy, Production database, provider or physical-clone evidence.

## 8. Changed-file and migration preservation audit

C605 changes exactly these six files relative to the C603 PR #41 head:

1. `docs/C605_EXTERNAL_AUTHORIZATION_SECURITY_REMEDIATION.md`
2. `scripts/fixtures/migration-execution-ledger-c603-authorization.sql`
3. `scripts/fixtures/test-migration-execution-ledger-c603-authorization.sql`
4. `scripts/fixtures/test-c605-recovery-concurrency.sql`
5. `scripts/test-c605-external-authorization.mjs`
6. `scripts/test-migration-execution-ledger-postgres16.sh`

No file under `supabase/migrations/` and no `supabase/migration-inventory.json` entry is changed. The historical migration tree remains 40/40 and matches the inventory. C575/C576 contracts remain unchanged.

PRs #36–#40 remain open and unmerged. PR #41 remains open, draft and unmerged. No Production data, credentials, signing keys, trust roots, database privileges or infrastructure settings were changed.

## 9. Required human approvals and external dependencies

**Security**
- Approve threat model, provider/resource attestation format, Ed25519 algorithms, independent policy and nonce authorities, canonicalization profile, signature verification boundary, clock bounds, receipt lifetime, revocation semantics and residual provider trust.
- Approve HSM/KMS custody, independent administrative domains, key compromise containment, and the meaning of the physical-clone assurance claim.

**Infrastructure**
- Provide independently authenticated immutable provider resource IDs and live-instance identity.
- Operate the gateway, provider identity adapter and linearizable nonce/fencing authority in separate administrative trust domains.
- Enforce gateway-only private networking, mTLS, endpoint/resource pinning, time synchronization, HA and disaster recovery.
- Demonstrate that clone/restore/failover increments or rebinds the external resource generation.

**DBA / Database Security**
- Select and review a PostgreSQL-compatible Ed25519 verification mechanism or approved isolated verifier boundary.
- Approve dedicated gateway principals, exact grants, direct RPC revocations, network controls, connection pooling and catalog assertions.
- Validate migration behavior and live catalog parity without normal `supabase db push` before migration-history reconciliation.

**Operations**
- Approve alerting, external authority outage behavior, incident response, rollback, nonce retention, backup/restore drills and re-enablement procedures.

## 10. Final status and acceptance boundary

| Finding / gate | Status |
|---|---|
| Recovery mutates only signed target IDs | PASS — PostgreSQL 16 |
| Signed-set mismatch rejected without mutation | PASS — PostgreSQL 16 |
| Newly stale row deferred to later pass | PASS — PostgreSQL 16 |
| Multi-session recovery row-state race | PASS — PostgreSQL 16 |
| Monotonic disposable generation and key rotation | PASS — PostgreSQL 16 |
| Revocation waits behind admitted RPC generation lock | PASS — PostgreSQL 16 |
| Revoked-token replay has zero side effects | PASS — PostgreSQL 16 |
| Five actors × nine RPC privilege/denial matrix | PASS — PostgreSQL 16 |
| Protected-table zero-side-effect assertions | PASS — PostgreSQL 16 |
| External Ed25519 trust-boundary prototype | PASS — 12 Node tests |
| Local file-backed nonce consume across test instances | PASS — prototype only |
| Stale database backup replay after authority-object recreation | PASS — prototype only |
| Physical clone denial using external resource identity | PASS — prototype only |
| Distributed nonce durability / multi-region linearizability | NOT ESTABLISHED |
| Provider-supplied Production resource attestation | NOT ESTABLISHED |
| Second-language canonicalization implementation | NOT ESTABLISHED |
| PostgreSQL Ed25519 verification | NOT IMPLEMENTED |
| Reviewed constant-time PostgreSQL signature verification | NOT ESTABLISHED |
| Production physical-clone protection | NOT ESTABLISHED |
| Production credentials / infrastructure | NOT MODIFIED |
| Independent C604 acceptance | NOT RECORDED |

**Production remains NO-GO.** PR #41 must remain open and unmerged until a fresh independent Security/DBA review accepts the corrected implementation and explicitly resolves or accepts the external infrastructure dependencies. Infrastructure and Operations approvals are also required before any Production integration or trust-boundary changes.
