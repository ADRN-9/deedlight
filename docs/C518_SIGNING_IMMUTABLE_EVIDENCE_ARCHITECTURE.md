# C518 — Signing authority and immutable evidence architecture assessment

**Repository:** `ADRN-9/deedlight`  
**Assessment starting HEAD:** `4c15744e9b8d5540559e68ef11cdfdfd64fa96b1`  
**Implementation branch:** `feat/production-evidence-collector-e1-e2`  
**Scope:** non-Production evidence integrity hardening, architecture assessment and human-controlled dependency register.  
**Production disposition:** **NO-GO**. No Production signing, key provisioning, storage mutation, collector authentication, backup/PITR operation, restore, migration, or infrastructure change was performed.

## Executive summary

DeedLight already has a meaningful *verification* foundation:
- The migration evidence analyzer verifies Ed25519 signatures for three distinct roles: `evidence-approver`, `mapping-approver`, and `collector`.
- The trust-root bundle is external to the repository, and its canonical SHA-256 must match `DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256`, captured at analyzer process startup.
- Signer identity, key ID, algorithm, role, active/revoked status, key validity window, approval issue/expiry, revoked approval IDs, distinct signer/key/approval IDs, and signed claims binding are checked fail-closed.
- Tests generate ephemeral Ed25519 keys and exercise signature forgery, unauthorized signer, role separation, revocation, expiry, trust-root digest substitution, private-key material rejection and evidence/mapping/collector binding.

This is a verifier and test fixture—not a deployed signing authority. The Production collector emits `UNSIGNED_NOT_ACCEPTED` receipts. No KMS/HSM, production key custody, immutable evidence store, retention lock, independent receipt-acceptance service, Production staging environment, or restore evidence is established.

C518 adds a bounded offline evidence-package integrity manifest and adversarial tests. It binds the exact receipt bytes and raw evidence bytes to a deterministic package digest. It intentionally does **not** authenticate the manifest, sign anything, upload anything, or claim immutability. CI is configured to run these tests without Production credentials.

## Exact implementation changes

| File | Change | Security boundary |
|---|---|---|
| `scripts/evidence-package-integrity.mjs` | New deterministic two-file manifest creator/verifier | Offline integrity only; no signing or I/O |
| `scripts/test-evidence-package-integrity.mjs` | New adversarial tests for raw receipt/evidence tampering, path swaps, extra files, status promotion and manifest modification | Synthetic fixtures only |
| `.github/workflows/pr-validation.yml` | Adds a dedicated offline package-integrity test step | Existing CI fail-closed Production-secret checks remain in force |

The manifest is explicitly marked `UNSIGNED_INTEGRITY_ONLY_NOT_ACCEPTED`. It binds exactly `evidence.csv` and `receipt.json`, including path, byte length and SHA-256, and a canonical SHA-256 over the manifest payload. The verifier re-runs the collector's semantic receipt/evidence verifier before accepting the package as internally consistent.

**Important limitation:** an attacker who can replace both files and the manifest can recompute the unkeyed hashes. This manifest detects accidental corruption and partial/substitution attacks when the manifest digest is independently retained; it does not establish origin, signer identity, tamper-proof retention, or non-repudiation. It must not be represented as a signature or immutable-storage control.

## Existing signing and trust-root implementation

### Current cryptographic contract

`scripts/reconcile-migration-evidence.mjs` implements Ed25519 verification using Node's crypto public-key verification. A signed artifact has an exact envelope:
- `schemaVersion`, `kind`, `signerId`, `keyId`, `approvalId`;
- canonical `issuedAt` and `expiresAt`;
- exact `claims`;
- base64 Ed25519 signature over the canonical unsigned envelope.

Three independent roles are mandatory. The evidence approver, mapping approver and collector must have three distinct signer IDs, key IDs and approval IDs. Claims bind the exact project, evidence digest, mapping digest, query bundle digest, collector identity and capture timestamp. Collector authority is separately bound to authenticated database identity, effective privileges, execution ID, query digest, captured time and result digest. Migration history remains a database fact and is not treated as exact SQL execution provenance.

