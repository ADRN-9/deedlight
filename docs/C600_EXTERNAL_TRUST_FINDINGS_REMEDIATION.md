# C600 — Remediation of C598 external trust-binding findings

**Status:** Architecture remediation and disposable SQL authorization regression. This is not Production implementation. F-01 through F-08 are addressed as design requirements below; controls requiring provider, verifier, gateway, cryptographic SQL validation, and Production privilege changes remain **NOT IMPLEMENTED / NOT PROVEN**.

- Repository: `ADRN-9/deedlight`
- C598 baseline: `5da7cde1f1d02a47bde1575c20a32e091d051ab3`
- PR #37 remains separate from PR #36; neither is merged by this work.
- No Production resources, credentials, signing keys, database privileges, scheduler settings, or historical migrations are changed.
- C599 review artifact: not present in PR #37 reviews/comments, the checked base tree, or the repository branch/PR inventory available during this task. The explicit F-01…F-08 list in the assignment is therefore used as the remediation checklist. Independent review should attach the original C599 report if it exists elsewhere.

## 1. Security decision and scope

A single application gateway plus a single verifier key is not a sufficient trust boundary. The revised design uses four distinct controls:

1. **Network/credential boundary:** only gateway workloads can reach the privileged database endpoint, and only dedicated operation-class database identities receive narrowly scoped execute privileges.
2. **Database cryptographic boundary:** legacy privileged RPC entry points are not directly callable by gateway or application logins. Versioned authorization wrappers validate a verifier authorization, independent policy authorization, and a one-use signed dispatch receipt before calling private internal ledger operations.
3. **Independent authorization boundary:** workload/resource evidence and policy approval are produced by independently administered authorities with separate signing keys and control planes.
4. **Linearizable dispatch boundary:** a strongly consistent nonce/fencing authority serializes consume, generation transitions, and dispatch admission. Old generations cannot create new dispatch permits after a generation transition begins.

No single DB-local row, caller-supplied GUC, database system identifier, copied nonce table, gateway assertion, or queue claim is accepted as independent trust proof.

### Assurance boundary

This design can detect a physical clone that presents a different independently authenticated provider resource identity. It cannot prove integrity if the provider control plane, provider identity authority, and all independent trust authorities are jointly compromised or falsely attest the same resource. That is an explicit residual dependency, not a claim of absolute physical-clone prevention.

## 2. F-01 — Defensible gateway authorization boundary

### Required boundary

- The application, browser, migration runner, and ordinary service roles have no network route or database `EXECUTE` privilege for privileged ledger functions.
- A dedicated gateway service is the only network path to the privileged DB endpoint. Endpoint allowlisting, private networking, mTLS workload identity, TLS hostname/resource verification, and a dedicated secret broker enforce this path.
- Gateway database identities are separated by actor class (approver, runner, observer, verifier, recovery). There is no shared superuser or shared all-purpose gateway DB login.
- Each actor-class login receives only its corresponding narrow RPC grants. It cannot `SET ROLE` to another actor class, own ledger objects, create functions, modify grants, or access ledger tables directly.
- Legacy privileged function signatures are retained as internal implementation contracts but have direct `EXECUTE` revoked from every login, including gateway logins.
- Add versioned public authorization wrappers (one per operation, e.g. `*_authorized_v2`) that accept the unchanged operation parameters plus a bounded authorization envelope. Each wrapper validates the verifier authorization signature, independent policy signature, and nonce-authority dispatch receipt against the exact typed request before invoking a private owner-only implementation. The old C575/C576 ledger data contracts and historical migration files remain unchanged.
- The DB validates the signatures and claims itself using an approved, pinned verification mechanism. Gateway-side-only validation is insufficient because a gateway credential holder could otherwise call the legacy RPC directly.
- The wrapper rejects missing, malformed, expired, wrong-audience, wrong-operation, wrong-resource, wrong-generation, wrong-execution, wrong-source, wrong-artifact, wrong-parameter-digest, revoked-key, replayed, or mismatched receipts before any mutation.
- No wrapper or verifier implementation is selected here. Cryptographic extension/runtime and key-distribution choices require Security and DBA approval.

