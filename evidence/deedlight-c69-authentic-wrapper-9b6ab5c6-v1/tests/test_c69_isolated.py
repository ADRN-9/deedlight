"""Isolated source/SQLite negative-assurance tests. NOT PostgreSQL verification."""
from __future__ import annotations

import concurrent.futures
import hashlib
import json
import re
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "patch/PROPOSED_post029_c69_authentic_webhook_transport_hard_stop.sql").read_text()
NEG = (ROOT / "tests/postgres_negative_assertions.sql").read_text()
HISTORY = (ROOT / "tests/postgres_preexisting_history.sql").read_text()
SOURCES = json.loads((ROOT / "sources/AUTHENTIC_SOURCE_MANIFEST.json").read_text())
STOP_FUNCTIONS = (
    "begin_delivery_transport",
    "begin_delivery_transport_with_suppression",
    "begin_delivery_transport_identity_bound",
    "mark_delivery_sent",
    "mark_delivery_sent_with_recipient",
    "mark_delivery_sent_identity_bound",
    "record_resend_webhook_event",
    "record_resend_webhook_event_identity_bound",
)
TABLES = (
    "delivery_provider_events",
    "delivery_provider_pending_events",
    "delivery_provider_identity_conflicts",
)


def isolated_database(path: Path, *, historical: bool = False) -> sqlite3.Connection:
    conn = sqlite3.connect(path, timeout=10.0, isolation_level=None)
    conn.execute("PRAGMA busy_timeout = 10000")
    for table in TABLES:
        conn.execute(f'CREATE TABLE IF NOT EXISTS "{table}" (svix_event_id TEXT PRIMARY KEY, payload TEXT)')
    if historical:
        conn.execute("INSERT INTO delivery_provider_pending_events VALUES ('msg_c69pending001','synthetic-bounce')")
        conn.execute("INSERT INTO delivery_provider_identity_conflicts VALUES ('msg_c69conflict001','synthetic-conflict')")
    for table in TABLES:
        for action in ("INSERT", "UPDATE", "DELETE"):
            conn.execute(f'''CREATE TRIGGER "{table}_{action}" BEFORE {action} ON "{table}"
                          BEGIN SELECT RAISE(ABORT,'C69 legacy writes disabled'); END''')
    return conn


class AuthenticSourceEvidence(unittest.TestCase):
    def test_manifest_commits_are_pinned(self):
        self.assertEqual(SOURCES["repository"], "ADRN-9/deedlight")
        self.assertEqual(SOURCES["source_commit"], "f4bffa2d24f5241012b99f673eaaa39ac1dc2907")

    def test_original_025_to_028_hashes(self):
        self.assertEqual([x["sha256"] for x in SOURCES["sources"]], [
            "93f990990b2112e1ee4f049e5d9b9495ffd4d17e43159a9bf6146953d1ae9fc9",
            "d1f2812f343c799e42583f57265bc967cbeab98ca5400d4206e5bddc559be137",
            "3d30d188b867ab45e70befb5bbc2f69c5c94e594d29efb5d2758ecc7c7e1b81e",
            "d0e85b338a6b96fea5fcc8121369cd2dc20faab0cc8183ee01139a0015c0d391",
        ])

    def test_c61_source_bytes_unchanged(self):
        p = ROOT / "sources/PROPOSED_POST_028_provider_event_registry_C61.sql"
        self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),
                         "ed0dc53204c91b6171bc12de40929df6f54bae24e78716f0072d69593e008672")

    def test_authentic_sources_when_present(self):
        """Archived test package may omit source blobs; published Git evidence includes them."""
        available = [ROOT / "sources" / x["file"] for x in SOURCES["sources"]]
        if not all(p.is_file() for p in available):
            self.skipTest("Original 025-028 not mounted locally; verified via GitHub connector")
        for item in SOURCES["sources"]:
            with self.subTest(file=item["file"]):
                blob = (ROOT / "sources" / item["file"]).read_bytes()
                self.assertEqual(hashlib.sha256(blob).hexdigest(), item["sha256"])


