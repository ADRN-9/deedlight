"""Unit-level checks for the pinned evidence schema and full-inventory checker."""
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("assert_fixture_result", ROOT / "assert_fixture_result.py")
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
HEAD = module.EXPECTED["source_sha"]


def result(key, status, actual=None):
    return {
        "source_sha": HEAD,
        "invariant": key,
        "status": status,
        "expected": "a reviewed synthetic expectation",
        "actual": actual if actual is not None else {},
    }


class FixtureEvidenceTests(unittest.TestCase):
    def test_all_synthetic_case_expectations_are_explicit(self):
        self.assertEqual(set(module.EXPECTED["cases"]), set("ABCDEFGHIJ"))
        self.assertGreaterEqual(len(module.INVENTORY["required_invariants"]), 80)
        for case in module.EXPECTED["cases"].values():
            self.assertIn("description", case)
            self.assertIn("assert", case)

    def test_consumer_accepts_matching_full_inventory(self):
        pre = {"metadata_access_preflight": result("metadata_access_preflight", "VERIFIED", {"read_only": "on"})}
        for case, checks in module.EXPECTED["cases"].items():
            if case == "H":
                module.assert_case("H", None, None, permission_error=True)
                continue
            statuses = module._expected_statuses(case)
            audit = {key: result(key, value, checks.get("actual", {}).get(key))
                     for key, value in statuses.items()}
            module.assert_case(case, pre, audit)

    def test_consumer_rejects_scenario_mismatch(self):
        pre = {"metadata_access_preflight": result("metadata_access_preflight", "VERIFIED", {"read_only": "on"})}
        audit = {key: result(key, status)
                 for key, status in module._expected_statuses("A").items()}
        with self.assertRaises(AssertionError):
            module.assert_case("E", pre, audit)

    def test_rejects_missing_and_wrong_sha_json(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "captured.txt"
            path.write_text("BEGIN\nSET\nROLLBACK\n", encoding="utf-8")
            with self.assertRaises(AssertionError):
                module.records_from_psql(str(path))
            row = result("test", "VERIFIED")
            row["source_sha"] = "wrong"
            path.write_text("BEGIN\nSET\n" + json.dumps(row) + "\nROLLBACK\n", encoding="utf-8")
            with self.assertRaises(AssertionError):
                module.records_from_psql(str(path))

    def test_restricted_preflight_stops_audit(self):
        pre = {"metadata_access_preflight": result("metadata_access_preflight", "BLOCKED")}
        module.assert_case("H", pre, None)
        with self.assertRaises(AssertionError):
            module.assert_case("H", pre, {"some": result("some", "VERIFIED")})


if __name__ == "__main__":
    unittest.main()
