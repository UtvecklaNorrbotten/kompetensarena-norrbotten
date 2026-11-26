"""Versioned public SCB aggregates for employment. No database microdata.

Responses are cached by table version and exact selection. A failed/version-changing
collection never replaces the published catalog. Independent tables remain separate.
"""

import argparse
import base64
import csv
import io
import zipfile
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import gzip
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import time
import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
API = "https://statistikdatabasen.scb.se/api/v2/tables/"
SPECS = {
    "industry-month": (
        "TAB3784",
        "BAS · preliminära månadsuppgifter · bransch",
        "SNI2007",
        {"Fodelseregion": ["tot"]},
        "A-U+US",
        "15–74 år",
    ),
    "sector-month": (
        "TAB2597",
        "BAS · preliminära månadsuppgifter · sektor",
        "ArbetsSektor",
        {"Alder": ["15-74"], "Fodelseregion": ["tot"]},
        "010",
        "15–74 år",
    ),
    "age-month": (
        "TAB6260",
        "BAS · preliminära månadsuppgifter · ålder",
        "Alder",
        {"Fodelseregion": ["tot"]},
        "15-74",
        "Vald åldersgrupp",
    ),
    "birth-month": (
        "TAB6260",
        "BAS · preliminära månadsuppgifter · födelseregion",
        "Fodelseregion",
        {"Alder": ["15-74"]},
        "tot",
        "15–74 år",
    ),
    "education-month": (
        "TAB6666",
        "BAS · preliminära månadsuppgifter · utbildning",
        "UtbildningsNiva",
        {"Alder": ["20-64"], "Fodelseregion": ["tot"]},
        None,
        "20–64 år",
    ),
    "industry-year": (
        "TAB3204",
        "BAS · slutligt årligt register · bransch",
        "SNI2007",
        {"Fodelseregion": ["tot"]},
        "A-U+US",
        "15–74 år",
    ),
    "sector-year": (
        "TAB3260",
        "BAS · slutligt årligt register · sektor",
        "ArbetsSektor",
        {"Alder": ["15-74"], "Fodelseregion": ["tot"]},
        "010",
        "15–74 år",
    ),
    "education-year": (
        "TAB1786",
        "BAS · slutligt årligt register · utbildning",
        "UtbildningsNiva",
        {"SNI2007": ["A-U+US"]},
        None,
        "15–74 år",
    ),
    "rams-old-day": (
        "TAB900",
        "RAMS · äldre metod · arbetsplats",
        "SNI2007",
        {},
        "TOT",
        "16 år och äldre",
    ),
    "rams-old-night": (
        "TAB3039",
        "RAMS · äldre metod · bostad",
        "SNI2007",
        {},
        "TOT",
        "16 år och äldre",
    ),
    "rams-new-day": (
        "TAB5837",
        "RAMS · ny metod 2019–2021 · arbetsplats",
        "SNI2007",
        {},
        "TOT",
        "16–74 år",
    ),
    "rams-new-night": (
        "TAB5776",
        "RAMS · ny metod 2019–2021 · bostad",
        "SNI2007",
        {},
        "TOT",
        "16–74 år",
    ),
}


def encode(v):
    return json.dumps(
        v, ensure_ascii=False, separators=(",", ":"), allow_nan=False
    ).encode()


def request(path, payload=None):
    for attempt in range(6):
        try:
            r = urllib.request.Request(
                API + path,
                data=encode(payload) if payload else None,
                headers={
                    "Content-Type": "application/json",
                    "User-Agent": "KompetensarenaNorrbotten/1.0",
                },
            )
            with urllib.request.urlopen(r, timeout=100) as response:
                return json.load(response)
        except (urllib.error.URLError, TimeoutError) as error:
            print(
                "SCB retry",
                path.split("/")[0],
                type(error).__name__,
                getattr(error, "code", "timeout"),
                attempt + 1,
                flush=True,
            )
            if isinstance(error, urllib.error.HTTPError) and error.code not in (
                408,
                429,
                500,
                502,
                503,
                504,
            ):
                raise
            if attempt == 5:
                raise
            time.sleep(min(30, 2**attempt))


