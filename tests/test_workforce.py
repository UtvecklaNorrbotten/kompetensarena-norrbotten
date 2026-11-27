import base64
import gzip
import hashlib
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from fetch_workforce import SPECS

class WorkforceSnapshot(unittest.TestCase):
    def test_published_snapshot(self):
        catalog = json.loads((ROOT / 'src/data/workforce/catalog.json').read_bytes())
        self.assertEqual(set(catalog['datasets']), set(SPECS))
        self.assertEqual(len(catalog['geographies']), 312)
        for key, info in catalog['datasets'].items():
            total = 0
            for geo in info['selection'].get('Region', ['00']):
                filename = key + '/geo-' + geo + '.json'
                asset = catalog['files'][filename]
                raw = (ROOT / 'public/data/workforce' / asset['path']).read_bytes()
                self.assertEqual(hashlib.sha256(raw).hexdigest(), asset['sha256'])
                rows = json.loads(gzip.decompress(base64.b64decode(json.loads(raw)['gzip'])))
                self.assertEqual(len(rows), len({tuple(r[:5]) for r in rows}))
                total += len(rows)
                for r in rows:
                    self.assertIn(r[0], info['periods'])
                    self.assertIn(r[1], info['sexes'])
                    self.assertIn(r[2], info['categories'])
                    self.assertIn(r[4], info['measures'])
                    self.assertTrue(r[5] is None or r[5] >= 0)
            self.assertEqual(total, info['cells'])
        # Every asset, including comparisons, is content-addressed and verified.
        for asset in catalog['files'].values():
            raw = (ROOT / 'public/data/workforce' / asset['path']).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), asset['sha256'])

if __name__ == '__main__':
    unittest.main()
