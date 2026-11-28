# C629 — Supabase Production Provider Escalation and Dependency Tracker

- Project: DeedLight
- Priority: P0 / Production release blocker
- Owner: DeedLight Security Architect (provider coordination); named platform/database owners to be assigned
- Related work: C628 D01–D09
- Tracker status: **OPEN — provider escalation NOT SUBMITTED**
- Production posture: **NO-GO** for recovery authorization that depends on unverified provider guarantees
- Last updated: 2026-11-28

## Purpose and decision boundary

This document converts the nine C628 external-trust dependencies into individually trackable provider questions, acceptance criteria, and independent DeedLight decisions. It is an escalation package and evidence tracker, **not evidence that Supabase Support has received or answered a ticket**.

Provider response status is restricted to:

- `NOT SUBMITTED`: no verified submission.
- `PENDING`: submission independently evidenced; answer outstanding.
- `CONFIRMED`: written provider answer plus required technical acceptance evidence.
- `REJECTED`: provider explicitly says the requested guarantee/capability is unavailable or unsupported.
- `INSUFFICIENT EVIDENCE`: answer is ambiguous, conditional without an enforceable guarantee, undocumented, or not supported by acceptance evidence.

Initial status for every question: **NOT SUBMITTED**. Do not promote a status based on verbal assurances, generic PostgreSQL behavior, disposable-database tests, or an unanswered ticket.

## Provider evidence baseline (not project-specific proof)

The following public Supabase documentation was reviewed as background for this escalation. It does not establish the behavior of DeedLight's particular Production project or substitute for written provider guarantees.

1. Restore to a new project: https://supabase.com/docs/guides/platform/clone-project
   - Describes database-only restoration, including schema, data, indexes, roles, permissions and users.
   - Describes manual reconfiguration requirements and warns that extensions configured for external operations (including pg_cron, pg_net and wrappers) must be disabled after the copy completes.
   - States that enabled extensions are copied.
2. Database backups and PITR: https://supabase.com/docs/guides/platform/backups
   - Describes physical backups, WAL-based PITR and restore behavior.
   - Notes that the project is inaccessible during restoration.
   - States that custom-role passwords are not included in downloadable daily backup files and need resetting after restoration.
3. Postgres roles: https://supabase.com/docs/guides/database/postgres/roles
   - Documents custom login roles and role permissions.
4. Connecting to Postgres / pooler modes: https://supabase.com/docs/guides/database/connecting-to-postgres
   - Describes direct, session-pooler and transaction-pooler connection modes and their intended use.
5. Vault: https://supabase.com/docs/guides/database/vault
   - Describes encrypted secret storage and key management. Restore portability and independence must be confirmed for the precise operation under review.
6. pgsodium: https://supabase.com/docs/guides/database/extensions/pgsodium
   - Supabase currently discourages new pgsodium usage and documents a pending deprecation path.
7. Extensions overview: https://supabase.com/docs/guides/database/extensions
8. Supabase Auth JWTs: https://supabase.com/docs/guides/auth/jwts

**Evidence limitation:** C628's reported observations (including shared PostgreSQL system_identifier behavior and scheduled-job execution timing) are carried forward as investigation leads. This document does not independently reproduce them against DeedLight Production. Provider confirmation is requested below. A database system identifier, endpoint certificate, project ref, copied row, GUC, Vault secret or cron state must not be treated as proof of a unique restore incarnation without a documented security guarantee.

---

## Individual provider dependency register

### D01 — Provider-authenticated physical database identity

- **Response status:** NOT SUBMITTED
- **Provider written confirmation required:** YES
- **DeedLight architecture decision required:** YES
- **Exact technical question:** Does Supabase expose an authenticated, machine-verifiable identity for the *currently running physical database incarnation*, distinct from the project identifier and endpoint identity? Does that identity change on in-place PITR, physical restore, restore-to-new-project/clone, project branch, failover, or replacement of the underlying database?
- **Expected guarantee:** A provider-authenticated attestation binds project, database instance/incarnation, restore event or epoch, and observation time. A restored copy cannot claim the source's current incarnation. Specify signature format, issuer, trust-chain distribution, freshness, revocation, and outage behavior.
- **Scenarios to answer:** (1) normal restart/failover without restore; (2) in-place PITR to an earlier timestamp; (3) physical backup restore; (4) restore-to-new-project clone; (5) project branch; (6) restore followed by another failover.
- **Acceptance criteria:** Capture pre-operation attestation; perform each supported scenario in a provider-approved non-production project; verify intended identity continuity/change; verify an old attestation is rejected after incarnation change; verify database superuser cannot forge or alter the attestation; verify expired/unavailable attestation fails closed.
- **Owner:** Supabase Platform/Database Engineering (provider); DeedLight Security Architect (internal).
- **Required provider response/configuration:** Written feature statement, API/interface and schema, signing-key trust model, lifecycle matrix, retention/freshness guarantees, supported plan/version requirements, and sample redacted attestation.
- **Security consequence if unavailable:** Database-local state cannot establish physical identity after rollback or clone; stale recovery authority could be replayed.
- **Fail-closed behavior:** Treat identity as unknown after any restore or uncertain lifecycle event; disable privileged recovery until independently re-established.

