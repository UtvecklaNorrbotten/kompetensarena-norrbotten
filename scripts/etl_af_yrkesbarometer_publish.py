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
import urllib.parse
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
                  {"Content-Type": "application/json", "User-Agent": "Kompetensarena-ETL/1.0", "Authorization": "Bearer " + secret},
                  method="POST")
            with urllib.request.urlopen(req, timeout=120) as response:
                return json.load(response)
        except urllib.error.HTTPError as e:
            if not safe or attempt == 4 or e.code not in (429, 502, 503, 504):
                raise RuntimeError(f"Import-API {path} svarade HTTP {e.code}") from None
        except (urllib.error.URLError, TimeoutError):
            if not safe or attempt == 4:
                raise RuntimeError("Import-API kunde inte nås") from None
        time.sleep(min(45, 3 * (2 ** attempt)))


def source_head():
    """Cheap check against current file; falls back to full check if unreliable."""
    url = BASE + "yrkesbarometer.json"
    request = urllib.request.Request(url, method="HEAD", headers={
        "User-Agent": "Kompetensarena-ETL/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            headers = response.headers
            return {
                "etag": headers.get("ETag") or "",
                "last_modified": headers.get("Last-Modified") or "",
                "content_length": headers.get("Content-Length") or "",
            }
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError):
        return None


def head_is_unchanged(previous, current):
    """Only trust HEAD if a version-bearing header exists on both sides."""
    if not isinstance(previous, dict) or not isinstance(current, dict):
        return False
    version_keys = ("etag", "last_modified")
    if not any(previous.get(k) and current.get(k) for k in version_keys):
        return False
    return previous == current


def state_get():
    base = os.environ.get("ETL_BASE_URL", "").rstrip("/")
    secret = os.environ.get("ETL_PUBLISH_KEY", "")
    if not base or not secret:
        raise ValueError("Missing ETL_BASE_URL or ETL_PUBLISH_KEY")
    url = base + "/api/public/jobs/source-state?" + urllib.parse.urlencode(
        {"source_id": "af-yrkesbarometer"})
    req = urllib.request.Request(url, headers={
        "User-Agent": "Kompetensarena-ETL/1.0",
        "Authorization": "Bearer " + secret,
        "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as response:
        return json.load(response).get("state") or {}


def record_source_status(status, period, fingerprints, rows, message=None):
    body = {"source_id": "af-yrkesbarometer", "status": status,
            "latest_available_period": period,
            "details": {"file_sha256": fingerprints, "rows": rows,
                        "schema": "yb-full-v2", "editions": sorted(EDITION_KEYS),
                        "current_head": CURRENT_HEAD}}
    if status == "succeeded":
        body["latest_successful_period"] = period
    if message:
        body["error_message"] = message[:500]
    return post("source-state", body, safe=False)


def should_publish(state, fingerprints):
    details = state.get("details") or {}
    return (state.get("last_status") != "succeeded"
            or details.get("file_sha256") != fingerprints)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=("validate", "publish", "check"), default="validate")
    p.add_argument("--report", default="artifacts/af-yrkesbarometer-import-report.json")
    args = p.parse_args()
    global CURRENT_HEAD
    CURRENT_HEAD = source_head() if args.mode == "check" else None
    state = state_get() if args.mode == "check" else {}
    # HEAD avoids downloading every historical file on ordinary check days.
    if args.mode == "check" and state.get("last_status") == "succeeded" and head_is_unchanged(
            (state.get("details") or {}).get("current_head"), CURRENT_HEAD):
        print("Unchanged source HTTP metadata: no download or database write", flush=True)
        report = {"mode": args.mode, "status": "no_change", "method": "head"}
        output = pathlib.Path(args.report)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(canonical(report) + "\n", encoding="utf-8")
        return
    entries = []
    for relative, edition in SOURCES:
        body, _, _ = fetch(BASE + relative)
        entries.append((pathlib.Path(relative).name, edition, body))
    # When a newer current edition arrives, fetch earlier 2026+ editions
    # from the historical archive before building the replacement snapshot.
    provisional, _ = prepare(entries)
    latest_current = max(provisional)
    latest_year = int(latest_current[:4])
    for year in range(2026, latest_year + 1):
        for half in (1, 2):
            edition = f"{year}-{half}"
            if edition >= latest_current:
                continue
            relative = f"historiska/yrkesbarometer_{edition}.json"
            body, _, _ = fetch(BASE + relative)
            entries.append((pathlib.Path(relative).name, edition, body))
    grouped, fingerprints = prepare(entries)
    report = {"mode": args.mode, "file_sha256": fingerprints,
              "editions": {k: {"rows": len(v), "norrbotten": sum(r["geo_code"] == "25" for r in v)}
                           for k, v in grouped.items()}}
    print(canonical(report), flush=True)
    global EDITION_KEYS
    EDITION_KEYS = list(grouped)
    latest = max(grouped)
    total_rows = sum(len(x) for x in grouped.values())
    if args.mode == "check":
        previous_editions = set((state.get("details") or {}).get("editions") or [])
        missing_editions = previous_editions - set(grouped)
        if missing_editions:
            raise ValueError("Previously published editions missing: " +
                             ", ".join(sorted(missing_editions)))
        if not should_publish(state, fingerprints):
            print("Inga ändringar sedan senaste lyckade publicering", flush=True)
            report["status"] = "no_change"
            output = pathlib.Path(args.report)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(canonical(report) + "\n", encoding="utf-8")
            return
        print("Ny eller ändrad källdata: full snapshot behövs", flush=True)
    if args.mode in ("publish", "check"):
        # A full snapshot supports the initial load as well as future new
        # editions. replace_period cannot add previously unseen editions.
        observations = [row for period in grouped for row in grouped[period]]
        total_chunks = math.ceil(len(observations) / CHUNK_ROWS)
        spec = {"schema": "yb-full-v2", "fingerprints": fingerprints,
                "chunk_size": CHUNK_ROWS, "indicator": INDICATOR}
        import_key = hashlib.sha256(canonical(spec).encode("utf-8")).hexdigest()
        print(f"Full snapshot: {len(observations)} rows, {total_chunks} chunks", flush=True)
        batch_id = None
        try:
            batch = post("etl-batch/start", {
                "indicator_id": INDICATOR, "source": "AF Yrkesbarometern",
                "mode": "full", "import_key": import_key,
                "expected_rows": len(observations), "expected_chunks": total_chunks,
            }, safe=False)
            batch_id = batch["batch_id"]
            for index in range(total_chunks):
                post("etl-batch/chunk", {
                    "batch_id": batch_id, "indicator_id": INDICATOR,
                    "chunk_index": index,
                    "observations": observations[index * CHUNK_ROWS:(index + 1) * CHUNK_ROWS],
                })
                if (index + 1) % 10 == 0 or index + 1 == total_chunks:
                    print(f"Staged {index + 1}/{total_chunks} chunks", flush=True)
            post("etl-batch/finalize", {"batch_id": batch_id}, safe=False)
            batch_id = None
            report["published"] = list(grouped)
            record_source_status("succeeded", latest, fingerprints, total_rows)
            report["status"] = "succeeded"
        except Exception as error:
            report["error"] = str(error)
            try:
                record_source_status("failed", latest, fingerprints, total_rows, str(error))
            except Exception:
                print("Could not record source failure", flush=True)
            if batch_id:
                try:
                    post("etl-batch/abort", {"batch_id": batch_id,
                         "reason": "Yrkesbarometer full snapshot failed"})
                except Exception:
                    print("Warning: failed batch could not be aborted", flush=True)
            raise
        finally:
            output = pathlib.Path(args.report)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(canonical(report) + "\n", encoding="utf-8")
    output = pathlib.Path(args.report)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(canonical(report) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
