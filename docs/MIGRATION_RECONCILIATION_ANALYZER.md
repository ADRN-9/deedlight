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
- --mode=report always emits executionMode: REPORT_ONLY, acceptance: REPORT_ONLY, the separate underlying analysisAcceptance, and reconciliationAccepted: false. Its exit 0 means only that a report was generated; it never represents successful reconciliation, even if the findings happen to be clear.
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

The Ed25519 signature covers canonical UTF-8 JSON of all fields except signature, with recursively sorted object keys and array order preserved. The envelope must contain exactly the documented fields and a non-array claims object; missing claims and arbitrary approval-reference fields are rejected. Signature verification uses Node's Ed25519 crypto implementation. A single Ed25519 public key may not be reused across the evidence approver, mapping approver and collector trust identities; all three approval IDs, signer identities and key IDs must be distinct. Approval files and the evidence payload are untrusted until their signatures and claims are verified.

Evidence approval claims must equal, not merely contain: projectRef, evidenceDigest (SHA-256 of canonical complete evidence JSON), mappingDigest (SHA-256 of canonical mapping JSON), queryBundleSha256, collectorIdentity and capturedAt.

Mapping approval claims must equal: projectRef, mappingDigest, inventoryBlobSha1, migrationCount: 39 and versionCount: 38.

The evidence envelope also contains collectorAuthority: a completed, read-only query execution record bound to the exact Production project, query bundle, collector identity, capture timestamp and unique execution ID. The collector's Ed25519 attestation binds the full evidence digest, the canonical digest of this authority record, and the execution ID. The authority record contains an exact execution receipt with start/completion timestamps, statement count, read-only transaction assertion, query-bundle digest, project, collector, capture time and a result digest over the complete migration-history export, catalog export and effective database-authority result. The result digest is checked against those exact evidence objects; a self-reported execution ID or isolated privilege result is insufficient. The signed database-authority facts must exactly equal the evidence-bound query result; changing either side invalidates the binding. The evidence approver independently signs the complete evidence digest, including the collector authority record.

Collector attestation claims must equal the evidence project, query bundle, collector identity and capture timestamp, and include databaseAuthority:

- named effective database role
- isSuperuser, canCreateRole, canCreateDatabase, bypassRls, isReplication and ownsObjects all explicitly false
- aggregate effective privileges exactly CONNECT, USAGE and SELECT
- complete database-level privilege export containing CONNECT only
- schema privilege rows whose exact, duplicate-free schema identity set equals the schema objects in the complete catalog export, with USAGE only
- table/sequence/routine privilege rows whose exact, duplicate-free kind-and-identity set equals the complete catalog export; tables and sequences have SELECT only, routines have no EXECUTE privilege
- catalog read privilege export containing SELECT only
- no inherited role memberships
- no owned schemas
- privilege proof query-bundle digest exactly matching the approved query bundle

A readOnly: true field and self-declared completeness booleans are not accepted as evidence of authority. Exact schema/object privilege identity sets are compared to the catalog inventory, duplicate/omitted/unexpected identities fail closed, and the collector signature binds the full query result digest. Collector attestation must be signed by a trusted collector identity, and its signed database-authority facts must be independently established by the approved collector query bundle. The execution receipt requires startedAt <= completedAt <= capturedAt <= now; every migration history row requires executedAt <= capturedAt <= now.

## Evidence envelope

Evidence schema version 2 contains:

- provenance: environment production, exact project ref xaipiovflxomcbfwtwmu, capture timestamp, collector identity and query-bundle SHA-256.
- history: complete true and all rows with version, exact migration name, source blob SHA-1 when available, execution timestamp, executor and execution ID.
- catalog: stable kind, identity and SHA-256 fingerprint records plus an exact required-kind dimension list, all bound into the signed collector query-result digest. A boolean complete flag is not used as proof.
- collectorAuthority: exact read-only privilege-query execution metadata and the databaseAuthority result bound by the trusted collector signature.
- mapping: schema version 1 and the exact 39 migration effect entries, including source-linked review dispositions for all nine domains.

Evidence must be no more than 24 hours old. Future timestamps, migration execution after capture, capture after the current time, query completion after capture, wrong project refs, incomplete history/catalog exports, malformed history names/versions, unrecognized versions, missing catalog dimensions, untrusted signers, invalid signatures, expired/revoked approvals, mismatched claims or trust-root digest mismatches fail closed to Unknown.

## Migration-effect mapping contract

Every one of the 39 migration source entries must bind its exact path and pinned Git blob SHA-1 and explicitly include all nine effect domains. Each entry also contains a coverage record for every domain. Every coverage record must declare disposition: effects when effects are mapped or disposition: none when the domain is empty, include a substantive reviewer rationale, and cite one or more valid source line ranges within that exact migration file. An empty effects array without a source-linked no-effect review is invalid. Mapping top-level fields, migration-entry fields, effect-domain fields, coverage records and individual effect fields are schema-allowlisted; unsupported extra fields or domains are rejected.

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