Trust-root bundle validation:
- requires schema version 1 and rejects unknown bundle/key fields;
- rejects private key material and non-Ed25519 keys;
- rejects duplicate key IDs and reuse of one public key across signer identities;
- requires the independent trust-root digest;
- checks key role, status, `notBefore`, `notAfter`, and explicit `revokedAt`;
- rejects revoked approval IDs and expired or not-yet-valid artifacts.

### Current gap

The verifier has no corresponding authorized signer service. There is no production key-generation/provisioning workflow, HSM/KMS key reference, signing policy, quorum approval workflow, audit-log evidence, rotation ceremony, emergency revocation runbook, recovery/escrow policy, or independent key-custodian attestation. Ephemeral fixture private keys in CI are test-only and are never Production authority.

### Recommended signing architecture (not deployed)

1. **Offline root of trust:** create a root authority under a separately governed security account, preferably HSM-backed. Root key is non-exportable, not mounted into CI or application runtimes, and used only to authorize short-lived role-specific public keys and trust-root bundle versions.
2. **Role-separated operational keys:** provision separate non-exportable Ed25519-capable signing identities for evidence approver, migration mapping approver and collector. If the selected managed KMS/HSM cannot sign Ed25519, do not silently switch algorithms; either select a provider supporting the exact algorithm or separately review a versioned algorithm migration and verifier contract.
3. **Attested signing requests:** the signer accepts a bounded schema, exact artifact kind and digest, project identity, evidence/mapping/query digests, capture time, approval IDs, signer role and expiry. It must not accept arbitrary bytes or generic signing requests from the application.
4. **Independent authorization:** evidence and mapping approvals come from different human authorities. Collector attestation comes from a separately controlled collector identity. Signing service checks role-specific policy and quorum; the collector cannot approve its own evidence or mapping.
5. **Trust-root publication:** publish only public keys, key IDs, signer IDs, roles, validity intervals and revocation metadata. Publish a canonical trust-root bundle plus its digest through a separate protected channel. The digest must not be sourced from the same untrusted evidence package it validates.
6. **Verification:** use a separate offline verifier/service that verifies signature, artifact schema, claim binding, key validity at signing time, current revocation policy, trust-root version, receipt/evidence hashes and freshness. Acceptance is a separate signed state transition, never inferred from signature presence.

### Key custody, rotation and revocation procedure

**Provisioning**
- Security owner and key custodian approve role, scope, algorithm, identity and recovery policy.
- Generate keys inside the selected KMS/HSM; private key material is non-exportable. Record immutable key resource ID, algorithm, region/account boundary, hardware protection level, creation audit event, public-key fingerprint and custody approvals.
- Validate a test signature with the public key in an isolated staging environment. Confirm unauthorized principals cannot invoke signing, export, disable, delete or alter policy.
- Publish a signed trust-root bundle update with key ID, signer ID, role, validity interval, status and explicit null revocation timestamp.

**Rotation**
- Create a new key and publish it as active before the old key is retired.
- Verify new signatures end-to-end in staging and independently validate the trust-root digest distribution.
- Establish a bounded overlap; old key can verify historical artifacts only under explicit historical validation policy, but must no longer issue new signatures after cutover.
- Mark the old key retired/revoked in a versioned trust-root update; do not reuse key IDs or public-key material.
- Retain the signed old trust-root versions for audit and historical signature verification, while current acceptance policy checks revocation and compromise status.

**Emergency revocation**
- Security owner can disable the KMS/HSM signing permission/key immediately; do not wait for a code release.
- Publish a separately authenticated trust-root revocation with effective UTC timestamp, reason code and affected approval IDs where applicable.
- Invalidate pending approval IDs and stop accepting new receipts signed by the compromised key. Decide explicitly whether historical signatures remain valid before compromise time; do not infer trusted signing time solely from an untrusted artifact timestamp.
- Preserve KMS audit logs, root-bundle versions, signature samples and incident timeline in immutable storage.
- Restore service only after a new key, new root-bundle digest, signer authorization and independent verifier checks are approved.

**Recovery**
- Define KMS/HSM regional failure and account-loss procedures before activation. Prefer provider-managed replication/backup under a separate security boundary. If key export/escrow is required, it materially weakens non-exportability and requires a documented dual-control offline ceremony, split knowledge and periodic recovery drill. No recovery mechanism is currently evidenced.

