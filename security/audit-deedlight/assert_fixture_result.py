#!/usr/bin/env python3
"""Validate synthetic PostgreSQL audit JSON; never connects to a database."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
EXPECTED = json.loads((ROOT / "fixture_expectations.json").read_text(encoding="utf-8"))


def records_from_psql(path: str) -> dict[str, dict]:
    results: dict[str, dict] = {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line.startswith("{"):
            continue
        record = json.loads(line)
        for field in ("source_sha", "invariant", "status", "expected", "actual"):
            if field not in record:
                raise AssertionError(f"missing {field}")
        if record["source_sha"] != EXPECTED["source_sha"]:
            raise AssertionError("source SHA mismatch")
        if record["status"] not in {"VERIFIED", "FAILED", "BLOCKED", "UNKNOWN"}:
            raise AssertionError("unexpected status")
        if not isinstance(record["actual"], dict):
            raise AssertionError("actual metadata must be an object")
        invariant = record["invariant"]
        if invariant in results:
            raise AssertionError(f"duplicate invariant: {invariant}")
        results[invariant] = record
    if not results:
        raise AssertionError("no machine-readable JSON records; do not infer PASS")
    return results


def assert_case(
    case: str,
    preflight: dict[str, dict] | None,
    audit: dict[str, dict] | None,
    *,
    permission_error: bool = False,
) -> None:
    spec = EXPECTED["cases"][case]
    if case == "H":
        if permission_error:
            if preflight or audit:
                raise AssertionError("permission-error STOP must not run audit")
            return
        if not preflight or preflight["metadata_access_preflight"]["status"] != "BLOCKED":
            raise AssertionError("restricted metadata preflight must be BLOCKED")
        if audit:
            raise AssertionError("preflight BLOCKED; audit must not run")
        return

    if not preflight or preflight["metadata_access_preflight"]["status"] != "VERIFIED":
        raise AssertionError("metadata preflight not VERIFIED; STOP")
    if not audit:
        raise AssertionError("audit results missing")
    for invariant, status in {**EXPECTED["common"], **spec["assert"]}.items():
        if invariant not in audit:
            raise AssertionError(f"missing invariant {invariant}")
        observed = audit[invariant]["status"]
        if observed != status:
            raise AssertionError(f"{invariant}: expected {status}, observed {observed}")
    for invariant, subset in spec.get("actual", {}).items():
        actual = audit[invariant]["actual"]
        for name, value in subset.items():
            if actual.get(name) != value:
                raise AssertionError(f"{invariant}.actual.{name}: expected {value!r}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("case", choices=sorted(EXPECTED["cases"]))
    parser.add_argument("--preflight")
    parser.add_argument("--audit")
    parser.add_argument("--preflight-error", action="store_true")
    args = parser.parse_args()
    if args.preflight_error and args.case != "H":
        parser.error("preflight-error classification is only accepted in restricted fixture H")
    if args.case != "H" and (not args.preflight or not args.audit):
        parser.error("preflight and audit evidence required")
    if args.case == "H" and not args.preflight_error and not args.preflight:
        parser.error("restricted fixture requires preflight evidence or a permission error")
    preflight = records_from_psql(args.preflight) if args.preflight else None
    audit = records_from_psql(args.audit) if args.audit else None
    assert_case(args.case, preflight, audit, permission_error=args.preflight_error)
    print(f"fixture {args.case}: expected classifications CONFIRMED")


if __name__ == "__main__":
    main()
