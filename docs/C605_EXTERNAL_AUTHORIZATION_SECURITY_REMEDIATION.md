# C605 — C603 security-review remediation and remaining trust boundary

**Repository:** ADRN-9/deedlight  
**C603 starting candidate:** `121ccd7913a68306d026a3bb38dc7c9853506628`  
**C603 PR:** #41 (must remain open, draft and unmerged)  
**C605 branch:** `feat/c605-external-ledger-authorization`  
**Scope:** additive disposable PostgreSQL 16 fixture changes, adversarial tests, and an external Ed25519 authority prototype. No Production changes.

## 1. Repository recovery and preservation

At task start, PR #41 was open/draft/unmerged at the exact C603 candidate. PRs #36–#40 were also open and unmerged. The C603 exact-head CI runs previously recorded as successful were #2415 (PostgreSQL 16 ledger job) and #2416 (13-job PR workflow).

The historical migration tree contained 40 SQL migrations and all 40 paths matched `supabase/migration-inventory.json`. C605 adds no historical migration and changes no C575/C576 contract. PR #41's branch and commit history are not rewritten; C605 is a new branch based on the exact PR #41 head.

The GitHub review-submission endpoint currently returns no C604 review record. This implementation nevertheless treats the Manager-provided C604 REQUEST_CHANGES findings as the authoritative checklist. No claim is made that a formal independent review is recorded or accepted.

## 2. Recovery target-set race — implementation

The old wrapper independently calculated a signed target-set digest and then called the legacy implementation, which re-ran a broad stale-row predicate. That permitted the set subsequently mutated to differ from the set that had been authorized.

C605 changes the disposable wrapper as follows:

1. Validate the stale interval before querying.
2. Select stale execution rows in stable `execution_id` order using `FOR UPDATE`.
3. While those row locks are held, build the exact ordered target snapshot and UUID array.
4. Calculate the target digest from that snapshot and validate the signed authorization against that digest and count.
5. Pass the exact UUID array to `recover_stale_executions_targets_impl(uuid[], interval)`.
6. Update only those IDs, rechecking database resource, state and stale threshold. A row-count mismatch raises a trust failure and rolls back the transaction.

A newly stale row inserted after target selection is deliberately deferred to a later recovery pass. The test injects such a row from an AFTER UPDATE trigger while the selected row is being recovered; it proves the new row is not silently included in the already-authorized set. A separately signed empty target set is also rejected when a row becomes stale before invocation, with the row unchanged.

**Boundary:** this is a deterministic interleaving/race-injection test and row-locking implementation test. It is not yet a multi-session PostgreSQL recovery race benchmark. That remains a CI follow-up if the current test runner cannot safely exercise two independent recovery sessions.

## 3. Monotonic generation and revocation — disposable implementation

C605 adds a per-actor `authorization_generations` row with generation and active/revoked state.

- Generation updates are guarded: an active generation can advance only by exactly one; it cannot decrement, skip, or be reactivated after revocation.
- Rotation uses compare-and-swap on the expected generation, disables prior keys and installs a new generation key in one transaction.
- Authorization obtains a `FOR SHARE` lock on the active generation row and the matching key row. The locks remain held through the protected operation's transaction.
- A concurrent rotation/revocation therefore serializes behind an already-admitted transaction. Requests linearized before revocation may finish; requests starting after the generation transition commit must use the new generation or fail closed.
- Tests reject a generation-1 token after rotation to generation 2, verify the generation-2 key path, reject stale compare-and-swap, and reject a revoked actor.

This is a disposable SQL model. The generation table is still database-local and is not an independent monotonic authority. A database clone or stale restore can rewind it. Production generation must be owned by an independently administered linearizable authority.

## 4. External trust architecture prototype

The new `scripts/test-c605-external-authorization.mjs` prototype uses Node's OpenSSL-backed Ed25519 implementation with three distinct key pairs:

- Provider/resource authority signs the live external resource identity and generation.
- Independent policy authority signs the actor, operation, request digest, resource, generation, audience and nonce.
- Nonce/fencing authority verifies both assertions, atomically consumes the nonce, and signs a short-lived dispatch receipt.

The test model includes:
- 32 concurrent consumes of the same nonce, exactly one winner;
- physical clone with a copied PostgreSQL system identifier but a different external provider resource ID;
- stale local backup with a restored empty nonce table, while the external nonce authority retains the consumed nonce;
- generation rotation and revocation before/after dispatch admission;
- tampered request claims and invalid signatures;
- expiration and future-issued boundaries;
- database transaction rollback after external consume, requiring a fresh nonce on retry.

### Important limits

This is a bounded prototype, not an external infrastructure deployment. The three key pairs and nonce store are in one Node test process and in-memory state. It does not demonstrate durable nonce consumption across process restart, independent accounts, provider attestation, HSM/KMS custody, multi-region linearizability, a live gateway, or a real database connection.

The current C603 PostgreSQL fixture still uses disposable database-held HMAC keys and PostgreSQL JSONB canonicalization. C605 does **not** claim that PostgreSQL now verifies Ed25519 receipts. A reviewed PostgreSQL verifier extension or an approved isolated cryptographic verification boundary, plus gateway-only database networking and per-request online nonce admission, must be selected and integrated before Production.

No database-local system identifier, nonce table, or generation table is represented as physical-clone protection. A clone is denied in the prototype only when the independently attested external resource ID differs and the external authority is consulted online for each dispatch.

## 5. Canonicalization specification — JCS-Integer v1 prototype

The external prototype uses a constrained deterministic JSON profile. This is a versioned project profile, not a claim of full RFC 8785 compatibility.

