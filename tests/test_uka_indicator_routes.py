"""Synthetic direct-reference and filter-integrity checks."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
from uka_indicator_routes import university_reference

URL = 'https://statistik-api.uka.se/api/totals/99?university=1&year=HT2026&group_slug=example'


class ReferenceTests(unittest.TestCase):
    def body(self, url=None):
        return {'groups': [{'column': 'Lärosäten', 'totals': [
            {'name': 'Exempellärosäte', 'value': 1.7, 'url': url or URL.replace('university=1', 'university=32')}]}]}

    def probe(self, value):
        class ExampleProbe:
            def get(self, url, indicator):
                return {'yearly_totals': {'totals': [{'year': 'HT2026', 'value': value}]}}
        return ExampleProbe()

    def test_decimal_source_observation_matches_direct_reference(self):
        r = university_reference(self.probe(1.7), URL, self.body(), 99)
        self.assertTrue(r['verified']); self.assertEqual(r['value'], '1.7')

    def test_changed_group_context_is_rejected(self):
        url = URL.replace('university=1', 'university=32').replace('group_slug=example', 'group_slug=wrong')
        with self.assertRaisesRegex(ValueError, 'another selection'):
            university_reference(self.probe(1.7), URL, self.body(url), 99)

    def test_mismatching_source_value_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'differs'):
            university_reference(self.probe(2), URL, self.body(), 99)
