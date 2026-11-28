# C602 — Privileged execution-ledger RPC authorization matrix

**Assessment date:** 2026-11-28  
**Repository:** `ADRN-9/deedlight`  
**C602 branch base:** C600 PR #38 head `0d81fa5bd3892d3ec063c41a4275b9a60c14b30c`  
**C601 evidence:** PR #39, `docs/c601-exact-repository-pr-evidence`, head `d87eeb5a70b938d72ccb758acaeb65f9727eadb6`  
**Scope:** inspect and document the existing disposable PostgreSQL execution-ledger fixture. No Production privilege, credential, trust-root, or scheduler changes. No gateway remediation implementation.

## Executive disposition

**Authorization matrix: documented from actual SQL. Production authorization boundary: NOT ESTABLISHED.**

The nine RPCs exist in `scripts/fixtures/migration-execution-ledger-v1.sql`, a disposable PostgreSQL fixture. C600's direct-call denial fixture is `scripts/fixtures/test-migration-execution-ledger-c600.sql`. The PostgreSQL runner `scripts/test-migration-execution-ledger-postgres16.sh` connects as `postgres` to a pinned disposable service and creates the functions/roles from that fixture. These sources are not evidence that the same roles or RPCs are installed in Production. The feature branch contains 40 historical migration SQL files and a 40-entry inventory, but the C601 evidence says default `main` has 23 migrations and no inventory. Do not equate fixture definitions with a Production schema deployment.

All nine functions are `SECURITY DEFINER` with `SET search_path = pg_catalog, deedlight_execution_ledger`. They are created by the fixture's `postgres` database login, so their owner in that disposable harness is `postgres`. The runner explicitly sets `PGUSER=postgres`; exact live catalog ownership should still be confirmed from the job's catalog if a different runner invocation is used.

The fixture revokes all function EXECUTE from PUBLIC, then grants only the actor-role mapping below. Each actor role is `NOLOGIN NOINHERIT`. The fixture grants all five roles to `postgres` to allow tests to `SET ROLE`. The helper `actor_role()` returns `current_setting('role')`. Consequently, the fixture proves effective-role authorization, not independently authenticated actor identity. A privileged `postgres` session can impersonate each role using `SET ROLE`; a superuser can also change session authorization. This is a known test-harness impersonation path, not a safe Production identity model.

## 1. Five actor roles — preserve as independent authorities

| Role | Intended authority | Allowed RPCs |
|---|---|---|
| Approver | Create an immutable approval scope | `approve_execution` |
| Runner | Reserve, start, heartbeat, record committed effect, finalize its own execution | `reserve_execution`, `start_execution`, `heartbeat_execution`, `record_effect_commit_marker`, `finalize_execution` |
| Observer | Capture registered pre/post snapshots independently of approver and runner | `capture_snapshot` |
| Recovery | Recover stale reservations/running executions under bounded timeout | `recover_stale_executions` |
| Verifier | Append an independent verdict for terminal execution | `record_verification` |

The roles are separate PostgreSQL role names, but the fixture creates them as NOLOGIN and grants membership to the shared `postgres` test principal. This is not five independent database login identities. No C602 conclusion treats the fixture as proof of Production role separation.

## 2. Nine-RPC authorization matrix

All nine signatures below are schema-qualified and match the actual function declarations and C600 test fixture. All are SECURITY DEFINER and owned by the fixture creator (`postgres` in the pinned test harness). PUBLIC function EXECUTE is revoked. The named actor role is the only role explicitly granted EXECUTE for that RPC.

### 2.1 `approve_execution`

