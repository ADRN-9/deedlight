# DeedLight Production SECURITY DEFINER owner enforcement — technical design

**Status:** PROPOSAL ONLY — not approved for implementation  
**Prepared:** Cycle 378  
**Scope:** The 18 exact SECURITY DEFINER function identity signatures listed in `docs/PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md` Query 8A/8B  
**Production disposition:** NO-GO; no Production ownership evidence or approval was available to this cycle  
**Migration 038:** Out of scope and must remain unchanged

## 1. Purpose and non-goals

After authoritative Production Query 8A/8B evidence is collected and explicitly approved by the Production DBA and security approver, add an executable, fail-closed contract that detects drift in SECURITY DEFINER function ownership and owner-role membership.

This design does not select or predict any Production role name, owner mapping, membership path, or role attribute. It contains no approved Production identities. It does not authorize ownership changes, grants/revokes, migration execution, Production access, or changes to migration 038.

The policy is an attestation contract, not an automatic repair system. Drift must stop the migration/CI gate; it must never be silently corrected by reassigning owners, changing memberships, weakening privileges, or adopting the observed state as a new baseline.

## 2. Preconditions to implementation

Implementation is blocked until all of the following exist:

1. A verified Production target and read-only collection record for the intended project.
2. Exactly 18 accepted Query 8A rows, all exact signatures present and all SECURITY DEFINER.
3. Complete, untruncated Query 8B output reconciled against every distinct owner in Query 8A. A valid empty graph requires the explicit successful zero-row attestation described in the read-only audit checklist.
4. Explicit DBA and security approval for each of the 18 signature-to-owner mappings and every owner attribute.
5. Explicit DBA and security approval for the complete direct/transitive membership graph for every distinct owner, including INHERIT, SET and effective MEMBER/USAGE/SET semantics.
6. Named approvers, organizational roles, approval timestamps with timezone, immutable evidence references, and verified evidence hashes.
7. Independent security/database review of the final policy manifest and executable implementation.
8. A tested, documented migration-runner transaction/rollback contract.

Any missing, stale, conflicting, partial, or ambiguous input blocks implementation. CI synthetic roles can test mechanics only; they cannot fill any production mapping or approval field.

## 3. Authoritative policy model

The future policy must be version-controlled, immutable for a given migration/release, and reviewable in the PR. Prefer a literal, migration-owned policy manifest used by the verifier rather than deriving expected values at runtime from the current database. Do not let the verifier learn or update its own baseline from observed Production state.

### 3.1 Exact signature-to-owner mapping

Define one mapping entry for each of the exact 18 identity signatures in Query 8A:

- `identity_signature`: full schema-qualified PostgreSQL identity signature, including argument types.
- `expected_owner_role`: exact approved PostgreSQL role name.
- `approval_record_ref`: immutable protected evidence reference for the explicit per-function DBA/security approval.
- `policy_version`: immutable manifest/release identifier.

Enforce a bijection between the expected 18 signatures and the observed Query 8A inventory: exactly one policy entry and exactly one catalog function per signature. Do not match on routine name alone. Reject duplicates, missing entries, extra entries, unresolved `to_regprocedure` results, signature normalization ambiguity, missing owners, or non-SECURITY-DEFINER routines.

Several signatures may map to one approved owner if and only if each of those signatures has its own explicit approval. Do not infer that one approval automatically authorizes another function sharing the role.

### 3.2 Approved owner-role attributes

For each distinct expected owner role, retain the complete approved Query 8A role-attribute tuple:

- `rolsuper`
- `rolinherit`
- `rolcreaterole`
- `rolcreatedb`
- `rolcanlogin`
- `rolreplication`
- `rolbypassrls`

Compare the observed tuple exactly to the signed/approved tuple. Missing or NULL values fail closed.

At minimum, implementation must reject an owner with SUPERUSER, CREATEROLE, CREATEDB, REPLICATION or BYPASSRLS unless a separately documented security exception is explicitly authorized. The default proposed policy is to reject all five. Do not turn that default into a Production assertion until the DBA/security approvers have reviewed the actual attributes and signed the policy. `rolcanlogin` and `rolinherit` must also be explicitly approved; they must not be silently ignored or normalized.