1. Encode canonical output as UTF-8 JSON with no insignificant whitespace.
2. Object keys are sorted by ECMAScript UTF-16 code-unit ordering.
3. Strings and keys must be NFC-normalized Unicode scalar strings. Reject unpaired surrogates; do not silently normalize signed input.
4. Values are limited to objects, arrays, strings, booleans, null and safe integers. Floating-point numbers, NaN, infinities, undefined, symbols, sparse arrays and non-plain objects are rejected.
5. JSON parsers at the wire boundary must reject duplicate object keys before object materialization. Unknown fields are rejected by each operation's closed schema.
6. Hash the exact canonical UTF-8 bytes with SHA-256. Sign the versioned domain-separated typed claims, not a concatenated string or a PostgreSQL-only serialization.

Cross-language vectors:

| Input object | Canonical UTF-8 JSON | SHA-256 |
|---|---|---|
| `{"b":2,"a":1}` | `{"a":1,"b":2}` | `43258cff783fe7036d8a43033f830adfc60ec037382473548ac742b888292777` |
| `{"z":1,"a":{"y":true,"x":"é"},"arr":[3,"ok"]}` | `{"a":{"x":"é","y":true},"arr":[3,"ok"],"z":1}` | `b998c4dfd549775bb9ddd3ab0545d44e64fd98cb0d8c04254f8e4e0f6d86d484` |
| `{"message":"café","n":0,"ok":true}` | `{"message":"café","n":0,"ok":true}` | `7baabaafc3c9275b12e78c02044e44aed5536a5543916209083c50f6e99e8abe` |

These vectors are exercised by the Node test. A second implementation in the chosen gateway language and a PostgreSQL integration vector suite are still required before the profile is accepted. Existing C603 JSONB text digests are not silently reinterpreted as JCS-Integer digests.

## 6. Constant-time verification

The prototype delegates Ed25519 verification to Node/OpenSSL and uses Node's `timingSafeEqual` only for a fixed-length byte comparison helper. The C603 SQL HMAC comparison remains ordinary SQL equality and is test-only. No reviewed constant-time PostgreSQL primitive has been implemented or approved. This gate is **NOT ESTABLISHED** for Production.

## 7. Changed-file scope

Expected C605 additions/changes:
- `scripts/fixtures/migration-execution-ledger-c603-authorization.sql` — exact-set recovery and disposable generation/revocation model.
- `scripts/fixtures/test-migration-execution-ledger-c603-authorization.sql` — recovery target-set interleaving, zero-mutation, generation rotation and revocation assertions.
- `scripts/test-c605-external-authorization.mjs` — external Ed25519 authority prototype and canonicalization vectors.
- `scripts/test-migration-execution-ledger-postgres16.sh` — invokes the C605 prototype after the historical ledger suite and C603 fixture.

The complete PR changed-file list and migration-inventory comparison must be rechecked at the final exact head.

## 8. Required human approvals / external dependencies

**Security**
- Approve threat model, provider/resource attestation format, Ed25519 algorithms, independent policy and nonce authorities, canonicalization profile, signature verification boundary, clock bounds, receipt lifetime, revocation semantics, key rotation and residual provider trust.
- Approve HSM/KMS custody, independent administrative domains, key compromise containment, and the meaning of the physical-clone assurance claim.

**Infrastructure**
- Provide independently authenticated immutable provider resource IDs and live-instance identity.
- Operate the gateway, provider identity adapter and linearizable nonce/fencing authority in separate administrative trust domains.
- Enforce gateway-only private networking, mTLS, endpoint/resource pinning, time synchronization, HA and disaster recovery.
- Demonstrate that clone/restore/failover increments or rebinds the external resource generation.

**DBA / Database Security**
- Select and review a PostgreSQL-compatible Ed25519 verification mechanism or approved isolated verifier boundary.
- Approve dedicated gateway principals, exact grants, direct RPC revocations, network controls, connection pooling, and catalog assertions.
- Validate migration behavior and live catalog parity without normal `supabase db push` before migration-history reconciliation.

**Operations**
- Approve alerting, external authority outage behavior, incident response, rollback, nonce retention, backup/restore drills and re-enablement procedures.

No Production credentials, signing keys, trust roots, database privileges, provider accounts or infrastructure settings were modified. No Production data was read or changed by C605.

## 9. Status and acceptance boundary

| Finding / gate | C605 status |
|---|---|
| Recovery mutates only the signed target IDs | IMPLEMENTED; PostgreSQL CI pending |
| Recovery signed-set mismatch is rejected without mutation | IMPLEMENTED; PostgreSQL CI pending |
| Newly stale rows are deferred to a later pass | IMPLEMENTED; deterministic trigger interleaving test pending |
| Monotonic disposable generation and key revocation | IMPLEMENTED; PostgreSQL CI pending |
| Generation/key row lock serializes SQL authorization against rotation | IMPLEMENTED in disposable fixture; CI pending |
| External Ed25519 authority model | PROTOTYPED in Node |
| Clone identity separation using external provider resource ID | PROTOTYPED; no provider integration |
| External nonce persistence across stale DB restore | PROTOTYPED in-memory; durable external service NOT ESTABLISHED |
| External concurrent nonce consume | PROTOTYPED in-process; distributed linearizability NOT ESTABLISHED |
| Cross-language canonicalization | Node vectors implemented; second language NOT ESTABLISHED |
| PostgreSQL Ed25519 verification | NOT IMPLEMENTED |
| Reviewed constant-time PostgreSQL signature verification | NOT ESTABLISHED |
| Production physical-clone protection | NOT ESTABLISHED |
| Production credentials / infrastructure | NOT MODIFIED |
| Independent C604 acceptance | NOT RECORDED |

Production remains **NO-GO**. PR #41 must remain open and unmerged until a fresh independent security review accepts the corrected implementation and explicitly resolves or accepts the external infrastructure dependencies.