- **Signature:** `approve_execution(uuid, uuid, uuid, jsonb) RETURNS void`
- **Parameters:** `p_approval_id`, `p_record_id`, `p_execution_id`, `p_source_identity`.
- **Owner / grant:** fixture owner `postgres`; EXECUTE only to `deedlight_ledger_approver`.
- **Required checks:** current database identity must match the installation anchor; effective role must equal approver; three UUIDs must be non-NULL; source identity must be a non-NULL JSON object.
- **Allowed invocation:** direct SQL function call under `SET ROLE deedlight_ledger_approver` in the disposable fixture. Production must use an independently authenticated Approver identity and, after C603, an authorized wrapper.
- **Request binding:** current RPC does not accept a signed request, operation/audience/generation/nonce, or canonical request digest. The source JSON is only checked to be an object here; unlike reserve/marker it is not passed through `valid_source_identity()`. It is stored in the approval row and later compared by reserve.
- **Failure:** identity mismatch fails closed; wrong role raises `approver authority required`; incomplete scope raises `approval scope is incomplete`; duplicate approval/execution/record uniqueness raises a unique violation.
- **Side effects on rejection:** no approval row should be inserted on any rejected statement. A successful call inserts one immutable approval.
- **Positive test:** `test-migration-execution-ledger-v1.sql` creates approvals for normal, partial, abandoned, ambiguous, query-mismatch and crash fixtures (e.g. lines 19–25, 129–135, 240–246, 292–298, 429–435, 497–503).
- **Negative tests:** duplicate execution and duplicate record IDs rejected (lines 203–237); wrong-role EXECUTE is covered by the ACL matrix requirement below. C600 untrusted-role fixture denies direct invocation.
- **Coverage:** positive path exists; direct-call denial for all nine exists only for the untrusted NOLOGIN test role; full cross-actor matrix and caller-identity binding are not established.

### 2.2 `reserve_execution`

- **Signature:** `reserve_execution(uuid, uuid, uuid, jsonb) RETURNS void`
- **Parameters:** `p_approval_id`, `p_record_id`, `p_execution_id`, `p_source_identity`.
- **Owner / grant:** fixture owner `postgres`; EXECUTE only to `deedlight_ledger_runner`.
- **Required checks:** live database identity; Runner effective role; source identity must be an object with exactly the accepted relative path/SHA-256 shape; approval must exist, be unconsumed, and match current DB identity, record ID, execution ID and exact source JSON.
- **Allowed invocation:** Runner only, using the approval previously created by Approver.
- **Request binding:** typed UUID scope and exact equality with stored approval plus source path/hash. No cryptographic signature, canonical serialized request digest, audience, generation, expiry, workload principal, or nonce is verified.
- **Failure:** D1001 missing trust / identity mismatch; D1002 invalid source identity; D1005 missing/consumed approval, scope mismatch or replay; uniqueness violation on duplicate execution/record.
- **Side effects on rejection:** no execution row and no approval consumption on rejected call. On success execution insert and approval consumption occur in the same transaction.
- **Positive test:** normal reservation lines 47–55; additional partial, stale, crash and concurrent replay flows.
- **Negative tests:** caller transaction rollback restores both execution row and approval consumption (lines 27–45); consumed/interrupted/unknown approval replay rejected (lines 181–201, 269–289); concurrent replay has exactly one winner in the C585 shell test.
- **Coverage:** substantial positive/replay/atomicity coverage; direct invocation by every gateway actor and signed-envelope rejection are not established.

### 2.3 `record_effect_commit_marker`

- **Signature:** `record_effect_commit_marker(uuid, jsonb) RETURNS void`
- **Parameters:** `p_execution_id`, `p_source_identity`.
- **Owner / grant:** fixture owner `postgres`; EXECUTE only to `deedlight_ledger_runner`.
- **Required checks:** live DB identity; Runner role; valid source identity; execution exists; exact source identity equality; execution is running and its recorded runner identity equals the current effective role.
- **Allowed invocation:** Runner only, in the same transaction as the migration effect whose commit it attests.
- **Request binding:** execution UUID plus exact source JSON equality. The marker stores the runner role label, transaction ID and source identity. It does not verify a canonical signed request or cryptographically authenticated Runner identity.
- **Failure:** D1001/D1002/D1003 or D1008-family trust failures as appropriate; role mismatch, missing execution, source substitution or inactive runner fail closed.
- **Side effects on rejection:** no marker row is inserted. The caller's enclosing transaction must roll back the associated migration effect when marker insertion fails.
- **Positive test:** committed effect and marker are inserted together (lines 65–73, 153–160); crash test kills the client before commit and asserts both roll back.
- **Negative tests:** C578 crash rollback and C600 untrusted direct-call denial; wrong actor must be denied by EXECUTE ACL.
- **Coverage:** positive and crash atomicity covered; privileged gateway actor impersonation is not.