A gateway database credential is not itself authorization. Possession of a gateway credential without a valid per-call authorization envelope must not execute a privileged operation.

### Direct-call test contract

For each of the nine existing privileged RPCs:
1. Direct invocation by anon/authenticated/application/ordinary admin roles fails at PostgreSQL privilege checking.
2. Direct invocation by every gateway actor login using the legacy signature fails at PostgreSQL privilege checking.
3. Direct invocation through the corresponding v2 wrapper with no envelope or an invalid envelope fails signature/claim/nonce validation.
4. The test records pre/post counts and hashes for approvals, executions, snapshots, commit markers, verification events, and all operation-specific effects. Every negative case requires exact equality and zero external dispatches.
5. A positive test with independently signed valid evidence authorizes exactly one operation and produces one correlated audit record.

A failure response alone is not sufficient: all side-effect assertions must pass.

## 3. F-02 — Approver, runner, observer, recovery and verifier separation

The five actor classes remain separate principals, not merely labels inside a shared service:

| Actor | Permitted operation | Must not possess |
|---|---|---|
| Approver | Approve an immutable record/execution/source scope | Runner, observer, recovery or verifier credentials |
| Runner | Reserve/start/heartbeat/marker/finalize only its own execution | Approval signing authority, observer evidence authority, recovery or verifier credentials |
| Observer | Capture registered pre/post snapshots | Approval, runner, recovery or verifier credentials |
| Recovery | Recover stale reservations/running executions under bounded policy | Ability to approve, run, observe, or verify |
| Verifier | Record independent verification for terminal execution | Approval, runner, observer, recovery or database-owner authority |

Enforcement requirements:

- Separate non-inheriting PostgreSQL roles and separate login principals. Each login maps to exactly one actor class in an independently controlled principal registry.
- At each wrapper and internal function boundary, derive actor identity from authenticated `session_user` mapped to the registry, not a caller-controlled argument or `current_setting('role')` alone. Reject unexpected `SET ROLE`, role membership, session authorization changes, and shared connection pools that erase principal identity.
- No principal is a member of more than one actor role. No runtime login is superuser, database owner, role administrator, or owner of SECURITY DEFINER functions.
- Observer independence from approver/runner is checked against immutable principal IDs, not display names.
- Verifier is independently deployed and cannot update execution status; it may append only a verification event for a terminal execution.
- Recovery actions require a separate recovery principal and produce an append-only recovery audit event with reason, stale threshold, and affected execution IDs.
- Human approver identities and workload principals are separately attributable. CI role simulation is not Production identity proof.

The existing fixture's `actor_role()` uses `current_setting('role')`; it is a test role simulator, not an acceptable Production principal-authentication design. Production integration must replace the simulator behind a reviewed, backward-compatible boundary.

## 4. F-03 — Independently authenticated live database resource identity

### Identity tuple

The external inventory owns immutable values for:

- project ID and environment ID;
- provider account/project/region;
- database service/cluster ID and unique live instance/resource ID;
- endpoint identity (TLS SAN plus provider-issued resource binding, not DNS name alone);
- deployment generation and failover epoch;
- workload identity ID and approved gateway identity;
- inventory revision and status.

PostgreSQL `system_identifier`, database OID/name, server version, DNS, IP address, and caller-provided connection strings remain useful diagnostic inputs but are never the trust root.

### Per-connection verification

- The gateway obtains a fresh signed resource-identity statement from the provider control plane over authenticated TLS.
- It verifies the provider signature, issuer, audience, resource ID, endpoint identity, cluster membership, current-primary status, region, generation, and freshness.
- The gateway opens TLS to the exact endpoint and verifies certificate chain, hostname/SAN, and resource binding against that statement. Redirects, DNS changes, proxy substitutions, certificate mismatch, unexpected IP/resource, and endpoint aliases fail closed.
- The attestation binds both the stable service/cluster identity and the currently active database instance identity. A stable endpoint alias alone is insufficient.
- The DB authorization wrapper validates the resource identity statement (or a verifier-signed normalized claim) against pinned provider/verifier public keys and the attested resource/generation. A copied database-local anchor cannot satisfy this check.