## Immutable evidence storage and tamper detection

### Current state

- Collector writes `evidence.csv` and `receipt.json` to a newly created external local directory with restrictive file permissions.
- Receipt contains raw evidence SHA-256, canonical result SHA-256, byte length, source commit, inventory blob, query bundle digest, endpoint/TLS identity metadata, role identity, rollback verification and capture timestamps.
- `verifyReceiptAndEvidence` re-parses the CSV, checks the strict receipt schema, raw evidence hash, canonical result hash, record counts and transaction-close marker.
- Reconciliation analyzer verifies the signed evidence, mapping and collector claims and their cross-bindings.
- C518 package manifest adds a deterministic binding of exact receipt bytes and evidence bytes.

### Missing controls

No immutable object store, retention policy, WORM/Object Lock, legal hold, object versioning, server-side encryption/KMS key policy, independent object digest, append-only audit log, replication policy, lifecycle policy, delete-denial test, or independent read-back verifier is deployed. Local `0600` files and SHA-256 are not immutability. A mutable manifest is not an authenticity mechanism.

### Recommended E4 storage contract

- Dedicated evidence account/project separate from DeedLight Production and CI; separate storage administrator and evidence custodian roles.
- Versioned object storage with compliance-mode retention lock/WORM, retention period approved by legal/security, object version IDs and delete/overwrite denial.
- Encrypt at rest using a customer-managed key where feasible; key policy separates evidence writers, readers, retention administrators and KMS key administrators. No writer may shorten retention or delete protected versions.
- Upload signed receipt, raw evidence, package manifest, trust-root bundle version, signature/approval artifacts, source commit/query digest, CI run references and failure diagnostics as separate content-addressed objects.
- Store an independently signed index/commit record that binds all object names, version IDs, byte lengths, SHA-256 digests, trust-root version and retention metadata. A storage receipt must include provider object version ID, retention mode/until date and server timestamp.
- A separate verifier retrieves the exact object versions, re-hashes every byte, verifies signatures and trust-root version, checks object-lock metadata and confirms the index signature. Any mismatch or missing retention metadata fails closed.
- Run periodic read-back and retention-denial tests; export provider audit logs to a separate immutable security log destination.

## Isolated staging pipeline and Production collector authentication

**Already present in the code boundary:** the E1/E2 collector uses a fixed approved SQL bundle, independently pinned endpoint-profile and TLS CA digests, libpq `verify-full`, direct login as `deedlight_catalog_auditor`, a minimal child environment, read-only repeatable-read transaction, strict result parsing, explicit rollback marker, bounded output/time and private local files. It refuses arbitrary SQL. CI runs a disposable PostgreSQL 16 integration fixture with locally generated TLS certificates and asserts Production configuration/secrets are absent.

**Not established:** Production credentials or profile, Production TLS/endpoint proof, a real dedicated Production login, a production runner identity, OIDC workload federation, short-lived database credentials, production secret-manager policy, HSM/KMS-backed collector attestation, independent signed receipt verifier, or E4 storage.

**Required staging pipeline:**
1. CI static and adversarial tests run on synthetic fixtures only; no Production secrets, routes or endpoints.
2. Isolated staging project with independent project identity, test-only login and disposable datasets. Prove wrong project, wrong TLS CA, DNS/hostname substitution, inherited environment, privilege escalation and credential expiry all fail closed.
3. A staging-only identity provider issues short-lived OIDC identity to a locked-down runner. The runner exchanges it for narrowly scoped secret-manager access and a short-lived database credential; no long-lived DB password in GitHub secrets.
4. Production collector activation is a separate, human-approved workflow/environment requiring protected deployment reviewers and exact source/query/trust-root digests. Do not re-use staging identities.
5. Collector signs only the successful fixed-query result digest after independent policy checks; it cannot sign approvals or alter evidence after capture.
6. Evidence is delivered to E4 immutable storage. An independent verifier re-reads exact object versions and validates receipt, signature, trust root and retention controls.

### Production authentication prerequisites

