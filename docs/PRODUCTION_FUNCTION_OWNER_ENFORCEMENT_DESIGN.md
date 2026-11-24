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

