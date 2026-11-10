"""Synthetic examples: source evidence is tested separately against UKÄ."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).parents[1]/'scripts'))
from uka_source_audit import digest
from uka_verified_collection import Collection, observations, paths, root_control
from uka_json_probe import BASE


def metadata():
    m={'indicator':13,'snapshot':'example','universities':[{'value':'uni:1','label':'Riket'},{'value':'uni:2','label':'Exempelhögskolan'}],
       'genders':[{'value':'gender:'+x,'label':x} for x in ('Kvinnor','Män','Total')],
       'ages':[{'value':'age:1','label':'Total'}], 'retained_periods':[{'value':'from:HT2026','label':'HT2026'}],
       'groups':[{'index':'6.','values':[{'value':'dynamic:TOTAL','label':'Total'},{'value':'dynamic:10_','label':'Exempelprogram'}]}]}
    m['metadata_hash']=digest(m); return m


def rows():
    return [{'Tidsperiod':'HT2026','Lärosäte':'','Kön':g,'Åldersgrupp':'Total','Program':p,'Värde':'2,30'}
            for g in ('Kvinnor','Män','Total') for p in ('','Exempelprogram')]


def body(gender='Total'):
    q='&gender='+gender if gender!='Total' else ''
    return {'indicator':{'id':13},'yearly_totals':{'totals':[{'year':'HT2026','value':2.3}]},
            'groups':[{'column':'Lärosäten','totals':[]}, {'column':'Program','totals':[{'name':'Exempelprogram','value':2.3,'url':BASE+'/13?university=1&year=HT2026'+q+'&group_slug=example'}]}]}


class VerifiedCollectionTest(unittest.TestCase):
    def test_exact_decimal_identity_and_duplicates(self):
        actual=observations(rows(),metadata(),'HT2026',['1','2'])
        self.assertEqual(set(actual.values()),{'2.3'})
        changed=rows()+[dict(rows()[0], **{'Värde':'99'})]
        with self.assertRaisesRegex(ValueError,'Duplicate'): observations(changed,metadata(),'HT2026',['1','2'])

    def test_rejects_context_unknown_dimension_and_header_collision(self):
        for column,value in [('Program','Okänt'),('Kön','Okänt'),('Åldersgrupp','-24'),('Tidsperiod','VT2026'),('Lärosäte','Okänd')]:
            r=rows(); r[0][column]=value
            with self.assertRaises(ValueError): observations(r,metadata(),'HT2026',['1','2'])
        r=rows();r[0]['Program[0]']=''
        with self.assertRaises(ValueError): observations(r,metadata(),'HT2026',['1','2'])

    def test_path_preserves_parent_context(self):
        g={'values':[{'value':'dynamic:'+token,'label':name} for token,name in [('1_','A'),('2_','B'),('3_1','Övrigt'),('3_2','Övrigt')]]}
        result=paths(g,('Examenskategori','Examen'))
        self.assertIn({'Examenskategori':'A','Examen':'Övrigt'},result)
        self.assertIn({'Examenskategori':'B','Examen':'Övrigt'},result)
        with self.assertRaises(ValueError): paths({'values':[{'value':'dynamic:3_9','label':'X'}]},('A','B'))

    def test_positive_absence_does_not_create_zeros(self):
        a=observations(rows(),metadata(),'HT2026',['1','2'])
        r=root_control(a,body(),13,'HT2026','Total','Total',['1','2'])
        self.assertEqual(r['not_advertised_universities'],['2'])
        self.assertEqual(len(a),6)
        with self.assertRaises(ValueError): root_control({},body(),13,'HT2026','Total','Total',['1','2'])

    def test_bad_control_value_or_context_blocks(self):
        a=observations(rows(),metadata(),'HT2026',['1','2'])
        for mutate in ('value','url','missing','unknown'):
            b=body(); r=b['groups'][1]['totals'][0]
            if mutate=='value':r['value']=99
            if mutate=='url':r['url']=r['url'].replace('HT2026','VT2026')
            if mutate=='missing':del r['value']
            if mutate=='unknown':b['groups'][1]['column']='Okänd'
            with self.assertRaises(ValueError):root_control(a,b,13,'HT2026','Total','Total',['1','2'])

    def test_missing_or_duplicate_json_dimension_lists_block(self):
        a=observations(rows(),metadata(),'HT2026',['1','2'])
        for groups in ([],[body()['groups'][0]],body()['groups']+[body()['groups'][1]]):
            b=body();b['groups']=groups
            with self.assertRaisesRegex(ValueError,'root dimension'):root_control(a,b,13,'HT2026','Total','Total',['1','2'])

    def test_77_source_group_order_is_study_then_level(self):
        from uka_verified_collection import GROUP_LEVELS
        self.assertEqual(GROUP_LEVELS[77],[('Studieform',),('Utbildningsnivå',)])

    def test_null_and_marker_are_not_zero(self):
        r=rows();r[0]['Värde']='..';a=observations(r,metadata(),'HT2026',['1','2'])
        self.assertIn('..',a.values())
        b=body(); b['yearly_totals']['totals'][0]['value']=None
        with self.assertRaises(ValueError):root_control(a,b,13,'HT2026','Total','Total',['1','2'])

    def test_manifest_lock_and_changed_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            with Collection(tmp,metadata(),'example'):
                with self.assertRaisesRegex(ValueError,'Another worker'):Collection(tmp,metadata(),'example')
            m=metadata();m['retained_periods'].append({'value':'from:VT2026','label':'VT2026'});m['metadata_hash']=digest({k:v for k,v in m.items() if k!='metadata_hash'})
            with self.assertRaisesRegex(ValueError,'manifest changed'):Collection(tmp,m,'example')
            m=metadata();m['ages'][0]['label']='-24'
            with self.assertRaisesRegex(ValueError,'metadata'):Collection(tmp,m,'example')

    def test_failed_export_never_commits_and_resume_zero_budget(self):
        with tempfile.TemporaryDirectory() as tmp:
            with Collection(tmp,metadata(),'example') as c:
                with patch.object(c,'export',side_effect=ValueError('Technical empty')):
                    with self.assertRaises(ValueError):c.collect('HT2026')
                self.assertEqual(c.report()['observations'],0)
                self.assertEqual(c.db.execute('SELECT count(*) FROM periods').fetchone()[0],0)
                self.assertEqual(json.loads((Path(tmp)/'checkpoints/HT2026.json').read_text())['state'],'blocked')
            with Collection(tmp,metadata(),'example') as c:
                with self.assertRaisesRegex(RuntimeError,'budget'):c.collect('HT2026')
                self.assertFalse(c.report()['publish_allowed'])


class SourceFixtureTest(unittest.TestCase):
    def prepare(self,tmp):
        import zipfile
        with zipfile.ZipFile(Path(__file__).parent/'fixtures/uka-13-coverage-2026-11-10.zip') as z:z.extractall(tmp)
        return json.loads((Path(tmp)/'metadata.json').read_text())

    def test_actual_source_offline_staging_restart_and_tampering(self):
        with tempfile.TemporaryDirectory() as tmp:
            m=self.prepare(tmp)
            with Collection(tmp,m,'2026-11-10-all') as c:
                r=c.collect('HT2026');self.assertTrue(r['written_this_run']);self.assertEqual(r['observations'],5046)
                expected=r['staging_sha256'];self.assertFalse(c.collect('HT2026')['written_this_run'])
                self.assertEqual(c.report()['new_json_requests'],0);self.assertEqual(c.report()['new_exports'],0)
            with Collection(tmp,m,'2026-11-10-all') as c:
                self.assertEqual(c.collect('HT2026')['staging_sha256'],expected)
                with c.db:c.db.execute("UPDATE observations SET payload='{}' WHERE key=(SELECT min(key) FROM observations)")
            with self.assertRaisesRegex(ValueError,'Staged rows'):Collection(tmp,m,'2026-11-10-all')

    def test_transaction_rollback_keeps_source_for_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            m=self.prepare(tmp)
            with Collection(tmp,m,'2026-11-10-all') as c:
                c.db.execute("CREATE TRIGGER synthetic_abort BEFORE INSERT ON observations BEGIN SELECT RAISE(ABORT,'Synthetic interrupted write'); END")
                with self.assertRaisesRegex(Exception,'Synthetic interrupted write'):c.collect('HT2026')
                self.assertEqual(c.db.execute('SELECT count(*) FROM periods').fetchone()[0],0)
                self.assertEqual(c.db.execute('SELECT count(*) FROM observations').fetchone()[0],0)
                c.db.execute('DROP TRIGGER synthetic_abort')
                self.assertEqual(c.collect('HT2026')['observations'],5046)

    def test_changed_raw_evidence_prevents_resume(self):
        with tempfile.TemporaryDirectory() as tmp:
            m=self.prepare(tmp)
            with Collection(tmp,m,'2026-11-10-all') as c:c.collect('HT2026')
            raw=next((Path(tmp)/'selections').glob('*.csv'));raw.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError,'CSV source evidence'):Collection(tmp,m,'2026-11-10-all')

if __name__=='__main__':unittest.main()
