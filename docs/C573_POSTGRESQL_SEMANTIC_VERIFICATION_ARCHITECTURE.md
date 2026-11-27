# C573 — PostgreSQL semantic-verification architecture and acceptance specification

**Status:** Proposed architecture; implementation NOT PRESENT; Production acceptance NO-GO  
**Project:** DeedLight  
**PR context:** #29, stacked feature branch  
**Inspected PR HEAD:** `2133cee1439287399740bf9794bbb0b4e793105c`  
**Inspected PR base:** `0e5bf38f1fdd67300825ecdf29555aa1ff3674b7`  
**Migration inventory blob:** `4e63f31368d446e905f4f44565be73337c7188fb`

This document specifies a future implementation and its acceptance gates. It does not claim that PostgreSQL AST parsing, semantic resolution, semantic approval, or semantic execution evidence currently exists. No Production database, migration history, trust root, key, or credential was changed or provisioned for C573.

## 1. Executive decision

The current migration evidence pipeline is deliberately fail-closed. It pins 40 migration source files, validates source excerpts and typed category contracts, verifies signed evidence envelopes against externally provisioned trust roots, and limits live catalog authorization to `catalog_only_v1`. It does not parse PostgreSQL into ASTs, resolve SQL names against a point-in-time schema, or establish non-catalog semantic effects.

C573 defines a separate semantic-verification layer. It must not broaden the existing catalog contract or reinterpret source inspection as execution proof.

**Acceptance invariant:** a non-catalog category is accepted only when its exact source bytes have been parsed by a version-pinned PostgreSQL-compatible parser, all relevant semantics have been resolved against an identified catalog state, all unsupported constructs are explicitly accounted for, and a separately authorized reviewer has signed an approval bound to the exact parser, resolver, source, AST, and result identities. Any unsupported, unresolved, ambiguous, unsigned, stale, or unverifiable result remains `UNKNOWN` and blocks acceptance.

A signed declaration that a category is `none`, an empty effects array, a matching digest, a regex match, or a migration-history row is never semantic proof.

## 2. Existing baseline and preserved invariants

### 2.1 Verified repository facts at inspection

- PR #29 was open and unmerged when inspected.
- Its head branch was `fix/c558-pr28-security-remediation`; the exact PR API head SHA was `2133cee1439287399740bf9794bbb0b4e793105c`.
- Its base SHA was `0e5bf38f1fdd67300825ecdf29555aa1ff3674b7`.
- The inspected implementation includes `scripts/reconcile-migration-evidence.mjs`, `scripts/migration-effect-contracts.mjs`, the collector and adapter, and the C556/C570 contract documentation.
- The inventory manifest is pinned to blob `4e63f31368d446e905f4f44565be73337c7188fb`, with 40 paths and 39 unique version identifiers.
- The intentional duplicate version is `202607260007`, with both `202607260007_sprint6_daily_deedlight.sql` and `202607260007_sprint7_pwa_daily_engagement.sql`.
- Migration 039, `202611260039_delivery_kind_scoped_claims.sql`, remains an inventory entry.
- The existing analyzer's semantic-verification state is `UNKNOWN` while any non-catalog evidence is unresolved.

These are repository/API observations, not local test results or Production execution claims.

### 2.2 Invariants that must not change

1. Preserve the exact 40 inventory entries, paths, blob identities, byte lengths, and deterministic inventory checks.
2. Preserve both Migration 007 source files as distinct source identities. Never collapse them into one file or infer which body ran from the shared version string.
3. Preserve Migration 039 and its exact source identity.
4. Preserve strict migration-history ordering and SQL NULL distinctions.
5. Preserve `catalog_only_v1` and its existing eleven catalog kinds: schemas, tables, sequences, columns, constraints, indexes, triggers, policies, routines, privileges, and ownership.
6. Do not flatten transformations, backfills, dependencies, preconditions, or postconditions into catalog objects.
7. Do not accept unsigned evidence, signed absence declarations as semantic proof, or repository-held trust roots.
8. Do not infer historical execution from source inspection, AST generation, source digests, parser output, or a migration-history row.
9. Do not mutate Production migration history or run normal Production `supabase db push` as part of semantic analysis.
10. Fail closed when the parser, resolver, catalog snapshot, extension behavior, dependency graph, approval, or evidence provenance is missing or ambiguous.