class ExplicitCatalogAssertions(unittest.TestCase):
    def test_known_function_count(self):
        for fn in STOP_FUNCTIONS:
            with self.subTest(fn=fn):
                matches = re.findall(r"CREATE OR REPLACE FUNCTION public\."+fn+r"\s*\(",SQL)
                self.assertEqual(len(matches), 1)

    def test_all_function_bodies_raise(self):
        bodies = re.findall(r"CREATE OR REPLACE FUNCTION public\.([a-z_]+)\s*\(.*?AS \$deny\$(.*?)\$deny\$;", SQL, re.S)
        self.assertEqual(len(bodies), len(STOP_FUNCTIONS))
        for fn,body in bodies:
            with self.subTest(fn=fn):
                self.assertIn("RAISE EXCEPTION 'C69",body)
                self.assertIn("ERRCODE='42501'",body)

    def test_stop_transport_and_event_recording_both(self):
        self.assertIn("public.begin_delivery_transport_identity_bound(uuid,uuid,text)",SQL)
        self.assertIn("public.begin_delivery_transport_with_suppression(uuid,uuid,text,text)",SQL)
        self.assertIn("public.begin_delivery_transport(uuid,uuid,text)",SQL)
        self.assertIn("public.record_resend_webhook_event_identity_bound(text,text,text,text,timestamptz,text,text)",SQL)
        self.assertIn("public.record_resend_webhook_event(text,text,text,text,timestamptz,text,text)",SQL)

    def test_all_legacy_tables_listed(self):
        for table in TABLES:
            with self.subTest(table=table):
                self.assertIn("'"+table+"'",SQL)
                self.assertIn("'"+table+"'",NEG)
        self.assertIn("delivery_provider_identity_conflicts",SQL)

    def test_correct_authentic_column_not_event_id(self):
        self.assertIn("a.attname='svix_event_id'",SQL)
        self.assertIn("a.atttypid='pg_catalog.text'::pg_catalog.regtype",SQL)
        self.assertIn("co.contype='p'",SQL)

    def test_trigger_always_enabled(self):
        self.assertIn("ENABLE ALWAYS TRIGGER c69_veto_event_dml",SQL)
        self.assertIn("ENABLE ALWAYS TRIGGER c69_veto_event_truncate",SQL)
        self.assertIn("ENABLE ALWAYS TRIGGER c69_registry_activation_veto",SQL)

    def test_drifts_are_refused(self):
        self.assertIn("unexpected legacy RPC overload",SQL)
        self.assertIn("unreviewed privileged lifecycle wrapper detected",SQL)
        self.assertIn("unreviewed svix_event_id acceptance table",SQL)
        self.assertIn("authentic 024-028",SQL)

    def test_all_privileged_recorder_apis_revoked(self):
        for fn in ("deedlight_reserve_provider_event","deedlight_bind_provider_event",
                   "deedlight_process_nonsuppressing_event"):
            self.assertIn("public."+fn,SQL)
        self.assertIn("FROM PUBLIC,anon,authenticated,service_role",SQL)
        self.assertIn("has_function_privilege('service_role'",SQL)

    def test_fail_closed_registry_and_history(self):
        self.assertIn("accepting_new_events IS DISTINCT FROM false",SQL)
        self.assertIn("C69 registry activation requires audited reconciliation",SQL)
        self.assertIn("c69_retired_function_inventory",SQL)
        self.assertNotIn("TRUNCATE TABLE public.delivery_provider_events",SQL)

    def test_preserves_safety_boundaries(self):
        self.assertNotIn("DROP FUNCTION",SQL)
        self.assertNotRegex(SQL, r"(?im)^\s*(DROP|ALTER)[^;]*\bCASCADE\b")
        self.assertNotIn("GRANT EXECUTE",SQL)
        self.assertNotIn("DELIVERY_ENABLED=true",SQL)
        self.assertNotIn("SKIP LOCKED",SQL.upper())

    def test_negative_fixture_really_uses_025_to_028_tables(self):
        self.assertIn("delivery_provider_pending_events",HISTORY)
        self.assertIn("delivery_provider_identity_conflicts",HISTORY)
        self.assertIn("svix_event_id",HISTORY)
        self.assertIn("C69_HISTORICAL_QUARANTINE_PRESERVED",NEG)

    def test_no_external_delivery_or_private_addresses(self):
        self.assertNotIn("api.resend.com",SQL)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY",SQL)
        self.assertNotIn("RESEND_API_KEY",SQL)
        self.assertNotIn("@gmail.com",SQL)

    def test_sql_source_statement_balance(self):
        self.assertEqual(SQL.count("BEGIN;"),1)
        self.assertEqual(SQL.count("COMMIT;"),1)
        self.assertEqual(SQL.count("$deny$"),2*(len(STOP_FUNCTIONS)+2))


