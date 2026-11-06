"""Synthetic source and crash examples for file staging; no production writes."""
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import Mock
sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
from uka_campaign import Campaign, CampaignProbe
from uka_json_plan import build_plan
from uka_source_audit import digest, write_json


def inventory():
    return {'indicators': [{'id': 99, 'periods': ['HT2026', 'VT2026'],
            'genders': ['Total'], 'ages': ['Total'], 'age_parameter_values': {'Total': '1'},
            'groups': [{'options_including_total': 2}], 'university_options_including_riket': 2}]}


def cache_source(root, url, value, snapshot='example'):
    from uka_json_probe import validate_url
    body = {'indicator': {'id': 99}, 'groups': [],
            'yearly_totals': {'totals': [{'year': validate_url(url, 99)['year'], 'value': value}]}}
    path = Path(root) / 'responses' / (digest([snapshot, 99, validate_url(url, 99)]) + '.json')
    write_json(path, {'url': url, 'snapshot': snapshot, 'body': body, 'sha256': digest(body)})
    return body


class CampaignTests(unittest.TestCase):
    def test_partial_plan_cannot_be_complete_or_publish(self):
        with tempfile.TemporaryDirectory() as tmp:
            plan = build_plan(inventory(), 'example', tmp)
            cache_source(tmp, plan['jobs'][0]['url'], 1.7)
            with Campaign(tmp, plan, 99) as c:
                r = c.run(CampaignProbe(tmp, 'example', 0))
                self.assertEqual(r['completed_jobs'], 1)
                self.assertEqual(r['observations'], 1)
                self.assertFalse(r['discovery_complete'])
                self.assertFalse(r['publish_allowed'])

    def test_resume_preserves_staged_rows_and_only_fetches_missing_selection(self):
        with tempfile.TemporaryDirectory() as tmp:
            plan = build_plan(inventory(), 'example', tmp)
            cache_source(tmp, plan['jobs'][0]['url'], 1.7)
            with Campaign(tmp, plan, 99) as c:
                c.run(CampaignProbe(tmp, 'example', 0))
            probe = CampaignProbe(tmp, 'example', 1)
            response = Mock(); response.json.return_value = {'indicator': {'id': 99}, 'groups': [],
                'yearly_totals': {'totals': [{'year': 'VT2026', 'value': 2.3}]}}
            probe.session.get = Mock(return_value=response)
            with Campaign(tmp, plan, 99) as c:
                result = c.run(probe)
                self.assertTrue(result['discovery_complete'])
                self.assertFalse(result['publish_allowed'])
                self.assertEqual(result['observations'], 2)
                self.assertEqual(probe.session.get.call_args.args[0], plan['jobs'][1]['url'])
                signature = result['staging_sha256']
            with Campaign(tmp, plan, 99) as c:
                replay = c.run(CampaignProbe(tmp, 'example', 0))
                self.assertEqual(replay['new_requests'], 0)
                self.assertEqual(replay['staging_sha256'], signature)

    def test_manifest_change_and_second_writer_are_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            plan = build_plan(inventory(), 'example', tmp)
            with Campaign(tmp, plan, 99):
                with self.assertRaisesRegex(ValueError, 'Another worker'):
                    Campaign(tmp, plan, 99)
            changed = build_plan(inventory(), 'new-snapshot', tmp)
            with self.assertRaisesRegex(ValueError, 'manifest or policy'):
                Campaign(tmp, changed, 99)

    def test_transaction_rolls_back_rows_and_done_marker_on_duplicate(self):
        with tempfile.TemporaryDirectory() as tmp:
            plan = build_plan(inventory(), 'example', tmp); spec = plan['jobs'][0]
            cache_source(tmp, spec['url'], 1.7)
            with Campaign(tmp, plan, 99) as c:
                with c.queue(spec) as q:
                    summary = q.run(CampaignProbe(tmp, 'example', 0))
                    c.db.execute("CREATE TRIGGER simulate_crash BEFORE UPDATE ON jobs WHEN NEW.status='done' BEGIN SELECT RAISE(ABORT, 'Synthetic crash'); END")
                    c.db.commit()
                    with self.assertRaisesRegex(sqlite3.IntegrityError, 'Synthetic crash'):
                        c.stage(spec, q, summary)
                    self.assertEqual(c.db.execute('SELECT count(*) FROM observations').fetchone()[0], 0)
                    self.assertEqual(c.db.execute('SELECT status FROM jobs WHERE id=?', (spec['job_id'],)).fetchone()[0], 'pending')
                    c.db.execute('DROP TRIGGER simulate_crash'); c.db.commit()
                    c.stage(spec, q, summary)
                    self.assertEqual(c.db.execute('SELECT count(*) FROM observations').fetchone()[0], 1)

    def test_staging_rejects_tampered_observation_even_with_valid_body_hash(self):
        with tempfile.TemporaryDirectory() as tmp:
            plan = build_plan(inventory(), 'example', tmp); spec = plan['jobs'][0]
            cache_source(tmp, spec['url'], 1.7)
            with Campaign(tmp, plan, 99) as c, c.queue(spec) as q:
                summary = q.run(CampaignProbe(tmp, 'example', 0))
                row = q.db.execute('SELECT id,observations FROM nodes').fetchone()
                observations = json.loads(row['observations']); observations[0]['value'] = '99.9'
                q.db.execute('UPDATE nodes SET observations=? WHERE id=?', (json.dumps(observations), row['id'])); q.db.commit()
                with self.assertRaisesRegex(ValueError, 'differs from source'):
                    c.stage(spec, q, summary)
                self.assertEqual(c.db.execute('SELECT count(*) FROM observations').fetchone()[0], 0)

    def test_shared_source_cache_is_read_without_duplication_or_requests(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp) / 'base'; primary = Path(tmp) / 'primary'
            plan = build_plan(inventory(), 'example', base); spec = plan['jobs'][0]
            cache_source(base, spec['url'], 1.7)
            p = CampaignProbe(primary, 'example', 0, [base])
            self.assertEqual(p.get(spec['url'], 99)['indicator']['id'], 99)
            self.assertEqual(p.requests, 0)
            self.assertFalse((primary / 'responses').exists())

    def test_completed_baseline_queue_is_seeded_without_fetching_or_copying_source_cache(self):
        from uka_json_queue import Queue
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp) / 'base'; primary = Path(tmp) / 'staging'
            plan = build_plan(inventory(), 'example', base); spec = plan['jobs'][0]
            cache_source(base, spec['url'], 1.7)
            with Queue(base / 'known.sqlite', spec['url'], 'example', indicator=99) as q:
                self.assertTrue(q.run(CampaignProbe(base, 'example', 0))['graph_closed'])
            with Campaign(primary, plan, 99, [base]) as c:
                r = c.run(CampaignProbe(primary, 'example', 0, [base]))
                self.assertEqual(r['seeded_jobs'], 1)
                self.assertEqual(r['observations'], 1)
                self.assertEqual(r['new_requests'], 0)
                self.assertFalse((primary / 'responses').exists())

    def test_source_queue_for_other_period_cannot_be_staged_under_first_period(self):
        with tempfile.TemporaryDirectory() as tmp:
            plan = build_plan(inventory(), 'example', tmp)
            first, second = plan['jobs']
            cache_source(tmp, second['url'], 1.7)
            with Campaign(tmp, plan, 99) as c, c.queue(second) as q:
                result = q.run(CampaignProbe(tmp, 'example', 0))
                with self.assertRaisesRegex(ValueError, 'does not match manifest'):
                    c.stage(first, q, result)
                self.assertEqual(c.db.execute('SELECT count(*) FROM observations').fetchone()[0], 0)

    def test_modified_previously_staged_data_is_rejected_on_resume(self):
        with tempfile.TemporaryDirectory() as tmp:
            plan = build_plan(inventory(), 'example', tmp)
            cache_source(tmp, plan['jobs'][0]['url'], 1.7)
            with Campaign(tmp, plan, 99) as c:
                c.run(CampaignProbe(tmp, 'example', 0))
                c.db.execute("UPDATE observations SET payload='{}'"); c.db.commit()
            with self.assertRaisesRegex(ValueError, 'Previously staged observations changed'):
                Campaign(tmp, plan, 99)
