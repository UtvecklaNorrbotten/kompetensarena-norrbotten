"""Read-only UKÄ source staging and observation audit. No publication credentials.

This deliberately cannot publish. A source response is not evidence of completeness:
only a comparison against an independent selection can certify a partition plan.
"""
from __future__ import annotations

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import csv
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import hashlib
import io
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlparse

import requests
from bs4 import BeautifulSoup

INDICATORS = (13, 31, 33, 97, 99, 108, 136, 77, 134, 135)
BASE = "https://statistik-www.uka.se/export"
VERSION = 1
REQUIRED = {"Tidsperiod", "Lärosäte", "Kön", "Åldersgrupp", "Värde"}


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(",", ":")).encode()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


def options(html, prefix):
    soup = BeautifulSoup(html, "html.parser")
    result = []
    for element in soup.select("[value]"):
        value = element["value"]
        if not value.startswith(prefix):
            continue
        label = element.get("name")
        if label is None:
            label_element = element.find_next("label")
            label = label_element.get_text(" ", strip=True) if label_element else element.get_text(" ", strip=True)
        result.append({"value": value, "label": label})
    if len({o["value"] for o in result}) != len(result):
        raise ValueError("Duplicate source filter tokens")
    return result


def groups(html):
    result = []
    for group in BeautifulSoup(html, "html.parser").select(".groupTitles"):
        marker = group.select_one(".dynamic-filter-index")
        if marker is None:
            raise ValueError("Dynamic group without index")
        values = options(str(group), "dynamic:")
        # The final underscore separates node ID and *immediate* parent ID.
        # Token string length is NOT the depth of this hierarchy.
        parents = {}
        for option in values:
            token = option["value"].removeprefix("dynamic:")
            if token == "TOTAL":
                continue
            node, parent = token.split("_", 1)
            parents[node] = parent or None
        depths = {}
        def depth(node, trail=()):
            if node in trail:
                raise ValueError("Cyclic source hierarchy")
            parent = parents[node]
            if parent is not None and parent not in parents:
                raise ValueError("Unknown hierarchy parent: " + parent)
            return 0 if parent is None else 1 + depth(parent, trail + (node,))
        for node in parents:
            depths[node] = depth(node)
        result.append({"index": marker.get_text(strip=True), "values": values,
                       "parents": parents, "depths": depths})
    return result


def parse_csv(raw):
    if not raw:
        return {"status": "technical_empty_body", "rows": []}
    try:
        text = raw.decode("utf-8-sig", errors="strict")
        reader = csv.DictReader(io.StringIO(text), delimiter=";")
        headers = reader.fieldnames or []
        if len(headers) != len(set(headers)) or not REQUIRED.issubset(headers):
            raise ValueError("Missing/duplicate required CSV columns")
        rows = []
        for row in reader:
            if None in row or any(v is None for v in row.values()):
                raise ValueError("Ragged or truncated CSV record")
            row["Tidsperiod"] = re.sub(r'^="(.*)"$', r'\1', row["Tidsperiod"])
            rows.append(row)
        return {"status": "data" if rows else "empty_selection_unconfirmed", "rows": rows,
                "headers": headers}
    except (UnicodeError, ValueError, csv.Error) as error:
        return {"status": "invalid_csv", "error": str(error), "rows": []}


def canonical_value(value):
    value = value.strip()
    try:
        decimal = Decimal(value.replace("\u00a0", "").replace(" ", "").replace(",", "."))
        if not decimal.is_finite():
            raise ValueError("Non-finite source value")
        return str(decimal.normalize())
    except InvalidOperation:
        # Preserve missing/suppression markers rather than turning them into zero.
        if value not in ("", "..", ".", "-", "…"):
            raise ValueError("Unknown source value marker: " + value)
        return value


def observations(rows):
    result = {}
    for row in rows:
        key = tuple(sorted((re.sub(r"\[[012]\]$", "", column), value)
                           for column, value in row.items() if column != "Värde"))
        if key in result:
            raise ValueError("Duplicate observation key (even if values agree)")
        result[key] = canonical_value(row["Värde"])
    return result


