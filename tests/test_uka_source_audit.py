"""Synthetic examples of source failures, partition comparisons and checkpoints."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location("uka_source_audit", Path(__file__).parents[1] / "scripts/uka_source_audit.py")
uka = importlib.util.module_from_spec(spec)
spec.loader.exec_module(uka)

HEADER = "Tidsperiod;Lärosäte;Studieform;Ämnesområde[0];Ämnesdelområde[1];Ämnesgrupp[2];Kön;Åldersgrupp;Värde\n"


def raw_csv(value="14,40", extra=""):
    return (HEADER + f'"=""2025/26""";Exempeluniversitet;;;;;Kvinnor;-24;{value}\n' + extra).encode("utf-8-sig")


class AuditTests(unittest.TestCase):
    def test_empty_body_is_not_a_valid_empty_selection(self):
        self.assertEqual(uka.parse_csv(b"")["status"], "technical_empty_body")
        self.assertEqual(uka.parse_csv(HEADER.encode())["status"], "empty_selection_unconfirmed")
        self.assertEqual(uka.parse_csv(b"<html>error</html>")["status"], "invalid_csv")

    def test_truncation_and_duplicate_headers_are_rejected(self):
        self.assertEqual(uka.parse_csv((HEADER + "2025/26;Exempeluniversitet\n").encode())["status"], "invalid_csv")
        self.assertEqual(uka.parse_csv(HEADER.replace("Studieform", "Kön").encode())["status"], "invalid_csv")

    def test_values_are_compared_not_counts(self):
        a = uka.parse_csv(raw_csv())["rows"]
        b = uka.parse_csv(raw_csv("14,41"))["rows"]
        result = uka.compare(a, b)
        self.assertFalse(result["exact"])
        self.assertEqual(result["changed"], 1)
        self.assertEqual(a[0]["Tidsperiod"], "2025/26")
        b[0]["Värde"] = "14.400"
        self.assertTrue(uka.compare(a, b)["exact"])

    def test_matching_exports_cannot_hide_ignored_filters(self):
        rows = uka.parse_csv(raw_csv())["rows"]
        uka.validate_selection(rows, "from:2025/26", "Exempeluniversitet", "gender:Kvinnor", ["-24"])
        for period, university, gender, ages in [
            ("from:2024/25", "Exempeluniversitet", "gender:Kvinnor", ["-24"]),
            ("from:2025/26", "Annat exempeluniversitet", "gender:Kvinnor", ["-24"]),
            ("from:2025/26", "Exempeluniversitet", "gender:Män", ["-24"]),
            ("from:2025/26", "Exempeluniversitet", "gender:Kvinnor", ["Total"]),
        ]:
            with self.assertRaisesRegex(ValueError, "unrequested"):
                uka.validate_selection(rows, period, university, gender, ages)

    def test_duplicate_keys_rejected_even_when_values_differ(self):
        a = uka.parse_csv(raw_csv())["rows"]
        with self.assertRaisesRegex(ValueError, "Duplicate observation"):
            uka.compare(a, a + [dict(a[0], **{"Värde": "99"})])

    def test_missing_extra_and_suppressed_values_are_preserved(self):
        a = uka.parse_csv(raw_csv(".."))["rows"]
        b = uka.parse_csv(raw_csv("0"))["rows"]
        self.assertFalse(uka.compare(a, b)["exact"])
        b[0]["Åldersgrupp"] = "Total"
        result = uka.compare(a, b)
        self.assertEqual((result["missing"], result["extra"]), (1, 1))
        self.assertEqual(uka.canonical_value(".."), "..")
        with self.assertRaises(ValueError):
            uka.canonical_value("NaN")

    def test_hierarchy_traverses_parent_ids(self):
        html = '''<div class="groupTitles"><h3><span class="dynamic-filter-index">7.</span>Ämne</h3>
        <input value="dynamic:TOTAL" name="Total"><label>Total</label>
        <input value="dynamic:910_"><label>Område</label>
        <input value="dynamic:921_910"><label>Delområde</label>
        <input value="dynamic:922_921"><label>Grupp</label></div>'''
        group = uka.groups(html)[0]
        self.assertEqual(group["depths"], {"910": 0, "921": 1, "922": 2})
        self.assertEqual(group["parents"]["922"], "921")
        with self.assertRaisesRegex(ValueError, "Unknown hierarchy parent"):
            uka.groups(html.replace("922_921", "922_999"))

    def test_resume_uses_verified_bytes_and_metadata_hash(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = uka.Source(tmp, "example-release")
            posted = Mock(status_code=200)
            posted.json.return_value = {"fileUrl": uka.BASE + "/cache/example.csv"}
            downloaded = Mock(status_code=200, content=raw_csv())
            source.session.post = Mock(return_value=posted)
            source.session.get = Mock(return_value=downloaded)
            filters = ["from:2025/26", "to:2025/26"]
            first = source.export(33, filters, "meta-a")
            second = source.export(33, filters, "meta-a")
            self.assertTrue(second["cached"])
            self.assertEqual(source.session.post.call_count, 1)
            # A corrupt checkpoint may never be silently accepted.
            (Path(tmp) / "selections" / (first["key"] + ".csv")).write_bytes(b"corrupt")
            source.export(33, filters, "meta-a")
            self.assertEqual(source.session.post.call_count, 2)
            source.export(33, filters, "meta-b")
            self.assertEqual(source.session.post.call_count, 3)

    def test_empty_response_is_never_reused_as_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = uka.Source(tmp, "example-release")
            posted = Mock(status_code=200)
            posted.json.return_value = {"fileUrl": uka.BASE + "/cache/example.csv"}
            source.session.post = Mock(return_value=posted)
            source.session.get = Mock(return_value=Mock(status_code=200, content=b""))
            first = source.export(33, [], "meta")
            self.assertEqual(first["status"], "technical_empty_body")
            source.export(33, [], "meta")
            self.assertEqual(source.session.post.call_count, 2)
            evidence = json.loads((Path(tmp) / "selections" / (first["key"] + ".json")).read_text())
            self.assertEqual(evidence["bytes"], 0)

    def test_minimal_source_failure_prevents_larger_exports(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = uka.Source(tmp, "example-release")
            source.metadata = Mock(return_value={
                "metadata_hash": "meta", "groups": [],
                "ages": [{"value": "age:1", "label": "Total"}],
                "genders": [{"value": "gender:Total", "label": "Total"}],
                "universities": [{"value": "uni:1", "label": "Riket"}],
                "retained_periods": [{"value": "from:2025/26"}],
            })
            source.export = Mock(return_value={"key": "failed-control", "status": "technical_empty_body", "rows": []})
            source.json_total = Mock(return_value="123")
            report = uka.run_audit(source, 33)
            self.assertFalse(report["verified"])
            self.assertFalse(report["publish_allowed"])
            self.assertEqual(source.export.call_count, 1)
            self.assertEqual(report["control"]["independent_json_total"], "123")


if __name__ == "__main__":
    unittest.main()
