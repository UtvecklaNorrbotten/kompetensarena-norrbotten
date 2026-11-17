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
from gleif.bulk import read_csv,FIELDS
from gleif.import_gleif import relation,reserved_tree,record

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

    def test_no_exact_lei_never_asserts_no_group(self):
        r=reserved_tree({'status':'not_found','entities':[]},{},{})
        self.assertEqual(r['status'],'no_exact_lei')
        self.assertNotIn('no_parent',canonical(r))

    def test_untrusted_urls_and_redirects_are_rejected(self):
        with self.assertRaises(GleifError):Client().response('https://synthetic.example/steal')

if __name__=='__main__':unittest.main()