### 2.4 `capture_snapshot`

- **Signature:** `capture_snapshot(uuid, text, text) RETURNS jsonb`
- **Parameters:** `p_execution_id`, `p_phase` (`pre` or `post`), `p_query_id`.
- **Owner / grant:** fixture owner `postgres`; EXECUTE only to `deedlight_ledger_observer`.
- **Required checks:** live DB identity; Observer role; phase is valid; execution exists; Observer differs from approver and runner; pre phase requires reserved status; post phase requires running status and a matching committed marker; query is registered; SQL digest, bundle digest, manifest member count and exact query membership validate.
- **Allowed invocation:** Observer only, independently of Approver and Runner, for pre/post phase.
- **Request binding:** execution UUID, phase, registered query ID, stored SQL SHA-256 and canonical manifest digest/member pair. The SQL itself is fetched from the immutable registry and executed dynamically after integrity checks. No external signature, resource generation, caller audience or nonce is bound.
- **Failure:** D1001/D1003/D1004 and other fail-closed trust errors; invalid phase/state, non-independent observer, missing query or manifest integrity/member mismatch fail before snapshot insert.
- **Side effects on rejection:** no snapshot row is inserted and no query result is returned as an accepted snapshot.
- **Positive test:** independent pre/post snapshots for normal and partial executions (lines 56–60, 74–78, 145–166).
- **Negative tests:** post snapshot without marker rejected (lines 521–534); mismatched registered pre/post query identities cause finalization rejection (lines 428–494); C600 untrusted direct call.
- **Coverage:** positive and data-integrity negatives exist; authenticated observer principal and all cross-actor invocation attempts are not established.

### 2.5 `start_execution`

- **Signature:** `start_execution(uuid) RETURNS void`
- **Parameters:** `p_execution_id`.
- **Owner / grant:** fixture owner `postgres`; EXECUTE only to `deedlight_ledger_runner`.
- **Required checks:** live DB identity; Runner effective role; pre-execution snapshot exists; execution is reserved. On success, status becomes running and runner identity is set to the effective role.
- **Allowed invocation:** Runner after successful reserve and pre snapshot.
- **Request binding:** execution UUID and current ledger state. No source hash, canonical request, authenticated workload identity, generation, audience or nonce is supplied/validated at this step.
- **Failure:** wrong role raises `migration runner authority required`; missing pre-snapshot is D1003; non-reservable state raises an exception.
- **Side effects on rejection:** status remains unchanged and no runner identity/start timestamp is assigned.
- **Positive test:** normal and partial/crash paths (lines 61–64, 150–152, 313–315, 518–520).
- **Negative tests:** pre-snapshot absence/ordering behavior is tested through snapshot/finalization fixtures; C600 direct untrusted denial.
- **Coverage:** positive flow exists; exhaustive wrong-actor direct calls and authenticated identity are not established.

### 2.6 `heartbeat_execution`

- **Signature:** `heartbeat_execution(uuid) RETURNS void`
- **Parameters:** `p_execution_id`.
- **Owner / grant:** fixture owner `postgres`; EXECUTE only to `deedlight_ledger_runner`.
- **Required checks:** live DB identity; Runner effective role; execution is running and runner identity equals effective role.
- **Allowed invocation:** currently any caller that can assume the Runner effective role, for an execution attributed to that role.
- **Request binding:** execution UUID and role-label ownership. No heartbeat nonce, monotonic client sequence, signed workload identity or generation fence.
- **Failure:** wrong role raises `migration runner authority required`; missing/inactive/not-owned execution raises `active execution owned by this runner not found`.
- **Side effects on rejection:** heartbeat timestamp is unchanged.
- **Positive test:** normal running execution heartbeat at lines 61–64.
- **Negative tests:** wrong-owner and non-running conditions are enforced in function logic; direct C600 untrusted denial. No explicit adversarial cross-login heartbeat test was found.
- **Coverage:** limited positive; principal spoofing and stale-runner fencing not established.

### 2.7 `finalize_execution`

