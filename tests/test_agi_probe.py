"""Synthetic examples exercising failure modes; no source data fixtures."""
import importlib.util
import datetime as dt
import pathlib
import unittest
from urllib.parse import parse_qs, urlparse

spec = importlib.util.spec_from_file_location('probe', pathlib.Path(__file__).parents[1] / 'scripts/probe_skatteverket_agi.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def example_row(i):
    return dict(period='202608', uppdateringsdatum='2026-10-03', gruppering='Kommun',
                statistikterm='Lönesumma', antal='10', belopp='123',
                grupperingsvärde=str(i), inkomstar='2026', ar_manad='Månad')


class ProbeTests(unittest.TestCase):
    def test_fetches_every_page(self):
        def get(url):
            offset = int(parse_qs(urlparse(url).query)['_offset'][0])
            return dict(resultCount=501, offset=offset,
                        results=[example_row(i) for i in range(offset, min(offset + 500, 501))])
        self.assertEqual(len(probe.fetch_rows({'gruppering': 'Kommun'}, get)), 501)

    def test_changed_count_fails(self):
        def get(url):
            offset = int(parse_qs(urlparse(url).query)['_offset'][0])
            return dict(resultCount=501 if offset == 0 else 502, offset=offset,
                        results=[example_row(i) for i in range(offset, min(offset + 500, 501))])
        with self.assertRaises(ValueError):
            probe.fetch_rows({}, get)

    def test_wrong_filter_and_duplicate_fail(self):
        with self.assertRaises(ValueError):
            probe.fetch_rows({'gruppering': 'Län'}, lambda _: dict(resultCount=1, offset=0, results=[example_row(1)]))
        with self.assertRaises(ValueError):
            probe.fetch_rows({}, lambda _: dict(resultCount=2, offset=0, results=[example_row(1), example_row(1)]))

    def test_empty_page_is_not_success(self):
        with self.assertRaises(ValueError):
            probe.fetch_rows({}, lambda _: dict(resultCount=1, offset=0, results=[]))

    def test_latest_month_is_not_automatically_mature(self):
        self.assertEqual(probe.period_status('202609', '2026-10-03')['status'], 'immature')
        self.assertEqual(probe.period_status('202610', '2026-10-03')['status'], 'immature')
        self.assertEqual(probe.period_status('202608', '2026-10-03')['status'], 'candidate_not_verified_complete')
        self.assertEqual(probe.default_period(dt.date(2026, 1, 9)), '202511')


if __name__ == '__main__':
    unittest.main()
