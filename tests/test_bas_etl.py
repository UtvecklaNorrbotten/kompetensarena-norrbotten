"""Synthetic examples: schedule boundaries, JSON-stat axes and publication."""
import copy
from datetime import date
import importlib.util
import itertools
from pathlib import Path
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("bas", Path(__file__).parents[1] / "scripts/etl_scb_bas.py")
bas = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bas)
VERSION = "2026-09-29T06:00:00Z"
SELECTED = {"Region": ["00", "2580"], "Kon": ["1+2"], "SNI2007": ["F", "G"],
            "Fodelseregion": ["tot"], "ContentsCode": ["0000054D", "0000056A"]}


def fixture(selected=None, period="2026M07"):
    selected = selected or SELECTED
    dimensions = {**selected, "Tid": [period]}
    # Deliberately different dimension order from the request.
    order = list(reversed(dimensions))
    return {"id": order, "size": [len(dimensions[x]) for x in order], "updated": VERSION,
            "dimension": {x: {"category": {"index": {v: i for i, v in enumerate(dimensions[x])},
                                            "label": {v: "Exempel " + v for v in dimensions[x]}}}
                          for x in order},
            "value": list(range(len(list(itertools.product(*(dimensions[x] for x in order))))))}


class FakeClient:
    def __init__(self, state=None, fail_finalize=False, version_change=False, resume=None):
        self.state = state
        self.calls = []
        self.fail_finalize = fail_finalize
        self.version_change = version_change
        self.resume = resume

    def scb_metadata(self, table):
        data = fixture()
        if self.version_change:
            data["updated"] = "2026-09-30T06:00:00Z"
        return data

    def scb_data(self, table, selected, period):
        self.calls.append(("scb-data", period))
        return fixture(selected, period)

    def etl(self, path, body=None, **kwargs):
        self.calls.append((path, body))
        if path.startswith("source-state?"):
            return {"state": copy.deepcopy(self.state)}
        if path.startswith("etl-batch/resume-history?"):
            return self.resume
        if path == "etl-batch/start":
            return {"batch_id": "example-batch"}
        if path == "etl-batch/finalize" and self.fail_finalize:
            raise RuntimeError("Exempel: finalisering misslyckades")
        return {}


class ScheduleTests(unittest.TestCase):
    def test_window_opens_on_22_and_continues_across_year(self):
        self.assertEqual(bas.expected_period(date(2026, 10, 21)), "2026M07")
        self.assertEqual(bas.expected_period(date(2026, 10, 22)), "2026M08")
        self.assertEqual(bas.expected_period(date(2026, 11, 1)), "2026M08")
        self.assertEqual(bas.expected_period(date(2027, 1, 1)), "2026M10")

    def test_success_stops_checks_until_next_window(self):
        state = {"last_successful_at": VERSION, "last_status": "succeeded",
                 "latest_successful_period": "2026M07"}
        self.assertFalse(bas.should_check(date(2026, 10, 21), state))
        self.assertTrue(bas.should_check(date(2026, 10, 22), state))
        state["latest_successful_period"] = "2026M08"
        self.assertFalse(bas.should_check(date(2026, 11, 1), state))

    def test_failure_and_quarterly_pause_continue_outside_window(self):
        state = {"last_successful_at": VERSION, "last_status": "failed",
                 "latest_successful_period": "2026M07"}
        self.assertTrue(bas.should_check(date(2026, 10, 10), state))
        state.update(last_status="succeeded", details={"revision_pending": True})
        self.assertTrue(bas.should_check(date(2026, 10, 10), state))
        self.assertTrue(bas.should_check(date(2026, 10, 10), None))


class NormalizationTests(unittest.TestCase):
    def test_axis_order_preserves_geography_gender_and_perspective(self):
        data = fixture()
        rows = bas.normalize(data, SELECTED, bas.TARGETS["industry"], "2026M07", VERSION)
        self.assertEqual(len(rows), 8)
        expected = {(r["geo_code"], r["dimensions"]["sni2007_code"],
                     r["dimensions"]["geografiskt_perspektiv_code"]): r["value"] for r in rows}
        self.assertEqual(expected[("00", "F", "arbetsstalle")], 0)
        self.assertEqual(expected[("2580", "G", "bostad")], 7)
        self.assertTrue(all(r["dimensions"]["kon_code"] == "1+2" for r in rows))

    def test_missing_value_is_null_and_status_preserved(self):
        data = fixture()
        data["value"] = {"0": 0}
        data["status"] = {"1": ".."}
        rows = bas.normalize(data, SELECTED, bas.TARGETS["industry"], "2026M07", VERSION)
        self.assertEqual(sum(r["value"] is None for r in rows), 7)
        self.assertEqual(sum(r["dimensions"].get("scb_status") == ".." for r in rows), 1)

    def test_incomplete_invalid_and_changed_versions_rejected(self):
        data = fixture()
        data["value"].pop()
        with self.assertRaises(ValueError):
            bas.normalize(data, SELECTED, bas.TARGETS["industry"], "2026M07", VERSION)
        data = fixture()
        data["value"][0] = -1
        with self.assertRaises(ValueError):
            bas.normalize(data, SELECTED, bas.TARGETS["industry"], "2026M07", VERSION)
        with self.assertRaises(ValueError):
            bas.normalize(fixture(), SELECTED, bas.TARGETS["industry"], "2026M07", "other-version")

    def test_metadata_validates_levels_and_exact_scope(self):
        regions = ["00", *bas.COUNTIES, *(f"{i:04d}" for i in range(1000, 1290))]
        selected = {**SELECTED, "Region": regions, "Kon": ["1", "2", "1+2"]}
        meta = fixture(selected, "2020M01")
        actual, periods = bas.selection(meta, bas.TARGETS["industry"])
        self.assertEqual(len(actual["Region"]), 312)
        self.assertEqual(actual["Fodelseregion"], ["tot"])
        self.assertEqual(periods, ["2020M01"])
        del meta["dimension"]["Region"]["category"]["index"]["25"]
        with self.assertRaises(ValueError):
            bas.selection(meta, bas.TARGETS["industry"])


