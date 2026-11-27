"""Public SCB aggregates for the workforce page; atomic, version-bound snapshots."""
import argparse
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import gzip
import hashlib
import json
import math
from pathlib import Path
from urllib.parse import quote

from fetch_employment import ROOT, request, codes, decode, encode, packed

SPECS = {
    "status-month": ("TAB6260", "BAS · arbetskraft och grupper utanför · månad", "Alder",
                     {"Alder": ["15-74", "20-64"], "Fodelseregion": ["tot"]}),
    "birth-month": ("TAB6260", "BAS · inrikes och utrikes födda · månad", "Fodelseregion",
                    {"Alder": ["20-64"]}),
    "age-year": ("TAB5655", "BAS · åldersstruktur · årsmedelvärde", "Alder",
                 {"Fodelseregion": ["tot"]}),
    "education-month": ("TAB6666", "BAS · utbildningsnivå · månad", "UtbildningsNiva",
                        {"Alder": ["20-64"], "Fodelseregion": ["tot"]}),
    "occupation-year": ("TAB4435", "Yrkesregistret · ålder bland anställda · arbetsplatsens län", "Yrke2012", {}),
    "retirement-education": ("TAB6371", "RMI U4 · sysselsatta 60–64 år efter utbildning · arbetsplatsens län", "Utbildning", {}),
    "industry-age": ("TAB5543", "BAS · äldre sysselsatta efter bransch · endast riket", "SNI2007",
                     {"Yrkesstallning": ["TOT"], "Fodelseregion": ["tot"],
                      "Alder": ["15-74", "55-64", "65-74"], "ContentsCode": ["0000071U"]}),
}