def compare(reference, candidate):
    a, b = observations(reference), observations(candidate)
    missing, extra = a.keys() - b.keys(), b.keys() - a.keys()
    changed = [k for k in a.keys() & b.keys() if a[k] != b[k]]
    return {"exact": not (missing or extra or changed), "reference_rows": len(a),
            "candidate_rows": len(b), "missing": len(missing), "extra": len(extra),
            "changed": len(changed),
            "examples": {"missing": list(missing)[:3], "extra": list(extra)[:3],
                         "changed": [{"key": k, "reference": a[k], "candidate": b[k]} for k in changed[:3]]}}


def validate_selection(rows, period, university, gender, ages):
    """Reject ignored/misapplied filters even if two exports agree with each other."""
    observations(rows)
    for row in rows:
        if row["Tidsperiod"] != period.removeprefix("from:"):
            raise ValueError("Source returned an unrequested period")
        name = row["Lärosäte"] or "Riket"
        if name != university:
            raise ValueError("Source returned an unrequested university: " + name)
        if row["Kön"] != gender.removeprefix("gender:"):
            raise ValueError("Source returned an unrequested gender")
        if row["Åldersgrupp"] not in ages:
            raise ValueError("Source returned an unrequested age")


class Source:
    def __init__(self, root, snapshot):
        self.root = Path(root)
        self.snapshot = snapshot
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": "Kompetensarena-UKA-ReadOnly-Audit/1.0",
                                     "X-Requested-With": "XMLHttpRequest"})
        self.network_exports = 0

    def json_total(self, indicator, university, period):
        """Independent API total; never derive it by summing groups or genders."""
        response = self.session.get(f"https://statistik-api.uka.se/api/totals/{indicator}/",
                                    params={"university": university.removeprefix("uni:"),
                                            "year": period.removeprefix("from:")}, timeout=60)
        response.raise_for_status()
        body = response.json()
        write_json(self.root / "controls" / f"{indicator}-{digest([university, period])}.json", body)
        values = [v["value"] for v in body.get("yearly_totals", {}).get("totals", [])
                  if v.get("year") == period.removeprefix("from:")]
        if len(values) != 1:
            raise ValueError("Independent API does not confirm the requested source total")
        return canonical_value(str(values[0]))

    def metadata(self, indicator):
        path = self.root / "metadata" / f"{indicator}.json"
        if path.exists():
            saved = json.loads(path.read_text())
            if saved.get("snapshot") == self.snapshot and saved.get("version") == VERSION:
                return saved
        endpoints = {"periods": "academic_term.php?direction=from", "universities": "university.php",
                     "genders": "gender.php", "ages": "age.php", "groups": "group.php"}
        def fetch(item):
            name, endpoint = item
            # Independent reads, separate session per worker.
            response = requests.get(BASE + "/filters/" + endpoint,
                                    params={"indicator": json.dumps([str(indicator)])}, timeout=60)
            response.raise_for_status()
            if not response.content and name != "groups":
                raise ValueError("Empty mandatory filter: " + name)
            return name, response.text
        with ThreadPoolExecutor(max_workers=3) as pool:
            html = dict(pool.map(fetch, endpoints.items()))
        result = {"indicator": indicator, "version": VERSION, "snapshot": self.snapshot,
                  "groups": groups(html["groups"])}
        for name, prefix in (("periods", "from:"), ("universities", "uni:"),
                             ("genders", "gender:"), ("ages", "age:")):
            result[name] = options(html[name], prefix)
            if not result[name]:
                raise ValueError("No " + name)
        periods = result["periods"]
        result["retained_periods"] = periods[:20 if periods[0]["value"][5:7] in ("HT", "VT") else 10]
        result["metadata_hash"] = digest(result)
        write_json(path, result)
        return result

    def export(self, indicator, filters, meta_hash):
        spec = {"version": VERSION, "snapshot": self.snapshot, "indicator": indicator,
                "filters": filters, "metadata_hash": meta_hash}
        key = digest(spec)
        path = self.root / "selections" / (key + ".json")
        raw_path = path.with_suffix(".csv")
        if path.exists() and raw_path.exists():
            cached = json.loads(path.read_text())
            raw = raw_path.read_bytes()
            if cached.get("spec") == spec and cached.get("sha256") == hashlib.sha256(raw).hexdigest():
                parsed = parse_csv(raw)
                if parsed["status"] == "data":
                    return {**cached, **parsed, "cached": True}
        self.network_exports += 1
        evidence = {"spec": spec, "key": key, "cached": False}
        try:
            response = self.session.post(BASE + "/api/index.php",
                                         data=[("indicator", str(indicator))] + [("filters[]", v) for v in filters],
                                         timeout=90)
            evidence["export_http"] = response.status_code
            response.raise_for_status()
            url = response.json().get("fileUrl")
            if not url or urlparse(url).hostname != "statistik-www.uka.se" or urlparse(url).scheme != "https":
                raise ValueError("Missing or unexpected source file URL")
            response = self.session.get(url, timeout=90)
            evidence.update(file_url=url, download_http=response.status_code, bytes=len(response.content))
            response.raise_for_status()
            raw = response.content
            evidence["sha256"] = hashlib.sha256(raw).hexdigest()
            parsed = parse_csv(raw)
            evidence.update({k: v for k, v in parsed.items() if k != "rows"})
            evidence["row_count"] = len(parsed["rows"])
            raw_path.parent.mkdir(parents=True, exist_ok=True)
            temporary = raw_path.with_suffix(".tmp")
            temporary.write_bytes(raw)
            temporary.replace(raw_path)
            write_json(path, evidence)
            return {**evidence, **parsed}
        except (requests.RequestException, ValueError, KeyError) as error:
            evidence.update(status="technical_failure", error=str(error), row_count=0)
            write_json(path, evidence)
            return {**evidence, "rows": []}