### Failover semantics

A failover is a trust transition, not transparent DNS continuity:

1. Infrastructure control plane identifies the promoted resource and its authenticated provider identity.
2. Independent inventory enters `transitioning`; new dispatch permits for the old generation stop.
3. In-flight dispatch permits drain or expire under §7.
4. Inventory increments generation/failover epoch and binds the new primary resource and endpoint.
5. Verifier issues only new-generation attestations.
6. Gateway discards old connection pools and re-establishes TLS with the new resource identity.
7. A failover with ambiguous identity, stale inventory, or inconsistent provider control-plane state remains unavailable for privileged RPCs.

A standby may be pre-registered as an eligible failover resource, but cannot be treated as primary until a signed promotion event and generation transition commit.

## 5. F-04 — Verifier compromise containment and residual risk

A verifier with unilateral signing authority can mint apparently valid authorizations if compromised. The revised design does not treat verifier compromise as harmless.

### Dual independent authorization

- **Workload/resource verifier:** attests fresh provider workload identity, database resource identity, endpoint, generation, source and artifact provenance.
- **Independent policy authority:** separately evaluates operation policy, approver authorization, actor separation, environment, change window, allowlist, and execution scope. It signs a distinct authorization over the same canonical request digest.
- **Nonce/fencing authority:** independently consumes the nonce and issues a signed one-use dispatch receipt after checking both authorizations and current generation.
- DB wrappers require all three cryptographic artifacts. The verifier cannot mint the policy signature or nonce receipt; policy authority cannot forge provider workload identity; nonce authority cannot invent either authorization.

The authorities must use separate administrative boundaries, credentials, key custody and audit paths. Sharing a cloud account administrator, CI signing key, runtime identity, or mutable policy file invalidates the claimed independence.

### Containment

- Verifier signing keys are HSM/KMS non-exportable; the runtime has sign-only permission and no key-admin permission.
- The verifier cannot edit resource inventory, generation, allowed source policy, actor mappings, or DB grants.
- Key revocation and policy deny-list are checked online by nonce authority and DB wrapper trust bundle; stale cache can deny but cannot positively authorize.
- Rate limits and anomaly detection cap issuance by workload, operation, resource and execution.
- Emergency containment revokes verifier key, policy authorization key if exposed, and outstanding nonce epoch; disables dispatch; preserves audit evidence; requires two-person reactivation and full staging adversarial revalidation.
- A verifier compromise alert triggers incident response and an inventory/policy review. No fail-open fallback or long-lived emergency token exists.

### Accepted residual risk

If the provider's workload identity/control plane is compromised, or if the independent policy authority and nonce authority are also compromised, an attacker may satisfy the multiple-signature policy. The system cannot independently prove a dishonest provider's physical-resource statement. This residual risk must be explicitly accepted by Security and Infrastructure before Production. A verifier-only compromise should be insufficient to authorize a new operation under the dual-signature design.

## 6. F-05 — Linearizable generation fencing and delayed dispatch

The inventory and nonce/fencing authority must share a strongly consistent serialization domain or equivalent linearizable protocol. Eventual consistency and cache-based positive authorization are prohibited.

### State machine

- `ACTIVE(g)`: current generation g accepts new challenges and dispatch permits.
- `TRANSITIONING(g)`: no new permits for g; previously admitted permits drain or expire.
- `ACTIVE(g+1)`: new resource/generation is active; all g authorizations are permanently stale.
- `REVOKED`: no privileged dispatch.

### Linearization points

