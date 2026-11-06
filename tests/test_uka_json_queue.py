"""Synthetic crash/resume and transaction integrity examples."""
import copy
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
from uka_json_queue import Queue

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


if __name__ == '__main__':
    unittest.main()
