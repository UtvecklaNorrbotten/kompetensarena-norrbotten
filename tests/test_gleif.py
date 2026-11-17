"""Synthetic GLEIF fixtures: exact matching, pagination, exceptions and history."""
import csv
import io
import json
import sys
import tempfile
import unittest
import zipfile
from datetime import date
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from gleif.client import Client,GleifError,org_number,canonical,entity
from gleif.bulk import read_csv,FIELDS,bulk_response
from gleif.import_gleif import relation,reserved_tree,record
from gleif import import_gleif

A='12340000000000000000';B='12340000000000000100';C='12340000000000000200'

def raw(lei=A,org='000000-0000',registry='RA000544',country='SE'):
    return {'id':lei,'attributes':{'lei':lei,'entity':{'legalName':{'name':'Synthetic AB'},
       'registeredAs':org,'registeredAt':{'id':registry},'jurisdiction':country,'status':'ACTIVE'},
       'registration':{'status':'ISSUED','lastUpdateDate':'2026-01-01'}}}

def rr(parent=B,status='ACTIVE',registration='PUBLISHED',deleted=''):
    return {'Relationship.StartNode.NodeID':A,'Relationship.StartNode.NodeIDType':'LEI',
       'Relationship.EndNode.NodeID':parent,'Relationship.EndNode.NodeIDType':'LEI',
       'Relationship.RelationshipType':'IS_DIRECTLY_CONSOLIDATED_BY','Relationship.RelationshipStatus':status,
       'Registration.RegistrationStatus':registration,'DeletedAt':deleted}

