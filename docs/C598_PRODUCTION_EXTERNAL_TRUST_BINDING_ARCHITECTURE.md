# C598 — Production external trust-binding architecture specification

**Status:** Architecture proposal only. Physical-clone protection is **NOT ESTABLISHED** and this document does not implement or enable it. No trust provider, credentials, database roles, Production resources, trust roots, migrations, or scheduler settings are selected or changed.

- Repository: `ADRN-9/deedlight`
- Specification baseline: `f26a7dfea5c8d1342a31952363476127d97b0607` (PR #36 HEAD at assignment start)
- Scope: Production database identity and workload attestation for the execution-ledger privileged RPC boundary.
- Existing C593–C597 evidence is retained as database-local identity-consistency evidence only. It is not independent proof of physical database identity or workload provenance.

## 1. Executive security position

The current ledger checks compare identity values observed by PostgreSQL and recorded in ledger state. Those checks are valuable against accidental target substitution and stale/inconsistent database state. They do not establish an independent trust anchor: a physical clone can copy database-resident identity values, manifests, approvals, nonce rows, and ledger state. Equality between copied values is not proof that the caller reached the intended Production database resource.

The proposed design adds an independently operated trust authority and a narrowly scoped privileged-RPC gateway. The gateway is the only application path allowed to invoke the nine privileged ledger RPCs. It verifies a short-lived, verifier-signed, operation-specific attestation, atomically consumes its nonce at the independent authority, pins the target to a separately inventoried database resource, and then invokes exactly one RPC through a dedicated database principal. Direct application-role execution of those RPCs is denied.

**No offline or database-local fallback is permitted.** If identity proof, verifier connectivity, nonce consumption, signature validation, target binding, deployment-generation validation, or authorization is unavailable or ambiguous, the privileged operation fails closed.

This is a proposed trust boundary, not a claim that DeedLight currently has an external verifier, gateway, provider workload identity, or physical-clone protection.

## 2. Threat model and assurance boundary

### In-scope threats

- A byte-for-byte database clone carries copied `system_identifier`, database OIDs, ledger rows, manifests, approvals, execution records, and local nonce state.
- A snapshot or restored database is started under a different managed database resource.
- An old valid attestation is replayed, including concurrently against original and cloned targets.
- An attestation is substituted across projects, environments, database resources, deployment generations, operations, execution IDs, or source identities.
- A workload from staging, a developer environment, or another project attempts a Production ledger operation.
- A stale deployment continues using an old generation after rotation, rollback, restore, or redeployment.
- The verifier is unreachable, compromised, misconfigured, or has stale/revoked signing keys.
- A gateway, application role, database role, or alternate RPC route attempts to bypass verification.
- Provider response loss leaves the caller uncertain whether the nonce was consumed or the RPC executed.

### Explicit limits

This design can distinguish a copied database running as a different independently identified resource, and can reject stale or replayed attestations through an external one-use nonce authority. It cannot by itself distinguish malicious code or a copied database process executing inside the exact same trusted infrastructure identity if the infrastructure authority falsely attests that resource. That residual risk depends on provider isolation, host/control-plane integrity, and human-controlled trust-root governance.

The design does not prove that SQL text was semantically executed merely because a runner reports a source digest. Source identity is a binding input and audit label, not independent execution proof. C585's execution-evidence limitations remain.

## 3. Trust architecture

### Components and trust separation

1. **Deployment inventory (independent control plane).** An authoritative, access-controlled registry records the immutable project ID, environment, unique managed database resource ID, deployment generation, approved workload identities, allowed source identities, and active/revoked status. It is not stored solely inside the database being protected.
2. **Workload identity adapter.** A provider-specific adapter obtains a signed workload identity document from the hosting platform's native identity mechanism. The adapter is replaceable; the protocol contract is provider-neutral. No static secret or self-asserted environment variable is accepted as workload identity.
3. **Independent attestation verifier/issuer.** A separately deployed service validates the workload identity document, queries the deployment inventory and independent infrastructure control plane, issues a fresh challenge, validates the complete request, and signs a short-lived attestation. It is outside the application deployment and outside the database trust domain.
4. **Privileged ledger RPC gateway.** A narrowly scoped service validates the attestation, asks the verifier to atomically consume its nonce for the exact request, resolves the registered target resource, and forwards exactly one permitted ledger RPC. It does not accept arbitrary SQL or arbitrary RPC names.
5. **Production PostgreSQL database.** Retains C593–C597 identity checks and ledger semantics. Only the gateway's dedicated database principal can execute the privileged ledger RPCs. Application/browser roles cannot call them directly.
6. **Audit sink.** An independently retained append-only security audit stream records issuance, verification, nonce consumption, revocation, denied attempts, and RPC outcomes without storing bearer tokens, signing secrets, or sensitive member data.

The verifier and its inventory must not be deployed as a sidecar in the same failure/credential domain as the application or database. A second container in the same deployment is not an independent trust anchor.

### Logical request flow

```text
Application workload
  | provider-signed workload identity + requested RPC context
  v
Independent verifier <----> deployment inventory + infrastructure control plane
  | challenge (fresh random nonce, one-use, short expiry)
  v
Application obtains signed workload identity evidence
  | challenge + identity evidence + exact operation/source context
  v
Independent verifier
  | validates identity, environment, resource, generation, source, policy
  | issues verifier-signed operation-specific attestation
  v
Privileged RPC gateway
  | validates signature, claims, expiry, target, exact RPC
  | atomically consumes nonce at verifier (compare-and-set)
  | resolves/pins registered database resource
  v
Production PostgreSQL (gateway-only DB principal)
  | executes one allowlisted privileged RPC
  v
Gateway returns result; independent audit sink records outcome
```

If the verifier or nonce authority cannot be reached, the gateway must not call PostgreSQL. A timeout after nonce consumption is an ambiguous outcome: the same attestation is never reused. The caller obtains a new challenge and follows the ledger's existing execution-state/reconciliation rules; it must not blindly repeat a potentially completed side effect.

## 4. Unique resource and environment identity

### Canonical deployment binding

The deployment inventory must define a tuple with independently provisioned values:

- `project_id`: immutable DeedLight project identifier, not a display name.
- `environment_id`: immutable environment identifier (for example, Production), not a caller-provided string alone.
- `database_resource_id`: globally unique managed database resource identifier from the infrastructure control plane; not `system_identifier`, database name, host name, DNS name, or database OID.
- `deployment_generation`: monotonically increasing generation maintained outside PostgreSQL. Increment for database replacement/restore/clone, environment reassignment, trusted workload replacement, trust policy change, or other event defined by Security and DBA.
- `workload_identity_id`: immutable identity of the authorized workload/deployment principal.
- `source_identity`: canonical source release identity, including immutable repository identity, commit SHA, and the exact approved migration/query bundle identity where relevant.
- `inventory_version`: version of the independent binding record used during attestation.

The inventory must enforce uniqueness of `database_resource_id` and prohibit one resource from being concurrently registered as two environments. A clone receives a distinct resource ID and must not inherit Production's registration. Environment labels, DB-local rows, DNS aliases, and copied configuration files are not authoritative.

### Generation lifecycle

Generation is an external monotonic fencing value, not a value read from a database row and trusted on its own. Restore, clone, replacement, failover where identity changes, and rollback to a prior deployment require an explicit inventory transition. Old generations are revoked before the new generation is activated. A rollback is a new generation, not a decrement or reuse of a prior generation.

The verifier checks current generation against the authoritative inventory for every attestation and again when consuming the nonce. It rejects any generation that is not exactly current.

## 5. Attestation contract

### Required claims

Use a canonical, versioned signed payload (JWS or COSE may be selected only after Security approval). The algorithm must be allowlisted; `none`, algorithm confusion, untrusted key URLs, caller-supplied key material, and implicit algorithm negotiation are prohibited.

Each attestation must contain and cryptographically bind:

| Claim | Requirement |
|---|---|
| `iss` | Exact independent verifier issuer identity |
| `aud` | Exact privileged ledger RPC gateway audience |
| `project_id` | Immutable DeedLight project identifier |
| `environment_id` | Immutable environment identifier |
| `database_resource_id` | Unique infrastructure resource ID |
| `deployment_generation` | Current external monotonic generation |
| `operation` | Exact one-RPC operation name / allowlisted operation ID |
| `execution_id` | Exact ledger execution UUID |
| `source_identity` | Canonical immutable source identity and approved digest |
| `workload_identity_id` | Verified workload principal |
| `nonce` | At least 256 bits of CSPRNG entropy, issued by the independent nonce authority |
| `jti` | Unique attestation identifier |
| `iat`, `nbf`, `exp` | Issued/not-before/expiry timestamps |
| `inventory_version` | Exact independent inventory revision |
| `request_digest` | Digest of canonical request parameters excluding secrets |

The token must be one-operation, one-execution, one-target, one-generation, one-audience, one-use. A token cannot authorize a sequence of RPCs. A distinct nonce and attestation are required for each privileged RPC invocation.

### Lifetime and clock policy

The target lifetime is at most 60 seconds from issuance, with a shorter lifetime preferred after clock-skew and operational measurements. The maximum is a policy ceiling, not a guarantee that a 60-second token remains acceptable. The verifier and gateway must use synchronized trusted clocks, reject excessive skew, and fail closed when time health is uncertain. `exp` is exclusive; expiry is checked at both gateway validation and nonce consumption.

### Canonicalization and signature verification

- Define a single canonical serialization and version it.
- Reject duplicate JSON keys, unknown critical claims, missing required claims, malformed identifiers, invalid UTF-8, noncanonical encodings, and unsupported versions.
- Verify the signature against a pinned verifier key set obtained through an authenticated, independently controlled channel.
- Enforce exact `iss`, `aud`, operation, resource, environment, generation, source and request digest equality.
- Never accept a signature key ID as authority to fetch a key from an arbitrary URL.
- Do not log raw bearer attestations or private identity documents.

## 6. Atomic external nonce consumption and replay rejection

The nonce authority maintains a strongly consistent, durable, independently protected record keyed by `(issuer_id, nonce)` and `jti`. It exposes an atomic compare-and-set operation:

```text
consume(issuer, nonce, jti, request_digest, resource_id, generation, operation, now):
  BEGIN SERIALIZABLE / equivalent atomic transaction
    require nonce exists
    require state = issued
    require stored binding equals every supplied binding
    require now < expires_at
    require issuer/key/generation/resource are active
    update state = consumed, consumed_at = now, consume_request_digest = request_digest
      only where state = issued and expires_at > now
    require exactly one row updated
  COMMIT
  return signed consume receipt
```

The store must provide a globally atomic winner across verifier replicas and regions. Eventual consistency, cache-only replay detection, per-process memory, or PostgreSQL-local nonce rows are insufficient. A duplicate or concurrent consume returns a generic replay/consumed denial and never a second success. The consume receipt is signed and bound to the exact request, gateway audience, database resource, generation, operation, execution ID, source identity, and attestation `jti`.

The gateway forwards the RPC only after a successful consume receipt. A nonce is never restored to `issued`, including on timeout or downstream database error. An unconsumed challenge expires and is garbage-collected only after a retention period adequate for audit. Consumed records or cryptographic tombstones must be retained long enough to cover the maximum replay horizon and incident investigation requirements.

**Cross-system atomicity:** nonce consumption and a PostgreSQL transaction cannot be one atomic transaction. Therefore the protocol is deliberately at-most-once for the attestation, not exactly-once for the entire distributed request. If the gateway crashes after consumption but before the RPC, the caller requests a new attestation after checking ledger state. If it crashes after the RPC but before returning the response, it must reconcile by `execution_id` and existing ledger state before any retry. The gateway must not reuse a consumed nonce to make retries convenient.

## 7. Verifier deployment, signing-key custody, rotation and revocation

### Independent deployment requirements

- Separate cloud account/project or equivalent independently administered security boundary from both application and database.
- Separate deployment pipeline, administrators, service identity, network policy, logging sink, and break-glass procedure.
- No shared application runtime secrets, database service-role credential, or mutable deployment volume.
- Private authenticated ingress from the gateway; outbound access restricted to approved identity/control-plane APIs and audit sink.
- Explicit health, availability, clock, inventory freshness, and signing-key status checks.
- No ability for application operators to alter verifier trust policy or signing keys through the application deployment.

### Signing-key custody

- Private signing keys generated and retained in an approved HSM/KMS or equivalent non-exportable key custody service.
- No private signing key in repository, CI variables readable by application jobs, environment files, database, browser bundle, logs, or developer workstation.
- Verifier service receives narrowly scoped sign permission; it cannot export private key material.
- Separate key-administration and verifier-runtime permissions; two-person approval for production key creation, activation, rotation, emergency revocation, and recovery.
- Public verification keys distributed through a pinned trust bundle with explicit key IDs, validity intervals, and revocation status.

### Rotation and revocation

- Planned rotation: create new key, publish/approve public key, run overlap verification tests, switch issuer to new key, observe, then retire old key after the maximum attestation lifetime plus clock-skew allowance.
- Emergency rotation: immediately revoke the compromised key in the independent trust registry, invalidate all outstanding attestations, and reject the key at every gateway/verifier replica. Do not wait for token expiry.
- Revocation state must be checked online at consume time; stale local caches cannot authorize after revocation. Cache may only cause denial if stale.
- Maintain a tested break-glass process to disable all privileged ledger RPCs while key state is repaired. No emergency bypass token or static fallback key.

## 8. Enforcement before every privileged ledger RPC

The security invariant is: **no privileged ledger RPC executes unless the independent verifier has authorized and consumed a fresh attestation for that exact RPC invocation.**

The proposed gateway is the enforcement point:

1. Inventory all nine C593 privileged RPCs from the exact source and migration definitions. Treat this as an explicit allowlist; unknown or newly added privileged RPCs are denied by default.
2. Route every application call to those RPCs through the gateway.
3. Revoke direct `EXECUTE` from browser roles, anon/authenticated roles, application service roles, and all other non-gateway principals. Grant only the minimum RPC privileges to a dedicated gateway database role.
4. Verify database `session_user` is the dedicated gateway principal at each privileged function boundary where feasible; keep SECURITY DEFINER ownership and search-path hardening unchanged.
5. Gateway verifies one attestation and consumes its nonce immediately before forwarding the exact allowlisted RPC. It pins the connection to the registered database resource; it cannot accept caller-selected connection strings.
6. Bind the signed request digest to canonical RPC parameters. No parameter rewriting or operation aliasing is allowed after attestation.
7. Enforce the same boundary for reserve, commit-marker, finalize, stale recovery, and every other privileged RPC in the exact nine-function inventory.
8. Deny direct database network access from ordinary application workloads where the infrastructure model supports it. The gateway is the only workload with network and database-role authority for these functions.
9. Audit all grants, ownership, SECURITY DEFINER functions, alternate RPC endpoints, scheduled jobs, migration scripts, admin tools, and service-role paths for bypasses.

The exact nine function names and current privilege map must be generated from source/catalog evidence during implementation planning; this specification intentionally does not invent names. Any additional privileged ledger function discovered must be included before rollout or remain inaccessible.

**Important:** An application-side HTTP check followed by a direct database RPC is not sufficient. Nor is a caller-settable PostgreSQL GUC, a copied database-local permit row, or a signed token checked only once at application login. Enforcement must be unavoidable for every privileged invocation.

## 9. Adversarial test plan

All tests must run in disposable environments before any Production approval. Use independent verifier state and two physically distinct disposable database resources where relevant. A green unit test without a real cross-instance atomic nonce test is insufficient.

| Test | Adversarial setup | Required outcome / evidence |
|---|---|---|
| Physical clone | Copy a database snapshot including system identifier, DB OIDs, ledger, manifests and local rows to a new resource ID | Clone denied because independent inventory maps its resource ID/generation differently; zero privileged RPC side effects |
| Copied local identity | Preserve every C593 database-local identity value on clone | Still denied; proves local identity equality is not the trust root |
| Wrong project/environment | Valid staging workload and token presented for Production or another project | Denied with no DB connection/RPC |
| Wrong DB resource | Valid token for DB-A sent to DB-B | Denied before RPC; target cannot be caller-overridden |
| Stale generation | Attestation issued for generation N, inventory advanced to N+1 before consume | Denied at consume; N cannot be restored |
| Expired/not-yet-valid | Expired token and future `nbf` token | Denied; no clock-skew fallback |
| Replay | Reuse a consumed token/nonce sequentially | Second request denied as replay |
| Concurrent replay | Race same attestation against two gateway replicas and two DB resources | Exactly one external consume succeeds; at most one RPC is forwarded |
| Nonce substitution | Valid signature with another nonce, nonce bound to another request, or malformed nonce | Signature/binding validation fails; no RPC |
| Operation substitution | Attestation for reserve used for finalize/commit-marker/recovery | Denied; operation and parameter digest mismatch |
| Execution substitution | Attestation for execution A used for B | Denied; no side effects on either execution |
| Source substitution | Replace repository, commit, migration/query bundle digest or source identity | Denied by inventory/policy binding |
| Workload substitution | Use developer, staging, stale, or unauthorized workload identity | Denied by verifier |
| Signature/key attacks | Wrong issuer/audience, unknown/revoked key, altered claims, algorithm confusion, duplicate JSON keys | Denied; no fail-open behavior |
| Verifier outage | Timeout, DNS failure, 5xx, unavailable signing/nonce store | All privileged RPCs denied; ordinary unrelated nonprivileged app behavior remains governed separately |
| Ambiguous consume | Verifier consumes nonce but response is lost | Same token denied on retry; new challenge plus ledger reconciliation required |
| Gateway bypass | Call RPC directly as anon/authenticated/service role; attempt alternate URL/connection | Database denies direct execute; no side effects |
| Gateway credential misuse | Gateway role attempts arbitrary SQL, schema writes, unrelated functions or privilege escalation | Denied by least privilege; only allowlisted RPC execution possible |
| Inventory outage/staleness | Control-plane lookup unavailable or inventory revision stale | Denied; no cached positive authorization |
| Revocation race | Revoke key/generation while requests are in flight | Consume after revocation denied; bounded and specified semantics for already-consumed in-flight request approved by Security |
| Clone in same resource boundary | Simulate duplicate process/restore that falsely presents same infrastructure identity | Documented residual; must be prevented/detected by provider isolation/control-plane attestation and human review, not claimed solved by DB tests |

Every negative test must assert zero database side effects, not merely an HTTP error. Positive tests must prove exactly one authorized invocation and emit redacted audit correlation IDs. CI must fail if any allowlisted privileged RPC is missing a test or any new privileged RPC lacks an explicit policy entry.

## 10. Human decisions and approvals required

No implementation provider, credential, trust root, or Production role change is authorized by this document. The following approvals are mandatory and must be recorded before implementation:

### Security approval

- Approve threat model, assurance boundary, residual risks and the meaning of “physical-clone protection.”
- Approve attestation format, canonicalization, claims, lifetime, audience, signature algorithms, verifier trust anchors, key custody, rotation/revocation and emergency shutdown.
- Approve independent verifier administrative boundary and two-person control model.
- Approve nonce consistency guarantees, retention, replay semantics and audit retention.
- Approve gateway bypass threat analysis and acceptance of the provider/host trust dependency.
- Approve all adversarial tests and production acceptance gates.

### Infrastructure approval

- Select the hosting provider identity mechanism and immutable resource-ID source only after review.
- Approve separate verifier deployment/account/project, private network routes, DNS/TLS, high availability, monitoring, time synchronization, KMS/HSM integration and disaster recovery.
- Approve deployment-generation lifecycle and atomic inventory updates for clone, restore, replacement, failover, rollback and decommissioning.
- Approve gateway placement, scaling, network isolation, database endpoint pinning and incident response.
- Confirm the infrastructure provider's guarantee that resource IDs and workload identity assertions cannot be self-asserted by the application workload.

### DBA / Database Security approval

- Inventory the exact nine privileged RPCs, all alternate execution paths and current grants/owners.
- Approve dedicated gateway principal, least-privilege grants, direct EXECUTE revocations, connection policy and session identity checks.
- Approve how gateway-only enforcement is preserved through migrations, Supabase role changes, admin workflows and future RPC additions.
- Approve audit queries and evidence capture without exposing private member data.
- Confirm no historical migration is rewritten and no normal Production `supabase db push` occurs before the separate migration-history reconciliation gate.

### Product / Operations approval

- Approve maintenance window, user-impact expectations, alert routing, incident ownership, kill-switch semantics and rollback.
- Approve operational readiness and support procedures for fail-closed verifier outages.
- Confirm no user-facing feature or outbound delivery scheduler depends on a bypass or weaker trust mode.

## 11. Implementation sequence and gates

1. **Discovery only:** inventory nine RPC definitions, grants, roles, application call sites, Supabase API exposure, direct DB paths, infrastructure resource identifiers, and current deployment topology. Produce a signed-off data-flow and bypass map. No changes to Production.
2. **Security design approval:** agree threat model, residual risk, token schema, key algorithm, lifetime, nonce semantics, inventory ownership and verifier independence.
3. **Infrastructure design approval:** choose provider adapter and independent deployment boundary; establish non-Production inventory and workload identity proof.
4. **Disposable verifier prototype:** implement challenge issuance, identity validation, signed attestation, online revocation and globally atomic nonce consume in a non-Production environment. Do not use Production credentials or trust roots.
5. **Gateway prototype:** implement exact allowlist, target pinning, parameter digest, one-RPC token, dedicated test DB principal, strict timeouts and audit events. No arbitrary SQL.
6. **Database enforcement rehearsal:** in disposable PostgreSQL, prove all nine RPCs reject direct calls and accept only gateway-mediated requests. Preserve C575/C576 contracts and all historical migration files. Add automated grant/function inventory verifiers.
7. **Adversarial integration:** execute all tests in §9, including cross-replica concurrent replay, cloned DB resource, stale generation, verifier outage and ambiguous response. Inspect actual PostgreSQL logs and external verifier audit records.
8. **Staging shadow mode:** collect identity and policy decisions without allowing a shadow decision to authorize Production. Compare observed resource/generation/source values; resolve mismatches.
9. **Staging enforcement:** enable gateway-only privileged calls in staging, run full authenticated/unauthenticated regressions, exercise verifier outage and key revocation, and demonstrate rollback.
10. **Production change plan:** only after all human approvals, exact-head CI, staging acceptance, change window and credential handling approval. Production rollout is a separate task and is not authorized here.
11. **Gradual Production activation:** canary a narrow workload and operation set, then all nine RPCs; observe denials, latency, verifier health, nonce consumption and audit reconciliation. Any bypass or mismatch halts rollout.
12. **Closeout:** attach exact commit, approvals, provider control-plane evidence, verifier key lifecycle evidence, database grants, gateway logs, PostgreSQL logs, adversarial results and rollback rehearsal. Only then may Security decide whether the assurance claim “physical-clone protection established within the approved provider trust boundary” is supportable.

## 12. Rollback and emergency disable

Rollback must reduce capability, never weaken verification:

- Global trust-enforcement switch defaults to **enabled enforcement** in Production once activated. Missing/malformed switch configuration means deny, not bypass.
- Emergency action is to disable all privileged ledger RPC execution at the gateway and/or revoke its DB principal's execute authority through an approved DBA procedure. This may pause ledger operations; it must not grant direct application access.
- Do not roll back to direct service-role calls, database-local identity-only checks, static shared secrets, cached positive decisions, or long-lived tokens.
- If verifier outage occurs before Production activation, do not activate. If outage occurs after activation, deny privileged RPCs, preserve unrelated read-only/user journeys where safe, alert operators, and reconcile in-flight execution IDs after recovery.
- If signing key compromise is suspected, revoke key and all outstanding attestations, disable gateway authorization, rotate under two-person approval, then re-run staging adversarial tests.
- Database rollback uses a separately reviewed forward-fix or compatible code rollback; never delete ledger history, clear nonce evidence, rewind generation, or destructively alter customer data.
- Resume only after verifier health, inventory freshness, key status, nonce-store consistency and audit continuity are independently demonstrated and Security/Infrastructure/DBA approve re-enable.

## 13. Measurable acceptance criteria

The architecture is not accepted for Production until all of the following are evidenced:

1. One immutable resource ID maps to exactly one project/environment/generation in the independent inventory; uniqueness and generation transitions are tested.
2. A byte-for-byte clone with copied database-local identity is denied on a distinct resource in 100/100 repeated attempts, with zero privileged RPC side effects.
3. All nine privileged RPCs require one valid, operation-specific attestation; 100% direct-call attempts from anon, authenticated, application service and non-gateway roles are denied.
4. 100/100 expired, future, stale-generation, wrong-environment, wrong-resource, wrong-operation, wrong-execution, wrong-source, wrong-audience, invalid-signature and revoked-key attempts are denied before RPC.
5. In at least 1,000 concurrent duplicate-consume races across multiple verifier replicas, exactly one consume succeeds per nonce and at most one RPC is forwarded.
6. Replayed nonce/attestation is rejected across verifier replicas, gateway replicas, and distinct database resources; replay records survive service restart and region failover.
7. Verifier, inventory, signing service, nonce store, clock-health, DNS, and gateway outages produce 100% fail-closed behavior; no positive cached authorization is used.
8. Ambiguous consume and downstream RPC outcomes never reuse the same nonce; recovery reconciles by execution ID without duplicate side effects.
9. Key rotation, emergency revocation and all-outstanding-token invalidation are rehearsed with measured propagation bounded by an approved SLO (proposed target: 30 seconds maximum; Security must approve).
10. Every allowlisted RPC emits a redacted correlated audit record for attestation issuance, consume decision, gateway forward and database outcome; no raw token, signing secret, provider credential or private member data appears in logs.
11. CI contains automated direct-privilege, allowlist-completeness, signature, replay, clone, outage and no-side-effect checks. Exact-head CI and actual PostgreSQL integration logs pass.
12. Staging full regression, rollback rehearsal, independent Security/Infrastructure/DBA approvals and an explicit Production change authorization are complete.

The numeric repetition counts and proposed 30-second revocation target are proposed acceptance thresholds, not existing evidence or guarantees. Security and Operations must approve or replace them before execution.

## 14. Existing evidence preserved and evidence boundary

C593–C597 established database-local identity consistency checks, immutable query-bundle membership/digest checks, adversarial substitution tests, PostgreSQL 16.16 runtime evidence, and exact-head CI on the prior PR #36 head. These checks remain useful and must remain in place.

They do **not** establish:
- independent provider workload identity;
- a unique external Production database resource binding;
- an external monotonic deployment generation;
- verifier-signed, short-lived operation-specific attestations;
- atomic external nonce consumption;
- independently governed verifier signing keys or revocation;
- unavoidable gateway enforcement before each privileged RPC;
- protection against a physical clone that carries all local database state.

Current status of each item above is **NOT IMPLEMENTED / NOT PROVEN**. This specification is design documentation only.

## 15. Change scope and compatibility constraints

Implementation must preserve all 40 historical migration files, migration inventory SHA `4e63f31368d446e905f4f44565be73337c7188fb` as observed at the C597 baseline, C575/C576 contracts, and `catalog_only_v1`. Any future privilege changes require new reviewed migrations and an explicit DBA plan; this task does not authorize them.

No Production database, role, grant, resource, environment variable, provider account, credential, signing key, trust root, or scheduler configuration was modified for C598. PR #36 is not modified, merged, or closed by this work.