def collect(key, cache, sample=False):
    table, label, group, fixed = SPECS[key]
    meta = request(table + "/metadata?lang=sv")
    selected = {k: codes(meta, k) for k in meta["id"]}
    selected.update(fixed)
    # Only the source's county/municipality/national codes, not unknown geography.
    if "Region" in selected:
        selected["Region"] = [g for g in selected["Region"] if g != "99" and g.isdigit()]
    if sample:
        if "Region" in selected:
            selected["Region"] = ["00", "25"]
        selected["Tid"] = selected["Tid"][-1:]
    if set(selected) != set(meta["id"]):
        raise ValueError("Ändrad tabellstruktur")
    periods = selected["Tid"]
    # Modest requests also avoid SCB server errors on large monthly selections.
    width = max(1, 35000 // math.prod(len(v) for k, v in selected.items() if k != "Tid"))

    def fetch(start):
        selection = {**selected, "Tid": periods[start:start + width]}
        query = {"selection": [{"variableCode": k, "valueCodes": v} for k, v in selection.items()]}
        fingerprint = hashlib.sha256(encode([table, meta["updated"], query])).hexdigest()
        path = cache / (fingerprint + ".json")
        if path.exists():
            d = json.loads(path.read_bytes())
        else:
            d = request(table + "/data?lang=sv&outputFormat=json-stat2", query)
            if d.get("updated") != meta["updated"]:
                raise ValueError("SCB-version ändrades under hämtning")
            list(decode(d, selection))
            path.write_bytes(encode(d))
        if d.get("updated") != meta["updated"]:
            raise ValueError("Fel cacheversion")
        return selection, d

    rows = defaultdict(list)
    with ThreadPoolExecutor(max_workers=2) as pool:
        for selection, d in pool.map(fetch, range(0, len(periods), width)):
            for f, value, flag in decode(d, selection):
                # Period, sex, category, age, measure, value, source status.
                rows[f.get("Region", "00")].append([f["Tid"], f["Kon"], f[group], f.get("Alder", ""),
                                           f["ContentsCode"], value, flag])
            print(key, selection["Tid"][-1], flush=True)
    if request(table + "/metadata?lang=sv")["updated"] != meta["updated"]:
        raise ValueError("SCB-version ändrades under hämtning")
    labels = {k: v["category"]["label"] for k, v in meta["dimension"].items()}
    info = {"table": table, "label": label, "updated": meta["updated"], "periods": periods,
            "group": group, "categories": {c: labels[group][c] for c in selected[group]},
            "ages": {c: labels["Alder"][c] for c in selected.get("Alder", [])},
            "measures": {c: labels["ContentsCode"][c] for c in selected["ContentsCode"]},
            "units": meta["dimension"]["ContentsCode"]["category"].get("unit", {}),
            "sexes": selected["Kon"], "selection": selected, "notes": meta.get("note", []),
            "source": f"https://statistikdatabasen.scb.se/api/v2/tables/{table}/metadata?lang=sv",
            "cells": sum(map(len, rows.values()))}
    if group == "Utbildning":
        info["groups"] = {}
        for item in meta["dimension"][group]["extension"]["codelists"]:
            values = request("../codeLists/" + quote(item["id"], safe="") + "?lang=sv")["values"]
            family = "inriktning" if "inriktn" in item["id"].lower() else "niva" if "nivå" in item["id"].lower() else "grupp"
            info["groups"][family] = [v["code"] for v in values]
    if table in ("TAB6260", "TAB5655", "TAB6666"):
        measures = info["measures"]
        numerator = next(c for c, l in measures.items() if "(arbetskraften)" in l)
        denominator = next(c for c, l in measures.items() if l == "antal totalt")
        rate = next(c for c, l in measures.items() if l == "arbetskraftsdeltagande")
        checks = 0
        for records in rows.values():
            lookup = {tuple(r[:5]): None if r[6] else r[5] for r in records}
            for r in records:
                if r[4] != numerator:
                    continue
                prefix = tuple(r[:4])
                n, d, a = lookup.get(prefix + (numerator,)), lookup.get(prefix + (denominator,)), lookup.get(prefix + (rate,))
                if n is not None and d is not None and a is not None and d >= 1000:
                    if abs(a - 100 * n / d) > 0.16:
                        raise ValueError("Arbetskraftsdeltagandet avviker från källans täljare/nämnare")
                    checks += 1
        info["rate_checks"] = checks
    return info, dict(rows), {g: labels.get("Region", {"00": "Riket"})[g] for g in selected.get("Region", ["00"])}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--sample", action="store_true")
    args = parser.parse_args()
    cache = ROOT / ".cache/workforce"
    if args.force:
        cache = cache / ("force-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S"))
    cache.mkdir(parents=True, exist_ok=True)
    dest = ROOT / "public/data/workforce"
    catpath = ROOT / "src/data/workforce/catalog.json"
    old = json.loads(catpath.read_bytes()) if catpath.exists() else {"datasets": {}}
    catalog = {"fetched": datetime.now(timezone.utc).isoformat(), "datasets": {}, "geographies": {}, "files": {}}
    pending = {}
    for key, spec in SPECS.items():
        meta = request(spec[0] + "/metadata?lang=sv")
        previous = old["datasets"].get(key)
        complete = previous and previous.get("cells", 0) > 0 and all(
            name in old.get("files", {}) and (dest / old["files"][name]["path"]).is_file()
            for name in [*[f"{key}/geo-{g}.json" for g in previous["selection"].get("Region", ["00"])],
                         *[f"{key}/period-{p}.json" for p in previous["periods"]]])
        if complete and previous["updated"] == meta["updated"] and not args.force and not args.sample:
            catalog["datasets"][key] = previous
            catalog["geographies"].update(old["geographies"])
            catalog["files"].update({k:v for k,v in old["files"].items() if k.startswith(key + "/")})
            continue
        checkpoint = cache / (key + "-" + hashlib.sha256(encode([meta["updated"], spec])).hexdigest() + ".gz")
        if checkpoint.exists() and not args.sample and not args.force:
            info, rows, geos = json.loads(gzip.decompress(checkpoint.read_bytes()))
        else:
            info, rows, geos = collect(key, cache, args.sample)
            if not args.sample:
                checkpoint.write_bytes(gzip.compress(encode([info, rows, geos]), mtime=0))
        catalog["datasets"][key] = info
        catalog["geographies"].update(geos)
        periodrows = defaultdict(list)
        for geo, records in rows.items():
            pending[f"{key}/geo-{geo}.json"] = packed(records)
            for row in records:
                periodrows[row[0]].append([geo, *row[1:]])
        for period, records in periodrows.items():
            pending[f"{key}/period-{period}.json"] = packed(records)
        print("Verified", key, info["cells"], flush=True)
    if args.sample:
        print("SCB-prov verifierat; ingen publicering")
        return
    for name, content in pending.items():
        digest = hashlib.sha256(content).hexdigest()
        path = name.replace(".json", "-" + digest[:16] + ".json")
        target = dest / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        catalog["files"][name] = {"path": path, "sha256": digest}
    if catalog["datasets"] == old["datasets"] and catalog["files"] == old.get("files"):
        print("Oförändrade versioner")
        return
    catpath.parent.mkdir(parents=True, exist_ok=True)
    catpath.write_bytes(encode(catalog) + b"\n")
    keep = {v["path"] for v in catalog["files"].values()}
    for path in dest.glob("*/*.json"):
        if str(path.relative_to(dest)) not in keep:
            path.unlink()


if __name__ == "__main__":
    main()
