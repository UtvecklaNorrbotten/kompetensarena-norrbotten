import base64
import gzip
import hashlib
import itertools
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MatchingSnapshot(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads((ROOT / 'src/data/matching/catalog.json').read_text())

    def load(self, filename):
        snapshot = json.loads((ROOT / 'public/data/matching' / filename).read_text())
        raw = gzip.decompress(base64.b64decode(snapshot['gzip']))
        self.assertTrue(filename.endswith(hashlib.sha256(raw).hexdigest()[:16] + '.json'))
        return json.loads(raw)

    def check_values(self, row, offset):
        self.assertEqual(len(row), offset + 8)
        for i, value in enumerate(row[offset:]):
            self.assertTrue(value is None or isinstance(value, (float, int)))
            if value is not None:
                self.assertGreaterEqual(value, 0)
                if i >= 5:
                    self.assertLessEqual(value, 100)

    def test_summary_coverage_and_missing_values(self):
        c = self.catalog
        self.assertEqual(len(c['regions']), 312)
        self.assertEqual(set(c['regions']), set(c['summary']))
        expected = set(itertools.product(c['education'], ['totalt', '1', '2'], c['periods']))
        missing = 0
        for geo, filename in c['summary'].items():
            rows = self.load(filename)
            self.assertEqual(len(rows), len(expected), geo)
            self.assertEqual({tuple(r[:3]) for r in rows}, expected, geo)
            for r in rows:
                self.check_values(r, 3)
                missing += sum(v is None for v in r[3:])
        self.assertGreater(missing, 0)

    def test_comparison_is_identical_to_geo_slices(self):
        c = self.catalog
        expected = {p: {} for p in c['periods']}
        for geo, filename in c['summary'].items():
            for r in self.load(filename):
                expected[r[2]][(geo, r[0], r[1])] = r[3:]
        for period, filename in c['comparisons'].items():
            rows = self.load(filename)
            actual = {tuple(r[:3]): r[3:] for r in rows}
            self.assertEqual(len(actual), len(rows))
            self.assertEqual(actual, expected[period])

    def test_flow_coverage(self):
        c = self.catalog
        geos = {g for g in c['regions'] if len(g) == 2 or g.startswith('25')}
        self.assertEqual(set(c['flows']), geos)
        expected = set(itertools.product(c['education'], ['totalt', '1', '2'], c['periods'], set(c['branches']) - {'A-U'}))
        for geo, filename in c['flows'].items():
            rows = self.load(filename)
            self.assertEqual(len(rows), len(expected), geo)
            self.assertEqual({tuple(r[:4]) for r in rows}, expected, geo)
            for r in rows:
                self.check_values(r, 4)

    def test_classifications_and_source_notes(self):
        c = self.catalog
        for name, total in [('grupp', '00S'), ('niva', '00N'), ('inriktning', '00I')]:
            self.assertIn(total, c['groups'][name])
            self.assertTrue(set(c['groups'][name]) <= set(c['education']))
        self.assertTrue(c['notes'])
        self.assertTrue(c['measureNotes'])


if __name__ == '__main__':
    unittest.main()