- Independently verified Supabase project and endpoint profile; pinned TLS CA chain; no trust in SQL GUCs as identity.
- Dedicated non-superuser direct-login collector role with exact catalog/history SELECT allowlist, no inherited memberships, no app-row privileges and no ownership/DDL/mutation powers.
- Short-lived credential via approved secret manager/OIDC where supported; credentials never in repo, chat, shell history, process arguments or logs.
- Protected runner environment, workload identity attestation, egress allowlist, audit logs, least privilege, credential revocation and incident response.
- DBA/security approval of the read-only window and collector commit/query digest. Collection remains separate from any migration or reconciliation approval.

## Backup/PITR and isolated restore rehearsal

No Production backup, PITR configuration, restore point, retention setting, restore operation or recovery test was inspected or performed in C518. There is no repository artifact that proves a restorable Production backup exists.

Before any future migration-history/schema reconciliation:
1. DBA confirms the Production project's backup/PITR entitlement, recovery window, retention and latest successful recovery point through the Supabase Dashboard/provider evidence.
2. Record exact project, database, restore-point UTC timestamp, recovery window and provider operation ID in the change record; ensure the point predates all proposed writes.
3. Restore into a separate isolated non-Production project with equivalent PostgreSQL major version/extensions and no public access. Disable delivery, Cron and external integrations; block outbound provider traffic.
4. Verify restore completed, database is accessible, expected roles/extensions/schema/history/data invariants exist, and authenticated/unauthenticated DeedLight regression checks pass.
5. Test proposed reconciliation only on the restored clone. Capture before/after schema and history exports, object fingerprints, row-count/invariant results and rollback rehearsal.
6. Independently verify the clone can be restored again or discarded without Production side effects. Record elapsed restore time and observed data-loss window.
7. DBA, security owner and independent reviewer approve the precise Production change plan, rollback point and abort conditions. A backup status indicator alone is not a restore rehearsal.

Rollback must use a proven restore point or reviewed forward correction. Do not assume reverse SQL can undo data transformations, provider events or backfills. A migration-history-only edit is not a schema rollback.

## Existing executable tests and CI evidence

### Existing tests

- `scripts/test-reconcile-migration-evidence.mjs`: ephemeral Ed25519 keypair tests for valid three-role signatures, signature forgery, unauthorized key, revocation, expiry, revoked approval IDs, trust-root digest substitution, private material rejection, signer/key/approval separation, claim binding, tampered evidence/mapping and invalid collector authority.
- `scripts/test-production-evidence-collector.mjs`: strict receipt schema, raw/canonical digest binding, CSV/ACL completeness, timestamp semantics, TLS CA pin integrity and cleanup.
- `scripts/test-production-evidence-collector-postgres16.sh`: disposable PostgreSQL 16 + local TLS certificate + direct-login integration; no Production credentials.
- `scripts/test-production-owner-approval-bundle.mjs`: signed Production owner approval mechanics using ephemeral fixture keys.
- `scripts/test-production-migration-readonly-audit-postgres16.sh`: synthetic PostgreSQL role/privilege and read-only audit behavior.
- C518 adds `scripts/test-evidence-package-integrity.mjs` for the unkeyed package-manifest integrity contract.

### CI evidence status

At assessment time, the most recent completed PR #24 validation run known from C517 was `45896308928` on source HEAD `aaefdd0c2e2e9cd533082081cc52d7bcb6a4d9af` (12/12 jobs success). It predates C518 and does not validate C518 changes.

C518 adds the package test to `.github/workflows/pr-validation.yml`. A new exact-head CI run is required before claiming the implementation/tests pass. CI tests use ephemeral keys and disposable PostgreSQL only; they do not establish KMS/HSM readiness, Production signing, Production collector authentication, immutable storage or restore readiness.

## Human-controlled dependency register

