"""Isolated C65 regression: real SQLite transactions + SQL source contract.
This is NOT PostgreSQL execution and cannot certify the missing 025-028 schema.
"""
import sqlite3
import threading
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / 'patch/202611140030_close_legacy_webhook_acceptance.sql').read_text()


def setup(db):
    con = sqlite3.connect(db, isolation_level=None, timeout=15)
    con.executescript('''
      PRAGMA journal_mode=WAL;
      CREATE TABLE registry(provider TEXT NOT NULL, event_id TEXT NOT NULL,
        digest TEXT NOT NULL, event_type TEXT NOT NULL,
        state TEXT NOT NULL CHECK(state IN ('pending','processed','identity_conflict')),
        PRIMARY KEY(provider,event_id));
      CREATE TABLE legacy_processed(provider TEXT, event_id TEXT);
      CREATE TABLE legacy_pending(provider TEXT, event_id TEXT);
      CREATE TABLE legacy_conflict(provider TEXT, event_id TEXT);
      CREATE TABLE control(singleton INTEGER PRIMARY KEY, enabled INTEGER NOT NULL);
      INSERT INTO control VALUES(1,0);
      CREATE TRIGGER reject_legacy_processed BEFORE INSERT ON legacy_processed BEGIN SELECT RAISE(ABORT,'c65 veto'); END;
      CREATE TRIGGER reject_legacy_pending BEFORE INSERT ON legacy_pending BEGIN SELECT RAISE(ABORT,'c65 veto'); END;
      CREATE TRIGGER reject_legacy_conflict BEFORE INSERT ON legacy_conflict BEGIN SELECT RAISE(ABORT,'c65 veto'); END;
    ''')
    return con


def reserve(con, event, digest='aaa', state='pending'):
    if con.execute('SELECT enabled FROM control WHERE singleton=1').fetchone() != (1,):
        raise PermissionError('registry disabled pending reconciliation')
    con.execute('BEGIN IMMEDIATE')
    try:
        cur = con.execute('SELECT digest,state FROM registry WHERE provider=? AND event_id=?', ('resend',event)).fetchone()
        if cur is None:
            con.execute('INSERT INTO registry VALUES (?,?,?,?,?)', ('resend',event,digest,'email.bounced',state))
            result='NEW_PENDING'
        elif cur[0]!=digest:
            con.execute('UPDATE registry SET state=? WHERE provider=? AND event_id=?',('identity_conflict','resend',event))
            result='IDENTITY_CONFLICT'
        else:
            result='DUPLICATE_'+cur[1].upper()
        con.commit()
        return result
    except BaseException:
        con.rollback()
        raise


