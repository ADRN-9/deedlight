"""Adversarial tests of an executed SQLite surrogate, not PostgreSQL functions."""
from __future__ import annotations

import hashlib
import sqlite3
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from registry_sqlite_reference import Event, Registry, Closed


def evt(event_id="evt_001", payload=b"synthetic-event", event_type="email.bounced", msg="mail_1"):
    return Event("resend", event_id, hashlib.sha256(payload).digest(), event_type, msg)


class EventIdentityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = Registry.initialize(Path(self.tmp.name) / "events.sqlite")

    def activate(self):
        self.store.enable_for_synthetic_test()

    def row(self, event_id="evt_001"):
        with self.store.db() as db:
            return db.execute("SELECT state,bound_delivery_id FROM registry WHERE event_id=?", (event_id,)).fetchone()

    def count(self, table):
        assert table in {"registry","conflicts","suppressions"}
        with self.store.db() as db:
            return db.execute(f"SELECT count(*) FROM {table}").fetchone()[0]

    def test_01_disabled_until_history_review(self):
        with self.assertRaises(Closed): self.store.reserve(evt())
        self.assertEqual(0, self.count("registry"))

    def test_02_synthetic_activation_must_leave_provenance(self):
        self.activate()
        self.assertEqual("NEW_PENDING", self.store.reserve(evt()))

    def test_03_duplicate_pending_is_not_second_row(self):
        self.activate()
        self.assertEqual("NEW_PENDING", self.store.reserve(evt()))
        self.assertEqual("DUPLICATE_PENDING", self.store.reserve(evt()))
        self.assertEqual(1, self.count("registry"))

    def test_04_duplicate_processed_is_not_second_row(self):
        self.activate()
        self.store.reserve(evt())
        with self.store.db() as db:
            db.execute("UPDATE registry SET state='processed' WHERE event_id='evt_001'")
        self.assertEqual("DUPLICATE_PROCESSED", self.store.reserve(evt()))
        self.assertEqual(1, self.count("registry"))

    def test_05_conflicting_payload_quarantines_original_identity(self):
        self.activate()
        self.store.reserve(evt())
        self.assertEqual("IDENTITY_CONFLICT",self.store.reserve(evt(payload=b"different")))
        self.assertEqual(("identity_conflict",None),self.row())
        self.assertEqual(1,self.count("registry"))
        self.assertEqual(1,self.count("conflicts"))

    def test_06_conflicting_provider_message_quarantines(self):
        self.activate();self.store.reserve(evt())
        self.assertEqual("IDENTITY_CONFLICT",self.store.reserve(evt(msg="mail_other")))
        self.assertEqual("identity_conflict",self.row()[0])

    def test_07_conflicting_event_type_quarantines(self):
        self.activate();self.store.reserve(evt())
        self.assertEqual("IDENTITY_CONFLICT",self.store.reserve(evt(event_type="email.complained")))

    def test_08_conflicting_replay_after_processed_quarantines(self):
        self.activate();self.store.reserve(evt())
        with self.store.db() as db: db.execute("UPDATE registry SET state='processed'")
        self.assertEqual("IDENTITY_CONFLICT",self.store.reserve(evt(payload=b"evil")))
        self.assertEqual("identity_conflict",self.row()[0])

    def test_09_quarantined_event_cannot_return_to_pending(self):
        self.activate();self.store.reserve(evt());self.store.reserve(evt(payload=b"evil"))
        self.assertEqual("QUARANTINED",self.store.reserve(evt()))
        self.assertEqual("identity_conflict",self.row()[0])

    def test_10_quarantine_is_durable_across_connections(self):
        self.activate();self.store.reserve(evt());self.store.reserve(evt(payload=b"evil"))
        other = Registry(self.store.path)
        self.assertEqual("QUARANTINED",other.reserve(evt()))

    def test_11_conflicting_replay_is_idempotently_recorded(self):
        self.activate();self.store.reserve(evt())
        for _ in range(3): self.store.reserve(evt(payload=b"evil"))
        self.assertEqual(1,self.count("conflicts"))

    def test_12_bounce_replay_never_creates_second_row(self):
        self.activate()
        e=evt(event_type="email.bounced")
        self.assertEqual("NEW_PENDING",self.store.reserve(e))
        for _ in range(8): self.assertEqual("DUPLICATE_PENDING",self.store.reserve(e))
        self.assertEqual(1,self.count("registry"))

    def test_13_complaint_replay_never_creates_second_row(self):
        self.activate();e=evt(event_type="email.complained")
        self.store.reserve(e)
        self.assertEqual("DUPLICATE_PENDING",self.store.reserve(e))
        self.assertEqual(1,self.count("registry"))

    def test_14_different_event_ids_remain_separate(self):
        self.activate();self.store.reserve(evt("evt_a"));self.store.reserve(evt("evt_b"))
        self.assertEqual(2,self.count("registry"))

    def test_15_different_provider_requires_separate_authorization(self):
        self.activate()
        with self.assertRaises(Closed): self.store.reserve(Event("unreviewed", "evt_001",b"a"*32,"email.bounced","mail_1"))

    def test_16_null_event_id_rejected(self):
        self.activate()
        with self.assertRaises(Closed): self.store.reserve(evt(event_id=None))

    def test_17_blank_event_id_rejected(self):
        self.activate()
        with self.assertRaises(Closed): self.store.reserve(evt(event_id=""))

    def test_18_malformed_event_id_rejected(self):
        self.activate()
        for id_ in [" space", "a\nb", "évt", "a"*256, "<script>"]:
            with self.subTest(id=id_), self.assertRaises(Closed): self.store.reserve(evt(event_id=id_))
        self.assertEqual(0,self.count("registry"))

    def test_19_bad_digest_rejected(self):
        self.activate()
        with self.assertRaises(Closed): self.store.reserve(Event("resend", "evt_001", b"x", "email.bounced", "mail_1"))

    def test_20_invalid_event_type_rejected(self):
        self.activate()
        with self.assertRaises(Closed): self.store.reserve(evt(event_type="bad\nevent"))

    def test_21_control_character_provider_message_rejected(self):
        self.activate()
        with self.assertRaises(Closed): self.store.reserve(evt(msg="secret\r\nleak"))

    def test_22_pending_without_provider_id_stays_unmatched(self):
        self.activate();self.store.reserve(evt(msg=None))
        self.assertEqual("PENDING_UNMATCHED",self.store.bind("resend","evt_001"))

    def test_23_pending_until_matching_ledger_dispatch_exists(self):
        self.activate();self.store.reserve(evt())
        self.assertEqual("PENDING_UNMATCHED",self.store.bind("resend","evt_001"))
        with self.store.db() as db: db.execute("INSERT INTO ledger VALUES ('job_1','mail_1')")
        self.assertEqual("BOUND_PENDING",self.store.bind("resend","evt_001"))
        self.assertEqual(("pending","job_1"),self.row())

    def test_24_rebinding_same_authoritative_dispatch_is_safe(self):
        self.activate();self.store.reserve(evt())
        with self.store.db() as db: db.execute("INSERT INTO ledger VALUES ('job_1','mail_1')")
        self.assertEqual("BOUND_PENDING",self.store.bind("resend","evt_001"))
        self.assertEqual("BOUND_PENDING",self.store.bind("resend","evt_001"))

    def test_25_duplicate_provider_message_mapping_rejected_by_unique_index(self):
        self.activate();self.store.reserve(evt())
        with self.store.db() as db:
            db.execute("INSERT INTO ledger VALUES ('job_1','mail_1')")
            with self.assertRaises(sqlite3.IntegrityError):
                db.execute("INSERT INTO ledger VALUES ('job_2','mail_1')")
        self.assertEqual("BOUND_PENDING",self.store.bind("resend","evt_001"))

    def test_26_provider_mapping_changed_after_binding_quarantined(self):
        self.activate();self.store.reserve(evt())
        with self.store.db() as db: db.execute("INSERT INTO ledger VALUES ('job_1','mail_1')")
        self.store.bind("resend","evt_001")
        with self.store.db() as db:
            db.execute("DELETE FROM ledger WHERE id='job_1'")
            db.execute("INSERT INTO ledger VALUES ('job_2','mail_1')")
        self.assertEqual("IDENTITY_CONFLICT",self.store.bind("resend","evt_001"))

    def test_27_early_event_later_dispatch_binding(self):
        self.activate();self.store.reserve(evt("evt_early", b"early"))
        self.assertEqual("PENDING_UNMATCHED",self.store.bind("resend","evt_early"))
        with self.store.db() as db: db.execute("INSERT INTO ledger VALUES ('job_1','mail_1')")
        self.assertEqual("BOUND_PENDING",self.store.bind("resend","evt_early"))

    def test_28_delayed_success_cannot_remove_suppression(self):
        self.activate()
        with self.store.db() as db:
            db.execute("INSERT INTO suppressions VALUES ('recipient_1','complaint')")
        self.store.reserve(evt("evt_delayed_success",event_type="email.delivered"))
        self.assertEqual(1,self.count("suppressions"))

    def test_29_replayed_complaint_cannot_remove_suppression(self):
        self.activate()
        with self.store.db() as db:
            db.execute("INSERT INTO suppressions VALUES ('recipient_1','complaint')")
        e=evt("evt_complaint",event_type="email.complained")
        self.store.reserve(e);self.store.reserve(e)
        self.assertEqual(1,self.count("suppressions"))

    def test_30_interrupted_transaction_rolls_back(self):
        self.activate()
        with self.assertRaises(sqlite3.OperationalError): self.store.reserve(evt(),inject_error=True)
        self.assertEqual(0,self.count("registry"))
        self.assertEqual("NEW_PENDING",self.store.reserve(evt()))

    def test_31_failure_in_duplicate_transaction_preserves_existing_row(self):
        self.activate();self.store.reserve(evt())
        with self.assertRaises(sqlite3.OperationalError): self.store.reserve(evt(),inject_error=True)
        self.assertEqual(("pending",None),self.row())

    def test_32_historical_cross_table_duplicate_blocks_activation(self):
        with self.store.db() as db:
            db.execute("INSERT INTO historical_sources VALUES ('processed','resend','evt_001',?)",(b"a"*32,))
            db.execute("INSERT INTO historical_sources VALUES ('pending','resend','evt_001',?)",(b"a"*32,))
        with self.assertRaises(Closed): self.activate()
        with self.assertRaises(Closed): self.store.reserve(evt())

    def test_33_identical_historical_duplicate_also_requires_reconciliation(self):
        with self.store.db() as db:
            db.execute("INSERT INTO historical_sources VALUES ('processed','resend','evt_001',?)",(b"b"*32,))
            db.execute("INSERT INTO historical_sources VALUES ('quarantine','resend','evt_001',?)",(b"b"*32,))
        with self.assertRaises(Closed): self.activate()

    def test_34_even_one_historical_row_blocks_activation_until_imported(self):
        with self.store.db() as db:
            db.execute("INSERT INTO historical_sources VALUES ('pending','resend','evt_001',?)",(b"b"*32,))
        with self.assertRaises(Closed): self.activate()
        self.assertEqual(0,self.count("registry"))
        # Real 025-028 source mappings are unavailable; do not auto-import.

    def test_35_many_simultaneous_identical_events_have_single_winner(self):
        self.activate();n=16;barrier=threading.Barrier(n)
        def worker(_):
            barrier.wait(timeout=15)
            return self.store.reserve(evt())
        with ThreadPoolExecutor(max_workers=n) as pool: out=list(pool.map(worker,range(n)))
        self.assertEqual(1,out.count("NEW_PENDING"))
        self.assertEqual(n-1,out.count("DUPLICATE_PENDING"))
        self.assertEqual(1,self.count("registry"))

    def test_36_conflicting_concurrent_writes_quarantine(self):
        self.activate();n=12;barrier=threading.Barrier(n)
        def worker(i):
            barrier.wait(timeout=15)
            return self.store.reserve(evt(payload=(b"a" if i%2 else b"b")))
        with ThreadPoolExecutor(max_workers=n) as pool: out=list(pool.map(worker,range(n)))
        self.assertEqual(1,out.count("NEW_PENDING"))
        self.assertIn("IDENTITY_CONFLICT",out)
        self.assertEqual(("identity_conflict",None),self.row())
        self.assertEqual(1,self.count("registry"))

    def test_37_no_automatic_processing_of_bounce(self):
        self.activate();self.store.reserve(evt())
        with self.store.db() as db: db.execute("INSERT INTO ledger VALUES ('job_1','mail_1')")
        self.assertEqual("BOUND_PENDING",self.store.bind("resend","evt_001"))
        self.assertEqual("pending",self.row()[0])

    def test_38_complaint_mapping_must_be_database_derived(self):
        self.activate();self.store.reserve(evt(event_type="email.complained"))
        with self.store.db() as db: db.execute("INSERT INTO ledger VALUES ('job_1','mail_1')")
        self.assertEqual("BOUND_PENDING",self.store.bind("resend","evt_001"))
        self.assertEqual("job_1",self.row()[1])

    def test_39_unknown_event_cannot_be_bound(self):
        self.activate()
        with self.assertRaises(Closed):self.store.bind("resend","evt_unknown")

    def test_40_same_event_identity_all_states_share_single_pk(self):
        self.activate();self.store.reserve(evt())
        with self.store.db() as db:
            with self.assertRaises(sqlite3.IntegrityError):
                db.execute("INSERT INTO registry(provider,event_id,digest,event_type,state) VALUES ('resend','evt_001',?,'email.bounced','processed')",(b"a"*32,))
        self.assertEqual(1,self.count("registry"))

    def test_41_bound_delivered_event_promotes_to_processed(self):
        self.activate();self.store.reserve(evt(event_type="email.delivered"))
        with self.store.db() as db: db.execute("INSERT INTO ledger VALUES ('job_1','mail_1')")
        self.assertEqual("BOUND_PENDING",self.store.bind("resend","evt_001"))
        self.assertEqual("PROCESSED",self.store.process_nonsuppressing("resend","evt_001"))
        self.assertEqual("DUPLICATE_PROCESSED",self.store.reserve(evt(event_type="email.delivered")))

    def test_42_suppressive_event_cannot_promote_without_suppression(self):
        self.activate();self.store.reserve(evt(event_type="email.bounced"))
        with self.store.db() as db: db.execute("INSERT INTO ledger VALUES ('job_1','mail_1')")
        self.store.bind("resend","evt_001")
        with self.assertRaises(Closed): self.store.process_nonsuppressing("resend","evt_001")
        self.assertEqual("pending",self.row()[0])

    def test_43_unbound_delivered_event_stays_pending(self):
        self.activate();self.store.reserve(evt(event_type="email.delivered"))
        self.assertEqual("PENDING_UNMATCHED",self.store.process_nonsuppressing("resend","evt_001"))
        self.assertEqual("pending",self.row()[0])

    def test_44_conflicted_event_cannot_be_promoted(self):
        self.activate();self.store.reserve(evt(event_type="email.delivered"))
        self.store.reserve(evt(event_type="email.delivered",payload=b"conflict"))
        self.assertEqual("QUARANTINED",self.store.process_nonsuppressing("resend","evt_001"))
        self.assertEqual("identity_conflict",self.row()[0])

    def test_45_delayed_delivered_promotion_does_not_unsuppress(self):
        self.activate();self.store.reserve(evt(event_type="email.delivered"))
        with self.store.db() as db:
            db.execute("INSERT INTO suppressions VALUES ('recipient_1','permanent_bounce')")
            db.execute("INSERT INTO ledger VALUES ('job_1','mail_1')")
        self.store.bind("resend","evt_001")
        self.assertEqual("PROCESSED",self.store.process_nonsuppressing("resend","evt_001"))
        self.assertEqual(1,self.count("suppressions"))

    def test_46_changed_ledger_correlation_before_processing_quarantines(self):
        self.activate();self.store.reserve(evt(event_type="email.delivered"))
        with self.store.db() as db: db.execute("INSERT INTO ledger VALUES ('job_1','mail_1')")
        self.store.bind("resend","evt_001")
        with self.store.db() as db: db.execute("UPDATE ledger SET provider_result_id='mail_changed' WHERE id='job_1'")
        self.assertEqual("IDENTITY_CONFLICT",self.store.process_nonsuppressing("resend","evt_001"))
        self.assertEqual("identity_conflict",self.row()[0])


if __name__ == "__main__":
    unittest.main()
