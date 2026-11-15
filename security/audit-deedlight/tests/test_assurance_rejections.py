"""End-to-end negative assurance tests: invoke the actual command-line evidence checker."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("assert_fixture_result", ROOT / "assert_fixture_result.py")
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
SOURCE_SHA = module.INVENTORY["source_sha"]


def record(invariant: str, status: str, actual: dict | None = None) -> dict:
    return {
        "source_sha": SOURCE_SHA,
        "invariant": invariant,
        "status": status,
        "expected": "Reviewed synthetic expectation",
        "actual": {} if actual is None else actual,
    }


def valid_schema_records() -> list[dict]:
    return [record(name, status) for name, status in module._expected_statuses("A").items()]


def transaction(records: list[dict], *, trailer: bool = True) -> str:
    rows = ["BEGIN", "SET"] + [json.dumps(row, separators=(",", ":")) for row in records]
    if trailer:
        rows.append("ROLLBACK")
    return "\n".join(rows) + "\n"


class AssuranceToolCLITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.preflight = Path(self.temp.name) / "preflight.txt"
        self.audit = Path(self.temp.name) / "audit.txt"
        self.records = valid_schema_records()
        self.preflight.write_text(
            transaction([record("metadata_access_preflight", "VERIFIED", {"read_only": "on"})]),
            encoding="utf-8",
        )
        self.write_audit()

    def write_audit(self, *, trailer=True):
        self.audit.write_text(transaction(self.records, trailer=trailer), encoding="utf-8")

    def invoke(self, case="A", *extra):
        return subprocess.run(
            [sys.executable, str(ROOT / "assert_fixture_result.py"), case,
             "--preflight", str(self.preflight), "--audit", str(self.audit), *extra],
            text=True, capture_output=True, check=False,
        )

    def assert_rejected(self, case="A"):
        result = self.invoke(case)
        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_healthy_complete_evidence_is_accepted(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CONFIRMED", result.stdout)

    def test_missing_required_invariant_is_rejected(self):
        self.records = [r for r in self.records if r["invariant"] != "rls:public.delivery_ledger"]
        self.write_audit()
        self.assert_rejected()

    def test_duplicate_invariant_is_rejected(self):
        self.records.append(dict(self.records[0]))
        self.write_audit()
        self.assert_rejected()

    def test_unexpected_failed_security_result_is_rejected(self):
        next(r for r in self.records if r["invariant"] == "rls:public.delivery_ledger")["status"] = "FAILED"
        self.write_audit()
        self.assert_rejected()

    def test_unexpected_blocked_security_result_is_rejected(self):
        next(r for r in self.records if r["invariant"] == "rpc_acl:public.begin_delivery_transport(uuid,uuid,text)")["status"] = "BLOCKED"
        self.write_audit()
        self.assert_rejected()

    def test_malformed_json_is_rejected(self):
        self.audit.write_text('BEGIN\nSET\n{bad json}\nROLLBACK\n', encoding="utf-8")
        self.assert_rejected()

    def test_invalid_evidence_schema_is_rejected(self):
        self.records[0]["unexpected_field"] = "unapproved"
        self.write_audit()
        self.assert_rejected()
        del self.records[0]["unexpected_field"]
        self.records[0]["expected"] = {"wrong": "type"}
        self.write_audit()
        self.assert_rejected()

    def test_truncated_transaction_is_rejected(self):
        self.write_audit(trailer=False)
        self.assert_rejected()

    def test_missing_records_after_partial_output_are_rejected(self):
        self.records = self.records[:7]
        self.write_audit()
        self.assert_rejected()

    def test_incorrect_scenario_classification_is_rejected(self):
        self.assert_rejected("E")  # Healthy schema must not count as a negative grant fixture.

    def test_unrelated_postgres_error_is_rejected(self):
        self.audit.write_text(transaction(self.records) + "ERROR: division by zero\n", encoding="utf-8")
        self.assert_rejected()

    def test_unreviewed_security_dynamic_result_is_rejected(self):
        self.records.append(record("policy:public.delivery_ledger.example_policy", "FAILED"))
        self.write_audit()
        self.assert_rejected()

    def test_unreviewed_extra_invariant_is_rejected(self):
        self.records.append(record("injected:unreviewed", "VERIFIED"))
        self.write_audit()
        self.assert_rejected()

    def test_required_unknown_cannot_be_silently_promoted(self):
        next(r for r in self.records
             if r["invariant"].startswith("function_source:public.set_daily_reminder_preference"))["status"] = "VERIFIED"
        self.write_audit()
        self.assert_rejected()

    def test_unrelated_denial_stderr_cannot_satisfy_restricted_fixture(self):
        fake = Path(self.temp.name) / "denial.stderr"
        fake.write_text("FATAL: could not connect to server\n", encoding="utf-8")
        outcome = subprocess.run(
            [sys.executable, str(ROOT / "assert_fixture_result.py"), "H",
             "--preflight-error", "--preflight-stderr", str(fake)],
            text=True, capture_output=True, check=False,
        )
        self.assertNotEqual(outcome.returncode, 0)


if __name__ == "__main__":
    unittest.main()
