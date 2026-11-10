import copy
import hashlib
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import uka_snapshot_publish_verified as snap  # noqa: E402

PILOT = ROOT / "docs/data/uka-snapshot-2026-11-10-all-pilot-13.json"


class FakeRpc:
    """In-memory stand-in for the server functions; records every call."""

    def __init__(self, frozen_entry, *, source_ok=True, received=(), planned=15,
                 bound=None, published=False, readback=None):
        self.calls = []
        self.entry = frozen_entry
        self.source_ok = source_ok
        self.received = list(received)
        self.planned = planned
        self._bound = bound
        self.published = published
        self.readback = readback if readback is not None else copy.deepcopy(frozen_entry["periods"])
        self.active = "src-batch"

    def active_batch(self, indicator):
        return self.active

    def bound(self, key):
        return self._bound

    def __call__(self, name, body, timeout=300, retries=5):
        self.calls.append((name, body))
        if name == "uka_snapshot_verify_batch":
            return {"ok": self.source_ok, "batch_id": body["p_batch_id"]}
        if name == "uka_snapshot_start":
            if self._bound and self._bound["manifest"] != body["p_manifest"]:
                raise RuntimeError("HTTP 400: bound to another manifest")
            self._bound = self._bound or {"manifest": body["p_manifest"], "published_at": None}
            return {"planned_chunks": self.planned, "resumed": bool(self.received)}
        if name == "uka_snapshot_status":
            return {"batch_id": "new-batch", "received_indices": sorted(self.received),
                    "received_rows": self.entry["rows"] if len(self.received) == self.planned else 0,
                    "previous_batch_id": "src-batch",
                    "published_at": "2026-11-10T12:00:00Z" if self.published else None}
        if name in ("uka_snapshot_copy_chunk", "uka_snapshot_chunk"):
            dup = body["p_index"] in self.received
            if not dup:
                self.received.append(body["p_index"])
            return {"duplicate": dup, "index": body["p_index"]}
        if name == "uka_snapshot_finalize":
            self.published = True
            self.active = "new-batch"
            return {"status": "succeeded"}
        if name == "uka_snapshot_period_hashes":
            return self.readback
        raise AssertionError(name)

    def names(self):
        return [n for n, _ in self.calls]