- `begin_transition(g)` atomically changes ACTIVE(g) to TRANSITIONING(g), fencing future dispatch admissions for g.
- `admit_dispatch(token, now)` atomically checks current state ACTIVE(g), token generation g, nonce consumed, receipt bindings, and deadline; records a unique dispatch lease. Exactly one lease may exist per receipt.
- A transition cannot commit to ACTIVE(g+1) until all previously admitted leases are completed or their short dispatch deadline expires and are marked terminal. This makes the lease admission the defined in-flight linearization point.
- Gateway performs the DB network write synchronously immediately after admission, with no message queue, retry queue, deferred worker, or buffering layer between admission and send.
- DB wrapper verifies the dispatch lease signature, generation, resource, request digest, and short expiry. A delayed request arriving after its lease deadline is rejected before ledger effects.
- The generation transition waits for lease drain/expiry; once g+1 is active, no new g lease can be admitted. No generation decrement or reuse is allowed.

### Delayed/ambiguous dispatch

- If a request is delayed before `admit_dispatch`, it fails once transition begins.
- If the gateway receives a lease but cannot immediately dispatch, it discards the lease; no retry with that lease is permitted.
- If dispatch is delayed past the lease deadline, the DB wrapper rejects it.
- If the request may have reached PostgreSQL but the response is lost, the gateway does not resend. It reconciles by execution ID and ledger outcome using a fresh authorization only if the operation is proven not to have taken effect.
- A transition waits for already admitted leases, but never waits indefinitely: leases have a bounded deadline, after which they are terminal and cannot be accepted by the DB.
- The exact lease deadline, clock-skew bound, drain timeout and treatment of a DB transaction already executing at transition start require Security/Infrastructure/DBA approval. The proposed lease maximum is 2 seconds; this is a design target, not a deployed setting.

## 7. F-06 — Fresh workload evidence and verified artifact provenance

### Fresh workload evidence

Each authorization challenge includes a fresh unpredictable nonce and exact gateway audience. The workload supplies a provider-signed identity document with:

- immutable workload/service principal;
- project/environment and deployment identity;
- issuer, subject, audience and issue/expiry times;
- nonce/challenge binding;
- image digest and runtime deployment ID;
- provider resource/region identity where available.

Evidence is verified online against provider trust roots and current workload inventory. Caller-provided environment variables, static API keys, service names, labels or self-signed JSON are not workload evidence. Evidence lifetime is short and bounded by the challenge.

### Artifact provenance

The artifact must be cryptographically tied to an approved build attestation, including:

- repository immutable ID and canonical repository URI;
- commit SHA and Git tree digest;
- workflow identity and protected ref/environment;
- builder identity and workflow run ID;
- artifact/image digest (not mutable tag);
- dependency/build provenance statement and signature;
- approved migration/query bundle identity and digest;
- release ID and environment promotion record.

Independent policy authority verifies provenance signature, trusted builder identity, repository allowlist, protected branch/tag, commit/tree match, artifact digest, source bundle membership, and environment promotion. A source path plus caller-supplied SHA-256 is insufficient. Provenance is bound into the canonical request digest and all authorization signatures.

No specific provenance standard or provider is selected here. Security and Infrastructure must approve a format and trusted builder roots. C575/C576 schemas and existing historical records are not rewritten; the expanded provenance is a versioned external authorization envelope.

## 8. F-07 — Typed canonical request and signed consume receipt

### Canonical request encoding

Use deterministic CBOR under an approved canonicalization profile (RFC 8949 deterministic encoding) with a versioned, typed schema. Do not sign arbitrary JSON serialization or delimiter-concatenated strings.

Rules:

- Each operation has a closed schema with exact required keys and typed values; unknown fields are rejected.
- UUIDs use 16-byte binary representation; enums use fixed registered integer/string codes; integers use bounded unsigned/signed types; timestamps use integer UTC epoch units; hashes use fixed-length byte strings; booleans are CBOR booleans.
- Source identity is a typed tuple of repository ID, commit SHA, tree digest, path, source blob SHA-256 and bundle digest. Strings must be UTF-8, normalized according to a documented policy, and length-bounded.
- Arbitrary JSON parameters are prohibited in authorization-critical fields. Where a legacy `jsonb` field is unavoidable, validate against a closed schema, reject duplicate keys and non-finite numbers, normalize object key ordering and numeric representation, and include the canonical typed representation in the digest.
- Domain-separate by protocol/version, project, environment, RPC operation and audience. Bind all operation parameters, execution ID, record ID, approval ID, source identity, artifact provenance digest, actor principal, database resource, endpoint identity, generation, inventory revision, nonce, `jti`, expiry and policy decision ID.
- Verify that re-encoding the decoded request produces byte-for-byte identical canonical bytes. Reject noncanonical or ambiguous encodings.

### Consume receipt

The nonce authority emits a signed receipt only after a linearizable compare-and-set succeeds. It binds:

- issuer/key ID, receipt version, exact gateway/DB-wrapper audience;
- nonce ID and attestation `jti`;
- request digest and operation ID;
- project/environment/database resource/endpoint/generation;
- execution, record and approval IDs where applicable;
- source and artifact provenance digests;
- workload principal and policy decision ID;
- nonce-consumed timestamp, dispatch lease ID and exclusive dispatch deadline;
- inventory revision and nonce epoch.

Gateway and DB wrapper independently validate signature algorithm/key ID, issuer, audience, expiry, key revocation, exact request digest, resource, generation, operation, execution/source/artifact claims, and dispatch lease. Unknown keys, unknown claims marked critical, invalid encodings, mismatched claims, stale inventory or expired leases fail closed. A receipt is not accepted merely because the gateway says it verified it.

## 9. F-08 — Nonce anti-rollback recovery and audit outage

### Nonce-store durability and anti-rollback

- Use a strongly consistent consensus-backed store with linearizable conditional writes, quorum durability, authenticated replication, immutable sequence/high-water index and unique nonce/JTI constraints.
- Every issue, consume, revoke, generation transition and dispatch lease is committed to a monotonic log with a signed checkpoint.
- Independently publish checkpoint/high-water digests to a separately administered witness/audit domain. The witness must not be restored from the same backup set as the nonce store.
- A backup restore must compare restored log index/hash, nonce epoch, and high-water checkpoint against the independent witness before serving traffic.
- If any checkpoint is missing, lower, forked, stale or unverifiable, the store remains unavailable for authorization. Recovery requires an independently witnessed new nonce epoch and generation, revocation of all outstanding attestations/receipts, and full audit reconciliation.
- Never restore old `issued` nonce rows as authoritative, rewind generation, or reuse a nonce/JTI. A restored backup is a data-recovery source, not an authorization source.
- Multi-region failover requires consensus quorum and witness validation. A minority partition cannot issue/consume receipts.

### Audit sink outage

- Attestation issuance and nonce consume/dispatch must be durably audited before the gateway sends a privileged RPC.
- The nonce authority atomically appends the consume event to a durable, append-only replicated audit outbox in the same transaction as nonce consumption and dispatch lease creation.
- The gateway proceeds only after receiving a signed receipt proving both the consume and audit-outbox commit.
- If the durable outbox or its independent witness is unavailable, full, corrupt, or cannot confirm commit, no dispatch is admitted. Do not silently buffer in process memory or downgrade to ordinary logs.
- External SIEM delivery may be delayed only while the durable outbox remains within an approved bounded backlog/retention limit and the independent witness confirms continuity. Once the limit is exceeded or continuity is uncertain, privileged dispatch stops.
- Audit recovery verifies sequence continuity and all missing events before re-enable. Audit events are redacted; no bearer token, private signing key, provider credential or private member reflection is logged.

## 10. Complete nine-RPC authorization matrix

The operation parameters below are the current C593 fixture signatures. The v2 authorization wrapper binds the full typed parameter set plus the external source/artifact context. Existing source identity `{path, sha256}` remains a compatibility field; external provenance adds immutable repository/commit/tree/artifact/bundle fields without rewriting C575/C576 records.

