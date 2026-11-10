"""Synthetic policy and checkpoint examples; no network requests."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
from uka_json_plan import build_plan
from uka_source_audit import digest, write_json


class PlanTests(unittest.TestCase):
    def inventory(self):
        return {'indicators': [{'id': 33, 'periods': ['2025/26'], 'genders': ['Kvinnor', 'Total'],
            'ages': ['-24', 'Total'], 'age_parameter_values': {'-24': '8', 'Total': '1'},
            'groups': [{'options_including_total': 5}], 'university_options_including_riket': 78}]}

    def test_deterministic_keys_and_no_premature_completion(self):
        with tempfile.TemporaryDirectory() as cache:
            a = build_plan(self.inventory(), 'example', cache)
            self.assertEqual(a, build_plan(self.inventory(), 'example', cache))
            self.assertEqual(len(a['jobs']), 4)
            self.assertEqual(a['completed_discovery_jobs'], 0)
            self.assertFalse(a['publish_allowed'])
            self.assertNotEqual(a['plan_id'], build_plan(self.inventory(), 'new-release', cache)['plan_id'])

    def test_valid_root_cache_does_not_complete_child_discovery(self):
        with tempfile.TemporaryDirectory() as cache:
            a = build_plan(self.inventory(), 'example', cache); job = a['jobs'][0]
            body = {'indicator': {'id': 33}, 'groups': [], 'yearly_totals': {'totals': [{'year': '2025/26', 'value': 14.4}]}}
            path = Path(cache) / 'responses' / (job['cache_key'] + '.json')
            write_json(path, {'url': job['url'], 'snapshot': 'example', 'body': body, 'sha256': digest(body)})
            b = build_plan(self.inventory(), 'example', cache)
            self.assertEqual(b['root_states']['cached_root_validated'], 1)
            self.assertEqual(b['jobs'][0]['discovery_state'], 'pending')
            path.write_text(path.read_text().replace('14.4', '99.9'))
            self.assertEqual(build_plan(self.inventory(), 'example', cache)['root_states']['invalid_cache'], 1)

    def test_unknown_age_mapping_blocks_plan(self):
        with tempfile.TemporaryDirectory() as cache:
            i = self.inventory(); i['indicators'][0]['ages'].append('Exempelålder')
            with self.assertRaisesRegex(ValueError, 'mapping incomplete'):
                build_plan(i, 'example', cache)


if __name__ == '__main__':
    unittest.main()
