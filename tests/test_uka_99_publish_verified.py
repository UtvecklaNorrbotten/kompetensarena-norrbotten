"""Synthetic checks for the indicator 99 verified publication mapping."""
import hashlib
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))
import uka_99_publish_verified as pub

META = {
    "metadata_hash": "m",
    "snapshot": "2026-11-10",
    "universities": [
        {"value": "uni:1", "label": "Riket"},
        {"value": "uni:23", "label": "Luleå tekniska universitet"},
    ],
}


def staging(directory: Path, rows: list[dict], coverage=None, name="99-full.sqlite") -> Path:
    path = directory / name
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.execute("create table meta(binding text)")
    db.execute("create table years(period text primary key, summary text)")
    db.execute("create table observations(key text primary key, period text, payload text, source_hash text)")
    db.execute("insert into meta values (?)", [json.dumps({
        "indicator": 99, "policy": pub.POLICY, "genders": pub.GENDERS, "ages": ["Total"],
        "metadata_hash": "m", "periods": ["HT2026"]})])
    if coverage is None:
        counts = {}
        for r in rows:
            counts[r["gender"]] = counts.get(r["gender"], 0) + 1
        coverage = [{"gender": g, "observations": n} for g, n in counts.items()]
    db.execute("insert into years values ('HT2026', ?)", [json.dumps({"coverage": coverage})])
    for i, r in enumerate(rows):
        payload = {"indicator": 99, "period": "HT2026", "age": "Total", **r}
        db.execute("insert into observations values (?, 'HT2026', ?, 'h')", [str(i), json.dumps(payload)])
    db.commit()
    db.close()
    return path


def row(university="1", gender="Total", program=None, value="2.3", **extra):
    dims = {} if program is None else {"Program": program}
    return {"university": university, "gender": gender, "dimensions": dims, "value": value, **extra}


class PublishMappingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def test_maps_codes_riket_program_total_and_keeps_exact_value_text(self):
        rows, _ = pub.normalize(staging(self.tmp, [
            row(), row("23", "Kvinnor", "Läkarexamen", "0"), row("23", "Män", "Läkarexamen", "12.75")]), META)
        self.assertEqual(rows[0], {"period": "HT2026", "university": "Riket", "gender": "Total",
                                   "dimensions": {}, "value": "2.3"})
        self.assertEqual(rows[1]["university"], "Luleå tekniska universitet")
        self.assertEqual(rows[1]["dimensions"], {"program": "Läkarexamen"})
        self.assertEqual([r["value"] for r in rows], ["2.3", "0", "12.75"])

    def test_rejects_age_breakdown_unknown_gender_marker_and_extra_dimension(self):
        for bad in [row(age="-24"), row(gender="Okänt"), row(value=".."), row(value="2,3"),
                    {**row(), "dimensions": {"Program": "X", "Ålder": "-24"}},
                    row(program="Total")]:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                pub.normalize(staging(Path(tempfile.mkdtemp()), [bad]), META)

    def test_rejects_unknown_code_and_name_collision(self):
        with self.assertRaisesRegex(ValueError, "Okänd lärosäteskod"):
            pub.normalize(staging(self.tmp, [row(), row("99")]), META)
        collision = {**META, "universities": META["universities"] + [{"value": "uni:5", "label": "Riket"}]}
        with self.assertRaisesRegex(ValueError, "samma namn"):
            pub.normalize(staging(Path(tempfile.mkdtemp()), [row()]), collision)

    def test_rejects_duplicates_and_coverage_mismatch(self):
        with self.assertRaisesRegex(ValueError, "Dubblett"):
            pub.normalize(staging(self.tmp, [row(), row()]), META)
        with self.assertRaisesRegex(ValueError, "Radantal per termin"):
            pub.normalize(staging(Path(tempfile.mkdtemp()), [row()],
                                  coverage=[{"gender": "Total", "observations": 2}]), META)

    def test_requires_riket_and_never_reads_reference(self):
        with self.assertRaisesRegex(ValueError, "Riket saknas"):
            pub.normalize(staging(self.tmp, [row("23")]), META)
        ref = staging(self.tmp, [row()], name="reference-99/99.sqlite")
        with self.assertRaisesRegex(ValueError, "reference-99"):
            pub.normalize(ref, META)

    def test_manifest_chunks_hash_exact_payloads(self):
        rows, info = pub.normalize(staging(self.tmp, [row(), row("23", "Kvinnor", "A", "1.25")]), META)
        manifest, payloads = pub.build_manifest(rows, info, "a" * 64, "b" * 64, "2026-11-10",
                                                {"full_source_coverage_verified": False}, "basis")
        self.assertEqual(manifest["rows"], 2)
        self.assertEqual(sum(c["rows"] for c in manifest["chunks"]), 2)
        self.assertEqual(manifest["universities"][0], "Riket")
        self.assertIn({}, manifest["dimensions"])
        self.assertEqual(manifest["chunks"][0]["sha256"],
                         hashlib.sha256(payloads[0].encode("utf-8")).hexdigest())
        self.assertIn('"1.25"', payloads[0])
        self.assertFalse(manifest["review"]["full_source_coverage_verified"])


if __name__ == "__main__":
    unittest.main()