class Gleif(unittest.TestCase):
    def test_only_exact_registry_identifiers_are_used_not_names(self):
        self.assertEqual(org_number('000000-0000'),'0000000000')
        self.assertIsNone(org_number('SE000000000001'))
        client=Client()
        with patch.object(client,'search',return_value=([raw(),raw(B,registry='OTHER')],'2026-01-01T00:00:00Z')):
            values,pub=client.identities(['0000000000'])
        self.assertEqual(values['0000000000']['status'],'matched')
        self.assertEqual(len(values['0000000000']['entities']),1)
        with patch.object(client,'search',return_value=([raw(),raw(B)],'2026-01-01T00:00:00Z')):
            values,pub=client.identities(['0000000000'])
        self.assertEqual(values['0000000000']['status'],'ambiguous')

    def test_pagination_is_complete_and_pinned(self):
        client=Client()
        def page(items,page=1,last=1,total=1,pub='2026-01-01T00:00:00Z'):
            return {'meta':{'goldenCopy':{'publishDate':pub},'pagination':{'currentPage':page,'lastPage':last,'total':total}},'data':items}
        with patch.object(client,'json',side_effect=[page([raw()],last=2,total=2),page([raw(B)],2,2,2)]):
            rows,pub=client.search({})
            self.assertEqual(len(rows),2)
        for response in [page([],total=1),page([raw(),raw()],total=2)]:
            with patch.object(client,'json',return_value=response),self.assertRaises(GleifError):client.search({})
        with patch.object(client,'json',side_effect=[page([raw()],last=2,total=2),page([raw(B)],2,2,2,'2026-01-02T00:00:00Z')]),self.assertRaises(GleifError):client.search({})

    def test_inactive_and_deleted_relations_never_become_current_parent(self):
        result=relation(A,'direct',[rr(status='INACTIVE'),rr(deleted='2026-01-01')],[])
        self.assertEqual(result['state'],'unreported')
        self.assertEqual(len(result['historical_records']),2)
        ended=rr();ended.update({'Relationship.Period.1.periodType':'RELATIONSHIP_PERIOD','Relationship.Period.1.endDate':'2020-12-31T00:00:00Z'})
        self.assertEqual(relation(A,'direct',[ended],[],date(2026,1,1))['state'],'unreported')

    def test_exception_is_not_a_parent_or_identified_person(self):
        ex={'LEI':A,'Exception.Category':'DIRECT_ACCOUNTING_CONSOLIDATION_PARENT','Exception.Reason.1':'NATURAL_PERSONS'}
        r=relation(A,'direct',[],[ex]);self.assertEqual(r['state'],'exception');self.assertEqual(r['relations'],[])
        self.assertEqual(relation(A,'direct',[rr()],[ex])['state'],'conflict')
        self.assertEqual(relation(A,'direct',[rr(),rr(C)],[])['state'],'conflict')

    def test_lapsed_is_retained_with_caution_and_foreign_parents_are_preserved(self):
        r=relation(A,'direct',[rr(registration='LAPSED')],[])
        self.assertEqual(r['state'],'relation');self.assertIn('relationship_registration_lapsed',r['warnings'])
        e=entity(raw());parent=entity(raw(B,country='US'))
        tree=reserved_tree({'status':'matched','entities':[e]},{'rr':{A:[rr()]},'repex':{}},{B:parent})
        self.assertEqual(tree['parents'][0]['jurisdiction'],'US')
        self.assertNotIn('ownership_percentage',canonical(tree))

    def test_csv_schema_counts_and_filtering(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'test.zip';stream=io.StringIO();writer=csv.DictWriter(stream,fieldnames=sorted(FIELDS['rr']|set(rr())))
            writer.writeheader();writer.writerow(rr())
            with zipfile.ZipFile(p,'w') as z:z.writestr('synthetic.csv',stream.getvalue())
            self.assertEqual(len(read_csv(p,'rr',{A},1)[A]),1)
            self.assertEqual(read_csv(p,'rr',{C},1),{})
            with self.assertRaises(GleifError):read_csv(p,'rr',{A},2)
            with zipfile.ZipFile(p,'w') as z:z.writestr('synthetic.csv','unexpected\nvalue\n')
            with self.assertRaises(GleifError):read_csv(p,'rr',{A},1)

    def test_full_files_without_deleted_at_and_delta_tombstones(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'test.zip'
            for kind,row,key in [('rr',rr(),A),('repex',{'LEI':A,'Exception.Category':'DIRECT_ACCOUNTING_CONSOLIDATION_PARENT','Exception.Reason.1':'NATURAL_PERSONS'},A)]:
                row.pop('DeletedAt',None)
                for deleted in (None,'2026-01-01'):
                    value=dict(row)
                    if deleted:value['DeletedAt']=deleted
                    stream=io.StringIO();writer=csv.DictWriter(stream,fieldnames=sorted(value))
                    writer.writeheader();writer.writerow(value)
                    with zipfile.ZipFile(p,'w') as z:z.writestr('synthetic.csv',stream.getvalue())
                    parsed=read_csv(p,kind,{key},1)[key][0]
                    if deleted:self.assertEqual(parsed['DeletedAt'],deleted)
                    else:self.assertNotIn('DeletedAt',parsed)
                    result=relation(A,'direct',[parsed] if kind=='rr' else [],[parsed] if kind=='repex' else [])
                    self.assertEqual(result['state'],'unreported' if deleted else 'relation' if kind=='rr' else 'exception')

    def test_fresh_scheduled_run_reuses_scope_without_source_downloads(self):
        row={'identity':{'sha256':'a','next_check_at':'2999-01-01T00:00:00Z'},
             'relations':{'next_check_at':'2999-01-01T00:00:00Z','source':{'identity_sha256':'a','release':'2026-01-01'}}}
        with patch.object(import_gleif,'scope',return_value=[row]) as scope, \
             patch.object(import_gleif,'load') as load, \
             patch.object(import_gleif.Client,'identities') as identities, \
             patch.object(import_gleif.api,'call',return_value={'scope':1,'relations_checked':1}), \
             patch.object(import_gleif.api,'log') as log,patch('builtins.print'):
            import_gleif.main()
        scope.assert_called_once();load.assert_not_called();identities.assert_not_called()
        self.assertEqual(log.call_args.args[1],'no_change')
        self.assertEqual(log.call_args.args[3]['remaining_due'],0)

    def test_bulk_403_uses_only_same_pinned_path_on_official_mirror(self):
        client=Client();url='https://goldencopy.gleif.org/storage/golden-copy-files/2026/01/01/1/synthetic.csv.zip'
        response=object()
        with patch.object(client,'response',side_effect=[GleifError('GLEIF HTTP 403 resource=bulk'),response]) as request,patch('builtins.print'):
            r,used=bulk_response(client,url)
        self.assertIs(r,response)
        self.assertEqual(used,url.replace('goldencopy.gleif.org','leidata-preview.gleif.org'))
        self.assertEqual(request.call_count,2)
        with patch.object(client,'response',side_effect=GleifError('GLEIF HTTP 500 resource=bulk')) as request,self.assertRaises(GleifError):
            bulk_response(client,url)
        self.assertEqual(request.call_count,1)
        with patch.object(client,'response',side_effect=GleifError('GLEIF HTTP 403 resource=bulk')),self.assertRaises(GleifError):
            bulk_response(client,'https://synthetic.example/storage/golden-copy-files/test.zip')
        with self.assertRaises(GleifError):Client().response('https://leidata-preview.gleif.org/arbitrary')

    def test_no_exact_lei_never_asserts_no_group(self):
        r=reserved_tree({'status':'not_found','entities':[]},{},{})
        self.assertEqual(r['status'],'no_exact_lei')
        self.assertNotIn('no_parent',canonical(r))

    def test_untrusted_urls_and_redirects_are_rejected(self):
        with self.assertRaises(GleifError):Client().response('https://synthetic.example/steal')

if __name__=='__main__':unittest.main()
