"""Deterministic local checks; these do not execute PostgreSQL."""

from __future__ import annotations

import hashlib
import re
import subprocess
import tempfile
import unittest
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL = ROOT / "source/test-gentle-delivery-transport.original.sql"
FIXED = ROOT / "patch/test-gentle-delivery-transport.sql"
PATCH = ROOT / "patch/0001-ci-transport-claim-relative-clock.patch"
ORIGINAL_GIT_BLOB = "d0cce02799b10cde845344278e00bb57c2dffe42"


def utc_week_start(value: datetime) -> date:
    d = value.astimezone(UTC).date()
    return d - timedelta(days=d.isoweekday() - 1)


@dataclass
class Claim:
    token: uuid.UUID
    expires_at: datetime
    kind: str
    authorized_at: datetime | None = None
    consent: bool = True
    suspended: bool = False
    recipient_unchanged: bool = True

    def authorize(self, now: datetime, token: uuid.UUID, kind: str) -> bool:
        return (
            token == self.token
            and now < self.expires_at
            and kind == self.kind
            and self.consent
            and not self.suspended
            and self.recipient_unchanged
        )

    def begin(self, now: datetime, token: uuid.UUID, kind: str) -> bool:
        if not self.authorize(now, token, kind):
            return False
        self.authorized_at = self.authorized_at or now
        return True


def claimed_at(instant: datetime, kind: str = "weekly_newsletter") -> Claim:
    return Claim(uuid.uuid4(), instant + timedelta(minutes=5), kind)


class FixtureSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.original = ORIGINAL.read_text()
        cls.fixed = FIXED.read_text()

    def test_original_matches_github_blob_identity(self) -> None:
        data = ORIGINAL.read_bytes()
        blob = b"blob " + str(len(data)).encode() + b"\0" + data
        self.assertEqual(hashlib.sha1(blob).hexdigest(), ORIGINAL_GIT_BLOB)

    def test_patch_applies_to_original_byte_for_byte(self) -> None:
        with tempfile.TemporaryDirectory(prefix="deedlight-c70-patch-") as td:
            scripts = Path(td) / "scripts"
            scripts.mkdir()
            target = scripts / "test-gentle-delivery-transport.sql"
            target.write_bytes(ORIGINAL.read_bytes())
            subprocess.run(["git", "apply", "--check", str(PATCH)], cwd=td, check=True)
            subprocess.run(["git", "apply", str(PATCH)], cwd=td, check=True)
            self.assertEqual(target.read_bytes(), FIXED.read_bytes())

    def test_only_one_existing_script_is_patched(self) -> None:
        text = PATCH.read_text()
        self.assertEqual(text.count("--- a/"), 1)
        self.assertEqual(text.count("+++ b/"), 1)
        self.assertIn("scripts/test-gentle-delivery-transport.sql", text)

    def test_fixture_uses_live_transaction_clock(self) -> None:
        self.assertIn("v_now timestamptz := now()", self.fixed)
        self.assertIn("public.claim_delivery_jobs(v_now, 100)", self.fixed)
        self.assertIn("enqueue_current_weekly_goodness_if_curated(v_now, 5000)", self.fixed)
        self.assertNotRegex(self.fixed, r"'2026-10-26")
        self.assertIn("set local role service_role;", self.fixed.lower())
        self.assertRegex(self.fixed, r"(?s)\bbegin;\s+insert into public.weekly_goodness_features.*?\bcommit;")

    def test_iso_week_derived_explicitly_in_utc(self) -> None:
        self.assertGreaterEqual(self.fixed.count("timezone('UTC', now())"), 2)
        self.assertGreaterEqual(self.fixed.count("extract(isodow"), 2)
        self.assertIn("v_delivery_key text := 'weekly:' || v_week_start::text", self.fixed)
        self.assertIn("where delivery_key = v_delivery_key", self.fixed)

    def test_reuse_and_claimed_state_are_verified(self) -> None:
        self.assertIn("v_inserted_again <> 0", self.fixed)
        self.assertIn("v_inserted <> 1", self.fixed)
        self.assertIn("claim_token = v_token and claim_expires_at > now()", self.fixed)
        self.assertIn("v_started_2 is distinct from v_started_1", self.fixed)

    def test_stale_token_rejected_on_both_paths(self) -> None:
        self.assertIn("public.authorize_delivery_job(v_id, v_wrong_token)", self.fixed)
        self.assertIn("public.begin_delivery_transport(v_id, v_wrong_token)", self.fixed)
        self.assertIn("Stale token unexpectedly authorized", self.fixed)
        self.assertIn("Stale token unexpectedly began transport", self.fixed)

    def test_expired_claim_rejected_on_both_paths(self) -> None:
        self.assertIn("claim_expires_at = now() - interval '1 second'", self.fixed)
        self.assertIn("public.authorize_delivery_job(v_id, v_token)", self.fixed)
        self.assertIn("public.begin_delivery_transport(v_id, v_token)", self.fixed)
        self.assertIn("Expired claim unexpectedly authorized", self.fixed)
        self.assertIn("Expired claim unexpectedly began transport", self.fixed)

    def test_expected_denials_catch_only_permission_error(self) -> None:
        self.assertEqual(self.fixed.count("exception when sqlstate '42501'"), 4)
        self.assertEqual(self.fixed.count("null;\n  end;"), 4)
        self.assertNotIn("exception when others", self.fixed.lower())

    def test_previous_security_and_terminal_fixtures_retained(self) -> None:
        for needle in (
            "\\ir test-delivery-reliability-terminals.sql",
            "\\ir ../supabase/migrations/202609230021_gentle_delivery_transport.sql",
            "has_function_privilege('anon'",
            "has_function_privilege('authenticated'",
            "has_function_privilege('service_role'",
            "'gentle_delivery_transport_db', 'pass'",
        ):
            self.assertIn(needle, self.fixed)


