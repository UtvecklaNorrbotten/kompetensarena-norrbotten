"""Synthetic crash/resume and transaction integrity examples."""
import copy
from decimal import Decimal
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import requests
sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
from uka_json_queue import Queue, transient_error

ROOT = 'https://statistik-api.uka.se/api/totals/33?university=171&year=2025%2F26&gender=Kvinnor'


def fixture():
    def body(value, groups=()):
        return {'indicator': {'id': 33}, 'yearly_totals': {'totals': [{'year': '2025/26', 'value': value}]}, 'groups': list(groups)}
    def group(column, name, slug, value):
        return {'column': column, 'totals': [{'name': name, 'url': ROOT + '&group_slug=' + slug, 'value': value}]}
    return {ROOT: body(6, [group('Ämnesområde', 'Exempelämne', 'A', 4), group('Studieform', 'Exempelform', 'S', 5)]),
            ROOT + '&group_slug=A': body(4, [group('Studieform', 'Exempelform', 'AS', 3)]),
            ROOT + '&group_slug=S': body(5, [group('Ämnesområde', 'Exempelämne', 'AS', 3)]),
            ROOT + '&group_slug=AS': body(3)}


class MemoryProbe:
    def __init__(self, data, budget=100):
        self.data, self.budget, self.requests = data, budget, 0
        self.calls = []
    def get(self, url, indicator):
        if self.requests >= self.budget:
            raise RuntimeError('JSON request budget exhausted')
        self.requests += 1; self.calls.append(url)
        return copy.deepcopy(self.data[url])


