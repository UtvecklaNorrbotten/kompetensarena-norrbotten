"""Synthetic source hierarchies and observations for fail-closed coverage audit."""
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
from uka_hst_coverage import audit, source_paths


class CoverageTests(unittest.TestCase):
    def test_reused_code_keeps_children_under_their_active_parent(self):
        options = [{'value': 'dynamic:' + token, 'label': label} for token, label in
                   [('A_', 'Exempel A'), ('X_A', 'Övrigt'), ('L_X', 'Exempel L'),
                    ('B_', 'Exempel B'), ('X_B', 'Övrigt'), ('M_X', 'Exempel M')]]
        paths = source_paths(options)
        self.assertEqual(paths[2]['codes'], ['A', 'X', 'L'])
        self.assertEqual(paths[5]['codes'], ['B', 'X', 'M'])
        self.assertNotEqual(paths[2]['dimensions'], paths[5]['dimensions'])

    def test_unknown_active_parent_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'active parent'):
            source_paths([{'value': 'dynamic:L_UNKNOWN', 'label': 'Exempel'}])

    def test_duplicate_label_paths_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'uniquely'):
            source_paths([{'value': 'dynamic:A_', 'label': 'Exempel'},
                          {'value': 'dynamic:B_', 'label': 'Exempel'}])

    def test_closed_graph_does_not_prove_full_coverage_or_permit_publication(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'q.sqlite'; db = sqlite3.connect(p)
            db.executescript('CREATE TABLE meta(binding TEXT); CREATE TABLE nodes(status TEXT, dimensions TEXT, observations TEXT);')
            db.execute('INSERT INTO meta VALUES (?)', (json.dumps({'example': True}),))
            observation = {'university': 'EXAMPLE', 'dimensions': {}}
            db.execute('INSERT INTO nodes VALUES (?,?,?)', ('done', '{}', json.dumps([observation, observation])))
            db.commit(); db.close()
            r = audit(p, {'paths': [{'dimensions': {'Ämnesområde': 'Exempel'}}]})
            self.assertTrue(r['graph_closed'])
            self.assertFalse(r['full_source_coverage_verified'])
            self.assertFalse(r['publish_allowed'])
            self.assertEqual(r['duplicates'], 1)
            self.assertEqual(len(r['unobserved_subject_paths']), 1)

    def test_child_from_other_branch_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'q.sqlite'; db = sqlite3.connect(p)
            db.executescript('CREATE TABLE meta(binding TEXT); CREATE TABLE nodes(status TEXT, dimensions TEXT, observations TEXT);')
            db.execute('INSERT INTO meta VALUES (?)', ('{}',))
            dimensions = {'Ämnesområde': 'Exempel A', 'Ämnesdelområde': 'Övrigt', 'Ämnesgrupp': 'Exempel M'}
            db.execute('INSERT INTO nodes VALUES (?,?,?)', ('done', json.dumps(dimensions), '[]'))
            db.commit(); db.close()
            correct = {**dimensions, 'Ämnesområde': 'Exempel B'}
            r = audit(p, {'paths': [{'dimensions': correct}]})
            self.assertEqual(r['invalid_source_subject_paths'], [dimensions])