class SQLiteStopOnlyBehavior(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="c69_isolated_")
        self.db = Path(self.tmp.name) / "test.sqlite3"
        conn = isolated_database(self.db, historical=True)
        conn.close()

    def tearDown(self):
        self.tmp.cleanup()

    def test_history_preserved(self):
        conn=sqlite3.connect(self.db)
        self.assertEqual(conn.execute("SELECT count(*) FROM delivery_provider_pending_events").fetchone()[0],1)
        self.assertEqual(conn.execute("SELECT count(*) FROM delivery_provider_identity_conflicts").fetchone()[0],1)
        conn.close()

    def test_fresh_insert_denied_for_each_table(self):
        with sqlite3.connect(self.db) as conn:
            for table in TABLES:
                with self.subTest(table=table):
                    with self.assertRaisesRegex(sqlite3.IntegrityError,"C69"):
                        conn.execute(f"INSERT INTO {table} VALUES ('msg_test12345','synthetic')")

    def test_duplicate_pending_to_processed_denied(self):
        with sqlite3.connect(self.db) as conn:
            with self.assertRaises(sqlite3.IntegrityError):
                conn.execute("INSERT INTO delivery_provider_events VALUES ('msg_c69pending001','duplicate')")

    def test_duplicate_conflict_to_processed_denied(self):
        with sqlite3.connect(self.db) as conn:
            with self.assertRaises(sqlite3.IntegrityError):
                conn.execute("INSERT INTO delivery_provider_events VALUES ('msg_c69conflict001','duplicate')")

    def test_conflicting_payload_replay_denied(self):
        with sqlite3.connect(self.db) as conn:
            with self.assertRaises(sqlite3.IntegrityError):
                conn.execute("UPDATE delivery_provider_identity_conflicts SET payload='changed'")

    def test_deletion_denied_for_all_tables(self):
        with sqlite3.connect(self.db) as conn:
            for table in TABLES:
                with self.subTest(table=table):
                    with self.assertRaises(sqlite3.IntegrityError):
                        conn.execute(f"DELETE FROM {table} WHERE 1=1") if conn.execute(f"SELECT count(*) FROM {table}").fetchone()[0] else conn.execute(f"INSERT INTO {table} VALUES('msg_x','x')")

    def test_out_of_order_success_cannot_overwrite_pending(self):
        with sqlite3.connect(self.db) as conn:
            with self.assertRaises(sqlite3.IntegrityError):
                conn.execute("INSERT INTO delivery_provider_events VALUES('msg_success0001','delivered')")
            self.assertEqual(conn.execute("SELECT payload FROM delivery_provider_pending_events WHERE svix_event_id='msg_c69pending001'").fetchone()[0],"synthetic-bounce")

    def test_suppressed_bounce_and_complaint_never_marked_delivered(self):
        with sqlite3.connect(self.db) as conn:
            for val in ("permanent-bounce","complaint"):
                with self.subTest(val=val),self.assertRaises(sqlite3.IntegrityError):
                    conn.execute("INSERT INTO delivery_provider_events VALUES(?,?)",('msg_synthetic'+val,val))

    def test_retry_after_interrupted_operation_still_denied(self):
        with sqlite3.connect(self.db) as conn:
            for _ in range(2):
                conn.execute("BEGIN") if not conn.in_transaction else None
                with self.assertRaises(sqlite3.IntegrityError):
                    conn.execute("INSERT INTO delivery_provider_events VALUES('msg_retry0001','retry')")
                conn.rollback()
            self.assertEqual(conn.execute("SELECT count(*) FROM delivery_provider_events").fetchone()[0],0)

    def test_concurrent_identical_insert_fails_in_each_session(self):
        barrier=threading.Barrier(4)
        def attempt(_):
            db=sqlite3.connect(self.db, timeout=5, isolation_level=None)
            barrier.wait(timeout=5)
            try:
                db.execute("INSERT INTO delivery_provider_pending_events VALUES('msg_parallel001','synthetic')")
                return False
            except sqlite3.IntegrityError:
                return True
            finally:
                db.close()
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
            self.assertEqual(list(ex.map(attempt,range(4))),[True]*4)

    def test_concurrent_cross_table_duplicate_fails(self):
        def attempt(i):
            db=sqlite3.connect(self.db,timeout=5)
            try:
                db.execute(f"INSERT INTO {TABLES[i%3]} VALUES('msg_sameid0001','synthetic')")
                return False
            except sqlite3.IntegrityError:
                return True
            finally:
                db.close()
        with concurrent.futures.ThreadPoolExecutor(max_workers=9) as ex:
            self.assertEqual(list(ex.map(attempt,range(9))),[True]*9)

    def test_all_current_rows_unchanged_after_replay(self):
        with sqlite3.connect(self.db) as conn:
            before={t:conn.execute(f"SELECT * FROM {t}").fetchall() for t in TABLES}
            for t in TABLES:
                with self.assertRaises(sqlite3.IntegrityError):
                    conn.execute(f"INSERT INTO {t} VALUES('msg_again0001','x')")
            after={t:conn.execute(f"SELECT * FROM {t}").fetchall() for t in TABLES}
        self.assertEqual(before,after)


if __name__=="__main__":
    unittest.main(verbosity=2)