| Privileged RPC | Actor | Exact operation parameters | Required source/artifact binding | Expected failure behavior |
|---|---|---|---|---|
| `approve_execution` | Approver | `approval_id, record_id, execution_id, source_identity` | Immutable approved source tuple, release provenance, policy/change approval | Deny before approval insert on wrong approver, duplicate IDs, stale generation, missing policy signature or invalid source |
| `reserve_execution` | Runner | `approval_id, record_id, execution_id, source_identity` | Exact equality to approved source and same artifact digest as approval | Deny before approval consumption/execution insert on replay, mismatch, wrong runner, stale generation or invalid receipt |
| `record_effect_commit_marker` | Runner owning active execution | `execution_id, source_identity` | Exact source/artifact identity persisted at reservation; active runner identity | Deny before marker insert on wrong runner, non-running execution, source substitution or missing receipt |
| `capture_snapshot` | Observer independent of approver/runner | `execution_id, phase, query_id` | Registered immutable observation bundle/query digest plus same execution artifact provenance | Deny before dynamic SQL/snapshot insert on wrong observer, unregistered query, query/bundle substitution, stale resource or invalid receipt |
| `start_execution` | Runner owning reserved execution | `execution_id` | Source/artifact digest inherited from reservation; pre-snapshot query bundle identity | Deny before status transition on missing pre-snapshot, wrong runner, stale generation or invalid receipt |
| `heartbeat_execution` | Runner owning running execution | `execution_id` | Active reservation's exact source/artifact digest | Deny before heartbeat update on wrong runner, non-running state, expired dispatch lease or invalid receipt |
| `finalize_execution` | Runner owning running execution | `execution_id, outcome, outcome_detail` | Same source/artifact identity; pre/post snapshots and registered query bundle; commit marker | Deny before terminal update on missing/mismatched evidence, unsupported outcome, wrong runner, stale generation or invalid receipt |
| `recover_stale_executions` | Recovery | `stale_after interval` | Approved recovery policy, target resource/generation, bounded stale threshold; affected execution IDs derived server-side | Deny before any row update on non-recovery actor, invalid threshold, stale generation, missing policy or invalid receipt |
| `record_verification` | Independent verifier | `execution_id, verdict, evidence` | Independent verification report bound to terminal execution, artifact/source digests and snapshot/ledger evidence | Deny before verification insert on nonterminal execution, verifier overlap with approver/runner, invalid evidence or invalid receipt |

Additional matrix invariants:

- All nine operations require independent provider workload evidence, resource/endpoint identity, current generation, source/artifact provenance, policy authorization and a signed one-use consume/dispatch receipt.
- Every receipt is one operation, one execution scope, one target resource and one dispatch.
- The verifier may not substitute for the approver; the runner may not create observer evidence; the observer may not execute migrations; recovery may not approve or finalize; and the verifier cannot mutate execution status.
- The recovery RPC's broad interval signature is not itself an authorization scope: the signed request digest binds the interval, target, policy and execution set derived at dispatch. If the exact affected set cannot be frozen and audited, recovery is denied.
- Unknown/new privileged RPCs are deny-by-default and require a matrix row, wrapper, direct-call test and CI inventory assertion before release.

## 11. Adversarial tests and zero-side-effect evidence contract

### Executable test added in this change

Added `scripts/fixtures/test-migration-execution-ledger-c600.sql` and wired it into `scripts/test-migration-execution-ledger-postgres16.sh`.

The test creates a disposable untrusted role, grants schema name resolution but no function execution, verifies that all nine RPCs lack EXECUTE privilege, attempts each direct invocation, requires PostgreSQL `insufficient_privilege`, and compares before/after counts for approvals, executions, snapshots, commit markers and verification events. It emits:

`C600_NINE_RPC_UNAUTHORIZED_DIRECT_CALLS_DENIED_ZERO_SIDE_EFFECTS`

This is a real disposable SQL privilege-boundary regression. It does **not** prove provider identity, signed authorization, a gateway, or Production role configuration.

