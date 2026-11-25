import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('af',ROOT/'scripts/fetch_af_unemployment.py')
af=importlib.util.module_from_spec(spec);spec.loader.exec_module(af)
class AfUnemploymentTests(unittest.TestCase):
    def test_missing_and_suppression(self):
        self.assertEqual(af.numeric('0'),0)
        self.assertIsNone(af.numeric(None))
        self.assertEqual(af.numeric('<5'),'<5')
        self.assertEqual(af.complete([10,'<5']),'<5')
        self.assertIsNone(af.complete([10,None]))
        self.assertEqual(af.complete([0,10]),10)
        with self.assertRaises(ValueError): af.numeric('-1')
    def test_renumbered_cache(self):
        # Synthetic example: field-name discovery survives a renamed cache ID.
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'synthetic.xlsx'
            with zipfile.ZipFile(path,'w') as z:
                z.writestr('xl/pivotCache/pivotCacheDefinition7.xml',f'<pivotCacheDefinition xmlns="{af.NS[1:-1]}"><cacheFields><cacheField name="PERIOD"><sharedItems><s v="2026-01"/></sharedItems></cacheField><cacheField name="N"><sharedItems/></cacheField></cacheFields></pivotCacheDefinition>')
                z.writestr('xl/pivotCache/pivotCacheRecords7.xml',f'<pivotCacheRecords xmlns="{af.NS[1:-1]}"><r><x v="0"/><n v="0"/></r><r><x v="0"/><s v="&lt;5"/></r></pivotCacheRecords>')
            self.assertEqual(list(af.cache_rows(path,['PERIOD','N'])),[{'PERIOD':'2026-01','N':'0'},{'PERIOD':'2026-01','N':'<5'}])
    def test_snapshot_coverage_and_reconciliation(self):
        catalog=json.loads((af.OUT/'catalog.json').read_text())
        self.assertEqual(len(catalog['geographies']),312)
        self.assertGreater(catalog['validation']['crossSourceChecks'],40000)
        self.assertGreater(catalog['validation']['publishedNationalRateChecks'],100)
        self.assertLessEqual(catalog['historyStart'],'2016-01')
        for code in catalog['geographies']:
            data=json.loads((af.OUT/f'geo-{code}.json').read_text())
            keys=[tuple(r[:3]) for r in data['pairs']]
            self.assertEqual(len(keys),len(set(keys)))
            for p,g,s,n,d in data['pairs']:
                if g in ('pre','upper','post') and p<'2024-04': self.assertEqual([n,d],[None,None])
            self.assertTrue(any(r[0]==catalog['latest'] and r[1]=='total' and r[2]=='' for r in data['pairs']))
        national=json.loads((af.OUT/'geo-00.json').read_text())
        h={(p,s):n for p,s,n,o,pr in national['history']}
        for p,g,s,n,d in national['pairs']:
            if g=='total':self.assertEqual(n,h[p,s])
if __name__=='__main__':unittest.main()