class PublicationTests(unittest.TestCase):
    @patch.object(bas, "CHUNK_ROWS", 2)
    def test_full_snapshot_resumes_and_replays_partial_month(self):
        client = FakeClient(resume={"id": "resumed", "next_chunk_index": 5,
                                   "expected_chunks": 8, "expected_rows": 16})
        bas.publish(client, bas.TARGETS["industry"], fixture(), SELECTED,
                    ["2026M06", "2026M07"], True, time.monotonic() + 30)
        data_calls = [body for path, body in client.calls if path == "scb-data"]
        self.assertEqual(data_calls, ["2026M07"])
        chunks = [body["chunk_index"] for path, body in client.calls if path == "etl-batch/chunk"]
        self.assertEqual(chunks, [4, 5, 6, 7])
        self.assertEqual(client.calls[-1][0], "etl-batch/finalize")

    def test_failure_aborts_staging_and_never_marks_source_success(self):
        client = FakeClient(fail_finalize=True)
        report = {}
        with patch.object(bas, "selection", return_value=(SELECTED, ["2026M07"])):
            with self.assertRaises(RuntimeError):
                bas.run_target(client, "industry", "full", False, date(2026, 10, 9),
                               time.monotonic() + 30, report)
        statuses = [body["status"] for path, body in client.calls if path == "source-state"]
        self.assertEqual(statuses, ["ready", "failed"])
        self.assertTrue(any(path == "etl-batch/abort" for path, _ in client.calls))
        failure = [body for path, body in client.calls if path == "source-state"][-1]
        self.assertTrue(failure["details"]["revision_pending"])

    def test_incremental_only_fetches_unpublished_months(self):
        state = {"last_successful_at": VERSION, "last_status": "succeeded",
                 "latest_successful_period": "2026M06", "details": {}}
        client = FakeClient(state=state)
        report = {}
        with patch.object(bas, "selection", return_value=(SELECTED, ["2026M06", "2026M07"])):
            bas.run_target(client, "industry", "check", True, date(2026, 9, 29),
                           time.monotonic() + 30, report)
        self.assertEqual([body for path, body in client.calls if path == "scb-data"], ["2026M07"])
        starts = [body for path, body in client.calls if path == "etl-batch/start"]
        self.assertEqual(starts[0]["mode"], "replace_period")
        success = [body for path, body in client.calls if path == "source-state"][-1]
        self.assertEqual(success["latest_successful_period"], "2026M07")
        finalize_index = next(i for i, (path, _) in enumerate(client.calls) if path == "etl-batch/finalize")
        self.assertGreater(len(client.calls) - 1, finalize_index)

    def test_unchanged_release_keeps_waiting_no_data_download(self):
        state = {"last_successful_at": VERSION, "last_status": "succeeded",
                 "latest_successful_period": "2026M07", "details": {}}
        client = FakeClient(state=state)
        report = {}
        with patch.object(bas, "selection", return_value=(SELECTED, ["2026M07"])):
            bas.run_target(client, "industry", "check", True, date(2026, 10, 22),
                           time.monotonic() + 30, report)
        self.assertEqual(report["industry"]["status"], "waiting")
        self.assertFalse(any(path == "scb-data" for path, _ in client.calls))

    def test_version_change_stops_finalization(self):
        client = FakeClient(version_change=True)
        with self.assertRaises(ValueError):
            bas.publish(client, bas.TARGETS["industry"], fixture(), SELECTED,
                        ["2026M07"], True, time.monotonic() + 30)
        self.assertFalse(any(path == "etl-batch/finalize" for path, _ in client.calls))


if __name__ == "__main__":
    unittest.main()
