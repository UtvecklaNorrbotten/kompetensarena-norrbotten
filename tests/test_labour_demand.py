"""Synthetic edge cases plus full public snapshot integrity, no network calls."""
import base64
import gzip
import json
from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from audit_jobtech_demand import summarize
from fetch_labour_demand import encode,add

class DemandTests(unittest.TestCase):
    def test_suppression_and_missing(self):
        acc={};add(acc,'a',[0,1]);add(acc,'a',[0,'<5']);self.assertEqual(acc['a'],[0,'<5'])
        add(acc,'a',[None,0]);self.assertEqual(acc['a'],[None,'<5'])
        self.assertEqual(json.loads(gzip.decompress(base64.b64decode(encode(acc)['gzip']))),acc)

    def test_ad_identity_boundary_and_unknown_vacancies(self):
        a={'id':'version1','original_id':'source1','publication_date':'2026-09-01T00:00:00','number_of_vacancies':2}
        b={**a,'id':'version2'};c={**a,'id':'source2','original_id':'source2','number_of_vacancies':None}
        end={**a,'id':'outside','original_id':'outside','publication_date':'2026-10-01T00:00:00'}
        r=summarize([a,b,c,end],'2026-09-01T00:00:00','2026-10-01T00:00:00')
        self.assertEqual(r['boundaryExcluded'],1);self.assertEqual(r['uniqueOriginalIds'],2)
        self.assertEqual(r['repeatedIdentityRows'],1);self.assertEqual(r['sumKnownAdvertisedPositions'],2)
        self.assertEqual(r['unknownAdvertisedPositions'],1)

    def test_snapshot(self):
        folder=ROOT/'src/data/demand';catalog=json.loads((folder/'catalog.json').read_text())
        self.assertEqual(len(catalog['geographies']),312)
        self.assertGreaterEqual(catalog['validation']['publishedNationalCells'],120*4)
        for geo in catalog['geographies']:
            data=json.loads(gzip.decompress(base64.b64decode(json.loads((ROOT/'public/data/demand'/f'geo-{geo}.json').read_text())['gzip'])))
            self.assertTrue(data['totals']);self.assertEqual(max(r[0] for r in data['totals']),catalog['latest'])
            for dataset,rows in data.items():
                measures=1 if dataset=='groups' else 4
                for row in rows:
                    for v in row[-measures:]:self.assertTrue(v is None or v=='<5' or isinstance(v,(int,float)) and v>=0,(geo,dataset,row))
    def test_lor_snapshot(self):
        folder=ROOT/'src/data/demand'
        lor=json.loads((folder/'lor.json').read_text())
        for source in lor.values():
            d=source['data'];self.assertEqual(len(d['value']),__import__('math').prod(d['size']))
            self.assertTrue(source['sha256']);self.assertTrue(d['status'])

if __name__=='__main__':unittest.main()