class SnapshotPublishTest(unittest.TestCase):
    def setUp(self):
        self.frozen, self.entry = snap.load_frozen(PILOT, 13)
        self.key = snap.import_key(self.frozen, 13)

    def run_copy(self, rpc):
        return snap.run(rpc, self.frozen, self.entry, mode="copy", key=self.key,
                        basis=snap.DEFAULT_BASIS, logp=None)

    def test_canonical_line_matches_postgres_jsonb_text(self):
        # Reference rendered by PostgreSQL: jsonb_build_array(...)::text
        line = snap.canonical_line("HT2017", "Luleå tekniska universitet", "Män",
                                   {"amnesomrade": "Teknik", "aldersgrupp": "-24", "sni": "Å/ä"}, 12.5)
        self.assertEqual(line, '["HT2017", "Luleå tekniska universitet", "Män", '
                               '{"sni": "Å/ä", "aldersgrupp": "-24", "amnesomrade": "Teknik"}, "12.5"]')

    def test_period_hash_matches_postgres(self):
        # Reference: sha256(string_agg(line, E'\n' ORDER BY line COLLATE "C")) in PostgreSQL
        lines = [snap.canonical_line("VT2017", "Riket", "Total", {}, 5),
                 snap.canonical_line("VT2017", "Ängelholm", "Kvinnor", {"aldersgrupp": "35-"}, 0.25),
                 snap.canonical_line("VT2017", "Abc", "Män", {}, None)]
        self.assertEqual(snap.period_hashes(lines)[0]["sha256"],
                         "a5b3bcc6046bae3994764de152ae33cd67769e2888af55fa55ca50204ef88907")

    def test_value_text_fixed_decimal(self):
        self.assertEqual([snap.value_text(v) for v in (5.0, 1.5, 100, 0.25, 1e-7, 123456.789, "2.50")],
                         ["5", "1.5", "100", "0.25", "0.0000001", "123456.789", "2.5"])

    def test_pilot_manifest_loads(self):
        self.assertEqual(self.entry["rows"], 73268)
        self.assertEqual(len(self.entry["periods"]), 20)
        self.assertEqual(len(self.entry["coverage"]), 240)
        self.assertEqual(self.key, "uka-13-snapshot-2026-11-10-all-1be12b057d06")

    def test_wrong_indicator_refused(self):
        with self.assertRaises(snap.ManifestMismatch):
            snap.load_frozen(PILOT, 31)

    def test_source_mismatch_stops_before_any_write(self):
        rpc = FakeRpc(self.entry, source_ok=False)
        with self.assertRaises(snap.ManifestMismatch):
            self.run_copy(rpc)
        self.assertEqual(rpc.names(), ["uka_snapshot_verify_batch"])

    def test_resume_copies_only_missing_sparse_chunks(self):
        rpc = FakeRpc(self.entry, received=[0, 2, 14], planned=15)
        summary = self.run_copy(rpc)
        copied = [b["p_index"] for n, b in rpc.calls if n == "uka_snapshot_copy_chunk"]
        self.assertEqual(copied, [1] + list(range(3, 14)))
        self.assertEqual(rpc.names().count("uka_snapshot_finalize"), 1)
        self.assertTrue(summary["active"])
        self.assertEqual(summary["readback_mismatches"], [])
        self.assertEqual(summary["previous_batch_retained"], "src-batch")

    def test_bound_manifest_with_other_content_refused(self):
        other = snap.build_manifest(self.frozen, self.entry, mode="copy", basis=snap.DEFAULT_BASIS,
                                    source_batch_id="src-batch")
        other["periods"][3] = {**other["periods"][3], "sha256": "0" * 64}
        rpc = FakeRpc(self.entry, bound={"manifest": other, "published_at": None})
        with self.assertRaises(snap.ManifestMismatch):
            self.run_copy(rpc)
        self.assertEqual(rpc.names(), [])

    def test_already_published_is_idempotent(self):
        bound = snap.build_manifest(self.frozen, self.entry, mode="copy", basis=snap.DEFAULT_BASIS,
                                    source_batch_id="src-batch")
        rpc = FakeRpc(self.entry, bound={"manifest": bound, "published_at": "x"},
                      received=range(15), published=True)
        rpc.active = "new-batch"
        summary = self.run_copy(rpc)
        self.assertNotIn("uka_snapshot_copy_chunk", rpc.names())
        self.assertNotIn("uka_snapshot_finalize", rpc.names())
        self.assertTrue(summary["active"])

    def test_changed_value_in_readback_detected(self):
        bad = copy.deepcopy(self.entry["periods"])
        bad[5]["sha256"] = hashlib.sha256(b"changed").hexdigest()
        rpc = FakeRpc(self.entry, readback=bad)
        with self.assertRaises(snap.ManifestMismatch):
            self.run_copy(rpc)

    def test_upload_chunks_bound_by_hash(self):
        lines = [snap.canonical_line("HT2026", f"U{i:05d}", "Total", {}, i) for i in range(12001)]
        chunks, payloads = snap.upload_chunks(list(reversed(lines)))
        self.assertEqual([c["rows"] for c in chunks], [5000, 5000, 2001])
        for c, p in zip(chunks, payloads):
            self.assertEqual(c["sha256"], hashlib.sha256(p.encode()).hexdigest())
            self.assertFalse(p.endswith("\n"))
        # Concatenated chunks reproduce the period fingerprint (single period here).
        joined = hashlib.sha256("\n".join(payloads).encode()).hexdigest()
        self.assertEqual(joined, snap.period_hashes(lines)[0]["sha256"])


if __name__ == "__main__":
    unittest.main()