## 3. Target architecture

The semantic pipeline is a new, separately versioned capability. It is not a replacement for the collector's catalog-only contract.

```text
Pinned 40-entry inventory
        |
        v
Exact source-byte verifier
  Git blob SHA-1 + source SHA-256
        |
        v
PostgreSQL-major-pinned parser
  SQL AST + PL/pgSQL analysis
        |
        v
Canonical AST artifact
  parser identity + grammar version + AST digest
        |
        v
Point-in-time semantic resolver
  catalog snapshot + search_path + roles
  types + operators + functions + extensions
        |
        v
Migration-order / dependency graph
  object identity + create/use/drop edges
        |
        v
Per-migration semantic result
  supported / unsupported / unknown
        |
        v
Independent semantic reviewer approval
  detached signature over exact artifact claims
        |
        v
Read-only analyzer integration
  catalog_only_v1 remains unchanged
  any unknown => NOT_ACCEPTED
```

The parser, semantic resolver, and reviewer have different responsibilities:

- **Parser:** determines syntactic structure under a specific PostgreSQL grammar. It does not establish that a name resolves or that a statement executed.
- **Semantic resolver:** resolves names, types, operators, routines, dependencies, and effects against a defined catalog state and role/search-path context. It must not silently guess.
- **Reviewer:** evaluates the resulting semantic artifact and source-specific interpretation. The reviewer cannot approve an artifact whose parser/resolver output is incomplete or unsupported.
- **Execution evidence collector:** if later introduced for backfills or predicates, independently establishes a bounded read-only observation. It is separate from source-semantic analysis and is not implied by the AST.

### 3.1 PostgreSQL parser and AST requirements

Use a PostgreSQL-native grammar implementation, such as a pinned `libpg_query` build or an equivalent parser generated from the PostgreSQL server parser sources. The selected implementation must match the target PostgreSQL major version. A generic SQL parser, regex scanner, or parser with only approximate PostgreSQL support is not acceptable.

The implementation must:

- Parse the entire file as bytes decoded under a strict UTF-8 policy; reject invalid encodings, NUL bytes, and unrecognized encodings.
- Preserve exact original source bytes and byte offsets. AST locations must map unambiguously to original source byte ranges; line/column-only mappings must account for UTF-8.
- Parse every top-level statement and nested SQL expression into an AST.
- Canonicalize AST serialization deterministically without discarding identifiers, literal types, casts, operators, clauses, or source locations required for review.
- Record parser name, package/release version, PostgreSQL grammar major/minor where applicable, build artifact digest, configuration, and canonicalization schema version.
- Reject parse errors, truncated input, unsupported grammar nodes, partial parses, and parser fallback. No best-effort AST may be marked accepted.
- Retain the raw AST and a canonical AST digest for independent re-verification.

Parser success means syntactic parsing only. It is not semantic resolution, execution evidence, or approval.

### 3.2 Semantic resolution

Resolve each AST node against a reproducible catalog snapshot representing the schema immediately before the migration statement, not merely the final live Production catalog.

Resolution context must include:

- PostgreSQL server version and build identity.
- Database identity and an independently collected catalog-snapshot digest.
- Effective role, session role, privileges, and relevant role memberships.
- Exact `search_path` and schema visibility at each statement boundary.
- Relation, column, type, domain, enum, collation, operator, function/procedure, aggregate, cast, sequence, constraint, index, trigger, policy, schema, and extension identities.
- Function overload resolution using argument types, default arguments, variadic rules, polymorphic types, implicit/assignment/explicit casts, and search-path visibility.
- Relevant configuration values that affect parsing or semantics, including standard-conforming strings and identifier folding assumptions.
- Extension name, version, schema, owner, and availability of its declared objects and install/update scripts.

The resolver must distinguish unresolved names from absent names, and ambiguity from absence. If an object cannot be resolved uniquely, emit `UNKNOWN`; never select a convenient candidate.

### 3.3 Schema, relation, column, and database-object identity

Use structured identity records; do not use unqualified strings as authoritative keys.

Minimum identity forms:

