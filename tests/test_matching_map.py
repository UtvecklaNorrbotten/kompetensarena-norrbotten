import base64
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('matching_map_import', ROOT / 'scripts/fetch_rmi_matching_map.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class MatchingMapTests(unittest.TestCase):
    def test_missing_shares_are_not_zero(self):
        for value in (None, '', '..', '...', '…'):
            self.assertIsNone(module.share(value))
        self.assertEqual(module.share('0'), 0)
        for value in ('nan', '-0.1', '1.1'):
            with self.assertRaises(ValueError):
                module.share(value)

    def test_published_matrix(self):
        catalog = json.loads((ROOT / 'src/data/matching-map/catalog.json').read_text())
        wrapper = json.loads((ROOT / 'public/data/matching-map' / catalog['file']).read_text())
        payload = gzip.decompress(base64.b64decode(wrapper['gzip']))
        self.assertEqual(hashlib.sha256(payload).hexdigest(), catalog['matrixHash'])
        rows = json.loads(payload)
        self.assertEqual(len(rows), catalog['rowCount'])
        self.assertEqual(len(rows), len(catalog['educations']) * len(catalog['occupations']))
        self.assertEqual(len({(r[0], r[1]) for r in rows}), len(rows))
        assessments = set()
        sums = {e: [] for e in catalog['educations']}
        for e, o, by_education, by_occupation, subject, level in rows:
            self.assertIn(e, catalog['educations'])
            self.assertIn(o, catalog['occupations'])
            self.assertIn(subject, range(3))
            self.assertIn(level, range(3))
            assessments.add((subject, level))
            sums[e].append(by_education)
            for share in (by_education, by_occupation):
                self.assertTrue(share is None or 0 <= share <= 1)
        self.assertEqual(len(assessments), 9)
        for values in sums.values():
            if all(v is not None for v in values):
                self.assertAlmostEqual(sum(values), 1, places=8)


if __name__ == '__main__':
    unittest.main()
