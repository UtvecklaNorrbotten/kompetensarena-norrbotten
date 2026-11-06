"""Synthetic examples of incomplete CSV packages against saved staging."""
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
from uka_campaign import rows_digest
from uka_csv_staging_audit import audit
from uka_source_audit import digest


def csv_key(university):
    return json.dumps(['2025/26', university, 'Total', 'Total', {}], ensure_ascii=False, sort_keys=True)


def database(path):
    db = sqlite3.connect(path)
    db.executescript('CREATE TABLE meta(binding TEXT); CREATE TABLE jobs(id TEXT, ordinal INTEGER, spec TEXT, summary TEXT, status TEXT); CREATE TABLE observations(key TEXT, job_id TEXT, payload TEXT, source_hash TEXT);')
    db.execute('INSERT INTO meta VALUES (?)', (json.dumps({'indicator': 33, 'snapshot': 'example', 'plan_id': 'example-plan'}),))
    for uni, value in [('1','12.3'), ('32','4.5')]:
        payload = dict(indicator=33, period='2025/26', gender='Total', age='Total', university=uni, dimensions={}, value=value)
        key = digest([33, '2025/26', 'Total', 'Total', uni, {}])
        db.execute('INSERT INTO observations VALUES (?,?,?,?)', (key,'example-job',json.dumps(payload),'example-hash'))
    checksum = rows_digest(db.execute('SELECT key,payload,source_hash FROM observations ORDER BY key'))
    db.execute('INSERT INTO jobs VALUES (?,?,?,?,?)', ('example-job',0,json.dumps(dict(period='2025/26', gender='Total',age='Total')),json.dumps({'staging_sha256':checksum}),'done'))
    db.commit(); db.close()


class CSVStagingAuditTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'campaign.sqlite'; database(self.path)

    def test_subset_matches_values_but_cannot_complete_national_job(self):
        before = self.path.read_bytes()
        r = audit({csv_key('1'):'12.3'}, self.path, 'example', '2025/26')
        c = r['comparisons'][0]
        self.assertEqual(c['identical_shared_values'],1)
        self.assertEqual(c['only_reference'],1)
        self.assertFalse(c['national_selection_equivalent'])
        self.assertFalse(r['publish_allowed']); self.assertFalse(r['staging_written'])
        self.assertEqual(before,self.path.read_bytes())

    def test_exact_candidate_still_does_not_publish_or_write(self):
        r = audit({csv_key('1'):'12.3', csv_key('32'):'4.5'}, self.path, 'example', '2025/26')
        self.assertTrue(r['all_national_references_equivalent'])
        self.assertFalse(r['publish_allowed']); self.assertFalse(r['staging_written'])

    def test_same_count_with_value_change_or_university_swap_fails(self):
        for changed in ({csv_key('1'):'12.4',csv_key('32'):'4.5'},
                        {csv_key('1'):'12.3',csv_key('99'):'4.5'}):
            self.assertFalse(audit(changed,self.path,'example','2025/26')['all_national_references_equivalent'])

    def test_wrong_snapshot_and_period_fail(self):
        with self.assertRaisesRegex(ValueError, 'snapshot'):
            audit({},self.path,'other','2025/26')
        with self.assertRaisesRegex(ValueError, 'No completed'):
            audit({},self.path,'example','2024/25')
        with self.assertRaisesRegex(ValueError, 'another period'):
            audit({csv_key('1'):'12.3'},self.path,'example','2024/25')

    def test_tampered_staging_is_rejected(self):
        db=sqlite3.connect(self.path); db.execute("UPDATE observations SET payload='{}'"); db.commit(); db.close()
        with self.assertRaisesRegex(ValueError, 'Previously staged'):
            audit({},self.path,'example','2025/26')
