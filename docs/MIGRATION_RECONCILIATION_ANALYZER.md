# DeedLight Production migration reconciliation analyzer

Status: security-remediation implementation with synthetic regression coverage. No Production evidence has been collected or classified by this tool. No Production SQL or migration-history mutation is performed.

## Security model

The analyzer does not accept a caller-supplied digest as authorization. Acceptance requires three independent Ed25519-signed artifacts whose signer keys are present in an independently provisioned trust-root bundle:

1. **Production evidence approval** (evidence-approver): binds the exact Production project, SHA-256 of the complete evidence payload, canonical migration mapping digest, read-only query-bundle digest, collector identity and capture timestamp.
2. **Migration mapping approval** (mapping-approver): binds the exact canonical mapping digest, pinned migration-inventory Git blob SHA-1, 39 migration count and 38 unique version count.
3. **Collector authority attestation** (collector): binds the exact project, query bundle, collector identity and capture timestamp, and attests the effective database role and privilege evidence.

The three roles must resolve to active Ed25519 keys with valid key validity windows and three distinct signer identities and key IDs. Evidence and collector approvals must be issued after the exact capture timestamp. Approval artifacts must have valid signatures, valid issue/expiry windows and non-revoked approval IDs. Key revocation is represented in the external trust-root bundle. Signer identity and role are checked against the root; a string in the evidence is not an identity proof.

### Independently provisioned trust roots

- Store the trust-root JSON outside the repository, installed through an independently controlled host/secret-management process.
- The trust-root bundle contains public keys only. Private signing keys remain in the relevant approval/collector signing systems and must never be copied to this repository or the evidence export.
- Provision DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256 through protected runtime configuration, independently of the evidence and approvals files. It is the SHA-256 of canonical JSON for the complete trust-root bundle, including revocations.
- The CLI refuses to run without this protected digest and refuses a trust-root file inside the repository. A changed trust-root bundle fails digest verification.
- The protected environment variable and installed trust-root file are operational trust anchors. A local operator who can change both is outside the analyzer's trust boundary; Production execution must use a controlled runner.

## Invocation

The default mode is acceptance mode:

    node scripts/reconcile-migration-evidence.mjs \
      --evidence=/secure/deedlight/evidence.json \
      --approvals=/secure/deedlight/approvals.json \
      --trust-roots=/etc/deedlight/migration-trust-roots.json \
      --mode=accept

Required environment variable: DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256.

- Exit 0 with acceptance: ACCEPTED only when all trust checks pass and no ambiguous, partial/drifted or unknown classifications remain.
- Exit 2 when acceptance mode encounters missing/invalid trust, incomplete evidence, unresolved duplicate 007 ambiguity, partial/drifted effects or unknown classifications.
- --mode=report emits the report with acceptance: NOT_ACCEPTED when unresolved findings remain. Its exit 0 means only that a report was generated; it does not mean reconciliation succeeded.
- The report always declares mutationPerformed: false.

The analyzer has no database client, network client, service-role credentials, migration repair path or SQL execution path.

## Signed artifact format

Each approval artifact has this envelope:

    {
      "schemaVersion": 1,
      "kind": "production-evidence-approval",
      "signerId": "provisioned-signer-identity",
      "keyId": "provisioned-key-id",
      "approvalId": "unique-revocable-approval-id",
      "issuedAt": "2026-11-25T01:00:00.000Z",
      "expiresAt": "2026-11-25T12:00:00.000Z",
      "claims": {},
      "signature": "base64-ed25519-signature"
    }

The Ed25519 signature covers canonical UTF-8 JSON of all fields except signature, with recursively sorted object keys and array order preserved. Signature verification uses Node's Ed25519 crypto implementation. Approval files and the evidence payload are untrusted until their signatures and claims are verified.

Evidence approval claims must equal, not merely contain: projectRef, evidenceDigest (SHA-256 of canonical complete evidence JSON), mappingDigest (SHA-256 of canonical mapping JSON), queryBundleSha256, collectorIdentity and capturedAt.

Mapping approval claims must equal: projectRef, mappingDigest, inventoryBlobSha1, migrationCount: 39 and versionCount: 38.

Collector attestation claims must equal the evidence project, query bundle, collector identity and capture timestamp, and include databaseAuthority:

- named effective database role
- isSuperuser, canCreateRole, canCreateDatabase, bypassRls, isReplication and ownsObjects all explicitly false
- aggregate effective privileges exactly CONNECT, USAGE and SELECT
- complete database-level privilege export containing CONNECT only
- complete per-schema privilege export containing USAGE only
- complete per-object privilege export containing SELECT only
- complete catalog privilege export containing SELECT only
- no inherited role memberships
- no owned schemas
- privilege proof query-bundle digest exactly matching the approved query bundle

A readOnly: true field is not accepted as evidence of authority. Collector attestation must be signed by a trusted collector identity, and its signed database-authority facts must be independently established by the approved collector query bundle.

## Evidence envelope

Evidence schema version 2 contains:

- provenance: environment production, exact project ref xaipiovflxomcbfwtwmu, capture timestamp, collector identity and query-bundle SHA-256.
- history: complete true and all rows with version, exact migration name, source blob SHA-1 when available, execution timestamp, executor and execution ID.
- catalog: complete true, complete attestation for every required object/effect kind and records with stable kind, identity and SHA-256 fingerprint.
- mapping: schema version 1 and the exact 39 migration effect entries.

