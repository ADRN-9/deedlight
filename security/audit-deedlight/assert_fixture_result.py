#!/usr/bin/env python3
"""Fail-closed consumer of synthetic PostgreSQL audit evidence; no DB connections."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
EXPECTED = json.loads((ROOT / "fixture_expectations.json").read_text(encoding="utf-8"))
INVENTORY = json.loads((ROOT / "invariant_inventory.json").read_text(encoding="utf-8"))
SCHEMA = json.loads((ROOT / "audited/audit_record.schema.json").read_text(encoding="utf-8"))
STATUSES = frozenset(("VERIFIED", "FAILED", "BLOCKED", "UNKNOWN"))
MAX_EVIDENCE_BYTES = 1_048_576

if EXPECTED["source_sha"] != INVENTORY["source_sha"]:
    raise AssertionError("source pin differs between expectation and inventory")
if SCHEMA["properties"]["source_sha"]["const"] != INVENTORY["source_sha"]:
    raise AssertionError("published evidence schema source pin differs")
if len(set(INVENTORY["required_invariants"])) != len(INVENTORY["required_invariants"]):
    raise AssertionError("duplicate required invariant in approved inventory")


def validate_record(record: Any) -> dict[str, Any]:
    """Validate every declared JSON Schema constraint in this pinned schema subset."""
    if not isinstance(record, dict):
        raise AssertionError("audit evidence must be a JSON object")
    required = set(SCHEMA["required"])
    properties = SCHEMA["properties"]
    if required - record.keys():
        raise AssertionError(f"missing required evidence fields: {sorted(required - record.keys())}")
    if SCHEMA.get("additionalProperties") is False and record.keys() - properties.keys():
        raise AssertionError(f"unexpected evidence properties: {sorted(record.keys() - properties.keys())}")
    for key, value in record.items():
        spec = properties[key]
        expected_type = spec.get("type")
        if expected_type == "string" and not isinstance(value, str):
            raise AssertionError(f"{key} must be a string")
        if expected_type == "boolean" and type(value) is not bool:
            raise AssertionError(f"{key} must be a boolean")
        if expected_type == "object" and not isinstance(value, dict):
            raise AssertionError(f"{key} must be an object")
        if isinstance(value, str) and len(value) < spec.get("minLength", 0):
            raise AssertionError(f"{key} shorter than schema minimum")
        if "const" in spec and value != spec["const"]:
            raise AssertionError(f"{key} differs from pinned schema constant")
        if "enum" in spec and value not in spec["enum"]:
            raise AssertionError(f"{key} is not a valid schema enum")
    if record["source_sha"] != INVENTORY["source_sha"]:
        raise AssertionError("source SHA does not match pinned audit baseline")
    return record


def records_from_psql(path: str) -> dict[str, dict]:
    """Reject incomplete transactions, SQL errors, noise, duplicates and malformed JSON."""
    raw = Path(path).read_bytes()
    if not raw or len(raw) > MAX_EVIDENCE_BYTES:
        raise AssertionError("evidence is empty or exceeds the approved size limit")
    try:
        lines = raw.decode("utf-8", errors="strict").splitlines()
    except UnicodeDecodeError as exc:
        raise AssertionError("evidence is not UTF-8") from exc
    results: dict[str, dict] = {}
    state = "before_begin"
    began = rolled_back = False
    leading_role_set = False
    for lineno, line in enumerate(lines, 1):
        if line == "SET" and state == "before_begin" and not leading_role_set:
            # Fixture H uses one SET ROLE before the read-only catalog preflight.
            leading_role_set = True
            continue
        if line == "BEGIN" and state == "before_begin":
            began = True
            state = "inside"
            continue
        if line == "ROLLBACK" and state == "inside":
            rolled_back = True
            state = "finished"
            continue
        if state == "inside" and line == "SET":
            continue
        if state == "inside" and line.startswith("{"):
            try:
                record = validate_record(json.loads(line))
            except (ValueError, TypeError) as exc:
                raise AssertionError(f"malformed JSON evidence at line {lineno}") from exc
            invariant = record["invariant"]
            if invariant in results:
                raise AssertionError(f"duplicate evidence invariant: {invariant}")
            results[invariant] = record
            continue
        raise AssertionError(f"unexpected SQL output or truncated transaction at line {lineno}")
    if not began or not rolled_back or not results:
        raise AssertionError("missing BEGIN/ROLLBACK or machine-readable evidence; STOP")
    return results


def _expected_statuses(case: str) -> dict[str, str]:
    statuses = {name: "VERIFIED" for name in INVENTORY["required_invariants"]}
    statuses.update(INVENTORY["baseline_status_exceptions"])
    statuses.update(EXPECTED["cases"][case].get("assert", {}))
    extra = EXPECTED["cases"][case].get("approved_negative_exceptions", {})
    if set(extra) - set(statuses):
        raise AssertionError(f"fixture {case}: exception refers to an unapproved invariant")
    statuses.update(extra)
    if set(statuses) != set(INVENTORY["required_invariants"]):
        raise AssertionError("expected status map does not cover the pinned inventory")
    return statuses


def assert_case(
    case: str,
    preflight: dict[str, dict] | None,
    audit: dict[str, dict] | None,
    *,
    permission_error: bool = False,
) -> None:
    if case not in EXPECTED["cases"]:
        raise AssertionError(f"unknown fixture {case}")
    if case == "H":
        if permission_error:
            if preflight is not None or audit is not None:
                raise AssertionError("permission-error STOP must not execute an audit")
            return
        if preflight is None or set(preflight) != {"metadata_access_preflight"}:
            raise AssertionError("restricted preflight evidence is missing or polluted")
        validate_record(preflight["metadata_access_preflight"])
        if preflight["metadata_access_preflight"]["status"] != "BLOCKED" or audit is not None:
            raise AssertionError("metadata preflight denied; audit must NOT execute")
        return

    if preflight is None or set(preflight) != {"metadata_access_preflight"}:
        raise AssertionError("exactly one preflight record is required")
    validate_record(preflight["metadata_access_preflight"])
    pre = preflight["metadata_access_preflight"]
    if pre["status"] != "VERIFIED" or pre["actual"].get("read_only") != "on":
        raise AssertionError("preflight must attest a read-only metadata transaction")
    if audit is None:
        raise AssertionError("complete audit evidence required")
    statuses = _expected_statuses(case)
    missing = set(statuses) - set(audit)
    if missing:
        raise AssertionError(f"missing required invariants: {sorted(missing)}")

    for invariant, row in audit.items():
        validate_record(row)
        if row["invariant"] != invariant:
            raise AssertionError(f"record key mismatch for {invariant}")
        approved_status = statuses.get(invariant)
        if approved_status is None:
            families = [family for family in INVENTORY["approved_dynamic_families"]
                        if invariant.startswith(family["prefix"])]
            if len(families) != 1:
                raise AssertionError(f"unreviewed extra invariant: {invariant}")
            if row["status"] not in families[0]["statuses"]:
                raise AssertionError(f"unexpected security status in dynamic invariant: {invariant}")
        elif row["status"] != approved_status:
            raise AssertionError(
                f"{invariant}: expected {approved_status}, observed {row['status']}"
            )

    for invariant, subset in EXPECTED["cases"][case].get("actual", {}).items():
        actual = audit[invariant]["actual"]
        for name, value in subset.items():
            if actual.get(name) != value:
                raise AssertionError(f"{invariant}.actual.{name}: expected {value!r}")


def _permission_error_from_stderr(path: str) -> bool:
    raw = Path(path).read_bytes()
    if not raw or len(raw) > 16_384:
        raise AssertionError("missing or oversized PostgreSQL denial evidence")
    message = raw.decode("utf-8", errors="strict")
    if re.search(r"(?im)\b(?:FATAL|PANIC|connection refused|could not connect)\b", message):
        raise AssertionError("transport/database failure is not metadata access denial")
    if not re.search(r"(?im)(?:permission denied for (?:relation|table|schema|function)|insufficient privilege)", message):
        raise AssertionError("unrelated PostgreSQL error cannot satisfy fixture H")
    return True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("case", choices=sorted(EXPECTED["cases"]))
    parser.add_argument("--preflight")
    parser.add_argument("--audit")
    parser.add_argument("--preflight-error", action="store_true")
    parser.add_argument("--preflight-stderr")
    args = parser.parse_args()
    if args.preflight_error and (args.case != "H" or not args.preflight_stderr):
        parser.error("metadata permission error evidence is only valid for fixture H")
    if args.preflight_error and (args.preflight or args.audit):
        parser.error("denied preflight cannot be accompanied by purported successful evidence")
    if args.case != "H" and (not args.preflight or not args.audit):
        parser.error("preflight and audit evidence required")
    if args.case == "H" and not args.preflight_error and not args.preflight:
        parser.error("restricted preflight or genuine permission-error evidence required")
    if args.preflight_stderr and not args.preflight_error:
        parser.error("preflight stderr only applies to permission-error fixture H")
    if args.preflight_error:
        _permission_error_from_stderr(args.preflight_stderr)
    preflight = records_from_psql(args.preflight) if args.preflight else None
    audit = records_from_psql(args.audit) if args.audit else None
    assert_case(args.case, preflight, audit, permission_error=args.preflight_error)
    print(f"fixture {args.case}: complete evidence and approved classifications CONFIRMED")


if __name__ == "__main__":
    main()
