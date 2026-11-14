"""Isolated source contract and SQLite stand-in only — NOT PostgreSQL validation."""
from __future__ import annotations

import pathlib
import sqlite3
import tempfile
import threading
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SQL = (ROOT / "patch/202611140031_c67_closed_world_legacy_webhook_hard_stop.sql").read_text()
HISTORICAL = (ROOT / "provenance/ORIGINAL_C65_UNCHANGED.sql").read_text()


class SourceGuards(unittest.TestCase):
    def test_both_legacy_rpc_families(self):
        self.assertIn("'record_resend_webhook_event'", SQL)
        self.assertIn("'record_resend_webhook_event_identity_bound'", SQL)

    def test_base_not_whitelisted_in_post_retirement_guard(self):
        self.assertIn("C67 legacy webhook RPC family remains", SQL)
        self.assertIn("DROP FUNCTION %s RESTRICT", SQL)

    def test_retire_wrapper_before_base(self):
        self.assertIn("CASE WHEN p.proname='record_resend_webhook_event_identity_bound'", SQL)
        self.assertIn("THEN 0 ELSE 1 END", SQL)

    def test_no_cascade(self):
        self.assertNotIn("DROP FUNCTION %s CASCADE", SQL)
        self.assertNotIn("DROP TABLE", SQL)

    def test_explicit_conflict_inventory(self):
        self.assertIn("'delivery_provider_identity_conflicts'", SQL)
        self.assertIn("role_in_pipeline = 'identity_conflict'", SQL)

    def test_not_regex_name_discovery(self):
        self.assertNotIn("c.relname ~*", SQL)
        self.assertIn("pg_temp.c67_reviewed_event_tables", SQL)

    def test_all_three_categories_attested(self):
        for label in ("processed", "pending", "identity_conflict"):
            self.assertIn(f"role_in_pipeline = '{label}'", SQL)

    def test_unattested_event_table_fails(self):
        self.assertIn("C67 found an unreviewed provider-event acceptance table", SQL)

    def test_missing_inventory_fails_before_ddl(self):
        self.assertLess(SQL.index("C67 missing verified registry/024/025-028 inventory"),
                        SQL.index("CREATE TABLE deedlight_event_private.c67_legacy_veto_inventory"))

    def test_requires_inactive_registry(self):
        self.assertIn("accepting_new_events", SQL)
        self.assertIn("C67 requires registry to remain disabled", SQL)

    def test_registry_cannot_be_enabled_by_normal_update(self):
        self.assertIn("c67_reject_registry_activation", SQL)
        self.assertIn("BEFORE UPDATE OF accepting_new_events", SQL)
        self.assertIn("ENABLE ALWAYS TRIGGER c67_registry_activation_veto", SQL)

    def test_veto_all_normal_dml(self):
        self.assertIn("BEFORE INSERT OR UPDATE OR DELETE", SQL)
        self.assertIn("ENABLE ALWAYS TRIGGER c67_deny_legacy_event_dml", SQL)

    def test_veto_truncate(self):
        self.assertIn("BEFORE TRUNCATE", SQL)
        self.assertIn("ENABLE ALWAYS TRIGGER c67_deny_legacy_event_truncate", SQL)

    def test_private_schema_search_path(self):
        self.assertGreaterEqual(SQL.count("SET search_path = pg_catalog, pg_temp"), 2)
        self.assertIn("SECURITY INVOKER", SQL)
        self.assertNotIn("SECURITY DEFINER", SQL.split("CREATE FUNCTION deedlight_event_private.c67_reject_legacy_event_write()",1)[1].split("DO $c67_install$",1)[0])

    def test_browser_and_service_role_revocations(self):
        self.assertIn("FROM PUBLIC, anon, authenticated, service_role", SQL)
        self.assertIn("REVOKE EXECUTE ON FUNCTION public.begin_delivery_transport(uuid,uuid,text)", SQL)

    def test_transport_fail_closed_when_bounces_unprocessed(self):
        self.assertIn("has_function_privilege('service_role'", SQL)
        self.assertIn("C67 outbound transport permission not closed", SQL)

    def test_role_cannot_be_table_owner_member(self):
        for role in ("service_role", "anon", "authenticated"):
            self.assertIn(f"pg_has_role('{role}'", SQL)

    def test_dependent_object_evidence(self):
        self.assertIn("pg_catalog.pg_depend", SQL)
        self.assertIn("dependent_objects_before", SQL)

    def test_capture_function_provenance(self):
        for label in ("owner_role", "security_definer", "source_md5", "search_path_setting"):
            self.assertIn(label, SQL)

    def test_restrict_on_dependency(self):
        self.assertIn("DROP FUNCTION %s RESTRICT", SQL)
        self.assertIn("C67 authentic base/wrapper RPC signatures missing", SQL)

    def test_migration_is_transactional(self):
        self.assertIn("BEGIN;", SQL)
        self.assertIn("COMMIT;", SQL)
        self.assertIn("SET LOCAL lock_timeout", SQL)
        self.assertIn("SET LOCAL statement_timeout", SQL)

    def test_no_hidden_registry_activation(self):
        self.assertNotIn("SET accepting_new_events = true", SQL)
        self.assertNotIn("VALUES (true,true)", SQL)

    def test_c65_catalog_tripwire_would_prevent_base(self):
        self.assertIn("AND p.proname = 'record_resend_webhook_event_identity_bound'", HISTORICAL)
        self.assertIn("Additional legacy acceptance entry point requires source review", HISTORICAL)

    def test_current_proposal_not_in_production_flow(self):
        self.assertIn("NEVER run against Production", SQL)
        self.assertIn("The reviewed source/manifest is NOT present", SQL)

    def test_fixture_names_are_explicitly_synthetic(self):
        fixture = (ROOT / "tests/fixture_synthetic_legacy_025_028.sql").read_text()
        self.assertIn("SYNTHETIC fixture", fixture)
        self.assertIn("public.delivery_provider_identity_conflicts", fixture)

    def test_github_audit_gate_not_weakened(self):
        self.assertNotIn("npm audit", SQL)  # SQL cannot alter npm audit configuration