- Schema: database identity + schema name.
- Relation: database identity + schema + relation name + relation kind.
- Column: relation identity + column name + ordinal position + resolved type identity.
- Routine: schema + routine name + identity argument type vector + routine kind.
- Type: schema + type name + type kind; include typmod/collation where semantically relevant.
- Operator: schema + operator name + left/right operand type identities + implementation routine identity.
- Constraint/index/trigger/policy: owning relation identity + object name + object kind, with definition digest and relevant properties.
- Extension-owned object: extension identity/version plus the object identity it contributes.

Quoted identifiers are case-sensitive and must retain exact spelling. Unquoted identifiers must follow PostgreSQL folding rules. `search_path` resolution must be explicit and ordered. OIDs are useful only within the exact catalog snapshot that supplied them; they must not be treated as portable or durable cross-database identities. Include OIDs only alongside the snapshot identity and canonical logical identity.

### 3.4 Migration dependencies and execution ordering

Produce two separate graphs:

1. **Source dependency graph:** relation/routine/type/object reads and writes inferred from resolved ASTs.
2. **Migration ordering graph:** prerequisites and ordering constraints between pinned migration source identities.

Every edge must identify the source statement, referenced object, source migration blob, target/prerequisite migration blob, and resolution basis.

The inventory's deterministic path order is an input ordering rule, not proof of historical Production execution. Preserve it as the current inventory order and record it explicitly in analysis output. Do not infer that the two same-version Migration 007 files both executed, or infer which one executed first, from their shared version. Until an independently approved execution-order decision exists, treat the duplicate-version pair as an ambiguity blocker for any claim requiring a unique historical sequence. A disposable semantic replay may analyze each candidate sequence in isolated databases, but those are synthetic analyses and must never be labelled historical execution.

A cycle, missing prerequisite, unresolved object edge, ambiguous migration identity, or out-of-order dependency is a blocker. Topological sorting must be deterministic and must not silently reorder migrations to make a result pass.

### 3.5 Extensions and PostgreSQL-specific behavior

Record the extension inventory and exact versions in the resolver context. An extension's existence in `pg_extension` does not prove its SQL semantics are understood.

Support an extension only when the exact version's object definitions and relevant install/update scripts are available, pinned, and covered by the resolver's allowlist. Otherwise, any statement whose meaning depends on that extension is `UNKNOWN`.

PostgreSQL-specific constructs requiring first-class handling include dollar-quoted strings, quoted identifiers, arrays, composite and domain types, enums, range/multirange types, JSON/JSONB operators, generated columns, identity columns, partitioning, inheritance, row-level security, security-definer routines, search_path changes, triggers, event triggers, deferred constraints, transaction control, advisory locks, temporary objects, and extension-provided operators/functions.

No generic SQL fallback is permitted.

## 4. Supported / unsupported SQL matrix

"Supported" below means eligible for complete parsing and semantic resolution under the pinned PostgreSQL version and a complete catalog context. It does not mean that the statement executed in Production.

| Construct or behavior | Initial disposition | Acceptance rule |
|---|---|---|
| Basic DDL: CREATE/ALTER/DROP SCHEMA, TABLE, SEQUENCE, TYPE, DOMAIN | Supported when grammar and dependencies resolve | Emit object-level effects and dependencies |
| Columns, defaults, generated/identity columns, constraints | Supported when referenced types/functions resolve | Preserve exact column and constraint identity |
| Indexes, including partial/expression indexes | Supported when expressions and operator classes resolve | Resolve referenced columns, functions, opclasses and collations |
| Views and materialized views | Supported when query AST and all names resolve | Resolve underlying relation/column dependencies |
| INSERT/UPDATE/DELETE and MERGE | Supported when source, target, expressions and predicates resolve | AST-based read/write sets; no regex inference |
| CTEs, recursive CTEs, subqueries, joins | Supported when every scope resolves | Preserve lexical scopes and column lineage |
| Functions/procedures in SQL or PL/pgSQL | Conditional | Parse body and resolve calls; unknown on unanalysed control flow or body |
| Triggers and policies | Conditional | Resolve trigger function, event/timing, row context, roles and policy expressions |
| Grants, revokes, ownership, role changes | Conditional | Resolve principals and object scope; preserve privilege semantics |
| Extension SQL | Conditional | Exact extension/version scripts and object model required |
| Constant-string dynamic SQL | Conditional | Only if exact string is statically derivable and separately parsed/resolved |
| Variable-built EXECUTE / format() dynamic SQL | Unsupported initially | Emit UNKNOWN with source location and reason |
| PL/pgSQL branches/loops/exception blocks | Conditional | Require PL/pgSQL parser/control-flow model; unknown if path-dependent effect cannot be bounded |
| DO blocks | Conditional | PL/pgSQL body analysis required; never ignore the body |
| C-language or external-language routines | Unsupported initially | External implementation semantics unavailable |
| Unavailable procedural languages | Unsupported | Missing parser/runtime means UNKNOWN |
| dblink, FDW, remote database calls | Unsupported initially | Remote catalog and transaction state unavailable |
| Event triggers or callbacks with unresolved side effects | Unsupported initially | Emit UNKNOWN |
| psql meta-commands / client directives | Unsupported in migration SQL parser | Reject or route through a separately specified client-script parser; never silently skip |
| COPY PROGRAM, shell execution, external file/network effects | Unsupported | Explicit security blocker |
| Transaction/session changes that invalidate resolver assumptions | Conditional/unsupported | Track supported SET/RESET and transaction semantics; otherwise UNKNOWN |
| Unrecognised AST node or grammar version mismatch | Unsupported | Hard fail; no partial acceptance |
| Parse error, encoding error, truncated statement | Unsupported | Hard fail |