The mapping reviewer must inspect source SQL and document all effects and explicit no-effect domains. The analyzer verifies complete structural coverage, source ranges, canonical digest and the trusted signature. It does not infer complete SQL semantics using regex or claim that signatures alone prove the reviewer's judgment correct. The signed mapping approval is a governance attestation by an independently trusted mapping authority, not an automatic proof of semantic completeness.

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
- Exact execution requires one history row, exact version/name, exact source blob SHA-1 and valid execution timestamp, nonempty executor and execution ID, and a unique execution ID across the complete history export.
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


## Cycle 407 source review and evidence boundaries

The 39 migration SQL files were inspected at the pinned source revision. The following is a source-review index of the concrete SQL effect families observed; it is not a signed migration-effect mapping, a catalog fingerprint set, or an independent semantic approval. Exact object identities, before/after definitions, effective ACLs, ownership, data invariants and dependency edges still require a separately reviewed canonical mapping and Production catalog evidence.

| Migration source | Observed SQL effects requiring mapping |
|---|---|
| 001 initial schema | pgcrypto extension; profiles, themes, daily_posts, offerings, reactions, reflections, reports, badges, user_badges, saved_lights and daily_deed_completions; indexes, foreign keys, updated-at and counter triggers; signup/reaction/reflection/report functions; counter data updates; offerings_public view |
| 002 RLS policies | is_admin function; RLS enablement and policies across core tables; storage bucket insert and storage.objects policies |
| 003 offering review | offering indexes; offerings_public view replacement; view SELECT grant |
| 004 reactions | schema/table/function grants; is_admin and reaction counter function; counter updates and triggers; reactions RLS/policies; rising view and grant |
| 005 moderation | report/offering indexes; grants; is_admin and report counter functions; report/offering RLS and policies; counter triggers and data updates |
| 006 admin hotfix | preflight DO block; offerings column/constraint changes; grants and update policy; public view replacement |
| 007 Sprint 6 daily deed | pgcrypto; daily_posts and daily_reflections tables/columns/FKs/indexes; updated-at triggers; RLS/policies/grants; helper functions; daily_posts seed insert |
| 007 Sprint 7 PWA | daily_lights and daily_reflections tables/columns/FKs; existing-row updates/defaults/constraints; indexes; RLS/policies/grants |
| 008 short video | daily_lights video columns/defaults/constraints/indexes; existing-row data update; grants |
| 009 profiles privacy | profile column/username changes and data normalization; indexes; signup function; profile/offering policy changes; revoke/grant changes; profiles_public and offerings_public views |
| 010 identity consistency | signup function; offerings_public and offerings_rising views; view grants/revokes |
| 011 moderation-aware members | member_moderation_events table/index/RLS; admin member/context/suspension functions; profile suspension update and audit insert; offering/reflection policy changes; function ACLs |
| 012 daily completion | daily_deed_completions and daily_reflections column/constraint/index changes; policies; completion-count view; grants |
| 013 saved Lights | saved_lights column/constraint/index changes; RLS/policies and grants |
| 014 reminder preferences | daily_reminder_preferences table; updated-at trigger; RLS/policies and grants |
| 015 Weekly Goodness | reaction index; weekly_goodness_features table/trigger; weekly read/curation functions; feature delete/insert/update data changes; function ACLs |
| 016 invitations/newsletter | invitation_links, invitation_acceptances and newsletter_preferences tables/indexes/triggers/RLS; default preference data; invitation and newsletter functions; auth signup triggers; grants |
| 017 Offering ownership | offerings owner/removal fields and index; offering/reaction policies; update/remove/restore functions and ACLs; offering row updates |
| 018 removal guard | preflight checks; offering constraints; guarded remove function replacement and ACL |
| 019 delivery foundation | reminder preference function; delivery_ledger table/indexes/trigger/RLS; daily/weekly enqueue, claim, authorization, sent and failure functions; queue inserts/updates |
| 020 delivery reliability | ledger preflight/columns/index; claim/authorize/retry/sent/failure function replacements and ledger state updates |
| 021 transport | ledger transport-state change; begin_delivery_transport and curated weekly enqueue functions; ACLs |
| 022 pgcrypto qualification | preflight and signup function replacement with qualified extension references |
| 023 consent linearization | daily/weekly enqueue and begin transport function replacements; ledger updates; function ACLs/comments |
| 024 lease capacity | begin transport signature replacement and lease/state updates; weekly enqueue/curation function replacements; ACLs |
| 025 provider webhooks | provider events/suppressions tables, indexes and RLS; webhook event function; daily/weekly enqueue and transport function replacements; event/suppression/ledger inserts and updates |
| 026 provider lifecycle | event constraints; provider lifecycle table/index/RLS; lifecycle and event function replacements; lifecycle/suppression inserts and updates; ACLs |
| 027 provider integrity | event/lifecycle constraints; integrity anomaly table/index/RLS; event/lifecycle/suppression function replacements; anomaly/lifecycle/suppression writes; routine ACLs and comments |
| 028 claim expiry | authorize/retry/sent/failure function replacements; claim-token, lease-expiry and ledger state updates; service-role-only ACLs |
| 029 legacy replay guard | preflight; legacy lifecycle implementation rename/wrapper; routine ACLs and comments |
| 030 idempotency receipt guard | preflight; idempotency-window function; retry and sent function replacements; failed/queued ledger state transitions; ACLs/comments |
| 031 final recipient suppression | preflight; idempotency authorization replacement; recipient suppression checks and ledger failure/state updates; ACLs |
| 032 Resend suppression sync | provider event/anomaly constraints; suppression-state table/index/RLS; suppression event function; event/anomaly/lifecycle/state/suppression writes and deletes; ACLs |
| 033 cross-stream suppression order | preflight; lifecycle event function replacement; suppression ordering/deletion logic; ACLs/comments |
| 034 suppression timestamp order | suppression-order index; suppression event function replacement; event/anomaly/lifecycle/state/suppression writes and deletes; ACLs/comments |
| 035 private Offering base RLS | removal of broad/public Offering SELECT policies |
| 036 private Daily Reflection | daily_reflections constraints/policy replacement; owner-only select/insert/update policies; privilege revokes/grants |
| 037 provider conflict evidence | preflight; integrity cases/evidence/history tables, indexes, RLS and immutable audit triggers; conflict capture/resolution functions; lifecycle/suppression wrappers; audit/history inserts and case/lifecycle updates; routine ACLs |
| 038 provider lock order/pagination | preflight; integrity cursor/history indexes; lifecycle/event/suppression function replacements; paginated admin conflict/detail/evidence/history functions; service-role ACLs |