### D02 — PITR restoration and physical-clone state semantics

- **Response status:** NOT SUBMITTED
- **Provider written confirmation required:** YES
- **DeedLight architecture decision required:** YES
- **Exact technical question:** For each restore mode, exactly which database state is rewound/copied, which state is newly provisioned, which credentials/roles/secrets/extensions/settings are preserved or regenerated, and what provider event identifies completion?
- **Expected guarantee:** An authoritative matrix for in-place PITR, physical backup restore, restore-to-new-project, project branching and failover, covering schema/data/WAL, role catalog and credential verifiers, Vault key material, extensions, cron metadata, connection endpoints, TLS certificates, network controls, service configuration and project identifiers.
- **Scenarios to answer:** Restore to before (a) authorization issue, (b) authorization consumption, (c) key revocation, (d) principal password rotation, (e) cron disablement, and (f) schema/extension update. Include a clone made while source is live and a clone restored to a historical point.
- **Acceptance criteria:** For every supported mode, compare pre/post inventories and prove which values persist, rewind, regenerate or require manual setup. Verify old consumed/revoked authorization does not become valid. Verify restore completion and endpoint readiness are separately observable.
- **Owner:** Supabase Database/Backup Engineering; DeedLight Database Lead.
- **Required provider response/configuration:** Versioned restore semantics, credential and secret handling matrix, lifecycle event documentation, and supported audit/log evidence.
- **Security consequence if unavailable:** DeedLight may incorrectly assume a security control survives a rollback or clone.
- **Fail-closed behavior:** Treat restore semantics not explicitly covered by evidence as unknown; quarantine restored databases from privileged trust paths.

### D03 — Scheduled extension execution during restore/clone

- **Response status:** NOT SUBMITTED
- **Provider written confirmation required:** YES
- **DeedLight architecture decision required:** YES
- **Exact technical question:** Can any copied/restored scheduled task or extension execute before DeedLight can identify and quarantine the new incarnation? Is there a provider-supported way to suppress execution before first workload start?
- **Expected guarantee:** A documented pre-execution quarantine or, if unavailable, explicit confirmation that no such guarantee exists. Include pg_cron, pg_net, wrappers, triggers, extensions and provider-managed schedulers.
- **Scenarios to answer:** PITR in-place restore; physical restore; restore-to-new-project clone; branch; extension re-enable; job execution during provider recovery and before dashboard/API availability.
- **Acceptance criteria:** In an isolated provider-approved project, install a harmless scheduled sentinel and outbound-call sentinel; restore/clone; capture exact earliest execution relative to database/network readiness; prove outbound Production-like destinations reject the copy; test the documented suppression mechanism (if offered) before first job execution.
- **Owner:** Supabase Platform/Database Engineering; DeedLight Delivery Owner.
- **Required provider response/configuration:** Written statement of whether pre-start suppression exists, supported API/control and its timing guarantee; otherwise written confirmation that copied jobs may run and must be contained externally.
- **Security consequence if unavailable:** A restored database can send messages or invoke external mutation endpoints using copied schedules before operator intervention.
- **Fail-closed behavior:** All outbound endpoints require independent environment/incarnation authorization. Never trust a cron row, claim token, database flag or copied secret as proof of Production identity.

### D04 — Connection-pool database-principal isolation