The first implementation should deliberately support a smaller, testable subset. Expanding the subset requires versioned fixtures and independent PostgreSQL behavior tests. Unsupported does not mean harmless or absent.

## 5. PL/pgSQL and dynamic SQL handling

PostgreSQL's top-level SQL parser does not by itself establish the semantics of a procedural body. PL/pgSQL requires a dedicated analysis path.

Minimum requirements:

1. Extract routine identity and exact body bytes from the parsed CREATE FUNCTION/PROCEDURE statement.
2. Identify language, security-definer/invoker mode, volatility, strictness, parallel safety, search_path settings, configuration, argument types, and return type.
3. Parse PL/pgSQL syntax using a parser/validator matched to the same PostgreSQL major version. A disposable PostgreSQL server's PL/pgSQL compiler and a pinned static checker may be used, but only with a declared version and isolated fixture database.
4. Build a control-flow representation for branches, loops, exception handlers, returns, assignments, SELECT INTO, PERFORM, and calls.
5. Parse embedded static SQL statements as SQL ASTs and resolve them under the routine's effective execution context.
6. For EXECUTE, resolve only strings proven constant by a conservative data-flow analysis. Parameterized USING expressions still require type and value-flow handling. Any non-constant or path-dependent command remains UNKNOWN.
7. Do not execute arbitrary migration routines merely to obtain analysis. Static compilation/validation must be isolated and must not perform network, file, external-language, or Production side effects.
8. Record every unsupported body fragment with exact source location and a stable diagnostic code.

If a routine has any unresolved side-effecting path, the routine's relevant semantic category remains UNKNOWN even if other statements in the body were understood.

## 6. Exact source provenance and reproducibility

Every semantic artifact must be bound to the exact inventory and exact bytes analyzed.

Required source identity per migration:

- Repository full name and inspected commit SHA.
- Inventory manifest Git blob SHA-1 and canonical inventory SHA-256.
- Exact migration path, version, Git blob SHA-1, byte length, and independent SHA-256 of raw bytes.
- Parser input encoding and byte range.
- Per-statement source byte offsets, line/column ranges, and source SHA-256.
- Exact source file set: 40 paths, including both 007 files and 039.

The existing Git blob SHA-1 pin remains a compatibility/inventory identity; new semantic artifacts additionally use SHA-256. Neither hash proves execution or semantic correctness.

A source file changed by one byte invalidates all AST, resolver, review, and execution claims bound to its previous blob. No artifact may be reattached to a different source path or blob by matching filename/version alone.

## 7. Parser and resolver version identity

Every result must declare:

- Parser implementation name, immutable release/version, package source, and build/container digest.
- PostgreSQL grammar major/minor and build compatibility declaration.
- AST canonicalization schema version.
- Semantic resolver implementation version and build digest.
- Resolver rule-set version and allowlist digest.
- PostgreSQL server major/minor, extension inventory and versions.
- Catalog snapshot source, capture identity, digest, and transaction/snapshot metadata.
- Resolver configuration, role, session role, search_path and relevant GUCs.
- Migration ordering policy and dependency-graph digest.

