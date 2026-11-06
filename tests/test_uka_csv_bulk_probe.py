"""Synthetic HST CSV examples: observation identity, totals and scope."""
from pathlib import Path
import sys
import unittest
import tempfile
from unittest.mock import Mock
sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
from uka_csv_bulk_probe import observations, compare
from uka_source_audit import Source

META = {'universities': [{'label': 'Riket', 'value': 'uni:1'},
                        {'label': 'Exempellärosäte', 'value': 'uni:32'}],
        'ages': [{'label': '-24'}, {'label': '25-34'}, {'label': '35-'}, {'label': 'Total'}]}


def row(value='12,30'):
    return {'Tidsperiod': '2025/26', 'Lärosäte': '', 'Studieform': '',
            'Ämnesområde[0]': '', 'Ämnesdelområde[1]': '', 'Ämnesgrupp[2]': '',
            'Kön': 'Total', 'Åldersgrupp': 'Total', 'Värde': value}


class BulkCSVTests(unittest.TestCase):
    def test_native_total_value_is_preserved(self):
        actual = observations([row()], META, '2025/26', ['1'])
        self.assertEqual(list(actual.values()), ['12.3'])
        self.assertIn('"Total", "Total", {}', next(iter(actual)))

    def test_duplicate_key_with_different_value_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate CSV observation'):
            observations([row(), row('99,90')], META, '2025/26', ['1'])

    def test_reused_label_is_distinguished_by_full_parent_path(self):
        a = row(); a.update({'Ämnesområde[0]': 'Exempel A', 'Ämnesdelområde[1]': 'Övrigt'})
        b = row(); b.update({'Ämnesområde[0]': 'Exempel B', 'Ämnesdelområde[1]': 'Övrigt'})
        self.assertEqual(len(observations([a,b], META, '2025/26', ['1'])), 2)

    def test_wrong_scope_and_unconfirmed_empty_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'unrequested'):
            observations([row()], META, '2024/25', ['1'])
        with self.assertRaisesRegex(ValueError, 'unrequested'):
            observations([row()], META, '2025/26', ['32'])
        with self.assertRaisesRegex(ValueError, 'positive reference'):
            observations([], META, '2025/26', ['1'])

    def test_same_count_with_changed_value_is_not_an_exact_match(self):
        a = observations([row()], META, '2025/26', ['1'])
        b = observations([row('12,40')], META, '2025/26', ['1'])
        r = compare(a,b)
        self.assertFalse(r['exact']); self.assertEqual(len(r['different_values']), 1)

    def test_subject_child_under_wrong_parent_is_rejected(self):
        raw = row(); raw.update({'Ämnesområde[0]': 'Exempel A', 'Ämnesdelområde[1]': 'Övrigt', 'Ämnesgrupp[2]': 'Exempel M'})
        paths = [{'dimensions': {'Ämnesområde': 'Exempel B', 'Ämnesdelområde': 'Övrigt', 'Ämnesgrupp': 'Exempel M'}}]
        with self.assertRaisesRegex(ValueError, 'hierarchy'):
            observations([raw], META, '2025/26', ['1'], paths)

    def test_offline_budget_prevents_any_source_request(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Source(tmp, 'example'); source.export_budget = 0
            source.session.post = Mock()
            with self.assertRaisesRegex(RuntimeError, 'budget exhausted'):
                source.export(33, ['from:2025/26'], 'example')
            source.session.post.assert_not_called()
            self.assertEqual(source.network_exports, 0)
