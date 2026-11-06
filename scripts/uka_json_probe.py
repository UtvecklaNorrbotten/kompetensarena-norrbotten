"""Bounded, read-only feasibility tests for UKÄ's linked JSON API.

Follows advertised group links instead of inventing combined group identifiers.
This is not an importer: it cannot publish and does not certify CSV equivalence.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import date
import json
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlparse

import requests

from uka_source_audit import canonical_value, digest, write_json

BASE = "https://statistik-api.uka.se/api/totals"
CONTEXT = ("university", "year", "gender", "age_group")
SUBJECT_LEVELS = ("Ämnesområde", "Ämnesdelområde", "Ämnesgrupp")


def validate_url(url, indicator):
    parsed = urlparse(url)
    if (parsed.scheme != "https" or parsed.hostname != "statistik-api.uka.se" or
            parsed.path.rstrip("/") != f"/api/totals/{indicator}"):
        raise ValueError("Unexpected JSON source link")
    query = parse_qs(parsed.query)
    if any(len(v) != 1 for v in query.values()):
        raise ValueError("Ambiguous source parameters")
    return {key: values[0] for key, values in query.items()}


def validate_follow(parent, child, indicator):
    before, after = validate_url(parent, indicator), validate_url(child, indicator)
    if any(before.get(key) != after.get(key) for key in CONTEXT):
        raise ValueError("Advertised group link changed a context filter")


def yearly(body):
    result = {}
    for row in body.get("yearly_totals", {}).get("totals", []):
        if "value" not in row:
            raise ValueError("Missing source value field")
        key = row["year"]
        if key in result:
            raise ValueError("Duplicate source period")
        if row.get("value") is None:
            result[key] = None
        else:
            result[key] = canonical_value(str(row["value"]))
    if not result:
        raise ValueError("Missing yearly source observations")
    return result


def edge_value(parent_url, child_url, child_body, advertised_value, indicator):
    validate_follow(parent_url, child_url, indicator)
    period = validate_url(parent_url, indicator)["year"]
    values = yearly(child_body)
    expected = None if advertised_value is None else canonical_value(str(advertised_value))
    if period not in values or values[period] != expected:
        raise ValueError("Advertised observation differs from child source observation")
    return values[period]


class Probe:
    def __init__(self, root, snapshot, budget=100):
        self.root = Path(root)
        self.snapshot = snapshot
        self.budget = budget
        self.requests = 0
        self.session = requests.Session()
        self.session.headers["User-Agent"] = "Kompetensarena-UKA-ReadOnly-JSON-Probe/1.0"

    def get(self, url, indicator):
        query = validate_url(url, indicator)
        key = digest([self.snapshot, indicator, query])
        path = self.root / "responses" / (key + ".json")
        if path.exists():
            cached = json.loads(path.read_text())
            if (cached.get("snapshot") != self.snapshot or
                    validate_url(cached["url"], indicator) != query or
                    str(cached["body"].get("indicator", {}).get("id")) != str(indicator)):
                raise ValueError("Cached source context mismatch")
            if cached["sha256"] == digest(cached["body"]):
                return cached["body"]
        if self.requests >= self.budget:
            raise RuntimeError("JSON request budget exhausted")
        self.requests += 1
        response = self.session.get(url, timeout=60)
        response.raise_for_status()
        body = response.json()
        if str(body.get("indicator", {}).get("id")) != str(indicator):
            raise ValueError("Wrong source indicator")
        write_json(path, {"url": url, "snapshot": self.snapshot, "body": body, "sha256": digest(body)})
        return body

    def follow(self, url, body, column, indicator, name=None):
        matches = [row for group in body.get("groups", []) if group["column"] == column
                   for row in group.get("totals", []) if name is None or row.get("name") == name]
        if not matches:
            raise ValueError("Source offers no matching group: " + column)
        row = matches[0]
        validate_follow(url, row["url"], indicator)
        child = self.get(row["url"], indicator)
        value = edge_value(url, row["url"], child, row.get("value"), indicator)
        return row["url"], child, {"dimension": column, "category": row["name"], "value": value,
                                    "url": row["url"]}


def hst_case(probe, university, period):
    url = BASE + "/33?" + urlencode({"university": university, "year": period,
                                      "gender": "Kvinnor", "age_group": "8"})
    root = probe.get(url, 33)
    report = {"university": university, "period": period, "gender": "Kvinnor", "age": "-24",
              "root_url": url, "source_total": yearly(root).get(period), "edges": []}
    if report["source_total"] is None:
        raise ValueError("Requested period has no confirmed source total")
    subject_url, subject, subject_edge = probe.follow(url, root, "Ämnesområde", 33)
    study_url, study, study_edge = probe.follow(url, root, "Studieform", 33)
    joint_url, joint, joint_edge = probe.follow(subject_url, subject, "Studieform", 33, study_edge["category"])
    reverse_url, reverse, reverse_edge = probe.follow(study_url, study, "Ämnesområde", 33, subject_edge["category"])
    report["edges"] += [subject_edge, study_edge, joint_edge, reverse_edge]
    # Source may canonicalise both navigation orders to the very same endpoint.
    # Record this explicitly; it is not an independent CSV reference.
    report["two_navigation_orders"] = {
        "same_endpoint": validate_url(joint_url, 33) == validate_url(reverse_url, 33),
        "exact_yearly_observations": yearly(joint) == yearly(reverse),
        "periods_compared": sorted(yearly(joint)),
    }
    if not report["two_navigation_orders"]["exact_yearly_observations"]:
        raise ValueError("Different observations between navigation orders")
    current_url, current = joint_url, joint
    for level in ("Ämnesdelområde", "Ämnesgrupp"):
        current_url, current, edge = probe.follow(current_url, current, level, 33)
        report["edges"].append(edge)
    report["deepest_joint_value"] = yearly(current)[period]
    report["verified_sample"] = True
    return report


def hst_gender_age_grid(probe, expected_ages):
    """Check all offered age groups for each source gender, without summation."""
    root_url = BASE + "/33?" + urlencode({"university": "171", "year": "2025/26"})
    root = probe.get(root_url, 33)
    contexts = [("Total", root_url, root)]
    def follow_scalar(parent_url, row, changed_key, expected):
        before, after = validate_url(parent_url, 33), validate_url(row["url"], 33)
        if before.get(changed_key) is not None or after.get(changed_key) != str(expected):
            raise ValueError("Unexpected scalar filter transition")
        if any(before.get(k) != after.get(k) for k in CONTEXT if k != changed_key):
            raise ValueError("Scalar link changed another context filter")
        body = probe.get(row["url"], 33)
        period = before["year"]
        source_value = None if row.get("value") is None else canonical_value(str(row["value"]))
        values = yearly(body)
        if period not in values or values[period] != source_value:
            raise ValueError("Scalar child value differs from advertised value")
        return body
    for group in root.get("groups", []):
        if group["column"] == "Kön":
            for row in group["totals"]:
                gender = row["gender"]
                contexts.append((gender, row["url"], follow_scalar(root_url, row, "gender", gender)))
    if {gender for gender, _, _ in contexts} != {"Kvinnor", "Män", "Total"}:
        raise ValueError("Source gender grid incomplete")
    observations = []
    for gender, url, body in contexts:
        observations.append({"gender": gender, "age": "Total", "value": yearly(body)["2025/26"], "url": url})
        for group in body.get("groups", []):
            if group["column"] == "Åldersgrupper":
                for row in group["totals"]:
                    child = follow_scalar(url, row, "age_group", row["id"])
                    observations.append({"gender": gender, "age": row["name"],
                                         "value": yearly(child)["2025/26"], "url": row["url"]})
    keys = {(o["gender"], o["age"]) for o in observations}
    expected = {(gender, age) for gender in ("Kvinnor", "Män", "Total") for age in expected_ages}
    if len(keys) != len(observations) or keys != expected:
        raise ValueError("Source age/gender grid incomplete or duplicated")
    return {"university": "171", "period": "2025/26", "observations": observations, "verified_sample": True}


def run(output, inventory, snapshot):
    meta = json.loads(Path(inventory).read_text())["indicators"]
    report = {"snapshot": snapshot, "publish_allowed": False, "csv_equivalence_verified": False,
              "inventory": [], "hst_samples": []}
    # Each worker owns its own HTTP session; distinct indicator cache keys.
    def inspect(item):
        probe = Probe(output, snapshot, budget=2)
        result = {"indicator": item["id"], "periods": []}
        for period in dict.fromkeys((item["periods"][0], item["periods"][-1])):
            url = BASE + f"/{item['id']}?" + urlencode({"university": "1", "year": period})
            body = probe.get(url, item["id"])
            values = yearly(body)
            if period not in values:
                raise ValueError("Requested period absent from JSON API")
            result["periods"].append({"period": period, "source_total": values[period],
                                      "all_source_periods": sorted(values), "url": url,
                                      "group_columns": [g["column"] for g in body.get("groups", [])]})
        return result
    with ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(inspect, meta):
            report["inventory"].append(result)
            write_json(Path(output) / "summary.json", report)
            print(json.dumps({"indicator": result["indicator"], "checked_periods": [p["period"] for p in result["periods"]]}, ensure_ascii=False), flush=True)
    probe = Probe(output, snapshot, budget=42)
    for university, period in (("171", "2025/26"), ("171", "2024/25"),
                               ("32", "2025/26"), ("32", "2016/17"),
                               ("1", "2025/26"), ("1", "2016/17")):
        try:
            case = hst_case(probe, university, period)
        except (ValueError, requests.RequestException) as error:
            case = {"university": university, "period": period, "verified_sample": False, "error": str(error)}
        report["hst_samples"].append(case)
        write_json(Path(output) / "summary.json", report)
        print(json.dumps({k: case[k] for k in ("university", "period", "verified_sample", "source_total", "error") if k in case}, ensure_ascii=False), flush=True)
    for case in report["hst_samples"]:
        if case["university"] == "1" or not case["verified_sample"]:
            continue
        url = BASE + "/33?" + urlencode({"university": "1", "year": case["period"],
                                         "gender": "Kvinnor", "age_group": "8"})
        body = probe.get(url, 33)
        matches = [row for group in body.get("groups", []) if group["column"] == "Lärosäten"
                   for row in group["totals"]
                   if validate_url(row["url"], 33).get("university") == case["university"]]
        if len(matches) != 1 or canonical_value(str(matches[0]["value"])) != case["source_total"]:
            case.update(verified_sample=False, university_group_check=False)
        else:
            case["university_group_check"] = {"exact": True, "parent_url": url, "name": matches[0]["name"]}
    grid_probe = Probe(output, snapshot, budget=12)
    ages = next(m["ages"] for m in meta if m["id"] == 33)
    try:
        report["gender_age_grid"] = hst_gender_age_grid(grid_probe, ages)
    except (ValueError, requests.RequestException) as error:
        report["gender_age_grid"] = {"verified_sample": False, "error": str(error)}
    report["sample_checks_passed"] = all(c["verified_sample"] for c in report["hst_samples"])
    report["sample_checks_passed"] &= report["gender_age_grid"]["verified_sample"]
    report["hst_new_requests"] = probe.requests
    write_json(Path(output) / "summary.json", report)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="output/uka-json-probe")
    parser.add_argument("--inventory", default="docs/uka-source-inventory-2026-11-06.json")
    parser.add_argument("--snapshot", default=date.today().isoformat())
    args = parser.parse_args()
    report = run(args.output, args.inventory, args.snapshot)
    raise SystemExit(0 if report["sample_checks_passed"] else 1)