class C65ReferenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.db=Path(self.tmp.name)/'synthetic.db'
        self.con=setup(self.db)
        self.addCleanup(self.con.close)

    def test_01_disabled_registry_fails_closed(self):
        with self.assertRaises(PermissionError): reserve(self.con,'evt_a')
        self.assertEqual(self.con.execute('SELECT COUNT(*) FROM registry').fetchone()[0],0)

    def test_02_process_legacy_veto(self):
        with self.assertRaises(sqlite3.IntegrityError): self.con.execute("INSERT INTO legacy_processed VALUES('resend','evt_a')")

    def test_03_pending_legacy_veto(self):
        with self.assertRaises(sqlite3.IntegrityError): self.con.execute("INSERT INTO legacy_pending VALUES('resend','evt_a')")

    def test_04_conflict_legacy_veto(self):
        with self.assertRaises(sqlite3.IntegrityError): self.con.execute("INSERT INTO legacy_conflict VALUES('resend','evt_a')")

    def test_05_legacy_veto_persists_after_enable(self):
        self.con.execute('UPDATE control SET enabled=1')
        self.assertEqual(reserve(self.con,'evt_a'),'NEW_PENDING')
        for table in ('legacy_processed','legacy_pending','legacy_conflict'):
            with self.subTest(table=table), self.assertRaises(sqlite3.IntegrityError):
                self.con.execute(f"INSERT INTO {table} VALUES ('resend','evt_a')")

    def test_06_duplicate_across_states(self):
        self.con.execute('UPDATE control SET enabled=1')
        self.assertEqual(reserve(self.con,'evt_a'), 'NEW_PENDING')
        self.assertEqual(reserve(self.con,'evt_a'), 'DUPLICATE_PENDING')
        self.con.execute("UPDATE registry SET state='processed' WHERE event_id='evt_a'")
        self.assertEqual(reserve(self.con,'evt_a'), 'DUPLICATE_PROCESSED')
        self.assertEqual(self.con.execute('SELECT COUNT(*) FROM registry').fetchone()[0],1)

    def test_07_conflict_is_monotone(self):
        self.con.execute('UPDATE control SET enabled=1')
        reserve(self.con,'evt_a')
        self.assertEqual(reserve(self.con,'evt_a','different'),'IDENTITY_CONFLICT')
        self.assertEqual(reserve(self.con,'evt_a'), 'DUPLICATE_IDENTITY_CONFLICT')

    def test_08_failed_insert_rolls_back(self):
        self.con.execute('UPDATE control SET enabled=1')
        self.con.execute('BEGIN IMMEDIATE')
        with self.assertRaises(sqlite3.IntegrityError):
            self.con.execute("INSERT INTO legacy_pending VALUES('resend','evt_a')")
        self.con.rollback()
        self.assertEqual(self.con.execute('SELECT COUNT(*) FROM legacy_pending').fetchone()[0],0)

    def test_09_historical_rows_preserved(self):
        self.con.execute('DROP TRIGGER reject_legacy_pending')
        self.con.execute("INSERT INTO legacy_pending VALUES('resend','evt_historical')")
        self.con.execute('CREATE TRIGGER reject_legacy_pending BEFORE INSERT ON legacy_pending BEGIN SELECT RAISE(ABORT,\'c65 veto\'); END')
        self.assertEqual(self.con.execute('SELECT event_id FROM legacy_pending').fetchone()[0],'evt_historical')

    def test_11_legacy_conflicting_recipient_rejected(self):
        self.con.execute('UPDATE control SET enabled=1')
        reserve(self.con,'evt_original')
        for table in ('legacy_processed','legacy_pending','legacy_conflict'):
            with self.subTest(table=table), self.assertRaises(sqlite3.IntegrityError):
                self.con.execute(f"INSERT INTO {table} VALUES ('resend','evt_original')")

    def test_12_out_of_order_provider_notifications_cannot_write_legacy(self):
        for event in ('email.delivered', 'email.bounced', 'email.complained', 'suppression.added'):
            with self.subTest(event=event), self.assertRaises(sqlite3.IntegrityError):
                self.con.execute('INSERT INTO legacy_processed VALUES (?,?)',('resend',event))

    def test_13_replay_after_legacy_historical_event_fails(self):
        self.con.execute('DROP TRIGGER reject_legacy_processed')
        self.con.execute("INSERT INTO legacy_processed VALUES('resend','evt_prior')")
        self.con.execute('CREATE TRIGGER reject_legacy_processed BEFORE INSERT ON legacy_processed BEGIN SELECT RAISE(ABORT,\'c65 veto\'); END')
        with self.assertRaises(sqlite3.IntegrityError):
            self.con.execute("INSERT INTO legacy_processed VALUES('resend','evt_prior')")
        self.assertEqual(self.con.execute('SELECT count(*) FROM legacy_processed').fetchone()[0],1)

    def test_14_pending_to_processed_promotion_veto(self):
        self.con.execute('DROP TRIGGER reject_legacy_pending')
        self.con.execute("INSERT INTO legacy_pending VALUES('resend','evt_old_pending')")
        self.con.execute('CREATE TRIGGER reject_legacy_pending BEFORE INSERT ON legacy_pending BEGIN SELECT RAISE(ABORT,\'c65 veto\'); END')
        self.con.execute('CREATE TRIGGER reject_legacy_pending_delete BEFORE DELETE ON legacy_pending BEGIN SELECT RAISE(ABORT,\'c65 veto\'); END')
        with self.assertRaises(sqlite3.IntegrityError):
            self.con.execute("DELETE FROM legacy_pending WHERE event_id='evt_old_pending'")

    def test_15_bounce_or_complaint_cannot_be_marked_processed_in_old_tables(self):
        for event in ('evt_permanent_bounce','evt_complaint','evt_suppressed'):
            with self.subTest(event=event), self.assertRaises(sqlite3.IntegrityError):
                self.con.execute('INSERT INTO legacy_processed VALUES (?,?)',('resend',event))

    def test_10_concurrent_reservations_one_winner(self):
        self.con.execute('UPDATE control SET enabled=1')
        barrier=threading.Barrier(8)
        outcomes=[]
        errors=[]
        def worker():
            connection=sqlite3.connect(self.db,timeout=15,isolation_level=None)
            try:
                barrier.wait(timeout=12)
                outcomes.append(reserve(connection,'evt_shared'))
            except Exception as exc:
                errors.append(str(exc))
            finally:
                connection.close()
        ts=[threading.Thread(target=worker) for _ in range(8)]
        for t in ts:t.start()
        for t in ts:t.join(timeout=18)
        self.assertFalse(errors,errors)
        self.assertEqual(outcomes.count('NEW_PENDING'),1)
        self.assertEqual(outcomes.count('DUPLICATE_PENDING'),7)