- **Response status:** NOT SUBMITTED
- **Provider written confirmation required:** YES
- **DeedLight architecture decision required:** YES
- **Exact technical question:** In Supavisor transaction mode (and any dedicated pooler used), what are the exact pool partitioning keys and backend role semantics? Can two client principals ever share a backend in a way that leaks role, session state, prepared statements, temporary objects, advisory locks or authorization context?
- **Expected guarantee:** Documented authentication and backend-session isolation for each supported pooler/mode/version, including role switching, transaction reset behavior, connection reuse, cancellation and error paths.
- **Scenarios to answer:** Two distinct login roles interleaving transactions; SET ROLE / RESET ROLE; SET and SET LOCAL variables; commit/rollback; aborted transaction; prepared statement reuse; temp table; advisory lock; connection timeout/recycle; credential rotation.
- **Acceptance criteria:** Provider-approved concurrent test using separate least-privilege roles. Assert session_user/current_user/effective privileges and absence of cross-request state across successful and failed transactions. Run against the exact Production pooler endpoint/mode and record versions/configuration.
- **Owner:** Supabase Supavisor/Pooler Engineering; DeedLight Database Architect.
- **Required provider response/configuration:** Pool key definition, role authentication semantics, session reset guarantees, unsupported SQL/session features, and exact pooler implementation/version.
- **Security consequence if unavailable:** A request may execute under a prior principal's effective authorization context.
- **Fail-closed behavior:** Do not rely on mutable session state for recovery authorization; use separately authenticated narrow connections and transaction-bound checks. If isolation cannot be proven, prohibit this pooler path for privileged recovery.

### D05 — Supported PostgreSQL Ed25519 and COSE verification

- **Response status:** NOT SUBMITTED
- **Provider written confirmation required:** YES
- **DeedLight architecture decision required:** YES
- **Exact technical question:** Which exact managed Supabase PostgreSQL versions and provider-supported extensions/libraries expose Ed25519 verification and standards-conformant COSE Sign1 verification? Are those functions allowed under managed roles and supported through major-version upgrades?
- **Expected guarantee:** Named, maintained and supported implementation; exact version/function signatures; algorithm restrictions; canonical encoding/parser behavior; security patch policy; upgrade compatibility. Distinguish Ed25519 primitive verification from complete COSE protected-header, payload and algorithm validation.
- **Scenarios to answer:** Valid signature; modified payload; wrong key; unknown key ID; malformed CBOR; duplicate/non-canonical headers; unsupported algorithm; algorithm confusion; detached payload; expired/revoked authorization; extension upgrade/removal.
- **Acceptance criteria:** Independent test vectors (including malformed/adversarial cases) against the exact managed PostgreSQL version and extension. Verify no downgrade or alternate algorithm path. Document extension ownership and support lifecycle. No disposable PostgreSQL result alone qualifies.
- **Owner:** Supabase Database/Extensions Engineering; DeedLight Cryptography Reviewer.
- **Required provider response/configuration:** Supported extension/function matrix, versions, provider restrictions, maintenance/deprecation policy, and upgrade guarantees.
- **Security consequence if unavailable:** Database verification may rely on unsupported, incomplete or deprecated cryptographic code.
- **Fail-closed behavior:** No substitution with HMAC, pgjwt, deprecated pgsodium or hand-rolled parsing unless separately designed, reviewed and explicitly accepted. Unsupported verification means no privileged recovery.

### D06 — Independent database-principal authentication

- **Response status:** NOT SUBMITTED
- **Provider written confirmation required:** YES
- **DeedLight architecture decision required:** YES
- **Exact technical question:** Can a dedicated recovery database login be authenticated independently of rollback-prone database contents, and what precisely happens to its role, password verifier, memberships, grants and active sessions across each restore mode?
- **Expected guarantee:** Authentication is not silently resurrected by restoring role catalog state; revocation/rotation can be enforced outside the restored snapshot; distinct principals are supported and least-privilege grants can be maintained.
- **Scenarios to answer:** Role created before snapshot; password rotated after snapshot; role revoked/dropped after snapshot; restore to before rotation/revocation; physical clone; connection pool retains old session; provider-managed password reset.
- **Acceptance criteria:** Create distinct recovery and application principals; prove grants are minimal; rotate/revoke; perform restore scenarios; test fresh and existing sessions; prove revoked credential cannot authenticate after recovery. Verify credential recovery procedure without exposing secrets.
- **Owner:** Supabase Database Engineering; DeedLight Infrastructure Owner.
- **Required provider response/configuration:** Restore-specific role/password semantics and supported revocation/session invalidation procedure.
- **Security consequence if unavailable:** A database snapshot may restore a previously revoked credential or privileged role.
- **Fail-closed behavior:** Recovery principal is disabled until its identity, grants and credential state are re-established out-of-band after restore.

### D07 — Restore-incarnation fencing feasibility

