"""Synthetic examples for publication normalization and conflicting identities."""
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).parents[1]/'scripts'))
from uka_package_publication_audit import audit,fixed_value,jsonb_text

class PublicationAuditTest(unittest.TestCase):
    def test_numeric_forms_do_not_change_value(self):
        for text,expected in [('1E+1','10'),('2.300','2.3'),('0.0','0'),('0.0100','0.01')]:self.assertEqual(fixed_value(text),expected)
        with self.assertRaises(ValueError):fixed_value('NaN')
    def test_jsonb_keeps_full_parent_path_and_unicode(self):
        d={'inriktning':'Övrigt','examen':'Exempel','examenskategori':'Kategori'}
        self.assertEqual(json.loads(jsonb_text(d)),d)
        self.assertLess(jsonb_text(d).index('examen"'),jsonb_text(d).index('inriktning"'))
    def test_conflicting_values_for_one_identity_block(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'13';root.mkdir()
            (root/'metadata.json').write_text(json.dumps({'universities':[{'value':'uni:1','label':'Riket'}]}))
            db=sqlite3.connect(root/'collection.sqlite');db.execute('CREATE TABLE observations(payload TEXT)')
            row={'period':'HT2026','university':'1','gender':'Total','dimensions':{'Program':'Exempel'},'age':'Total','value':'1'}
            db.executemany('INSERT INTO observations VALUES (?)',[(json.dumps(row),),(json.dumps({**row,'value':'2'}),)]);db.commit();db.close()
            with self.assertRaisesRegex(ValueError,'Duplicate normalized identity'):audit(tmp)

if __name__=='__main__':unittest.main()
