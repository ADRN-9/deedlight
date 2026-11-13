"""Offline consumer tests; no PostgreSQL database is used."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("assert_fixture_result", ROOT / "assert_fixture_result.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
HEAD = module.EXPECTED["source_sha"]


def result(key, status, actual=None):
    return {"source_sha": HEAD, "invariant": key, "status": status,
            "expected": "a synthetic expectation", "actual": actual or {}}


class FixtureEvidenceTests(unittest.TestCase):
    def test_all_synthetic_case_expectations_are_explicit(self):
        self.assertEqual(set(module.EXPECTED["cases"]), set("ABCDEFGHIJ"))
        for case in module.EXPECTED["cases"].values():
            self.assertIn("description", case)
            self.assertIn("assert", case)

    def test_consumer_accepts_matching_synthetic_evidence(self):
        pre = {"metadata_access_preflight": result("metadata_access_preflight", "VERIFIED")}
        for case, checks in module.EXPECTED["cases"].items():
            if case == "H":
                module.assert_case("H", None, None, permission_error=True)
                continue
            expectations = {**module.EXPECTED["common"], **checks["assert"]}
            audit = {k: result(k, v, checks.get("actual", {}).get(k)) for k, v in expectations.items()}
            module.assert_case(case, pre, audit)

    def test_consumer_rejects_mismatch(self):
        pre = {"metadata_access_preflight": result("metadata_access_preflight", "VERIFIED")}
        audit = {k: result(k, v) for k, v in {
            **module.EXPECTED["common"], **module.EXPECTED["cases"]["E"]["assert"]
        }.items()}
        with self.assertRaises(AssertionError):
            module.assert_case("E", pre, audit)

    def test_rejects_missing_and_wrong_sha_json(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "captured.txt"
            path.write_text("BEGIN\nSET\nROLLBACK\n")
            with self.assertRaises(AssertionError):
                module.records_from_psql(str(path))
            row = result("test", "VERIFIED")
            row["source_sha"] = "wrong"
            path.write_text(json.dumps(row) + "\n")
            with self.assertRaises(AssertionError):
                module.records_from_psql(str(path))

    def test_restricted_preflight_stops_audit(self):
        pre = {"metadata_access_preflight": result("metadata_access_preflight", "BLOCKED")}
        module.assert_case("H", pre, None)
        with self.assertRaises(AssertionError):
            module.assert_case("H", pre, {"some": result("some", "VERIFIED")})


if __name__ == "__main__":
    unittest.main()
