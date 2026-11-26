import copy
import gzip
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from mucf.source import parse_value, parse_table, soup, queries
from mucf.collect import complete_year, write_json, read_json

FIXTURE = Path(__file__).parent / 'fixtures/mucf/crossed.html'


class Values(unittest.TestCase):
    def test_suppression_is_not_zero(self):
        for token in ['.', '..', '...', '…', '***', ' * * * ']:
            self.assertEqual(parse_value(token)[:2], [None, 'suppressed'])
            self.assertEqual(parse_value(token, percent=True)[2], token)
        self.assertEqual(parse_value('0'), [0, 'observed', '0'])
        self.assertEqual(parse_value('0,0 %', percent=True)[0], 0)
        self.assertEqual(parse_value('')[:2], [None, 'missing'])

    def test_swedish_numbers_and_invalid_values(self):
        self.assertEqual(parse_value('67\u00a0303')[0], 67303)
        self.assertEqual(parse_value('6,2 %', percent=True)[0], 6.2)
        for raw, percent in [('1,2', False), ('-1', False), ('NaN', False),
                             ('101 %', True), ('6,2', True), ('saknas', False)]:
            with self.assertRaises(ValueError):
                parse_value(raw, percent)

    def test_real_source_crossing(self):
        page = soup(FIXTURE.read_text())
        rows = parse_table(page, '2024', '25', 'Norrbottens Län', 'Master', 'Alla', True, True)
        self.assertEqual(len(rows), 12)
        self.assertEqual(rows[0][:6], ['25', '16-24', 'Kvinnor', 'Inrikesfödd', 'Master', 368])
        self.assertEqual(rows[0][8], 3.8)
        # Source totals stay exactly as published; no recomputation of parts.
        self.assertEqual(rows[2][5], 708)

    def test_wrong_year_geo_category_and_profiles_fail_closed(self):
        page = soup(FIXTURE.read_text())
        for args in [('2023', '25', 'Norrbottens Län', 'Master', 'Alla', True, True),
                     ('2024', '2580', 'Luleå', 'Master', 'Alla', True, True),
                     ('2024', '25', 'Norrbottens Län', 'Stat', 'Statliga arbetsmarknadsåtgärder', True, True),
                     ('2024', '25', 'Norrbottens Län', 'Master', 'Alla', False, False)]:
            with self.assertRaises(ValueError):
                parse_table(page, *args)

    def test_missing_and_duplicate_rows_fail(self):
        for duplicate in [False, True]:
            page = soup(FIXTURE.read_text())
            row = page.select('tbody tr')[0]
            if duplicate:
                page.select_one('tbody').append(copy.copy(row))
            else:
                row.decompose()
            with self.assertRaises(ValueError):
                parse_table(page, '2024', '25', 'Norrbottens Län', 'Master', 'Alla', True, True)

    def test_plan_keeps_official_totals_and_excludes_invalid_crossings(self):
        geos = [{'code': '25', 'categories': {'Master': 'Alla', 'Stat': 'Statliga åtgärder'}}]
        plan = list(queries(geos))
        self.assertEqual(len(plan), 6)
        self.assertTrue(all(not origin for _, _, cat, _, _, origin in plan if cat != 'Master'))
        self.assertEqual(len({q[0] for q in plan}), 6)

    def test_incomplete_year_never_activates(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            plan = [{'code': '25', 'categories': {'Master': 'Alla'}}]
            with self.assertRaises(ValueError):
                complete_year(root, '2024', plan, {}, 'cycle')
            self.assertFalse((root / 'snapshots/2024.json.gz').exists())

    def test_checkpoint_round_trip_and_deterministic_compression(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'test.json.gz'
            original = {'rows': [[None, '***', 0, 3.8]]}
            write_json(p, original)
            before = p.read_bytes()
            write_json(p, original)
            self.assertEqual(before, p.read_bytes())
            self.assertEqual(read_json(p), original)


if __name__ == '__main__':
    unittest.main()

class Publication(unittest.TestCase):
    def snapshot(self):
        from mucf.collect import NOTES
        import hashlib
        from mucf.collect import encode
        rows = parse_table(soup(FIXTURE.read_text()), '2024', '25', 'Norrbottens Län', 'Master', 'Alla', True, True)
        snapshot = {'schema': 1, 'year': '2024', 'geographies': [{'code': '25', 'categories': {'Master': 'Alla'}}],
                    'rows': rows, 'notes': NOTES}
        snapshot['data_sha256'] = hashlib.sha256(encode([snapshot['geographies'], rows, NOTES])).hexdigest()
        return snapshot

    def test_publication_keeps_source_null_and_denominator(self):
        from mucf.publish import observations
        snapshot = self.snapshot()
        snapshot['rows'][0][5:8] = [None, 'suppressed', '***']
        rows = list(observations(snapshot, 'count'))
        self.assertIsNone(rows[0]['value'])
        self.assertEqual(rows[0]['dimensions']['source_value'], '***')
        self.assertEqual(rows[0]['dimensions']['denominator'], 'befolkning')
        snapshot['rows'][0][4] = 'Okänd'
        snapshot['geographies'][0]['categories']['Okänd'] = 'Okänd aktivitet'
        self.assertEqual(list(observations(snapshot, 'share'))[0]['dimensions']['denominator'], 'uvas')

    def test_tampered_snapshot_rejected(self):
        from mucf.publish import verified_snapshot
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / '2024.json.gz'
            s = self.snapshot()
            write_json(p, s)
            self.assertEqual(verified_snapshot(p, '2024')['year'], '2024')
            s['rows'][0][5] = 99999
            write_json(p, s)
            with self.assertRaises(ValueError):
                verified_snapshot(p, '2024')

    def test_failed_upload_aborts_and_does_not_mark_published(self):
        from mucf.publish import publish
        class FailingClient:
            def __init__(self):
                self.calls = []
            def etl(self, path, body=None, **kwargs):
                self.calls.append(path)
                if path == 'etl-batch/start':
                    return {'batch_id': 'batch'}
                if path == 'etl-batch/chunk':
                    raise RuntimeError('upload failed')
                return {}
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            s = self.snapshot()
            write_json(root / 'snapshots/2024.json.gz', s)
            write_json(root / 'catalog.json', {'snapshots': {'2024': s['data_sha256']}})
            write_json(root / 'state.json', {'years': ['2024'], 'complete': True})
            client = FailingClient()
            with self.assertRaises(RuntimeError):
                publish(root, client)
            self.assertIn('etl-batch/abort', client.calls)
            self.assertNotIn('etl-batch/finalize', client.calls)
            self.assertFalse((root / 'published.json').exists())

class GeographyHeadings(unittest.TestCase):
    def test_real_overkalix_heading_and_suppression(self):
        import unicodedata
        page = soup((FIXTURE.parent / 'overkalix-crossed.html').read_text())
        for label in ['Överkalix', unicodedata.normalize('NFD', 'Överkalix')]:
            rows = parse_table(page, '2024', '2513', label, 'Master', 'Alla', True, True)
            self.assertEqual(len(rows), 12)
            self.assertEqual(rows[1][5:8], [None, 'suppressed', '***'])
        for label in ['Övertorneå', 'Overkalix', 'Överkalix kommun']:
            with self.assertRaises(ValueError):
                parse_table(page, '2024', '2513', label, 'Master', 'Alla', True, True)
        with self.assertRaises(ValueError):
            parse_table(page, '2023', '2513', 'Överkalix', 'Master', 'Alla', True, True)
        with self.assertRaises(ValueError):
            parse_table(page, '2024', '2513', 'Överkalix', 'Okänd', 'Okänd aktivitet', True, True)

class InitialPublication(Publication):
    def test_first_publication_creates_base_then_replaces_periods(self):
        self.check_modes(False, ['full', 'full', 'replace_period', 'replace_period'])

    def test_missing_local_checkpoint_does_not_replace_remote_history(self):
        self.check_modes(True, ['replace_period'] * 4)

    def check_modes(self, existing, expected):
        from mucf.publish import publish
        from mucf.collect import encode
        import hashlib
        class Client:
            def __init__(self): self.starts = []
            def etl(self, path, body=None, **kwargs):
                if path.startswith('etl-state?'):
                    return {'last_successful_at': '2026-11-26T00:00:00Z' if existing else None}
                if path == 'etl-batch/start':
                    self.starts.append(body)
                    return {'batch_id': 'batch'}
                return {}
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            s = self.snapshot()
            hashes = {}
            for year in ['2024', '2023']:
                s['year'] = year
                hashes[year] = s['data_sha256']
                write_json(root / f'snapshots/{year}.json.gz', s)
            write_json(root / 'catalog.json', {'snapshots': hashes})
            write_json(root / 'state.json', {'years': list(hashes), 'complete': True})
            client = Client()
            publish(root, client)
            self.assertEqual([s['mode'] for s in client.starts], expected)
            for body in client.starts:
                self.assertEqual('replace_period' in body, body['mode'] == 'replace_period')