### Required additional adversarial matrix before implementation acceptance

| Attack | Test and required zero-side-effect assertion |
|---|---|
| Legacy RPC direct call | Each of nine legacy signatures called by anon/authenticated/app/gateway actor logins; all denied; no ledger row changes |
| Missing/invalid receipt | Each v2 wrapper called with no receipt, random receipt, altered signature and expired receipt; no ledger or external effects |
| Wrong actor | Every actor attempts all operations outside its row; denied before writes |
| Actor impersonation | `SET ROLE`, membership escalation, shared pool identity swap, caller-supplied actor field; all denied |
| Verifier compromise | Simulate verifier signing key disclosure but no policy signature; no dispatch and no DB mutation |
| Policy compromise | Simulate policy signature without fresh provider identity; no dispatch |
| Resource/endpoint substitution | Valid evidence for DB-A sent to DB-B, DNS alias changed, certificate SAN mismatch, endpoint redirect, standby not promoted; no RPC |
| Failover race | Old generation token while transition begins; no new dispatch lease; no stale DB call |
| Delayed dispatch | Lease expires or generation transition drains before network write; DB rejects, no ledger effects |
| Concurrent generation fence | Race generation transition and dispatch across regions; serializable result, exactly one legal ordering, no old-generation admission after transition linearizes |
| Workload evidence replay | Reuse challenge, wrong audience, stale provider identity, altered image digest; denied |
| Artifact substitution | Change repository, commit, tree, builder, workflow run, image digest, bundle digest or release promotion; denied |
| Canonical encoding attack | Duplicate JSON keys, alternate integer/UUID encodings, noncanonical CBOR, Unicode confusables, unknown fields, type confusion; denied |
| Consume receipt substitution | Change operation, parameters, execution, resource, generation, source, artifact, audience or dispatch deadline; DB signature/binding check rejects |
| Nonce rollback | Restore stale backup, fork log, lose witness, replay old epoch; nonce authority remains offline and all old receipts rejected |
| Audit outage | Sink/outbox/witness unavailable or backlog limit exceeded; no dispatch; no DB mutation |
| Ambiguous outcome | Lose response after dispatch; same receipt cannot be retried; reconcile execution ID before fresh authorization |
| Key rotation/revocation | Race revoke with consume/dispatch; semantics follow approved linearization point; revoked key cannot authorize later calls |

Each test must snapshot all relevant DB tables, effect tables, RPC invocation counters, nonce-store sequence, dispatch ledger and audit outbox before/after. For a rejected request, every protected side-effect count/hash must remain identical. For a positive request, exactly one ledger operation, one consumed nonce, one dispatch lease and one correlated audit record are permitted. The external verifier/nonce tests require multiple independent service replicas and two distinct disposable DB resources; a single-process mock is insufficient.

## 12. Approvals and explicit dependencies

| Owner | Required approval / evidence | Status |
|---|---|---|
| Security | Threat model, dual-authority policy, trust roots, signature formats, residual risk, canonical encoding, nonce/revocation semantics, adversarial acceptance | **OUTSTANDING** |
| Infrastructure | Provider workload identity source, immutable resource/endpoint identity, failover API, independent verifier/policy/nonce deployment, quorum/witness, network boundary | **OUTSTANDING** |
| DBA | Exact nine-RPC catalog/grant inventory, v2 wrapper strategy, private internal function ownership, DB signature verification mechanism, principal mapping, connection restrictions | **OUTSTANDING** |
| Operations | Lease/drain SLO, outage behavior, audit retention/backlog, emergency disable/re-enable, failover and restore runbooks | **OUTSTANDING** |

No human approval is inferred from PR creation, CI success, or this architecture document.

## 13. Implementation sequence