class QueueTests(unittest.TestCase):
    def test_degree_indicator_follows_specialization_and_retains_source_totals(self):
        root = ROOT.replace('/33?', '/108?')
        data = {}
        for slug, value, column, name, child, expected in (
                ('', 100, 'Examenskategori', 'Exempelkategori', 'C', 40),
                ('C', 40, 'Examen', 'Exempelcivilingenjör', 'E', 30),
                ('E', 30, 'Inriktning', 'Exempelinriktning', 'S', 10)):
            url = root + ('&group_slug=' + slug if slug else '')
            data[url] = {'indicator': {'id': 108}, 'groups': [{'column': column, 'totals': [
                {'name': name, 'value': expected, 'url': root + '&group_slug=' + child}]}],
                'yearly_totals': {'totals': [{'year': '2025/26', 'value': value}]}}
        data[root + '&group_slug=S'] = {'indicator': {'id': 108}, 'groups': [],
            'yearly_totals': {'totals': [{'year': '2025/26', 'value': 10}]}}
        with tempfile.TemporaryDirectory() as tmp, Queue(Path(tmp) / 'q.sqlite', root, 'example', indicator=108) as q:
            r = q.run(MemoryProbe(data))
            self.assertTrue(r['graph_closed'])
            self.assertEqual(r['observations'], 4)
            self.assertEqual({Decimal(json.loads(row[0])) for row in q.db.execute('SELECT value FROM nodes')}, {100, 40, 30, 10})

    def test_program_indicator_retains_decimal_source_values(self):
        root = ROOT.replace('/33?', '/99?')
        data = {root: {'indicator': {'id': 99}, 'groups': [{'column': 'Program', 'totals': [
                    {'name': 'Exempelprogram', 'value': 1.7, 'url': root + '&group_slug=P'}]}],
                    'yearly_totals': {'totals': [{'year': '2025/26', 'value': 2.3}]}},
                root + '&group_slug=P': {'indicator': {'id': 99}, 'groups': [],
                    'yearly_totals': {'totals': [{'year': '2025/26', 'value': 1.7}]}}}
        with tempfile.TemporaryDirectory() as tmp, Queue(Path(tmp) / 'q.sqlite', root, 'example', indicator=99) as q:
            r = q.run(MemoryProbe(data))
            self.assertTrue(r['graph_closed'])
            self.assertEqual(r['indicator'], 99)
            self.assertEqual({json.loads(row[0]) for row in q.db.execute('SELECT value FROM nodes')}, {'2.3', '1.7'})

    def test_unverified_dimension_is_blocked_for_other_indicator(self):
        root = ROOT.replace('/33?', '/99?')
        data = {root: {'indicator': {'id': 99}, 'groups': [{'column': 'Unexpected', 'totals': []}],
                      'yearly_totals': {'totals': [{'year': '2025/26', 'value': 1.7}]}}}
        with tempfile.TemporaryDirectory() as tmp, Queue(Path(tmp) / 'q.sqlite', root, 'example', indicator=99) as q:
            r = q.run(MemoryProbe(data))
            self.assertEqual(r['states'], {'error': 1})
            self.assertFalse(r['graph_closed'])
            self.assertEqual(r['observations'], 0)

    def test_other_indicator_cannot_use_hst_specific_strategy(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'only for HST'):
                Queue(Path(tmp) / 'q.sqlite', ROOT.replace('/33?', '/99?'), 'example', 'study-first', indicator=99)

    def test_study_first_equals_all_routes_for_unambiguous_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            results = []
            for strategy in ('all-routes', 'study-first'):
                with Queue(Path(tmp) / (strategy + '.sqlite'), ROOT, 'example', strategy) as q:
                    result = q.run(MemoryProbe(fixture()))
                    self.assertTrue(result['graph_closed'])
                    results.append(sorted((r['dimensions'], r['value']) for r in q.db.execute('SELECT dimensions,value FROM nodes')))
            self.assertEqual(*results)

    def test_study_first_avoids_polluted_subject_to_study_links(self):
        data = fixture()
        data[ROOT + '&group_slug=A']['groups'][0]['totals'].append(
            {'name': 'Exempelform', 'url': ROOT + '&group_slug=WRONG', 'value': 999})
        with tempfile.TemporaryDirectory() as tmp:
            with Queue(Path(tmp) / 'q.sqlite', ROOT, 'example', 'study-first') as q:
                probe = MemoryProbe(data)
                result = q.run(probe)
                self.assertTrue(result['graph_closed'])
                self.assertEqual(result['observations'], 4)
                self.assertNotIn(ROOT + '&group_slug=WRONG', probe.calls)

    def test_strategy_cannot_change_when_resuming_queue(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'q.sqlite'
            with Queue(path, ROOT, 'example'):
                pass
            with self.assertRaisesRegex(ValueError, 'mismatch'):
                Queue(path, ROOT, 'example', 'study-first')

    def test_only_temporary_transport_and_selected_http_errors_are_retryable(self):
        for status in (408, 425, 429, 500, 502, 503, 504, 400, 401, 403, 404, 422):
            response = requests.Response(); response.status_code = status
            self.assertEqual(transient_error(requests.HTTPError(response=response)), status in (408,425,429,500,502,503,504))
        self.assertTrue(transient_error(requests.Timeout()))
        self.assertFalse(transient_error(requests.exceptions.SSLError()))
        self.assertFalse(transient_error(ValueError('Conflicting source values')))

    def test_retry_backoff_survives_reopen_and_skips_validated_nodes(self):
        class TimeoutProbe(MemoryProbe):
            def get(self, url, indicator):
                self.requests += 1
                raise requests.Timeout('Synthetic timeout')
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / 'q.sqlite'
            with Queue(db, ROOT, 'example') as q:
                q.run(MemoryProbe(fixture()), max_nodes=1)
                with patch('uka_json_queue.time.time', return_value=100):
                    r = q.run(TimeoutProbe(fixture()))
                self.assertEqual(r['states']['retry_wait'], 1)
                self.assertFalse(r['graph_closed'])
            with Queue(db, ROOT, 'example') as q:
                early = MemoryProbe(fixture())
                with patch('uka_json_queue.time.time', return_value=129):
                    r = q.run(early)
                self.assertEqual(r['stop_reason'], 'retry_backoff')
                self.assertNotIn(ROOT + '&group_slug=A', early.calls)
                resumed = MemoryProbe(fixture())
                with patch('uka_json_queue.time.time', return_value=130):
                    r = q.run(resumed)
                self.assertTrue(r['graph_closed'])
                self.assertEqual(resumed.calls, [ROOT + '&group_slug=A'])

    def test_three_transport_failures_block_instead_of_retrying_forever(self):
        class TimeoutProbe(MemoryProbe):
            def get(self, url, indicator):
                self.requests += 1
                raise requests.Timeout('Synthetic timeout')
        with tempfile.TemporaryDirectory() as tmp, Queue(Path(tmp) / 'q.sqlite', ROOT, 'example') as q:
            p = TimeoutProbe(fixture())
            for now in (100, 130, 190):
                with patch('uka_json_queue.time.time', return_value=now):
                    r = q.run(p)
            self.assertEqual(r['states'], {'error': 1})
            self.assertEqual(r['errors'][0]['error_kind'], 'transient_exhausted')
            self.assertEqual(r['errors'][0]['attempts'], 3)
            with patch('uka_json_queue.time.time', return_value=9999):
                q.run(p)
            self.assertEqual(p.requests, 3)

    def test_data_conflicts_are_never_reopened_automatically(self):
        data = fixture(); data[ROOT + '&group_slug=A']['yearly_totals']['totals'][0]['value'] = 99
        with tempfile.TemporaryDirectory() as tmp, Queue(Path(tmp) / 'q.sqlite', ROOT, 'example') as q:
            q.run(MemoryProbe(data))
            self.assertEqual(q.db.execute("SELECT error_kind FROM nodes WHERE status='error'").fetchone()[0], 'permanent')
            later = MemoryProbe(fixture())
            with patch('uka_json_queue.time.time', return_value=9999):
                r = q.run(later)
            self.assertNotIn(ROOT + '&group_slug=A', later.calls)
            self.assertEqual(later.requests, 0)
            self.assertEqual(r['stop_reason'], 'blocked_source_error')
            self.assertFalse(r['graph_closed'])

    def test_resume_mid_graph_skips_done_nodes_and_matches_uninterrupted(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / 'queue.sqlite'; p = MemoryProbe(fixture())
            with Queue(db, ROOT, 'example') as q:
                self.assertEqual(q.run(p, max_nodes=1)['states'], {'done': 1, 'pending': 2})
            p2 = MemoryProbe(fixture())
            with Queue(db, ROOT, 'example') as q:
                r = q.run(p2)
                self.assertTrue(r['graph_closed']); self.assertEqual(r['observations'], 4)
                saved = [tuple(row) for row in q.db.execute('SELECT dimensions,value FROM nodes ORDER BY dimensions')]
                self.assertEqual(q.run(p2)['processed_this_run'], 0)
            self.assertNotIn(ROOT, p2.calls)
            self.assertEqual(p2.requests, 3)
            with Queue(Path(tmp) / 'fresh.sqlite', ROOT, 'example') as q:
                q.run(MemoryProbe(fixture()))
                self.assertEqual(saved, [tuple(row) for row in q.db.execute('SELECT dimensions,value FROM nodes ORDER BY dimensions')])

    def test_request_budget_preserves_pending_node(self):
        with tempfile.TemporaryDirectory() as tmp, Queue(Path(tmp) / 'q.sqlite', ROOT, 'example') as q:
            r = q.run(MemoryProbe(fixture(), budget=0))
            self.assertEqual(r['stop_reason'], 'request_budget')
            self.assertEqual(r['states'], {'pending': 1})
            self.assertFalse(r['publish_allowed'])

    def test_failed_checkpoint_rolls_back_children_and_edges(self):
        data = fixture(); data[ROOT]['groups'].append(copy.deepcopy(data[ROOT]['groups'][0]))
        data[ROOT]['groups'][-1]['totals'][0]['url'] = ROOT + '&group_slug=conflict'
        with tempfile.TemporaryDirectory() as tmp, Queue(Path(tmp) / 'q.sqlite', ROOT, 'example') as q:
            r = q.run(MemoryProbe(data))
            self.assertEqual(r['states'], {'error': 1})
            self.assertEqual(q.db.execute('SELECT count(*) FROM edges').fetchone()[0], 0)

    def test_value_mismatch_preserves_validated_parent_and_blocks_closure(self):
        data = fixture(); data[ROOT + '&group_slug=A']['yearly_totals']['totals'][0]['value'] = 99
        with tempfile.TemporaryDirectory() as tmp, Queue(Path(tmp) / 'q.sqlite', ROOT, 'example') as q:
            r = q.run(MemoryProbe(data))
            self.assertEqual(r['states']['done'], 1)
            self.assertEqual(r['states']['error'], 1)
            self.assertFalse(r['graph_closed'])

    def test_snapshot_mismatch_and_concurrent_writer_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            db = Path(tmp) / 'q.sqlite'
            with Queue(db, ROOT, 'example'):
                with self.assertRaisesRegex(ValueError, 'Another worker'):
                    Queue(db, ROOT, 'example')
            with self.assertRaisesRegex(ValueError, 'snapshot mismatch'):
                Queue(db, ROOT, 'different')

    def test_missing_value_is_not_treated_as_source_null(self):
        data = fixture(); del data[ROOT]['yearly_totals']['totals'][0]['value']
        with tempfile.TemporaryDirectory() as tmp, Queue(Path(tmp) / 'q.sqlite', ROOT, 'example') as q:
            r = q.run(MemoryProbe(data))
            self.assertEqual(r['states'], {'error': 1})
            self.assertFalse(r['graph_closed'])

    def test_missing_groups_allowed_only_at_verified_terminal_scope(self):
        with tempfile.TemporaryDirectory() as tmp, Queue(Path(tmp) / 'q.sqlite', ROOT, 'example') as q:
            dims = {k: 'Exempel' for k in ('Ämnesområde', 'Ämnesdelområde', 'Ämnesgrupp', 'Studieform')}
            with q.db:
                q.db.execute('UPDATE nodes SET dimensions=?', (json.dumps(dims, sort_keys=True),))
            data = fixture(); del data[ROOT]['groups']
            self.assertTrue(q.run(MemoryProbe(data))['graph_closed'])

    def test_missing_groups_at_root_is_still_an_error(self):
        data = fixture(); del data[ROOT]['groups']
        with tempfile.TemporaryDirectory() as tmp, Queue(Path(tmp) / 'q.sqlite', ROOT, 'example') as q:
            self.assertEqual(q.run(MemoryProbe(data))['states'], {'error': 1})


if __name__ == '__main__':
    unittest.main()