An owner role's own attributes are distinct from attributes of roles it can reach through membership paths. Both sets must be validated.

### 3.3 Complete permitted membership-path manifest

For every distinct approved owner, define the complete set of allowed direct and transitive membership paths as observed and approved from Query 8B. A path entry must retain:

- Exact ordered `membership_path` role names.
- `depth` and direct/transitive classification.
- Exact `membership_edge_inherit_options` array for every edge.
- Exact `membership_edge_set_options` array for every edge.
- Effective `owner_is_member`, `owner_inherits_privileges`, and `owner_can_set_role`.
- Approved attributes for every granted role node on the path: superuser, inherit, create-role, create-database, login, replication and bypass-RLS.
- Protected approval reference and policy version.

Treat the membership graph as a set of full paths, not a set of endpoint role names. Preserve distinct paths that reach the same endpoint. Compare complete expected and actual path sets in both directions so that both added and removed paths are detected. Compare edge option arrays and effective privileges, not merely the existence of a membership.

A path is not harmless because its first edge has INHERIT disabled: a SET-enabled path may still allow role assumption. Likewise, an effective privilege result is not a substitute for retaining each path and edge option.

### 3.4 Explicit empty graph

An owner with no direct or transitive memberships may have an approved empty path set. This is an explicit policy value, not an absent manifest entry. The implementation must distinguish:
- Valid empty graph: successful complete Query 8B with verified zero rows and reconciliation to every distinct Query 8A owner, explicitly approved.
- Unknown graph: query failed, output unavailable, truncated, incomplete, not reconciled, or collection provenance missing.

Only the first may be represented as an approved empty set. Unknown must fail closed and must never be coerced to empty.

## 4. Enforcement algorithm

The verifier should run as a deterministic, read-only assertion over catalog metadata and the approved manifest:

1. Load the immutable policy version and verify its expected 18-signature inventory is exact and unique.
2. Resolve each identity signature with `to_regprocedure`; reject missing/ambiguous signatures.
3. Collect the actual function owner, SECURITY DEFINER status, exact catalog signature and all approved owner attributes.
4. Reject any signature-to-owner mismatch; do not issue `ALTER FUNCTION ... OWNER TO`.
5. Collect all direct/transitive membership paths for each distinct actual owner using PostgreSQL 16 membership edge options and effective `pg_has_role` semantics.
6. Normalize only representation details that are demonstrably equivalent (e.g. stable ordered arrays); never normalize away a role name, path, edge option or privilege.
7. Compare actual and approved owner attributes exactly.
8. Compare actual and approved complete membership path sets bidirectionally, including path order, edge INHERIT/SET options, effective privileges and role attributes.
9. Reject every unapproved path, missing approved path, changed option, changed effective privilege, changed role attribute, newly privileged role, and owner drift.
10. Emit a concise, non-sensitive failure identifying the signature/policy field that differs. Do not print credentials, member data, function bodies or unrelated catalog content.
11. Return success only when all 18 signatures, every distinct owner and the entire membership graph pass.

The verifier must not silently adopt the live catalog as policy, ignore an inaccessible role, fall back to a name-only check, or accept partial query results. It must fail closed on unsupported PostgreSQL versions, insufficient catalog visibility, malformed policy data, unknown role attributes, or incomplete result sets.

## 5. Privileged-role rejection

The default policy should reject owner roles with any of SUPERUSER, CREATEROLE, CREATEDB, REPLICATION or BYPASSRLS. The same privilege scan must cover every role node in every approved membership path, not only the final endpoint. A privilege reachable through a transitive path is still a privileged membership concern even if INHERIT is false; SET may permit assuming that role.

No privileged membership exception is implicit. Any proposed exception requires a written threat analysis, exact path/role scope, named DBA and security approval, expiry/review condition, and explicit policy representation. A broad exception for a role name or an entire owner is not acceptable.

## 6. Owner and membership drift rejection

The enforcement check must reject, at minimum:

