import hashlib
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import uka_hst_publish_verified as hst  # noqa: E402

PERIODS = ["2025/26", "2024/25", "2023/24", "2022/23", "2021/22",
           "2020/21", "2019/20", "2018/19", "2017/18", "2016/17"]
META = {"metadata_hash": "m", "snapshot": "2026-11-09",
        "universities": [{"value": "uni:1", "label": "Riket"},
                         {"value": "uni:32", "label": "Luleå tekniska universitet"}]}


def make_staging(path: Path, rows):
    db = sqlite3.connect(path)
    db.execute("create table meta(binding text)")
    db.execute("create table years(period text primary key, summary text)")
    db.execute("create table observations(key text primary key, period text, payload text, source_hash text)")
    db.execute("insert into meta values (?)", [json.dumps({
        "indicator": 33, "policy": hst.POLICY, "genders": hst.GENDERS, "ages": hst.AGES,
        "metadata_hash": "m", "periods": PERIODS})])
    for i, p in enumerate(rows):
        db.execute("insert into observations values (?,?,?,?)",
                   [f"{i:04d}", p["period"], json.dumps(p, ensure_ascii=False), "x"])
    db.commit()
    db.close()


def obs(period, uni, gender, age, value, **dims):
    return {"indicator": 33, "period": period, "university": uni, "gender": gender,
            "age": age, "dimensions": dims, "value": value}


class HstPublishTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp()) / "hst-collection"
        self.tmp.mkdir()
        rows = [obs(p, "1", "Total", "Total", "341246.6") for p in PERIODS]
        rows.append(obs("2025/26", "32", "Kvinnor", "-24", "12.30",
                        Ämnesområde="Teknik", Ämnesdelområde="Datateknik", Studieform="Fristående kurser"))
        make_staging(self.tmp / "hst-full.sqlite", rows)

    def build(self):
        rows, periods = hst.normalize(self.tmp / "hst-full.sqlite", META)
        return rows, hst.build_manifest(rows, periods, "a" * 64, "2026-11-09")

    def test_normalization_keeps_path_age_gender_and_exact_decimals(self):
        rows, _ = self.build()
        ltu = [r for r in rows if r["university"] != "Riket"][0]
        self.assertEqual(ltu["dimensions"], {"amnesomrade": "Teknik", "amnesdelomrade": "Datateknik",
                                             "studieform": "Fristående kurser", "aldersgrupp": "-24"})
        self.assertEqual(ltu["gender"], "Kvinnor")
        self.assertEqual(ltu["value"], "12.30")
        riket = [r for r in rows if r["university"] == "Riket"][0]
        self.assertEqual(riket["dimensions"], {})

    def test_identical_manifest_passes_and_any_chunk_change_is_mismatch(self):
        _, (manifest, payloads) = self.build()
        hst.compare_manifest(manifest, json.loads(json.dumps(manifest)))
        server = json.loads(json.dumps(manifest))
        server["chunks"][0]["sha256"] = hashlib.sha256(b"other").hexdigest()
        with self.assertRaises(hst.ManifestMismatch):
            hst.compare_manifest(manifest, server)
        server = json.loads(json.dumps(manifest))
        server["dimensions"] = list(reversed(server["dimensions"]))
        with self.assertRaises(hst.ManifestMismatch):
            hst.compare_manifest(manifest, server)

    def test_changed_value_changes_chunk_hash(self):
        _, (manifest, _) = self.build()
        rows, periods = hst.normalize(self.tmp / "hst-full.sqlite", META)
        rows[-1]["value"] = "12.3"
        other, _ = hst.build_manifest(rows, periods, "a" * 64, "2026-11-09")
        with self.assertRaises(hst.ManifestMismatch):
            hst.compare_manifest(other, manifest)

    def test_resume_sends_only_really_missing_noncontiguous_chunks(self):
        received = list(range(154)) + [155]
        self.assertEqual(hst.missing_chunks({"received_indices": received}, 231),
                         [154] + list(range(156, 231)))
        self.assertEqual(hst.missing_chunks({"received_indices": list(range(231))}, 231), [])
        with self.assertRaises(ValueError):
            hst.missing_chunks({"received_indices": [231]}, 231)

    def test_publish_resume_skips_received_and_refuses_new_import(self):
        _, (manifest, _) = self.build()
        payloads = ["p0", "p1", "p2"]
        stored = {0, 2}
        calls = []

        def rpc(name, body, timeout=300):
            calls.append((name, body.get("p_index")))
            if name == "uka_verified_start":
                return {"resumed": True}
            if name == "uka_verified_chunk":
                stored.add(body["p_index"])
                return {"ok": True}
            if name == "uka_verified_status":
                return {"received_chunks": len(stored), "received_indices": sorted(stored),
                        "received_rows": manifest["rows"], "status": "ready"}
            return {"ok": True}

        hst.publish(rpc, manifest, payloads, "k", None)
        self.assertEqual([c[1] for c in calls if c[0] == "uka_verified_chunk"], [1])
        self.assertEqual(calls[-1][0], "uka_verified_finalize")

        def fresh(name, body, timeout=300):
            return {"resumed": False}
        with self.assertRaises(RuntimeError):
            hst.publish(fresh, manifest, payloads, "k", None)

    def test_refuses_reference_material_and_bad_values(self):
        with self.assertRaises(ValueError):
            hst.normalize(Path("/x/legacy-reference/hst-full.sqlite"), META)
        bad = Path(tempfile.mkdtemp()) / "hst-full.sqlite"
        make_staging(bad, [obs(p, "1", "Total", "Total", "..") for p in PERIODS])
        with self.assertRaises(ValueError):
            hst.normalize(bad, META)

    def test_jsonb_text_orders_keys_like_postgres(self):
        self.assertEqual(hst.jsonb_text({"bb": 1, "a": [1, "ä"], "c": {}}),
                         '{"a": [1, "ä"], "c": {}, "bb": 1}')


if __name__ == "__main__":
    unittest.main()
