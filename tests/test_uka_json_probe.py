"""Synthetic examples for the bounded JSON feasibility probe."""
from pathlib import Path
import sys
import json
import tempfile
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))
import uka_json_probe as uka


BASE = uka.BASE + "/33?university=171&year=2025%2F26&gender=Kvinnor&age_group=8"
CHILD = BASE + "&group_slug=example-combination"


def body(value=14.4):
    return {"indicator": {"id": 33}, "yearly_totals": {"totals": [{"year": "2025/26", "value": value}]}}


class JsonProbeTests(unittest.TestCase):
    def test_group_link_must_preserve_university_period_gender_and_age(self):
        uka.validate_follow(BASE, CHILD, 33)
        for old, new in (("171", "32"), ("2025%2F26", "2024%2F25"), ("Kvinnor", "M%C3%A4n"), ("age_group=8", "age_group=1")):
            with self.assertRaisesRegex(ValueError, "changed a context filter"):
                uka.validate_follow(BASE, CHILD.replace(old, new), 33)

    def test_foreign_source_and_ambiguous_parameters_are_rejected(self):
        for url in (CHILD.replace("statistik-api.uka.se", "example.org"),
                    CHILD.replace("/33?", "/31?"), CHILD + "&age_group=9"):
            with self.assertRaises(ValueError):
                uka.validate_url(url, 33)

    def test_checks_values_not_only_year_counts(self):
        self.assertEqual(uka.edge_value(BASE, CHILD, body(), 14.4, 33), "14.4")
        with self.assertRaisesRegex(ValueError, "differs"):
            uka.edge_value(BASE, CHILD, body(14.5), 14.4, 33)

    def test_missing_period_and_duplicate_periods_are_rejected(self):
        b = body()
        b["yearly_totals"]["totals"][0]["year"] = "2024/25"
        with self.assertRaisesRegex(ValueError, "differs"):
            uka.edge_value(BASE, CHILD, b, 14.4, 33)
        b["yearly_totals"]["totals"] *= 2
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            uka.yearly(b)

    def test_null_is_preserved_and_not_zero(self):
        self.assertIsNone(uka.edge_value(BASE, CHILD, body(None), None, 33))
        with self.assertRaises(ValueError):
            uka.edge_value(BASE, CHILD, body(0), None, 33)

    def test_missing_value_field_is_not_source_null(self):
        b = body(); del b['yearly_totals']['totals'][0]['value']
        with self.assertRaisesRegex(ValueError, 'Missing source value'):
            uka.yearly(b)

    def test_cached_context_must_match_selected_snapshot_and_url(self):
        for field, value in (('snapshot', 'wrong-snapshot'), ('url', CHILD)):
            with tempfile.TemporaryDirectory() as tmp:
                probe = uka.Probe(tmp, 'example', budget=1)
                response = Mock(); response.json.return_value = body()
                probe.session.get = Mock(return_value=response)
                probe.get(BASE, 33)
                path = next((Path(tmp) / 'responses').glob('*.json'))
                cached = json.loads(path.read_text()); cached[field] = value
                path.write_text(json.dumps(cached))
                with self.assertRaisesRegex(ValueError, 'context mismatch'):
                    probe.get(BASE, 33)
                self.assertEqual(probe.session.get.call_count, 1)

    def test_cache_integrity_and_request_budget(self):
        with tempfile.TemporaryDirectory() as tmp:
            probe = uka.Probe(tmp, "example-campaign", budget=1)
            response = Mock()
            response.json.return_value = body()
            probe.session.get = Mock(return_value=response)
            self.assertEqual(probe.get(BASE, 33), probe.get(BASE, 33))
            self.assertEqual(probe.session.get.call_count, 1)
            with self.assertRaisesRegex(RuntimeError, "budget"):
                probe.get(CHILD, 33)
            # A modified cached body may not survive its checksum.
            path = next((Path(tmp) / "responses").glob("*.json"))
            path.write_text(path.read_text().replace('14.4', '99.9'))
            with self.assertRaisesRegex(RuntimeError, "budget"):
                probe.get(BASE, 33)


if __name__ == "__main__":
    unittest.main()
