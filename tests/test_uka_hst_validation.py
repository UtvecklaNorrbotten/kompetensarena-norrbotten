"""Synthetic plan and budget checks for the HST validation campaign."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from urllib.parse import parse_qs, urlparse
sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
from uka_hst_validation import cases, run


class ValidationTests(unittest.TestCase):
    def test_plan_has_two_periods_all_three_genders_and_four_ages(self):
        plan = cases()
        self.assertEqual(len(plan), 24)
        self.assertEqual(len({c['root_url'] for c in plan}), 24)
        self.assertEqual({c['gender'] for c in plan}, {'Total', 'Kvinnor', 'Män'})
        self.assertEqual({c['age'] for c in plan}, {'Total', '8', '9', '10'})
        for case in plan:
            query = parse_qs(urlparse(case['root_url']).query)
            self.assertEqual('gender' in query, case['gender'] != 'Total')
            self.assertEqual('age_group' in query, case['age'] != 'Total')

    def test_zero_budget_preserves_pending_case_and_forbids_publication(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = run(tmp, 'example', budget=0)
            self.assertEqual(result['new_requests'], 0)
            self.assertFalse(result['campaign_closed'])
            self.assertFalse(result['publish_allowed'])
            self.assertEqual(result['completed_cases'], 0)
            self.assertEqual(result['cases'][0]['states'], {'pending': 1})
            self.assertTrue((Path(tmp) / 'hst-validation.json').exists())