- **Response status:** NOT SUBMITTED
- **Provider written confirmation required:** YES
- **DeedLight architecture decision required:** YES
- **Exact technical question:** Does Supabase provide any provider-enforced fence that prevents pre-restore credentials, signatures, database sessions or API requests from being accepted by a restored incarnation? If not, can the provider expose a trustworthy restore event/epoch to an external fence?
- **Expected guarantee:** A restore invalidates or makes distinguishable all pre-restore authorization state; no restored database can self-assert that it is the current source.
- **Scenarios to answer:** Restore to a point before token issuance; restore to a point after issuance but before consumption; restore to a point before revocation; clone with copied roles/cron/secrets; source and clone both active.
- **Acceptance criteria:** Issue a one-time authorization at epoch N; consume/revoke it; restore to a snapshot containing the unconsumed state; demonstrate old authorization rejected by a component whose state was not restored. Demonstrate source and clone cannot both satisfy Production identity.
- **Owner:** Supabase Platform/Database Engineering; DeedLight Security Architect.
- **Required provider response/configuration:** Explicit yes/no for native fencing; if yes, API, threat model and guarantees; if no, documented restore events/identifiers and operational limitations.
- **Security consequence if unavailable:** Authorization replay across rollback/clone remains possible unless an independent DeedLight fence is implemented.
- **Fail-closed behavior:** A restore/clone event or uncertain lifecycle state invalidates trust. Do not reopen recovery until independent fence confirms a new incarnation.

### D08 — Independent monotonic generation authority

- **Response status:** NOT SUBMITTED (provider question only if Supabase offers a candidate capability)
- **Provider written confirmation required:** CONDITIONAL — ask whether a Supabase-managed service exists; absence of one does not block DeedLight from selecting an external authority.
- **DeedLight architecture decision required:** YES — mandatory internal architecture decision.
- **Exact technical question:** Does Supabase offer a provider-managed monotonic counter/epoch service that is transactionally durable outside the restored database and cannot be rolled back with PITR or clone? If so, what are its consistency, durability, failover and tenant-isolation guarantees?
- **Expected guarantee:** Atomic compare-and-advance; linearizable/strongly consistent reads and writes; state independent of PostgreSQL backups/restores; durable revocation; replay resistance; auditable writes; explicit unavailability semantics.
- **Scenarios to answer:** PostgreSQL PITR to old generation; concurrent generation advancement; authority failover; network partition; duplicate request; retry after ambiguous response; authority restore; account/project migration.
- **Acceptance criteria:** Advance from N to N+1; rewind PostgreSQL to N; verify N remains rejected. Race concurrent advances and replay old requests. Simulate authority outage and ambiguous write response; prove no stale authorization is accepted.
- **Owner:** DeedLight Security Architect and External Trust Service Owner. Supabase Platform Engineering only for candidate provider service confirmation.
- **Required provider response/configuration:** Written yes/no and specification for any candidate Supabase service. DeedLight must independently select and approve an external authority if no suitable provider capability exists.
- **Security consequence if unavailable:** Database rollback can rewind authorization generation and revive stale grants.
- **Fail-closed behavior:** No successful, authoritative generation read/advance means no privileged recovery. Do not substitute database sequence/table, timestamp, cron job or cache.

### D09 — External signing and private-key custody

- **Response status:** NOT SUBMITTED (provider question only for provider-managed KMS/HSM integration guarantees)
- **Provider written confirmation required:** CONDITIONAL
- **DeedLight architecture decision required:** YES — mandatory internal architecture decision.
- **Exact technical question:** Does Supabase offer a supported integration to an external KMS/HSM that keeps private signing keys non-exportable and inaccessible to database roles, including restored/cloned projects? What is the documented trust boundary for Vault/root-key restoration and project clones?
- **Expected guarantee:** Private key never enters PostgreSQL, Vault plaintext, application logs or browser configuration; signing requires independently authenticated authorization; revocation and rotation are independent of database rollback; every signing event is auditable.
- **Scenarios to answer:** PITR; physical clone; Vault restore; source/clone concurrent operation; key rotation; key revocation; compromised database superuser; KMS outage; ambiguous signing response.
- **Acceptance criteria:** Clone/restore database and attempt to extract/use key; verify failure. Attempt signing without external authorization; verify rejection. Revoke key and prove all old authorizations invalid. Verify audit event, key version and non-exportability. Verify outage fails closed.
- **Owner:** DeedLight Security Owner and KMS Administrator; Supabase Platform/Security Engineering for provider integration statements.
- **Required provider response/configuration:** Written KMS/HSM support statement, supported integration method, network/auth model, restore behavior, and confirmation whether Vault encryption root key is portable across relevant clone/restore operations.
- **Security consequence if unavailable:** A restored or compromised database may gain the ability to impersonate the trusted signer.
- **Fail-closed behavior:** No signing from database-held private keys or copied Vault secrets. If external KMS authorization cannot be established, refuse signing.