def codes(d, key):
    index = d["dimension"][key]["category"]["index"]
    return index if isinstance(index, list) else sorted(index, key=index.get)


def decode(d, selected):
    if set(d["id"]) != set(selected):
        raise ValueError("Ändrade dimensioner")
    axes = [codes(d, k) for k in d["id"]]
    for k, axis in zip(d["id"], axes):
        if set(axis) != set(selected[k]) or len(axis) != len(selected[k]):
            raise ValueError("Ofullständigt urval: " + k)
    size = math.prod(map(len, axes))
    if list(map(len, axes)) != d["size"]:
        raise ValueError("Fel dimensionstorlek")
    values, status = d["value"], d.get("status", {})
    if isinstance(values, list) and len(values) != size:
        raise ValueError("Ofullständigt svar")
    if isinstance(status, list) and len(status) != size:
        raise ValueError("Ofullständig status")
    if isinstance(values, dict) and any(
        not str(i).isdigit() or int(i) >= size for i in values
    ):
        raise ValueError("Felaktigt glest index")
    for i, cell in enumerate(itertools.product(*axes)):
        value = values[i] if isinstance(values, list) else values.get(str(i))
        flag = status[i] if isinstance(status, list) else status.get(str(i), "")
        if value is not None and (
            isinstance(value, bool)
            or not isinstance(value, (float, int))
            or not math.isfinite(value)
            or value < 0
        ):
            raise ValueError("Ogiltigt värde")
        yield dict(zip(d["id"], cell)), value, flag or ""


def bulk_cells(meta, selected, archive):
    """SCB's prebuilt CSV preserves its own totals and cell symbols."""

    def variants(code, label):
        values = {label, code + " " + label}
        return values | {v.replace("–", "-").replace("−", "-") for v in values}

    with zipfile.ZipFile(archive) as z:
        names = [n for n in z.namelist() if n.lower().endswith(".csv")]
        if len(names) != 1:
            raise ValueError("Oväntad SCB-bulkfil")
        with io.TextIOWrapper(
            z.open(names[0]), encoding="cp1252", newline=""
        ) as stream:
            reader = csv.reader(stream)
            header = next(reader)
            lookup = {
                k: {
                    v: code
                    for code in selected[k]
                    for v in variants(
                        code, meta["dimension"][k]["category"]["label"][code]
                    )
                }
                for k in selected
            }
            indices = {k: header.index(meta["dimension"][k]["label"]) for k in selected}
            order = sorted(selected, key=lambda k: len(selected[k]))
            count = 0
            for line, row in enumerate(reader):
                if line and line % 5000000 == 0:
                    print("Bulk rows", line, flush=True)
                if len(row) != len(header):
                    raise ValueError("Fel antal CSV-kolumner")
                if any(row[indices[k]] not in lookup[k] for k in order):
                    continue
                fields = {k: lookup[k][row[i]] for k, i in indices.items()}
                raw = row[-1].strip()
                try:
                    value = float(raw.replace(",", "."))
                    flag = ""
                except ValueError:
                    value = None
                    flag = raw
                count += 1
                yield fields, value, flag
            if count != math.prod(map(len, selected.values())):
                raise ValueError(f"Ofullständig bulkfil: {count} celler")


def packed(rows):
    return (
        encode(
            {
                "gzip": base64.b64encode(
                    gzip.compress(encode(rows), compresslevel=1, mtime=0)
                ).decode()
            }
        )
        + b"\n"
    )