- **Signature:** `finalize_execution(uuid, text, jsonb) RETURNS void`
- **Parameters:** `p_execution_id`, `p_outcome` (`succeeded`, `failed`, `partial`), `p_outcome_detail` JSON object.
- **Owner / grant:** fixture owner `postgres`; EXECUTE only to `deedlight_ledger_runner`.
- **Required checks:** live DB identity; Runner role; supported terminal outcome and object detail; commit marker exists; pre and post snapshots exist; their query ID, SQL digest and bundle digest agree; execution is running and belongs to current Runner.
- **Allowed invocation:** owning Runner only, after committed marker and matching independent snapshots.
- **Request binding:** execution UUID, outcome and detail JSON; pre/post snapshot query identity and stored source/runner linkage. No signed canonical finalization envelope or verifier receipt is required.
- **Failure:** D1001/D1003/D1004/D1006/D1007 or generic state/ownership exception; update occurs only after prerequisite checks.
- **Side effects on rejection:** execution remains running; no completion timestamp or outcome detail is persisted.
- **Positive test:** succeeded and partial finalization (lines 79–83, 167–179).
- **Negative tests:** mismatched pre/post registered queries rejected (lines 428–480); terminal transition guard makes completed outcomes immutable (lines 357–369); C600 direct untrusted denial.
- **Coverage:** positive and integrity negatives exist; no direct privileged actor spoofing test.

### 2.8 `recover_stale_executions`

- **Signature:** `recover_stale_executions(interval) RETURNS integer`
- **Parameters:** `p_stale_after`, constrained to greater than zero and no more than seven days.
- **Owner / grant:** fixture owner `postgres`; EXECUTE only to `deedlight_ledger_recovery`.
- **Required checks:** live DB identity; Recovery effective role; timeout bounds; selects reserved/running executions with heartbeat older than threshold.
- **Allowed invocation:** Recovery only, under bounded stale threshold.
- **Request binding:** caller-supplied interval plus DB clock/heartbeat state. No signed recovery reason, ticket, generation, target set digest, nonce or approval is required by this fixture.
- **Failure:** D1001 missing trust; D1006 timeout outside safe bounds; wrong role fails closed.
- **Side effects on rejection:** no execution status changes. On success reserved becomes interrupted; running becomes unknown with D1008 ambiguous-outcome diagnostic.
- **Positive test:** reserved expiry and running ambiguous recovery (lines 239–267, 291–327); shell crash recovery.
- **Negative tests:** replay of interrupted/unknown execution rejected (lines 269–289 and crash replay); C600 untrusted direct-call denial.
- **Coverage:** positive and replay tests exist; recovery authorization is only an effective-role check and has no independent approval/request binding.

### 2.9 `record_verification`

- **Signature:** `record_verification(uuid, text, jsonb) RETURNS void`
- **Parameters:** `p_execution_id`, `p_verdict` (`verified`, `rejected`, `inconclusive`), `p_evidence` JSON object.
- **Owner / grant:** fixture owner `postgres`; EXECUTE only to `deedlight_ledger_verifier`.
- **Required checks:** live DB identity; Verifier effective role; supported verdict; evidence object; execution exists and is terminal; verifier effective-role name differs from approver and runner.
- **Allowed invocation:** independent Verifier only, after execution is terminal.
- **Request binding:** execution UUID, verdict and evidence object. No signed verifier identity, evidence digest/canonical envelope, independent key, or verifier workload attestation is checked.
- **Failure:** wrong role raises `independent verifier authority required`; invalid verdict/evidence raises `verification evidence invalid`; nonterminal or same-role verifier raises `verification requires terminal execution and independent verifier`.
- **Side effects on rejection:** no verification event is inserted; execution status is never changed by this RPC.
- **Positive test:** separate verifier records a verdict after successful finalization (lines 121–126).
- **Negative tests:** Runner and Approver lack EXECUTE for verification (lines 329–355); verifier cannot mutate terminal execution state (lines 357–369); C600 untrusted direct-call denial.
- **Coverage:** basic actor separation and append-only behavior tested; verifier identity is still an effective role string, not independently authenticated identity.

