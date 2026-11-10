"""Synthetic year/coverage/transaction examples; no live source requests."""
import copy
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import urlencode

sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
from uka_99_full_csv import Collection, observation_key, root_control, union_exact
from uka_json_probe import BASE, validate_url
from uka_source_audit import digest, write_json


def metadata():
    m = {'indicator': 99, 'snapshot': 'example',
         'universities': [{'value': 'uni:' + u, 'label': 'Exempel ' + u} for u in ('1', '32', '171')],
         'retained_periods': [{'value': f'from:{t}{y}'} for y in range(2026, 2016, -1) for t in ('HT', 'VT')],
         'genders': [{'label': g, 'value': 'gender:' + g} for g in ('Kvinnor', 'Män', 'Total')],
         'ages': [{'label': a, 'value': 'age:' + t} for a, t in (('Total', '1'),)],
         'groups': [{'index': '6.', 'values': [{'label': s, 'value': 'dynamic:' + t} for s, t in
                    (('Total', 'TOTAL'), ('Exempel A', 'a_'), ('Exempel B', 'b_'), ('Exempel C', 'c_'), ('Exempel D', 'd_'))]}]}
    m['metadata_hash'] = digest(m)
    return m


def body(url, indicator=99):
    q = validate_url(url, 99)
    return {'indicator': {'id': indicator}, 'yearly_totals': {'totals': [{'year': q['year'], 'value': 1.25}]},
            'groups': [{'column': 'Lärosäten', 'totals': [{'name': 'Exempel ' + u, 'value': 1.25,
                       'url': BASE + '/99?' + urlencode({**q, 'university': u})} for u in ('32', '171')]},
                       {'column': 'Program', 'totals': [{'name': 'Exempel ' + s, 'value': 1.25} for s in ('A', 'B', 'C', 'D')]}]}


class FullYearTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name); self.m = metadata()
        self.c = Collection(self.root, self.m, 'example')
        self.addCleanup(lambda: self.c.close() if self.c is not None else None)
        self.c.export = self.export
        self.c.probe.get = lambda url, indicator: self.capture(self.root, url, indicator)
        self.c.bookends.get = lambda url, indicator: self.capture(self.root / 'bookends', url, indicator)

    def capture(self, root, url, indicator):
        value = body(url, indicator)
        path = root / 'responses' / (digest(['example', 99, validate_url(url, 99)]) + '.json')
        write_json(path, {'snapshot': 'example', 'url': url, 'body': value, 'sha256': digest(value)})
        return value

    def export(self, period, universities, studies):
        observations = {}
        for u in universities:
            for g in self.c.genders:
                for a in self.c.ages:
                    for study in studies:
                        dims = {} if study['label'] == 'Total' else {'Program': study['label']}
                        observations[observation_key(period, u, g, a, dims)] = '1.25'
        spec = {'period': period, 'universities': universities, 'studies': studies}
        raw = json.dumps(observations, sort_keys=True).encode()
        receipt = {'spec': spec, 'sha256': hashlib.sha256(raw).hexdigest(), 'status': 'data'}
        p = self.root / 'selections' / (digest(spec) + '.csv'); p.parent.mkdir(exist_ok=True)
        p.write_bytes(raw); write_json(p.with_suffix('.json'), receipt)
        return observations, receipt

    def test_verified_year_and_resume_do_not_repeat_exports(self):
        first = self.c.collect_year('HT2026')
        self.assertTrue(first['written_this_run']); self.assertEqual(first['observations'], 45)
        self.assertEqual(len(first['coverage']), 3)
        self.c.export = lambda *args: self.fail('Already staged year must not be fetched again')
        resumed = self.c.collect_year('HT2026')
        self.assertFalse(resumed['written_this_run'])
        self.assertEqual(first['staging_sha256'], resumed['staging_sha256'])
        report = self.c.report()
        self.assertEqual(report['staged_years'], 1)
        self.assertFalse(report['all_planned_years_staged']); self.assertFalse(report['publish_allowed'])
        self.assertFalse(report['full_source_coverage_verified'])

    def test_missing_row_in_one_partition_blocks_before_staging(self):
        original = self.export
        def incomplete(period, universities, studies):
            actual, receipt = original(period, universities, studies)
            if len(universities) < 3: actual.pop(next(iter(actual)))
            return actual, receipt
        self.c.export = incomplete
        with self.assertRaisesRegex(ValueError, 'Partition coverage'):
            self.c.collect_year('HT2026')
        self.assertEqual(self.c.report()['staged_years'], 0)
        self.assertEqual(json.loads((self.root / 'checkpoints/HT2026.json').read_text())['state'], 'blocked')

    def test_changed_source_bookend_blocks_whole_year(self):
        def changed(url, indicator):
            r = body(url, indicator); r['yearly_totals']['totals'][0]['value'] = 9; return r
        self.c.bookends.get = changed
        with self.assertRaisesRegex(ValueError, 'changed during year'):
            self.c.collect_year('HT2026')
        self.assertEqual(self.c.db.execute('SELECT count(*) FROM observations').fetchone()[0], 0)

    def test_changed_root_value_and_missing_university_do_not_pass_equal_csv_layouts(self):
        for kind in ('value', 'university'):
            def changed(url, indicator, kind=kind):
                r = body(url, indicator)
                if kind == 'value': r['yearly_totals']['totals'][0]['value'] = 99
                else: r['groups'][0]['totals'].pop()
                return r
            self.c.probe.get = changed
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                self.c.collect_year('HT2026')
        self.assertEqual(self.c.report()['observations'], 0)

    def test_observation_failure_rolls_back_year_completion(self):
        self.c.db.execute("CREATE TRIGGER synthetic_crash BEFORE INSERT ON observations BEGIN SELECT RAISE(ABORT, 'Synthetic interruption'); END")
        self.c.db.commit()
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'Synthetic interruption'):
            self.c.collect_year('HT2026')
        self.assertEqual(self.c.db.execute('SELECT count(*) FROM years').fetchone()[0], 0)
        self.assertEqual(self.c.db.execute('SELECT count(*) FROM observations').fetchone()[0], 0)

    def test_corrupt_staged_rows_block_resume(self):
        self.c.collect_year('HT2026')
        self.c.db.execute("UPDATE observations SET payload='{}'"); self.c.db.commit()
        with self.assertRaisesRegex(ValueError, 'Previously staged'):
            self.c.collect_year('HT2026')

    def test_changed_source_bytes_block_completed_year_resume(self):
        r = self.c.collect_year('HT2026')
        p = self.root / 'selections' / (digest(r['exports'][0]['spec']) + '.csv')
        p.write_bytes(p.read_bytes() + b'changed')
        with self.assertRaisesRegex(ValueError, 'CSV source or receipt changed'):
            self.c.collect_year('HT2026')

    def test_changed_manifest_and_unplanned_year_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Another worker'):
            Collection(self.root, self.m, 'example')
        with self.assertRaisesRegex(ValueError, 'outside frozen'):
            self.c.collect_year('HT2000')
        self.c.close(); self.c = None
        changed = copy.deepcopy(self.m); changed['universities'].pop(); changed['metadata_hash'] = digest({k: v for k, v in changed.items() if k != 'metadata_hash'})
        with self.assertRaisesRegex(ValueError, 'manifest changed'):
            Collection(self.root, changed, 'example')

    def test_technical_export_failure_leaves_checkpoint_and_no_completion(self):
        self.c.export = lambda *args: (_ for _ in ()).throw(ValueError('Technical empty body'))
        with self.assertRaisesRegex(ValueError, 'Technical empty'):
            self.c.collect_year('HT2026')
        self.assertEqual(self.c.report()['staged_years'], 0)


class LayoutAndAbsenceTests(unittest.TestCase):
    def test_overlapping_parts_and_same_count_value_change_fail(self):
        with self.assertRaisesRegex(ValueError, 'Overlapping'):
            union_exact([{'a': '1'}, {'a': '1'}], {'a': '1'})
        with self.assertRaisesRegex(ValueError, 'Partition coverage'):
            union_exact([{'["Exempel"]': '2'}], {'["Exempel"]': '1'})

    def test_unadvertised_university_is_recorded_without_generating_zero(self):
        url = BASE + '/99?university=1&year=HT2026'
        b = body(url); b['groups'] = []
        actual = {observation_key('HT2026', '1', 'Total', 'Total', {}): '1.25'}
        r = root_control(actual, b, 'HT2026', 'Total', 'Total', ['1', '32'])
        self.assertEqual(r['not_advertised_universities'], ['32'])
        self.assertEqual(len(actual), 1)

    def test_null_native_control_is_not_zero(self):
        b = body(BASE + '/99?university=1&year=HT2026'); b['groups'] = []
        b['yearly_totals']['totals'][0]['value'] = None
        key = observation_key('HT2026', '1', 'Total', 'Total', {})
        with self.assertRaisesRegex(ValueError, 'differing native'):
            root_control({key: '0'}, b, 'HT2026', 'Total', 'Total', ['1'])
        self.assertEqual(root_control({key: None}, b, 'HT2026', 'Total', 'Total', ['1'])['native_controls'], 1)