| Owner | Dependency / evidence required | Acceptance gate | Current status |
|---|---|---|---|
| Security owner | Select KMS/HSM provider and account boundary; document supported Ed25519 operation, HSM protection level, region, audit logs, availability and compliance controls | Independent security architecture approval and successful isolated sign/verify test | NOT PROVIDED |
| KMS/HSM administrator | Provision non-exportable root and three role-specific operational keys under separate identities | Key resource IDs, public fingerprints, policy snapshots and provider audit events verified | NOT PROVISIONED |
| Independent key custodian | Approve key ceremony, custody, recovery, dual control and separation of duties | Signed custody and recovery procedure; witnessed recovery drill | NOT PROVIDED |
| Security owner | Approve trust-root format/version, independent digest distribution and revocation authority | Versioned signed root bundle and independent digest pin distribution | NOT PROVIDED |
| Signing service owner | Implement bounded role-specific signing API with policy enforcement and audit logging | Staging-only negative tests for role misuse, altered claims, expiry, replay, revocation and disabled keys | NOT IMPLEMENTED |
| Independent verifier owner | Deploy separate acceptance verifier and trust-root/revocation freshness policy | Independent verifier accepts valid fixture and rejects forged/stale/revoked/misbound artifacts | NOT IMPLEMENTED |
| Evidence custodian | Provision separate evidence storage account/project, WORM/Object Lock, versioning, encryption and retention policy | Provider evidence of compliance-mode retention and overwrite/delete denial | NOT PROVISIONED |
| Storage/KMS administrators | Separate writer, reader, retention admin and key admin; prevent writers from changing retention | Access-policy review and negative privilege tests | NOT PROVIDED |
| Evidence custodian | Configure signed index/commit records, object-version receipts, audit-log export and periodic read-back | Independent re-hash and retention verification for exact object versions | NOT IMPLEMENTED |
| Platform/security | Configure isolated staging Supabase project, OIDC runner identity, secret manager, egress controls and short-lived DB auth | Wrong-project/TLS/credential/privilege/egress tests pass with staging-only data | NOT PROVIDED |
| Supabase DBA | Provision direct-login least-privilege collector principal and provide authenticated endpoint profile/CA via independent channel | Production identity/privilege/TLS verification under separately approved read-only collection | NOT PROVIDED |
| Supabase DBA | Supply backup/PITR settings and exact restorable recovery point | Provider-backed backup metadata and successful isolated restore evidence | NOT PROVIDED |
| DBA + application owner | Perform isolated restore rehearsal with delivery/Cron/provider egress disabled | Schema/history/data invariant and application regression checks pass on restored clone | NOT PERFORMED |
| Independent migration reviewer | Complete source-linked mapping for all 39 migrations across nine effect domains | Signed mapping approval digest; 007/018/037 uncertainty resolved or remains UNKNOWN | BLOCKED (C517) |
| Security reviewer | Independent security acceptance of PR #25 | Approved independent review and merge under normal repository policy | BLOCKED; PR #25 OPEN |

## Risks and explicit non-claims

- **No KMS/HSM readiness claim:** no provider selected, key provisioned or policy inspected.
- **No Production signing:** E2 receipt remains unsigned and not accepted; ephemeral CI keys are fixtures.
- **No immutability claim:** package manifest is unkeyed and locally verifiable; immutable storage and retention lock are absent.
- **No Production collector claim:** only disposable PostgreSQL/TLS integration is tested. Production project identity, login and credentials are unprovisioned.
- **No backup/restore claim:** Production PITR configuration and restore point are not independently verified; no restore operation occurred.
- **No migration reconciliation claim:** all Production execution classifications remain UNKNOWN; duplicate 007, Migration 018 and Migration 037 remain unresolved. Normal Production `supabase db push` is not approved.
- **PR #25 remains a separate security acceptance blocker:** do not merge it or represent this C518 work as independent approval.
- **Production remains NO-GO.**

## Acceptance sequence

1. Complete C518 exact-head CI and review the new offline package-manifest tests.
2. Security owner approves KMS/HSM provider, key algorithm and root/role separation; key custodian provisions and attests keys out-of-band.
3. Implement and adversarially test a bounded staging-only signing service and independent verifier; publish trust-root version and independent digest.
4. Provision E4 WORM store, separate access roles, retention lock and signed object index; pass tamper, delete-denial and read-back tests.
5. Complete isolated staging authentication/collector tests with OIDC and short-lived credentials.
6. DBA verifies backup/PITR and completes isolated restore rehearsal.
7. Resolve C517 migration provenance and PR #25 independently.
8. Only after separate explicit authorization may Production evidence collection/signing/storage be considered. No step in this report grants that authorization.