## 3. Exact EXECUTE grant matrix from fixture SQL

`REVOKE ALL ON ALL FUNCTIONS IN SCHEMA deedlight_execution_ledger FROM PUBLIC` is executed before the explicit grants.

| RPC | Approver | Runner | Observer | Recovery | Verifier |
|---|---:|---:|---:|---:|---:|
| approve_execution | ALLOW | DENY | DENY | DENY | DENY |
| reserve_execution | DENY | ALLOW | DENY | DENY | DENY |
| record_effect_commit_marker | DENY | ALLOW | DENY | DENY | DENY |
| capture_snapshot | DENY | DENY | ALLOW | DENY | DENY |
| start_execution | DENY | ALLOW | DENY | DENY | DENY |
| heartbeat_execution | DENY | ALLOW | DENY | DENY | DENY |
| finalize_execution | DENY | ALLOW | DENY | DENY | DENY |
| recover_stale_executions | DENY | DENY | DENY | ALLOW | DENY |
| record_verification | DENY | DENY | DENY | DENY | ALLOW |

All five roles receive schema USAGE and EXECUTE on `current_database_identity()`. The Runner additionally receives INSERT on the disposable `test_effects` fixture table and USAGE/SELECT on its identity sequence; this is not a grant on the protected ledger tables. C600 tests the Runner's direct ledger read/insert denial and Observer's inability to mutate the test-effects table.

## 4. Ownership, role membership and impersonation findings

### Confirmed in source

- Roles created: `deedlight_ledger_approver`, `deedlight_ledger_runner`, `deedlight_ledger_observer`, `deedlight_ledger_verifier`, `deedlight_ledger_recovery`.
- Each is `NOLOGIN NOINHERIT`.
- Fixture grants all five roles to `postgres`.
- Nine RPCs are SECURITY DEFINER with fixed search path.
- PUBLIC is revoked from schema, tables, sequences and all functions before explicit per-role grants.
- `actor_role()` reads `current_setting('role')`, not `session_user` or a principal registry.
- Function/table owner is the fixture creator, `postgres` in the test runner. The PostgreSQL test shell explicitly sets `PGUSER=postgres`.
- C600's untrusted role has schema USAGE but no EXECUTE; the test attempts all nine direct calls and asserts unchanged approval, execution, snapshot, marker and verification row sets.

### Direct invocation and impersonation paths

1. **Direct RPC invocation:** each actor role can call its explicitly granted functions directly. No signed authorization wrapper is present. A gateway credential holding Runner role can directly invoke all five Runner RPCs.
2. **Cross-role ACL barrier:** explicit grants prevent one non-member actor role from invoking another actor's RPC at PostgreSQL privilege checking. The existing C578 tests directly prove Runner and Approver cannot invoke `record_verification`; C600 proves an untrusted NOLOGIN role cannot invoke any of the nine.
3. **Role impersonation:** because `postgres` is a member of all five roles, it can `SET ROLE` to any actor. `actor_role()` then reports the selected role. The SQL tests intentionally use this path to simulate each actor. This is not an adversarial proof that five identities cannot impersonate one another; it demonstrates the opposite for the shared fixture superuser.
4. **Session authorization:** a superuser database login can change session authorization. The current actor check does not bind an immutable external workload identity.
5. **SECURITY DEFINER owner:** the owner runs the body with owner privileges. The owner/superuser can bypass the intended actor boundary, alter definitions/grants or manipulate the fixture. It must never be a runtime gateway credential.
6. **Shared role/connection pool:** if all actor calls use one login and set role per request, caller-controlled role switching can impersonate actor labels. Pool reset mistakes can also retain an effective role across requests.
7. **GUC spoofing:** `actor_role()` depends on the effective role setting; it does not accept arbitrary user GUC actor claims, but `SET ROLE` is itself a caller-controlled role context when membership permits it.

No claim is made that C602 closes these paths. The signed gateway wrapper, independent principal mapping, role provisioning and privilege redesign are C603 work and require DBA/Security approval.

## 5. Existing positive and negative test inventory