def run_audit(source, indicator):
    meta = source.metadata(indicator)
    dynamic = [g["index"] + v["value"] for g in meta["groups"] for v in g["values"]]
    ages = [v["value"] for v in meta["ages"]]
    genders = [v["value"] for v in meta["genders"]]
    university_names = {v["value"]: v["label"] for v in meta["universities"]}
    age_names = [v["label"] for v in meta["ages"]]
    locations = ["uni:1"]
    ltu = [v["value"] for v in meta["universities"] if v["label"] == "Luleå tekniska universitet"]
    locations += ltu
    if indicator == 33:
        locations += ["uni:171"]
    periods = meta["retained_periods"]
    # Several periods, including the oldest retained period; never claim a full import.
    selected_periods = list(dict.fromkeys(v["value"] for v in (periods[0], periods[min(1, len(periods)-1)], periods[-1])))
    report = {"indicator": indicator, "metadata_hash": meta["metadata_hash"],
              "offered_periods": [v["value"] for v in periods], "offered_universities": meta["universities"],
              "offered_genders": genders, "offered_ages": ages, "cases": [], "publish_allowed": False}
    # Check a tiny source total BEFORE requesting larger selections. A zero-byte
    # file is a technical fault; recursive splitting only multiplies that fault.
    period = selected_periods[0]
    baseline_filters = [period, period.replace("from:", "to:", 1), "uni:1", "gender:Total", "age:1"]
    baseline_filters += [g["index"] + "dynamic:TOTAL" for g in meta["groups"]]
    baseline = source.export(indicator, baseline_filters, meta["metadata_hash"])
    report["control"] = {"key": baseline["key"], "status": baseline["status"]}
    try:
        independent = source.json_total(indicator, "uni:1", period)
        report["control"]["independent_json_total"] = independent
        if baseline["status"] == "data":
            validate_selection(baseline["rows"], period, "Riket", "gender:Total", ["Total"])
            report["control"]["exact"] = len(baseline["rows"]) == 1 and canonical_value(baseline["rows"][0]["Värde"]) == independent
    except (requests.RequestException, ValueError, KeyError) as error:
        report["control"]["independent_error"] = str(error)
    if not report["control"].get("exact", False):
        report.update(verified=False, blocked="Minimal source total not verified; no larger requests made",
                      network_exports=source.network_exports)
        write_json(source.root / f"audit-{indicator}.json", report)
        print(json.dumps(report["control"], ensure_ascii=False), flush=True)
        return report
    largest = max(meta["groups"], key=lambda g: len(g["values"]), default=None)
    for period in selected_periods:
        for location in locations:
            for gender in genders:
                base = [period, period.replace("from:", "to:", 1), location, gender] + ages
                def export(filters):
                    result = source.export(indicator, base + filters, meta["metadata_hash"])
                    if result["status"] == "data":
                        try:
                            validate_selection(result["rows"], period, university_names[location], gender, age_names)
                        except ValueError as error:
                            result = {**result, "status": "invalid_observations", "error": str(error)}
                    return result
                reference = export(dynamic)
                case = {"period": period, "university": location, "gender": gender,
                        "reference": reference["key"], "reference_status": reference["status"], "checks": []}
                if largest and len(largest["values"]) > 1:
                    # Match the successful PR #81 experiment: interleaved, not contiguous halves.
                    chosen = [largest["index"] + v["value"] for v in largest["values"]]
                    other = [v for v in dynamic if v not in chosen]
                    parts = [export(other + chosen[offset::2]) for offset in (0, 1)]
                    case["parts"] = [{"key": p["key"], "status": p["status"], "rows": len(p["rows"])} for p in parts]
                    if reference["status"] == "data" and all(p["status"] in ("data", "empty_selection_unconfirmed") for p in parts):
                        try:
                            case["checks"].append({"test": "full_vs_split", **compare(reference["rows"], [r for p in parts for r in p["rows"]])})
                        except ValueError as error:
                            case["checks"].append({"test": "full_vs_split", "exact": False, "error": str(error)})
                if reference["status"] == "data":
                    total_filters = [g["index"] + "dynamic:TOTAL" for g in meta["groups"]]
                    total = export(total_filters)
                    case["total_reference"] = {"key": total["key"], "status": total["status"]}
                    if total["status"] == "data":
                        dimension_columns = set(reference["rows"][0]) - REQUIRED
                        candidate = [row for row in reference["rows"] if not any(row[c] for c in dimension_columns)]
                        try:
                            case["checks"].append({"test": "source_totals", **compare(total["rows"], candidate)})
                        except ValueError as error:
                            case["checks"].append({"test": "source_totals", "exact": False, "error": str(error)})
                    case["coverage"] = {column: dict(Counter(r[column] for r in reference["rows"])) for column in REQUIRED - {"Värde"}}
                expected = {"source_totals"} | ({"full_vs_split"} if largest and len(largest["values"]) > 1 else set())
                case["verified"] = (reference["status"] == "data" and
                                    expected == {c["test"] for c in case["checks"]} and
                                    all(c["exact"] for c in case["checks"]))
                report["cases"].append(case)
                # Persist progress even when the process is interrupted later.
                write_json(source.root / f"audit-{indicator}.json", report)
                print(json.dumps({"indicator": indicator, **case}, ensure_ascii=False), flush=True)
    report["verified"] = bool(report["cases"]) and all(c["verified"] for c in report["cases"])
    report["network_exports"] = source.network_exports
    write_json(source.root / f"audit-{indicator}.json", report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--indicator", type=int, choices=INDICATORS, required=True)
    parser.add_argument("--output", default="output/uka-source-audit")
    parser.add_argument("--snapshot", default=datetime.now(timezone.utc).date().isoformat())
    parser.add_argument("--inventory-only", action="store_true")
    args = parser.parse_args()
    source = Source(args.output, args.snapshot)
    try:
        if args.inventory_only:
            meta = source.metadata(args.indicator)
            print(json.dumps(meta, ensure_ascii=False, indent=2))
            return 0
        report = run_audit(source, args.indicator)
        return 0 if report["verified"] else 1
    except Exception as error:
        write_json(source.root / f"failure-{args.indicator}.json", {"error": str(error), "publish_allowed": False})
        raise


if __name__ == "__main__":
    sys.exit(main())