- Owner role renamed, replaced, missing, or changed for any exact function signature.
- Function missing, duplicate policy identity, signature change, or SECURITY DEFINER disabled.
- Any owner role attribute changed from its approved value.
- Any newly added direct or transitive membership path.
- Any approved path removed or altered.
- Any changed INHERIT or SET edge option.
- Any changed effective MEMBER, USAGE/inherited-privilege or SET result.
- Any newly reachable privileged role or role-attribute change along a path.
- Any empty/non-empty graph mismatch.
- Incomplete or inconsistent catalog visibility or unsupported PostgreSQL semantics.

The verifier reports drift; it does not repair it. A correction requires a separately reviewed change and renewed approval evidence. Re-baselining requires the full Query 8A/8B evidence and approval procedure again.

## 7. Atomic migration and rollback behavior

The eventual enforcement migration should be assertion-only with respect to function ownership and memberships. It must not contain automatic `ALTER FUNCTION OWNER`, `GRANT`, `REVOKE`, role creation, or role-attribute mutation.

Required behavior:

- Run all preflight, manifest validation, owner checks and graph checks as one atomic migration unit.
- No policy baseline or success marker is committed before every assertion passes.
- Any mismatch raises an explicit exception and aborts the migration.
- On failure, PostgreSQL must roll back the entire migration unit; there must be no partial policy, DDL, ownership, membership or migration-history success state.
- The migration runner's actual transaction semantics must be verified for the supported Supabase CLI/deployment path. Do not assume a transaction boundary from local PostgreSQL behavior alone.
- Do not include non-transactional statements or external side effects in this migration.
- Prove the failure/rollback path in disposable PostgreSQL 16 and the actual supported migration runner before Production use.
- A failed migration is corrected in source and re-run only after review; do not use migration repair or manually mark it applied to bypass a failed assertion.

If the selected migration mechanism cannot guarantee atomic rollback for the intended statements, stop and redesign the mechanism before implementation.

## 8. PostgreSQL 16 positive and negative fixture matrix

Use only disposable PostgreSQL 16 identities and functions in CI. The fixture names are deliberately synthetic and must never be copied into the Production manifest.

### Positive fixtures

- All 18 exact identity signatures resolve, are SECURITY DEFINER and match the fixture's explicit per-signature owner mapping.
- Multiple functions sharing one fixture owner are each independently mapped.
- Owner attribute tuples match the fixture manifest exactly.
- Direct and transitive memberships match every approved fixture path and edge option.
- Distinct paths to the same role are both retained and accepted when both are present in the manifest.
- Effective MEMBER/USAGE/SET values match PostgreSQL's catalog-derived results.
- A successful zero-row Query 8B fixture is accepted only when every distinct fixture owner is reconciled and its empty graph is explicitly represented in the manifest.
- Full manifest and catalog match completes without side effects.

### Negative fixtures

- Each of the 18 signatures independently maps to a different unexpected owner.
- One missing function, one unexpected signature, duplicate manifest signature, missing owner, or non-SECURITY-DEFINER function.
- Each owner privilege independently enabled: SUPERUSER, CREATEROLE, CREATEDB, REPLICATION and BYPASSRLS.
- LOGIN or INHERIT attribute differs from the approved tuple.
- Privileged role introduced at a direct or transitive membership depth.
- Extra membership path, missing approved path, altered path order, or additional alternate path to an existing endpoint.
- INHERIT edge toggled; SET edge toggled; effective MEMBER/USAGE/SET changed.
- Membership path removed to create an unexpected empty graph, or path added to an explicitly approved empty graph.
- Query 8B query failure, incomplete/truncated fixture result, missing owner reconciliation, or unknown result coerced to empty.
- Unsupported PostgreSQL version or insufficient catalog visibility.
- Malformed/partial manifest or missing approval reference.
- Migration assertion failure proves all migration effects roll back atomically and no successful migration-history state is recorded.

Each negative test must assert the specific fail-closed diagnostic and verify the database state is unchanged after rollback. Positive and negative fixture tests are not evidence of Production ownership.

## 9. Review, release and operational boundaries