Any parser, grammar, canonicalizer, resolver, rule-set, extension version, or relevant catalog snapshot change requires a new semantic result and new approval. Version strings without immutable build digests are insufficient.

## 8. Trust and provenance model

### 8.1 Separate semantic approval role

The existing trust roles are evidence approver, mapping approver, and collector. C573 must not silently reuse one of those roles as a semantic approver.

A future trust-root change may define a dedicated `semantic-approver` role, but only through an independently reviewed trust-root change, external provisioning, documented key custody, rotation, revocation, and approval policy. C573 does not provision keys or change the trust-root bundle.

The semantic approval is a detached signature over a canonical claim object containing at least:

- Project and repository identity.
- Exact PR/commit identity and inventory digest.
- Every migration path, version, blob SHA-1, raw-source SHA-256 and byte length.
- Parser and resolver identities/build digests and PostgreSQL grammar/server versions.
- Canonical AST artifact digest per source and statement.
- Catalog snapshot and extension inventory digests.
- Semantic result and dependency graph digests.
- Supported/unsupported/unknown counts and all diagnostic identifiers.
- Explicit reviewed scope and exclusions.
- Reviewer identity, approval ID, issue time, expiry, and revocation semantics.

The verifier must validate canonical serialization, signature algorithm, key identity, role, key validity window, revocation, approval expiry, exact claims, and the independently provisioned trust-root bundle digest. Unknown fields, duplicate IDs, malformed claims, unsigned artifacts, stale approvals, or missing roots fail closed.

### 8.2 No signed absence proof

A signed mapping or approval that declares `none`, an empty effect list, or "no effect found" is not proof that no effect exists.

A category can be considered semantically absent only if:
- The parser completely covers the exact source bytes under the declared grammar.
- All SQL and procedural bodies are covered.
- All names, scopes, dependencies, extensions, and dynamic behavior relevant to the category resolve.
- There are zero unsupported or unknown constructs that could affect the category.
- The resolver's category-specific absence result is explicit and reproducible.
- A separately authorized reviewer approves that exact complete result.

If any step is incomplete, absence remains UNKNOWN. The signature authenticates who approved a claim; it does not make a false or incomplete claim true.

### 8.3 Execution evidence remains separate

An AST proves what source declares, not what ran. A source digest proves bytes, not execution. A migration-history row proves only the recorded history fact.

Backfills, preconditions, and postconditions require separately collected read-only execution evidence bound to:
- Project/database identity and a verifiable snapshot or transaction boundary.
- Exact migration source blob and statement identity.
- Exact query/predicate bytes and digest.
- Effective role and relevant session configuration.
- Execution ID, start/end timestamps, transaction outcome.
- Result schema and result artifact digest; row counts alone are insufficient.
- Collector identity/build and independently verifiable attestation.

No execution result may be synthesized by parser output or by a signed source mapping. If historical evidence does not exist, the historical execution claim remains UNKNOWN; a new disposable replay is not historical proof.

## 9. Report contract and C572 diagnostic findings

### 9.1 Per-migration output

Each of the 40 entries must produce a structured record, even when trust verification fails:

- Exact source identity and source-verification status.
- Parse status, parser identity, AST digest, statement count.
- Semantic resolution status.
- Per-category status: VERIFIED, UNSUPPORTED, UNKNOWN, or NOT_EVALUATED.
- Resolved object identities and dependency edges.
- Unsupported construct diagnostics with stable code, source range, node kind, and explanation.
- Trust/provenance status and the specific failed checks.
- Independent approval status and exact approval binding.
- Execution evidence status, separately from semantic status.

Global acceptance must be `NOT_ACCEPTED` if any required migration/category is UNKNOWN, unsupported, unapproved, stale, or untrusted.

### 9.2 F-01 — incomplete semantic diagnostics on trust failures

C572 finding F-01 is an explicit acceptance requirement for this design: trust failures must not leave semantic diagnostics incomplete or misleading.

Required behavior:

- Always emit all 40 migration classifications and all five non-catalog categories, even when the trust-root bundle, signature, mapping, or evidence payload is invalid.
- Emit a trust failure as a distinct diagnostic, not as a semantic finding and not as a reason to suppress category diagnostics.
- Mark semantic status UNKNOWN or NOT_EVALUATED when trust failure prevents reliable analysis. Never mark a category VERIFIED based on untrusted inputs.
- Include category-specific blockers and per-migration reason codes. Do not return only a generic `trustVerified=false` or a global message.
- Preserve both trust diagnostics and parser/resolver diagnostics when the parser can safely inspect independently verified source bytes. Do not parse untrusted or mismatched source bytes as if they were pinned.
- Keep the output shape stable under malformed/missing inputs, with empty arrays plus explicit NOT_EVALUATED reasons where details cannot safely be produced.
- Tests must assert complete 40 × 5 diagnostics for missing roots, wrong root digest, unsigned artifacts, invalid signatures, revoked/expired keys, malformed approvals, source drift, and malformed evidence.
- A diagnostic completeness improvement must never weaken acceptance, signature checks, or source provenance.

### 9.3 PR-triggered CI coverage gap for stacked feature branches

The inspected `.github/workflows/pr-validation.yml` declares:

```yaml
on:
  push:
    branches-ignore: [main]
  pull_request:
    branches: [main]
```

PR #29 targets `feat/category-specific-migration-effects-c556`, not `main`. The current pull_request branch filter therefore does not select this stacked PR. Pushes to the feature branch match the push filter, but that does not replace explicit PR-triggered validation or prove a run occurred.

Before semantic implementation is eligible for review, CI policy must deliberately cover pull requests targeting supported feature bases. The workflow change must avoid duplicate uncontrolled runs, preserve read-only permissions and non-Production configuration, and validate the exact PR head SHA. Required evidence is an actual Actions run with event, head SHA, checkout SHA, workflow SHA, job conclusions, and failure logs. Empty PR-run lookups are not evidence of success or of absent push runs.

## 10. Executable verification strategy

Architecture documentation is not implementation evidence. The following tests are required before any semantic acceptance claim.

### 10.1 Parser conformance and AST fixtures

- PostgreSQL-major-specific positive and negative grammar fixtures.
- Quoted/unquoted identifiers, Unicode identifiers, dollar quotes, comments, nested expressions, CTE scopes, casts, operators, arrays, JSONB, generated columns, partitions and DDL variants.
- Multiple statements and malformed/truncated SQL.
- Byte-offset to source-line mapping including CRLF and multi-byte UTF-8.
- Deterministic AST serialization across repeated runs.
- Unknown-node rejection and parser-version mismatch rejection.
- Differential checks against the matching PostgreSQL server parser in disposable PostgreSQL.

### 10.2 Semantic resolver fixtures

- Explicit schema versus search_path resolution and shadowing.
- Case-sensitive quoted names and PostgreSQL unquoted folding.
- Overloaded routines/operators, implicit casts, domains, enums, collations and polymorphic types.
- Missing and ambiguous relations, columns, types, functions and operators.
- Relation/column renames, drops, dependency invalidation, constraints, indexes, triggers, policies and RLS.
- Security-definer routines, effective role changes, grants/revokes, ownership and default privileges.
- Extension versions and unknown extension-owned behavior.
- Dependency graph cycles, missing prerequisites, deterministic ordering, and duplicate 007 ambiguity.
- All unresolved references must produce UNKNOWN, never guessed identities.

### 10.3 PL/pgSQL and dynamic SQL fixtures

- Static SQL in function/procedure bodies.
- IF/ELSIF/ELSE, loops, exception blocks, RETURN QUERY, SELECT INTO and PERFORM.
- Constant dynamic SQL that can be safely extracted and reparsed.
- Variable concatenation, format(), EXECUTE USING, data-dependent SQL, nested dynamic execution and path-dependent command construction.
- External-language functions, C functions, FDW and dblink.
- Verify unsupported constructs always block the affected semantic categories.

### 10.4 Trust, provenance, and report adversarial tests

- Missing, unsigned, forged, wrong-role, expired, revoked, stale, duplicated, malformed and unknown-field approvals.
- Repository-contained trust roots and mismatched externally provisioned root digests.
- Source path/blob/byte-length/hash drift and source swapping between the two Migration 007 files.
- AST, parser, resolver, catalog snapshot, extension and graph digest tampering.
- Signed `none`/empty-effect claims with hidden or unsupported syntax.
- Trust failure output completeness: exactly 40 migration classifications and all five non-catalog categories, with explicit trust and semantic blockers.
- Approval replay against another commit, parser build, resolver build, grammar major, extension set, or catalog snapshot must fail.