Evidence must be no more than 24 hours old. Future timestamps, wrong project refs, incomplete history/catalog exports, malformed history names/versions, unrecognized versions, missing catalog dimensions, untrusted signers, invalid signatures, expired/revoked approvals, mismatched claims or trust-root digest mismatches fail closed to Unknown.

## Migration-effect mapping contract

Every one of the 39 migration source entries must bind its exact path and pinned Git blob SHA-1 and explicitly include all nine effect domains. Mapping top-level fields, migration-entry fields, effect-domain fields and individual effect fields are schema-allowlisted; unsupported extra fields or domains are rejected. An empty array is an explicit reviewer attestation that the migration has no effect in that domain; omitting a domain is invalid.

| Domain | Required coverage |
|---|---|
| schema | Tables, columns, constraints, indexes, triggers and policies |
| privileges | Grants, revokes, PUBLIC/anon/authenticated/service_role ACLs and effective access |
| ownership | Schema, relation and routine owners |
| routines | Function/procedure signatures, complete definitions, SECURITY DEFINER, configuration/search_path and ACLs |
| dataTransformations | Data transformations and resulting invariants |
| backfills | Backfill scope, completion evidence and postconditions |
| dependencies | Required/created dependencies and ordering constraints |
| preconditions | Preconditions required before applying the migration |
| postconditions | Assertions that must hold after application |

Each effect entry contains a supported kind, stable identity, SHA-256 fingerprint and reviewer-readable description. The mapping digest is computed over the complete canonical mapping and must match both the signed mapping approval and the signed evidence approval. A self-reported complete flag or hash is never authorization.

The mapping reviewer must inspect source SQL and document all effects. The analyzer does not infer complete SQL semantics using regex or claim that signatures prove the reviewer's judgment correct. The signed mapping approval is a governance attestation, not an automatic proof of semantic completeness.

## Catalog fingerprint contract

The approved collector and mapping reviewer must agree on canonical fingerprints:

- Tables: schema, relation name, persistence/partition attributes and relation definition.
- Columns: schema/table, ordinal, name, type, nullability, default, generated/identity attributes.
- Constraints: schema/table/name, type, validation/deferrability and canonical definition.
- Indexes: schema/table/name, uniqueness, validity/readiness, access method and canonical definition.
- Triggers: schema/table/name, enabled state, timing/events and canonical definition.
- Policies: schema/table/name, command, roles, permissive mode and USING/WITH CHECK expressions.
- Routines: schema/name/identity arguments, full definition, owner, SECURITY DEFINER, configuration/search_path and ACLs.
- Privileges and ownership: actual role grants, effective privileges and owner identity.
- Data transformations and backfills: independently queried result fingerprints and invariant evidence.
- Dependencies and lifecycle assertions: canonical dependency graph, precondition and postcondition results.

Routine ACL fingerprints must account for PUBLIC, anon, authenticated and service_role, plus relevant schema ACLs. Ownership/role membership evidence remains subject to independent security review. A routine's definition alone is not enough.

## Migration-history identity and classification

The analyzer separates schema representation, history recording and exact source execution:

- A history version is not enough. The migration name must match the source filename suffix.
- Exact execution requires one history row, exact version/name, exact source blob SHA-1 and valid execution timestamp, executor and execution ID.
- Matching catalog effects without exact execution metadata are classified as Schema represented but history ambiguous, never Applied and verified.
- Duplicate version 202607260007 always remains ambiguous, even if one history row matches one of the two filenames. A row cannot prove execution of both distinct source bodies.

Classifications:

- **Applied and verified**: authenticated complete mapping, all expected effects match, and exact source execution is established by unique history metadata.
- **Schema represented but history ambiguous**: all mapped effects exist but history is absent, non-unique, lacks exact source identity, or shares a duplicate version.
- **Verified unapplied**: authenticated complete history and effect exports show no history execution and no expected mapped effects.
- **Partial or drifted**: some effects are missing, an effect fingerprint conflicts, or history exists while mapped effects are incomplete.
- **Unknown**: trust, source, mapping, evidence or catalog checks are missing, malformed or ambiguous.

Acceptance mode fails on all unresolved ambiguity, including both duplicate-007 rows. Reporting mode is explicitly non-acceptance.

## Forward-only reconciliation proposal

1. Provision and independently approve the public trust-root bundle; protect its canonical SHA-256 in runtime configuration.
2. Obtain DBA-authorized read-only Production exports and signed collector attestation.
3. Have independent reviewers approve the full 39-migration effect mapping and sign its canonical digest.
4. Sign the exact evidence digest, mapping digest, query bundle, project, collector identity and capture timestamp.
5. Run acceptance mode and investigate every Unknown, Partial/drifted and ambiguous result.
6. Establish a verified backup/PITR restore point and rehearse restoration before any schema mutation.
7. For proven missing effects, prepare a new uniquely versioned, idempotent forward-only migration with preconditions, postconditions and data-preservation checks. Preserve historical source files.
8. Treat history-only correction as exceptional and separately DBA/security-approved. Never blindly mark 007 or protected migrations 036–038 applied.
9. Keep delivery disabled and schedulers paused during reconciliation. Capture before/after evidence and stop on unexpected drift.

## Current boundaries

No Production export, signed Production approval, trust-root installation, collector credential audit, schema classification, DBA authorization or migration-history mutation is included in this code change. Synthetic tests use ephemeral Ed25519 keys and disposable fixtures only. Their keys are not valid Production trust roots.
