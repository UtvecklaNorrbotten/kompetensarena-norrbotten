import importlib.util
import json
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "etl_af_yrkesbarometer_publish.py"
spec = importlib.util.spec_from_file_location("yrkesbarometer", SCRIPT)
import sys
sys.path.insert(0, str(SCRIPT.parent))
yb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(yb)


class YrkesbarometerTest(unittest.TestCase):
    def test_source_state_detects_deltas(self):
        f = {"yrkesbarometer.json": "abc"}
        self.assertTrue(yb.should_publish({}, f))
        self.assertTrue(yb.should_publish({"last_status": "failed", "details": {"file_sha256": f}}, f))
        self.assertTrue(yb.should_publish({"last_status": "succeeded", "details": {"file_sha256": {}}}, f))
        self.assertFalse(yb.should_publish({"last_status": "succeeded", "details": {"file_sha256": f}}, f))

    def test_prepare_preserves_complete_raw_row(self):
        result = []
        for geo in ("00", "25"):
            result.append({"lan": geo, "omgang": "2026-1", "yb_concept_id": "demo",
                           "jobbmojligheter": "ok", "rekryteringssituation": "brist",
                           "prognos": "okad", "ssyk": ["1234"],
                           "hogsta_bedomningsniva": "riket"})
        grouped, fingerprints = yb.prepare([("yrkesbarometer.json", "current",
                                              json.dumps(result).encode())])
        self.assertEqual(len(grouped["2026-1"]), 2)
        original = json.loads(grouped["2026-1"][0]["dimensions"]["row_json"])
        self.assertEqual(original["ssyk"], ["1234"])
        self.assertEqual(grouped["2026-1"][0]["value"], None)

    def test_duplicate_occupation_rejected(self):
        row = {"lan": "25", "omgang": "2026-1", "yb_concept_id": "demo",
               "jobbmojligheter": "ok", "rekryteringssituation": "ok", "prognos": "ok"}
        with self.assertRaises(ValueError):
            yb.prepare([("x", "2026-1", json.dumps([row, row]).encode())])


if __name__ == "__main__":
    unittest.main()
