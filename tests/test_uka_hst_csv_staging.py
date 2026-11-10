"""Synthetic examples for atomic scoped CSV staging; no live UKÄ requests."""
import copy
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
from uka_campaign import Campaign, CampaignProbe
from uka_hst_csv_staging import file_hash, reference_observations, run, stage_package
from uka_json_plan import build_plan
from uka_json_probe import BASE, validate_url
from uka_json_queue import Queue
from uka_source_audit import digest, write_json


def identity(university='171'):
    return json.dumps(['2025/26', university, 'Total', 'Total', {}], ensure_ascii=False, sort_keys=True)


class CSVPackageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        inventory = {'indicators': [{'id': 33, 'periods': ['2025/26'], 'genders': ['Total'],
                     'ages': ['Total'], 'age_parameter_values': {'Total': '1'},
                     'groups': [], 'university_options_including_riket': 2}]}
        self.plan = build_plan(inventory, 'example', self.root)
        self.c = Campaign(self.root, self.plan, 33)
        self.addCleanup(lambda: self.c.close() if self.c is not None else None)
        self.manifest = {'version': 1, 'indicator': 33, 'snapshot': 'example',
                         'plan_id': self.plan['plan_id'],
                         'scope': {'period': '2025/26', 'universities': ['171'], 'genders': ['Total'], 'ages': ['Total']},
                         'csv_sha256': 'synthetic-csv', 'subject_metadata_hash': digest(self.c.subject_metadata),
                         'expected_observations': 1, 'publish_allowed': False, 'source_release_verified': False}
        self.actual = {identity(): '1.25'}

    def stage(self, manifest=None, actual=None, reference=None):
        return stage_package(self.c, manifest or self.manifest,
                             self.actual if actual is None else actual,
                             self.actual if reference is None else reference)

    def test_scoped_write_and_idempotent_resume_leave_national_jobs_unchanged(self):
        before = self.c.report(); package, written = self.stage()
        self.assertTrue(written)
        self.assertEqual(self.stage(), (package, False))
        after = self.c.report()
        for k in ('completed_jobs', 'observations', 'staging_sha256', 'manifest_sha256'):
            self.assertEqual(before[k], after[k])
        self.assertEqual(after['csv_package_observations'], 1)
        self.assertFalse(after['discovery_complete']); self.assertFalse(after['publish_allowed'])
        with self.assertRaisesRegex(ValueError, 'Another worker'):
            Campaign(self.root, self.plan, 33)

    def test_incomplete_or_changed_values_or_extra_keys_are_rejected_before_write(self):
        for changed in ({}, {identity(): '1.26'}, {identity('32'): '1.25'},
                        {**self.actual, identity('32'): '9'}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                self.stage(actual=changed)
        self.assertEqual(self.c.csv_packages(), [])

    def test_missing_positive_reference_and_missing_context_fail(self):
        with self.assertRaisesRegex(ValueError, 'positive reference'):
            self.stage(reference={})
        m = copy.deepcopy(self.manifest); m['scope']['genders'].append('Kvinnor')
        with self.assertRaisesRegex(ValueError, 'contexts'):
            self.stage(manifest=m)

    def test_changed_policy_and_changed_manifest_for_same_scope_are_rejected(self):
        for field in ('snapshot', 'plan_id', 'subject_metadata_hash'):
            changed = {**self.manifest, field: 'changed'}
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'policy'):
                self.stage(manifest=changed)
        self.stage()
        with self.assertRaisesRegex(ValueError, 'another manifest'):
            self.stage(manifest={**self.manifest, 'csv_sha256': 'revision'})

    def test_resume_checks_staged_rows_and_manifest_before_reporting_progress(self):
        self.stage()
        self.c.db.execute("UPDATE csv_observations SET payload='{}'"); self.c.db.commit()
        with self.assertRaisesRegex(ValueError, 'CSV observations changed'):
            self.c.report()
        # A new Campaign constructor also rejects the modified package.
        self.c.close(); self.c = None
        with self.assertRaisesRegex(ValueError, 'CSV observations changed'):
            Campaign(self.root, self.plan, 33)

    def test_null_is_distinct_from_missing_and_zero(self):
        with self.assertRaisesRegex(ValueError, 'positive reference'):
            self.stage(actual={identity(): None}, reference={identity(): '0'})
        self.stage(actual={identity(): None}, reference={identity(): None})
        p = json.loads(self.c.db.execute('SELECT payload FROM csv_observations').fetchone()[0])
        self.assertIn('value', p); self.assertIsNone(p['value'])

    def test_transaction_interruption_rolls_back_rows_and_completion(self):
        # Create the schema via a successful write, then remove that synthetic package.
        self.stage()
        self.c.db.execute('DELETE FROM csv_observations'); self.c.db.execute('DELETE FROM csv_packages')
        self.c.db.execute("CREATE TRIGGER simulate_crash BEFORE INSERT ON csv_observations BEGIN SELECT RAISE(ABORT, 'Synthetic interruption'); END")
        self.c.db.commit()
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'Synthetic interruption'):
            self.stage()
        self.assertEqual(self.c.db.execute('SELECT count(*) FROM csv_packages').fetchone()[0], 0)
        self.assertEqual(self.c.db.execute('SELECT count(*) FROM csv_observations').fetchone()[0], 0)
        self.c.db.execute('DROP TRIGGER simulate_crash'); self.c.db.commit()
        self.assertTrue(self.stage()[1])

    def test_overlapping_packages_cannot_duplicate_rows(self):
        self.stage()
        m = copy.deepcopy(self.manifest); m['scope']['universities'].append('32'); m['expected_observations'] = 2
        actual = {**self.actual, identity('32'): '2'}
        with self.assertRaises(sqlite3.IntegrityError):
            self.stage(manifest=m, actual=actual, reference=actual)
        self.assertEqual(len(self.c.csv_packages()), 1)

    def test_conflict_with_national_staging_fails(self):
        payload = dict(indicator=33, period='2025/26', gender='Total', age='Total', university='171', dimensions={}, value='9')
        key = digest([33, '2025/26', 'Total', 'Total', '171', {}])
        job_id = self.c.db.execute('SELECT id FROM jobs').fetchone()[0]
        self.c.db.execute('INSERT INTO observations VALUES (?,?,?,?)', (key, job_id, json.dumps(payload), 'synthetic'))
        self.c.db.commit()
        with self.assertRaisesRegex(ValueError, 'conflicts with national'):
            self.stage()