| Evidence | Existing test | What it proves | What it does not prove |
|---|---|---|---|
| P-01 | Normal approve → reserve → pre snapshot → start → heartbeat → marker → post snapshot → finalize → verify | All nine positive RPC paths function in disposable PostgreSQL | Independent Production logins or signed authorization |
| P-02 | Partial execution flow | Partial outcome remains partial | Gateway identity |
| P-03 | Stale reserved/running recovery | Recovery role can transition to interrupted/unknown | Recovery request approval/identity |
| N-01 | C600 direct call as `deedlight_c600_untrusted` | All nine lack EXECUTE for untrusted role; ledger rows unchanged | Privileged gateway actor direct-call denial |
| N-02 | Runner/Approver call `record_verification` | EXECUTE ACL denies two cross-role attempts | Full 5×9 adversarial matrix |
| N-03 | Duplicate/replayed approval and concurrent reservation | One-use approval and exactly one replay winner | Cryptographic request replay protection |
| N-04 | Missing marker, invalid snapshots/query mismatch | Snapshot/finalization preconditions enforced | Signed observation provenance |
| N-05 | Crash before transaction commit | Effect and marker rollback atomically | External process/workload attestation |
| N-06 | Terminal mutation | Terminal state immutable | Database owner/superuser protection |
| N-07 | Runner direct ledger read/insert and Observer fixture mutation | Operational table access constrained | Full role membership/impersonation audit |

**Missing tests:** catalog-derived exact owner/ACL assertion at CI; explicit role membership and `SET ROLE` adversarial proof; five actor roles × nine RPC invocation matrix; session-user/principal binding; gateway-role direct legacy call without signed envelope; no-side-effect row-hash assertion for every wrong actor/expired/mismatched authorization. These remain open acceptance criteria, not passing tests.

## 6. Canonical request-binding requirements for C603

C602 records that current RPC parameters are not a canonical signed authorization envelope. Before gateway access is considered safe, a future wrapper contract must bind at minimum:

- protocol/version and operation identifier (exact RPC and argument schema);
- actor class and immutable authenticated principal/workload identity;
- DeedLight project/environment and independently verified live provider resource/endpoint identity;
- deployment generation/fencing epoch and expected state transition;
- execution ID, record ID, approval ID and one-use approval identity where applicable;
- canonical source identity (normalized repository-relative path and exact SHA-256);
- typed operation parameters, outcome/verdict and canonical evidence digest;
- audience, issue/expiry times, nonce, replay/consume receipt and verifier/policy authority;
- canonical encoding version, digest algorithm, signature key ID and revocation/freshness checks.

Encoding must be deterministic and typed; reject duplicate/unknown fields, noncanonical encodings, path ambiguity, Unicode normalization ambiguity, out-of-range values, wrong audience/operation/resource/generation, expired or replayed nonces, revoked keys and missing independent signatures. The database must validate the binding before any protected mutation. This is a requirements handoff only; C602 does not implement cryptography, wrappers, credentials, or Production trust roots.

## 7. Migration and C575/C576 preservation

The C600 feature head's `supabase/migration-inventory.json` blob is `4e63f31368d446e905f4f44565be73337c7188fb`; it declares 40 SQL migration files and 39 unique versions, with one intentional duplicate-version group. A recursive Git tree comparison at C600 head enumerated exactly 40 `supabase/migrations/*.sql` paths, all matching the inventory. C602's base is that exact C600 head. C602 adds documentation only; no historical migration SQL, inventory, C575 schema/validator contract, C576 pre/postcondition contract or `catalog_only_v1` file is modified.

This is feature-branch preservation only. It does not establish main-branch or Production migration reconciliation.

## 8. Evidence classifications

