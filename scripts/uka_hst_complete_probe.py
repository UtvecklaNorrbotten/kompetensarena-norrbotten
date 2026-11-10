"""Exhaust the advertised HST JSON graph for one small, bounded selection.

No publishing. Graph closure is not proof of equivalence to the broken CSV API.
"""
from collections import Counter
import argparse
from datetime import date
import json
from pathlib import Path
from urllib.parse import urlencode

from uka_json_probe import BASE, Probe, SUBJECT_LEVELS, edge_value, validate_follow, validate_url, yearly
from uka_source_audit import digest, write_json


def traverse(probe, root_url, study_first=False):
    seen, values, edge_checks = {}, {}, 0
    def visit(url, body, dimensions):
        nonlocal edge_checks
        key = digest(validate_url(url, 33))
        if key in seen:
            if seen[key] != dimensions:
                raise ValueError("Same source URL reached with conflicting dimensions")
            return
        if len(seen) >= 100:
            raise ValueError("Unexpected graph size; bounded probe stopped")
        seen[key] = dimensions
        period = validate_url(url, 33)["year"]
        series = yearly(body)
        if period not in series:
            raise ValueError("Requested period missing")
        observation_key = json.dumps(dimensions, ensure_ascii=False, sort_keys=True)
        if observation_key in values:
            raise ValueError("Different source nodes duplicate an observation key")
        values[observation_key] = series[period]
        groups = [g for g in body.get("groups", []) if g["column"] in (*SUBJECT_LEVELS, "Studieform")]
        groups.sort(key=lambda g: (g["column"] != "Studieform") if study_first else (g["column"] == "Studieform"))
        for group in groups:
            column = group["column"]
            if column in dimensions:
                raise ValueError("Source reoffers an already selected dimension")
            for row in group.get("totals", []):
                child_url = row["url"]
                validate_follow(url, child_url, 33)
                child = probe.get(child_url, 33)
                edge_value(url, child_url, child, row.get("value"), 33)
                edge_checks += 1
                visit(child_url, child, {**dimensions, column: row["name"]})
    visit(root_url, probe.get(root_url, 33), {})
    return values, edge_checks


def main(output="output/uka-json-probe", snapshot=None):
    probe = Probe(output, snapshot or date.today().isoformat(), budget=80)
    report = {"indicator": 33, "university": "171", "period": "2025/26", "gender": "Kvinnor",
              "publish_allowed": False, "csv_equivalence_verified": False,
              "scope": "All nodes advertised by the JSON API for this university/period/gender and all four ages",
              "ages": [], "observations": []}
    for age, label in ((None, "Total"), ("8", "-24"), ("9", "25-34"), ("10", "35-")):
        query = {"university": "171", "year": "2025/26", "gender": "Kvinnor"}
        if age is not None:
            query["age_group"] = age
        url = BASE + "/33?" + urlencode(query)
        forward, checks = traverse(probe, url)
        before_reverse = probe.requests
        reverse, reverse_checks = traverse(probe, url, study_first=True)
        if forward != reverse:
            raise ValueError("Traversal orders disagree on observation keys or values")
        if probe.requests != before_reverse:
            raise ValueError("Second traversal unexpectedly fetched already cached source data")
        report["ages"].append({"age": label, "nodes": len(forward), "edge_value_checks": checks,
                               "reverse_edge_value_checks": reverse_checks, "exact_order_comparison": True,
                               "reverse_new_requests": 0, "source_total": forward["{}"]})
        report["observations"] += [{"age": label, "dimensions": json.loads(k), "value": v}
                                   for k, v in sorted(forward.items())]
        write_json(Path(output) / "complete-hst.json", report)
        print(json.dumps(report["ages"][-1], ensure_ascii=False), flush=True)
    keys = [digest([r["age"], r["dimensions"]]) for r in report["observations"]]
    if len(keys) != len(set(keys)):
        raise ValueError("Duplicate observation keys across ages")
    report.update(graph_closure_verified=True, duplicates=0, new_requests=probe.requests,
                  rows=len(keys), dimension_combinations=dict(Counter("|".join(sorted(o["dimensions"])) or "Total"
                                                                    for o in report["observations"])))
    report["volume_upper_bound"] = {
        "hst_source_periods": 10, "genders": 3, "ages": 4,
        "study_choices_including_total": 5, "subject_choices_including_total": 231,
        "national_graph_requests_before_sparsity_and_reuse": 10 * 3 * 4 * 5 * 231,
        "meaning": "Conservative planning bound; not a measured runtime or required request count. University lists can be read within national group responses.",
    }
    write_json(Path(output) / "complete-hst.json", report)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="output/uka-json-probe")
    parser.add_argument("--snapshot", default=date.today().isoformat())
    args = parser.parse_args()
    main(args.output, args.snapshot)
