"""Synthetic examples. Integration smoke test reads real source files separately."""
import io
import sys
import unittest
import zipfile
from decimal import Decimal
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from company_accounts.allocation import allocate
from company_accounts.ixbrl import parse
from company_accounts.profiles import profile
from company_accounts.source import RangeReader
from unittest.mock import patch
from concurrent.futures import ThreadPoolExecutor
from company_accounts.archive_pool import ArchivePool
from company_accounts.import_accounts import import_one

ORG='0000000000'  # Synthetic identifier, not a real company.


def report(extra='', revenue='1 234,5',scale='3',currency='SEK'):
    return f'''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:ix="http://www.xbrl.org/2013/inlineXBRL"
    xmlns:x="http://www.xbrl.org/2003/instance" xmlns:g="http://www.taxonomier.se/se/fr/gen-base/2021-10-31"
    xmlns:cd="http://www.taxonomier.se/se/fr/cd-base/2021-10-31" xmlns:iso="http://www.xbrl.org/2003/iso4217">
    <x:context id="p"><x:entity><x:identifier scheme="http://www.bolagsverket.se">{ORG}</x:identifier></x:entity><x:period><x:startDate>2024-05-01</x:startDate><x:endDate>2025-04-30</x:endDate></x:period></x:context>
    <x:context id="b"><x:entity><x:identifier scheme="http://www.bolagsverket.se">{ORG}</x:identifier></x:entity><x:period><x:instant>2025-04-30</x:instant></x:period></x:context>
    <x:unit id="sek"><x:measure>iso:{currency}</x:measure></x:unit>
    <ix:nonNumeric name="g:FinansiellRapportList" contextRef="p">ArsredovisningMember</ix:nonNumeric>
    <ix:nonNumeric name="cd:RakenskapsarForstaDag" contextRef="p">2024-05-01</ix:nonNumeric>
    <ix:nonFraction name="g:Nettoomsattning" contextRef="p" unitRef="sek" format="ixt:numspacecomma" scale="{scale}">{revenue}</ix:nonFraction>
    <ix:nonFraction name="g:Rorelseresultat" contextRef="p" unitRef="sek" format="ixt:numspacecomma" sign="-">10</ix:nonFraction>
    <ix:nonFraction name="g:EgetKapital" contextRef="b" unitRef="sek" format="ixt:numspacecomma">0</ix:nonFraction>
    <ix:nonFraction name="g:Tillgangar" contextRef="b" unitRef="sek" format="ixt:numspacecomma">100</ix:nonFraction>
    {extra}</html>'''.encode()


