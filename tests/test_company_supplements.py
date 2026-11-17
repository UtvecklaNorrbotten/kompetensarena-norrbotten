"""Synthetic examples: fallback is opt-in, narrow and never silently verified."""
import io
import sys
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from test_company_accounts import report,ORG
from company_accounts.ixbrl import parse
from company_accounts.supplement_accounts import extract_reserved,process,as_zip

URI='http://xbrl.taxonomier.se/se/fr/gaap/k2/risbs/2017-09-30/se-k2-risbs-2017-09-30.xsd'

def legacy(uri=URI,extra=''):
    dat=report(extra+'<link:schemaRef xmlns:link="http://www.xbrl.org/2003/linkbase" xmlns:xlink="http://www.w3.org/1999/xlink" xlink:href="'+uri+'"/>')
    return dat.replace(b'<ix:nonNumeric name="g:FinansiellRapportList" contextRef="p">ArsredovisningMember</ix:nonNumeric>',b'')

def package(*docs):
    b=io.BytesIO()
    with zipfile.ZipFile(b,'w') as z:
        for i,d in enumerate(docs):z.writestr(str(i)+'.xhtml',d)
    return b.getvalue()

class Supplements(unittest.TestCase):
    def test_strict_parser_unchanged_and_reserved_scope_explicit(self):
        with self.assertRaisesRegex(ValueError,'missing report scope'):
            parse(legacy(),ORG,'2025-04-30')
        r=parse(legacy(),ORG,'2025-04-30',allow_legacy_k2=True)
        self.assertEqual(r['metrics']['net_sales'],'1234500')
        self.assertIn('legacy_k2_missing_scope_declaration',r['issues'])
        self.assertEqual(r['provenance']['_report']['scope_basis'],'inferred_legacy_k2_with_reservation')

    def test_other_hosts_versions_frameworks_and_dimensions_refused(self):
        for uri in [URI.replace('xbrl.taxonomier.se','synthetic.example'),URI.replace('2017-09-30','2021-10-31'),URI.replace('/k2/','/k3/')]:
            with self.assertRaises(ValueError):parse(legacy(uri),ORG,'2025-04-30',allow_legacy_k2=True)
        with self.assertRaises(ValueError):
            parse(legacy(extra='<x:explicitMember>synthetic</x:explicitMember>'),ORG,'2025-04-30',allow_legacy_k2=True)
        with self.assertRaises(ValueError):parse(legacy(), '1111111111','2025-04-30',allow_legacy_k2=True)

    def test_security_and_conflicting_reports_still_blocked(self):
        with self.assertRaises(ValueError):parse(b'<!DOCTYPE html>'+legacy(),ORG,'2025-04-30',allow_legacy_k2=True)
        with self.assertRaises(ValueError):extract_reserved(package(legacy(),legacy().replace(b'1 234,5',b'9')),ORG,'2025-04-30')

    def test_nil_metrics_not_invented_and_source_pdf_preserved(self):
        r,sha=extract_reserved(package(legacy(),b'<html/>'),ORG,'2025-04-30')
        self.assertIsNone(r['metrics']['average_employees'])
        with zipfile.ZipFile(io.BytesIO(as_zip(b'%PDF-synthetic'))) as z:
            self.assertEqual(z.read('source.pdf'),b'%PDF-synthetic')

    def test_api_no_documents_checkpoint_has_no_fabricated_source(self):
        class Client:
            def documents(self,org):return []
        r=process({'org_nr':ORG},'api',Client())
        self.assertEqual(r['reason'],'api_no_documents')
        self.assertIsNone(r['package_sha256'])
        self.assertIsNone(r['document'])

if __name__=='__main__':unittest.main()
