#!/usr/bin/env python3
"""Import AF Yrkesbarometern editions via existing authenticated period-batch API.

Each edition is a separate period. Existing editions are kept when a new
current file supersedes an earlier one. All original row fields are retained
as canonical JSON in dimensions (not converted into false numeric measures).
"""
import argparse
import collections
import datetime
import hashlib
import json
import math
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from etl_af_yrkesbarometer_archive import BASE, SOURCES, fetch

INDICATOR = "af-yrkesbarometern"
CHUNK_ROWS = 400
COUNTIES = set("01 03 04 05 06 07 08 09 10 12 13 14 17 18 19 20 21 22 23 24 25".split())


def canonical(x):
    return json.dumps(x, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def unwrap(obj):
    if isinstance(obj, list):
        return obj
    if isinstance(obj, dict):
        candidates = [v for v in obj.values() if isinstance(v, list) and v and isinstance(v[0], dict)]
        if len(candidates) == 1:
            return candidates[0]
    raise ValueError("Källans JSON-struktur kan inte entydigt tolkas")


def normalize_region(value):
    s = str(value).strip()
    if s in COUNTIES or s == "00":
        return s
    if s.lower() in ("riket", "hela riket", "sverige"):
        return "00"
    raise ValueError("Okänd länskod: " + repr(s))


def edition_period(row, fallback):
    # Always prefer the source's publication edition; the current filename
    # is not itself a durable period identity.
    raw = row.get("omgang")
    if raw is None or str(raw).strip() == "":
        if fallback == "current":
            raise ValueError("Aktuell källa saknar 'omgang'; importen stoppas")
        return fallback
    s = str(raw).strip()
    if not (2 <= len(s) <= 20):
        raise ValueError("Ogiltig publiceringsomgång")
    return s


def prepare(entries):
    grouped = collections.defaultdict(list)
    fingerprints = {}
    for filename, fallback, content in entries:
        rows = unwrap(json.loads(content))
        if not rows or not all(isinstance(row, dict) for row in rows):
            raise ValueError("Tom eller inkonsekvent källfil: " + filename)
        for i, row in enumerate(rows):
            for key in ("lan", "omgang", "yb_concept_id", "jobbmojligheter", "rekryteringssituation", "prognos"):
                if key not in row:
                    raise ValueError(f"Fältet {key!r} saknas i {filename}")
            period = edition_period(row, fallback)
            geo = normalize_region(row["lan"])
            original = canonical(row)
            # The complete source row is losslessly preserved; JSON objects
            # or arrays need string encoding for the existing dimensions API.
            dims = {
                "edition": period,
                "yb_concept_id": str(row["yb_concept_id"]),
                "row_json": original,
                "source_file": filename,
                "row_index": i,
            }
            observation = {"geo_code": geo, "period": period,
                           "value": None, "dimensions": dims}
            grouped[period].append(observation)
        fingerprints[filename] = hashlib.sha256(content).hexdigest()
    for period, rows in grouped.items():
        regions = {x["geo_code"] for x in rows}
        if "25" not in regions or "00" not in regions:
            raise ValueError("Norrbotten eller Riket saknas för period " + period)
        rows.sort(key=lambda x: (x["geo_code"], x["dimensions"]["yb_concept_id"],
                                 x["dimensions"]["source_file"], x["dimensions"]["row_index"]))
        # Source editions are expected to be distinct. Detect unexpected
        # duplicate occupation/geography IDs rather than silently aggregate.
        ids = [(r["geo_code"], r["dimensions"]["yb_concept_id"]) for r in rows]
        if len(ids) != len(set(ids)):
            raise ValueError("Dubbla yrkes-/länbedömningar inom omgång " + period)
    return dict(sorted(grouped.items())), fingerprints


def post(path, payload, safe=True):
    base = os.environ.get("ETL_BASE_URL", "").rstrip("/")
    secret = os.environ.get("ETL_PUBLISH_KEY", "")
    if not base or not secret:
        raise ValueError("ETL_BASE_URL och ETL_PUBLISH_KEY krävs vid publicering")
    body = canonical(payload).encode("utf-8")
    for attempt in range(5 if safe else 1):
        try:
            req = urllib.request.Request(base + "/api/public/jobs/" + path, body,
                  {"Content-Type": "application/json", "Authorization": "Bearer " + secret},
                  method="POST")
            with urllib.request.urlopen(req, timeout=120) as response:
                return json.load(response)
        except urllib.error.HTTPError as e:
            if not safe or attempt == 4 or e.code not in (429, 502, 503, 504):
                raise RuntimeError(f"Import-API svarade HTTP {e.code}") from None
        except (urllib.error.URLError, TimeoutError):
            if not safe or attempt == 4:
                raise RuntimeError("Import-API kunde inte nås") from None
        time.sleep(min(45, 3 * (2 ** attempt)))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=("validate", "publish"), default="validate")
    p.add_argument("--report", default="artifacts/af-yrkesbarometer-import-report.json")
    args = p.parse_args()
    entries = []
    for relative, edition in SOURCES:
        body, _, _ = fetch(BASE + relative)
        entries.append((pathlib.Path(relative).name, edition, body))
    grouped, fingerprints = prepare(entries)
    report = {"mode": args.mode, "file_sha256": fingerprints,
              "editions": {k: {"rows": len(v), "norrbotten": sum(r["geo_code"] == "25" for r in v)}
                           for k, v in grouped.items()}}
    print(canonical(report), flush=True)
    if args.mode == "publish":
        for period, rows in grouped.items():
            nchunks = math.ceil(len(rows) / CHUNK_ROWS)
            batch = post("etl-batch/start", {
                "indicator_id": INDICATOR, "source": "AF Yrkesbarometern",
                "mode": "replace_period", "replace_period": period,
                "expected_rows": len(rows), "expected_chunks": nchunks,
            }, safe=False)
            batch_id = batch["batch_id"]
            for index in range(nchunks):
                post("etl-batch/chunk", {
                    "batch_id": batch_id, "indicator_id": INDICATOR,
                    "chunk_index": index,
                    "observations": rows[index * CHUNK_ROWS:(index + 1) * CHUNK_ROWS],
                })
            post("etl-batch/finalize", {"batch_id": batch_id})
            print("Publicerad:", period, len(rows), flush=True)
        report["published"] = list(grouped)
    output = pathlib.Path(args.report)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(canonical(report) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