---

## Provider escalation package (single coordinated P0 ticket)

**Suggested subject:** P0 Security Architecture Escalation — PITR/Clone Incarnation Identity, Scheduled Workload Isolation, and External Recovery Trust Guarantees (DeedLight)

**Suggested routing:** Supabase Support → Database/Platform Engineering; request escalation to Backup/Restore, Supavisor, Extensions and Security/KMS owners as applicable.

**Submission state:** NOT SUBMITTED. The following is prepared text only.

### Ticket body

We are designing a fail-closed recovery authorization boundary for a production application using Supabase-managed PostgreSQL. The security design must remain safe across in-place PITR, physical backup restoration, restore-to-new-project/clone, project branching, failover and recovery from ambiguous provider outcomes.

We need written, version-specific answers from the teams responsible for managed PostgreSQL, backup/restore, Supavisor, extensions and platform security. Please answer each numbered question explicitly; where a capability is not supported, please say so rather than suggesting an unverified PostgreSQL workaround.

1. **Physical database identity (D01):** Is there a provider-authenticated attestation for the currently running physical database incarnation? Does it change for PITR, physical restore, clone, branch and failover? Provide interface, issuer/signature, freshness, lifecycle and anti-forgery guarantees.
2. **Restore semantics (D02):** Provide a restore-mode matrix for data/catalog, role credentials, secrets/Vault root key, extensions, cron jobs, endpoints, TLS, network controls and completion events for in-place PITR, physical restore, new-project clone and branch.
3. **Scheduled work (D03):** Can pg_cron/pg_net/wrapper or other copied jobs run before an operator can quarantine a restored database? Is there a supported pre-execution suppression/quarantine control? State exact earliest execution timing and limitations.
4. **Pooler isolation (D04):** Document Supavisor transaction-pool partition keys, role authentication and backend reset guarantees. Can session state, role, prepared statements, temporary objects, advisory locks or authorization context cross client boundaries? Provide exact version and supported test method.
5. **Ed25519/COSE (D05):** Which managed PostgreSQL versions and supported extensions provide Ed25519 verification and complete COSE Sign1 verification? Provide function names, versions, algorithm and parser guarantees, role restrictions, upgrade/deprecation policy.
6. **Recovery principal (D06):** For each restore mode, how are custom login roles, password verifiers, memberships, grants and active sessions handled? How can a revoked/rotated recovery credential be guaranteed not to return after rollback?
7. **Restore fencing (D07):** Is there a provider-enforced mechanism that invalidates pre-restore authorization or exposes a trustworthy restore epoch/event to an external verifier? If unsupported, explicitly confirm.
8. **Monotonic generation (D08):** Does Supabase provide a strongly consistent, rollback-independent monotonic generation/epoch authority outside the PostgreSQL restore domain? If yes, provide durability, consistency, failover and audit guarantees. If no, explicitly confirm no suitable managed capability is offered.
9. **External signing/KMS (D09):** What supported KMS/HSM integrations keep signing private keys non-exportable and inaccessible to database roles and restored clones? Clarify Vault root-key behavior across PITR, clone and branch.

For each response, please identify the applicable product/plan, PostgreSQL and pooler versions, documented support status, operational prerequisites, failure behavior, and whether the guarantee is contractual/documented or best-effort. Please distinguish confirmed platform behavior from recommendations or generic PostgreSQL behavior.

### Requested provider evidence

- Written response linked to each D01–D09.
- Applicable product and version identifiers.
- API/interface specifications and relevant documentation.
- Restore/clone lifecycle guarantees.
- Provider-supported test environment and acceptance procedure.
- Explicit statement for every unsupported or unavailable guarantee.

### Security posture while awaiting response

No Production configuration, credentials, migrations or recovery contracts are to be changed as part of this escalation. DeedLight will not treat queue claims, copied database state, PostgreSQL system identifiers, database-resident secrets, or successful disposable PostgreSQL tests as independent recovery authority.

---

## DeedLight decisions that must not be delegated to Supabase

