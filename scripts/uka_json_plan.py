"""Build an offline deterministic UKÄ discovery plan. Never fetch or publish."""
import argparse
from collections import Counter
import json
import math
from pathlib import Path
from urllib.parse import urlencode

from uka_json_probe import BASE, validate_url, yearly
from uka_source_audit import digest, write_json

STRATEGY = "national-linked-json-v1"


def build_plan(inventory, snapshot, cache):
    jobs, summaries = [], []
    for source in inventory["indicators"]:
        indicator = source["id"]
        count, cached = 0, 0
        if set(source["ages"]) != set(source["age_parameter_values"]):
            raise ValueError("Source age token mapping incomplete")
        for period in source["periods"]:
            for gender in source["genders"]:
                for age in source["ages"]:
                    query = {"university": "1", "year": period}
                    # Absence of the filter requests the API's own total.
                    if gender != "Total":
                        query["gender"] = gender
                    if age != "Total":
                        query["age_group"] = source["age_parameter_values"][age]
                    url = BASE + f"/{indicator}?" + urlencode(query)
                    spec = {"strategy": STRATEGY, "indicator": indicator, "snapshot": snapshot,
                            "query": query, "inventory_hash": digest(source)}
                    cache_key = digest([snapshot, indicator, query])
                    path = Path(cache) / "responses" / (cache_key + ".json")
                    state = "not_cached"
                    if path.exists():
                        try:
                            saved = json.loads(path.read_text())
                            if (saved["snapshot"] != snapshot or validate_url(saved["url"], indicator) != query or
                                    saved["sha256"] != digest(saved["body"]) or
                                    str(saved["body"]["indicator"]["id"]) != str(indicator) or
                                    period not in yearly(saved["body"]) or
                                    not isinstance(saved["body"].get("groups"), list)):
                                raise ValueError("Invalid cached root")
                            state = "cached_root_validated"
                            cached += 1
                        except (ValueError, KeyError, TypeError):
                            state = "invalid_cache"
                    jobs.append({"job_id": digest(spec), "indicator": indicator, "period": period,
                                 "gender": gender, "age": age, "age_parameter": query.get("age_group"), "url": url,
                                 "cache_key": cache_key, "root_state": state,
                                 "discovery_state": "pending", "publication_state": "blocked"})
                    count += 1
        summaries.append({"indicator": indicator, "root_jobs": count, "validated_cached_roots": cached,
                          "group_node_upper_bound": count * math.prod(g["options_including_total"] for g in source["groups"]),
                          "university_scope": "Riket plus source university lists for each group and period",
                          "university_filter_options": source["university_options_including_riket"]})
    if len({j["job_id"] for j in jobs}) != len(jobs):
        raise ValueError("Duplicate plan job")
    spec = {"strategy": STRATEGY, "snapshot": snapshot, "inventory_hash": digest(inventory)}
    return {"plan_id": digest(spec), **spec, "source_release_verified": False, "publish_allowed": False,
            "network_requests": 0, "completed_discovery_jobs": 0,
            "root_states": dict(Counter(j["root_state"] for j in jobs)),
            "indicators": summaries, "jobs": jobs,
            "blockers": ["Full period-specific graph and university coverage not verified",
                         "Independent source reference and null/empty semantics unresolved",
                         "Snapshot label is not a verified source release",
                         "Resumable database publication not implemented"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", default="docs/uka-source-inventory-2026-11-06.json")
    parser.add_argument("--snapshot", required=True)
    parser.add_argument("--cache", default="output/uka-json-probe")
    parser.add_argument("--output", default="output/uka-json-plan.json")
    args = parser.parse_args()
    plan = build_plan(json.loads(Path(args.inventory).read_text()), args.snapshot, args.cache)
    write_json(Path(args.output), plan)
    print(json.dumps({k: v for k, v in plan.items() if k != "jobs"}, ensure_ascii=False, indent=2))
