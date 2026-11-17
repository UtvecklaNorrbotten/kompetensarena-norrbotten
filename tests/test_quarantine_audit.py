"""Synthetic examples for diagnostic reasons, auxiliary files and safe output."""
import io
import sys
import unittest
import zipfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from company_accounts.audit_quarantine import diagnose, reason
from test_company_accounts import report, ORG


def package(*documents):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w') as z:
        for i, content in enumerate(documents):
            z.writestr(f'synthetic-{i}.xhtml', content)
    return stream.getvalue()


class QuarantineDiagnostics(unittest.TestCase):
    def test_auxiliary_filing_does_not_turn_valid_report_into_quarantine(self):
        result = diagnose(package(report(), b'<html/>'), {'org_nr': ORG, 'period_end': '2025-04-30'})
        self.assertEqual(result['outcome'], 'supported_company_report')
        self.assertEqual(result['valid_documents'], 1)
        self.assertEqual(result['errors'], {'missing_report_scope': 1})
        self.assertNotIn('metrics', result)

    def test_conflicting_valid_reports_remain_ambiguous(self):
        result = diagnose(package(report(), report(revenue='9')), {'org_nr': ORG, 'period_end': '2025-04-30'})
        self.assertEqual(result['outcome'], 'conflicting_company_reports')
        self.assertEqual(result['valid_documents'], 2)

    def test_no_company_report_and_malformed_xml_are_distinguished(self):
        result = diagnose(package(b'<html/>', b'<html>'), {'org_nr': ORG, 'period_end': '2025-04-30'})
        self.assertEqual(result['outcome'], 'no_supported_company_report')
        self.assertEqual(result['errors'], {'missing_report_scope': 1, 'invalid_xml': 1})
        self.assertEqual(reason(ValueError('synthetic-secret')), 'unclassified_parser_error')

    def test_pdf_is_reported_without_claiming_extraction(self):
        result = diagnose(b'%PDF-synthetic', {'org_nr': ORG, 'period_end': '2025-04-30'})
        self.assertEqual(result['outcome'], 'pdf_only')
        self.assertEqual(result['valid_documents'], 0)


if __name__ == '__main__':
    unittest.main()