class TimeReferenceTests(unittest.TestCase):
    def test_week_start_monday(self) -> None:
        self.assertEqual(utc_week_start(datetime(2026, 11, 14, tzinfo=UTC)), date(2026, 11, 9))

    def test_utc_semantics_across_local_midnight(self) -> None:
        from datetime import timezone

        moment = datetime(2026, 11, 8, 18, 0, tzinfo=timezone(timedelta(hours=-8)))
        self.assertEqual(utc_week_start(moment), date(2026, 11, 9))

    def test_year_boundary_iso_week(self) -> None:
        self.assertEqual(utc_week_start(datetime(2027, 1, 1, tzinfo=UTC)), date(2026, 12, 28))

    def test_positive_live_claim(self) -> None:
        now = datetime(2034, 6, 12, 8, tzinfo=UTC)
        claim = claimed_at(now)
        self.assertTrue(claim.authorize(now, claim.token, "weekly_newsletter"))

    def test_positive_before_expiry(self) -> None:
        now = datetime(2034, 6, 12, 8, tzinfo=UTC)
        claim = claimed_at(now)
        self.assertTrue(claim.begin(now + timedelta(minutes=4, seconds=59), claim.token, claim.kind))

    def test_expires_at_exact_boundary(self) -> None:
        now = datetime(2034, 6, 12, 8, tzinfo=UTC)
        claim = claimed_at(now)
        self.assertFalse(claim.authorize(now + timedelta(minutes=5), claim.token, claim.kind))

    def test_expired_claim_one_second_later(self) -> None:
        now = datetime(2034, 6, 12, 8, tzinfo=UTC)
        claim = claimed_at(now)
        self.assertFalse(claim.begin(now + timedelta(minutes=5, seconds=1), claim.token, claim.kind))

    def test_stale_token_denied_before_expiry(self) -> None:
        now = datetime(2034, 6, 12, 8, tzinfo=UTC)
        claim = claimed_at(now)
        self.assertFalse(claim.authorize(now, uuid.uuid4(), claim.kind))

    def test_stale_token_cannot_start_transport(self) -> None:
        now = datetime(2034, 6, 12, 8, tzinfo=UTC)
        claim = claimed_at(now)
        self.assertFalse(claim.begin(now, uuid.uuid4(), claim.kind))
        self.assertIsNone(claim.authorized_at)

    def test_bad_token_does_not_invalidate_good_claim(self) -> None:
        now = datetime(2034, 6, 12, 8, tzinfo=UTC)
        claim = claimed_at(now)
        self.assertFalse(claim.authorize(now, uuid.uuid4(), claim.kind))
        self.assertTrue(claim.authorize(now, claim.token, claim.kind))

    def test_idempotent_transport_start(self) -> None:
        now = datetime(2034, 6, 12, 8, tzinfo=UTC)
        claim = claimed_at(now)
        self.assertTrue(claim.begin(now, claim.token, claim.kind))
        self.assertTrue(claim.begin(now + timedelta(seconds=2), claim.token, claim.kind))
        self.assertEqual(claim.authorized_at, now)

    def test_revoked_consent_denied(self) -> None:
        now = datetime(2034, 6, 12, 8, tzinfo=UTC)
        claim = claimed_at(now)
        claim.consent = False
        self.assertFalse(claim.authorize(now, claim.token, claim.kind))

    def test_suspended_account_denied(self) -> None:
        now = datetime(2034, 6, 12, 8, tzinfo=UTC)
        claim = claimed_at(now)
        claim.suspended = True
        self.assertFalse(claim.begin(now, claim.token, claim.kind))

    def test_changed_recipient_denied(self) -> None:
        now = datetime(2034, 6, 12, 8, tzinfo=UTC)
        claim = claimed_at(now)
        claim.recipient_unchanged = False
        self.assertFalse(claim.authorize(now, claim.token, claim.kind))

    def test_delivery_kind_isolation(self) -> None:
        now = datetime(2034, 6, 12, 8, tzinfo=UTC)
        claim = claimed_at(now, "weekly_newsletter")
        self.assertFalse(claim.begin(now, claim.token, "daily_reminder"))

    def test_legacy_fixed_october_claim_expired_in_november(self) -> None:
        old = datetime(2026, 10, 26, 16, 1, tzinfo=UTC)
        actual = datetime(2026, 11, 14, 14, tzinfo=UTC)
        claim = claimed_at(old)
        self.assertFalse(claim.authorize(actual, claim.token, claim.kind))

    def test_new_relative_clock_valid_in_any_year(self) -> None:
        for year in (2026, 2027, 2032, 2044):
            now = datetime(year, 11, 14, 14, tzinfo=UTC)
            claim = claimed_at(now)
            with self.subTest(year=year):
                self.assertTrue(claim.authorize(now, claim.token, claim.kind))


if __name__ == "__main__":
    unittest.main()