class SurrogateBarriers(unittest.TestCase):
    """SQLite test double for independent old event stores and hard-stop triggers."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="deedlight_c67_test_")
        self.path = pathlib.Path(self.tmp.name) / "test.sqlite"
        self.db = sqlite3.connect(self.path)
        self.db.executescript("""
        CREATE TABLE registry(provider TEXT NOT NULL,event_id TEXT NOT NULL,
                              state TEXT NOT NULL DEFAULT 'pending',
                              PRIMARY KEY(provider,event_id));
        CREATE TABLE processed(provider TEXT,event_id TEXT,kind TEXT);
        CREATE TABLE pending(provider TEXT,event_id TEXT,kind TEXT);
        CREATE TABLE conflicts(provider TEXT,event_id TEXT,reason TEXT);
        CREATE TABLE control(accepting INTEGER NOT NULL);
        INSERT INTO control VALUES(0);
        INSERT INTO processed VALUES('resend','evt_historical','email.bounced');
        INSERT INTO pending VALUES('resend','evt_historical','email.complained');
        INSERT INTO conflicts VALUES('resend','evt_historical','recipient_changed');
        """)
        self.db.commit()
        for table in ("processed", "pending", "conflicts"):
            for method in ("INSERT", "UPDATE", "DELETE"):
                name = f"deny_{table}_{method.lower()}"
                self.db.execute(f"CREATE TRIGGER {name} BEFORE {method} ON {table} "
                                "BEGIN SELECT RAISE(ABORT,'C67 legacy acceptance closed'); END")
        self.db.execute("""CREATE TRIGGER refuse_activation BEFORE UPDATE OF accepting ON control
                           WHEN NEW.accepting <> 0
                           BEGIN SELECT RAISE(ABORT,'C67 intake disabled'); END""")
        self.db.commit()

    def tearDown(self):
        self.db.close()
        self.tmp.cleanup()

    def test_historical_processed_survives(self):
        self.assertEqual(1, self.db.execute("SELECT count(*) FROM processed").fetchone()[0])

    def test_historical_pending_survives(self):
        self.assertEqual(1, self.db.execute("SELECT count(*) FROM pending").fetchone()[0])

    def test_historical_conflict_survives(self):
        self.assertEqual(1, self.db.execute("SELECT count(*) FROM conflicts").fetchone()[0])

    def test_duplicate_provider_id_in_history_not_erased(self):
        self.assertEqual(3, sum(self.db.execute(f"SELECT count(*) FROM {t} WHERE event_id='evt_historical'").fetchone()[0]
                                for t in ("processed", "pending", "conflicts")))

    def test_base_rpc_proxy_denied(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO processed VALUES('resend','evt_retry','email.bounced')")

    def test_identity_bound_proxy_denied(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO conflicts VALUES('resend','evt_retry','mismatch')")

    def test_pending_store_denied(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO pending VALUES('resend','evt_retry','email.bounced')")

    def test_update_evidence_denied(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE conflicts SET reason='erased'")

    def test_delete_evidence_denied(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("DELETE FROM pending")

    def test_intake_activation_denied(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE control SET accepting=1")

    def test_registry_unique_identity_when_manually_enabled_in_surrogate(self):
        self.db.execute("INSERT INTO registry(provider,event_id) VALUES('resend','evt_unique')")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO registry(provider,event_id) VALUES('resend','evt_unique')")

    def test_all_conflicting_stores_remain_unchanged_after_failure(self):
        for table in ("processed", "pending", "conflicts"):
            self.assertEqual(1, self.db.execute(f"SELECT count(*) FROM {table}").fetchone()[0])

    def test_concurrent_attempts_to_different_legacy_stores_both_fail(self):
        errors: list[str] = []
        gate = threading.Barrier(3)

        def attempt(table: str):
            conn = sqlite3.connect(self.path, timeout=5)
            gate.wait(timeout=5)
            try:
                conn.execute(f"INSERT INTO {table} VALUES('resend','evt_race','email.bounced')")
                conn.commit()
            except sqlite3.IntegrityError:
                errors.append(table)
            finally:
                conn.close()

        th = [threading.Thread(target=attempt, args=(table,)) for table in ("processed", "pending")]
        for t in th: t.start()
        gate.wait(timeout=5)
        for t in th: t.join(timeout=10)
        self.assertCountEqual(["processed", "pending"], errors)
        self.assertEqual(0, self.db.execute("SELECT count(*) FROM processed WHERE event_id='evt_race'").fetchone()[0])
        self.assertEqual(0, self.db.execute("SELECT count(*) FROM pending WHERE event_id='evt_race'").fetchone()[0])

    def test_transaction_atomicity_of_rejected_event(self):
        with self.assertRaises(sqlite3.IntegrityError):
            with self.db:
                self.db.execute("INSERT INTO registry VALUES('resend','evt_atomic','pending')")
                self.db.execute("INSERT INTO conflicts VALUES('resend','evt_atomic','dup')")
        self.assertEqual(0, self.db.execute("SELECT count(*) FROM registry WHERE event_id='evt_atomic'").fetchone()[0])


if __name__ == '__main__':
    unittest.main()
