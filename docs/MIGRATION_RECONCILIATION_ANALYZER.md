# DeedLight Production migration evidence analyzer

Status: implementation and synthetic regression coverage only. No Production evidence has been collected or classified by this tool.

## Purpose and safety boundary

`scripts/reconcile-migration-evidence.mjs` is a read-only report generator. It never connects to Supabase, executes SQL, writes migration history, edits migration files, or proposes an automatic `migration repair` command. It compares the pinned repository inventory with a separately collected, approved evidence export.

Run only after the Production DBA has supplied an authorized read-only export and an independent approver has supplied the matching approved payload digest:

```sh
node scripts/reconcile-migration-evidence.mjs /secure/path/deedlight-production-evidence.json <independently-approved-payload-sha256>
```

Exit status 2 means evidence is incomplete/stale/untrusted or one or more migrations are Unknown or Partial/drifted. The report always declares `mutationPerformed: false`. The analyzer must not be used as a substitute for DBA review or a Production migration approval.

## Required evidence envelope

The JSON envelope is schemaVersion 1 and contains:

- `provenance`: environment `production`, exact project ref `xaipiovflxomcbfwtwmu`, capture timestamp, `readOnly: true`, named collector, SHA-256 of the exact read-only query bundle, DBA approval reference and `payloadSha256`.
- `history`: `complete: true` and all migration-history rows, preserving duplicates and exact version values.
- `catalog`: `complete: true`, `completeKinds` containing all seven required dimensions, and object records with stable kind, identity and SHA-256 fingerprint.
- `migrationEffects`: exactly 39 reviewed mappings. Every mapping binds an exact migration path and pinned Git blob SHA-1 to one or more expected catalog objects.
- `mapping`: `complete: true`, independent reviewer identity and SHA-256 of the reviewed source-to-schema mapping.

The independently approved digest is passed out-of-band as the CLI's second argument. The digest covers the canonical evidence payload and provenance metadata (excluding only the digest field itself). A self-reported digest is not trusted. The approver must compare the exact digest against the evidence artifact and retain the signed approval record separately. A digest alone is not a digital signature or proof that a collector was honest.

The evidence must be no more than 24 hours old. Future timestamps, wrong project refs, write-capable collectors, missing DBA approval references, missing query fingerprints, incomplete exports, incomplete mapping, malformed history rows and payload tampering fail closed to Unknown.

## Catalog fingerprint contract

The DBA-approved exporter and reviewer must agree on canonical fingerprints before any Production export is accepted. Fingerprints must be stable SHA-256 values over canonical catalog facts, not names alone:

| Kind | Required identity/fingerprint contents |
|---|---|
| tables | schema, relation name, persistence/partition attributes and relevant relation definition |
| columns | schema, table, ordinal, name, type, nullability, default, generated/identity attributes |
| constraints | schema/table/name, type, validated/deferrable state and canonical definition |
| indexes | schema/table/name, uniqueness, validity/readiness, access method and canonical definition |
| triggers | schema/table/name, enabled state, timing/events and canonical definition |
| policies | schema/table/name, command, roles, permissive mode and USING/WITH CHECK expressions |
| routines | schema/name/identity arguments, complete definition, owner role, SECURITY DEFINER, configuration/search_path and effective plus explicit ACL facts |

Routine fingerprints must include actual owner and effective EXECUTE privileges for PUBLIC, anon, authenticated and service_role, plus relevant schema ACLs. Query 8A/8B ownership and role-membership evidence remains a separately required security approval input; the migration analyzer does not replace that audit.

The mapping must be reviewed for all 39 migrations. The analyzer intentionally does not guess SQL effects by regex-parsing migration text. A source-to-object mapping that is absent, incomplete or not independently reviewed cannot support any classification.

## Classification rules

- **Applied and verified**: exact local source fingerprint; exactly one history row for the unique version; every reviewed expected object is present with the exact canonical fingerprint; all required exports and approvals are complete and fresh.
- **Schema represented but history ambiguous**: all mapped effects are present, but history is missing/non-unique, or the migration version is duplicated. The duplicate `202607260007` always remains ambiguous even if a history row exists.
- **Verified unapplied**: complete authoritative history and all seven catalog dimensions show no history row and no expected mapped effect. This conclusion is only as strong as the independently reviewed exhaustive effect mapping.
- **Partial or drifted**: any expected effects are missing while others exist, an existing object's fingerprint differs, or history claims a migration whose mapped schema effects are incomplete.
- **Unknown**: source fingerprints differ; evidence is missing, stale, malformed, wrong-target, untrusted or incomplete; mappings are missing/duplicated; or catalog identities are ambiguous.

A single `202607260007` history row can never prove both the Sprint 6 Daily Deedlight and Sprint 7 PWA Daily Engagement SQL bodies executed. The two migration files and their source fingerprints remain separate. The analyzer classifies each body's mapped effects independently and marks both ambiguous when their complete effects are present.

## Forward-only reconciliation proposal

1. Obtain DBA/security-approved read-only Production exports and independently retain the exact evidence digest and approval.
2. Review the complete 39-entry source-to-schema mapping, including Migration 007's two distinct effects and all protected 036–038 effects.
3. Run the analyzer and investigate every Unknown, Partial/drifted and history-ambiguous classification. No automated history repair is allowed.
4. Establish a verified backup/PITR restore point and rehearse restoration before any schema mutation. Record RPO/RTO, migration lock owner, execution window and recovery operator.
5. For proven missing effects, prepare a new uniquely versioned, idempotent, forward-only migration with explicit preconditions, postconditions and data-preservation checks. Preserve original historical migration files.
6. Treat any migration-history-only correction as exceptional. It requires proof that every effect of the exact historical source body is present, a separate DBA/security approval and a documented recovery plan. Never blindly mark 007, 036, 037 or 038 applied.
7. Keep scheduler activation and outbound delivery disabled during reconciliation. Capture before/after catalog exports, history rows, CI, deployment and smoke evidence. Stop on unexpected drift; prefer a reviewed forward repair over destructive rollback.

## Current known repository facts

At the implementation starting point, the committed inventory declares 39 SQL migration files and 38 unique versions. Its sole intentional duplicate is `202607260007`, containing distinct Sprint 6 and Sprint 7 SQL bodies. Migrations 036, 037 and 038 are protected by their pinned source fingerprints and are not changed by this tooling.

No Production export, schema classification, DBA authorization or migration-history mutation is included in this implementation. Synthetic fixture results are not Production evidence.