class ReferenceReplayTests(unittest.TestCase):
    def test_explicit_projection_verifies_full_national_graph_then_selects_ltu(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); url = BASE + '/33?university=1&year=2025%2F26'
            q = validate_url(url, 33)
            body = {'indicator': {'id': 33}, 'yearly_totals': {'totals': [{'year': '2025/26', 'value': 12.5}]},
                    'groups': [{'column': 'Lärosäten', 'totals': [{'name': 'Exempel LTU', 'value': 1.25,
                               'url': BASE + '/33?university=32&year=2025%2F26'}]}]}
            write_json(root / 'responses' / (digest(['example', 33, q]) + '.json'),
                       {'snapshot': 'example', 'url': url, 'sha256': digest(body), 'body': body})
            database = root / 'reference.sqlite'; probe = CampaignProbe(root, 'example', 0)
            with Queue(database, url, 'example', 'study-first', 33) as queue:
                self.assertTrue(queue.run(probe)['graph_closed'])
                binding = json.loads(queue.db.execute('SELECT binding FROM meta').fetchone()[0])
            manifest = {'snapshot': 'example', 'scope': {'period': '2025/26', 'universities': ['32'], 'genders': ['Total'], 'ages': ['Total']},
                        'reference_universities': ['1'], 'references': [{'file': database.name, 'sha256': file_hash(database), 'binding': binding}]}
            self.assertEqual(reference_observations(manifest, root, probe, {'paths': []}), {identity('32'): '1.25'})
            manifest['scope']['universities'] = ['999']
            with self.assertRaisesRegex(ValueError, 'No positive'):
                reference_observations(manifest, root, probe, {'paths': []})

    def test_fresh_replay_checks_source_hash_graph_and_frozen_reference(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); url = BASE + '/33?university=171&year=2025%2F26'
            q = validate_url(url, 33)
            body = {'indicator': {'id': 33}, 'groups': [], 'yearly_totals': {'totals': [{'year': '2025/26', 'value': 1.25}]}}
            source_path = root / 'responses' / (digest(['example', 33, q]) + '.json')
            saved = {'snapshot': 'example', 'url': url, 'sha256': digest(body), 'body': body}
            write_json(source_path, saved)
            database = root / 'reference.sqlite'; probe = CampaignProbe(root, 'example', 0)
            with Queue(database, url, 'example', 'study-first', 33) as queue:
                self.assertTrue(queue.run(probe)['graph_closed'])
                binding = json.loads(queue.db.execute('SELECT binding FROM meta').fetchone()[0])
            manifest = {'snapshot': 'example', 'scope': {'period': '2025/26', 'universities': ['171'], 'genders': ['Total'], 'ages': ['Total']},
                        'references': [{'file': database.name, 'sha256': file_hash(database), 'binding': binding}]}
            with patch('requests.sessions.Session.request', side_effect=AssertionError('Network forbidden')):
                self.assertEqual(reference_observations(manifest, root, probe, {'paths': []}), {identity(): '1.25'})
                empty = {**manifest, 'references': []}
                with self.assertRaisesRegex(ValueError, 'Missing positive'):
                    reference_observations(empty, root, probe, {'paths': []})
                saved['body']['yearly_totals']['totals'][0]['value'] = 9
                write_json(source_path, saved)
                with self.assertRaisesRegex(ValueError, 'cannot close'):
                    reference_observations(manifest, root, probe, {'paths': []})
                database.write_bytes(database.read_bytes() + b'changed')
                with self.assertRaisesRegex(ValueError, 'checksum changed'):
                    reference_observations(manifest, root, probe, {'paths': []})


class FrozenCSVReceiptTests(unittest.TestCase):
    def attempt(self, mutate):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); csv = root / 'csv'
            with zipfile.ZipFile('tests/fixtures/uka-hst-bulk-2026-11-06.zip') as archive:
                archive.extractall(csv)
            mutate(csv)
            with patch('requests.sessions.Session.request', side_effect=AssertionError('Network forbidden')):
                with self.assertRaises((ValueError, RuntimeError)):
                    run(root / 'staging', csv, csv / 'export-filters.json', root / 'missing-references', [],
                        'config/uka_hst_csv_pilot.json', root / 'report.json')
            self.assertFalse((root / 'staging' / 'campaign.sqlite').exists())

    def test_metadata_projection_change_fails_before_staging(self):
        def mutate(csv):
            p = csv / 'export-filters.json'; m = json.loads(p.read_text())
            m['universities'][0]['label'] = 'Synthetic changed label'; write_json(p, m)
        self.attempt(mutate)

    def test_csv_bytes_change_cannot_trigger_live_fallback_or_staging(self):
        def mutate(csv):
            sha = json.loads(Path('config/uka_hst_csv_pilot.json').read_text())['csv_sha256']
            for p in (csv / 'selections').glob('*.csv'):
                if file_hash(p) == sha:
                    p.write_bytes(p.read_bytes() + b'changed'); return
            self.fail('Missing frozen pilot CSV')
        self.attempt(mutate)
