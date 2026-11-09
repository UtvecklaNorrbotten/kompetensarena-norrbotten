"""Synthetic year/coverage/transaction examples; no live source requests."""
import copy
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import urlencode

sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
from uka_hst_full_csv import Collection, observation_key, root_control, union_exact
from uka_json_probe import BASE, validate_url
from uka_source_audit import digest


def metadata():
    m = {'indicator': 33, 'snapshot': 'example',
         'universities': [{'value': 'uni:' + u, 'label': 'Exempel ' + u} for u in ('1', '32', '171')],
         'retained_periods': [{'value': f'from:{y}/{str(y+1)[-2:]}'} for y in range(2025, 2015, -1)],
         'genders': [{'label': g, 'value': 'gender:' + g} for g in ('Kvinnor', 'Män', 'Total')],
         'ages': [{'label': a, 'value': 'age:' + t} for a, t in (('-24', '8'), ('25-34', '9'), ('35-', '10'), ('Total', '1'))],
         'groups': [{'index': '6.', 'values': [{'label': s, 'value': 'dynamic:' + t} for s, t in
                    (('Total', 'TOTAL'), ('Exempel A', 'a_'), ('Exempel B', 'b_'), ('Exempel C', 'c_'), ('Exempel D', 'd_'))]},
                    {'index': '7.', 'values': [{'label': 'Total', 'value': 'dynamic:TOTAL'}]}]}
    m['metadata_hash'] = digest(m)
    return m


def body(url, indicator=33):
    q = validate_url(url, 33)
    return {'indicator': {'id': indicator}, 'yearly_totals': {'totals': [{'year': q['year'], 'value': 1.25}]},
            'groups': [{'column': 'Lärosäten', 'totals': [{'name': 'Exempel ' + u, 'value': 1.25,
                       'url': BASE + '/33?' + urlencode({**q, 'university': u})} for u in ('32', '171')]},
                       {'column': 'Studieform', 'totals': [{'name': 'Exempel ' + s, 'value': 1.25} for s in ('A', 'B', 'C', 'D')]}]}


class FullYearTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name); self.m = metadata()
        self.c = Collection(self.root, self.m, 'example')
        self.addCleanup(lambda: self.c.close() if self.c is not None else None)
        self.c.export = self.export
        self.c.probe.get = body; self.c.bookends.get = body

    def export(self, period, universities, studies):
        observations = {}
        for u in universities:
            for g in self.c.genders:
                for a in self.c.ages:
                    for study in studies:
                        dims = {} if study['label'] == 'Total' else {'Studieform': study['label']}
                        observations[observation_key(period, u, g, a, dims)] = '1.25'
        return observations, {'sha256': digest([period, universities, studies]), 'status': 'data'}

    def test_verified_year_and_resume_do_not_repeat_exports(self):
        first = self.c.collect_year('2025/26')
        self.assertTrue(first['written_this_run']); self.assertEqual(first['observations'], 180)
        self.assertEqual(len(first['coverage']), 12)
        self.c.export = lambda *args: self.fail('Already staged year must not be fetched again')
        resumed = self.c.collect_year('2025/26')
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
            self.c.collect_year('2025/26')
        self.assertEqual(self.c.report()['staged_years'], 0)
        self.assertEqual(json.loads((self.root / 'checkpoints/2025-26.json').read_text())['state'], 'blocked')

    def test_changed_source_bookend_blocks_whole_year(self):
        def changed(url, indicator):
            r = body(url, indicator); r['yearly_totals']['totals'][0]['value'] = 9; return r
        self.c.bookends.get = changed
        with self.assertRaisesRegex(ValueError, 'changed during year'):
            self.c.collect_year('2025/26')
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
                self.c.collect_year('2025/26')
        self.assertEqual(self.c.report()['observations'], 0)

    def test_observation_failure_rolls_back_year_completion(self):
        self.c.db.execute("CREATE TRIGGER synthetic_crash BEFORE INSERT ON observations BEGIN SELECT RAISE(ABORT, 'Synthetic interruption'); END")
        self.c.db.commit()
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'Synthetic interruption'):
            self.c.collect_year('2025/26')
        self.assertEqual(self.c.db.execute('SELECT count(*) FROM years').fetchone()[0], 0)
        self.assertEqual(self.c.db.execute('SELECT count(*) FROM observations').fetchone()[0], 0)

    def test_corrupt_staged_rows_block_resume(self):
        self.c.collect_year('2025/26')
        self.c.db.execute("UPDATE observations SET payload='{}'"); self.c.db.commit()
        with self.assertRaisesRegex(ValueError, 'Previously staged'):
            self.c.collect_year('2025/26')

    def test_changed_manifest_and_unplanned_year_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'outside frozen'):
            self.c.collect_year('2000/01')
        self.c.close(); self.c = None
        changed = copy.deepcopy(self.m); changed['universities'].pop(); changed['metadata_hash'] = digest({k: v for k, v in changed.items() if k != 'metadata_hash'})
        with self.assertRaisesRegex(ValueError, 'manifest changed'):
            Collection(self.root, changed, 'example')

    def test_technical_export_failure_leaves_checkpoint_and_no_completion(self):
        self.c.export = lambda *args: (_ for _ in ()).throw(ValueError('Technical empty body'))
        with self.assertRaisesRegex(ValueError, 'Technical empty'):
            self.c.collect_year('2025/26')
        self.assertEqual(self.c.report()['staged_years'], 0)


class LayoutAndAbsenceTests(unittest.TestCase):
    def test_overlapping_parts_and_same_count_value_change_fail(self):
        with self.assertRaisesRegex(ValueError, 'Overlapping'):
            union_exact([{'a': '1'}, {'a': '1'}], {'a': '1'})
        with self.assertRaisesRegex(ValueError, 'Partition coverage'):
            union_exact([{'["Exempel"]': '2'}], {'["Exempel"]': '1'})

    def test_unadvertised_university_is_recorded_without_generating_zero(self):
        url = BASE + '/33?university=1&year=2025%2F26'
        b = body(url); b['groups'] = []
        actual = {observation_key('2025/26', '1', 'Total', 'Total', {}): '1.25'}
        r = root_control(actual, b, '2025/26', 'Total', 'Total', ['1', '32'])
        self.assertEqual(r['not_advertised_universities'], ['32'])
        self.assertEqual(len(actual), 1)

    def test_null_native_control_is_not_zero(self):
        b = body(BASE + '/33?university=1&year=2025%2F26'); b['groups'] = []
        b['yearly_totals']['totals'][0]['value'] = None
        key = observation_key('2025/26', '1', 'Total', 'Total', {})
        with self.assertRaisesRegex(ValueError, 'differing native'):
            root_control({key: '0'}, b, '2025/26', 'Total', 'Total', ['1'])
        self.assertEqual(root_control({key: None}, b, '2025/26', 'Total', 'Total', ['1'])['native_controls'], 1)
