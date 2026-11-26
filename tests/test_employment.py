"""Source snapshots plus synthetic validation of sparse/status JSON-stat."""

import base64
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "employment", ROOT / "scripts/fetch_employment.py"
)
etl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(etl)


class EmploymentTests(unittest.TestCase):
    def test_sparse_status(self):
        # Synthetic example with deliberately reordered dimensions and sparse data.
        d = {
            "id": ["Tid", "Region"],
            "size": [2, 1],
            "dimension": {
                "Tid": {"category": {"index": {"2021": 1, "2020": 0}}},
                "Region": {"category": {"index": ["25"]}},
            },
            "value": {"0": 0},
            "status": {"1": "c"},
        }
        rows = list(etl.decode(d, {"Region": ["25"], "Tid": ["2020", "2021"]}))
        self.assertEqual(rows[0][1], 0)
        self.assertIsNone(rows[1][1])
        self.assertEqual(rows[1][2], "c")
        d["size"] = [1, 1]
        with self.assertRaises(ValueError):
            list(etl.decode(d, {"Region": ["25"], "Tid": ["2020", "2021"]}))

    def test_bulk_symbols_and_labels(self):
        # Synthetic example: SCB's CSV labels use hyphens and retain symbols.
        meta = {
            "dimension": {
                "Region": {
                    "label": "region",
                    "category": {"label": {"25": "Norrbottens län"}},
                },
                "Alder": {
                    "label": "ålder",
                    "category": {"label": {"15-74": "15–74 år"}},
                },
                "Tid": {
                    "label": "månad",
                    "category": {"label": {"2020M01": "2020M01", "2020M02": "2020M02"}},
                },
            }
        }
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / "test.zip"
            with zipfile.ZipFile(archive, "w") as z:
                z.writestr(
                    "test.csv",
                    "region,ålder,månad,värde\n25 Norrbottens län,15-74 år,2020M01,0\n25 Norrbottens län,15-74 år,2020M02,..\n".encode(
                        "cp1252"
                    ),
                )
            rows = list(
                etl.bulk_cells(
                    meta,
                    {
                        "Region": ["25"],
                        "Alder": ["15-74"],
                        "Tid": ["2020M01", "2020M02"],
                    },
                    archive,
                )
            )
            self.assertEqual(rows[0][1], 0)
            self.assertIsNone(rows[1][1])
            self.assertEqual(rows[1][2], "..")

    def test_snapshot(self):
        catalog = json.loads((ROOT / "src/data/employment/catalog.json").read_bytes())
        self.assertEqual(len(catalog["geographies"]), 312)
        self.assertEqual(set(catalog["datasets"]), set(etl.SPECS))
        for name, info in catalog["datasets"].items():
            self.assertEqual(len(info["selection"]["Region"]), 312)
            self.assertEqual(info["periods"], sorted(info["periods"]))
            if name.startswith("rams-old"):
                self.assertEqual(info["periods"][0], "2011")
                self.assertEqual(info["periods"][-1], "2018")
            if name.startswith("rams-new"):
                self.assertEqual(info["periods"], ["2019", "2020", "2021"])
            for geo in ["00", "25", "2580"]:
                entry = catalog["files"][f"{name}/geo-{geo}.json"]
                content = (ROOT / "public/data/employment" / entry["path"]).read_bytes()
                self.assertEqual(hashlib.sha256(content).hexdigest(), entry["sha256"])
                rows = json.loads(
                    gzip.decompress(base64.b64decode(json.loads(content)["gzip"]))
                )
                self.assertTrue(rows)
                self.assertEqual(len(rows), len({tuple(r[:4]) for r in rows}))
                self.assertEqual(set(r[0] for r in rows), set(info["periods"]))
                if (
                    name == "industry-month"
                    and geo == "00"
                    and info["updated"] == "2026-10-27T07:00:00Z"
                ):
                    r = next(
                        r
                        for r in rows
                        if r[:4] == ["2026M08", "1+2", "bostad", "A-U+US"]
                    )
                    # Independent SCB key figure on BAS's product page, checked 2026-11-26.
                    self.assertEqual(r[4], 5467704)
            if info["rate"]:
                self.assertGreater(info["rate_checks"], 0)

    def test_all_files(self):
        c = json.loads((ROOT / "src/data/employment/catalog.json").read_bytes())
        for logical, entry in c["files"].items():
            content = (ROOT / "public/data/employment" / entry["path"]).read_bytes()
            self.assertEqual(
                hashlib.sha256(content).hexdigest(), entry["sha256"], logical
            )


if __name__ == "__main__":
    unittest.main()