Before implementation PR approval:
- DBA verifies the 18 owner mappings and full membership graph against the protected evidence.
- Security reviewer independently verifies the privilege policy, path semantics and exception handling.
- Reviewer verifies the manifest contains exactly the approved evidence and no fixture-derived Production assumptions.
- CI executes all positive/negative PostgreSQL 16 tests and the migration-runner rollback test.
- PR remains draft until required approvals and exact-head CI are present.

Before any Production rollout:
- Confirm approved target and release scope.
- Obtain explicit Production change approval.
- Use the existing deployment controls and rollback procedure.
- Verify exact deployed commit and database migration outcome.
- Do not treat CI or source review as Production catalog evidence.

This design does not change migration 038, Production, PR merge status, secrets, credentials, or scheduler configuration.

## 10. Cycle 378 implementation-readiness decision

**Implementation readiness: BLOCKED — evidence and approvals absent.**

The technical enforcement shape is sufficiently specified for independent design review, but it is not ready for an implementation PR. The 18 expected owners, owner attribute tuples, permitted membership paths, empty-graph decisions, and DBA/security approvers must be populated only from accepted Production evidence and explicit approval. No role mapping has been guessed or created in this design.

### Cycle 379 handoff

1. Obtain the verified, least-privilege Production Query 8A/8B collection through the authorized DBA; do not attempt access by elevating permissions.
2. Apply the acceptance checklist in `docs/PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md`, including the 18-row count, complete Query 8B output, and explicit empty-result interpretation.
3. Obtain explicit per-signature owner approval and per-owner membership graph approval from named DBA and security approvers, with timestamps and protected evidence references.
4. Have independent reviewers approve the final owner-attribute and membership-path policy.
5. Only after those gates pass, create the exact approved manifest and implement the assertion-only enforcement with PostgreSQL 16 positive/negative fixtures and migration-runner atomic rollback tests.
6. Keep migration 038 unchanged, PR #22 OPEN / DRAFT / UNMERGED, and Production NO-GO until separately authorized.



---

## Cycle 382 — fail-closed manifest mechanics (not Production enforcement)

**Status:** executable structural validator added; Production policy remains NOT IMPLEMENTED and NO-GO.  
**Production project:** `xaipiovflxomcbfwtwmu`  
**Migration 038:** unchanged and out of scope.

### Added repository artifacts

- `scripts/verify-production-function-owner-manifest.mjs` exports `validateProductionOwnerManifest` and provides a CLI requiring explicit manifest, approvals and expected Production project reference.
- `scripts/test-production-function-owner-manifest.mjs` contains fixture-only positive and negative tests.
- `.github/workflows/pr-validation.yml` runs the fixture-only validator tests in the disposable PostgreSQL ownership-audit job before Query 8A/8B database behavior tests.

The validator requires exactly the 18 signatures already defined by the audited Query 8A contract; one exact function-to-owner mapping per signature; complete Query 8A evidence with exactly 18 rows; complete Query 8B evidence with an explicit distinct-owner count and owner reconciliation; complete owner records and explicit role attributes; complete per-owner membership path arrays and edge INHERIT/SET/effective privilege fields; and exactly two distinct-person approvals (Production DBA and security) for each function mapping, each owner attribute tuple, and each owner's full membership graph.

Each approval must bind to the exact Production project, both Query 8A/8B SHA-256 values, the immutable policy version, and a SHA-256 digest of the exact approved policy value. The validator rejects absent/partial arrays, duplicates, unexpected/missing signatures, unknown or incomplete graphs, mismatched counts, malformed evidence metadata, privileged owner/path role attributes, incomplete approval coverage, mismatched evidence hashes, and approvals from the same person. It never derives an owner mapping from a live database.

### Invocation after authoritative evidence exists

Keep the Production manifest and approvals outside the repository in the approved protected evidence store. A future authorized operator can run:

```sh
node scripts/verify-production-function-owner-manifest.mjs \
  --manifest /protected/path/production-owner-manifest.json \
  --approvals /protected/path/production-owner-approvals.json \
  --expected-project-ref xaipiovflxomcbfwtwmu
```

