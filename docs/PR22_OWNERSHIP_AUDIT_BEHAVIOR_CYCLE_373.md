# PR #22 — Cycle 373 PostgreSQL ownership-audit behavior tests

**Repository:** \`ADRN-9/deedlight\`  
**PR:** [#22](https://github.com/ADRN-9/deedlight/pull/22)  
**Branch:** \`security/private-daily-journey-admin-isolation-c408\`  
**Starting HEAD:** \`9948510fd98300b3b4bdab48b4c9f785fa361b0f\`  
**Scope:** disposable PostgreSQL 16 execution of the exact Query 8A and Query 8B SQL fences in \`docs/PRODUCTION_READ_ONLY_MIGRATION_AUDIT.md\`.

## Test implementation

- \`scripts/test-ownership-audit-postgres16.mjs\` extracts the actual fenced SQL under the exact Query 8A and Query 8B headings. It executes those unchanged query bodies through \`psql\`; no copied or reimplemented ownership query substitutes for the documented SQL.
- \`scripts/test-ownership-audit-fixtures.sql\` creates 18 synthetic SECURITY DEFINER routines using every exact documented identity signature and a synthetic owner. Every fixture function uses \`search_path=pg_catalog\`.
- Seventeen functions retain PostgreSQL's default function ACL (\`proacl IS NULL\`). The \`is_admin()\` fixture receives a deliberately explicit ACL for a separate synthetic role. The assertions distinguish the stored ACL from the default-expanded ACL.
- Membership fixtures cover a direct inherited edge, a direct SET-only edge, a second direct inherited edge, and a recursive SET-only path to a role with CREATEROLE and BYPASSRLS. Query results assert depth, directness, MEMBER, USAGE, SET, edge-derived effective privileges and privileged-role flags.
- Negative fixtures revoke and restore a membership edge, verify that the transitive path disappears/reappears, remove one expected function and verify the inventory still returns 18 rows with \`MISSING_FUNCTION\`, and verify the application-level fail-closed assertion rejects a missing-owner status or unresolved owner identity.
- The cleanup SQL drops only uniquely named synthetic fixture roles and objects. The harness runs cleanup in a \`finally\` block after fixture setup succeeds.

## PostgreSQL missing-owner limitation

A valid PostgreSQL function's \`pg_proc.proowner\` is protected by a dependency on the owning role. A normal catalog-valid fixture cannot retain a function row while deleting its owner role. The test therefore does not corrupt system catalogs or fabricate an invalid \`proowner\` state. Instead, it separately exercises the consumer's fail-closed handling for \`MISSING_OWNER_ROLE\` and a null owner identity. Query 8A retains the LEFT JOIN and explicit status for defensive reporting if catalog corruption or an abnormal restore ever exposes such a condition.

## CI

A dedicated PostgreSQL 16 service job runs the harness with no Production credentials. It is separate from and does not replace the existing lexical verifier tests. CI is the execution authority; local execution is not claimed unless independently performed.

## Coverage boundary

These tests prove behavior only in a disposable PostgreSQL 16 instance populated with synthetic identities. They do not establish Production function owners, acceptable Production role memberships, Production ACLs, migration application status, or DBA approval. No Production owner name is embedded in fixture SQL or test expectations.

## Safety and handoff

- No migration SQL (036–038 or historical 007) is changed.
- No Production database, credentials, deployment, scheduler, provider, or delivery operation is used.
- PR #22 remains OPEN / DRAFT / UNMERGED; no merge or approval is authorized by this change.
- Production remains NO-GO pending authoritative DBA evidence, approved per-signature owner mappings, executable Production owner enforcement, independent security acceptance and the remaining rollout gates.

### Cycle 374 handoff

1. Review the PostgreSQL 16 exact-query behavior run and inspect any failed assertions before accepting the result.
2. Confirm the new job ran against the exact branch HEAD and that cleanup completed.
3. Review whether membership-path results need explicit path multiplicity assertions for multiple routes to the same role.
4. Keep Production owner mapping unset until the authorized DBA supplies evidence and approval.
