#!/usr/bin/env python3
"""Validate original PR11 evidence and explicitly audit post-033 compatibility."""
from __future__ import annotations

import importlib.util
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PR11 = ROOT / "security/audit-deedlight"
spec = importlib.util.spec_from_file_location(
    "pr11_assert_fixture_result", PR11 / "assert_fixture_result.py"
)
if spec is None or spec.loader is None:
    raise RuntimeError("Unrecoverable PR11 evidence parser")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

# PR11 intentionally audits the pre-025 source. These are known, explicitly
# retained mismatches, not claims that its original schema audit passed C79.
KNOWN_LEGACY_FAIL = frozenset({
    "function:public.claim_delivery_jobs(timestamptz,integer)",
    "function:public.handle_new_user()",
    "rls:public.daily_reminder_preferences",
    "rls:public.newsletter_preferences",
    "rls:public.profiles",
    "rls:public.weekly_goodness_features",
    "rpc_acl:public.begin_delivery_transport(uuid,uuid,text)",
    "rpc_acl:public.claim_delivery_jobs(timestamptz,integer)",
    "rpc_acl:public.mark_delivery_sent(uuid,uuid,text)",
})
EXPECTED_BLOCKED = frozenset({"production_identity:independent_project_reference"})
SOURCE_TREE = "5b9fa485c0dcc67beb5b82e9623e5dff4e93260b"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def read_security_rows(path: Path) -> dict[str, dict]:
    content = path.read_text(encoding="utf-8")
    rows: dict[str, dict] = {}
    phase = "start"
    for line in content.splitlines():
        if phase == "start" and line == "BEGIN":
            phase = "inside"
        elif phase == "inside" and line == "SET":
            continue
        elif phase == "inside" and line.startswith("{"):
            row = json.loads(line)
            require(
                isinstance(row, dict)
                and isinstance(row.get("invariant"), str)
                and type(row.get("passed")) is bool
                and row.get("source_tree") == SOURCE_TREE,
                "Malformed or unpinned post-033 catalog assertion",
            )
            require(row["invariant"] not in rows, "Duplicate post-033 assertion")
            rows[row["invariant"]] = row
        elif phase == "inside" and line == "ROLLBACK":
            phase = "finished"
        else:
            raise AssertionError(f"Unexpected catalog audit output: {line[:100]}")
    require(phase == "finished" and len(rows) >= 19, "Incomplete post-033 assertions")
    return rows


def main() -> None:
    require(len(sys.argv) == 4, "Usage: verify-c79-audit-compat.py preflight legacy_catalog c79_catalog")
    preflight = module.records_from_psql(sys.argv[1])
    historical = module.records_from_psql(sys.argv[2])
    require(preflight["metadata_access_preflight"]["status"] == "VERIFIED", "Catalog preflight not verified")
    expected = module._expected_statuses("A")
    require(set(historical) == set(expected), "PR11 audit invariant coverage drifted")
    failed = frozenset(k for k, v in historical.items() if v["status"] == "FAILED")
    blocked = frozenset(k for k, v in historical.items() if v["status"] == "BLOCKED")
    require(failed == KNOWN_LEGACY_FAIL, f"Unexpected PR11 historical failures: {sorted(failed ^ KNOWN_LEGACY_FAIL)}")
    require(blocked == EXPECTED_BLOCKED, f"Unexpected PR11 blocking metadata results: {sorted(blocked)}")
    for key, record in historical.items():
        want = "FAILED" if key in KNOWN_LEGACY_FAIL else expected[key]
        require(record["status"] == want, f"Unreviewed PR11 status change: {key}")
    current = read_security_rows(Path(sys.argv[3]))
    failures = sorted(k for k, v in current.items() if not v["passed"])
    require(not failures, f"Post-033 catalog security checks failed: {failures}")
    print(json.dumps({
        "c79_post033_catalog": "pass",
        "c79_post033_checks": len(current),
        "original_pr11_fixture_matrix": "pass",
        "original_pr11_legacy_catalog": "incompatible_with_025_033",
        "original_pr11_legacy_statuses": dict(Counter(v["status"] for v in historical.values())),
        "documented_legacy_failures": sorted(failed),
        "production_identity": "not_proven",
        "full_schema_rls_attestation": "not_tested",
        "independent_security_acceptance": "not_granted",
    }, sort_keys=True))


if __name__ == "__main__":
    main()
