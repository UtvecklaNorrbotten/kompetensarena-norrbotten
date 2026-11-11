import importlib.util
from datetime import date, datetime, timezone
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("afr_gate", Path(__file__).resolve().parents[1] / "scripts/afr_recovery_gate.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class AfrRecoveryGateTests(unittest.TestCase):
    def test_dst(self):
        self.assertTrue(gate.is_recovery_slot("15 7 * * *", date(2026, 11, 16)))
        self.assertFalse(gate.is_recovery_slot("15 6 * * *", date(2026, 11, 16)))
        self.assertTrue(gate.is_recovery_slot("15 6 * * *", date(2026, 7, 16)))
        self.assertFalse(gate.is_recovery_slot("15 7 * * *", date(2026, 7, 16)))

    def test_previous_success(self):
        day = date(2026, 11, 16)
        good = [{"id": 2, "conclusion": "success", "created_at": "2026-11-16T04:00:00Z"}]
        skipped = [{"id": 1, "conclusion": "success", "created_at": "2026-11-16T06:15:00Z"}]
        failed = [{"id": 3, "conclusion": "failure", "created_at": "2026-11-16T04:00:00Z"}]
        self.assertTrue(gate.had_successful_run(good, day, 999))
        self.assertFalse(gate.had_successful_run(skipped, day, 999))
        self.assertFalse(gate.had_successful_run(failed, day, 999))
        self.assertFalse(gate.had_successful_run(good, day, 2))

    def test_decision(self):
        now = datetime(2026, 11, 16, 7, 15, tzinfo=timezone.utc)
        self.assertTrue(gate.should_recover("15 7 * * *", now, [], 5))
        self.assertFalse(gate.should_recover("15 6 * * *", now, [], 5))


if __name__ == "__main__":
    unittest.main()