class C65SQLSafetyTests(unittest.TestCase):
    def test_begin_commit(self): self.assertTrue(SQL.startswith('-- DeedLight'));self.assertIn('BEGIN;',SQL);self.assertRegex(SQL,r'COMMIT;\s*$')
    def test_fails_if_registry_absent(self): self.assertIn("to_regclass('deedlight_event_private.provider_event_registry')",SQL)
    def test_requires_registry_disabled(self): self.assertIn('IS DISTINCT FROM false',SQL)
    def test_identifies_exact_high_severity_rpc(self): self.assertIn("p.proname = 'record_resend_webhook_event_identity_bound'",SQL)
    def test_drops_all_legacy_overloads(self): self.assertIn('DROP FUNCTION %s RESTRICT',SQL)
    def test_refuses_missing_rpc(self): self.assertIn('Expected legacy acceptance RPC absent',SQL)
    def test_no_cascade_drop(self): self.assertNotIn('DROP FUNCTION %s CASCADE',SQL)
    def test_trigger_rejects_dml(self): self.assertIn('BEFORE INSERT OR UPDATE OR DELETE',SQL)
    def test_trigger_always(self): self.assertIn('ENABLE ALWAYS TRIGGER',SQL)
    def test_trigger_not_removable_by_service_rpc(self): self.assertIn('SECURITY INVOKER',SQL)
    def test_revoke_legacy_table_dml(self): self.assertIn('FROM PUBLIC, anon, authenticated, service_role',SQL)
    def test_does_not_touch_suppression(self): self.assertNotIn('UPDATE delivery_private.recipient_suppression',SQL)
    def test_does_not_activate_registry(self): self.assertNotIn('accepting_new_events = true',SQL)
    def test_restrict_search_path(self): self.assertIn('SET search_path = pg_catalog, pg_temp',SQL)
    def test_no_generic_history_deletion(self): self.assertNotIn('TRUNCATE',SQL.upper());self.assertNotIn('DELETE FROM',SQL.upper())
    def test_no_secret_or_recipient_diagnostics(self): self.assertNotIn('RAISE NOTICE',SQL)
    def test_guard_inventory_private(self): self.assertIn('deedlight_event_private.c65_legacy_veto_inventory',SQL)
    def test_requires_catalog_discovered_table(self): self.assertIn('No legacy event tables discovered',SQL)
    def test_fails_on_additional_named_entry_point(self): self.assertIn('Additional legacy acceptance entry point requires source review',SQL)


if __name__=='__main__':unittest.main()