### 10.5 PostgreSQL behavior and integration tests

Use disposable PostgreSQL instances matching the declared supported major, initially PostgreSQL 16 because the existing workflow's database jobs use PostgreSQL 16. This is a CI fixture, not proof of the Production server major. First obtain and pin the Production server version through existing authorized read-only evidence before selecting the production grammar target.

- Replay only in isolated databases with no Production credentials or network access.
- Build the resolver catalog state at each migration boundary.
- Compare parser/resolver effects against catalog changes from disposable execution.
- Include failure/interruption, transaction rollback, duplicate-version alternative sequences, extensions and privilege boundaries.
- Assert no external network, filesystem, shell, or Production database access.
- Preserve the existing PostgreSQL 16 migration-order, collector, adapter, analyzer, ownership and privacy suites.

### 10.6 CI gates

Required independent jobs should include:
1. Parser conformance and AST integrity.
2. Semantic resolver unit/adversarial tests.
3. PL/pgSQL/dynamic SQL negative tests.
4. Inventory/source provenance verification.
5. Disposable PostgreSQL behavior integration.
6. Trust/approval and 40 × 5 diagnostic completeness.
7. Existing analyzer/adapter/collector regressions.
8. Exact-head final workflow evidence.

Every job must use non-Production configuration, no service-role or provider credentials, and read-only repository permissions. A green build is necessary but not sufficient for Production acceptance.

## 11. Proposed implementation stages and exit criteria

| Stage | Deliverable | Exit criteria |
|---|---|---|
| S0 — Baseline and grammar decision | Verify Production PostgreSQL major and exact 40-source inventory | Version and inventory evidence independently recorded; duplicate 007 ambiguity explicit |
| S1 — Parser spike | Version-pinned PostgreSQL parser and canonical AST output | All 40 files parse or emit explicit unsupported diagnostics; no silent partial parse |
| S2 — Source provenance | AST artifacts bound to exact raw bytes and statement ranges | Tamper/source-swap tests fail closed; parser/build identity immutable |
| S3 — Catalog model | Snapshot schema/object/type/routine/extension identities | Deterministic identity resolution; unresolved/ambiguous names UNKNOWN |
| S4 — Resolver | Statement-by-statement semantic effect/dependency graph | Positive/negative fixtures and disposable PG differential tests pass |
| S5 — Procedural analysis | PL/pgSQL control-flow and conservative dynamic SQL handling | All unhandled control-flow/dynamic behavior explicitly UNKNOWN |
| S6 — Review and trust | Dedicated semantic approval schema and independent role design | Separate trust-root approval, revocation, replay and digest-binding tests; no keys provisioned by implementation |
| S7 — Analyzer integration | Read-only semantic artifact verifier; preserve catalog_only_v1 | Any missing/unsupported/untrusted artifact remains NOT_ACCEPTED; complete 40 × 5 diagnostics |
| S8 — CI and handover | Exact-head CI, workflow coverage and rollback/runbook | Actual run/job/checkout evidence; independent review; no Production mutation |

No stage may be skipped by marking an unverified artifact as applied, approving a signed absence assertion, or treating synthetic replay as historical execution.

## 12. Security risks and unresolved dependencies

1. **Grammar drift:** parser grammar may not match the Production server. Block until exact major/version compatibility is established.
2. **Semantic drift:** parser ASTs omit catalog-dependent behavior unless resolver context is complete. Block unresolved names and overloads.
3. **Procedural blind spots:** PL/pgSQL and dynamic SQL can hide side effects. Block unanalysed paths.
4. **Extension opacity:** extension names/versions do not provide implementation semantics. Block unsupported extension behavior.
5. **Search-path and role confusion:** object resolution and security-definer execution vary by context. Bind effective role and search_path per statement/routine.
6. **Duplicate Migration 007:** shared version cannot identify source execution or order. Keep both sources distinct and historical order UNKNOWN without independent evidence.
7. **False absence:** parser omissions or unsupported nodes can make an empty effects list look complete. Require whole-source coverage and zero unresolved relevant nodes.
8. **Approval replay:** approvals could be replayed against changed source/parser/resolver/snapshot. Bind all digests and versions into signed claims.
9. **Trust-root compromise:** semantic approval authority must be separately provisioned, least-privileged, revocable, and audited. C573 does not provision it.
10. **Execution evidence confusion:** synthetic PostgreSQL replay and source ASTs are not historical Production execution evidence.
11. **CI event gap:** stacked PRs do not match the current pull_request base filter. Actual exact-head Actions evidence is still required.
12. **F-01 report degradation:** trust failures can obscure useful per-category diagnostics. Stable structured diagnostics must be complete without making untrusted data acceptable.
13. **Resource exhaustion:** hostile or pathological SQL can exhaust parser/resolver resources. Enforce input, AST depth, statement count, CPU and memory limits; timeout means UNKNOWN.
14. **Tooling supply chain:** parser binaries, generated grammar, extension scripts and resolver dependencies require pinned versions, digests and vulnerability review.