class Accounts(unittest.TestCase):
    def test_scale_sign_missing_zero_and_period(self):
        r=parse(report(),ORG,'2025-04-30')
        self.assertEqual(Decimal(r['metrics']['net_sales']),Decimal('1234500'))
        self.assertEqual(r['metrics']['operating_profit'],'-10')
        self.assertEqual(r['metrics']['equity'],'0')
        self.assertIsNone(r['metrics']['profit_for_year'])
        self.assertEqual(r['period_start'],'2024-05-01')
        self.assertEqual(r['currency'],'SEK')

    def test_framework_and_original_entrypoint_retained(self):
        uri='http://xbrl.taxonomier.se/se/fr/gaap/k3/risbs/2021-10-31/se-k3-risbs-2021-10-31.xsd'
        extra='<link:schemaRef xmlns:link="http://www.xbrl.org/2003/linkbase" xmlns:xlink="http://www.w3.org/1999/xlink" xlink:href="'+uri+'"/>'
        r=parse(report(extra),ORG,'2025-04-30')
        self.assertTrue(r['report_type'].startswith('K3;'))
        self.assertEqual(r['provenance']['_report']['entrypoints'],[uri])

    def test_conflicting_duplicate_is_missing(self):
        extra='<ix:nonFraction name="g:Nettoomsattning" contextRef="p" unitRef="sek">999</ix:nonFraction>'
        self.assertIsNone(parse(report(extra),ORG,'2025-04-30')['metrics']['net_sales'])

    def test_equal_duplicate_not_added(self):
        extra='<ix:nonFraction name="g:Nettoomsattning" contextRef="p" unitRef="sek">1234500</ix:nonFraction>'
        self.assertEqual(Decimal(parse(report(extra),ORG,'2025-04-30')['metrics']['net_sales']),Decimal(1234500))


    def test_rounded_duplicates_use_most_accurate_without_addition(self):
        extra='<ix:nonFraction name="g:Nettoomsattning" contextRef="p" unitRef="sek" decimals="0">1234499</ix:nonFraction>'
        data=report(extra).replace(b'scale="3"',b'scale="3" decimals="-3"')
        r=parse(data,ORG,'2025-04-30')
        self.assertEqual(r['metrics']['net_sales'],'1234499')
        self.assertIn('net_sales:consistent_rounded_duplicates',r['issues'])
        self.assertEqual(len(r['provenance']['net_sales']),2)

    def test_exact_duplicate_and_negative_rounding(self):
        extra='<ix:nonFraction name="g:Nettoomsattning" contextRef="p" unitRef="sek" decimals="INF">-1234499</ix:nonFraction>'
        data=report(extra,revenue='-1 234,5').replace(b'scale="3"',b'scale="3" decimals="-3"')
        self.assertEqual(parse(data,ORG,'2025-04-30')['metrics']['net_sales'],'-1234499')

    def test_truly_inconsistent_rounding_keeps_gap_and_provenance(self):
        extra='<ix:nonFraction name="g:Nettoomsattning" contextRef="p" unitRef="sek" decimals="0">1236000</ix:nonFraction>'
        data=report(extra).replace(b'scale="3"',b'scale="3" decimals="-3"')
        r=parse(data,ORG,'2025-04-30')
        self.assertIsNone(r['metrics']['net_sales'])
        self.assertEqual(len(r['provenance']['net_sales']),2)

    def test_same_accuracy_different_values_not_resolved(self):
        extra='<ix:nonFraction name="g:Nettoomsattning" contextRef="p" unitRef="sek" decimals="0">1234501</ix:nonFraction>'
        data=report(extra).replace(b'scale="3"',b'scale="3" decimals="0"')
        self.assertIsNone(parse(data,ORG,'2025-04-30')['metrics']['net_sales'])

    def test_employee_unit_alias_is_prefix_independent(self):
        extra='<x:unit id="employees"><x:measure>g:MedelantaletAnstallda</x:measure></x:unit><ix:nonFraction name="g:MedelantaletAnstallda" contextRef="p" unitRef="employees" decimals="0">3</ix:nonFraction>'
        r=parse(report(extra),ORG,'2025-04-30')
        self.assertEqual(r['metrics']['average_employees'],'3')
        bad=report(extra).replace(b'<x:measure>g:MedelantaletAnstallda</x:measure>',b'<x:measure>iso:SEK</x:measure>')
        self.assertIsNone(parse(bad,ORG,'2025-04-30')['metrics']['average_employees'])

    def test_unknown_extension_does_not_replace_standard_fact(self):
        data=report().replace(b'xmlns:g="http://www.taxonomier.se/se/fr/gen-base/2021-10-31"',b'xmlns:g="https://synthetic.example/extension"')
        with self.assertRaises(ValueError):parse(data,ORG,'2025-04-30')

    def test_group_declaration_never_used_for_company(self):
        extra='<ix:nonNumeric name="g:FinansiellRapportList" contextRef="p">KoncernredovisningMember</ix:nonNumeric>'
        with self.assertRaises(ValueError):parse(report(extra),ORG,'2025-04-30')

    def test_wrong_identity_and_period_refused(self):
        with self.assertRaises(ValueError):parse(report(),'1111111111','2025-04-30')
        with self.assertRaises(ValueError):parse(report(),ORG,'2024-04-30')

    def test_unknown_transform_is_gap(self):
        data=report().replace(b'ixt:numspacecomma" scale',b'ixt:unknown" scale')
        self.assertIsNone(parse(data,ORG,'2025-04-30')['metrics']['net_sales'])

    def test_excluded_footnote_is_not_a_digit(self):
        r=parse(report(revenue='1 234,5<ix:exclude>9</ix:exclude>'),ORG,'2025-04-30')
        self.assertEqual(Decimal(r['metrics']['net_sales']),Decimal('1234500'))

    def test_dtd_refused(self):
        with self.assertRaises(ValueError):parse(b'<!DOCTYPE html>'+report(),ORG,'2025-04-30')