No Production manifest or approval document is present in this PR. No placeholder manifest is checked in. Fixture names such as `fixture_owner_only` and `Fixture DBA` exist only in the test file and are explicitly not Production expectations.

### Security boundary and known limitation

This is a **structural completeness and policy-value binding gate**, not a cryptographic approval verifier or live catalog drift checker. It validates that referenced evidence/approval hashes are well-formed and consistently bound; it does not retrieve protected evidence, recompute hashes from the external artifacts, authenticate the approver's identity/signature, or prove that a human approval is genuine. Those checks must be performed by the authorized evidence custodian and independent reviewers before accepting the protected records. It also does not connect to Production or compare live catalog state with the manifest. A later, separately approved read-only catalog verifier remains necessary before any enforcement migration.

The fixture suite tests the mechanics only. It cannot satisfy Query 8A/8B, authorize Production owner mappings, or change the implementation-readiness gate. Migration 038, Production, branch targets and PR merge state remain untouched.

### Cycle 383 handoff

1. Verify exact-head CI for the commit that adds this validator and fixture suite; record every job result.
2. Review validator behavior and its stated structural-only limitation. Extend negative fixtures if review finds a missing fail-closed case.
3. Keep the Production manifest and approvals absent until authorized Query 8A/8B evidence and explicit DBA/security approvals exist.
4. Recheck whether a human-controlled DBA has granted least-privilege read-only access to project `xaipiovflxomcbfwtwmu`; the connected Supabase accounts currently do not.
5. Do not modify migration 038, merge/retarget PR #22, or run Production SQL/deployment. Production ownership enforcement and release remain NO-GO.


### Query 8B evidence shape clarification

Cycle 382 extended the Query 8B SELECT result with `membership_path_role_attributes`, an ordered array containing the seven role attributes for every role node in the path, including the owner and intermediate roles. Endpoint-only role attributes are insufficient to validate transitive paths. The manifest validator requires each path role-attribute record to name the corresponding role node and rejects positional/name mismatches. Query 8B's row count is the count of returned owner-to-endpoint membership paths; each path retains its full ordered role sequence and edge option arrays.


---

## Cycle 384 — cryptographic approval and evidence verification

**Implementation status:** repository verifier and disposable fixture tests added. **Production acceptance remains BLOCKED / NO-GO.** No Production key, identity, approval, owner mapping, or evidence artifact has been created or assumed.

### New executable artifacts

- `scripts/verify-production-owner-approval-bundle.mjs` exports `verifyProductionOwnerApprovalBundle` and provides a CLI.
- `scripts/test-production-owner-approval-bundle.mjs` creates ephemeral Ed25519 keypairs and fixture identities at test runtime. No fixture private key or public key is a Production trust anchor.
- The ownership-audit CI job runs the new test suite before the existing PostgreSQL 16 ownership-audit harness.

Invocation after the Production authority and protected evidence bundle exist:

```sh
node scripts/verify-production-owner-approval-bundle.mjs \
  --artifact-root /protected/deedlight-owner-evidence \
  --manifest manifest.json \
  --approvals approvals.json \
  --trust-root trusted-identity-registry.json
```

The artifact root is an explicitly provisioned local protected directory. All artifact references are normalized relative paths under that root. The verifier performs no HTTP, DNS, URL fetching, database connection, or arbitrary remote-reference resolution. It rejects absolute paths, traversal, backslashes, symlinks, non-regular files, non-canonical JSON, and artifacts larger than 25 MiB. The CLI accepts no URL-based artifact locator. The trust root and its delivery channel must be provisioned out-of-band by the approved evidence custodian; putting a trust root in this PR would defeat the trust boundary.

### Approval cryptography and identity boundary

Only Ed25519 signatures are supported. Each individual signed approval payload must bind:

- Unique approval ID and nonce.
- Exact Production project reference.
- Individual policy version.
- SHA-256 of the complete canonical immutable manifest.
- Actual Query 8A and Query 8B result SHA-256 values.
- Scope, subject, owner role, and exact approved-value digest.
- Trusted identity ID, trusted key ID, and asserted approver role.
- Explicit approval decision, approval timestamp, and expiration timestamp.