Unresolved external dependencies include a verified Production PostgreSQL version, a selected and maintained PostgreSQL-native parser distribution, a complete catalog snapshot contract, PL/pgSQL analysis tooling, exact extension script coverage, independent semantic reviewers, and a future separately approved trust-root role.

## 13. Rollout, rollback, and Production boundary

- Build and test parser/resolver only in isolated disposable PostgreSQL environments.
- Do not connect the semantic analyzer to Production with write privileges.
- Do not mutate `supabase_migrations.schema_migrations`, mark migrations applied, or reconcile migration history as part of this work.
- Do not change Production schema, extension versions, roles, grants, scheduler, or delivery settings.
- Do not provision semantic trust roots or expose private keys/tokens.
- Keep the new semantic result advisory/NOT_ACCEPTED until every acceptance gate is independently demonstrated.
- Roll back by reverting the isolated implementation/specification commits; no database rollback should be required because no Production mutation is permitted.

Production migration acceptance remains **NO-GO** until semantic verification is implemented, independently approved, and supported by exact-head CI and the separate Production evidence gates.

## 14. C573 execution status and evidence register

| Item | Status |
|---|---|
| PR #29 current head | Verified by GitHub PR API: `2133cee1439287399740bf9794bbb0b4e793105c` |
| PR base SHA | Verified: `0e5bf38f1fdd67300825ecdf29555aa1ff3674b7` |
| Inventory blob and 40 entries | Verified by GitHub file retrieval |
| Both Migration 007 sources and Migration 039 | Verified in inventory |
| Existing catalog_only_v1 boundary | Inspected in analyzer/collector |
| Existing PostgreSQL AST parser | Not present in inspected semantic pipeline |
| Semantic resolver | Not implemented |
| PL/pgSQL/dynamic SQL semantic handling | Not implemented |
| Independent semantic approval | Not implemented; no trust-root change |
| F-01 acceptance requirements | Documented; implementation not changed |
| Stacked PR CI filter gap | Verified in workflow YAML; no workflow change made |
| Tests executed by C573 | None; GitHub connector has no shell/test execution capability |
| PostgreSQL behavior tests passed | Not claimed |
| Production state changed | No |
| PR #29 merged | No |

### Source links

- [PR #29](https://github.com/ADRN-9/deedlight/pull/29)
- [Inspected PR HEAD](https://github.com/ADRN-9/deedlight/commit/2133cee1439287399740bf9794bbb0b4e793105c)
- [Pinned migration inventory](https://github.com/ADRN-9/deedlight/blob/fix/c558-pr28-security-remediation/supabase/migration-inventory.json)
- [Current analyzer](https://github.com/ADRN-9/deedlight/blob/fix/c558-pr28-security-remediation/scripts/reconcile-migration-evidence.mjs)
- [Category contract validator](https://github.com/ADRN-9/deedlight/blob/fix/c558-pr28-security-remediation/scripts/migration-effect-contracts.mjs)
- [Existing C556/C570 handover](https://github.com/ADRN-9/deedlight/blob/fix/c558-pr28-security-remediation/docs/C556_CATEGORY_SPECIFIC_EFFECT_CONTRACTS.md)
- [PR Validation workflow](https://github.com/ADRN-9/deedlight/blob/fix/c558-pr28-security-remediation/.github/workflows/pr-validation.yml)

**Final status:** C573 architecture specification authored as a proposal. PostgreSQL semantic verification is NOT IMPLEMENTED / NOT VERIFIED. No test PASS, Production acceptance, trust-root provisioning, migration reconciliation, or PR merge is claimed.