class Allocation(unittest.TestCase):
    def rows(self,*classes):
        return [dict(cfar_nr=str(i+1),history_id=i+1,anst_kl=c) for i,c in enumerate(classes)]

    def test_single_even_missing(self):
        r=allocate(self.rows(None),'10')
        self.assertEqual(Decimal(r[0]['weight']),1)
        self.assertEqual(Decimal(r[0]['estimated_net_sales']),10)

    def test_all_swedish_establishments_not_geographic_subset(self):
        r=allocate(self.rows(2,3),'1900')
        self.assertEqual(Decimal(r[0]['weight']),Decimal('0.263157894736842105'))
        self.assertEqual(sum(Decimal(x['estimated_net_sales']) for x in r),1900)

    def test_zero_excluded_when_positive_exists(self):
        r=allocate(self.rows(1,2),'100')
        self.assertEqual(Decimal(r[0]['weight']),0)
        self.assertEqual(Decimal(r[1]['weight']),1)

    def test_all_zero_equal_and_residual(self):
        r=allocate(self.rows(1,1,1),'100')
        self.assertEqual(sum(Decimal(x['weight']) for x in r),1)
        self.assertEqual(sum(Decimal(x['estimated_net_sales']) for x in r),100)
        self.assertTrue(all('all_zero_equal_weights' in x['flags'] for x in r))

    def test_missing_imputed_median_not_zero(self):
        r=allocate(self.rows(2,3,None),'100')
        self.assertEqual(Decimal(r[2]['midpoint']),Decimal('4.75'))
        self.assertIn('imputed_company_median',r[2]['flags'])

    def test_open_top_and_missing_sales(self):
        r=allocate(self.rows(16,2),None)
        self.assertEqual(Decimal(r[0]['midpoint']),Decimal('12499.5'))
        self.assertIsNone(r[0]['estimated_net_sales'])

    def test_fictitious_mobile_establishment_is_explicit(self):
        rows=self.rows(2,3)
        rows[1]['ae_typ']=3
        result=allocate(rows,'100')
        self.assertIn('fictitious_establishment',result[1]['flags'])
        self.assertEqual(sum(Decimal(r['weight']) for r in result),1)

    def test_wire_decimals_never_use_scientific_notation(self):
        for revenue in ('0','0.00000001','100'):
            for row in allocate(self.rows(1,2,16),revenue):
                for field in ('midpoint','weight','estimated_net_sales'):
                    self.assertRegex(row[field],r'^-?\d+(\.\d+)?$')

    def test_duplicate_cfar_refused(self):
        with self.assertRaises(ValueError):allocate([dict(cfar_nr='1',anst_kl=2)]*2,'100')


class Profiles(unittest.TestCase):
    def test_contacts_excluded_from_history_hash(self):
        a=profile(dict(peOrgNr='synthetic',namn='Exempel',expImp='N',tel='1'),'je')
        b=profile(dict(peOrgNr='synthetic',namn='Exempel',expImp='N',tel='2'),'je')
        self.assertEqual(a['profile_hash'],b['profile_hash'])
        self.assertNotEqual(a['contact_hash'],b['contact_hash'])

    def test_string_code_and_coordinate_types(self):
        self.assertIn('"expImp":"J"',profile(dict(peOrgNr='synthetic',expImp='J'),'je')['profile_canonical'])
        with self.assertRaises(ValueError):profile(dict(cfarNr=1,geografiskInformation={'nordKoordinatAdressSW':'123'}),'ae')


class Ranges(unittest.TestCase):
    def test_full_download_response_refused(self):
        class Response(io.BytesIO):
            status=200
            headers={}
        with patch('company_accounts.source.request',return_value=Response(b'x'*100)):
            with self.assertRaises(ValueError):RangeReader(dict(key='test',size=100,etag='x')).read(10)