def collect(key, cache, sample=False):
    print("Collect", key, flush=True)
    table, label, dim, fixed, total, age = SPECS[key]
    meta = request(table + "/metadata?lang=sv")
    labels = {k: v["category"]["label"] for k, v in meta["dimension"].items()}
    selected = {k: codes(meta, k) for k in meta["id"]}
    selected.update(fixed)
    # Region lists are taken from the source, never inferred by adding municipalities.
    regions = [r for r in selected["Region"] if len(r) in (2, 4) and r.isdigit()]
    if len(regions) != 312 or "25" not in regions or "00" not in regions:
        raise ValueError("Kontrollera geografisk täckning")
    selected["Region"] = ["00", "25", "2580"] if sample else regions
    if key.startswith("rams-old"):
        selected["Tid"] = [p for p in selected["Tid"] if p >= "2011"]
    # RAMS offers detailed/grouped SNI via codelists. Use the default published
    # classification and its own total; never relabel it as BAS's 15 groups.
    categories = labels[dim]
    if total not in categories:
        total = next(
            (
                c
                for c, l in categories.items()
                if l.lower() in ("totalt", "total", "samtliga näringsgrenar")
            ),
            None,
        )
    contents = labels["ContentsCode"]
    rate = next((c for c, l in contents.items() if l == "sysselsättningsgrad"), None)
    denominator = next((c for c, l in contents.items() if l == "antal totalt"), None)
    count = next((c for c, l in contents.items() if l == "antal sysselsatta"), None)
    perspectives = {}
    if count:
        perspectives[count] = "bostad"
        selected["ContentsCode"] = [count, rate, denominator]
        if not rate or not denominator:
            raise ValueError("Nämnare eller sysselsättningsgrad saknas")
    else:
        for c, l in contents.items():
            if "arbetsställets belägenhet" in l or "dagbefolkning" in l:
                perspectives[c] = "arbetsstalle"
            elif "bostadens belägenhet" in l or "nattbefolkning" in l:
                perspectives[c] = "bostad"
            elif key.startswith("rams-"):
                perspectives[c] = "arbetsstalle" if key.endswith("day") else "bostad"
        if not perspectives:
            raise ValueError("Okänt tabellinnehåll")
        selected["ContentsCode"] = list(perspectives)
    if set(selected) != set(meta["id"]):
        raise ValueError("Ändrad tabell")
    if sample:
        selected["Tid"] = selected["Tid"][-1:]
    for k, v in selected.items():
        if not v or not set(v) <= set(codes(meta, k)):
            raise ValueError("Ogiltigt urval: " + k)
    periods = selected["Tid"]
    bygeo = defaultdict(dict)
    cells_per_period = math.prod(len(v) for k, v in selected.items() if k != "Tid")
    limit = 140000 if key == "industry-month" else 45000
    width = (
        1
        if key.endswith("-month") and key != "industry-month"
        else max(1, limit // cells_per_period)
    )
    if cells_per_period > 140000:
        raise ValueError("För stort uttag")

    def fetch_chunk(start):
        selection = {**selected, "Tid": periods[start : start + width]}
        query = {
            "selection": [
                {"variableCode": k, "valueCodes": v} for k, v in selection.items()
            ]
        }
        fingerprint = hashlib.sha256(
            encode([table, meta["updated"], query])
        ).hexdigest()
        path = cache / (fingerprint + ".json")
        if path.exists():
            d = json.loads(path.read_bytes())
        else:
            d = request(table + "/data?lang=sv&outputFormat=json-stat2", query)
            if d.get("updated") != meta["updated"]:
                raise ValueError("SCB-version ändrades")
            list(decode(d, selection))
            path.write_bytes(encode(d))
        return start, selection, d

    archive = cache / (table + "-" + meta["updated"].replace(":", "_") + ".zip")
    if table == "TAB2597" and not sample and not archive.exists():
        url = f"https://www.statistikdatabasen.scb.se/Resources/PX/bulk/ssd/sv/{table}_sv.zip"
        temporary = archive.with_suffix(".partial")
        print("Download bulk", table, flush=True)
        with urllib.request.urlopen(url, timeout=120) as response, temporary.open(
            "wb"
        ) as output:
            modified = response.headers.get("Last-Modified")
            version = datetime.fromisoformat(meta["updated"].replace("Z", "+00:00"))
            if not modified or parsedate_to_datetime(modified) < version:
                raise ValueError(
                    "SCB:s CSV-fil har ännu inte uppdaterats till API-versionen"
                )
            while block := response.read(1024 * 1024):
                output.write(block)
        with zipfile.ZipFile(temporary) as z:
            if not z.namelist():
                raise ValueError("Tom bulkfil")
        if request(table + "/metadata?lang=sv")["updated"] != meta["updated"]:
            raise ValueError("Ändrad bulkversion")
        temporary.replace(archive)
    if archive.exists() and not sample:
        chunks = [(0, selected, None)]
    else:
        with ThreadPoolExecutor(max_workers=3) as pool:
            chunks = list(pool.map(fetch_chunk, range(0, len(periods), width)))
    for start, selection, d in chunks:
        cells = (
            bulk_cells(meta, selection, archive) if d is None else decode(d, selection)
        )
        for f, value, flag in cells:
            c = f["ContentsCode"]
            perspective = perspectives.get(c, "bostad")
            rowkey = (f["Tid"], f["Kon"], perspective, f[dim])
            row = bygeo[f["Region"]].setdefault(rowkey, [None, None, "", "", None])
            if c == rate:
                row[1], row[3] = value, flag
            elif c == denominator:
                row[4] = value
            else:
                row[0], row[2] = value, flag
        print(key, start + len(selection["Tid"]), "/", len(periods), flush=True)
    if archive.exists() and not sample:
        probe = {
            **selected,
            "Region": ["00", "25", "2580"],
            "Tid": [periods[0], periods[-1]],
        }
        query = {
            "selection": [
                {"variableCode": k, "valueCodes": v} for k, v in probe.items()
            ]
        }
        source = request(table + "/data?lang=sv&outputFormat=json-stat2", query)
        if source.get("updated") != meta["updated"]:
            raise ValueError("Bulk/API har olika versioner")
        for f, value, flag in decode(source, probe):
            c = f["ContentsCode"]
            row = bygeo[f["Region"]][
                (f["Tid"], f["Kon"], perspectives.get(c, "bostad"), f[dim])
            ]
            vi, fi = (1, 3) if c == rate else (4, 2) if c == denominator else (0, 2)
            if row[vi] != value or (c != denominator and row[fi] != (flag or "")):
                archive.unlink(missing_ok=True)
                raise ValueError(
                    "Bulk och oberoende API-prov avviker; bulkcachen har rensats"
                )
        print("Bulk/API verified", table, flush=True)
    if key.startswith("rams-"):
        # Ask SCB to eliminate dimensions: these are official source totals, not
        # a sum of protected detail cells. Cover total sex and/or total industry.
        for omitted in [(dim,), ("Kon",), (dim, "Kon")]:
            reduced = {k: v for k, v in selected.items() if k not in omitted}
            query = {
                "selection": [
                    {"variableCode": k, "valueCodes": v} for k, v in reduced.items()
                ]
            }
            fingerprint = hashlib.sha256(
                encode([table, meta["updated"], query])
            ).hexdigest()
            path = cache / (fingerprint + ".json")
            if path.exists():
                d = json.loads(path.read_bytes())
            else:
                d = request(table + "/data?lang=sv&outputFormat=json-stat2", query)
                if d.get("updated") != meta["updated"]:
                    raise ValueError("Ändrad RAMS-version")
                list(decode(d, reduced))
                path.write_bytes(encode(d))
            for f, value, flag in decode(d, reduced):
                rowkey = (
                    f["Tid"],
                    f.get("Kon", "1+2"),
                    next(iter(perspectives.values())),
                    f.get(dim, "ALL"),
                )
                bygeo[f["Region"]][rowkey] = [value, None, flag, "", None]
        total = "ALL"
        categories = {**categories, "ALL": "Samtliga näringsgrenar"}
        selected["Kon"] = ["1", "2", "1+2"]
    if request(table + "/metadata?lang=sv")["updated"] != meta["updated"]:
        raise ValueError("SCB-version ändrades under hämtning")
    # Published rates are checked against their own source numerator/denominator.
    # Disclosure perturbation and one-decimal rate rounding need a small tolerance.
    checks = 0
    for records in bygeo.values():
        for n, r, flag, rflag, d in records.values():
            if (
                n is not None
                and r is not None
                and d is not None
                and d >= 100
                and not flag
                and not rflag
            ):
                if abs(r - 100 * n / d) > 0.16:
                    raise ValueError(
                        "Sysselsättningsgrad avviker från källans täljare/nämnare"
                    )
                checks += 1
    rows = {
        geo: [[*k, *v[:4]] for k, v in sorted(records.items())]
        for geo, records in bygeo.items()
    }
    info = {
        "table": table,
        "label": label,
        "updated": meta["updated"],
        "periods": periods,
        "categories": categories,
        "total": total,
        "age": age,
        "dimension": dim,
        "perspectives": sorted(set(perspectives.values())),
        "selection": selected,
        "notes": meta.get("note", []),
        "rate": bool(rate),
        "rate_checks": checks,
        "source": f"https://statistikdatabasen.scb.se/api/v2/tables/{table}/metadata?lang=sv",
    }
    print("Verified", key, sum(map(len, rows.values())), flush=True)
    if archive.exists():
        with archive.open("rb") as source:
            info["bulk_sha256"] = hashlib.file_digest(source, "sha256").hexdigest()
    return info, rows, labels["Region"]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--sample", action="store_true")
    p.add_argument("--force", action="store_true")
    p.add_argument("--resume", action="store_true")
    args = p.parse_args()
    cache = Path(os.environ.get("EMPLOYMENT_CACHE", "/tmp/employment-cache"))
    if args.force and not args.resume:
        cache = cache / (
            "force-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
        )
    cache.mkdir(parents=True, exist_ok=True)
    print("Response cache:", str(cache), flush=True)
    dest = ROOT / "public/data/employment"
    dest.mkdir(parents=True, exist_ok=True)
    catalog_path = ROOT / "src/data/employment/catalog.json"
    old = (
        json.loads(catalog_path.read_bytes())
        if catalog_path.exists()
        else {"datasets": {}}
    )
    catalog = {
        "fetched": datetime.now(timezone.utc).isoformat(),
        "datasets": {},
        "geographies": {},
        "files": {},
    }
    pending = {}
    for key in SPECS:
        print("Check", key, flush=True)
        meta = request(SPECS[key][0] + "/metadata?lang=sv")
        previous = old["datasets"].get(key)
        if (
            previous
            and previous["updated"] == meta["updated"]
            and not args.force
            and not args.sample
        ):
            catalog["datasets"][key] = previous
            catalog["geographies"].update(old["geographies"])
            catalog["files"].update(
                {k: v for k, v in old["files"].items() if k.startswith(key + "/")}
            )
            continue
        collected = cache / (
            key
            + "-"
            + hashlib.sha256(encode([meta["updated"], SPECS[key]])).hexdigest()
            + ".gz"
        )
        if collected.exists() and not args.sample:
            info, rows, geos = json.loads(gzip.decompress(collected.read_bytes()))
            if info["updated"] != meta["updated"]:
                raise ValueError("Fel version i återstartscache")
        else:
            info, rows, geos = collect(key, cache, args.sample)
            if not args.sample:
                collected.write_bytes(
                    gzip.compress(encode([info, rows, geos]), compresslevel=1, mtime=0)
                )
        catalog["datasets"][key] = info
        catalog["geographies"].update(geos)
        for geo, records in rows.items():
            pending[f"{key}/geo-{geo}.json"] = packed(records)
        byperiod = defaultdict(list)
        for geo, records in rows.items():
            for row in records:
                byperiod[row[0]].append([geo, *row[1:]])
        for period, records in byperiod.items():
            pending[f"{key}/period-{period}.json"] = packed(records)
        print("Packed", key, flush=True)
        if args.sample:
            continue
    if args.sample:
        print("SCB-prov verifierat, ingen publicering")
        return
    # Immutable content-addressed generations: requests using an old catalog keep
    # reading that exact generation while a new deployment is propagated.
    for name, content in pending.items():
        digest = hashlib.sha256(content).hexdigest()
        file = name.replace(".json", "-" + digest[:16] + ".json")
        target = dest / file
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        catalog["files"][name] = {"path": file, "sha256": digest}
    if catalog["datasets"] == old["datasets"] and catalog["files"] == old.get("files"):
        print("Oförändrade SCB-versioner")
        return
    catalog_path.parent.mkdir(parents=True, exist_ok=True)
    catalog_path.write_bytes(encode(catalog) + b"\n")
    # All assets in a Git deployment are switched together. Remove superseded
    # files from the new deployment, keeping old deployments internally consistent.
    keep = {v["path"] for v in catalog["files"].values()}
    for file in dest.glob("*/*.json"):
        if str(file.relative_to(dest)) not in keep:
            file.unlink()


if __name__ == "__main__":
    main()