Source anchor register (line numbers refer to the exact pinned migration files; anchors are review starting points, not an exhaustive substitute for per-effect records):

| Migration file | Reviewed source anchors |
|---|---|
| 202607210001 | L1-L335 |
| 202607210002 | L1-L180 |
| 202607220003 | L4-L38 |
| 202607260004 | L5-L146 |
| 202607260005 | L5-L180 |
| 202607260006 | L5-L76 |
| 202607260007 Sprint 6 | L4-L202 |
| 202607260007 Sprint 7 | L3-L153 |
| 202607270008 | L6-L47 |
| 202608060009 | L6-L233 |
| 202608100010 | L8-L130 |
| 202608100011 | L11-L459 |
| 202608110012 | L13-L175 |
| 202608110013 | L12-L116 |
| 202608120014 | L7-L98 |
| 202608130015 | L12-L290 |
| 202608130016 | L9-L439 |
| 202608130017 | L11-L445 |
| 202608140018 | L8-L118 |
| 202609230019 | L11-L573 |
| 202609230020 | L10-L485 |
| 202609230021 | L6-L116 |
| 202609240022 | L13-L28 |
| 202611120023 | L5-L292 |
| 202611120024 | L3-L322 |
| 202611190025 | L6-L488 |
| 202611190026 | L4-L400 |
| 202611200027 | L5-L602 |
| 202611210028 | L5-L212 |
| 202611210029 | L5-L169 |
| 202611210030 | L3-L211 |
| 202611220031 | L5-L184 |
| 202611220032 | L5-L384 |
| 202611220033 | L5-L123 |
| 202611230034 | L5-L310 |
| 202611230035 | L9-L12 |
| 202611230036 | L7-L75 |
| 202611240037 | L7-L1161 |
| 202611240038 | L5-L1025 |

This source review identifies operation families and data-write sites, but does not prove the semantic result of dynamic SQL, DO blocks, conditional DDL, existing-row transformations, trigger side effects, ownership inheritance or effective role grants. Those require line-specific canonical effect records and independently reviewed fingerprints. The analyzer's synthetic fixtures deliberately do not claim to model these 39 actual migration effects.

## Controlled Production trust-root provisioning

Trust roots are authorization configuration, not evidence supplied by the candidate being evaluated. The CLI requires both an external trust-root file and a separately provisioned `DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256` digest. The file must resolve outside the repository; missing configuration, a repository-contained path, malformed digest, digest mismatch, untrusted key, revoked key or expired approval fails closed.

Provisioning procedure (operator/DBA/security approval required; not performed by this change):

1. Generate three independent Ed25519 key pairs in an approved KMS/HSM or controlled offline signing environment for the evidence approver, mapping approver and collector. Never commit private keys or place them in the evidence bundle.
2. Independently verify signer identities, role assignments, key custody, validity intervals, revocation contacts and separation of duties. Do not reuse a public key across roles.
3. Export only the public keys and their status/validity metadata into the trust-root JSON. Keep the canonical trust-root SHA-256 in protected deployment/runner configuration managed outside repository-controlled files and CI artifacts.
4. Place the public trust-root JSON in a read-only path outside the repository on the controlled acceptance runner. Set `DEEDLIGHT_MIGRATION_TRUST_ROOTS_SHA256` through protected configuration, not command-line arguments or evidence metadata.
5. Have the DBA/security approvers independently sign a change record for the public-key bundle and digest. Test rotation/revocation with synthetic keys before using Production authorities.
6. Restrict access to the runner, trust-root file, protected digest, signing service and resulting audit logs. Rotate/revoke compromised keys and approval IDs promptly; fail closed while the trust configuration is unavailable.

No Production trust roots, signing credentials, protected configuration, approvals or collector identities were provisioned or changed during Cycle 407.