class RangeMemory(unittest.TestCase):
    def test_large_read_keeps_only_bounded_cache(self):
        data=b'a'*300000
        class Response(io.BytesIO):
            status=206
            headers={'Content-Range':'bytes 0-249999/300000'}
        reader=RangeReader(dict(key='test',size=len(data),etag='one'))
        with patch('company_accounts.source.request',return_value=Response(data[:250000])):
            self.assertEqual(reader.read(250000),data[:250000])
        self.assertEqual(len(reader.cached),131072)
        reader.seek(100)
        self.assertEqual(reader.read(20),data[100:120])


class ArchiveReuse(unittest.TestCase):
    def setUp(self):
        self.data=io.BytesIO()
        with zipfile.ZipFile(self.data,'w',zipfile.ZIP_DEFLATED) as z:
            for i in range(20):z.writestr(str(i),('Synthetic example '+str(i))*100)
        self.opens=0
        def opener(archive):
            self.opens+=1
            reader=io.BytesIO(self.data.getvalue())
            return reader,zipfile.ZipFile(reader)
        self.pool=ArchivePool(capacity=1,opener=opener)
        self.a=dict(key='a',etag='one',size=len(self.data.getvalue()))

    def test_parallel_members_share_one_directory(self):
        def read(i):
            with self.pool.acquire(self.a) as z:return z.read(str(i)).decode()
        with ThreadPoolExecutor(max_workers=8) as workers:
            values=list(workers.map(read,range(20)))
        self.assertEqual(self.opens,1)
        self.assertTrue(all(v==('Synthetic example '+str(i))*100 for i,v in enumerate(values)))

    def test_etag_change_opens_new_archive_without_closing_active_reader(self):
        with self.pool.acquire(self.a) as first:
            with self.pool.acquire({**self.a,'etag':'two'}) as second:
                self.assertEqual(second.read('1'),first.read('1'))
            self.assertEqual(first.read('2'),('Synthetic example 2'*100).encode())
        self.assertEqual(self.opens,2)
        self.assertEqual(len(self.pool.entries),1)


class ConcurrentStructure(unittest.TestCase):
    def candidate(self):
        return dict(je_id='synthetic',org_nr=ORG,period_end='2025-04-30',
                    archive_key='arsredovisningar/2026/01_1.zip',member_name=ORG+'_2025-04-30.zip',archive_etag='one')

    def run_import(self, changed):
        calls=[]
        structures=iter([dict(sync_id='old',establishments=[dict(cfar_nr='1',history_id=1,anst_kl=2)]),
                         dict(sync_id='new',establishments=[dict(cfar_nr='1',history_id=2,anst_kl=3)])])
        def call(action,body=None,**params):
            if action=='structure':return next(structures)
            if action=='state':return dict(sync=dict(id='new' if changed else 'old'))
            if action=='account':
                calls.append(body)
                if len(calls)==1:raise RuntimeError('ETL account: HTTP 422')
                return dict(ok=True)
            raise AssertionError(action)
        doc=dict(period_end='2025-04-30',metrics=dict(net_sales='100'))
        with (
            patch('company_accounts.import_accounts.read_package',return_value=b'synthetic zip') as read,
            patch('company_accounts.import_accounts.extract',return_value=('synthetic.xhtml',b'synthetic report',doc)),
            patch('company_accounts.import_accounts.api.upload',return_value='synthetic/path') as upload,
            patch('company_accounts.import_accounts.api.call',side_effect=call),
        ):
            if changed:
                self.assertEqual(import_one(self.candidate()),'imported')
                self.assertEqual(len(calls),2)
                self.assertEqual(calls[1]['structure']['sync_id'],'new')
            else:
                with self.assertRaises(RuntimeError):import_one(self.candidate())
                self.assertEqual(len(calls),1)
            self.assertEqual(read.call_count,1)
            self.assertEqual(upload.call_count,1)

    def test_structure_change_retries_without_refetching_document(self):
        self.run_import(True)

    def test_real_validation_failure_is_not_hidden(self):
        self.run_import(False)


if __name__=='__main__':unittest.main()