The verifier checks the signature over canonical payload bytes against an explicitly supplied trusted key registry. The registry binds key IDs to identity IDs and active key material; a separate identity record must authorize the asserted `production_dba` or `security` role. Key validity intervals, identity activation, key revocation, approval revocation, expiration, and consumed approval IDs are checked. Unsupported algorithms and absent trusted keys fail closed. Approvals are still required in the exact DBA/security pairs enforced by the existing manifest validator.

**Trust boundary:** a valid Ed25519 signature proves control of a private key, not a person's legal identity or authority by itself. A human-controlled Production/security authority must authenticate approvers, approve identity-to-role assignments, securely provision public keys, and distribute the trusted registry through an independent protected channel. The repository contains no Production public keys or identities. No authorized approval authority or trust registry was available for this cycle, so no Production signature could be verified and Production acceptance remains blocked.

### Approval artifact and evidence byte integrity

The trusted registry contains an explicit SHA-256 index for the complete approval artifact, both exact SQL query files, and both raw query-result files. The verifier hashes the bytes actually read from disk and compares them to that independently provisioned index. It also compares result bytes with the hashes embedded in the manifest and signed by every approval. Approval artifact tampering, evidence substitution, SQL substitution, malformed canonical JSON, missing files, and hash mismatch all fail closed.

Query execution metadata must include exact project reference, query ID/version, execution ID, collector identity, execution principal, PostgreSQL server version, timestamp with timezone, successful/complete/untruncated status, explicit read-only transaction and role attestations, result row count, SQL path/hash, and raw result path/hash. Collector identities and read-only execution-principal names must both be explicitly allowlisted in the trusted registry. The SQL and result artifacts must be indexed by the trusted evidence custodian.

Query 8A bytes are parsed and checked for all 18 exact signatures, `PRESENT`, SECURITY DEFINER true, resolved owners, and all seven role attributes. Query 8B bytes are parsed and reconciled to the exact distinct Query 8A owner set. Every actual path, intermediate role attribute, INHERIT/SET edge option, and effective MEMBER/USAGE/SET result must equal the approved manifest graph. The query SQL itself is hashed and checked for the required 18-signature or recursive-membership inventory.

A zero-row Query 8B result is accepted only when the actual result file is an empty array and the manifest includes a successful zero-row attestation bound to the exact execution ID, query hash, result hash, collector identity, timestamp, all-owner coverage, and reason. An absent result, failed query, truncated result, or unqueried owner cannot be represented as an empty graph.

### Replay, expiry and revocation

Duplicate approval IDs within one artifact, approvals signed for a different manifest or policy version, expired/not-yet-valid approvals, revoked key IDs, revoked approval IDs, and IDs already listed as consumed by the trusted authority are rejected. The verifier is deliberately read-only: it does not mutate a consumption ledger. The protected authority must atomically record approval IDs as consumed in its trusted registry after the separately approved acceptance event. Without that authoritative consumption update, the verifier cannot claim global one-time-use semantics across separate verifier invocations.

### Artifact handling and SSRF boundary

No arbitrary URL is fetched. A URI-looking legacy evidence reference is not resolved by this verifier and is not a substitute for local evidence bytes. Files must be staged into the protected artifact root by an authorized evidence custodian; the trust registry records their exact relative paths and hashes. The implementation rejects path traversal and symlinks and caps each file at 25 MiB. The trust registry itself is a trust anchor and must be delivered out-of-band with protected write access; an attacker able to replace both the registry and bundle is outside the verifier's local trust boundary and must be addressed by the custodian's access controls and independent verification.

### Separate read-only live catalog comparison design

A future catalog verifier must be a separately reviewed, read-only operation, not part of this approval-bundle verifier:

1. The DBA independently confirms the exact project reference `xaipiovflxomcbfwtwmu`, PostgreSQL 16+, the named read-only collector, catalog visibility, and a read-only transaction. Use one repeatable-read, read-only transaction for Query 8A and Query 8B where the approved connection permits it; capture transaction/server identity and timestamps.
2. Query 8A produces the live 18-signature set. Normalize by exact identity signature and compare expected-to-actual and actual-to-expected. Report missing signatures, unexpected signatures, SECURITY DEFINER drift, owner-role drift, and each of the seven owner-attribute differences. Never silently drop unresolved functions or owners.
3. Query 8B produces the complete live owner membership graph. Normalize each owner-to-granted-role path as ordered role names, every edge INHERIT/SET option, every path-node attribute tuple, and effective MEMBER/USAGE/SET booleans. Compare both directions (expected EXCEPT actual and actual EXCEPT expected, or equivalent canonical set comparison) so both missing approved paths and unexpected live paths are detected. Preserve multiple distinct paths to the same endpoint.
4. Explicitly include every distinct Query 8A owner in the Query 8B coverage declaration. A zero-row graph is a valid empty graph only if the query succeeded, was complete/untruncated, queried every owner, and its zero-row attestation is accepted. Unknown or missing owners are not empty.
5. Return a read-only drift report with exact evidence hashes and counts. Any mismatch, incomplete result, unknown role, privileged attribute, unsupported catalog version, or uncertain project identity fails closed. The verifier must never execute ALTER OWNER, GRANT, REVOKE, CREATE ROLE, migration SQL, or any other mutation.
6. Independent DBA and security review must approve the expected manifest and the drift report before a separate enforcement implementation is considered. Migration 038 remains unchanged until that later approved contract exists.

### Cycle 384 acceptance disposition and blockers

- **P0 — Production authority/trust bootstrap absent:** no human-authorized DBA/security identity registry, trusted Ed25519 public keys, collector registry, read-only principal allowlist, or protected trust-root delivery channel is available. Exact dependency: the DeedLight Production organization/project administrator and security owner must authenticate named approvers, designate the collector, approve their roles, provision public keys, define key rotation/revocation, and establish protected trust-root/evidence custody.
- **P0 — Query 8A/8B Production evidence absent:** the last verified access investigation (Cycle 382, 2026-11-24) found both connected Supabase accounts unable to discover or read project `xaipiovflxomcbfwtwmu`. Cycle 384 did not acquire new access or execute Production SQL. The 18-row Query 8A result and complete Query 8B membership graph remain NOT COLLECTED.
- **P1 — Global replay consumption is externally managed:** the verifier rejects duplicate, cross-manifest, expired, revoked and already-consumed approvals; a protected authority must maintain and atomically update the consumed-ID registry. The verifier itself never writes trust state.
- **P1 — Live catalog drift verifier not implemented:** this cycle specifies the separate read-only bidirectional comparison design but does not query Production or add an owner-enforcement migration.
- **P2 — Trust-root authenticity is an operational root-of-trust dependency:** the registry is not self-authenticating. Its source, delivery, review and write permissions must be controlled independently of the bundle and repository.

### Cycle 385 handoff

1. Review the verifier and the exact-head CI run; do not claim tests PASS until all jobs complete successfully for the final SHA.
2. Obtain an explicit human-controlled Production/security authority for approver identity proofing, key provisioning, collector authorization, trust-root distribution, and revocation/consumption operations.
3. Obtain the authorized read-only Production connection, collect Query 8A/8B, and preserve exact SQL/result bytes plus execution provenance in the protected evidence root.
4. Independently review the trust root, approval artifacts, manifest digest, and evidence custody before accepting any signature.
5. Implement the separate read-only bidirectional live-catalog comparison only after authoritative evidence exists.
6. Preserve migration 038, PR #22's base on PR #10, and Production NO-GO. No merge, retarget, deployment, Production SQL, or ownership change is authorized.


### Cycle 384 verifier operational safeguards

The production CLI does not accept a caller-supplied verification clock; it uses the current system time for expiry and key-validity checks. The exported API's `asOf` injection exists for deterministic tests and must not be used to backdate a Production acceptance. The trusted registry also requires a read-only execution-principal allowlist, not merely a caller-provided `roleReadOnly` boolean. Approval nonces must be unique and canonical, in addition to unique approval IDs. The local artifact reader uses no-follow file opens for the final path component and verifies regular-file type and size after opening.