1. Attach the original C599 review artifact and independently reconcile each finding with this document.
2. Security approves the trust model, dual-signature design, canonical request schema, threat boundary and residual risk.
3. Infrastructure identifies provider-signed workload and live database resource evidence, endpoint/failover APIs, independent service domains and quorum/witness capabilities.
4. DBA produces a catalog-derived list of the nine exact function signatures, owners, grants, memberships, alternate entry points and current SECURITY DEFINER properties.
5. Implement a disposable provider adapter, independent verifier, policy authority, nonce/fencing service, witness and durable audit outbox; no Production credentials.
6. Implement gateway and nine versioned authorization wrappers in disposable PostgreSQL. Revoke direct access to legacy signatures from every runtime login; wrappers validate all signatures and typed request bindings before calling private internal operations.
7. Run all tests in §11, including cross-replica replay/fence races, physical clone on a different resource, failover and nonce-store anti-rollback. Inspect actual PostgreSQL and trust-service logs.
8. Enforce in staging with separate actor principals; prove outage, compromise containment, revocation, delayed dispatch and rollback.
9. Obtain written Security, Infrastructure, DBA and Operations approval plus explicit Production change authorization before any Production action.
10. Roll out gradually with observed provider identity, generation, nonce, dispatch, DB and audit evidence. Any bypass, mismatch, audit gap or uncertain outcome stops privileged operations.

## 14. Rollback

Rollback disables privileged v2 dispatch and revokes gateway actor login access under an approved DBA runbook. It never restores direct application access to legacy RPCs, weakens signature checks, accepts stale receipts, rewinds generation, restores old nonce state as authoritative, or bypasses audit. Ledger reads and unrelated application paths may continue only where independently safe. Re-enable requires healthy trust authorities, fresh generation/nonce epoch, key status, audit continuity, staging adversarial tests and all required human approvals.

## 15. Validation and honest status

### Exact-head CI evidence for implementation commit

The implementation/test commit `c7fcecc2a2a3abd9b799504ef38f163e9a5a0f0f` completed both fresh workflow runs:

- Branch push run #2365: `46086529718`, **13/13 jobs successful**.
- PR validation run #2366: `46086534720`, **13/13 jobs successful**.
- PostgreSQL 16 branch job: `140797361956`, successful.
- PostgreSQL 16 PR job: `140797383916`, successful.
- Validation branch job: `140797361855`, successful.
- Validation PR job: `140797383389`, successful.

The actual PostgreSQL logs for both runs contain `C600_NINE_RPC_UNAUTHORIZED_DIRECT_CALLS_DENIED_ZERO_SIDE_EFFECTS`, the inherited C593/C595 manifest/identity assertions, C585 one-winner replay marker, and C578 PostgreSQL 16 remediation PASS marker. The expected cancellation/replay SQL errors in the concurrency test are asserted test behavior, not CI failures.

The validation logs show successful TypeScript checks, Next.js production builds, Cloudflare/OpenNext packaging, and zero dependency advisories. This validates the current source and disposable test harness only; it does not validate the proposed external trust services or Production authorization.

- C600 SQL test: **IMPLEMENTED**; fresh PostgreSQL 16 exact-head CI is required before it is called PASS.
- C598 branch/PR CI: predecessor evidence only; not evidence for this new commit.
- External verifier, policy authority, gateway, nonce/fencing service, resource identity adapter, DB cryptographic wrappers and key custody: **NOT IMPLEMENTED**.
- Physical-clone protection in Production: **NOT ESTABLISHED**.
- Security/Infrastructure/DBA/Operations approvals: **OUTSTANDING**.
- Production changes: **NONE**.
- Historical migrations: must remain unchanged; this branch changes no `supabase/migrations` files.

## 16. Changed files

1. `docs/C600_EXTERNAL_TRUST_FINDINGS_REMEDIATION.md` — this architecture, RPC matrix, threat cases and approval handoff.
2. `scripts/fixtures/test-migration-execution-ledger-c600.sql` — nine direct unauthorized invocation tests and zero-side-effect assertions.
3. `scripts/test-migration-execution-ledger-postgres16.sh` — invokes the new C600 fixture test in the existing PostgreSQL 16 suite.

PR #37 remains a separate predecessor. PR #36 is not changed, merged or closed by this work.
