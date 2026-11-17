"""Synthetic examples: safe structural categories, never financial values."""
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from diagnose_company_quarantine import structure
from test_company_accounts import report, ORG

class Structure(unittest.TestCase):
    def test_missing_fact_differs_from_unsupported_namespace(self):
        row = {'org_nr': ORG, 'period_end': '2025-04-30'}
        self.assertEqual(structure(b'<html/>', row)['structure'], 'no_inline_facts')
        self.assertEqual(structure(report(), row)['structure'], 'supported_scope_fact')
        changed = report().replace(b'http://www.taxonomier.se/se/fr/gen-base/2021-10-31', b'https://synthetic.example/extension')
        self.assertEqual(structure(changed, row)['structure'], 'scope_namespace_rejected')
        self.assertEqual(structure(report(), {**row, 'org_nr': '1111111111'})['company_contexts'], 'missing')

    def test_dtd_is_never_parsed(self):
        self.assertEqual(structure(b'<!DOCTYPE html><html/>', {})['structure'], 'doctype_blocked')
        self.assertEqual(structure(b'<!DOCTYPE html [<!ENTITY x "synthetic">]>', {})['structure'], 'entity_declaration_blocked')

if __name__ == '__main__':
    unittest.main()
