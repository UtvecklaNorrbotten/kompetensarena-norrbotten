"""Synthetic examples exercise precision and dimension/identity rejection."""
import copy
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
from uka_99_values import observations
from uka_99_full_csv import DeadlineSession
from test_uka_99_full_csv import metadata


class ValuesTests(unittest.TestCase):
    def setUp(self):
        self.row = {'Tidsperiod':'HT2026','Lärosäte':'','Program':'Exempel A',
                    'Kön':'Kvinnor','Åldersgrupp':'Total','Värde':'2,34567890123456789'}

    def test_precision_missing_and_real_zero_are_distinct(self):
        for raw, expected in [('2,34567890123456789','2.34567890123456789'),('0,00','0'),('..','..'),('','')]:
            with self.subTest(raw=raw):
                self.row['Värde']=raw
                self.assertEqual(list(observations([self.row],metadata(),'HT2026',['1']).values()),[expected])

    def test_scope_and_duplicate_rejections(self):
        for field,value in [('Program','Unknown'),('Åldersgrupp','-24'),('Kön','Other'),('Tidsperiod','VT2026'),('Lärosäte','Unknown')]:
            row=copy.deepcopy(self.row);row[field]=value
            with self.subTest(field=field), self.assertRaises(ValueError):
                observations([row],metadata(),'HT2026',['1'])
        with self.assertRaisesRegex(ValueError,'Duplicate'):
            observations([self.row,self.row],metadata(),'HT2026',['1'])
        with self.assertRaisesRegex(ValueError,'Empty'):
            observations([],metadata(),'HT2026',['1'])

    def test_deadline_blocks_before_network(self):
        with DeadlineSession(0) as s, self.assertRaisesRegex(RuntimeError,'time budget'):
            s.get('https://example.invalid')