| Claim | Classification | Basis |
|---|---|---|
| Nine SQL signatures and role checks | PASS | Direct inspection of fixture source |
| Nine SECURITY DEFINER / fixed search path | PASS | Direct inspection of function declarations |
| Explicit EXECUTE grants and PUBLIC revoke | PASS | Direct inspection of ACL DDL |
| Fixture owner = postgres | PASS for disposable harness | Fixture runner PGUSER=postgres; no Production owner claim |
| Five role definitions are NOLOGIN/NOINHERIT | PASS for fixture | Direct role DDL |
| Five independent Production actor identities | NOT ESTABLISHED | No login identities; shared postgres member of all roles |
| Untrusted role denied all nine direct calls, zero protected row changes | PASS in C600 exact-head PostgreSQL evidence | C600 marker in exact PR #38 PostgreSQL logs; fixture inspected |
| Full 5×9 wrong-role direct invocation matrix | NOT ESTABLISHED | Existing tests cover only selected cross-role RPCs |
| SET ROLE / session authorization cannot impersonate | FAIL in fixture model | postgres has membership in all five; actor_role reads current_setting('role') |
| Canonical signed request binding | NOT ESTABLISHED | No envelope/signature/nonce validation in nine RPCs |
| Production database privileges/owners match fixture | NOT ESTABLISHED | No Production catalog query or deployment proof |
| 40 historical migration files preserved on C600 feature head | PASS | Recursive tree and inventory agree |
| C575/C576 contracts preserved | PARTIAL | Prior C601/C600 evidence and no migration changes; no full independent contract re-audit |
| Production readiness | NO-GO | Gateway identity, impersonation, signed binding and independent review remain unresolved |

## 9. Recommended C603 handoff

**C603 — Enforce signed gateway authorization and immutable five-principal identity at the database boundary.**

Acceptance requirements:
1. DBA captures a live catalog snapshot for the disposable target: function signatures, owner, SECURITY DEFINER, proconfig/search_path, ACLs, role attributes, role memberships, default privileges and alternate callable entry points.
2. Replace the current shared-role simulator with five independent NOLOGIN capability roles plus separately authenticated, non-superuser login principals or equivalent verified principal mapping; no runtime principal may inherit or SET ROLE to another actor class.
3. Make the SECURITY DEFINER owner a dedicated NOLOGIN least-privilege owner, not a gateway login or shared superuser.
4. Revoke direct legacy RPC EXECUTE from every runtime actor login; expose only versioned authorization wrappers.
5. Verify canonical typed request signatures, independent policy/verifier approvals, resource identity, generation, audience, expiry and nonce consume receipt inside the database boundary.
6. Test direct legacy calls from every one of the five gateway principals and all nine RPCs, plus wrong-role, SET ROLE, session-authorization, pool-reuse, expired, replayed, altered-parameter, wrong-operation, wrong-resource and stale-generation attacks.
7. For every rejected case, compare full protected table hashes/counts and prove zero dispatch side effects.
8. Preserve the 40 inherited migration blobs and C575/C576 contracts; use a reviewed forward migration only after Security/DBA approval. No historical migration rewrite.
9. Run exact-head PostgreSQL 16 and full CI; inspect actual logs. No Production mutation without separate approval.

C603 must not infer Production readiness from this fixture audit. Production remains **NO-GO** until the database boundary and all external trust dependencies are independently verified.

## 10. Sources

- [C600 fixture SQL](https://github.com/ADRN-9/deedlight/blob/0d81fa5bd3892d3ec063c41a4275b9a60c14b30c/scripts/fixtures/migration-execution-ledger-v1.sql)
- [C600 positive test SQL](https://github.com/ADRN-9/deedlight/blob/0d81fa5bd3892d3ec063c41a4275b9a60c14b30c/scripts/fixtures/test-migration-execution-ledger-v1.sql)
- [C600 untrusted direct-call test](https://github.com/ADRN-9/deedlight/blob/0d81fa5bd3892d3ec063c41a4275b9a60c14b30c/scripts/fixtures/test-migration-execution-ledger-c600.sql)
- [PostgreSQL 16 runner](https://github.com/ADRN-9/deedlight/blob/0d81fa5bd3892d3ec063c41a4275b9a60c14b30c/scripts/test-migration-execution-ledger-postgres16.sh)
- [C600 trust remediation report](https://github.com/ADRN-9/deedlight/blob/0d81fa5bd3892d3ec063c41a4275b9a60c14b30c/docs/C600_EXTERNAL_TRUST_FINDINGS_REMEDIATION.md)
- [C601 evidence report / PR #39](https://github.com/ADRN-9/deedlight/pull/39)

No Production query, privilege mutation, credential access, or trust-root modification was performed.
