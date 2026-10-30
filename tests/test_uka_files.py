"""Syntetiska Exempel för kontroller som ska stoppa felaktig publicering."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock
spec=importlib.util.spec_from_file_location('uka',Path(__file__).parents[1]/'scripts/uka_files_sync.py')
uka=importlib.util.module_from_spec(spec)
spec.loader.exec_module(uka)

class ValidationTests(unittest.TestCase):
    def row(self,**kwargs):
        return dict(period='2020/21',university='Luleå tekniska universitet',gender='Total',
                    value=72.3,dimensions={'program':'Sjuksköterskeexamen','aldersgrupp':'Total'},**kwargs)

    def test_distinct_dimensions_are_not_duplicates(self):
        a=self.row();b=self.row();b['dimensions']['aldersgrupp']='-24'
        uka.validate([a,b],required_program=True)

    def test_duplicate_observation_cannot_replace_active_batch(self):
        with self.assertRaisesRegex(ValueError,'Dubblett'):uka.validate([self.row(),self.row()])

    def test_impossible_percent_and_period_rejected(self):
        for field,value in [('value',101),('value',float('nan')),('period','2020/22')]:
            r=self.row();r[field]=value
            with self.assertRaises(ValueError):uka.validate([r])

    def test_null_is_preserved_separately_from_zero(self):
        self.assertIsNone(uka.number('..'));self.assertEqual(uka.number('–'),0)
        self.assertEqual(uka.number('72,30'),72.3)
        with self.assertRaises(ValueError):uka.number('not-a-number')

    def test_missing_universities_and_program_rejected(self):
        r=self.row();r['university']='Riket'
        with self.assertRaisesRegex(ValueError,'LTU'):uka.validate([r])
        r=self.row();r['dimensions'].pop('program')
        with self.assertRaisesRegex(ValueError,'Program'):uka.validate([r],required_program=True)

    def test_failed_chunk_aborts_without_finalize(self):
        p=uka.Publisher.__new__(uka.Publisher)
        p.request=Mock(side_effect=[{'batch_id':'batch'},RuntimeError('chunk failed'),{}])
        with self.assertRaisesRegex(RuntimeError,'chunk failed'):p.publish('uka-test',[self.row()])
        self.assertEqual([c.args[0] for c in p.request.call_args_list],['uka/start','uka/chunk','uka/abort'])

    def test_finalize_count_must_match(self):
        p=uka.Publisher.__new__(uka.Publisher)
        p.request=Mock(side_effect=[{'batch_id':'batch'},{},{'rows':0},{}])
        with self.assertRaisesRegex(ValueError,'radantal'):p.publish('uka-test',[self.row()])

if __name__=='__main__':unittest.main()
