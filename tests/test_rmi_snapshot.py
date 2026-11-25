import json
import hashlib
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class RmiSnapshotTests(unittest.TestCase):
    def test_coverage_uniqueness_and_missing_values(self):
        catalog = json.loads((ROOT / 'src/data/rmi/catalog.json').read_text())
        self.assertEqual(len(catalog['regions']), 15)
        self.assertEqual(catalog['table'], 'TAB6928')
        expected = {(group, sex, period) for group in catalog['groups'] for sex in ['totalt','1','2'] for period in catalog['periods']}
        missing = 0
        for geo in catalog['regions']:
            path = ROOT / f'src/data/rmi/{geo}.json'
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), catalog['snapshots'][geo])
            rows = json.loads(path.read_text())
            self.assertEqual(len(rows), len(expected))
            self.assertEqual({tuple(r[:3]) for r in rows}, expected)
            for row in rows:
                self.assertEqual(len(row), 12)
                self.assertTrue(all(v is None or isinstance(v, (int,float)) for v in row[3:]))
                missing += sum(v is None for v in row[3:])
        # Source omissions must stay missing rather than being coerced to zero.
        self.assertGreater(missing, 0)

    def test_map_matches_official_municipality_catalog(self):
        catalog = json.loads((ROOT / 'src/data/rmi/catalog.json').read_text())
        shapes = json.loads((ROOT / 'src/data/norrbotten-map.json').read_text())
        self.assertEqual({s['code'] for s in shapes}, set(catalog['regions']) - {'25'})
        self.assertTrue(all(s['path'].startswith('M') and s['path'].endswith('Z') for s in shapes))

if __name__ == '__main__':
    unittest.main()