These are internal architecture decisions even if provider answers inform them.

1. **Choose an independent trust authority.** Select an externally durable service that owns monotonic generation, restore-incarnation fencing, authorization expiry/revocation and replay prevention. It must be outside the Supabase PostgreSQL backup/restore domain. Define availability, consistency, tenant isolation, audit, disaster recovery, retention, cost and exit strategy.
2. **Choose KMS/HSM and key custody.** Select an external KMS/HSM with non-exportable signing keys, separate administrators, scoped workload identity, rotation, revocation, audit logging and tested recovery. Define signer authorization policy and emergency key compromise procedure.
3. **Define trust protocol.** Specify signed authorization claims, target project/database/incarnation binding, generation, nonce, audience, expiry, key ID, algorithm allowlist, canonical encoding and one-time consumption. Reject ambiguous outcomes.
4. **Define restore quarantine.** All restored/cloned databases begin untrusted. Prevent outbound Production delivery and privileged recovery until an independent authority has approved the exact incarnation. Include cron, extension, edge-function and external endpoint paths.
5. **Choose principal topology.** Separate app, delivery, migration, operator and recovery principals. Minimize grants; avoid service-role or database-superuser dependence for ordinary recovery operations.
6. **Define degraded-mode behavior.** Trust authority/KMS/network outages, delayed provider events, clock uncertainty, lost response after write/sign, and partial restore all fail closed. Define human break-glass governance without silent bypass.
7. **Approve verification implementation.** Choose a maintained cryptographic library/verification boundary based on supported provider capability and independent review; do not assume PostgreSQL is the correct place to parse/verify COSE.
8. **Own lifecycle operations.** Define how source and clone are distinguished, how old keys and authorizations are revoked, and how a restored Production service is re-enrolled.

## Tracking and acceptance workflow

For each D01–D09, maintain:
- provider response status and date;
- ticket URL/ID and exact written answer;
- provider contact/team and applicable versions;
- evidence links and limitations;
- named DeedLight owner;
- acceptance-test run, environment and result;
- security reviewer disposition;
- remaining blockers and next action.

Status transition rules:
- `NOT SUBMITTED → PENDING`: only after ticket submission is independently evidenced by ticket ID/URL or sent correspondence record.
- `PENDING → CONFIRMED`: written answer plus acceptance criteria passed and reviewed.
- `PENDING → REJECTED`: explicit provider denial or unsupported capability.
- Any state → `INSUFFICIENT EVIDENCE`: evidence is ambiguous, incomplete, stale, or cannot be reproduced.
- A rejected provider capability can be closed only after an independently reviewed DeedLight replacement architecture passes the same security objective. Rejection itself is not acceptance.

## Production gate

Production remains **NO-GO** for trust/recovery paths that rely on any unresolved D01–D09 guarantee. No provider answer alone grants Production approval. Level 2 security review must verify the integrated design and adversarial acceptance tests, including:

- PITR and clone with old authorization replay;
- concurrent source/clone isolation;
- copied scheduled job attempting outbound action;
- revoked credential after rollback;
- pooler cross-principal concurrency;
- malformed and substituted cryptographic signatures;
- monotonic generation during restore and authority failover;
- KMS outage, key revocation and ambiguous signing outcome;
- external endpoint rejection for untrusted incarnations.

No Production configuration, credentials, existing migrations, or recovery authorization contracts are changed by this document.

## Current status snapshot

| ID | Provider response | Written confirmation required | Internal decision required | Gate |
|---|---|---|---|---|
| D01 | NOT SUBMITTED | Yes | Yes | BLOCKED |
| D02 | NOT SUBMITTED | Yes | Yes | BLOCKED |
| D03 | NOT SUBMITTED | Yes | Yes | BLOCKED |
| D04 | NOT SUBMITTED | Yes | Yes | BLOCKED |
| D05 | NOT SUBMITTED | Yes | Yes | BLOCKED |
| D06 | NOT SUBMITTED | Yes | Yes | BLOCKED |
| D07 | NOT SUBMITTED | Yes | Yes | BLOCKED |
| D08 | NOT SUBMITTED | Conditional | Yes | BLOCKED |
| D09 | NOT SUBMITTED | Conditional | Yes | BLOCKED |

**Next action:** A DeedLight-authorized owner must submit the prepared ticket through the authenticated Supabase Support channel, capture the ticket ID/URL and submitted body, then update the individual status records to PENDING. No submission has been performed by this change.
